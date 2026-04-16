import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/user_search.dart';
import 'chat_cubit.dart';
import 'chat_state.dart';
import 'profile_draft_state.dart';

/// Holds [TextEditingController]s and draft avatar selection for [ProfileScreen].
///
/// Controllers are disposed in [close]; profile text is synced when
/// [ChatCubit.currentUserProfile] changes (same [Equatable] semantics as before).
class ProfileDraftCubit extends Cubit<ProfileDraftState> {
  ProfileDraftCubit(this._chat)
      : displayNameController = TextEditingController(),
        statusController = TextEditingController(),
        usernameController = TextEditingController(),
        super(
          ProfileDraftState(
            username: '',
            selectedAvatarUrl: '',
          ),
        ) {
    _subscription = _chat.stream.listen(_onChatState);
    _applyProfile(_chat.state.currentUserProfile);
    unawaited(_chat.loadCurrentUserProfile());
  }

  final ChatCubit _chat;
  final TextEditingController displayNameController;
  final TextEditingController statusController;
  final TextEditingController usernameController;

  late final StreamSubscription<ChatState> _subscription;
  UserSearchResult? _lastAppliedProfile;

  void _onChatState(ChatState chatState) {
    _applyProfile(chatState.currentUserProfile);
  }

  void _applyProfile(UserSearchResult? profile) {
    if (profile == null) return;
    if (profile == _lastAppliedProfile) return;
    if (state.isSaving) return;

    _lastAppliedProfile = profile;
    displayNameController.text = profile.displayName;
    statusController.text = profile.statusText ?? '';
    usernameController.text = profile.username;
    emit(
      state.copyWith(
        username: profile.username,
        selectedAvatarUrl: profile.avatarUrl,
      ),
    );
  }

  void selectAvatar(String url) {
    emit(state.copyWith(selectedAvatarUrl: url));
  }

  void clearSnack() {
    if (state.snack != null) {
      emit(state.copyWith(clearSnack: true));
    }
  }

  /// Same validation and API call sequence as the former bottom sheet [handleSave].
  Future<void> save() async {
    if (state.isSaving) return;
    emit(state.copyWith(isSaving: true, clearSnack: true));
    try {
      await _chat.updateCurrentUserProfile(
        displayName: displayNameController.text.trim(),
        statusText: statusController.text.trim(),
        avatarUrl: state.selectedAvatarUrl,
      );
      emit(
        state.copyWith(
          isSaving: false,
          snack: const ProfileSnack(
            message: 'Profile updated',
            isError: false,
          ),
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isSaving: false,
          snack: ProfileSnack(message: e.message, isError: true),
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isSaving: false,
          snack: const ProfileSnack(
            message: 'Profile update failed',
            isError: true,
          ),
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    displayNameController.dispose();
    statusController.dispose();
    usernameController.dispose();
    return super.close();
  }
}
