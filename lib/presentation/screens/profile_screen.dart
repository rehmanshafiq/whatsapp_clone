import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/bottom_navigation/bottom_navigation_bloc.dart';
import '../bloc/bottom_navigation/bottom_navigation_event.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../cubit/profile_draft_cubit.dart';
import '../cubit/profile_draft_state.dart';
import '../widgets/chat_avatar.dart';

/// Full-screen edit profile (same fields, API calls, and styling as the former
/// chat-list bottom sheet). Local draft + text controllers live in
/// [ProfileDraftCubit] so this screen stays a [StatelessWidget].
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProfileDraftCubit(context.read<ChatCubit>()),
      child: const _ProfileScaffold(),
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, chatState) {
        final profile = chatState.currentUserProfile;
        if (profile == null) {
          return Scaffold(
            backgroundColor: AppColors.scaffold,
            appBar: AppBar(
              backgroundColor: AppColors.appBar,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => _openChatsTab(context),
              ),
              title: const Text(
                'Edit Profile',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }

        return BlocConsumer<ProfileDraftCubit, ProfileDraftState>(
          listenWhen: (previous, current) =>
              previous.snack != current.snack && current.snack != null,
          listener: (context, state) {
            final snack = state.snack!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(snack.message),
                backgroundColor:
                    snack.isError ? Colors.red.shade800 : AppColors.accent,
              ),
            );
            context.read<ProfileDraftCubit>().clearSnack();
          },
          builder: (context, draftState) {
            final draftCubit = context.read<ProfileDraftCubit>();
            final avatarOptions = <String>{
              if (profile.avatarUrl.isNotEmpty) profile.avatarUrl,
              ...AppConstants.placeholderAvatars,
            }.toList();

            return Scaffold(
              backgroundColor: AppColors.scaffold,
              appBar: AppBar(
                backgroundColor: AppColors.appBar,
                elevation: 0,
                leading: IconButton(
                  icon:
                      const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => _openChatsTab(context),
                ),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.viewInsetsOf(context).bottom +
                          MediaQuery.paddingOf(context).bottom +
                          24,
                    ),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight - 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: ChatAvatar(
                              imageUrl: draftState.selectedAvatarUrl,
                              name: profile.displayName,
                              radius: 48,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 72,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: avatarOptions.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                if (index == avatarOptions.length) {
                                  return GestureDetector(
                                    onTap: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Avatar upload not implemented',
                                          ),
                                        ),
                                      );
                                    },
                                    child: CircleAvatar(
                                      radius: 24,
                                      backgroundColor: AppColors.chatBackground,
                                      child: const Icon(
                                        Icons.upload,
                                        color: AppColors.iconMuted,
                                      ),
                                    ),
                                  );
                                }
                                final option = avatarOptions[index];
                                final isSelected =
                                    option == draftState.selectedAvatarUrl;
                                return GestureDetector(
                                  onTap: () => draftCubit.selectAvatar(option),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.accent
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: ChatAvatar(
                                      imageUrl: option,
                                      name: profile.displayName,
                                      radius: 24,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          _ProfileLabeledField(
                            label: 'Display Name',
                            child: TextField(
                              controller: draftCubit.displayNameController,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              decoration: _profileInputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ProfileLabeledField(
                            label: 'Status',
                            child: TextField(
                              controller: draftCubit.statusController,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              decoration: _profileInputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ProfileLabeledField(
                            label: 'Username (cannot be changed)',
                            child: TextField(
                              controller: draftCubit.usernameController,
                              enabled: false,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              decoration: _profileInputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                disabledBackgroundColor:
                                    AppColors.accent.withValues(alpha: 0.6),
                              ),
                              onPressed: draftState.isSaving
                                  ? null
                                  : () => draftCubit.save(),
                              child: draftState.isSaving
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save Changes',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

void _openChatsTab(BuildContext context) {
  context.read<BottomNavigationBloc>().add(
        const BottomNavigationTabSelected(0),
      );
}

InputDecoration _profileInputDecoration() {
  return InputDecoration(
    filled: true,
    fillColor: AppColors.chatBackground,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
  );
}

class _ProfileLabeledField extends StatelessWidget {
  const _ProfileLabeledField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
