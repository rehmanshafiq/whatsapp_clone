import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/di/service_locator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/audio_playback_service.dart';
import '../../data/models/message.dart';
import 'message_action_sheet.dart';
import 'message_status_icon.dart';
import 'forwarded_label.dart';

class AudioMessageBubble extends StatefulWidget {
  final Message message;

  /// Auth headers (Bearer + x-api-key) for downloading protected audio files.
  /// Pass `context.read<ChatCubit>().authHeadersForMedia` from the parent.
  final Map<String, String>? authHeaders;

  const AudioMessageBubble({
    super.key,
    required this.message,
    this.authHeaders,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble>
    with SingleTickerProviderStateMixin {
  final AudioPlaybackService _playbackService = getIt<AudioPlaybackService>();
  bool _isPlaying = false;

  /// True as soon as this message is selected in the playback service —
  /// before playback actually starts (remote audio may still be buffering).
  /// Enables waveform seeking immediately on tap.
  bool _isActive = false;

  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  bool _isSyncingDuration = false;
  bool _isPreparingRemoteAudio = false;
  String? _cachedRemoteFilePath;

  static const double _swipeTrigger = 64.0;
  static const double _swipeMax = 100.0;
  late final AnimationController _swipeController;
  double _swipeDragExtent = 0;
  bool _swipeHapticFired = false;

  late final StreamSubscription<String?> _playingIdSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<void> _completionSub;

  bool get _isThisMessage =>
      _playbackService.currentlyPlayingId == widget.message.id;

  static const _speeds = [1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: _swipeMax,
      value: 0,
    );
    _totalDuration = widget.message.audioDuration ?? Duration.zero;

    _playingIdSub = _playbackService.playingIdStream.listen((id) {
      if (!mounted) return;
      final isThis = id == widget.message.id;
      final playing = isThis && _playbackService.isPlaying;

      // Rebuild whenever either flag changes. _isActive flips true the moment
      // the user taps play — before playback actually starts — so seek
      // gestures attach immediately, even for remote/buffering audio.
      if (isThis != _isActive || playing != _isPlaying) {
        setState(() {
          _isActive = isThis;
          _isPlaying = playing;
        });
      }

      if (!isThis) {
        if (_position != Duration.zero || _playbackSpeed != 1.0) {
          setState(() {
            _position = Duration.zero;
            _playbackSpeed = 1.0;
          });
        }
      } else if (_totalDuration <= Duration.zero) {
        unawaited(_syncDurationFromPlayer());
      }
    });

    _positionSub = _playbackService.positionStream.listen((pos) {
      if (!mounted || !_isThisMessage || _isSeeking) return;
      setState(() => _position = pos);
      if (_totalDuration <= Duration.zero) {
        unawaited(_syncDurationFromPlayer());
      }
    });

    _durationSub = _playbackService.durationStream.listen((dur) {
      if (!mounted || !_isThisMessage) return;
      if (dur > Duration.zero) setState(() => _totalDuration = dur);
    });

    _completionSub = _playbackService.completionStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _isActive = false;
        _position = Duration.zero;
        _playbackSpeed = 1.0;
      });
    });
  }

  @override
  void dispose() {
    _swipeController.dispose();
    _playingIdSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _completionSub.cancel();
    super.dispose();
  }

  void _togglePlayback() => unawaited(_togglePlaybackInternal());

  Future<void> _togglePlaybackInternal() async {
    final path = widget.message.audioPath ?? widget.message.mediaUrl;
    if (path == null) return;

    // Resolve server-relative paths to full URLs.
    final resolvedPath = path.startsWith('/uploads/')
        ? '${AppConstants.apiBaseUrl}$path'
        : path;

    final playablePath = await _resolvePlayablePath(resolvedPath);
    if (playablePath == null) return;

    final streamHeaders =
        playablePath.startsWith('http') ? widget.authHeaders : null;
    await _playbackService.play(
      widget.message.id,
      playablePath,
      headers: streamHeaders,
    );
    if (_totalDuration <= Duration.zero) {
      unawaited(_syncDurationFromPlayer());
    }
  }

  /// Downloads remote audio to a correctly-named temp file using auth headers.
  /// Falls back to direct URL streaming if download fails.
  Future<String?> _resolvePlayablePath(String resolvedPath) async {
    // Local file — just verify it exists.
    if (!resolvedPath.startsWith('http')) {
      return File(resolvedPath).existsSync() ? resolvedPath : null;
    }

    // Return cached local copy if still valid.
    final cachedPath = _cachedRemoteFilePath;
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }

    // Another download is already running — stream directly in the meantime.
    if (_isPreparingRemoteAudio) return resolvedPath;

    _isPreparingRemoteAudio = true;
    try {
      final uri = Uri.tryParse(resolvedPath);
      if (uri == null) return resolvedPath;

      // ── Correct file extension ────────────────────────────────────────────
      // Must derive extension from the *source URL* so .webm files are saved
      // as .webm — not silently renamed to .m4a — so Android decoders can
      // reliably parse and seek voice notes produced by web clients.
      final ext = _inferAudioExtension(uri.path);

      final tempDir = await getTemporaryDirectory();
      final localPath = '${tempDir.path}/audio_${widget.message.id}$ext';
      final localFile = File(localPath);

      if (!localFile.existsSync() || localFile.lengthSync() == 0) {
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);

          // ── Auth headers ──────────────────────────────────────────────────
          // /uploads/ files are protected. Without Bearer + x-api-key the
          // server returns 401, the download fails silently, and the player
          // either can't open the file or tries to stream without auth.
          widget.authHeaders?.forEach((key, value) {
            request.headers.set(key, value);
          });

          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            // Auth failed or file not found — fall back to URL streaming.
            return resolvedPath;
          }

          final sink = localFile.openWrite();
          await for (final chunk in response) {
            sink.add(chunk);
          }
          await sink.close();
        } finally {
          client.close(force: true);
        }
      }

      if (localFile.existsSync() && localFile.lengthSync() > 0) {
        _cachedRemoteFilePath = localFile.path;
        return localFile.path;
      }
    } catch (_) {
      // Any error → fall back to direct URL streaming.
    } finally {
      _isPreparingRemoteAudio = false;
    }

    return resolvedPath;
  }

  /// Returns the correct extension for [sourcePath].
  /// Handles all formats the backend may produce, including .webm (Chrome/Opus).
  String _inferAudioExtension(String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.m4a'))  return '.m4a';
    if (lower.endsWith('.aac'))  return '.aac';
    if (lower.endsWith('.mp3'))  return '.mp3';
    if (lower.endsWith('.wav'))  return '.wav';
    if (lower.endsWith('.webm')) return '.webm'; // ← was missing
    if (lower.endsWith('.ogg') || lower.endsWith('.oga')) return '.ogg';
    if (lower.endsWith('.opus')) return '.opus';
    return '.m4a';
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_playbackSpeed);
    final newSpeed = _speeds[(idx + 1) % _speeds.length];
    setState(() => _playbackSpeed = newSpeed);
    if (_isThisMessage) _playbackService.setPlaybackRate(newSpeed);
  }

  void _onDragStart() { if (_isActive) _isSeeking = true; }

  void _onDragUpdate(double fraction) {
    if (!_isActive || _totalDuration.inMilliseconds <= 0) return;
    setState(() {
      _position = Duration(
        milliseconds:
        (fraction.clamp(0.0, 1.0) * _totalDuration.inMilliseconds)
            .round(),
      );
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_isActive) return;
    _isSeeking = false;
    _playbackService.seek(_position);
  }

  void _onDragCancel() { if (_isActive) _isSeeking = false; }

  void _onSwipeDragUpdate(DragUpdateDetails d) {
    _swipeDragExtent =
        (_swipeDragExtent + d.delta.dx).clamp(0.0, double.infinity);
    _swipeController.value = math.min(_swipeDragExtent, _swipeMax);
    if (!_swipeHapticFired && _swipeDragExtent >= _swipeTrigger) {
      _swipeHapticFired = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onSwipeDragEnd(DragEndDetails _) => _finishSwipe();
  void _onSwipeDragCancel() => _finishSwipe();

  void _finishSwipe() {
    final triggered = _swipeDragExtent >= _swipeTrigger;
    _swipeDragExtent = 0;
    _swipeHapticFired = false;

    if (_swipeController.value == 0) {
      if (triggered && mounted) MessageActionSheet.show(context, widget.message);
      return;
    }
    _swipeController
        .animateWith(SpringSimulation(
      SpringDescription(mass: 1, stiffness: 300, damping: 22),
      _swipeController.value, 0, 0,
    ))
        .then((_) {
      if (triggered && mounted) MessageActionSheet.show(context, widget.message);
    });
  }

  void _onTapSeek(double fraction) {
    if (!_isActive || _totalDuration.inMilliseconds <= 0) return;
    final pos = Duration(
      milliseconds:
      (fraction.clamp(0.0, 1.0) * _totalDuration.inMilliseconds).round(),
    );
    setState(() => _position = pos);
    _playbackService.seek(pos);
  }

  Future<void> _syncDurationFromPlayer() async {
    if (_isSyncingDuration) return;
    _isSyncingDuration = true;
    try {
      // Remote audio can report duration late (after buffering/index parsing).
      for (var i = 0; i < 30; i++) {
        if (!mounted || !_isThisMessage) return;
        final dur = await _playbackService.getDuration();
        if (!mounted || !_isThisMessage) return;
        if (dur != null && dur > Duration.zero) {
          if (_totalDuration != dur) setState(() => _totalDuration = dur);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      _isSyncingDuration = false;
    }
  }

  String _formatDuration(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
          '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final hourRaw = widget.message.timestamp.hour % 12;
    final period = widget.message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:'
        '${widget.message.timestamp.minute.toString().padLeft(2, '0')} $period';

    final displayDuration = _isActive ? _position : Duration.zero;
    final progress = _totalDuration.inMilliseconds > 0
        ? (displayDuration.inMilliseconds / _totalDuration.inMilliseconds)
        .clamp(0.0, 1.0)
        : 0.0;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
        minWidth: 220,
      ),
      margin: EdgeInsets.only(
        left: isOutgoing ? 64 : 8,
        right: isOutgoing ? 8 : 64,
        top: 2,
        bottom: 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isOutgoing ? AppColors.outgoingBubble : AppColors.incomingBubble,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
          bottomRight: Radius.circular(isOutgoing ? 0 : 12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message.isForwarded) const ForwardedLabel(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayPauseButton(
                isPlaying: _isPlaying,
                onTap: _togglePlayback,
                isOutgoing: isOutgoing,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SeekableWaveformBar(
                      progress: progress,
                      isOutgoing: isOutgoing,
                      seekEnabled: _isActive,
                      onTapSeek: _onTapSeek,
                      onDragStart: _onDragStart,
                      onDragUpdate: _onDragUpdate,
                      onDragEnd: _onDragEnd,
                      onDragCancel: _onDragCancel,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isActive
                                  ? _formatDuration(_position)
                                  : _formatDuration(_totalDuration),
                              style: TextStyle(
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                            if (_isActive) ...[
                              const SizedBox(width: 6),
                              _SpeedButton(
                                speed: _playbackSpeed,
                                onTap: _cycleSpeed,
                                isOutgoing: isOutgoing,
                              ),
                            ],
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                            if (isOutgoing) ...[
                              const SizedBox(width: 4),
                              MessageStatusIcon(
                                  status: widget.message.status, size: 14),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return GestureDetector(
      // While this track is active, pass horizontal drags to the waveform.
      onHorizontalDragUpdate: _isActive ? null : _onSwipeDragUpdate,
      onHorizontalDragEnd: _isActive ? null : _onSwipeDragEnd,
      onHorizontalDragCancel: _isActive ? null : _onSwipeDragCancel,
      child: AnimatedBuilder(
        animation: _swipeController,
        builder: (context, child) {
          final dx = _swipeController.value;
          final p = (dx / _swipeTrigger).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: isOutgoing ? null : 4,
                right: isOutgoing ? 4 : null,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: p,
                    child: Transform.scale(
                      scale: 0.4 + p * 0.6,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accent
                              .withValues(alpha: 0.18 + p * 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.reply,
                            size: 18,
                            color: AppColors.accent
                                .withValues(alpha: 0.5 + p * 0.5)),
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(offset: Offset(dx, 0), child: child),
            ],
          );
        },
        child: Align(
          alignment:
          isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: bubble,
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final bool isOutgoing;
  const _PlayPauseButton(
      {required this.isPlaying,
        required this.onTap,
        required this.isOutgoing});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isOutgoing
            ? AppColors.accent.withValues(alpha: 0.3)
            : AppColors.divider,
        shape: BoxShape.circle,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          key: ValueKey(isPlaying),
          color: AppColors.textPrimary,
          size: 24,
        ),
      ),
    ),
  );
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;
  final bool isOutgoing;
  const _SpeedButton(
      {required this.speed, required this.onTap, required this.isOutgoing});

  @override
  Widget build(BuildContext context) {
    final label = speed == 1.5 ? '1.5x' : '${speed.toInt()}x';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: isOutgoing
              ? AppColors.accent.withValues(alpha: 0.25)
              : AppColors.divider.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _SeekableWaveformBar extends StatelessWidget {
  final double progress;
  final bool isOutgoing;
  final bool seekEnabled;
  final ValueChanged<double> onTapSeek;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onDragCancel;

  const _SeekableWaveformBar({
    required this.progress,
    required this.isOutgoing,
    required this.seekEnabled,
    required this.onTapSeek,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const bw = 2.5, bs = 1.5;
      final barCount =
      (constraints.maxWidth / (bw + bs)).floor().clamp(1, 40);
      final totalW = barCount * (bw + bs) - bs;
      double frac(double dx) => (dx / totalW).clamp(0.0, 1.0);

      final paint = CustomPaint(
        size: Size(constraints.maxWidth, 28),
        painter: _WaveformPainter(
          progress: progress,
          activeColor: isOutgoing ? AppColors.textPrimary : AppColors.accent,
          inactiveColor: AppColors.textSecondary.withValues(alpha: 0.3),
        ),
      );

      if (!seekEnabled) return paint;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => onTapSeek(frac(d.localPosition.dx)),
        onHorizontalDragStart: (d) {
          onDragStart();
          onDragUpdate(frac(d.localPosition.dx));
        },
        onHorizontalDragUpdate: (d) => onDragUpdate(frac(d.localPosition.dx)),
        onHorizontalDragEnd: onDragEnd,
        onHorizontalDragCancel: onDragCancel,
        child: paint,
      );
    });
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  static const _h = [
    0.3, 0.5, 0.7, 0.4, 0.9, 0.6, 0.8, 0.3, 0.7, 0.5,
    0.6, 0.9, 0.4, 0.8, 0.3, 0.7, 0.5, 0.9, 0.6, 0.4,
    0.8, 0.3, 0.7, 0.5, 0.9, 0.4, 0.6, 0.8, 0.3, 0.7,
    0.5, 0.4, 0.8, 0.6, 0.9, 0.3, 0.7, 0.5, 0.4, 0.8,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const bw = 2.5, bs = 1.5;
    final barCount =
    (size.width / (bw + bs)).floor().clamp(1, _h.length);
    final totalW = barCount * (bw + bs) - bs;
    final px = totalW * progress;

    for (int i = 0; i < barCount; i++) {
      final x = i * (bw + bs);
      final bh = size.height * _h[i % _h.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - bh) / 2, bw, bh),
          const Radius.circular(1.5),
        ),
        Paint()
          ..color = (x + bw / 2) <= px ? activeColor : inactiveColor
          ..style = PaintingStyle.fill,
      );
    }

    if (progress > 0 && progress < 1) {
      canvas.drawCircle(
        Offset(px.clamp(0.0, totalW), size.height / 2),
        4.0,
        Paint()..color = activeColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress;
}