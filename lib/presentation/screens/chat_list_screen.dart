import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/shimmer_list.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch(ChatCubit cubit) {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        cubit.updateSearchQuery('');
      }
    });
  }

  Future<void> _logout(BuildContext context) async {
    final box = GetStorage();
    await box.erase();
    if (!mounted) return;
    context.goNamed(AppRouter.auth);
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
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onChanged: cubit.updateSearchQuery,
              )
            : const Text('WhatsApp'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search,
                color: AppColors.iconMuted),
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
                  Text(state.error!,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => cubit.loadChats(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final channels = state.filteredChannels;

          if (channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                      size: 64),
                  const SizedBox(height: 16),
                  Text(
                    state.searchQuery.isNotEmpty
                        ? 'No chats found'
                        : 'No conversations yet',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 16),
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
