import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_search.dart';
import '../cubit/chat_cubit.dart';
import '../widgets/chat_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  bool _isLoading = true;
  String? _error;
  List<UserSearchResult> _blockedUsers = const <UserSearchResult>[];

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final users = await context.read<ChatCubit>().getBlockedUsers();
      if (!mounted) return;
      setState(() {
        _blockedUsers = users;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load blocked users: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleUnblock(UserSearchResult user) async {
    final cubit = context.read<ChatCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.appBar,
        title: const Text(
          'Unblock user',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Unblock ${user.displayName}? You can chat with this user again.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Unblock',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await cubit.unblockUser(user.userId);
      // Keep the main chat list consistent when user navigates back.
      await cubit.loadChats();
      if (!mounted) return;
      setState(() {
        _blockedUsers =
            _blockedUsers.where((u) => u.userId != user.userId).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${user.displayName} unblocked'),
          backgroundColor: AppColors.appBar,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to unblock user: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.appBar,
        title: const Text('Blocked users'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadBlockedUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_blockedUsers.isEmpty) {
      return const Center(
        child: Text(
          'No blocked users',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      color: AppColors.accent,
      backgroundColor: AppColors.appBar,
      child: ListView.separated(
        itemCount: _blockedUsers.length,
        separatorBuilder: (_, _) =>
            const Divider(color: AppColors.divider, height: 1, indent: 76),
        itemBuilder: (context, index) {
          final user = _blockedUsers[index];
          return ListTile(
            leading: _buildAvatar(user),
            title: Text(
              user.displayName,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: Text(
              '@${user.username}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: TextButton(
              onPressed: () => _handleUnblock(user),
              child: const Text('Unblock'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(UserSearchResult user) {
    return ChatAvatar(
      imageUrl: user.avatarUrl,
      name: user.displayName.isNotEmpty ? user.displayName : user.username,
      radius: 22,
    );
  }
}
