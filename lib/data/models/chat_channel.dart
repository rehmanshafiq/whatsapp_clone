import 'package:equatable/equatable.dart';

import 'message_status.dart';

class ChatChannel extends Equatable {
  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  final MessageStatus? lastMessageStatus;
  final String? lastMessageSenderId;
  /// Peer participant's user id (for WebSocket send_message / message_delivered / message_read).
  final String? peerUserId;
  /// Last seen timestamp when peer is offline (from presence_update).
  final DateTime? lastSeen;
  /// Whether the current user has muted this conversation.
  final bool isMuted;
  /// Whether this conversation is a group chat.
  final bool isGroup;
  /// The group's unique id (needed for group management APIs). Null for 1:1.
  final String? groupId;

  const ChatChannel({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.lastMessage = '',
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastMessageStatus,
    this.lastMessageSenderId,
    this.peerUserId,
    this.lastSeen,
    this.isMuted = false,
    this.isGroup = false,
    this.groupId,
  });

  ChatChannel copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
    MessageStatus? lastMessageStatus,
    String? lastMessageSenderId,
    String? peerUserId,
    DateTime? lastSeen,
    bool? isMuted,
    bool? isGroup,
    String? groupId,
  }) {
    return ChatChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      peerUserId: peerUserId ?? this.peerUserId,
      lastSeen: lastSeen ?? this.lastSeen,
      isMuted: isMuted ?? this.isMuted,
      isGroup: isGroup ?? this.isGroup,
      groupId: groupId ?? this.groupId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarUrl': avatarUrl,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime.toIso8601String(),
        'unreadCount': unreadCount,
        'isOnline': isOnline,
        'lastMessageStatus': lastMessageStatus?.name,
        'lastMessageSenderId': lastMessageSenderId,
        'peerUserId': peerUserId,
        'lastSeen': lastSeen?.toIso8601String(),
        'isMuted': isMuted,
        'isGroup': isGroup,
        'groupId': groupId,
      };

  factory ChatChannel.fromJson(Map<String, dynamic> json) => ChatChannel(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatarUrl'] as String? ?? '',
        lastMessage: json['lastMessage'] as String? ?? '',
        lastMessageTime: DateTime.parse(json['lastMessageTime'] as String),
        unreadCount: json['unreadCount'] as int? ?? 0,
        isOnline: json['isOnline'] as bool? ?? false,
        lastMessageStatus: json['lastMessageStatus'] != null
            ? MessageStatus.values.firstWhere(
                (e) => e.name == json['lastMessageStatus'],
                orElse: () => MessageStatus.sent,
              )
            : null,
        lastMessageSenderId: json['lastMessageSenderId'] as String?,
        peerUserId: json['peerUserId'] as String?,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'] as String)
            : null,
        isMuted:
            json['isMuted'] as bool? ??
            json['is_muted'] as bool? ??
            false,
        isGroup: json['isGroup'] as bool? ?? false,
        groupId: json['groupId'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        lastMessage,
        lastMessageTime,
        unreadCount,
        isOnline,
        lastMessageStatus,
        lastMessageSenderId,
        peerUserId,
        lastSeen,
        isMuted,
        isGroup,
        groupId,
      ];
}
