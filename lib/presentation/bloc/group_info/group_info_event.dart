part of 'group_info_bloc.dart';

sealed class GroupInfoEvent extends Equatable {
  const GroupInfoEvent();

  @override
  List<Object?> get props => [];
}

final class LoadGroupInfo extends GroupInfoEvent {
  const LoadGroupInfo(this.groupId);
  final String groupId;

  @override
  List<Object?> get props => [groupId];
}

final class UpdateGroup extends GroupInfoEvent {
  const UpdateGroup({this.name, this.description, this.avatarUrl});
  final String? name;
  final String? description;
  final String? avatarUrl;

  @override
  List<Object?> get props => [name, description, avatarUrl];
}

final class DeleteGroupRequested extends GroupInfoEvent {
  const DeleteGroupRequested();
}

final class AddMembersRequested extends GroupInfoEvent {
  const AddMembersRequested(this.userIds);
  final List<String> userIds;

  @override
  List<Object?> get props => [userIds];
}

final class RemoveMemberRequested extends GroupInfoEvent {
  const RemoveMemberRequested(this.userId);
  final String userId;

  @override
  List<Object?> get props => [userId];
}

final class UpdateMemberRoleRequested extends GroupInfoEvent {
  const UpdateMemberRoleRequested({required this.userId, required this.role});
  final String userId;
  final String role;

  @override
  List<Object?> get props => [userId, role];
}

final class LeaveGroupRequested extends GroupInfoEvent {
  const LeaveGroupRequested();
}

/// Clears one-shot navigation/action flags after UI has consumed them.
final class ActionConsumed extends GroupInfoEvent {
  const ActionConsumed();
}
