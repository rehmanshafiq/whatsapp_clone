import 'package:equatable/equatable.dart';

class GroupMember extends Equatable {
  const GroupMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String role;
  final DateTime joinedAt;

  bool get isOwner => role == 'owner' || role == 'creator';
  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get canManageMembers => isOwner || isAdmin;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'role': role,
        'joined_at': joinedAt.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        userId,
        username,
        displayName,
        avatarUrl,
        role,
        joinedAt,
      ];
}
