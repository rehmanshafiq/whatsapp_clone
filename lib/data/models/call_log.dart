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

  factory CallLog.fromJson(Map<String, dynamic> json) {
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

    final started = asDateTime(json['started_at']) ?? DateTime.now();

    return CallLog(
      callId: asString(json['call_id']) ?? '',
      callerId: asString(json['caller_id']) ?? '',
      calleeId: asString(json['callee_id']) ?? '',
      callType: (asString(json['call_type']) ?? 'voice').toLowerCase(),
      status: (asString(json['status']) ?? 'completed').toLowerCase(),
      startedAt: started,
      endedAt: asDateTime(json['ended_at']),
      duration: asInt(json['duration']),
      peerDisplayName: asString(json['peer_display_name']) ?? 'Unknown',
      peerAvatarUrl: asString(json['peer_avatar_url']) ?? '',
    );
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
