import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioPlaybackService {
  AudioPlayer _player = AudioPlayer();
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

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<String>? _errorSub;

  AudioPlaybackService() {
    _attachListeners();
  }

  void _attachListeners() {
    _positionSub = _player.onPositionChanged.listen((pos) {
      _positionController.add(pos);
    });
    _durationSub = _player.onDurationChanged.listen((dur) {
      _durationController.add(dur);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        _completionController.add(null);
        _currentlyPlayingId = null;
        _playingIdController.add(null);
        _safeCall(() => _player.setPlaybackRate(1.0));
      } else if (_currentlyPlayingId != null &&
          (state == PlayerState.playing || state == PlayerState.paused)) {
        _playingIdController.add(_currentlyPlayingId);
      }
    });
    _errorSub = _player.onLog.listen((msg) {
      debugPrint('AudioPlayer log: $msg');
    });
  }

  void _detachListeners() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
  }

  /// Recreate the player to clear any stuck error state.
  Future<void> _resetPlayer() async {
    _detachListeners();
    try {
      await _player.dispose();
    } catch (_) {}
    _player = AudioPlayer();
    _attachListeners();
  }

  Future<void> play(String messageId, String pathOrUrl) async {
    if (_currentlyPlayingId == messageId) {
      final state = _player.state;
      if (state == PlayerState.playing) {
        await _safeCall(() => _player.pause());
        _playingIdController.add(messageId);
        return;
      }
      if (state == PlayerState.paused) {
        await _safeCall(() => _player.resume());
        _playingIdController.add(messageId);
        return;
      }
    }

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

    await _safeCall(() => _player.stop());
    _currentlyPlayingId = messageId;
    // Ensure UI starts each new track from the beginning and does not reuse
    // stale position from a previously played message.
    _positionController.add(Duration.zero);
    _playingIdController.add(messageId);

    try {
      if (isUrl) {
        await _player.play(UrlSource(pathOrUrl));
      } else {
        await _player.play(DeviceFileSource(pathOrUrl));
      }
    } catch (e) {
      debugPrint('AudioPlayback: play failed, resetting player: $e');
      _currentlyPlayingId = null;
      _playingIdController.add(null);
      await _resetPlayer();
    }
  }

  Future<void> stop() async {
    await _safeCall(() => _player.stop());
    _positionController.add(Duration.zero);
    _currentlyPlayingId = null;
    _playingIdController.add(null);
  }

  Future<void> seek(Duration position) async {
    await _safeCall(() => _player.seek(position));
  }

  Future<void> setPlaybackRate(double rate) async {
    await _safeCall(() => _player.setPlaybackRate(rate));
  }

  Future<Duration?> getDuration() async {
    try {
      return await _player.getDuration();
    } catch (_) {
      return null;
    }
  }

  PlayerState get state => _player.state;

  Future<void> _safeCall(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  void dispose() {
    _detachListeners();
    _player.dispose();
    _playingIdController.close();
    _positionController.close();
    _durationController.close();
    _completionController.close();
  }
}
