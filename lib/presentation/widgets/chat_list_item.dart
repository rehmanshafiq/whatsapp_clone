import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/chat_channel.dart';
import 'chat_avatar.dart';
import 'unread_badge.dart';

class ChatListItem extends StatelessWidget {
  final ChatChannel channel;
  final VoidCallback onTap;

  const ChatListItem({
    super.key,
    required this.channel,
    required this.onTap,
  });

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(time.year, time.month, time.day);
    final diff = today.difference(msgDate).inDays;

    if (diff == 0) {
      final period = time.hour >= 12 ? 'PM' : 'AM';
      final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final m = time.minute.toString().padLeft(2, '0');
      return '$h:$m $period';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[time.weekday - 1];
    }
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ChatAvatar(
              imageUrl: channel.avatarUrl,
              name: channel.name,
              heroTag: 'avatar_${channel.id}',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        _formatTime(channel.lastMessageTime),
                        style: TextStyle(
                          color: channel.unreadCount > 0
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (channel.unreadCount == 0 && channel.lastMessage.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.done_all, size: 16, color: AppColors.seenTick),
                        ),
                      Expanded(
                        child: Text(
                          channel.lastMessage.isEmpty
                              ? 'Tap to start chatting'
                              : channel.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: channel.lastMessage.isEmpty
                                ? AppColors.textSecondary.withValues(alpha: 0.6)
                                : AppColors.textSecondary,
                            fontSize: 14,
                            fontStyle: channel.lastMessage.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      if (channel.unreadCount > 0)
                        UnreadBadge(count: channel.unreadCount),
                    ],
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
