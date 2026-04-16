import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/chat_channel.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository/auth_repository.dart';
import '../bloc/bottom_navigation/bottom_navigation_bloc.dart';
import '../bloc/bottom_navigation/bottom_navigation_event.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/shimmer_list.dart';
import '../widgets/chat_avatar.dart';
import 'blocked_users_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSearching = false;
  String _localSearchQuery = '';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkSessionAndLoadChats();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  late final _ChatListLifecycleObserver _lifecycleObserver =
      _ChatListLifecycleObserver(() async {
        await getIt<AuthRepository>().validateOrLogoutExpiredSession();
      });

  Future<void> _checkSessionAndLoadChats() async {
    await getIt<AuthRepository>().validateOrLogoutExpiredSession();
    if (!mounted) return;
    if (!getIt<AuthRepository>().isAuthenticated) {
      context.goNamed(AppRouter.auth);
      return;
    }
    final cubit = context.read<ChatCubit>();
    await cubit.loadChats();
    // Load current user's profile so AppBar avatar can be shown.
    // Errors are handled silently inside the cubit.
    await cubit.loadCurrentUserProfile();
  }

  void _toggleSearch(ChatCubit cubit) {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _localSearchQuery = '';
      }
    });
  }

  void _onSearchChanged(ChatCubit cubit, String value) {
    setState(() {
      _localSearchQuery = value;
    });
  }

  Future<void> _logout(BuildContext context) async {
    await getIt<AuthRepository>().logout();
    if (!context.mounted) return;
    context.goNamed(AppRouter.auth);
  }

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

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.appBar,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onChanged: (value) => _onSearchChanged(cubit, value),
              )
            : BlocBuilder<ChatCubit, ChatState>(
                buildWhen: (previous, current) =>
                    previous.currentUserProfile != current.currentUserProfile,
                builder: (context, state) {
                  final profile = state.currentUserProfile;
                  final displayName = (profile?.displayName.isNotEmpty == true)
                      ? profile!.displayName
                      : 'You';
                  final avatarUrl = profile?.avatarUrl;

                  return Row(
                    children: [
                      const Text(
                        'WhatsApp',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                },
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.iconMuted,
            ),
            onPressed: () => _toggleSearch(cubit),
          ),
          IconButton(
            icon: const Icon(Icons.block, color: AppColors.iconMuted),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BlockedUsersScreen(),
                ),
              );
            },
            tooltip: 'Blocked users',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.iconMuted),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: BlocBuilder<ChatCubit, ChatState>(
        buildWhen: (previous, current) {
          if (previous.isLoading != current.isLoading) return true;
          if (previous.error != current.error) return true;
          // Equatable equality on lists inside ChatState will trigger build
          if (previous.channels != current.channels) return true;
          return false;
        },
        builder: (context, state) {
          if (state.isLoading && state.channels.isEmpty) {
            return const ShimmerChatList();
          }

          if (state.error != null && state.channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(state.error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => cubit.loadChats(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Filter channels locally instead of using the shared cubit searchQuery
          final channels = _localSearchQuery.isEmpty
              ? state.channels
              : state.channels.where((c) {
                  final query = _localSearchQuery.toLowerCase();
                  return c.name.toLowerCase().contains(query) ||
                      c.lastMessage.toLowerCase().contains(query);
                }).toList();

          if (channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    color: AppColors.textSecondary.withValues(alpha: 0.4),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _localSearchQuery.isNotEmpty
                        ? 'No chats found'
                        : 'No conversations yet',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: cubit.loadChats,
            color: AppColors.accent,
            backgroundColor: AppColors.appBar,
            child: ListView.separated(
              itemCount: channels.length,
              separatorBuilder: (_, _) => const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 76,
              ),
              itemBuilder: (context, index) {
                final channel = channels[index];
                return ChatListItem(
                  channel: channel,
                  onTap: () {
                    context.goNamed(
                      AppRouter.chatDetail,
                      pathParameters: {'id': channel.id},
                    );
                  },
                  onLongPress: () => _showChatActionSheet(context, channel),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => context.goNamed(AppRouter.contacts),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Long-press action sheet
  // ---------------------------------------------------------------------------

  void _showChatActionSheet(BuildContext ctx, ChatChannel channel) {
    final cubit = ctx.read<ChatCubit>();

    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mute / Unmute
                ListTile(
                  leading: Icon(
                    channel.isMuted
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                    color: AppColors.textPrimary,
                  ),
                  title: Text(
                    channel.isMuted ? 'Unmute' : 'Mute',
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleToggleMute(ctx, cubit, channel);
                  },
                ),
                // Clear chat
                ListTile(
                  leading: const Icon(
                    Icons.cleaning_services_outlined,
                    color: AppColors.textPrimary,
                  ),
                  title: const Text(
                    'Clear chat',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmClearChat(ctx, cubit, channel);
                  },
                ),
                // Block user
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.redAccent),
                  title: const Text(
                    'Block',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmBlockUser(ctx, cubit, channel);
                  },
                ),
                // Delete conversation
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Delete conversation',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteConversation(ctx, cubit, channel);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleToggleMute(
    BuildContext ctx,
    ChatCubit cubit,
    ChatChannel channel,
  ) async {
    try {
      await cubit.toggleMute(channel.id);
      if (!ctx.mounted) return;
      final newState = channel.isMuted ? 'unmuted' : 'muted';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Chat $newState', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),),
          backgroundColor: AppColors.appBar,
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle mute: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmClearChat(
    BuildContext ctx,
    ChatCubit cubit,
    ChatChannel channel,
  ) {
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.appBar,
        title: const Text(
          'Clear chat',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Clear all messages with ${channel.name}? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _executeClearChat(ctx, cubit, channel.id);
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeClearChat(
    BuildContext ctx,
    ChatCubit cubit,
    String conversationId,
  ) async {
    try {
      await cubit.clearChat(conversationId);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            'Chat cleared', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500,),
          ),
          backgroundColor: AppColors.appBar,
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Failed to clear chat: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmDeleteConversation(
    BuildContext ctx,
    ChatCubit cubit,
    ChatChannel channel,
  ) {
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.appBar,
        title: const Text(
          'Delete conversation',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete conversation with ${channel.name}? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _executeDeleteConversation(ctx, cubit, channel.id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteConversation(
    BuildContext ctx,
    ChatCubit cubit,
    String conversationId,
  ) async {
    try {
      await cubit.deleteConversation(conversationId);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Conversation deleted', style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),),
          backgroundColor: AppColors.appBar,
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Failed to delete conversation: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _confirmBlockUser(
    BuildContext ctx,
    ChatCubit cubit,
    ChatChannel channel,
  ) {
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.appBar,
        title: const Text(
          'Block user',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Block ${channel.name}? You and this user will no longer be able to message each other.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _executeBlockUser(ctx, cubit, channel);
            },
            child: const Text(
              'Block',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeBlockUser(
    BuildContext ctx,
    ChatCubit cubit,
    ChatChannel channel,
  ) async {
    final userId = channel.peerUserId;
    if (userId == null || userId.isEmpty) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Unable to block this user right now'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      await cubit.blockUser(userId);
      await cubit.loadChats();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('${channel.name} blocked',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
          ),),
          backgroundColor: AppColors.appBar,
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Failed to block user: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

class _ChatListLifecycleObserver extends WidgetsBindingObserver {
  _ChatListLifecycleObserver(this.onResumed);

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
