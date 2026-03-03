import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../model/chat_channel.dart';

class ChatListItem extends StatelessWidget {
  final ChatChannel channel;

  const ChatListItem({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Row(
        children: [
          _Avatar(imageUrl: channel.imageUrl, name: channel.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      channel.time,
                      style: TextStyle(
                        color: channel.unreadCount > 0
                            ? const Color(0xFF25D366)
                            : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (channel.isDelivered)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.done_all,
                          size: 16,
                          color: Color(0xFF53BDEB),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        channel.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (channel.unreadCount > 0)
                      _UnreadBadge(count: channel.unreadCount),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? imageUrl;
  final String name;

  const _Avatar({this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (context, url) => _PlaceholderAvatar(name: name),
          errorWidget: (context, url, error) => _PlaceholderAvatar(name: name),
        ),
      );
    }
    return _PlaceholderAvatar(name: name);
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  final String name;

  const _PlaceholderAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFF2A3942),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      child: Center(
        child: Text(
          count > 99 ? '99+' : count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}