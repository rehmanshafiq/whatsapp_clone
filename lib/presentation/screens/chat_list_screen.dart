import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/chat_channel.dart';
import '../../data/models/user_search.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository/auth_repository.dart';
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

                  return GestureDetector(
                    onTap: profile == null
                        ? null
                        : () => _showEditProfileDialog(
                              context.read<ChatCubit>(),
                              profile,
                            ),
                    child: Row(
                      children: [
                        ChatAvatar(
                          imageUrl: avatarUrl,
                          name: displayName,
                          radius: 18,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'WhatsApp',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

  Future<void> _showEditProfileDialog(
    ChatCubit cubit,
    UserSearchResult profile,
  ) async {
    final rootContext = context;

    final displayNameController =
        TextEditingController(text: profile.displayName);
    final statusController =
        TextEditingController(text: profile.statusText ?? '');

    String selectedAvatarUrl = profile.avatarUrl;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.appBar,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> handleSave() async {
              if (isSaving) return;
              setState(() {
                isSaving = true;
              });
              try {
                await cubit.updateCurrentUserProfile(
                  displayName: displayNameController.text.trim(),
                  statusText: statusController.text.trim(),
                  avatarUrl: selectedAvatarUrl,
                );
                if (Navigator.of(bottomSheetContext).canPop()) {
                  Navigator.of(bottomSheetContext).pop();
                }
              } catch (_) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(
                    content: Text('Profile update failed'),
                  ),
                );
              } finally {
                setState(() {
                  isSaving = false;
                });
              }
            }

            final avatarOptions = <String>[
              if (profile.avatarUrl.isNotEmpty) profile.avatarUrl,
              ...AppConstants.placeholderAvatars,
            ].toSet().toList();

            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.iconMuted,
                          ),
                          onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ChatAvatar(
                        imageUrl: selectedAvatarUrl,
                        name: profile.displayName,
                        radius: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: avatarOptions.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          if (index == avatarOptions.length) {
                            return GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Avatar upload not implemented'),
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
                          final isSelected = option == selectedAvatarUrl;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedAvatarUrl = option;
                              });
                            },
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
                    _buildProfileTextField(
                      label: 'Display Name',
                      controller: displayNameController,
                      enabled: true,
                    ),
                    const SizedBox(height: 12),
                    _buildProfileTextField(
                      label: 'Status',
                      controller: statusController,
                      enabled: true,
                    ),
                    const SizedBox(height: 12),
                    _buildProfileTextField(
                      label: 'Username (cannot be changed)',
                      controller:
                          TextEditingController(text: profile.username),
                      enabled: false,
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: handleSave,
                        child: const Text(
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
        );
      },
    );
  }

  Widget _buildProfileTextField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
  }) {
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
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
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
          ),
        ),
      ],
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
