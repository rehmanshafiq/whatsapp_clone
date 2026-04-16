import 'package:equatable/equatable.dart';

class CallLog extends Equatable {
  const CallLog({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.callType,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.duration,
    required this.peerDisplayName,
    required this.peerAvatarUrl,
  });

  final String callId;
  final String callerId;
  final String calleeId;

  /// `"voice"` or `"video"` from API.
  final String callType;

  /// e.g. `completed`, `missed`, `rejected`, `busy`, `cancelled`.
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int duration;
  final String peerDisplayName;
  final String peerAvatarUrl;

  bool get isVideo => callType.toLowerCase() == 'video';

  /// Backend may send `peer_*` **or** `caller_*` / `callee_*`; peer is resolved
  /// using [currentUserId] when the legacy fields are absent.
  factory CallLog.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    String? asString(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      return v.toString();
    }

    DateTime? asDateTime(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v)?.toLocal();
      return null;
    }

    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    final callerId = asString(json['caller_id']) ?? '';
    final calleeId = asString(json['callee_id']) ?? '';
    final callerName = asString(json['caller_display_name'])?.trim() ?? '';
    final calleeName = asString(json['callee_display_name'])?.trim() ?? '';
    final callerAvatar = asString(json['caller_avatar_url'])?.trim() ?? '';
    final calleeAvatar = asString(json['callee_avatar_url'])?.trim() ?? '';

    final legacyPeerName = asString(json['peer_display_name'])?.trim();
    final legacyPeerAvatar = asString(json['peer_avatar_url'])?.trim() ?? '';

    final peerName = _resolvePeerDisplayName(
      currentUserId: currentUserId,
      callerId: callerId,
      calleeId: calleeId,
      callerName: callerName,
      calleeName: calleeName,
      legacyPeerName: legacyPeerName,
    );
    final peerAvatar = _resolvePeerAvatarUrl(
      currentUserId: currentUserId,
      callerId: callerId,
      calleeId: calleeId,
      callerAvatar: callerAvatar,
      calleeAvatar: calleeAvatar,
      legacyPeerAvatar: legacyPeerAvatar,
    );

    final started = asDateTime(json['started_at']) ??
        asDateTime(json['ended_at']) ??
        asDateTime(json['created_at']) ??
        DateTime.now();

    var durationSec = asInt(json['duration']);
    if (durationSec <= 0) {
      final ms = asInt(json['duration_ms']);
      if (ms > 0) {
        durationSec = (ms / 1000).round();
      }
    }

    return CallLog(
      callId: asString(json['call_id']) ?? '',
      callerId: callerId,
      calleeId: calleeId,
      callType: (asString(json['call_type']) ?? 'voice').toLowerCase(),
      status: (asString(json['status']) ?? 'completed').toLowerCase(),
      startedAt: started,
      endedAt: asDateTime(json['ended_at']),
      duration: durationSec,
      peerDisplayName: peerName,
      peerAvatarUrl: peerAvatar,
    );
  }

  static String _resolvePeerDisplayName({
    required String? currentUserId,
    required String callerId,
    required String calleeId,
    required String callerName,
    required String calleeName,
    required String? legacyPeerName,
  }) {
    if (legacyPeerName != null && legacyPeerName.isNotEmpty) {
      return legacyPeerName;
    }
    final uid = currentUserId?.trim();
    if (uid != null && uid.isNotEmpty) {
      if (callerId == uid) {
        return calleeName.isNotEmpty ? calleeName : 'Unknown';
      }
      if (calleeId == uid) {
        return callerName.isNotEmpty ? callerName : 'Unknown';
      }
    }
    if (calleeName.isNotEmpty) return calleeName;
    if (callerName.isNotEmpty) return callerName;
    return 'Unknown';
  }

  static String _resolvePeerAvatarUrl({
    required String? currentUserId,
    required String callerId,
    required String calleeId,
    required String callerAvatar,
    required String calleeAvatar,
    required String legacyPeerAvatar,
  }) {
    if (legacyPeerAvatar.isNotEmpty) return legacyPeerAvatar;
    final uid = currentUserId?.trim();
    if (uid != null && uid.isNotEmpty) {
      if (callerId == uid) return calleeAvatar;
      if (calleeId == uid) return callerAvatar;
    }
    if (calleeAvatar.isNotEmpty) return calleeAvatar;
    return callerAvatar;
  }

  @override
  List<Object?> get props => [
        callId,
        callerId,
        calleeId,
        callType,
        status,
        startedAt,
        endedAt,
        duration,
        peerDisplayName,
        peerAvatarUrl,
      ];
}
