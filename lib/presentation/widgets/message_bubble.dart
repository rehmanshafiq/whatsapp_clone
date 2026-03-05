import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message.dart';
import '../cubit/chat_cubit.dart';
import 'audio_message_bubble.dart';
import 'message_status_icon.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final ReactionsController reactionsController;
  final VoidCallback? onReactionChanged;

  const MessageBubble({
    super.key,
    required this.message,
    required this.reactionsController,
    this.onReactionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = message.isAudio
        ? AudioMessageBubble(message: message)
        : _TextMessageBubble(message: message);

    return ChatMessageWrapper(
      messageId: message.id,
      controller: reactionsController,
      alignment:
          message.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      config: ChatReactionsConfig(
        availableReactions: const ['👍', '❤️', '😂', '😮', '😢', '🙏', '➕'],
        enableHapticFeedback: true,
        showContextMenu: false,
        dialogBackgroundColor: AppColors.appBar,
      ),
      onReactionAdded: (reaction) {
        reactionsController.addReaction(message.id, reaction);
        context.read<ChatCubit>().reactToMessage(message.id, reaction);
        onReactionChanged?.call();
      },
      onReactionRemoved: (reaction) {
        reactionsController.removeReaction(message.id, reaction);
        context.read<ChatCubit>().reactToMessage(message.id, reaction);
        onReactionChanged?.call();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            message.isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          if (message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: message.isOutgoing ? 64 : 8,
                right: message.isOutgoing ? 8 : 64,
                top: 2,
              ),
              child: _ReactionRow(reactions: message.reactions),
            ),
        ],
      ),
    );
  }
}

/// Renders reaction emojis below the message bubble (WhatsApp-style).
/// Uses [message.reactions] as single source of truth so UI updates when cubit emits.
class _ReactionRow extends StatelessWidget {
  final Map<String, List<String>> reactions;

  const _ReactionRow({required this.reactions});

  @override
  Widget build(BuildContext context) {
    final totalCount =
        reactions.values.fold<int>(0, (sum, list) => sum + list.length);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            (emoji) => Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
          if (totalCount > 1) ...[
            const SizedBox(width: 4),
            Text(
              '$totalCount',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
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
    final period = message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = message.timestamp.hour % 12;
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:${message.timestamp.minute.toString().padLeft(2, '0')} $period';

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
