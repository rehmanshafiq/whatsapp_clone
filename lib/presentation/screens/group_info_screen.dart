import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/group_member.dart';
import '../../data/repository/chat_repository.dart';
import '../bloc/group_info/group_info_bloc.dart';
import '../widgets/chat_avatar.dart';

class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GroupInfoBloc(getIt<ChatRepository>())..add(LoadGroupInfo(groupId)),
      child: const _GroupInfoView(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root view – listener for navigation events (delete / leave)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupInfoView extends StatelessWidget {
  const _GroupInfoView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<GroupInfoBloc, GroupInfoState>(
      listenWhen: (prev, curr) =>
          curr.isDeleted != prev.isDeleted ||
          curr.hasLeft != prev.hasLeft ||
          (curr.actionError != null && curr.actionError != prev.actionError),
      listener: (context, state) {
        if (state.isDeleted || state.hasLeft) {
          context.read<GroupInfoBloc>().add(const ActionConsumed());
          context.goNamed(AppRouter.chats);
          return;
        }
        if (state.actionError != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(state.actionError!),
              backgroundColor: Colors.redAccent,
            ));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(
          backgroundColor: AppColors.appBar,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: const Text(
            'Group Info',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: const _Body(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GroupInfoBloc, GroupInfoState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        if (state.error != null) {
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
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context
                      .read<GroupInfoBloc>()
                      .add(LoadGroupInfo(state.groupId)),
                  child: const Text('Retry',
                      style: TextStyle(color: AppColors.accent)),
                ),
              ],
            ),
          );
        }

        final details = state.groupDetails;
        if (details == null) return const SizedBox.shrink();

        return ListView(
          children: [
            const SizedBox(height: 24),
            // ── Group avatar + name + member count ──
            _GroupHeader(
              name: details.name,
              avatarUrl: details.avatarUrl,
              memberCount: state.members.length,
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.divider, height: 1),

            // ── Description ──
            if (details.description.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Description',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details.description,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
            ],

            // ── Edit group (admin/owner only) ──
            if (state.canManageMembers) ...[
              ListTile(
                leading:
                    const Icon(Icons.edit, color: AppColors.accent, size: 22),
                title: const Text('Edit Group',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => _showEditGroupDialog(context, state),
              ),
              const Divider(color: AppColors.divider, height: 1),
            ],

            // ── Members header + add button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Members (${state.members.length})',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (state.canManageMembers)
                    IconButton(
                      icon: const Icon(Icons.person_add,
                          color: AppColors.accent, size: 22),
                      onPressed: () => _showAddMembersDialog(context),
                    ),
                ],
              ),
            ),

            // ── Member list ──
            ...state.members.map((member) => _MemberTile(
                  member: member,
                  isOwner: state.isOwner,
                  isAdmin: state.isAdmin,
                  currentUserId: state.currentUserId,
                )),

            const SizedBox(height: 16),
            const Divider(color: AppColors.divider, height: 1),

            // ── Leave group ──
            _DangerAction(
              icon: Icons.exit_to_app,
              label: 'Leave Group',
              onTap: () => _confirmAction(
                context,
                title: 'Leave Group',
                message:
                    'Are you sure you want to leave this group? You will no longer receive messages.',
                actionLabel: 'Leave',
                onConfirm: () => context
                    .read<GroupInfoBloc>()
                    .add(const LeaveGroupRequested()),
              ),
            ),

            // ── Delete group (owner only) ──
            if (state.isOwner)
              _DangerAction(
                icon: Icons.delete_forever,
                label: 'Delete Group',
                onTap: () => _confirmAction(
                  context,
                  title: 'Delete Group',
                  message:
                      'This will permanently delete the group and all its messages for everyone.',
                  actionLabel: 'Delete',
                  onConfirm: () => context
                      .read<GroupInfoBloc>()
                      .add(const DeleteGroupRequested()),
                ),
              ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  void _showEditGroupDialog(BuildContext context, GroupInfoState state) {
    final details = state.groupDetails!;
    String name = details.name;
    String description = details.description;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.appBar,
          title: const Text('Edit Group',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: TextEditingController(text: name),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.divider)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent)),
                ),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: description),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.divider)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent)),
                ),
                maxLines: 3,
                onChanged: (v) => description = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                context.read<GroupInfoBloc>().add(UpdateGroup(
                      name: name.trim().isNotEmpty ? name.trim() : null,
                      description: description.trim(),
                    ));
              },
              child: const Text('Save',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        );
      },
    );
  }

  void _showAddMembersDialog(BuildContext context) {
    String input = '';
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.appBar,
          title: const Text('Add Members',
              style: TextStyle(color: AppColors.textPrimary)),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter user IDs (comma-separated)',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent)),
            ),
            onChanged: (v) => input = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                final ids = input
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (ids.isNotEmpty) {
                  context
                      .read<GroupInfoBloc>()
                      .add(AddMembersRequested(ids));
                }
              },
              child:
                  const Text('Add', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        );
      },
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onConfirm,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.appBar,
          title:
              Text(title, style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(message,
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                onConfirm();
              },
              child: Text(actionLabel,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group header – avatar, name, member count
// ─────────────────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.avatarUrl,
    required this.memberCount,
  });

  final String name;
  final String avatarUrl;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ChatAvatar(imageUrl: avatarUrl, name: name, radius: 48),
        const SizedBox(height: 14),
        Text(
          name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '$memberCount member${memberCount == 1 ? '' : 's'}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member tile – avatar, name, role badge, actions
// ─────────────────────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isOwner,
    required this.isAdmin,
    required this.currentUserId,
  });

  final GroupMember member;
  final bool isOwner;
  final bool isAdmin;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final isSelf = member.userId == currentUserId;

    return ListTile(
      leading: ChatAvatar(
        imageUrl: member.avatarUrl,
        name: member.displayName,
        radius: 22,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              '${member.displayName}${isSelf ? ' (You)' : ''}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isOwner || member.isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: member.isOwner
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.divider,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                member.isOwner ? 'creator' : 'admin',
                style: TextStyle(
                  color: member.isOwner
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        member.username,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      trailing: (!isSelf && (isOwner || (isAdmin && member.isMember)))
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.iconMuted),
              color: AppColors.appBar,
              onSelected: (action) =>
                  _handleMemberAction(context, action),
              itemBuilder: (_) => [
                if (isOwner) ...[
                  PopupMenuItem(
                    value: member.isAdmin ? 'demote' : 'promote',
                    child: Text(
                      member.isAdmin ? 'Remove admin' : 'Make admin',
                      style:
                          const TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            )
          : null,
    );
  }

  void _handleMemberAction(BuildContext context, String action) {
    final bloc = context.read<GroupInfoBloc>();
    switch (action) {
      case 'promote':
        bloc.add(UpdateMemberRoleRequested(
            userId: member.userId, role: 'admin'));
      case 'demote':
        bloc.add(UpdateMemberRoleRequested(
            userId: member.userId, role: 'member'));
      case 'remove':
        bloc.add(RemoveMemberRequested(member.userId));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Danger action row (leave / delete)
// ─────────────────────────────────────────────────────────────────────────────

class _DangerAction extends StatelessWidget {
  const _DangerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.redAccent, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
