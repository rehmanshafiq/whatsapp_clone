import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/chat_channel.dart';
import '../../data/models/message_status.dart';
import 'chat_avatar.dart';
import 'unread_badge.dart';

class ChatListItem extends StatelessWidget {
  final ChatChannel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ChatListItem({
    super.key,
    required this.channel,
    required this.onTap,
    this.onLongPress,
  });

  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  String _displayName() {
    if (channel.name.trim().isNotEmpty) return _capitalizeName(channel.name);
    if (channel.isGroup) return 'Group';
    return 'Chat';
  }

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

  Widget _buildStatusIcon(MessageStatus? status) {
    if (status == null) return const SizedBox();
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary);
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 16, color: AppColors.textSecondary);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 16, color: AppColors.textSecondary);
      case MessageStatus.seen:
        return const Icon(Icons.done_all, size: 16, color: AppColors.seenTick);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showUnreadBadge = channel.unreadCount > 0 && !channel.isMuted;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ChatAvatar(
              imageUrl: channel.avatarUrl,
              name: _displayName(),
              heroTag: 'avatar_${channel.id}',
              isGroup: channel.isGroup,
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
                          _displayName(),
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
                      if (channel.lastMessageSenderId == AppConstants.currentUserId && channel.lastMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildStatusIcon(channel.lastMessageStatus),
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
                      if (showUnreadBadge)
                        UnreadBadge(count: channel.unreadCount),
                      if (channel.isMuted)
                        Padding(
                          padding: EdgeInsets.only(left: showUnreadBadge ? 6 : 0),
                          child: const Icon(
                            Icons.volume_off,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
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
