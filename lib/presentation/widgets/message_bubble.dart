import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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
import '../screens/media_viewer_screen.dart';
import 'audio_message_bubble.dart';
import 'document_message_bubble.dart';
import 'location_message_bubble.dart';
import 'message_status_icon.dart';
import 'message_action_sheet.dart';
import 'forwarded_label.dart';

/// Canonical body marker for soft-deleted messages.
const String _deletedMessageMarker = 'message deleted';

/// True when body indicates a deleted message (accept legacy display text too).
bool _isDeletedMessage(String body) {
  final normalized = body.trim().toLowerCase();
  return normalized == _deletedMessageMarker ||
      normalized == 'this message was deleted';
}

/// Display text for message body. Keep one user-facing phrase.
String _messageDisplayText(String body) =>
    _isDeletedMessage(body) ? 'This message was deleted' : body;

/// Renders normal message text, or a WhatsApp-like deleted-message row.
Widget _buildMessageBodyText(
  String body, {
  required TextStyle normalStyle,
  Color? deletedColor,
}) {
  final displayText = _messageDisplayText(body);
  if (!_isDeletedMessage(body)) {
    return Text(displayText, style: normalStyle);
  }

  final effectiveDeletedColor =
      (deletedColor ?? normalStyle.color ?? AppColors.textSecondary).withValues(
        alpha: 0.85,
      );
  final deletedStyle = normalStyle.copyWith(
    color: effectiveDeletedColor,
    fontStyle: FontStyle.italic,
  );
  final iconSize = (deletedStyle.fontSize ?? 15) - 1;

  return Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              Icons.block,
              size: iconSize < 12 ? 12 : iconSize,
              color: effectiveDeletedColor,
            ),
          ),
        ),
        TextSpan(text: displayText),
      ],
    ),
    style: deletedStyle,
  );
}

/// View-once image is considered expired 60 seconds after opening.
bool _isViewOnceExpired(DateTime? viewOnceOpenedAt) {
  if (viewOnceOpenedAt == null) return false;
  return viewOnceOpenedAt
      .add(const Duration(seconds: 2))
      .isBefore(DateTime.now());
}

/// Backend may return server-relative media URLs like `/uploads/...`.
/// Only prepend baseUrl for those; leave local absolute paths (e.g. /data/... on Android) unchanged.
String? _resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('/uploads/')) return '${AppConstants.apiBaseUrl}$url';
  return url;
}

/// Small pulsing dot used for transient recording indicator UI.
class RecordingDotIndicator extends StatefulWidget {
  final double size;

  const RecordingDotIndicator({super.key, this.size = 8});

  @override
  State<RecordingDotIndicator> createState() => _RecordingDotIndicatorState();
}

class _RecordingDotIndicatorState extends State<RecordingDotIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
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

  // View-once: sender, not yet opened by recipient → placeholder (no image for sender either)
  if (message.isViewOnce && isOutgoing && message.viewOnceOpenedAt == null) {
    return Container(
      width: isSticker ? stickerSize : placeholderSize,
      height: isSticker ? stickerSize : placeholderSize,
      decoration: BoxDecoration(
        color: AppColors.appBar.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_outlined,
              color: AppColors.textSecondary,
              size: 36,
            ),
            const SizedBox(height: 6),
            Text(
              'View once photo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // View-once: recipient not opened -> tap to view placeholder
  if (message.isViewOnce && !isOutgoing && message.viewOnceOpenedAt == null) {
    return _ViewOnceTapToView(
      message: message,
      isSticker: isSticker,
      placeholderSize: placeholderSize,
      stickerSize: stickerSize,
    );
  }

  // View-once: recipient opened, not expired, and we have local file (fetched with auth)
  final viewOnceLocalPath =
      message.isViewOnce &&
          !isOutgoing &&
          message.viewOnceOpenedAt != null &&
          !_isViewOnceExpired(message.viewOnceOpenedAt)
      ? context.read<ChatCubit>().state.viewOnceLocalPaths[message.id]
      : null;
  if (viewOnceLocalPath != null) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(
              localFilePath: viewOnceLocalPath,
              isViewOnce: true,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
        child: Image.file(
          File(viewOnceLocalPath),
          width: isSticker ? stickerSize : null,
          height: isSticker ? stickerSize : null,
          fit: isSticker ? BoxFit.contain : BoxFit.cover,
        ),
      ),
    );
  }

  // View-once: recipient opened but expired — "Photo expired" bubble (clock + text)
  if (message.isViewOnce &&
      !isOutgoing &&
      message.viewOnceOpenedAt != null &&
      _isViewOnceExpired(message.viewOnceOpenedAt)) {
    const expiredMutedColor = Color(
      0xFFA89888,
    ); // Muted light-tan for icon & text
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

  // View-once: sender — recipient has opened → show "Opened" (WhatsApp-style)
  if (message.isViewOnce && isOutgoing && message.viewOnceOpenedAt != null) {
    return Container(
      width: isSticker ? stickerSize : placeholderSize,
      height: isSticker ? stickerSize : placeholderSize,
      decoration: BoxDecoration(
        color: AppColors.appBar.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(isSticker ? 0 : 8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_outlined,
              color: AppColors.textSecondary,
              size: 36,
            ),
            const SizedBox(height: 6),
            Text(
              'Opened',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show image (view-once sender not yet opened, or opened recipient within 60s, or normal image)
  final hasMediaOrLocal = message.mediaUrl != null || message.localFilePath != null;
  if (hasMediaOrLocal) {
    final isOurApiUrl =
        resolvedMediaUrl != null &&
        resolvedMediaUrl.startsWith('http') &&
        resolvedMediaUrl.contains(AppConstants.apiBaseUrl);
    final httpHeaders = isOurApiUrl
        ? context.read<ChatCubit>().authHeadersForMedia
        : null;

    Widget imageWidget = ClipRRect(
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
              File(resolvedMediaUrl ?? message.localFilePath!),
              width: isSticker ? stickerSize : null,
              height: isSticker ? stickerSize : null,
              fit: isSticker ? BoxFit.contain : BoxFit.cover,
            ),
    );

    // Overlay for uploading state
    if (message.isUploading) {
      imageWidget = Stack(
        alignment: Alignment.center,
        children: [
          imageWidget,
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
        ],
      );
    }

    if (isSticker || message.isViewOnce) return imageWidget;

    return GestureDetector(
      onTap: () {
        if (message.isUploading) return;
        final isLocal = resolvedMediaUrl == null ||
            !resolvedMediaUrl.startsWith('http');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(
              networkUrl: isLocal ? null : resolvedMediaUrl,
              localFilePath: isLocal ? (message.mediaUrl ?? message.localFilePath) : null,
              httpHeaders: httpHeaders,
            ),
          ),
        );
      },
      child: imageWidget,
    );
  }

  return const SizedBox.shrink();
}

class MessageBubble extends StatelessWidget {
  final Message message;
  final ReactionsController reactionsController;
  final VoidCallback? onReactionChanged;
  final VoidCallback? onReplyPreviewTap;
  final bool isFlashHighlighted;

  const MessageBubble({
    super.key,
    required this.message,
    required this.reactionsController,
    this.onReactionChanged,
    this.onReplyPreviewTap,
    this.isFlashHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget bubble;
    if (message.isAudio) {
      bubble = AudioMessageBubble(
        message: message,
        authHeaders: context.read<ChatCubit>().authHeadersForMedia,
      );
    } else if (message.isContact) {
      bubble = _ContactMessageBubble(
        message: message,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isLocation) {
      bubble = _LocationMessageWrapper(
        message: message,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isImage) {
      bubble = _MediaMessageBubble(
        message: message,
        isSticker: false,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isVideo) {
      bubble = _VideoMessageBubble(
        message: message,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isGif) {
      bubble = _MediaMessageBubble(
        message: message,
        isSticker: false,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isSticker) {
      bubble = _MediaMessageBubble(
        message: message,
        isSticker: true,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    } else if (message.isDocument) {
      bubble = DocumentMessageBubble(message: message);
    } else {
      bubble = _TextMessageBubble(
        message: message,
        onReplyPreviewTap: onReplyPreviewTap,
      );
    }

    return ChatMessageWrapper(
      messageId: message.id,
      controller: reactionsController,
      alignment: message.isOutgoing
          ? Alignment.centerRight
          : Alignment.centerLeft,
      config: const ChatReactionsConfig(
        availableReactions: ['👍', '❤️', '😂', '😮', '😢', '🙏', '➕'],
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
        context.read<ChatCubit>().removeReaction(message.id, reaction);
        onReactionChanged?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isFlashHighlighted
              ? AppColors.accent.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _SwipeableMessage(
          enabled: !message.isAudio,
          isOutgoing: message.isOutgoing,
          onSwipeComplete: () => MessageActionSheet.show(context, message),
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
        ),
      ),
    );
  }
}

class _SwipeableMessage extends StatefulWidget {
  final bool enabled;
  final bool isOutgoing;
  final VoidCallback onSwipeComplete;
  final Widget child;

  const _SwipeableMessage({
    required this.enabled,
    required this.isOutgoing,
    required this.onSwipeComplete,
    required this.child,
  });

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage>
    with SingleTickerProviderStateMixin {
  static const double _triggerThreshold = 64.0;
  static const double _maxDrag = 100.0;

  late final AnimationController _controller;
  double _dragExtent = 0;
  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: _maxDrag,
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;
    _dragExtent = (_dragExtent + dx).clamp(0.0, double.infinity);
    _controller.value = math.min(_dragExtent, _maxDrag);

    if (!_hapticFired && _dragExtent >= _triggerThreshold) {
      _hapticFired = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _finishSwipe();
  }

  void _onDragCancel() {
    _finishSwipe();
  }

  void _finishSwipe() {
    final triggered = _dragExtent >= _triggerThreshold;
    _dragExtent = 0;
    _hapticFired = false;

    if (_controller.value == 0) {
      if (triggered && mounted) widget.onSwipeComplete();
      return;
    }

    final springDesc = SpringDescription(mass: 1, stiffness: 300, damping: 22);
    final simulation = SpringSimulation(springDesc, _controller.value, 0, 0);
    _controller.animateWith(simulation).then((_) {
      if (triggered && mounted) {
        widget.onSwipeComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final dx = _controller.value;
          final progress = (dx / _triggerThreshold).clamp(0.0, 1.0);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: widget.isOutgoing ? null : 4,
                right: widget.isOutgoing ? 4 : null,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.4 + progress * 0.6,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(
                            alpha: 0.18 + progress * 0.22,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.reply,
                          size: 18,
                          color: AppColors.accent.withValues(
                            alpha: 0.5 + progress * 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, 0),
                child: child,
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _ContactMessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onReplyPreviewTap;

  const _ContactMessageBubble({
    required this.message,
    this.onReplyPreviewTap,
  });

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
              if (message.replyToMessageId != null)
                _ReplyPreview(
                  senderId: message.replyToSenderId,
                  previewText: message.replyToBody,
                  attachmentType: message.replyToAttachmentType,
                  isOutgoing: message.isOutgoing,
                  onTap: onReplyPreviewTap,
                ),
              if (message.isForwarded)
                const ForwardedLabel(),
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
  final VoidCallback? onReplyPreviewTap;

  const _LocationMessageWrapper({
    required this.message,
    this.onReplyPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = LocationMessageBubble(message: message);
    if (message.replyToMessageId == null && !message.isForwarded) {
      return GestureDetector(onTap: () => _openInMaps(context), child: bubble);
    }
    return GestureDetector(
      onTap: () => _openInMaps(context),
      child: Align(
        alignment: message.isOutgoing
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: message.isOutgoing ? 64 : 8,
            right: message.isOutgoing ? 8 : 64,
            top: 2,
            bottom: 2,
          ),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: message.isOutgoing
                ? AppColors.outgoingBubble
                : AppColors.incomingBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(message.isOutgoing ? 12 : 0),
              bottomRight: Radius.circular(message.isOutgoing ? 0 : 12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.replyToMessageId != null)
                _ReplyPreview(
                  senderId: message.replyToSenderId,
                  previewText: message.replyToBody,
                  attachmentType: message.replyToAttachmentType,
                  isOutgoing: message.isOutgoing,
                  onTap: onReplyPreviewTap,
                ),
              if (message.isForwarded)
                const ForwardedLabel(),
              bubble,
            ],
          ),
        ),
      ),
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
    final entries = reactions.entries.toList()
      ..removeWhere((e) => e.value.isEmpty)
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: entries.map((entry) {
        final users = entry.value;
        final hasMine = users.contains(AppConstants.currentUserId);
        final count = users.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: hasMine
                ? AppColors.accent.withValues(alpha: 0.25)
                : AppColors.appBar,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasMine ? AppColors.accent : AppColors.chatBackground,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.key, style: const TextStyle(fontSize: 14)),
              if (count > 1) ...[
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final String? senderId;
  final String? previewText;
  final String? attachmentType;
  final bool isOutgoing;
  final VoidCallback? onTap;

  const _ReplyPreview({
    required this.senderId,
    required this.previewText,
    required this.attachmentType,
    required this.isOutgoing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    final myBackendId = cubit.repository.getCurrentUserId();
    final isMe =
        senderId == AppConstants.currentUserId ||
        (myBackendId != null &&
            myBackendId.isNotEmpty &&
            senderId == myBackendId);
    final String name;
    if (isMe) {
      name = 'You';
    } else if (senderId == null || senderId!.isEmpty) {
      name = isOutgoing
          ? 'You'
          : (cubit.state.selectedChannel?.name ?? 'Unknown');
    } else {
      name = cubit.state.selectedChannel?.name ?? senderId!;
    }
    String text = (previewText ?? '').trim();
    final type = (attachmentType ?? '').toLowerCase();
    if (text.isEmpty) {
      if (type == 'image') {
        text = 'Photo';
      } else if (type == 'video') {
        text = 'Video';
      } else if (type == 'audio' || type == 'voice') {
        text = 'Voice message';
      } else if (type == 'document') {
        text = 'Document';
      } else if (type == 'location') {
        text = 'Location';
      } else if (type == 'gif') {
        text = 'GIF';
      } else if (type == 'sticker') {
        text = 'Sticker';
      }
    }

    final preview = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.chatBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: Colors.purpleAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                if (text.isNotEmpty)
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return preview;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: preview,
    );
  }
}

class _TextMessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onReplyPreviewTap;

  const _TextMessageBubble({
    required this.message,
    this.onReplyPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final isDeletedMessage = _isDeletedMessage(message.text);
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
            if (!isDeletedMessage &&
                message.replyToMessageId != null &&
                message.replyToMessageId!.isNotEmpty)
              _ReplyPreview(
                senderId: message.replyToSenderId,
                previewText: message.replyToBody,
                attachmentType: message.replyToAttachmentType,
                isOutgoing: message.isOutgoing,
                onTap: onReplyPreviewTap,
              ),
            if (message.isForwarded && !isDeletedMessage)
              const ForwardedLabel(),
            _buildMessageBodyText(
              message.text,
              normalStyle: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                height: 1.3,
              ),
              deletedColor: AppColors.textSecondary,
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
    );
  }
}

class _MediaMessageBubble extends StatelessWidget {
  final Message message;
  final bool isSticker;
  final VoidCallback? onReplyPreviewTap;

  const _MediaMessageBubble({
    required this.message,
    required this.isSticker,
    this.onReplyPreviewTap,
  });

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
            if (!isSticker && message.replyToMessageId != null)
              _ReplyPreview(
                senderId: message.replyToSenderId,
                previewText: message.replyToBody,
                attachmentType: message.replyToAttachmentType,
                isOutgoing: message.isOutgoing,
                onTap: onReplyPreviewTap,
              ),
            if (!isSticker && message.isForwarded)
              const ForwardedLabel(),
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
                child: _buildMessageBodyText(
                  message.text,
                  normalStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.3,
                  ),
                  deletedColor: AppColors.textSecondary,
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
  final VoidCallback? onReplyPreviewTap;

  const _VideoMessageBubble({
    required this.message,
    this.onReplyPreviewTap,
  });

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
    final rawUrl = widget.message.mediaUrl ?? widget.message.localFilePath;
    final url = _resolveMediaUrl(rawUrl);
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
            if (widget.message.replyToMessageId != null)
              _ReplyPreview(
                senderId: widget.message.replyToSenderId,
                previewText: widget.message.replyToBody,
                attachmentType: widget.message.replyToAttachmentType,
                isOutgoing: widget.message.isOutgoing,
                onTap: widget.onReplyPreviewTap,
              ),
            if (widget.message.isForwarded)
              const ForwardedLabel(),
            GestureDetector(
              onTap: () {
                if (!_initialized || _error || widget.message.isUploading) return;
                _controller?.pause();
                final rawUrl = widget.message.mediaUrl ?? widget.message.localFilePath;
                final url = _resolveMediaUrl(rawUrl);
                final isLocal = url != null && !url.startsWith('http');
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MediaViewerScreen(
                      networkUrl: isLocal ? null : url,
                      localFilePath: isLocal ? url : null,
                      isVideo: true,
                    ),
                  ),
                );
              },
              child: ClipRRect(
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
                          if (widget.message.isUploading)
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 3,
                            )
                          else
                            const CircleAvatar(
                              backgroundColor: Colors.black45,
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
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
            ),
            if (widget.message.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: _buildMessageBodyText(
                  widget.message.text,
                  normalStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  deletedColor: AppColors.textSecondary,
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

class _ViewOnceTapToView extends StatefulWidget {
  final Message message;
  final bool isSticker;
  final double placeholderSize;
  final double stickerSize;

  const _ViewOnceTapToView({
    required this.message,
    required this.isSticker,
    required this.placeholderSize,
    required this.stickerSize,
  });

  @override
  State<_ViewOnceTapToView> createState() => _ViewOnceTapToViewState();
}

class _ViewOnceTapToViewState extends State<_ViewOnceTapToView> {
  bool _opening = false;

  Future<void> _openAndView() async {
    if (_opening) return;
    setState(() => _opening = true);

    final cubit = context.read<ChatCubit>();
    await cubit.openViewOnceMessage(widget.message.id);

    if (!mounted) return;

    final localPath = cubit.state.viewOnceLocalPaths[widget.message.id];
    if (localPath == null) {
      setState(() => _opening = false);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          localFilePath: localPath,
          isViewOnce: true,
        ),
      ),
    );

    if (!mounted) return;
    cubit.expireViewOnceMessage(widget.message.id);
    setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.isSticker ? widget.stickerSize : widget.placeholderSize;
    return GestureDetector(
      onTap: _openAndView,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.appBar,
          borderRadius: BorderRadius.circular(widget.isSticker ? 0 : 8),
        ),
        child: _opening
            ? const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
            : Column(
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
}
