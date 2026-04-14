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
    final createdRaw = json['created_at'];
    DateTime createdAt;
    if (createdRaw is String && createdRaw.isNotEmpty) {
      createdAt = DateTime.parse(createdRaw);
    } else {
      createdAt = DateTime.now();
    }

    return GroupDetails(
      groupId: _str(json['group_id']),
      name: _str(json['name']),
      description: _str(json['description']),
      avatarUrl: _str(json['avatar_url']),
      ownerId: _str(json['owner_id'] ?? json['created_by']),
      conversationId: _str(json['conversation_id']),
      inviteCode: _str(json['invite_code']),
      createdAt: createdAt,
    );
  }

  /// Handles nulls (PUT responses often omit fields that were not sent).
  static String _str(dynamic value) =>
      value == null ? '' : value.toString();

  /// When the server returns a partial group object (or `{status: updated}` parsed
  /// as empty fields), keep stable ids and non-empty text/media from [previous].
  GroupDetails mergeMissingFrom(GroupDetails previous) {
    final missingIds = groupId.isEmpty || conversationId.isEmpty;
    return GroupDetails(
      groupId: groupId.isNotEmpty ? groupId : previous.groupId,
      name: name.isNotEmpty ? name : previous.name,
      description: description.isNotEmpty ? description : previous.description,
      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : previous.avatarUrl,
      ownerId: ownerId.isNotEmpty ? ownerId : previous.ownerId,
      conversationId:
          conversationId.isNotEmpty ? conversationId : previous.conversationId,
      inviteCode: inviteCode.isNotEmpty ? inviteCode : previous.inviteCode,
      createdAt: missingIds ? previous.createdAt : createdAt,
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
