import 'package:equatable/equatable.dart';

class UserSearchResult extends Equatable {
  const UserSearchResult({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    this.statusText,
    this.presenceStatus,
    this.lastSeen,
  });

  final String userId;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String? statusText;

  /// e.g. "online" / "offline"
  final String? presenceStatus;

  /// Epoch milliseconds from presence API, if available.
  final int? lastSeen;

  UserSearchResult copyWith({
    String? statusText,
    String? presenceStatus,
    int? lastSeen,
  }) {
    return UserSearchResult(
      userId: userId,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      statusText: statusText ?? this.statusText,
      presenceStatus: presenceStatus ?? this.presenceStatus,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    userId,
    username,
    displayName,
    avatarUrl,
    statusText,
    presenceStatus,
    lastSeen,
  ];
}
