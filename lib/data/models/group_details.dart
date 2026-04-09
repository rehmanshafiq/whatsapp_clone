import 'package:equatable/equatable.dart';

class GroupDetails extends Equatable {
  const GroupDetails({
    required this.groupId,
    required this.name,
    required this.description,
    required this.avatarUrl,
    required this.ownerId,
    required this.conversationId,
    required this.inviteCode,
    required this.createdAt,
  });

  final String groupId;
  final String name;
  final String description;
  final String avatarUrl;
  final String ownerId;
  final String conversationId;
  final String inviteCode;
  final DateTime createdAt;

  factory GroupDetails.fromJson(Map<String, dynamic> json) {
    return GroupDetails(
      groupId: json['group_id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      ownerId: json['owner_id'] as String? ??
          json['created_by'] as String? ??
          '',
      conversationId: json['conversation_id'] as String,
      inviteCode: json['invite_code'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'owner_id': ownerId,
        'conversation_id': conversationId,
        'invite_code': inviteCode,
        'created_at': createdAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        groupId,
        name,
        description,
        avatarUrl,
        ownerId,
        conversationId,
        inviteCode,
        createdAt,
      ];
}
