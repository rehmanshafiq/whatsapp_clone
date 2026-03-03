import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

class ChatDetailScreen extends StatefulWidget {
  final String channelId;

  const ChatDetailScreen({super.key, required this.channelId});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatCubit>().loadMessages(widget.channelId);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listenWhen: (prev, curr) => prev.messages.length != curr.messages.length,
      listener: (_, _) => _scrollToBottom(),
      builder: (context, state) {
        final channel = state.selectedChannel;
        final cubit = context.read<ChatCubit>();

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) cubit.clearSelectedChannel();
          },
          child: Scaffold(
            backgroundColor: AppColors.chatBackground,
            appBar: AppBar(
              backgroundColor: AppColors.appBar,
              leadingWidth: 32,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
              ),
              title: Row(
                children: [
                  ChatAvatar(
                    imageUrl: channel?.avatarUrl,
                    name: channel?.name ?? '',
                    radius: 18,
                    heroTag: 'avatar_${widget.channelId}',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel?.name ?? 'Chat',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (state.isTyping)
                          const Text('typing...',
                              style: TextStyle(
                                  color: AppColors.accent, fontSize: 12))
                        else if (state.isOnline)
                          const Text('online',
                              style: TextStyle(
                                  color: AppColors.accent, fontSize: 12))
                        else
                          const Text('last seen recently',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.videocam, color: AppColors.iconMuted),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.call, color: AppColors.iconMuted),
                  onPressed: () {},
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.iconMuted),
                  color: AppColors.appBar,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'view_contact',
                      child: Text('View contact',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'media',
                      child: Text('Media, links, and docs',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'search',
                      child: Text('Search',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'mute',
                      child: Text('Mute notifications',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                    PopupMenuItem(
                      value: 'wallpaper',
                      child: Text('Wallpaper',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ],
            ),
            body: Stack(
              children: [
                CustomPaint(
                  painter: _ChatBackgroundPainter(),
                  size: Size.infinite,
                ),
                Column(
                  children: [
                    Expanded(
                      child: state.isLoading && state.messages.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.accent))
                          : ListView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              itemCount: state.messages.length +
                                  (state.isTyping ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == state.messages.length &&
                                    state.isTyping) {
                                  return const TypingIndicator();
                                }
                                return MessageBubble(
                                    message: state.messages[index]);
                              },
                            ),
                    ),
                    ChatInputBar(
                      onSend: (text) =>
                          cubit.sendMessage(widget.channelId, text),
                      onSendAudio: (file, duration) =>
                          cubit.sendAudioMessage(
                            widget.channelId,
                            file.path,
                            duration,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    const spacing = 30.0;
    const dotSize = 1.5;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
