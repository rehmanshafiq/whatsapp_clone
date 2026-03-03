import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../core/di/service_locator.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/user.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/contact_cubit.dart';
import '../cubit/contact_state.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/shimmer_list.dart';

class SelectContactScreen extends StatelessWidget {
  const SelectContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ContactCubit>()..loadContacts(),
      child: const _ContactScreenContent(),
    );
  }
}

class _ContactScreenContent extends StatefulWidget {
  const _ContactScreenContent();

  @override
  State<_ContactScreenContent> createState() => _ContactScreenContentState();
}

class _ContactScreenContentState extends State<_ContactScreenContent> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactCubit = context.read<ContactCubit>();

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
                    color: AppColors.textPrimary, fontSize: 17),
                decoration: const InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onChanged: contactCubit.updateSearchQuery,
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select contact',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 18)),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search,
                color: AppColors.iconMuted),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  contactCubit.updateSearchQuery('');
                }
              });
            },
          ),
        ],
      ),
      body: ResponsiveBuilder(
        builder: (context, sizingInfo) {
          final crossAxisCount =
              sizingInfo.deviceScreenType == DeviceScreenType.tablet ? 2 : 1;
          return BlocBuilder<ContactCubit, ContactState>(
            builder: (context, state) {
              if (state.isLoading) return const ShimmerChatList();

              if (state.error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(state.error!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                );
              }

              final contacts = state.filteredContacts;
              final grouped = _groupByLetter(contacts);

              return ListView(
                children: [
                  _ActionTile(
                    icon: Icons.group,
                    label: 'New group',
                    onTap: () {},
                  ),
                  _ActionTile(
                    icon: Icons.person_add,
                    label: 'New contact',
                    onTap: () {},
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  if (crossAxisCount > 1)
                    ..._buildGridSections(grouped, context)
                  else
                    ..._buildListSections(grouped, context),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<User>> _groupByLetter(List<User> contacts) {
    final map = <String, List<User>>{};
    for (final c in contacts) {
      final letter = c.name.isNotEmpty ? c.name[0].toUpperCase() : '#';
      map.putIfAbsent(letter, () => []).add(c);
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  List<Widget> _buildListSections(
      Map<String, List<User>> grouped, BuildContext context) {
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(entry.key,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ));
      for (final contact in entry.value) {
        widgets.add(_ContactTile(
          contact: contact,
          onTap: () => _openChat(context, contact),
        ));
      }
    }
    return widgets;
  }

  List<Widget> _buildGridSections(
      Map<String, List<User>> grouped, BuildContext context) {
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(entry.key,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ));
      for (int i = 0; i < entry.value.length; i += 2) {
        widgets.add(Row(
          children: [
            Expanded(
              child: _ContactTile(
                contact: entry.value[i],
                onTap: () => _openChat(context, entry.value[i]),
              ),
            ),
            if (i + 1 < entry.value.length)
              Expanded(
                child: _ContactTile(
                  contact: entry.value[i + 1],
                  onTap: () => _openChat(context, entry.value[i + 1]),
                ),
              )
            else
              const Expanded(child: SizedBox()),
          ],
        ));
      }
    }
    return widgets;
  }

  Future<void> _openChat(BuildContext context, User contact) async {
    final chatCubit = context.read<ChatCubit>();
    final channelId = await chatCubit.openOrCreateChat(contact);
    if (context.mounted) {
      context.goNamed(AppRouter.chatDetail, pathParameters: {'id': channelId});
    }
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.accent,
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(label,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 16)),
      onTap: onTap,
    );
  }
}

class _ContactTile extends StatelessWidget {
  final User contact;
  final VoidCallback onTap;

  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ChatAvatar(
        imageUrl: contact.avatarUrl,
        name: contact.name,
        radius: 22,
      ),
      title: Text(contact.name,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 16)),
      subtitle: Text(contact.about,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13)),
      onTap: onTap,
    );
  }
}
