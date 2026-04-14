part of 'group_info_bloc.dart';

final class GroupInfoState extends Equatable {
  const GroupInfoState({
    this.groupId = '',
    this.groupDetails,
    this.members = const [],
    this.isLoading = false,
    this.error,
    this.isUpdating = false,
    this.isDeleted = false,
    this.hasLeft = false,
    this.actionError,
  });

  final String groupId;
  final GroupDetails? groupDetails;
  final List<GroupMember> members;
  final bool isLoading;
  final String? error;
  final bool isUpdating;
  final bool isDeleted;
  final bool hasLeft;
  final String? actionError;

  String get currentUserId => _currentUserId;

  GroupMember? get currentMember {
    try {
      return members.firstWhere((m) => m.userId == _currentUserId);
    } catch (_) {
      return null;
    }
  }

  /// True if our row in the member list is owner/admin, or if [groupDetails.ownerId]
  /// matches the logged-in user (covers API id vs placeholder "me" mismatches).
  bool get isOwner {
    if (currentMember?.isOwner == true) return true;
    final d = groupDetails;
    if (d != null &&
        d.ownerId.isNotEmpty &&
        d.ownerId == _currentUserId) {
      return true;
    }
    return false;
  }

  bool get isAdmin => currentMember?.isAdmin ?? false;
  bool get canManageMembers => isOwner || isAdmin;

  GroupInfoState copyWith({
    String? groupId,
    GroupDetails? groupDetails,
    List<GroupMember>? members,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isUpdating,
    bool? isDeleted,
    bool? hasLeft,
    String? actionError,
    bool clearActionError = false,
  }) {
    return GroupInfoState(
      groupId: groupId ?? this.groupId,
      groupDetails: groupDetails ?? this.groupDetails,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isUpdating: isUpdating ?? this.isUpdating,
      isDeleted: isDeleted ?? this.isDeleted,
      hasLeft: hasLeft ?? this.hasLeft,
      actionError: clearActionError
          ? null
          : (actionError ?? this.actionError),
    );
  }

  @override
  List<Object?> get props => [
        groupId,
        groupDetails,
        members,
        isLoading,
        error,
        isUpdating,
        isDeleted,
        hasLeft,
        actionError,
      ];
}

/// Synced from [ChatRepository.getCurrentUserId] in [GroupInfoBloc] (not the placeholder `me`).
String _currentUserId = '';
