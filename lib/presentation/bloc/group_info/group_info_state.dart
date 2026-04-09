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

  bool get isOwner => currentMember?.isOwner ?? false;
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

/// Set once from AppConstants at bloc creation time.
String _currentUserId = '';
