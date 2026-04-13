import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/group_member.dart';
import '../../data/models/user_search.dart';
import '../../data/repository/chat_repository.dart';
import '../bloc/group_info/group_info_bloc.dart';
import '../cubit/chat_cubit.dart';
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
      child: BlocListener<GroupInfoBloc, GroupInfoState>(
        listenWhen: (prev, curr) {
          final cd = curr.groupDetails;
          final pd = prev.groupDetails;
          if (cd == null || pd == null) return false;
          if (pd.groupId != cd.groupId) return false;
          return cd.name != pd.name || cd.avatarUrl != pd.avatarUrl;
        },
        listener: (context, state) {
          final d = state.groupDetails!;
          context.read<ChatCubit>().applyGroupChannelPatch(
                groupId: d.groupId,
                name: d.name,
                avatarUrl: d.avatarUrl,
              );
        },
        child: BlocBuilder<GroupInfoBloc, GroupInfoState>(
          builder: (context, state) {
            return Scaffold(
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
          );
          },
        ),
      ),
    );
  }
}

void _showEditGroupDialog(BuildContext context, GroupInfoState state) {
  final details = state.groupDetails;
  if (details == null) return;
  final bloc = context.read<GroupInfoBloc>();
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => _EditGroupDialog(
      bloc: bloc,
      initialName: details.name,
      initialDescription: details.description,
    ),
  );
}

void _showAddMembersDialog(BuildContext context, GroupInfoState state) {
  final existing = state.members.map((m) => m.userId).toSet();
  final bloc = context.read<GroupInfoBloc>();
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => _AddMembersDialog(
      bloc: bloc,
      repository: getIt<ChatRepository>(),
      existingUserIds: existing,
    ),
  );
}

bool _isUuid(String s) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(s.trim());
}

class _AddMembersDialog extends StatefulWidget {
  const _AddMembersDialog({
    required this.bloc,
    required this.repository,
    required this.existingUserIds,
  });

  final GroupInfoBloc bloc;
  final ChatRepository repository;
  final Set<String> existingUserIds;

  @override
  State<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<_AddMembersDialog> {
  final _searchController = TextEditingController();
  final _pasteController = TextEditingController();
  Timer? _debounce;
  List<UserSearchResult> _results = [];
  final Set<String> _selectedIds = {};
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = [];
        _searchError = null;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 400), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final list = await widget.repository.searchUsers(query);
      if (!mounted) return;
      setState(() {
        // Show every API match. Users already in the group stay visible but are
        // not selectable (otherwise the list looks empty while the network
        // succeeded — same as web "Find" showing the row).
        _results = list;
        _searching = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.message;
        _results = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = e.toString();
        _results = [];
      });
    }
  }

  void _toggleSelected(String userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
      } else {
        _selectedIds.add(userId);
      }
    });
  }

  void _addPasteIdsToSelection() {
    final raw = _pasteController.text;
    final parts =
        raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    final valid = <String>[];
    final invalid = <String>[];
    for (final p in parts) {
      if (_isUuid(p)) {
        if (!widget.existingUserIds.contains(p)) {
          valid.add(p.trim());
        }
      } else {
        invalid.add(p);
      }
    }
    if (invalid.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Use search for names, or paste UUIDs only. Not valid: ${invalid.join(", ")}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    if (valid.isEmpty) return;
    setState(() => _selectedIds.addAll(valid));
  }

  void _submit() {
    if (_selectedIds.isEmpty) return;
    Navigator.of(context).pop();
    widget.bloc.add(AddMembersRequested(_selectedIds.toList()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.appBar,
      title: const Text('Add members',
          style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        height: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search by username',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon:
                    Icon(Icons.search, color: AppColors.iconMuted, size: 22),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.divider)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            // if (_searchError != null)
            //   Padding(
            //     padding: const EdgeInsets.only(top: 8),
            //     child: Text(
            //       _searchError!,
            //       style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            //     ),
            //   ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _searchController.text.trim().length < 2
                      ? 'Type user names to search'
                      : 'No users found',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final u = _results[i];
                  final alreadyMember =
                  widget.existingUserIds.contains(u.userId);
                  final checked = _selectedIds.contains(u.userId);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: alreadyMember
                        ? null
                        : (_) => _toggleSelected(u.userId),
                    title: Text(
                      u.displayName,
                      style: TextStyle(
                        color: alreadyMember
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      alreadyMember
                          ? '@${u.username} · Already in this group'
                          : '@${u.username}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),

          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _selectedIds.isEmpty ? null : _submit,
          child: Text(
            'Add${_selectedIds.isEmpty ? "" : " (${_selectedIds.length})"}',
            style: TextStyle(
              color: _selectedIds.isEmpty
                  ? AppColors.textSecondary
                  : AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
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

List<GroupMember> _filterMembersLocal(
  List<GroupMember> members,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return members;
  return members
      .where((m) {
        final name = m.displayName.toLowerCase();
        final user = m.username.toLowerCase();
        final id = m.userId.toLowerCase();
        return name.contains(q) || user.contains(q) || id.contains(q);
      })
      .toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final TextEditingController _memberSearchController = TextEditingController();

  @override
  void dispose() {
    _memberSearchController.dispose();
    super.dispose();
  }

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

        return Column(
          children: [
            if (state.isUpdating)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: AppColors.divider,
              ),
            Expanded(
              child: ListView(
                children: [
                  const SizedBox(height: 24),
                  _GroupHeader(
                    name: details.name,
                    avatarUrl: details.avatarUrl,
                    memberCount: state.members.length,
                    canManage: state.canManageMembers,
                    onEditTap: state.canManageMembers
                        ? () => _showEditGroupDialog(context, state)
                        : null,
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: AppColors.divider, height: 1),

                  if (state.canManageMembers ||
                      details.description.isNotEmpty) ...[
                    InkWell(
                      onTap: state.canManageMembers
                          ? () => _showEditGroupDialog(context, state)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Description',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                if (state.canManageMembers) ...[
                                  const Spacer(),
                                  Text(
                                    'Tap to edit',
                                    style: TextStyle(
                                      color: AppColors.accent.withValues(
                                          alpha: 0.85),
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              details.description.isEmpty
                                  ? 'Add group description'
                                  : details.description,
                              style: TextStyle(
                                color: details.description.isEmpty &&
                                        state.canManageMembers
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                                fontSize: 15,
                                fontStyle: details.description.isEmpty &&
                                        state.canManageMembers
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                  ],

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      'Members (${state.members.length})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _memberSearchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search members',
                        hintStyle: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 15),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.iconMuted, size: 22),
                        suffixIcon: _memberSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: AppColors.iconMuted, size: 20),
                                onPressed: () {
                                  _memberSearchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.appBar,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.accent),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 10),
                      ),
                    ),
                  ),

                  if (state.canManageMembers)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.accent.withValues(alpha: 0.15),
                        child: const Icon(Icons.person_add,
                            color: AppColors.accent, size: 22),
                      ),
                      title: const Text(
                        'Add members',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: const Text(
                        'Search by username or paste UUIDs',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      onTap: () => _showAddMembersDialog(context, state),
                    ),

                  ...() {
                    final filtered = _filterMembersLocal(
                      state.members,
                      _memberSearchController.text,
                    );
                    if (filtered.isEmpty &&
                        _memberSearchController.text.trim().isNotEmpty) {
                      return [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          child: Text(
                            'No members match your search',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                  alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ];
                    }
                    return filtered
                        .map(
                          (member) => _MemberTile(
                            member: member,
                            youAreOwner: state.isOwner,
                            youAreAdmin: state.isAdmin,
                            currentUserId: state.currentUserId,
                          ),
                        )
                        .toList();
                  }(),

                  const SizedBox(height: 16),
                  const Divider(color: AppColors.divider, height: 1),

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
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit group (name + description)
// ─────────────────────────────────────────────────────────────────────────────

class _EditGroupDialog extends StatefulWidget {
  const _EditGroupDialog({
    required this.bloc,
    required this.initialName,
    required this.initialDescription,
  });

  final GroupInfoBloc bloc;
  final String initialName;
  final String initialDescription;

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.appBar,
      title: const Text('Edit group',
          style: TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Group name',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.divider)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
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
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final desc = _descController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop();
            widget.bloc.add(UpdateGroup(
                  name: name,
                  description: desc,
                ));
          },
          child: const Text('Save', style: TextStyle(color: AppColors.accent)),
        ),
      ],
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
    required this.canManage,
    this.onEditTap,
  });

  final String name;
  final String avatarUrl;
  final int memberCount;
  final bool canManage;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ChatAvatar(
            imageUrl: avatarUrl,
            name: name,
            radius: 48,
            isGroup: true,
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: canManage ? onEditTap : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.edit,
                      size: 18, color: AppColors.textSecondary),
                ],
              ],
            ),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Member tile – avatar, name, role badge, actions
// ─────────────────────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.youAreOwner,
    required this.youAreAdmin,
    required this.currentUserId,
  });

  final GroupMember member;
  final bool youAreOwner;
  final bool youAreAdmin;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final isSelf = member.userId == currentUserId;
    final showMenu = !isSelf &&
        !member.isOwner &&
        (youAreOwner || (youAreAdmin && member.isMember));

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
      trailing: showMenu
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.iconMuted),
              color: AppColors.appBar,
              onSelected: (action) => _handleMemberAction(context, action),
              itemBuilder: (ctx) {
                final items = <PopupMenuEntry<String>>[];
                if (youAreOwner) {
                  items.add(
                    PopupMenuItem(
                      value: member.isAdmin ? 'demote' : 'promote',
                      child: Text(
                        member.isAdmin
                            ? 'Dismiss as admin'
                            : 'Make group admin',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  );
                }
                if (youAreOwner || (youAreAdmin && member.isMember)) {
                  items.add(
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove from group',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  );
                }
                return items;
              },
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
        break;
      case 'demote':
        bloc.add(UpdateMemberRoleRequested(
            userId: member.userId, role: 'member'));
        break;
      case 'remove':
        bloc.add(RemoveMemberRequested(member.userId));
        break;
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
