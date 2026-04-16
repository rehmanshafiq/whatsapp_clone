import 'package:equatable/equatable.dart';

/// One-shot UI feedback after attempting to save the profile.
final class ProfileSnack extends Equatable {
  const ProfileSnack({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  List<Object?> get props => [message, isError];
}

/// Draft data for the Profile / Edit Profile screen (avatar picker + save).
///
/// Text for editable fields is held in [ProfileDraftCubit] controllers so this
/// [StatelessWidget] tree does not need [setState].
final class ProfileDraftState extends Equatable {
  const ProfileDraftState({
    required this.username,
    required this.selectedAvatarUrl,
    this.isSaving = false,
    this.snack,
  });

  /// Read-only; shown in the disabled username field.
  final String username;

  /// Currently chosen avatar URL (placeholders, current, or prior server URL).
  final String selectedAvatarUrl;

  final bool isSaving;

  /// Non-null triggers a [SnackBar]; cleared after the listener shows it.
  final ProfileSnack? snack;

  ProfileDraftState copyWith({
    String? username,
    String? selectedAvatarUrl,
    bool? isSaving,
    ProfileSnack? snack,
    bool clearSnack = false,
  }) {
    return ProfileDraftState(
      username: username ?? this.username,
      selectedAvatarUrl: selectedAvatarUrl ?? this.selectedAvatarUrl,
      isSaving: isSaving ?? this.isSaving,
      snack: clearSnack ? null : (snack ?? this.snack),
    );
  }

  @override
  List<Object?> get props => [username, selectedAvatarUrl, isSaving, snack];
}
