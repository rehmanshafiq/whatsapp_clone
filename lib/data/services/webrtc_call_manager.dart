import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/constants/app_constants.dart';
import '../../core/root_scaffold_messenger.dart';
import '../repository/chat_repository.dart';

enum CallSessionPhase { idle, ringingOut, ringingIn, connecting, connected }

enum _CallRole { caller, callee }

/// WebRTC + signaling for 1:1 voice/video.
///
/// FIX SUMMARY (vs previous version):
/// 1. Caller no longer creates the PC in [startOutgoingCall].
///    PC is always created in [onCallAnswered] so ICE candidates are fresh
///    and perfectly aligned with the SDP offer. This is the real "deferred
///    offer" pattern.
/// 2. [onCallAnswered] no longer aborts when `call_id` is missing – some
///    servers omit it; we generate a synthetic id so signaling continues.
/// 3. [onWebRtcOffer] buffers the offer in [_pendingRemoteOffer] when the
///    callee's PC hasn't finished initialising yet (async race condition).
///    [onIncomingCall] drains the buffer immediately after PC is ready.
/// 4. [_resetState] clears the pending offer so stale offers can't
///    contaminate a subsequent call.
class WebRtcCallManager extends ChangeNotifier {
  WebRtcCallManager({required ChatRepository chatRepository})
      : _repo = chatRepository {
    _signalingSub = _repo.socketMessages.listen(
      _onSocketEnvelope,
      onError: (Object e, StackTrace st) {
        debugPrint('[WebRtcCallManager] signaling stream error: $e');
      },
      cancelOnError: false,
    );
  }

  final ChatRepository _repo;
  StreamSubscription<dynamic>? _signalingSub;

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

  /// ICE servers loaded before call_initiate / incoming_call so they are
  /// ready for PC creation in [onCallAnswered] / [onIncomingCall].
  List<Map<String, dynamic>>? _pendingIceServers;

  /// FIX: Buffer a remote offer that arrived before the callee's PC was ready.
  RTCSessionDescription? _pendingRemoteOffer;

  Timer? _ringTimeout;
  Timer? _durationTicker;
  DateTime? _connectedAt;

  final List<RTCIceCandidate> _remoteIceBuffer = <RTCIceCandidate>[];

  // ── TURN credential cache ──────────────────────────────────────────────────
  List<Map<String, dynamic>>? _cachedIceServers;
  DateTime? _credentialsExpireAt;
  String? _credentialsProvider;
  int? _cachedTtlSeconds;

  // ── Public getters ─────────────────────────────────────────────────────────
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

  void clearTurnCredentialsCache() {
    _cachedIceServers = null;
    _credentialsExpireAt = null;
    _credentialsProvider = null;
    _cachedTtlSeconds = null;
  }

  void noteOutgoingCallId(String callId) {
    if (_role != _CallRole.caller || callId.isEmpty) return;
    _callId ??= callId;
  }

  // ── Signaling event normalisation ─────────────────────────────────────────

  static String _canonicalSignalingEvent(String type) {
    switch (type) {
      case 'rtc_offer':
      case 'sdp_offer':
      case 'webrtcoffer':
        return 'webrtc_offer';
      case 'rtc_answer':
      case 'sdp_answer':
        return 'webrtc_answer';
      case 'icecandidate':
      case 'new_ice_candidate':
      case 'ice-candidate':
        return 'ice_candidate';
      default:
        return type;
    }
  }

  void _onSocketEnvelope(dynamic event) {
    Map<String, dynamic>? raw;
    if (event is Map<String, dynamic>) {
      raw = event;
    } else if (event is Map) {
      raw = Map<String, dynamic>.from(event);
    } else if (event is String) {
      try {
        final decoded = jsonDecode(event);
        if (decoded is Map<String, dynamic>) {
          raw = decoded;
        } else if (decoded is Map) {
          raw = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    if (raw == null) return;

    final typeRaw = _string(raw['event']);
    if (typeRaw == null) return;
    final normalized = typeRaw.toLowerCase().trim();
    if (normalized == 'ping' || normalized == 'pong') return;

    final type = _canonicalSignalingEvent(normalized);
    const signaling = <String>{
      'incoming_call',
      'call_answered',
      'call_rejected',
      'call_ended',
      'webrtc_offer',
      'webrtc_answer',
      'ice_candidate',
      'call_ringing',
      'call_outgoing',
      'outgoing_call',
      'call_progress',
    };
    if (!signaling.contains(type)) return;

    final data = raw['data'];
    final Map<String, dynamic>? map = data is Map<String, dynamic>
        ? data
        : data is Map
        ? Map<String, dynamic>.from(data)
        : null;

    switch (type) {
      case 'incoming_call':
        if (map != null) unawaited(onIncomingCall(map));
        break;
      case 'call_answered':
        if (map != null) unawaited(onCallAnswered(map));
        break;
      case 'call_rejected':
        if (map != null) onCallRejected(map);
        break;
      case 'call_ended':
        if (map != null) onCallEnded(map);
        break;
      case 'webrtc_offer':
        if (map != null) {
          debugPrint('[WebRtcCallManager] webrtc_offer received');
          unawaited(onWebRtcOffer(map));
        }
        break;
      case 'webrtc_answer':
        if (map != null) unawaited(onWebRtcAnswer(map));
        break;
      case 'ice_candidate':
        if (map != null) unawaited(onRemoteIceCandidate(map));
        break;
      case 'call_ringing':
      case 'call_outgoing':
      case 'outgoing_call':
      case 'call_progress':
        final id = map != null ? _string(map['call_id']) : null;
        if (id != null) noteOutgoingCallId(id);
        break;
    }
  }

  @override
  void dispose() {
    _signalingSub?.cancel();
    _signalingSub = null;
    super.dispose();
  }

  // ── Outgoing call ──────────────────────────────────────────────────────────

  /// FIX: We no longer create the PC here. We only pre-warm media and load ICE
  /// servers so they are ready the moment [call_answered] fires. The PC is
  /// created inside [onCallAnswered] with a fresh ICE-gathering session that
  /// is properly synchronised with the SDP offer.
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
      debugPrint(
        '[WebRtcCallManager] startOutgoingCall peer=$peerUserId video=$isVideo',
      );
      await _repo.ensureRealtimeSocketConnected();

      // Pre-warm: load ICE servers + open camera/mic so they are ready when
      // call_answered arrives. PC creation is deliberately deferred.
      final servers = await _loadIceServers();
      _pendingIceServers = servers;
      await _openLocalMedia();

      debugPrint('[WebRtcCallManager] media open, sending call_initiate');

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
      debugPrint(
        '[WebRtcCallManager] call_initiate sent, waiting for call_answered',
      );
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] startOutgoingCall failed: $e\n$st');
      _toast('Could not start call');
      await _cleanup();
    }
  }

  // ── Incoming call ──────────────────────────────────────────────────────────

  Future<void> onIncomingCall(Map<String, dynamic> data) async {
    debugPrint('[WebRtcCallManager] onIncomingCall data=$data');
    if (hasActiveCall) {
      final busyId = _string(data['call_id']) ?? _string(data['callId']);
      if (busyId != null) {
        _repo.sendCallReject(callId: busyId, reason: 'busy');
      }
      return;
    }

    final callId = _string(data['call_id']) ?? _string(data['callId']);
    final callerId =
        _string(data['caller_id']) ??
            _string(data['callerId']) ??
            _string(data['peer_user_id']) ??
            _string(data['peerUserId']);
    if (callId == null || callerId == null) {
      debugPrint(
        '[WebRtcCallManager] incoming_call missing call_id or caller_id, '
            'keys=${data.keys.toList()}',
      );
      return;
    }
    debugPrint(
      '[WebRtcCallManager] incoming call from $callerId callId=$callId',
    );

    _resetState();
    _role = _CallRole.callee;
    _callId = callId;
    _peerUserId = callerId;
    _peerDisplayName =
        _string(data['caller_name']) ??
            _string(data['caller_display_name']) ??
            'Unknown';
    _peerAvatarUrl = _resolveAvatarUrl(
      _string(data['caller_avatar']) ?? _string(data['caller_avatar_url']),
    );
    _isVideo = _string(data['call_type']) == 'video';
    _phase = CallSessionPhase.ringingIn;
    notifyListeners();

    _armRingTimeout();

    try {
      final servers = await _loadIceServers();
      await _openLocalMedia();
      await _createPeerConnection(servers);

      // FIX: drain any offer that arrived while PC was being set up.
      final pending = _pendingRemoteOffer;
      if (pending != null) {
        _pendingRemoteOffer = null;
        debugPrint(
          '[WebRtcCallManager] draining buffered remote offer after PC ready',
        );
        await _processRemoteOffer(pending.sdp!);
      }
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] incoming prep failed: $e\n$st');
      rejectIncoming(reason: 'rejected');
    }
  }

  void acceptIncoming() {
    unawaited(_acceptIncomingAsync());
  }

  Future<void> _acceptIncomingAsync() async {
    if (_phase != CallSessionPhase.ringingIn || _callId == null) return;
    _ringTimeout?.cancel();
    final sent = await _repo.sendCallAnswer(
      callId: _callId!,
      remotePeerUserId: _peerUserId,
    );
    if (!sent) {
      _toast('No connection. Open Chats to reconnect, then try again.');
      _armRingTimeout();
      notifyListeners();
      return;
    }
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

  // ── Caller: call answered → create PC + offer ──────────────────────────────

  /// FIX: `call_id` is now optional – we synthesise one if missing so the
  /// offer is always sent. The PC is created here (fresh ICE session).
  Future<void> onCallAnswered(Map<String, dynamic> data) async {
    debugPrint('[WebRtcCallManager] onCallAnswered role=$_role data=$data');
    if (_role != _CallRole.caller) return;

    // FIX: tolerate missing call_id rather than aborting.
    final id = _string(data['call_id']) ?? _string(data['callId']);
    if (id != null) {
      _callId = id;
    } else {
      debugPrint(
        '[WebRtcCallManager] call_answered has no call_id – '
            'using synthetic id (peer=$_peerUserId)',
      );
      _callId ??=
      'call_${_peerUserId}_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      // FIX: Always create a fresh PC here. Previously the PC was created in
      // startOutgoingCall, meaning the `if (_pc == null)` guard was never
      // entered and ICE candidates could race ahead of signaling.
      if (_pc != null) {
        debugPrint(
          '[WebRtcCallManager] closing stale PC before creating fresh one',
        );
        try {
          await _pc!.close();
        } catch (_) {}
        _pc = null;
      }

      final servers = _pendingIceServers ?? await _loadIceServers();
      _pendingIceServers = null;
      await _createPeerConnection(servers);
      debugPrint('[WebRtcCallManager] fresh PC created on call_answered');

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      debugPrint(
        '[WebRtcCallManager] SDP offer created, sending to peer=$_peerUserId',
      );
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

  // ── Callee: handle offer → send answer ────────────────────────────────────

  Future<void> onWebRtcOffer(Map<String, dynamic> data) async {
    if (_role != _CallRole.callee) return;
    final fromPeer = _peerIdFromSignalingMap(data);
    if (!_signalingPeerMatches(fromPeer)) {
      debugPrint('[WebRtcCallManager] Ignoring webrtc_offer from $fromPeer');
      return;
    }
    final sdp = _sdpFromSignalingMap(data);
    if (sdp == null) {
      debugPrint(
        '[WebRtcCallManager] webrtc_offer missing sdp, '
            'keys=${data.keys.toList()}',
      );
      return;
    }

    // FIX: Buffer the offer if the PC isn't ready yet (async race in
    // onIncomingCall). It will be drained once _createPeerConnection completes.
    if (_pc == null) {
      debugPrint(
        '[WebRtcCallManager] PC not ready yet – buffering remote offer',
      );
      _pendingRemoteOffer = RTCSessionDescription(sdp, 'offer');
      return;
    }

    await _processRemoteOffer(sdp);
  }

  /// Shared helper so the buffered-offer path and the direct path use the same
  /// logic.
  Future<void> _processRemoteOffer(String sdp) async {
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
      debugPrint('[WebRtcCallManager] answer sent to peer=$_peerUserId');
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] answer failed: $e\n$st');
      _toast('Could not connect');
      await hangUp();
    }
  }

  // ── Caller: handle answer ──────────────────────────────────────────────────

  Future<void> onWebRtcAnswer(Map<String, dynamic> data) async {
    if (_role != _CallRole.caller) return;
    final fromPeer = _peerIdFromSignalingMap(data);
    if (!_signalingPeerMatches(fromPeer)) {
      debugPrint('[WebRtcCallManager] Ignoring webrtc_answer from $fromPeer');
      return;
    }
    final sdp = _sdpFromSignalingMap(data);
    if (sdp == null || _pc == null) {
      debugPrint(
        '[WebRtcCallManager] webrtc_answer missing sdp or PC, '
            'keys=${data.keys.toList()}',
      );
      return;
    }
    try {
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      await _drainRemoteIce();
      debugPrint('[WebRtcCallManager] remote answer set – ICE should connect');
    } catch (e, st) {
      debugPrint('[WebRtcCallManager] setRemote answer failed: $e\n$st');
      _toast('Could not connect');
      await hangUp();
    }
  }

  // ── ICE candidates ─────────────────────────────────────────────────────────

  Future<void> onRemoteIceCandidate(Map<String, dynamic> data) async {
    final peer = _peerIdFromSignalingMap(data);
    if (!_signalingPeerMatches(peer)) return;
    final raw = data['candidate'];
    if (raw is! Map) return;
    final cand = _mapToIceCandidate(Map<String, dynamic>.from(raw));
    if (cand == null) return;

    if (_pc == null) {
      _remoteIceBuffer.add(cand);
      return;
    }
    final hasRemoteDesc = await _pc!.getRemoteDescription() != null;
    if (!hasRemoteDesc) {
      _remoteIceBuffer.add(cand);
      return;
    }
    try {
      await _pc!.addCandidate(cand);
    } catch (e) {
      debugPrint('[WebRtcCallManager] addCandidate failed: $e');
    }
  }

  // ── Call rejected / ended ──────────────────────────────────────────────────

  void onCallRejected(Map<String, dynamic> data) {
    debugPrint('[WebRtcCallManager] onCallRejected data=$data');
    if (_phase == CallSessionPhase.idle) return;
    final id = _string(data['call_id']) ?? _string(data['callId']);
    if (id != null && _callId != null && id != _callId) return;
    final reason = _string(data['reason']) ?? 'rejected';
    _toast(_rejectMessage(reason));
    unawaited(_cleanup());
  }

  void onCallEnded(Map<String, dynamic> data) {
    debugPrint('[WebRtcCallManager] onCallEnded data=$data');
    if (_phase == CallSessionPhase.idle) return;
    final id = _string(data['call_id']) ?? _string(data['callId']);
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

  // ── Internal helpers ───────────────────────────────────────────────────────

  bool _signalingPeerMatches(String? peerField) {
    if (peerField == null || _peerUserId == null) return true;
    if (peerField == _peerUserId) return true;
    final myId = _repo.getCurrentUserId();
    if (myId != null && peerField == myId) return true;
    if (myId == null) return true;
    return false;
  }

  String? _peerIdFromSignalingMap(Map<String, dynamic> data) {
    return _string(data['peer_user_id']) ??
        _string(data['peerUserId']) ??
        _string(data['from_user_id']) ??
        _string(data['fromUserId']) ??
        _string(data['sender_id']) ??
        _string(data['user_id']);
  }

  String? _sdpFromSignalingMap(Map<String, dynamic> data) {
    final direct = _string(data['sdp']);
    if (direct != null) return direct;
    for (final key in <String>[
      'sessionDescription',
      'session_description',
      'offer',
      'answer',
      'description',
    ]) {
      final v = data[key];
      if (v is Map) {
        final nested = Map<String, dynamic>.from(v);
        final s = _string(nested['sdp']);
        if (s != null) return s;
      }
    }
    return null;
  }

  void _markSessionConnectedIfNeeded() {
    if (_phase == CallSessionPhase.connected) return;
    if (_phase != CallSessionPhase.connecting &&
        _phase != CallSessionPhase.ringingOut) {
      return;
    }
    _phase = CallSessionPhase.connected;
    _connectedAt = DateTime.now();
    _startDurationTicker();
    notifyListeners();
  }

  void _armRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 30), () {
      if (_phase == CallSessionPhase.ringingIn) {
        rejectIncoming(reason: 'timeout');
      }
    });
  }

  // ── TURN credentials ───────────────────────────────────────────────────────

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
      final user =
          m['username']?.toString() ?? m['credentialName']?.toString();
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
      if (payload['urls'] != null) addMap(payload);
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

  // ── Media + PC ─────────────────────────────────────────────────────────────

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

  Future<void> _createPeerConnection(
      List<Map<String, dynamic>> servers,
      ) async {
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
      _markSessionConnectedIfNeeded();
      notifyListeners();
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRtcCallManager] PC connectionState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markSessionConnectedIfNeeded();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint('[WebRtcCallManager] PC FAILED – cleaning up');
        _toast('Call connection failed');
        unawaited(hangUp());
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        debugPrint('[WebRtcCallManager] PC CLOSED');
        if (_phase != CallSessionPhase.idle) {
          unawaited(_cleanup());
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        debugPrint('[WebRtcCallManager] PC disconnected (may recover)');
      }
    };

    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[WebRtcCallManager] ICE connectionState: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markSessionConnectedIfNeeded();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('[WebRtcCallManager] ICE FAILED – cleaning up');
        _toast('Call connection failed');
        unawaited(hangUp());
      }
    };

    // Add local tracks (stream was opened in _openLocalMedia).
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

  // ── State reset + cleanup ──────────────────────────────────────────────────

  /// FIX: also clears [_pendingRemoteOffer] so a stale offer from a previous
  /// call cannot contaminate a new one.
  void _resetState() {
    _ringTimeout?.cancel();
    _durationTicker?.cancel();
    _remoteIceBuffer.clear();
    _pendingRemoteOffer = null; // FIX
    _callId = null;
    _peerUserId = null;
    _peerDisplayName = '';
    _peerAvatarUrl = null;
    _micEnabled = true;
    _connectedAt = null;
    _pendingIceServers = null;
  }

  Future<void> _cleanup() async {
    debugPrint('[WebRtcCallManager] _cleanup phase=$_phase');
    _ringTimeout?.cancel();
    _durationTicker?.cancel();
    _remoteIceBuffer.clear();
    _pendingRemoteOffer = null; // FIX
    _pendingIceServers = null;

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

  // ── Utilities ──────────────────────────────────────────────────────────────

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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}