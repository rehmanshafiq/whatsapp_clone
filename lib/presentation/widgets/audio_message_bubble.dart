import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/di/service_locator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/audio_playback_service.dart';
import '../../data/models/message.dart';
import 'message_status_icon.dart';

class AudioMessageBubble extends StatefulWidget {
  final Message message;

  const AudioMessageBubble({super.key, required this.message});

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final AudioPlaybackService _playbackService = getIt<AudioPlaybackService>();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  bool _isPreparingRemoteAudio = false;
  String? _cachedRemoteFilePath;

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
    _totalDuration = widget.message.audioDuration ?? Duration.zero;

    _playingIdSub = _playbackService.playingIdStream.listen((id) {
      if (!mounted) return;
      final playing =
          id == widget.message.id &&
          _playbackService.state == PlayerState.playing;
      if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
      if (id != widget.message.id) {
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
    });

    _durationSub = _playbackService.durationStream.listen((dur) {
      if (!mounted || !_isThisMessage) return;
      if (dur > Duration.zero) {
        setState(() => _totalDuration = dur);
      }
    });

    _completionSub = _playbackService.completionStream.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _playbackSpeed = 1.0;
      });
    });
  }

  @override
  void dispose() {
    _playingIdSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _completionSub.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    unawaited(_togglePlaybackInternal());
  }

  Future<void> _togglePlaybackInternal() async {
    // Prefer explicit audioPath (local recording). Fall back to mediaUrl
    // for audio/voice messages coming from the server that only provide
    // attachment_url.
    final path = widget.message.audioPath ?? widget.message.mediaUrl;
    if (path == null) return;
    // Only treat as server-relative if it looks like backend path (/uploads/...).
    // Do NOT prepend baseUrl for local absolute paths (e.g. /data/user/0/... on Android).
    final resolvedPath = path.startsWith('/uploads/')
        ? '${AppConstants.apiBaseUrl}$path'
        : path;
    final playablePath = await _resolvePlayablePath(resolvedPath);
    if (playablePath == null) return;
    await _playbackService.play(widget.message.id, playablePath);
    if (_totalDuration <= Duration.zero) {
      unawaited(_syncDurationFromPlayer());
    }
  }

  Future<String?> _resolvePlayablePath(String resolvedPath) async {
    if (!resolvedPath.startsWith('http')) {
      return File(resolvedPath).existsSync() ? resolvedPath : null;
    }

    final cachedPath = _cachedRemoteFilePath;
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }
    if (_isPreparingRemoteAudio) {
      return resolvedPath;
    }

    _isPreparingRemoteAudio = true;
    try {
      final uri = Uri.tryParse(resolvedPath);
      if (uri == null) return resolvedPath;

      final tempDir = await getTemporaryDirectory();
      final localPath =
          '${tempDir.path}/audio_${widget.message.id}${_inferAudioExtension(uri.path)}';
      final localFile = File(localPath);

      if (!localFile.existsSync() || localFile.lengthSync() == 0) {
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
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
      // Fall back to direct URL playback when local caching fails.
    } finally {
      _isPreparingRemoteAudio = false;
    }

    return resolvedPath;
  }

  String _inferAudioExtension(String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.m4a')) return '.m4a';
    if (lower.endsWith('.aac')) return '.aac';
    if (lower.endsWith('.mp3')) return '.mp3';
    if (lower.endsWith('.wav')) return '.wav';
    if (lower.endsWith('.ogg') || lower.endsWith('.oga')) return '.ogg';
    if (lower.endsWith('.opus')) return '.opus';
    return '.m4a';
  }

  void _cycleSpeed() {
    final currentIndex = _speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final newSpeed = _speeds[nextIndex];
    setState(() => _playbackSpeed = newSpeed);
    if (_isThisMessage) {
      _playbackService.setPlaybackRate(newSpeed);
    }
  }

  void _onDragStart() {
    if (!_isThisMessage) return;
    _isSeeking = true;
  }

  void _onDragUpdate(double fraction) {
    if (!_isThisMessage || _totalDuration.inMilliseconds <= 0) return;
    final clamped = fraction.clamp(0.0, 1.0);
    setState(() {
      _position = Duration(
        milliseconds: (clamped * _totalDuration.inMilliseconds).round(),
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isThisMessage) return;
    _isSeeking = false;
    _playbackService.seek(_position);
  }

  void _onDragCancel() {
    if (!_isThisMessage) return;
    _isSeeking = false;
  }

  void _onTapSeek(double fraction) {
    if (!_isThisMessage || _totalDuration.inMilliseconds <= 0) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final seekPos = Duration(
      milliseconds: (clamped * _totalDuration.inMilliseconds).round(),
    );
    setState(() => _position = seekPos);
    _playbackService.seek(seekPos);
  }

  Future<void> _syncDurationFromPlayer() async {
    // Remote audio can report duration a bit later than play() call.
    // Probe briefly so waveform seeking activates as soon as metadata arrives.
    for (var i = 0; i < 6; i++) {
      if (!mounted || !_isThisMessage) return;
      final duration = await _playbackService.getDuration();
      if (!mounted || !_isThisMessage) return;
      if (duration != null && duration > Duration.zero) {
        if (_totalDuration != duration) {
          setState(() => _totalDuration = duration);
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final period = widget.message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = widget.message.timestamp.hour % 12;
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:${widget.message.timestamp.minute.toString().padLeft(2, '0')} $period';

    final displayDuration = _isPlaying || _isThisMessage
        ? _position
        : Duration.zero;
    final progress = _totalDuration.inMilliseconds > 0
        ? (displayDuration.inMilliseconds / _totalDuration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
          color: isOutgoing
              ? AppColors.outgoingBubble
              : AppColors.incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
            bottomRight: Radius.circular(isOutgoing ? 0 : 12),
          ),
        ),
        child: Row(
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
                            _isPlaying || _isThisMessage
                                ? _formatDuration(_position)
                                : _formatDuration(_totalDuration),
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.8,
                              ),
                              fontSize: 11,
                            ),
                          ),
                          if (_isThisMessage) ...[
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
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 11,
                            ),
                          ),
                          if (isOutgoing) ...[
                            const SizedBox(width: 4),
                            MessageStatusIcon(
                              status: widget.message.status,
                              size: 14,
                            ),
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
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;
  final bool isOutgoing;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onTap,
    required this.isOutgoing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final VoidCallback onTap;
  final bool isOutgoing;

  const _SpeedButton({
    required this.speed,
    required this.onTap,
    required this.isOutgoing,
  });

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
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SeekableWaveformBar extends StatelessWidget {
  final double progress;
  final bool isOutgoing;
  final ValueChanged<double> onTapSeek;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onDragCancel;

  const _SeekableWaveformBar({
    required this.progress,
    required this.isOutgoing,
    required this.onTapSeek,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const barWidth = 2.5;
        const barSpacing = 1.5;
        final barCount = (constraints.maxWidth / (barWidth + barSpacing))
            .floor()
            .clamp(1, 40);
        final totalBarsWidth = barCount * (barWidth + barSpacing) - barSpacing;

        double fractionFromX(double dx) =>
            (dx / totalBarsWidth).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            onTapSeek(fractionFromX(details.localPosition.dx));
          },
          onHorizontalDragStart: (details) {
            onDragStart();
            onDragUpdate(fractionFromX(details.localPosition.dx));
          },
          onHorizontalDragUpdate: (details) {
            onDragUpdate(fractionFromX(details.localPosition.dx));
          },
          onHorizontalDragEnd: onDragEnd,
          onHorizontalDragCancel: onDragCancel,
          child: CustomPaint(
            size: Size(constraints.maxWidth, 28),
            painter: _WaveformPainter(
              progress: progress,
              activeColor: isOutgoing
                  ? AppColors.textPrimary
                  : AppColors.accent,
              inactiveColor: AppColors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
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

  static const _barHeights = [
    0.3,
    0.5,
    0.7,
    0.4,
    0.9,
    0.6,
    0.8,
    0.3,
    0.7,
    0.5,
    0.6,
    0.9,
    0.4,
    0.8,
    0.3,
    0.7,
    0.5,
    0.9,
    0.6,
    0.4,
    0.8,
    0.3,
    0.7,
    0.5,
    0.9,
    0.4,
    0.6,
    0.8,
    0.3,
    0.7,
    0.5,
    0.4,
    0.8,
    0.6,
    0.9,
    0.3,
    0.7,
    0.5,
    0.4,
    0.8,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.5;
    const barSpacing = 1.5;
    final barCount = (size.width / (barWidth + barSpacing)).floor().clamp(
      1,
      _barHeights.length,
    );

    // The actual width the waveform bars occupy (last bar has no trailing gap)
    final totalBarsWidth = barCount * (barWidth + barSpacing) - barSpacing;
    // Map the seek dot to the waveform width, not full canvas width
    final progressX = totalBarsWidth * progress;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + barSpacing);
      final barCenter = x + barWidth / 2;
      final heightFactor = _barHeights[i % _barHeights.length];
      final barHeight = size.height * heightFactor;
      final y = (size.height - barHeight) / 2;

      final paint = Paint()
        ..color = barCenter <= progressX ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }

    if (progress > 0 && progress < 1) {
      canvas.drawCircle(
        Offset(progressX.clamp(0.0, totalBarsWidth), size.height / 2),
        4.0,
        Paint()..color = activeColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
