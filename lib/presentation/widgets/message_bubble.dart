import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message.dart';
import '../cubit/chat_cubit.dart';
import 'audio_message_bubble.dart';
import 'emoji_reaction_overlay.dart';
import 'message_status_icon.dart';

class MessageBubble extends StatefulWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  Future<void> _showReactions() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final size = box.size;
    final messageRect = topLeft & size;

    if (!mounted) return;
    final result = await showReactionPicker(
      context: context,
      messageRect: messageRect,
      isOutgoing: widget.message.isOutgoing,
    );

    if (!mounted) return;
    await handleReactionResult(
      context: context,
      result: result,
      onReact: (emoji) {
        context.read<ChatCubit>().reactToMessage(widget.message.id, emoji);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReactions = widget.message.reactions.isNotEmpty;
    final child = widget.message.isAudio
        ? AudioMessageBubble(message: widget.message)
        : _TextMessageBubble(message: widget.message);

    return Padding(
      padding: EdgeInsets.only(bottom: hasReactions ? 12 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onLongPress: _showReactions,
            child: child,
          ),
          if (hasReactions)
            Positioned(
              bottom: -10,
              right: widget.message.isOutgoing ? 20 : null,
              left: widget.message.isOutgoing ? null : 20,
              child: _ReactionBadge(reactions: widget.message.reactions),
            ),
        ],
      ),
    );
  }
}

class _ReactionBadge extends StatelessWidget {
  final Map<String, List<String>> reactions;

  const _ReactionBadge({required this.reactions});

  @override
  Widget build(BuildContext context) {
    final totalCount =
        reactions.values.fold<int>(0, (sum, list) => sum + list.length);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.appBar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.chatBackground,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...reactions.keys.map(
            (emoji) => Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          if (totalCount > 1) ...[
            const SizedBox(width: 2),
            Text(
              '$totalCount',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TextMessageBubble extends StatelessWidget {
  final Message message;

  const _TextMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final time =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isOutgoing ? 64 : 8,
          right: isOutgoing ? 8 : 64,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isOutgoing ? AppColors.outgoingBubble : AppColors.incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
            bottomRight: Radius.circular(isOutgoing ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  MessageStatusIcon(status: message.status, size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
