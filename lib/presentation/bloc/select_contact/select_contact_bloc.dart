import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/models/user_search.dart';
import '../../../data/repository/chat_repository.dart';

part 'select_contact_event.dart';
part 'select_contact_state.dart';

class SelectContactBloc
    extends Bloc<SelectContactEvent, SelectContactState> {
  SelectContactBloc(this._repository) : super(const SelectContactState()) {
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<PerformSearch>(_onPerformSearch);
    on<ToggleSelection>(_onToggleSelection);
    on<ClearSelection>(_onClearSelection);
    on<CreateGroupPressed>(_onCreateGroupPressed);
    on<StartOneToOneChat>(_onStartOneToOneChat);
    on<NavigationConsumed>(_onNavigationConsumed);
  }

  final ChatRepository _repository;
  Timer? _debounceTimer;

  // ── Search ──────────────────────────────────────────────────────────

  void _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SelectContactState> emit,
  ) {
    _debounceTimer?.cancel();
    emit(state.copyWith(query: event.query, clearError: true));

    if (event.query.trim().isEmpty) {
      emit(state.copyWith(
        results: const [],
        isLoading: false,
        clearError: true,
      ));
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      add(const PerformSearch());
    });
  }

  Future<void> _onPerformSearch(
    PerformSearch event,
    Emitter<SelectContactState> emit,
  ) async {
    final query = state.query.trim();
    if (query.isEmpty) return;

    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final results = await _repository.searchUsers(query);
      emit(state.copyWith(results: results, isLoading: false));
    } on ApiException catch (e) {
      emit(state.copyWith(isLoading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  // ── Selection ───────────────────────────────────────────────────────

  void _onToggleSelection(
    ToggleSelection event,
    Emitter<SelectContactState> emit,
  ) {
    final updated = Set<UserSearchResult>.from(state.selectedUsers);
    if (updated.contains(event.user)) {
      updated.remove(event.user);
    } else {
      updated.add(event.user);
    }
    emit(state.copyWith(
      selectedUsers: updated,
      isGroupMode: updated.isNotEmpty,
    ));
  }

  void _onClearSelection(
    ClearSelection event,
    Emitter<SelectContactState> emit,
  ) {
    emit(state.copyWith(
      selectedUsers: const {},
      isGroupMode: false,
    ));
  }

  // ── Create group ────────────────────────────────────────────────────

  Future<void> _onCreateGroupPressed(
    CreateGroupPressed event,
    Emitter<SelectContactState> emit,
  ) async {
    if (state.selectedUsers.length < 2) return;

    emit(state.copyWith(isCreatingConversation: true, clearError: true));
    try {
      final memberIds =
          state.selectedUsers.map((u) => u.userId).toList();
      final channel = await _repository.createGroup(
        name: event.groupName,
        memberIds: memberIds,
      );
      emit(state.copyWith(
        isCreatingConversation: false,
        navigateToConversationId: channel.id,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(isCreatingConversation: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(
        isCreatingConversation: false,
        error: e.toString(),
      ));
    }
  }

  // ── 1:1 chat ────────────────────────────────────────────────────────

  Future<void> _onStartOneToOneChat(
    StartOneToOneChat event,
    Emitter<SelectContactState> emit,
  ) async {
    emit(state.copyWith(isCreatingConversation: true, clearError: true));
    try {
      final channel =
          await _repository.createOrGetConversationForUser(event.user);
      emit(state.copyWith(
        isCreatingConversation: false,
        navigateToConversationId: channel.id,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(isCreatingConversation: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(
        isCreatingConversation: false,
        error: e.toString(),
      ));
    }
  }

  // ── Navigation consumed ─────────────────────────────────────────────

  void _onNavigationConsumed(
    NavigationConsumed event,
    Emitter<SelectContactState> emit,
  ) {
    emit(state.copyWith(clearNavigation: true));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
