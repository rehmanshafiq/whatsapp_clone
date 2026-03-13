import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository/auth_repository.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/shimmer_list.dart';
import '../widgets/chat_avatar.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<ChatCubit>();
      cubit.loadChats();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch(ChatCubit cubit) {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        cubit.updateSearchQuery('');
        _searchDebounce?.cancel();
      }
    });
  }

  void _onSearchChanged(ChatCubit cubit, String value) {
    cubit.updateSearchQuery(value);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final query = _searchController.text.trim();
      if (query.isEmpty) {
        cubit.searchUsers('');
      } else {
        cubit.searchUsers(query);
      }
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
        return 'Last seen on ${dt.day}/${dt.month}/${dt.year} at $time';
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
            : const Text('WhatsApp'),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.iconMuted,
            ),
            onPressed: () => _toggleSearch(cubit),
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
          if (previous.searchQuery != current.searchQuery) return true;
          if (previous.userSearchResults != current.userSearchResults) return true;
          if (previous.isUserSearchLoading != current.isUserSearchLoading) return true;
          if (previous.userSearchError != current.userSearchError) return true;
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

          if (_isSearching && _searchController.text.trim().isNotEmpty) {
            final searchResults = state.userSearchResults;

            if (state.isUserSearchLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }

            if (state.userSearchError != null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.userSearchError!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (searchResults.isEmpty) {
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
              itemCount: searchResults.length,
              separatorBuilder: (context, index) => const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 76,
              ),
              itemBuilder: (context, index) {
                final user = searchResults[index];
                final presence = _buildPresenceSubtitle(
                  status: user.presenceStatus,
                  lastSeen: user.lastSeen,
                );
                return ListTile(
                  leading: ChatAvatar(
                    imageUrl: user.avatarUrl,
                    name: user.displayName,
                    radius: 24,
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
                        (user.statusText?.isNotEmpty == true
                            ? user.statusText!
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  onTap: () async {
                    final chatCubit = context.read<ChatCubit>();
                    try {
                      final channel = await chatCubit.repository
                          .createOrGetConversationForUser(user);
                      if (!context.mounted) return;
                      context.goNamed(
                        AppRouter.chatDetail,
                        pathParameters: {'id': channel.id},
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                    }
                  },
                );
              },
            );
          }

          final channels = state.filteredChannels;

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
                    state.searchQuery.isNotEmpty
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
}
