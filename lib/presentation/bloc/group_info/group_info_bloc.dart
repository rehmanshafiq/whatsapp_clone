import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/group_details.dart';
import '../../../data/models/group_member.dart';
import '../../../data/repository/chat_repository.dart';

part 'group_info_event.dart';
part 'group_info_state.dart';

class GroupInfoBloc extends Bloc<GroupInfoEvent, GroupInfoState> {
  GroupInfoBloc(this._repository) : super(const GroupInfoState()) {
    _syncCurrentUserId();
    on<LoadGroupInfo>(_onLoad);
    on<UpdateGroup>(_onUpdateGroup);
    on<DeleteGroupRequested>(_onDeleteGroup);
    on<AddMembersRequested>(_onAddMembers);
    on<RemoveMemberRequested>(_onRemoveMember);
    on<UpdateMemberRoleRequested>(_onUpdateMemberRole);
    on<LeaveGroupRequested>(_onLeaveGroup);
    on<ActionConsumed>(_onActionConsumed);
  }

  final ChatRepository _repository;

  void _syncCurrentUserId() {
    _currentUserId =
        _repository.getCurrentUserId() ?? AppConstants.currentUserId;
  }

  // ── Load ─────────────────────────────────────────────────────────────

  Future<void> _onLoad(
    LoadGroupInfo event,
    Emitter<GroupInfoState> emit,
  ) async {
    _syncCurrentUserId();
    emit(state.copyWith(
      groupId: event.groupId,
      isLoading: true,
      clearError: true,
    ));
    try {
      final results = await Future.wait([
        _repository.getGroupDetails(event.groupId),
        _repository.listGroupMembers(event.groupId),
      ]);
      emit(state.copyWith(
        groupDetails: results[0] as GroupDetails,
        members: results[1] as List<GroupMember>,
        isLoading: false,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(isLoading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  // ── Update group ────────────────────────────────────────────────────

  Future<void> _onUpdateGroup(
    UpdateGroup event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      final updated = await _repository.updateGroup(
        groupId: state.groupId,
        name: event.name,
        description: event.description,
        avatarUrl: event.avatarUrl,
      );
      final merged = state.groupDetails != null
          ? updated.mergeMissingFrom(state.groupDetails!)
          : updated;
      emit(state.copyWith(groupDetails: merged, isUpdating: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Delete group ────────────────────────────────────────────────────

  Future<void> _onDeleteGroup(
    DeleteGroupRequested event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      await _repository.deleteGroup(state.groupId);
      emit(state.copyWith(isUpdating: false, isDeleted: true));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Add members ─────────────────────────────────────────────────────

  Future<void> _onAddMembers(
    AddMembersRequested event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      await _repository.addGroupMembers(
        groupId: state.groupId,
        userIds: event.userIds,
      );
      final members = await _repository.listGroupMembers(state.groupId);
      emit(state.copyWith(members: members, isUpdating: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Remove member ───────────────────────────────────────────────────

  Future<void> _onRemoveMember(
    RemoveMemberRequested event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      await _repository.removeGroupMember(
        groupId: state.groupId,
        userId: event.userId,
      );
      final updated = List<GroupMember>.from(state.members)
        ..removeWhere((m) => m.userId == event.userId);
      emit(state.copyWith(members: updated, isUpdating: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Update role ─────────────────────────────────────────────────────

  Future<void> _onUpdateMemberRole(
    UpdateMemberRoleRequested event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      await _repository.updateMemberRole(
        groupId: state.groupId,
        userId: event.userId,
        role: event.role,
      );
      final members = await _repository.listGroupMembers(state.groupId);
      emit(state.copyWith(members: members, isUpdating: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Leave group ─────────────────────────────────────────────────────

  Future<void> _onLeaveGroup(
    LeaveGroupRequested event,
    Emitter<GroupInfoState> emit,
  ) async {
    emit(state.copyWith(isUpdating: true, clearActionError: true));
    try {
      await _repository.leaveGroup(state.groupId);
      emit(state.copyWith(isUpdating: false, hasLeft: true));
    } on ApiException catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.message));
    } catch (e) {
      emit(state.copyWith(isUpdating: false, actionError: e.toString()));
    }
  }

  // ── Clear one-shot flags ────────────────────────────────────────────

  void _onActionConsumed(
    ActionConsumed event,
    Emitter<GroupInfoState> emit,
  ) {
    emit(state.copyWith(
      isDeleted: false,
      hasLeft: false,
      clearActionError: true,
    ));
  }
}
