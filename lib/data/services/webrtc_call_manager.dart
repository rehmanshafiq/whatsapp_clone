import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/constants/app_constants.dart';
import '../../core/root_scaffold_messenger.dart';
import '../repository/chat_repository.dart';

enum CallSessionPhase { idle, ringingOut, ringingIn, connecting, connected }

enum _CallRole { caller, callee }

/// WebRTC + signaling for 1:1 voice/video. Deferred SDP: offer only after
/// [call_answered] for the caller; callee pre-warms [getUserMedia] + PC while ringing.
class WebRtcCallManager extends ChangeNotifier {
  WebRtcCallManager({required ChatRepository chatRepository})
    : _repo = chatRepository;

  final ChatRepository _repo;

  CallSessionPhase _phase = CallSessionPhase.idle;
  _CallRole _role = _CallRole.caller;

  String? _callId;
  String? _peerUserId;
  String _peerDisplayName = '';
  String? _peerAvatarUrl;
  bool _isVideo = false;
  bool _micEnabled = true;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Timer? _ringTimeout;
  Timer? _durationTicker;
  DateTime? _connectedAt;

  final List<RTCIceCandidate> _remoteIceBuffer = <RTCIceCandidate>[];

  /// Cached `ice_servers` from [GET /api/v1/chat/turn-credentials] with server [ttl].
  List<Map<String, dynamic>>? _cachedIceServers;
  DateTime? _credentialsExpireAt;
  String? _credentialsProvider;
  int? _cachedTtlSeconds;

  CallSessionPhase get phase => _phase;
  String get peerDisplayName => _peerDisplayName;
  String? get peerAvatarUrl => _peerAvatarUrl;
  bool get isVideo => _isVideo;
  bool get isMicEnabled => _micEnabled;
  bool get isCaller => _role == _CallRole.caller;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  Duration get connectedDuration {
    final start = _connectedAt;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  bool get hasActiveCall => _phase != CallSessionPhase.idle;

  /// Clears Metered/OpenRelay ICE cache (e.g. after logout or token change).
  void clearTurnCredentialsCache() {
    _cachedIceServers = null;
    _credentialsExpireAt = null;
    _credentialsProvider = null;
    _cachedTtlSeconds = null;
  }

  /// Optional [call_id] from server before [call_answered] (e.g. call_ringing).
  void noteOutgoingCallId(String callId) {
    if (_role != _CallRole.caller || callId.isEmpty) return;
    _callId ??= callId;
  }

  Future<void> startOutgoingCall({
    required String peerUserId,
    required String peerDisplayName,
    String? peerAvatarUrl,
    required bool isVideo,
    String? conversationId,
  }) async {
    if (hasActiveCall) return;

    _resetState();
    _role = _CallRole.caller;
    _peerUserId = peerUserId;
    _peerDisplayName = peerDisplayName;
    _peerAvatarUrl = _resolveAvatarUrl(peerAvatarUrl);
    _isVideo = isVideo;
    _phase = CallSessionPhase.ringingOut;
    notifyListeners();

    try {
      await _repo.ensureRealtimeSocketConnected();
      final servers = await _loadIceServers();
      await _openLocalMedia();
      await _createPeerConnection(servers);
      final sent = await _repo.sendCallInitiate(
        peerUserId: peerUserId,
        callType: isVideo ? 'video' : 'voice',
        conversationId: conversationId,
      );
      if (!sent) {
        _toast('No connection. Open Chats to reconnect, then try again.');
        await _cleanup();
        return;
      }
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] startOutgoingCall failed: $e\n$st');
      _toast('Could not start call');
      await _cleanup();
    }
  }

  Future<void> onIncomingCall(Map<String, dynamic> data) async {
    if (hasActiveCall) {
      final busyId = _string(data['call_id']);
      if (busyId != null) {
        _repo.sendCallReject(callId: busyId, reason: 'busy');
      }
      return;
    }

    final callId = _string(data['call_id']);
    final callerId = _string(data['caller_id']);
    if (callId == null || callerId == null) return;

    _resetState();
    _role = _CallRole.callee;
    _callId = callId;
    _peerUserId = callerId;
    _peerDisplayName =
        _string(data['caller_display_name']) ?? 'Unknown';
    _peerAvatarUrl = _resolveAvatarUrl(_string(data['caller_avatar_url']));
    _isVideo = _string(data['call_type']) == 'video';
    _phase = CallSessionPhase.ringingIn;
    notifyListeners();

    _armRingTimeout();

    try {
      final servers = await _loadIceServers();
      await _openLocalMedia();
      await _createPeerConnection(servers);
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] incoming prep failed: $e\n$st');
      rejectIncoming(reason: 'rejected');
    }
  }

  void acceptIncoming() {
    if (_phase != CallSessionPhase.ringingIn || _callId == null) return;
    _ringTimeout?.cancel();
    _repo.sendCallAnswer(callId: _callId!);
    _phase = CallSessionPhase.connecting;
    notifyListeners();
  }

  void rejectIncoming({String reason = 'rejected'}) {
    if (_phase != CallSessionPhase.ringingIn) {
      unawaited(_cleanup());
      return;
    }
    _ringTimeout?.cancel();
    if (_callId != null) {
      _repo.sendCallReject(callId: _callId!, reason: reason);
    }
    unawaited(_cleanup());
  }

  Future<void> onCallAnswered(Map<String, dynamic> data) async {
    if (_role != _CallRole.caller) return;
    final id = _string(data['call_id']);
    if (id == null) return;
    _callId = id;

    if (_pc == null) {
      debugPrint('[WebRtcCallManager] call_answered but no peer connection');
      return;
    }

    try {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      if (_peerUserId != null) {
        _repo.sendWebRtcOffer(
          peerUserId: _peerUserId!,
          sdp: offer.sdp ?? '',
        );
      }
      _phase = CallSessionPhase.connecting;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] offer failed: $e\n$st');
      _toast('Could not connect');
      await hangUp();
    }
  }

  Future<void> onWebRtcOffer(Map<String, dynamic> data) async {
    if (_role != _CallRole.callee) return;
    final fromPeer = _string(data['peer_user_id']);
    if (fromPeer != null &&
        _peerUserId != null &&
        fromPeer != _peerUserId) {
      debugPrint('[WebRtcCallManager] Ignoring webrtc_offer from $fromPeer');
      return;
    }
    final sdp = _string(data['sdp']);
    if (sdp == null || _pc == null) return;
    try {
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      await _drainRemoteIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      if (_peerUserId != null) {
        _repo.sendWebRtcAnswer(
          peerUserId: _peerUserId!,
          sdp: answer.sdp ?? '',
        );
      }
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] answer failed: $e\n$st');
      _toast('Could not connect');
      await hangUp();
    }
  }

  Future<void> onWebRtcAnswer(Map<String, dynamic> data) async {
    if (_role != _CallRole.caller) return;
    final fromPeer = _string(data['peer_user_id']);
    if (fromPeer != null &&
        _peerUserId != null &&
        fromPeer != _peerUserId) {
      debugPrint('[WebRtcCallManager] Ignoring webrtc_answer from $fromPeer');
      return;
    }
    final sdp = _string(data['sdp']);
    if (sdp == null || _pc == null) return;
    try {
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      await _drainRemoteIce();
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] setRemote answer failed: $e\n$st');
      _toast('Could not connect');
      await hangUp();
    }
  }

  Future<void> onRemoteIceCandidate(Map<String, dynamic> data) async {
    // Relay may set peer_user_id to the other party or to the local user (target).
    final peer = _string(data['peer_user_id']);
    final myId = _repo.getCurrentUserId();
    final partnerId = _peerUserId;
    if (peer != null && partnerId != null) {
      final forThisCall =
          peer == partnerId || (myId != null && peer == myId);
      if (!forThisCall) {
        return;
      }
    }
    final raw = data['candidate'];
    if (raw is! Map) return;
    final cand = _mapToIceCandidate(Map<String, dynamic>.from(raw));
    if (cand == null) return;

    if (_pc == null) {
      _remoteIceBuffer.add(cand);
      return;
    }
    final remoteSet = await _pc!.getRemoteDescription() != null;
    if (!remoteSet) {
      _remoteIceBuffer.add(cand);
      return;
    }
    try {
      await _pc!.addCandidate(cand);
    } catch (e) {
      debugPrint('[WebRtcCallManager] addCandidate failed: $e');
    }
  }

  void onCallRejected(Map<String, dynamic> data) {
    if (_phase == CallSessionPhase.idle) return;
    final id = _string(data['call_id']);
    if (id != null && _callId != null && id != _callId) return;
    final reason = _string(data['reason']) ?? 'rejected';
    _toast(_rejectMessage(reason));
    unawaited(_cleanup());
  }

  void onCallEnded(Map<String, dynamic> data) {
    if (_phase == CallSessionPhase.idle) return;
    final id = _string(data['call_id']);
    if (id != null && _callId != null && id != _callId) return;
    final reason = _string(data['reason']) ?? 'ended';
    if (reason == 'peer_disconnected') {
      _toast('The other person disconnected');
    } else if (reason == 'ended') {
      _toast('Call ended');
    }
    unawaited(_cleanup());
  }

  Future<void> hangUp() async {
    if (_callId != null) {
      _repo.sendCallEnd(callId: _callId!);
    }
    await _cleanup();
  }

  void toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    final audio = tracks.isEmpty ? null : tracks.first;
    if (audio == null) return;
    _micEnabled = !_micEnabled;
    audio.enabled = _micEnabled;
    notifyListeners();
  }

  // --- Internals ---

  void _armRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 30), () {
      if (_phase == CallSessionPhase.ringingIn) {
        rejectIncoming(reason: 'timeout');
      }
    });
  }

  /// Fetches TURN credentials before [createPeerConnection]. Reuses cached
  /// [ice_servers] until shortly before server [ttl] (Metered / OpenRelay).
  /// On fetch failure, falls back to the last good cache.
  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    final now = DateTime.now();
    final refreshBuffer = _refreshBufferForTtl(_cachedTtlSeconds);

    if (_cachedIceServers != null &&
        _credentialsExpireAt != null &&
        now.isBefore(_credentialsExpireAt!.subtract(refreshBuffer))) {
      return _cachedIceServers!;
    }

    final payload = await _repo.fetchTurnCredentialsPayload();
    if (payload != null) {
      final fromApi = _parseIceServers(payload);
      if (fromApi.isNotEmpty) {
        _cachedIceServers = fromApi;
        final ttlSec = _readTtlSeconds(payload);
        final provider = _readProvider(payload);
        _credentialsProvider = provider;
        _cachedTtlSeconds = ttlSec;
        if (ttlSec != null && ttlSec > 0) {
          _credentialsExpireAt = now.add(Duration(seconds: ttlSec));
        } else {
          _credentialsExpireAt = now.add(const Duration(hours: 1));
          _cachedTtlSeconds = 3600;
        }
        debugPrint(
          '[WebRtcCallManager] TURN credentials refreshed '
          'provider=${provider ?? '?'} ttl=${ttlSec ?? '?'}s '
          'servers=${fromApi.length}',
        );
        return fromApi;
      }
    }

    if (_cachedIceServers != null && _cachedIceServers!.isNotEmpty) {
      debugPrint(
        '[WebRtcCallManager] TURN fetch failed; using stale ICE cache '
        '(provider=$_credentialsProvider)',
      );
      return _cachedIceServers!;
    }

    return _parseIceServers(null);
  }

  static int? _readTtlSeconds(dynamic payload) {
    if (payload is! Map) return null;
    final t = payload['ttl'];
    if (t is int) return t > 0 ? t : null;
    if (t is num) {
      final v = t.toInt();
      return v > 0 ? v : null;
    }
    return null;
  }

  static String? _readProvider(dynamic payload) {
    if (payload is! Map) return null;
    final p = payload['provider'];
    if (p == null) return null;
    final s = p.toString();
    return s.isEmpty ? null : s;
  }

  /// How early to refresh before [ttl] ends. Capped so short TTLs still cache.
  static Duration _refreshBufferForTtl(int? ttlSec) {
    const maxBuffer = Duration(minutes: 2);
    if (ttlSec == null || ttlSec <= 0) return maxBuffer;
    if (ttlSec <= maxBuffer.inSeconds) {
      if (ttlSec <= 1) return Duration.zero;
      final fifth = (ttlSec / 5).ceil().clamp(1, ttlSec - 1);
      return Duration(seconds: fifth);
    }
    return maxBuffer;
  }

  List<Map<String, dynamic>> _parseIceServers(dynamic payload) {
    final out = <Map<String, dynamic>>[];

    void addMap(Map<dynamic, dynamic> m) {
      final urlsRaw = m['urls'] ?? m['url'];
      final user = m['username']?.toString() ?? m['credentialName']?.toString();
      final cred = m['credential']?.toString() ?? m['password']?.toString();
      if (urlsRaw is List) {
        final urls = urlsRaw.map((e) => e.toString()).toList();
        if (urls.isEmpty) return;
        final entry = <String, dynamic>{'urls': urls};
        if (user != null) entry['username'] = user;
        if (cred != null) entry['credential'] = cred;
        out.add(entry);
      } else if (urlsRaw != null) {
        final entry = <String, dynamic>{'urls': urlsRaw.toString()};
        if (user != null) entry['username'] = user;
        if (cred != null) entry['credential'] = cred;
        out.add(entry);
      }
    }

    if (payload is Map) {
      final list =
          payload['ice_servers'] ??
          payload['iceServers'] ??
          payload['servers'];
      if (list is List) {
        for (final e in list) {
          if (e is Map) addMap(e);
        }
      }
      if (payload['urls'] != null) {
        addMap(payload);
      }
    } else if (payload is List) {
      for (final e in payload) {
        if (e is Map) addMap(e);
      }
    }

    if (out.isEmpty) {
      out.add(<String, dynamic>{'urls': 'stun:stun.l.google.com:19302'});
    }
    return out;
  }

  Future<void> _openLocalMedia() async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': _isVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<void> _createPeerConnection(List<Map<String, dynamic>> servers) async {
    final configuration = <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };
    _pc = await createPeerConnection(configuration, <String, dynamic>{
      'mandatory': <String, dynamic>{},
      'optional': [
        <String, dynamic>{'DtlsSrtpKeyAgreement': true},
      ],
    });

    _pc!.onIceCandidate = (RTCIceCandidate? c) {
      if (c == null || _peerUserId == null) return;
      final cand = c.candidate;
      if (cand == null || cand.isEmpty) return;
      _repo.sendIceCandidate(
        peerUserId: _peerUserId!,
        candidate: <String, dynamic>{
          'candidate': cand,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      );
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams[0];
      notifyListeners();
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_phase != CallSessionPhase.connected) {
          _phase = CallSessionPhase.connected;
          _connectedAt = DateTime.now();
          _startDurationTicker();
          notifyListeners();
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        debugPrint('[WebRtcCallManager] PC state: $state');
      }
    };

    final ls = _localStream;
    if (ls != null) {
      for (final t in ls.getTracks()) {
        await _pc!.addTrack(t, ls);
      }
    }
  }

  Future<void> _drainRemoteIce() async {
    final pc = _pc;
    if (pc == null) return;
    final pending = List<RTCIceCandidate>.from(_remoteIceBuffer);
    _remoteIceBuffer.clear();
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('[WebRtcCallManager] buffered ICE add failed: $e');
      }
    }
  }

  RTCIceCandidate? _mapToIceCandidate(Map<String, dynamic> m) {
    final cand = m['candidate']?.toString();
    if (cand == null || cand.isEmpty) return null;
    final mid = m['sdpMid']?.toString();
    final idx = m['sdpMLineIndex'];
    int? lineIndex;
    if (idx is int) {
      lineIndex = idx;
    } else if (idx is num) {
      lineIndex = idx.toInt();
    }
    return RTCIceCandidate(cand, mid, lineIndex);
  }

  void _startDurationTicker() {
    _durationTicker?.cancel();
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase == CallSessionPhase.connected) {
        notifyListeners();
      }
    });
  }

  void _resetState() {
    _ringTimeout?.cancel();
    _durationTicker?.cancel();
    _remoteIceBuffer.clear();
    _callId = null;
    _peerUserId = null;
    _peerDisplayName = '';
    _peerAvatarUrl = null;
    _micEnabled = true;
    _connectedAt = null;
  }

  Future<void> _cleanup() async {
    _ringTimeout?.cancel();
    _durationTicker?.cancel();
    _remoteIceBuffer.clear();

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    try {
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    _phase = CallSessionPhase.idle;
    _callId = null;
    _peerUserId = null;
    _peerDisplayName = '';
    _peerAvatarUrl = null;
    notifyListeners();
  }

  String? _string(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  String? _resolveAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${AppConstants.apiBaseUrl}$url';
  }

  String _rejectMessage(String reason) {
    switch (reason) {
      case 'busy':
        return 'User busy';
      case 'timeout':
        return 'No answer';
      case 'rejected':
      default:
        return 'Call declined';
    }
  }

  void _toast(String message) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
