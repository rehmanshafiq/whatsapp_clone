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
    try { await _player.dispose(); } catch (_) {}
    _player = AudioPlayer();
    _attachListeners();
  }

  Future<void> play(String messageId, String filePath) async {
    if (_currentlyPlayingId == messageId) {
      final state = _player.state;
      if (state == PlayerState.playing) {
        await _safeCall(() => _player.pause());
        return;
      }
      if (state == PlayerState.paused) {
        await _safeCall(() => _player.resume());
        return;
      }
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint('AudioPlayback: file not found at $filePath');
      return;
    }
    if (file.lengthSync() == 0) {
      debugPrint('AudioPlayback: file is empty at $filePath');
      return;
    }

    await _safeCall(() => _player.stop());
    _currentlyPlayingId = messageId;
    _playingIdController.add(messageId);

    try {
      await _player.play(DeviceFileSource(filePath));
    } catch (e) {
      debugPrint('AudioPlayback: play failed, resetting player: $e');
      _currentlyPlayingId = null;
      _playingIdController.add(null);
      await _resetPlayer();
    }
  }

  Future<void> stop() async {
    await _safeCall(() => _player.stop());
    _currentlyPlayingId = null;
    _playingIdController.add(null);
  }

  Future<void> seek(Duration position) async {
    await _safeCall(() => _player.seek(position));
  }

  PlayerState get state => _player.state;

  Future<void> _safeCall(Future<void> Function() fn) async {
    try { await fn(); } catch (_) {}
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
