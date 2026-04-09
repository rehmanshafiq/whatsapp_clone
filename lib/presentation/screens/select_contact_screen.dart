import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_search.dart';
import '../../data/repository/chat_repository.dart';
import '../bloc/select_contact/select_contact_bloc.dart';
import '../widgets/chat_avatar.dart';

class SelectContactScreen extends StatelessWidget {
  const SelectContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SelectContactBloc(getIt<ChatRepository>()),
      child: const _SelectContactView(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root view – wires BlocListener for navigation & error snackbars
// ─────────────────────────────────────────────────────────────────────────────

class _SelectContactView extends StatelessWidget {
  const _SelectContactView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<SelectContactBloc, SelectContactState>(
      listenWhen: (prev, curr) =>
          (curr.navigateToConversationId != null &&
              prev.navigateToConversationId !=
                  curr.navigateToConversationId) ||
          (curr.error != null && prev.error != curr.error),
      listener: (context, state) {
        if (state.navigateToConversationId != null) {
          context.read<SelectContactBloc>().add(const NavigationConsumed());
          context.goNamed(
            AppRouter.chatDetail,
            pathParameters: {'id': state.navigateToConversationId!},
          );
          return;
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.redAccent,
              ),
            );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: const _AppBar(),
        body: const _Body(),
        floatingActionButton: const _GroupFab(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar – back button behaviour adapts to group mode
// ─────────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectContactBloc, SelectContactState>(
      buildWhen: (prev, curr) =>
          prev.isGroupMode != curr.isGroupMode ||
          prev.selectedUsers.length != curr.selectedUsers.length,
      builder: (context, state) {
        return AppBar(
          backgroundColor: AppColors.appBar,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              if (state.isGroupMode) {
                context
                    .read<SelectContactBloc>()
                    .add(const ClearSelection());
              } else {
                context.goNamed(AppRouter.chats);
              }
            },
          ),
          title: Text(
            state.isGroupMode
                ? '${state.selectedUsers.length} participant${state.selectedUsers.length == 1 ? '' : 's'} selected'
                : 'Select Contact',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            if (state.isGroupMode)
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.iconMuted),
                onPressed: () => context
                    .read<SelectContactBloc>()
                    .add(const ClearSelection()),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body – search field + selected chips + results list
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SearchField(),
        const _SelectedChips(),
        const Expanded(child: _ResultsList()),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field – always visible, dispatches SearchQueryChanged
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.appBar,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search for contacts...',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.iconMuted, size: 22),
          filled: true,
          fillColor: AppColors.scaffold,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) => context
            .read<SelectContactBloc>()
            .add(SearchQueryChanged(value)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selected user chips – horizontal scroll, visible only in group mode
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedChips extends StatelessWidget {
  const _SelectedChips();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectContactBloc, SelectContactState>(
      buildWhen: (prev, curr) =>
          prev.selectedUsers != curr.selectedUsers ||
          prev.isGroupMode != curr.isGroupMode,
      builder: (context, state) {
        if (!state.isGroupMode || state.selectedUsers.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          color: AppColors.appBar,
          height: 90,
          padding: const EdgeInsets.only(bottom: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: state.selectedUsers.length,
            itemBuilder: (context, index) {
              final user = state.selectedUsers.elementAt(index);
              return _SelectedUserChip(user: user);
            },
          ),
        );
      },
    );
  }
}

class _SelectedUserChip extends StatelessWidget {
  const _SelectedUserChip({required this.user});
  final UserSearchResult user;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          context.read<SelectContactBloc>().add(ToggleSelection(user)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ChatAvatar(
                  imageUrl: user.avatarUrl,
                  name: user.displayName,
                  radius: 24,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.iconMuted,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 60,
              child: Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results list – empty states, loading, error, and user tiles
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  const _ResultsList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectContactBloc, SelectContactState>(
      buildWhen: (prev, curr) =>
          prev.query != curr.query ||
          prev.results != curr.results ||
          prev.isLoading != curr.isLoading ||
          prev.error != curr.error ||
          prev.selectedUsers != curr.selectedUsers ||
          prev.isGroupMode != curr.isGroupMode ||
          prev.isCreatingConversation != curr.isCreatingConversation,
      builder: (context, state) {
        if (state.isCreatingConversation) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }

        final hasQuery = state.query.trim().isNotEmpty;

        if (!hasQuery) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_search_outlined,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Search for users',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }

        if (state.error != null && state.results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (state.results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_off_outlined,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No users found',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: state.results.length,
          separatorBuilder: (_, _) => const Divider(
            color: AppColors.divider,
            height: 1,
            indent: 76,
          ),
          itemBuilder: (context, index) {
            final user = state.results[index];
            final isSelected = state.selectedUsers.contains(user);
            return _ContactTile(
              user: user,
              isSelected: isSelected,
              isGroupMode: state.isGroupMode,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact tile – tap / long-press behaviour + selection indicator
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.user,
    required this.isSelected,
    required this.isGroupMode,
  });

  final UserSearchResult user;
  final bool isSelected;
  final bool isGroupMode;

  @override
  Widget build(BuildContext context) {
    final presence = _buildPresenceSubtitle(
      status: user.presenceStatus,
      lastSeen: user.lastSeen,
    );

    return ListTile(
      leading: Stack(
        children: [
          ChatAvatar(
            imageUrl: user.avatarUrl,
            name: user.displayName,
            radius: 24,
          ),
          if (isSelected)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        presence ??
            (user.statusText?.isNotEmpty == true ? user.statusText! : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      trailing: isGroupMode
          ? Checkbox(
              value: isSelected,
              activeColor: AppColors.accent,
              onChanged: (_) => context
                  .read<SelectContactBloc>()
                  .add(ToggleSelection(user)),
            )
          : null,
      onTap: () {
        final bloc = context.read<SelectContactBloc>();
        if (isGroupMode) {
          bloc.add(ToggleSelection(user));
        } else {
          bloc.add(StartOneToOneChat(user));
        }
      },
      onLongPress: () {
        context.read<SelectContactBloc>().add(ToggleSelection(user));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB – visible only when ≥ 2 users are selected, launches group creation
// ─────────────────────────────────────────────────────────────────────────────

class _GroupFab extends StatelessWidget {
  const _GroupFab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SelectContactBloc, SelectContactState>(
      buildWhen: (prev, curr) =>
          prev.selectedUsers.length != curr.selectedUsers.length ||
          prev.isCreatingConversation != curr.isCreatingConversation,
      builder: (context, state) {
        if (state.selectedUsers.length < 2 || state.isCreatingConversation) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton(
          backgroundColor: AppColors.accent,
          onPressed: () => _showGroupNameDialog(context),
          child: const Icon(Icons.arrow_forward, color: Colors.white),
        );
      },
    );
  }

  void _showGroupNameDialog(BuildContext context) {
    String groupName = '';
    showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.appBar,
          title: const Text(
            'Group name',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter group name',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
            onChanged: (v) => groupName = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(groupName.trim()),
              child: const Text(
                'Create',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        );
      },
    ).then((name) {
      if (!context.mounted) return;
      if (name != null && name.isNotEmpty) {
        context
            .read<SelectContactBloc>()
            .add(CreateGroupPressed(groupName: name));
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presence subtitle helper
// ─────────────────────────────────────────────────────────────────────────────

String? _buildPresenceSubtitle({
  required String? status,
  required int? lastSeen,
}) {
  if (status == 'online') return 'Online';
  if (status == 'offline' && lastSeen != null) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      lastSeen,
      isUtc: true,
    ).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(date).inDays;

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diffDays == 0) {
      return 'Last seen today at $time';
    } else if (diffDays == 1) {
      return 'Last seen yesterday at $time';
    } else {
      return 'Tap to start chatting';
    }
  }
  return null;
}
