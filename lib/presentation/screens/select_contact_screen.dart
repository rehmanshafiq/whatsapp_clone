import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user_search.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_avatar.dart';

class SelectContactScreen extends StatefulWidget {
  const SelectContactScreen({super.key});

  @override
  State<SelectContactScreen> createState() => _SelectContactScreenState();
}

class _SelectContactScreenState extends State<SelectContactScreen> {
  bool _isSearching = true;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.goNamed(AppRouter.chats),
        ),
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
            : const Text(
                'Select contact',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.iconMuted,
            ),
            onPressed: () => _toggleSearch(cubit),
          ),
        ],
      ),
      body: BlocBuilder<ChatCubit, ChatState>(
        buildWhen: (previous, current) {
          if (previous.searchQuery != current.searchQuery) return true;
          if (previous.userSearchResults != current.userSearchResults) {
            return true;
          }
          if (previous.isUserSearchLoading != current.isUserSearchLoading) {
            return true;
          }
          if (previous.userSearchError != current.userSearchError) return true;
          return false;
        },
        builder: (context, state) {
          final hasQuery = _searchController.text.trim().isNotEmpty;
          final searchResults = state.userSearchResults;

          if (!_isSearching || !hasQuery) {
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
                    'Search for a contact to start chatting',
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
            itemCount: searchResults.length,
            separatorBuilder: (context, index) => const Divider(
              color: AppColors.divider,
              height: 1,
              indent: 76,
            ),
            itemBuilder: (context, index) {
              final UserSearchResult user = searchResults[index];
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
        },
      ),
    );
  }
}
