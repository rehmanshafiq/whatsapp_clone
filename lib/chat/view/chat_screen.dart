import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import 'widgets/chat_list_item.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatCubit()..loadChannels(),
      child: const _ChatScreenContent(),
    );
  }
}

class _ChatScreenContent extends StatelessWidget {
  const _ChatScreenContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111B21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C33),
        elevation: 0,
        title: const Text(
          'WhatsApp',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1F2C33),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_group',
                child: Text('New group', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'starred',
                child: Text('Starred messages', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Settings', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: BlocBuilder<ChatCubit, ChatState>(
        builder: (context, state) {
          if (state is ChatLoading || state is ChatInitial) {
            return const _ShimmerList();
          }
          if (state is ChatLoaded) {
            return ListView.separated(
              itemCount: state.channels.length,
              separatorBuilder: (context, index) => const Divider(
                color: Color(0xFF1F2C33),
                height: 1,
                indent: 76,
              ),
              itemBuilder: (context, index) {
                return ChatListItem(channel: state.channels[index]);
              },
            );
          }
          if (state is ChatError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 10,
      separatorBuilder: (context, index) => const Divider(
        color: Color(0xFF1F2C33),
        height: 1,
        indent: 76,
      ),
      itemBuilder: (context, index) => const _ShimmerItem(),
    );
  }
}

class _ShimmerItem extends StatelessWidget {
  const _ShimmerItem();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1F2C33),
      highlightColor: const Color(0xFF2A3942),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFF2A3942),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 140,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3942),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3942),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}