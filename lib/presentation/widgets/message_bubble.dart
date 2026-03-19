import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/message.dart';
import '../cubit/chat_cubit.dart';
import 'audio_message_bubble.dart';
import 'document_message_bubble.dart';
import 'location_message_bubble.dart';
import 'message_status_icon.dart';

/// Display text for message body. "message deleted" -> "This message was deleted".
String _messageDisplayText(String body) =>
    body == 'message deleted' ? 'This message was deleted' : body;

/// True when body indicates a deleted message (show in italic).
bool _isDeletedMessage(String body) => body == 'message deleted';

/// View-once image is considered expired 60 seconds after opening.
bool _isViewOnceExpired(DateTime? viewOnceOpenedAt) {
  if (viewOnceOpenedAt == null) return false;
  return viewOnceOpenedAt.add(const Duration(seconds: 60)).isBefore(DateTime.now());
}

/// Backend may return server-relative media URLs like `/uploads/...`.
/// Only prepend baseUrl for those; leave local absolute paths (e.g. /data/... on Android) unchanged.
String? _resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('/uploads/')) return '${AppConstants.apiBaseUrl}$url';
  return url;
}

Widget _buildMediaContent(
  BuildContext context, {
  required Message message,
  required String? resolvedMediaUrl,
  required bool isSticker,
  required bool isOutgoing,
}) {
  const double placeholderSize = 200;
  const double stickerSize = 120;

  // View-once: recipient not opened -> tap to view placeholder
  if (message.isViewOnce &&
      !isOutgoing &&
      message.viewOnceOpenedAt == null) {
    return GestureDetector(
      onTap: () => context.read<ChatCubit>().openViewOnceMessage(message.id),
      child: Container(
        width: isSticker ? stickerSize : placeholderSize,
        height: isSticker ? stickerSize : placeholderSize,
        decoration: BoxDecoration(
          color: AppColors.appBar,
          borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility,
              color: AppColors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to view',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            Text(
              'View once photo',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // View-once: recipient opened, not expired, and we have local file (fetched with auth)
  final viewOnceLocalPath = message.isViewOnce &&
          !isOutgoing &&
          message.viewOnceOpenedAt != null &&
          !_isViewOnceExpired(message.viewOnceOpenedAt)
      ? context.read<ChatCubit>().state.viewOnceLocalPaths[message.id]
      : null;
  if (viewOnceLocalPath != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
      child: Image.file(
        File(viewOnceLocalPath),
        width: isSticker ? stickerSize : null,
        height: isSticker ? stickerSize : null,
        fit: isSticker ? BoxFit.contain : BoxFit.cover,
      ),
    );
  }

  // View-once: recipient opened but expired — "Photo expired" bubble (clock + text)
  if (message.isViewOnce &&
      !isOutgoing &&
      message.viewOnceOpenedAt != null &&
      _isViewOnceExpired(message.viewOnceOpenedAt)) {
    const expiredMutedColor = Color(0xFFA89888); // Muted light-tan for icon & text
    return Container(
      width: isSticker ? stickerSize : placeholderSize,
      height: isSticker ? stickerSize : placeholderSize,
      decoration: BoxDecoration(
        color: const Color(0xFF1E262C), // Dark charcoal outer
        borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF252D35), // Slightly lighter inner area
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.schedule, // Clock icon (circle with hands)
                  color: expiredMutedColor,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo expired',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: expiredMutedColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show image (view-once sender, or opened recipient within 60s, or normal image)
  if (message.mediaUrl != null) {
    final isOurApiUrl = resolvedMediaUrl != null &&
        resolvedMediaUrl.startsWith('http') &&
        resolvedMediaUrl.contains(AppConstants.apiBaseUrl);
    final httpHeaders = isOurApiUrl
        ? context.read<ChatCubit>().authHeadersForMedia
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
      child: (resolvedMediaUrl != null && resolvedMediaUrl.startsWith('http'))
          ? CachedNetworkImage(
              imageUrl: resolvedMediaUrl,
              httpHeaders: httpHeaders,
              width: isSticker ? stickerSize : null,
              height: isSticker ? stickerSize : null,
              fit: isSticker ? BoxFit.contain : BoxFit.cover,
              placeholder: (context, url) => Container(
                width: isSticker ? stickerSize : placeholderSize,
                height: isSticker ? stickerSize : placeholderSize,
                color: AppColors.chatBackground,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: isSticker ? stickerSize : placeholderSize,
                height: isSticker ? stickerSize : placeholderSize,
                color: AppColors.chatBackground,
                child: const Center(child: Icon(Icons.error_outline)),
              ),
            )
          : Image.file(
              File(message.mediaUrl!),
              width: isSticker ? stickerSize : null,
              height: isSticker ? stickerSize : null,
              fit: isSticker ? BoxFit.contain : BoxFit.cover,
            ),
    );
  }

  return const SizedBox.shrink();
}

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
    Widget bubble;
    if (message.isAudio) {
      bubble = AudioMessageBubble(message: message);
    } else if (message.isContact) {
      bubble = _ContactMessageBubble(message: message);
    } else if (message.isLocation) {
      bubble = _LocationMessageWrapper(message: message);
    } else if (message.isImage) {
      bubble = _MediaMessageBubble(message: message, isSticker: false);
    } else if (message.isVideo) {
      bubble = _VideoMessageBubble(message: message);
    } else if (message.isGif) {
      bubble = _MediaMessageBubble(message: message, isSticker: false);
    } else if (message.isSticker) {
      bubble = _MediaMessageBubble(message: message, isSticker: true);
    } else if (message.isDocument) {
      bubble = DocumentMessageBubble(message: message);
    } else {
      bubble = _TextMessageBubble(message: message);
    }

    return ChatMessageWrapper(
      messageId: message.id,
      controller: reactionsController,
      alignment: message.isOutgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
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
        crossAxisAlignment: message.isOutgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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

class _ContactMessageBubble extends StatelessWidget {
  final Message message;

  const _ContactMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final period = message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = message.timestamp.hour % 12;
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:${message.timestamp.minute.toString().padLeft(2, '0')} $period';

    final name = message.contactName ?? 'Unknown';
    final phone = message.contactPhone ?? '';

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _showContactActions(context, name, phone, message.contactId),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: EdgeInsets.only(
            left: isOutgoing ? 64 : 8,
            right: isOutgoing ? 8 : 64,
            top: 2,
            bottom: 2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isOutgoing
                ? AppColors.outgoingBubble
                : AppColors.incomingBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
              bottomRight: Radius.circular(isOutgoing ? 0 : 12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ContactThumb(message: message),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Divider(
                height: 1,
                color: AppColors.divider.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Message',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContactActions(
    BuildContext context,
    String name,
    String phone,
    String? contactId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.open_in_new,
                  color: AppColors.textPrimary,
                ),
                title: const Text(
                  'Open contact',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _openContact(context, contactId, phone);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.save_alt,
                  color: AppColors.textPrimary,
                ),
                title: const Text(
                  'Save to contacts',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _saveContact(context, name, phone);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openContact(
    BuildContext context,
    String? contactId,
    String phone,
  ) async {
    try {
      if (contactId != null && contactId.isNotEmpty) {
        await FlutterContacts.openExternalView(contactId);
        return;
      }

      final launched = await launchUrl(
        Uri(scheme: 'tel', path: phone),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showSnackBar(context, 'Could not open contact.');
      }
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'Could not open contact.');
      }
    }
  }

  Future<void> _saveContact(
    BuildContext context,
    String name,
    String phone,
  ) async {
    try {
      final hasPermission = await FlutterContacts.requestPermission(
        readonly: false,
      );
      if (!hasPermission) {
        if (context.mounted) {
          _showSnackBar(context, 'Contacts permission denied.');
        }
        return;
      }

      final contact = Contact()
        ..name.first = name
        ..phones = [Phone(phone)];
      await FlutterContacts.insertContact(contact);

      if (context.mounted) {
        _showSnackBar(context, 'Contact saved.');
      }
    } catch (_) {
      if (context.mounted) {
        _showSnackBar(context, 'Could not save contact.');
      }
    }
  }

  void _showSnackBar(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ContactThumb extends StatelessWidget {
  final Message message;

  const _ContactThumb({required this.message});

  @override
  Widget build(BuildContext context) {
    final name = message.contactName ?? '';
    final firstChar = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : '?';
    final encoded = message.contactPhotoBase64;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final bytes = base64Decode(encoded);
        return CircleAvatar(radius: 21, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }

    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.iconMuted.withValues(alpha: 0.28),
      child: Text(
        firstChar,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LocationMessageWrapper extends StatelessWidget {
  final Message message;

  const _LocationMessageWrapper({required this.message});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openInMaps(context),
      child: LocationMessageBubble(message: message),
    );
  }

  Future<void> _openInMaps(BuildContext context) async {
    final latitude = message.latitude;
    final longitude = message.longitude;
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location details are unavailable for this message.'),
        ),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps app.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps app.')),
        );
      }
    }
  }
}

/// Renders reaction emojis below the message bubble (WhatsApp-style).
/// Uses [message.reactions] as single source of truth so UI updates when cubit emits.
class _ReactionRow extends StatelessWidget {
  final Map<String, List<String>> reactions;

  const _ReactionRow({required this.reactions});

  @override
  Widget build(BuildContext context) {
    final totalCount = reactions.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.appBar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.chatBackground, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
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
      child: GestureDetector(
        onLongPress: () => _showMessageActions(context),
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
            color: isOutgoing
                ? AppColors.outgoingBubble
                : AppColors.incomingBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
              bottomRight: Radius.circular(isOutgoing ? 0 : 12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _messageDisplayText(message.text),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.3,
                  fontStyle: _isDeletedMessage(message.text)
                      ? FontStyle.italic
                      : FontStyle.normal,
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
                  if (message.isEdited) ...[
                    const SizedBox(width: 4),
                    Text(
                      'edited',
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    MessageStatusIcon(status: message.status, size: 14),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canDelete {
    if (!message.isOutgoing) return false;
    if (_isDeletedMessage(message.text)) return false;
    return true;
  }

  Future<void> _showMessageActions(BuildContext context) async {
    if (!_canDelete) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_canDelete)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.textPrimary),
                  title: const Text(
                    'Delete message',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.read<ChatCubit>().deleteMessage(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaMessageBubble extends StatelessWidget {
  final Message message;
  final bool isSticker;

  const _MediaMessageBubble({required this.message, required this.isSticker});

  @override
  Widget build(BuildContext context) {
    final resolvedMediaUrl = _resolveMediaUrl(message.mediaUrl);
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
        padding: isSticker
            ? EdgeInsets
                  .zero // Stickers often don't have a background bubble
            : const EdgeInsets.all(4),
        decoration: isSticker
            ? null
            : BoxDecoration(
                color: isOutgoing
                    ? AppColors.outgoingBubble
                    : AppColors.incomingBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
                  bottomRight: Radius.circular(isOutgoing ? 0 : 12),
                ),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildMediaContent(
              context,
              message: message,
              resolvedMediaUrl: resolvedMediaUrl,
              isSticker: isSticker,
              isOutgoing: isOutgoing,
            ),
            if (!isSticker &&
                message.text.isNotEmpty &&
                message.text != 'Photo' &&
                message.text != '\u{1F4F7} Photo')
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  _messageDisplayText(message.text),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.3,
                    fontStyle: _isDeletedMessage(message.text)
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            if (!isSticker) const SizedBox(height: 2),
            if (!isSticker)
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
                  if (message.isEdited) ...[
                    const SizedBox(width: 4),
                    Text(
                      'edited',
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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

class _VideoMessageBubble extends StatefulWidget {
  final Message message;

  const _VideoMessageBubble({required this.message});

  @override
  State<_VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<_VideoMessageBubble> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = _resolveMediaUrl(widget.message.mediaUrl);
    if (url == null) return;

    try {
      if (url.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        _controller = VideoPlayerController.file(File(url));
      }

      await _controller!.initialize();
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final period = widget.message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = widget.message.timestamp.hour % 12;
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:${widget.message.timestamp.minute.toString().padLeft(2, '0')} $period';

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
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isOutgoing
              ? AppColors.outgoingBubble
              : AppColors.incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isOutgoing ? 12 : 0),
            bottomRight: Radius.circular(isOutgoing ? 0 : 12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _error
                  ? Container(
                      height: 200,
                      color: Colors.black12,
                      child: const Center(child: Icon(Icons.error_outline)),
                    )
                  : _initialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _controller!.value.isPlaying
                                  ? _controller!.pause()
                                  : _controller!.play();
                            });
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.black45,
                            child: Icon(
                              _controller!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      height: 200,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
            ),
            if (widget.message.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  _messageDisplayText(widget.message.text),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontStyle: _isDeletedMessage(widget.message.text)
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
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
                if (widget.message.isEdited) ...[
                  const SizedBox(width: 4),
                  Text(
                    'edited',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  MessageStatusIcon(status: widget.message.status, size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
