import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message.dart';
import '../cubit/chat_cubit.dart';

class MessageActionSheet extends StatelessWidget {
  final Message message;

  const MessageActionSheet({
    super.key,
    required this.message,
  });

  static Future<void> show(BuildContext context, Message message) {
    final cubit = context.read<ChatCubit>();
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.appBar,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: MessageActionSheet(message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16, top: 8),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Header / Message Preview
            _buildMessagePreview(context),
            
            const SizedBox(height: 8),
            Divider(color: AppColors.divider.withValues(alpha: 0.5), height: 1),
            const SizedBox(height: 16),
            
            // Action Buttons
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ActionButton(
                    icon: Icons.reply,
                    label: 'Reply',
                    onTap: () {
                      final cubit = context.read<ChatCubit>();
                      cubit.startReplyTo(message);
                      Navigator.pop(context);
                    },
                  ),
                  _ActionButton(
                    icon: Icons.forward,
                    label: 'Forward',
                    onTap: () {
                      Navigator.pop(context);
                      _handleForward(context);
                    },
                  ),
                  _ActionButton(
                    icon: Icons.copy,
                    label: 'Copy',
                    onTap: () async {
                      Navigator.pop(context);
                      await context.read<ChatCubit>().copyMessageToClipboard(message);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message copied')),
                        );
                      }
                    },
                  ),
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(context);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildMessagePreview(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    String senderName = 'Sender';
    final isOutgoing = message.isOutgoing;
    
    if (isOutgoing) {
      senderName = 'You';
    } else {
      try {
        final channel = cubit.state.channels.firstWhere((c) => c.id == message.channelId);
        senderName = channel.name;
      } catch (_) {
        senderName = message.contactName ?? 'Sender';
      }
    }

    String previewText = message.text;
    IconData? mediaIcon;

    if (message.isImage) {
      previewText = 'Photo';
      mediaIcon = Icons.image;
    } else if (message.isVideo) {
      previewText = 'Video';
      mediaIcon = Icons.videocam;
    } else if (message.isAudio) {
      previewText = 'Voice message';
      mediaIcon = Icons.mic;
    } else if (message.isDocument) {
      previewText = message.documentFileName ?? 'Document';
      mediaIcon = Icons.insert_drive_file;
    } else if (message.isLocation) {
      previewText = 'Location';
      mediaIcon = Icons.location_on;
    } else if (message.isContact) {
      previewText = 'Contact';
      mediaIcon = Icons.person;
    } else if (message.isGif) {
      previewText = 'GIF';
      mediaIcon = Icons.gif;
    } else if (message.isSticker) {
      previewText = 'Sticker';
      mediaIcon = Icons.sticky_note_2;
    }

    if (message.text.isNotEmpty && mediaIcon != null) {
      previewText = '${message.text}   $previewText';
    } else if (message.text.isNotEmpty) {
      previewText = message.text;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    color: isOutgoing ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (mediaIcon != null) ...[
                      Icon(mediaIcon, size: 16, color: AppColors.iconMuted),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        previewText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppColors.iconMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    if (!message.isOutgoing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only delete your own messages')),
      );
      return;
    }
    
    final cubit = context.read<ChatCubit>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.appBar,
        title: const Text('Delete message?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to delete this message?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cubit.deleteMessage(message);
            },
            child: const Text('Delete for me', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForward(BuildContext context) async {
    final cubit = context.read<ChatCubit>();
    final channels = cubit.state.channels
        .where((c) => c.id != message.channelId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      
    if (channels.isEmpty) return;

    final selected = <String>{};
    final channelIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.72,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Forward to...',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${selected.length} selected',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: channels.length,
                        separatorBuilder: (_, __) => Divider(
                          color: AppColors.divider.withValues(alpha: 0.5),
                          height: 1,
                          indent: 76,
                        ),
                        itemBuilder: (_, index) {
                          final channel = channels[index];
                          final checked = selected.contains(channel.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (_) {
                              setModalState(() {
                                if (checked) {
                                  selected.remove(channel.id);
                                } else {
                                  selected.add(channel.id);
                                }
                              });
                            },
                            title: Text(
                              channel.name,
                              style: const TextStyle(color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              channel.lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            activeColor: AppColors.accent,
                            checkColor: Colors.white,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  Navigator.of(ctx).pop(selected.toList());
                                },
                          icon: const Icon(Icons.forward),
                          label: const Text('Forward'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (channelIds == null || channelIds.isEmpty) return;
    
    await cubit.forwardMessageToChannels(message, channelIds);
    if (!context.mounted) return;
    final label = channelIds.length == 1
        ? 'Forwarded to 1 chat'
        : 'Forwarded to ${channelIds.length} chats';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(icon, color: effectiveColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
