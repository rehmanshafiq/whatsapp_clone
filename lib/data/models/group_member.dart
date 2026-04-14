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
    final joinedRaw = json['joined_at'];
    DateTime joinedAt;
    if (joinedRaw is String && joinedRaw.isNotEmpty) {
      joinedAt = DateTime.parse(joinedRaw);
    } else {
      joinedAt = DateTime.now();
    }

    final role = _str(json['role']);
    return GroupMember(
      userId: _str(json['user_id']),
      username: _str(json['username']),
      displayName: _str(json['display_name']),
      avatarUrl: _str(json['avatar_url']),
      role: role.isEmpty ? 'member' : role,
      joinedAt: joinedAt,
    );
  }

  static String _str(dynamic value) =>
      value == null ? '' : value.toString();

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
