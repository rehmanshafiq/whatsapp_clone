import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;

class AudioPlaybackService {
  static const MethodChannel _justAudioChannel = MethodChannel(
    'com.ryanheise.just_audio.methods',
  );

  ja.AudioPlayer? _justPlayer;
  ap.AudioPlayer? _legacyPlayer;
  bool _useLegacyBackend = false;
  Future<void>? _backendInitFuture;
  String? _currentlyPlayingId;

  final _playingIdController = StreamController<String?>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completionController = StreamController<void>.broadcast();

  Stream<String?> get playingIdStream => _playingIdController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<void> get completionStream => _completionController.stream;

  String? get currentlyPlayingId => _currentlyPlayingId;
  bool get isPlaying {
    if (_useLegacyBackend) {
      return _legacyPlayer?.state == ap.PlayerState.playing;
    }
    return _justPlayer?.playing ?? false;
  }

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _justDurationSub;
  StreamSubscription<ja.PlayerState>? _justStateSub;
  StreamSubscription<Duration>? _legacyDurationSub;
  StreamSubscription<ap.PlayerState>? _legacyStateSub;
  StreamSubscription<String>? _legacyLogSub;

  AudioPlaybackService();

  Future<void> _ensureBackend() {
    final existing = _backendInitFuture;
    if (existing != null) return existing;
    final next = _initializeBackend();
    _backendInitFuture = next;
    return next;
  }

  Future<void> _initializeBackend() async {
    final justAudioAvailable = await _isJustAudioPluginAvailable();
    if (justAudioAvailable) {
      try {
        _justPlayer = ja.AudioPlayer();
        _useLegacyBackend = false;
        _attachJustAudioListeners();
        debugPrint('AudioPlayback: using just_audio backend');
        return;
      } catch (e) {
        debugPrint(
          'AudioPlayback: just_audio init failed, using audioplayers fallback: $e',
        );
      }
    }

    _legacyPlayer = ap.AudioPlayer();
    _useLegacyBackend = true;
    _attachLegacyAudioListeners();
    debugPrint('AudioPlayback: using audioplayers fallback backend');
  }

  Future<bool> _isJustAudioPluginAvailable() async {
    try {
      await _justAudioChannel.invokeMethod<void>('disposeAllPlayers');
      return true;
    } on MissingPluginException {
      debugPrint(
        'AudioPlayback: just_audio plugin unavailable, using audioplayers fallback.',
      );
      return false;
    } catch (_) {
      // Method channel exists but may return a platform error; plugin is present.
      return true;
    }
  }

  void _attachJustAudioListeners() {
    final player = _justPlayer;
    if (player == null) return;

    _positionSub = player.positionStream.listen((pos) {
      _positionController.add(pos);
    });

    _justDurationSub = player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _durationController.add(dur);
      }
    });

    _justStateSub = player.playerStateStream.listen(
      (state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _completionController.add(null);
          _currentlyPlayingId = null;
          _playingIdController.add(null);
          _safeCall(() => player.setSpeed(1.0));
          return;
        }

        if (_currentlyPlayingId != null &&
            state.processingState != ja.ProcessingState.idle) {
          _playingIdController.add(_currentlyPlayingId);
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('AudioPlayback: just_audio state error: $e');
      },
    );
  }

  void _attachLegacyAudioListeners() {
    final player = _legacyPlayer;
    if (player == null) return;

    _positionSub = player.onPositionChanged.listen((pos) {
      _positionController.add(pos);
    });

    _legacyDurationSub = player.onDurationChanged.listen((dur) {
      if (dur > Duration.zero) {
        _durationController.add(dur);
      }
    });

    _legacyStateSub = player.onPlayerStateChanged.listen((state) {
      if (state == ap.PlayerState.completed) {
        _completionController.add(null);
        _currentlyPlayingId = null;
        _playingIdController.add(null);
        _safeCall(() => player.setPlaybackRate(1.0));
      } else if (_currentlyPlayingId != null &&
          (state == ap.PlayerState.playing || state == ap.PlayerState.paused)) {
        _playingIdController.add(_currentlyPlayingId);
      }
    });

    _legacyLogSub = player.onLog.listen((msg) {
      debugPrint('AudioPlayback fallback log: $msg');
    });
  }

  void _detachListeners() {
    _positionSub?.cancel();
    _positionSub = null;

    _justDurationSub?.cancel();
    _justDurationSub = null;

    _justStateSub?.cancel();
    _justStateSub = null;

    _legacyDurationSub?.cancel();
    _legacyDurationSub = null;

    _legacyStateSub?.cancel();
    _legacyStateSub = null;

    _legacyLogSub?.cancel();
    _legacyLogSub = null;
  }

  Future<void> _switchToLegacyBackend() async {
    _detachListeners();

    final justPlayer = _justPlayer;
    _justPlayer = null;
    if (justPlayer != null) {
      try {
        await justPlayer.dispose();
      } catch (_) {}
    }

    _legacyPlayer ??= ap.AudioPlayer();
    _useLegacyBackend = true;
    _attachLegacyAudioListeners();
  }

  Future<void> _resetJustAudioPlayer() async {
    _detachListeners();
    final player = _justPlayer;
    _justPlayer = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _justPlayer = ja.AudioPlayer();
    _attachJustAudioListeners();
  }

  Future<void> _resetLegacyAudioPlayer() async {
    _detachListeners();
    final player = _legacyPlayer;
    _legacyPlayer = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _legacyPlayer = ap.AudioPlayer();
    _attachLegacyAudioListeners();
  }

  Future<void> play(
    String messageId,
    String pathOrUrl, {
    Map<String, String>? headers,
  }) async {
    await _ensureBackend();

    final isUrl = pathOrUrl.startsWith('http');
    if (!isUrl) {
      final file = File(pathOrUrl);
      if (!file.existsSync()) {
        debugPrint('AudioPlayback: file not found at $pathOrUrl');
        return;
      }
      if (file.lengthSync() == 0) {
        debugPrint('AudioPlayback: file is empty at $pathOrUrl');
        return;
      }
    }

    if (_useLegacyBackend) {
      await _playWithLegacy(
        messageId: messageId,
        pathOrUrl: pathOrUrl,
        isUrl: isUrl,
        headers: headers,
      );
      return;
    }

    await _playWithJustAudio(
      messageId: messageId,
      pathOrUrl: pathOrUrl,
      isUrl: isUrl,
      headers: headers,
    );
  }

  Future<void> _playWithJustAudio({
    required String messageId,
    required String pathOrUrl,
    required bool isUrl,
    Map<String, String>? headers,
  }) async {
    final player = _justPlayer;
    if (player == null) return;

    if (_currentlyPlayingId == messageId) {
      if (player.playing) {
        await _safeCall(() => player.pause());
        _playingIdController.add(messageId);
        return;
      }
      if (player.processingState == ja.ProcessingState.completed) {
        await _safeCall(() => player.seek(Duration.zero));
        _playingIdController.add(messageId);
        _startJustPlayback(player);
        return;
      }
      if (player.processingState == ja.ProcessingState.ready ||
          player.processingState == ja.ProcessingState.buffering) {
        _playingIdController.add(messageId);
        _startJustPlayback(player);
        return;
      }
    }

    if (_currentlyPlayingId != null && _currentlyPlayingId != messageId) {
      _currentlyPlayingId = null;
      _playingIdController.add(null);
    }

    await _safeCall(() => player.stop());
    _currentlyPlayingId = messageId;
    _positionController.add(Duration.zero);
    _playingIdController.add(messageId);

    try {
      if (isUrl) {
        await player.setUrl(pathOrUrl, headers: headers);
      } else {
        await player.setFilePath(pathOrUrl);
      }
      final duration = player.duration;
      if (duration != null && duration > Duration.zero) {
        _durationController.add(duration);
      }
      _startJustPlayback(player);
    } catch (e) {
      if (e is MissingPluginException) {
        debugPrint(
          'AudioPlayback: just_audio plugin missing at runtime. Switching fallback.',
        );
        await _switchToLegacyBackend();
        await _playWithLegacy(
          messageId: messageId,
          pathOrUrl: pathOrUrl,
          isUrl: isUrl,
          headers: headers,
        );
        return;
      }
      await _handleJustAudioPlaybackFailure(e);
    }
  }

  Future<void> _playWithLegacy({
    required String messageId,
    required String pathOrUrl,
    required bool isUrl,
    Map<String, String>? headers,
  }) async {
    final player = _legacyPlayer;
    if (player == null) return;

    if (_currentlyPlayingId == messageId) {
      final state = player.state;
      if (state == ap.PlayerState.playing) {
        await _safeCall(() => player.pause());
        _playingIdController.add(messageId);
        return;
      }
      if (state == ap.PlayerState.paused) {
        await _safeCall(() => player.resume());
        _playingIdController.add(messageId);
        return;
      }
    }

    if (_currentlyPlayingId != null && _currentlyPlayingId != messageId) {
      _currentlyPlayingId = null;
      _playingIdController.add(null);
    }

    await _safeCall(() => player.stop());
    _currentlyPlayingId = messageId;
    _positionController.add(Duration.zero);
    _playingIdController.add(messageId);

    try {
      if (isUrl) {
        await player.play(ap.UrlSource(pathOrUrl));
      } else {
        await player.play(ap.DeviceFileSource(pathOrUrl));
      }
    } catch (e) {
      await _handleLegacyPlaybackFailure(e);
    }
  }

  Future<void> stop() async {
    await _ensureBackend();
    _currentlyPlayingId = null;
    _playingIdController.add(null);
    _positionController.add(Duration.zero);

    if (_useLegacyBackend) {
      final player = _legacyPlayer;
      if (player != null) {
        await _safeCall(() => player.stop());
      }
      return;
    }

    final player = _justPlayer;
    if (player != null) {
      await _safeCall(() => player.stop());
    }
  }

  Future<void> seek(Duration position) async {
    await _ensureBackend();

    if (_useLegacyBackend) {
      final player = _legacyPlayer;
      if (player != null) {
        await _safeCall(() => player.seek(position));
      }
      return;
    }

    final player = _justPlayer;
    if (player != null) {
      await _safeCall(() => player.seek(position));
    }
  }

  Future<void> setPlaybackRate(double rate) async {
    await _ensureBackend();

    if (_useLegacyBackend) {
      final player = _legacyPlayer;
      if (player != null) {
        await _safeCall(() => player.setPlaybackRate(rate));
      }
      return;
    }

    final player = _justPlayer;
    if (player != null) {
      await _safeCall(() => player.setSpeed(rate));
    }
  }

  Future<Duration?> getDuration() async {
    await _ensureBackend();

    if (_useLegacyBackend) {
      final player = _legacyPlayer;
      if (player == null) return null;
      try {
        return await player.getDuration();
      } catch (_) {
        return null;
      }
    }

    return _justPlayer?.duration;
  }

  Future<void> _safeCall(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  void _startJustPlayback(ja.AudioPlayer player) {
    unawaited(
      player.play().catchError((Object e, StackTrace st) {
        debugPrint('AudioPlayback: just_audio play() future error: $e');
      }),
    );
  }

  Future<void> _handleJustAudioPlaybackFailure(Object error) async {
    debugPrint('AudioPlayback: just_audio play failed, resetting player: $error');
    _currentlyPlayingId = null;
    _playingIdController.add(null);

    if (_useLegacyBackend) return;
    try {
      await _resetJustAudioPlayer();
    } catch (_) {}
  }

  Future<void> _handleLegacyPlaybackFailure(Object error) async {
    debugPrint('AudioPlayback: audioplayers fallback play failed: $error');
    _currentlyPlayingId = null;
    _playingIdController.add(null);

    if (!_useLegacyBackend) return;
    try {
      await _resetLegacyAudioPlayer();
    } catch (_) {}
  }

  void dispose() {
    _detachListeners();

    final justPlayer = _justPlayer;
    if (justPlayer != null) {
      unawaited(justPlayer.dispose());
      _justPlayer = null;
    }

    final legacyPlayer = _legacyPlayer;
    if (legacyPlayer != null) {
      unawaited(legacyPlayer.dispose());
      _legacyPlayer = null;
    }

    _playingIdController.close();
    _positionController.close();
    _durationController.close();
    _completionController.close();
  }
}
