import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/audio_playback_service.dart';
import '../../data/models/message.dart';
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
  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------

  /// How close to the visual top (oldest messages) the user must scroll
  /// before we fire a pagination request.
  static const double _paginationTriggerThreshold = 120.0;

  /// "Scroll-to-bottom" FAB is hidden while the user is within this many
  /// pixels of the visual bottom (latest messages).
  static const double _atBottomThreshold = 80.0;

  // ------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------

  final _scrollController = ScrollController();
  late final ReactionsController _reactionsController;
  bool _reactionsSynced = false;
  bool _showScrollToBottom = false;

  /// The maxScrollExtent captured **once** at the start of each pagination
  /// request.  Nulled out after the post-frame delta jump is applied.
  /// Using `??=` in the scroll listener ensures we never overwrite it while
  /// a pagination fetch is already in flight.
  double? _extentBeforePagination;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _reactionsController = ReactionsController(
      currentUserId: AppConstants.currentUserId,
    );
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatCubit>().loadMessages(widget.channelId);
    });
  }

  @override
  void dispose() {
    getIt<AudioPlaybackService>().stop();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  String _capitalizeName(String name) {
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  // ------------------------------------------------------------------
  // Scroll handling
  // ------------------------------------------------------------------

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // ── "Scroll to bottom" FAB visibility ────────────────────────────
    // With reverse:true, pixels==0 is the visual bottom (latest messages).
    final atBottom = pos.pixels <= _atBottomThreshold;
    if (atBottom && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    } else if (!atBottom && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    }

    // ── Pagination trigger ────────────────────────────────────────────
    // With reverse:true, pixels==maxScrollExtent is the visual top (oldest
    // messages).  We request older messages when the user scrolls within
    // _paginationTriggerThreshold pixels of that edge.
    final distanceFromTop = pos.maxScrollExtent - pos.pixels;
    if (distanceFromTop <= _paginationTriggerThreshold) {
      // ??= guarantees we capture the extent only once per pagination cycle
      // and never overwrite it while a fetch is still in flight.
      _extentBeforePagination ??= pos.maxScrollExtent;
      context.read<ChatCubit>().loadOlderMessages(widget.channelId);
    }
  }

  // ------------------------------------------------------------------
  // Scroll helpers
  // ------------------------------------------------------------------

  /// Scrolls to the visual bottom (latest messages).
  /// Because the ListView uses reverse:true, "bottom" is always at pixels==0.
  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (animate) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  /// Called after older messages finish loading.
  ///
  /// The delta between the old and new maxScrollExtent equals the height of
  /// the prepended items.  We jump by that delta so the previously-visible
  /// messages stay in place — identical to WhatsApp behaviour.
  ///
  /// **Critical:** the delta must be read inside addPostFrameCallback so that
  /// Flutter has already laid out the new items and maxScrollExtent reflects
  /// the added content.  Reading it in the BlocListener (before layout) would
  /// always yield delta==0.
  void _restoreScrollPositionAfterPagination() {
    final saved = _extentBeforePagination;
    if (saved == null) return;
    _extentBeforePagination = null; // reset for the next pagination cycle

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final delta = pos.maxScrollExtent - saved;
      if (delta > 0) {
        // jumpTo keeps the scroll instant — no animation so the user doesn't
        // notice the viewport shift.
        _scrollController.jumpTo(pos.pixels + delta);
      }
    });
  }

  // ------------------------------------------------------------------
  // Reactions
  // ------------------------------------------------------------------

  void _syncReactions(List<Message> messages) {
    if (_reactionsSynced) return;
    _reactionsSynced = true;
    for (final message in messages) {
      for (final entry in message.reactions.entries) {
        for (final _ in entry.value) {
          _reactionsController.addReaction(message.id, entry.key);
        }
      }
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------
  // Formatting helpers
  // ------------------------------------------------------------------

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'last seen recently';
    final local = lastSeen.isUtc ? lastSeen.toLocal() : lastSeen;
    final hour12 = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:${local.minute.toString().padLeft(2, '0')} $ampm';
    return 'last seen $timeStr';
  }

  DateTime _toLocalDateOnly(DateTime dateTime) {
    final local = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    return DateTime(local.year, local.month, local.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int month) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _formatMessageDateLabel(DateTime timestamp) {
    final date = _toLocalDateOnly(timestamp);
    final today = _toLocalDateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    if (_isSameDay(date, today)) return 'Today';
    if (_isSameDay(date, yesterday)) return 'Yesterday';

    return '${date.day} ${_monthName(date.month)} ${date.year}';
  }

  String _formatEmptyChatDateLabel(DateTime timestamp) {
    final date = _toLocalDateOnly(timestamp);
    return '${_monthName(date.month).toUpperCase()} ${date.day}, ${date.year}';
  }

  Future<void> _showEncryptionInfoSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.scaffold,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _EncryptionInfoGraphic(),
                    const SizedBox(height: 18),
                    const Text(
                      'Your chats and calls are private',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'End-to-end encryption keeps your personal messages between you and the people you choose. No one outside of the chat, not even WhatsApp, can read, listen to, or share them. This includes your:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.95),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _EncryptionFeatureRow(
                      icon: Icons.message_outlined,
                      label: 'Text and voice messages',
                    ),
                    const SizedBox(height: 12),
                    // const _EncryptionFeatureRow(
                    //   icon: Icons.call_outlined,
                    //   label: 'Audio and video calls',
                    // ),
                    // const SizedBox(height: 12),
                    const _EncryptionFeatureRow(
                      icon: Icons.attach_file,
                      label: 'Photos, videos and documents',
                    ),
                    const SizedBox(height: 12),
                    const _EncryptionFeatureRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location sharing',
                    ),
                    const SizedBox(height: 12),
                    // const _EncryptionFeatureRow(
                    //   icon: Icons.autorenew,
                    //   label: 'Status updates',
                    // ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      // ── Rebuild condition ─────────────────────────────────────────
      buildWhen: (prev, curr) =>
          prev.messages != curr.messages ||
          prev.selectedChannel != curr.selectedChannel ||
          prev.isLoading != curr.isLoading ||
          prev.hasLoadedMessages != curr.hasLoadedMessages ||
          prev.isPaginationLoading != curr.isPaginationLoading ||
          prev.isTyping != curr.isTyping ||
          prev.isRecordingAudio != curr.isRecordingAudio ||
          prev.isOnline != curr.isOnline ||
          prev.replyingTo != curr.replyingTo ||
          prev.selectedChannel?.lastSeen != curr.selectedChannel?.lastSeen ||
          prev.channels
                  .where((c) => c.id == widget.channelId)
                  .firstOrNull
                  ?.isOnline !=
              curr.channels
                  .where((c) => c.id == widget.channelId)
                  .firstOrNull
                  ?.isOnline,

      // ── Side-effect condition ─────────────────────────────────────
      listenWhen: (prev, curr) =>
          // New messages arrived (new socket message or initial load).
          prev.messages.length != curr.messages.length ||
          // Initial load finished.
          (prev.isLoading && !curr.isLoading && curr.messages.isNotEmpty) ||
          // Pagination finished — need to restore scroll position.
          (prev.isPaginationLoading && !curr.isPaginationLoading),

      listener: (_, state) {
        final forThisChat = state.messages
            .where((m) => m.channelId == widget.channelId)
            .toList();

        _syncReactions(forThisChat);

        // ── Auto-scroll to bottom for new incoming/outgoing messages ──
        // Only when the user is already at the bottom; otherwise leave them
        // where they are (they may be reading older messages).
        final atBottom =
            _scrollController.hasClients &&
            _scrollController.position.pixels <= _atBottomThreshold;
        if (atBottom) {
          _scrollToBottom(animate: forThisChat.length > 1);
        }

        // ── Restore scroll position after pagination ──────────────────
        // This is intentionally checked independently of `atBottom` —
        // the user is near the top when pagination fires, never at bottom.
        _restoreScrollPositionAfterPagination();
      },

      builder: (context, state) {
        final channel = state.selectedChannel;
        final cubit = context.read<ChatCubit>();

        final channelIsOnline =
            state.channels
                .where((c) => c.id == widget.channelId)
                .firstOrNull
                ?.isOnline ??
            false;
        final isOnline = state.isOnline || channelIsOnline;

        // Only show messages for this conversation (handles socket updates).
        final messagesForThisChat = state.messages
            .where((m) => m.channelId == widget.channelId)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // reversed so index 0 == latest message (sits at visual bottom
        // because ListView has reverse:true).
        final reversedMessages = messagesForThisChat.reversed.toList();
        final hasNoMessages = messagesForThisChat.isEmpty;
        final introDate = hasNoMessages
            ? DateTime.now()
            : messagesForThisChat.first.timestamp;

        // Total item count:
        //   • optional typing indicator at index 0 (visual bottom)
        //   • messages
        //   • intro banner at the visual top
        //   • optional pagination loader at the last index (visual top)
        final typingOffset = state.isTyping ? 1 : 0;
        final introIndex = typingOffset + reversedMessages.length;
        final loaderIndex = introIndex + 1;
        final itemCount =
            reversedMessages.length +
            typingOffset +
            1 +
            (state.isPaginationLoading ? 1 : 0);

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
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
              ),
              title: Row(
                children: [
                  ChatAvatar(
                    imageUrl: channel?.avatarUrl,
                    name: _capitalizeName(channel?.name ?? ''),
                    radius: 18,
                    heroTag: 'avatar_${widget.channelId}',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _capitalizeName(channel?.name ?? 'Chat'),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (state.isRecordingAudio)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const RecordingDotIndicator(size: 8),
                              const SizedBox(width: 6),
                              const Text(
                                'recording audio...',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        else if (state.isTyping)
                          const Text(
                            'typing...',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                            ),
                          )
                        else if (isOnline)
                          const Text(
                            'online',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                            ),
                          )
                        else
                          Text(
                            _formatLastSeen(channel?.lastSeen),
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
            ),
            body: Stack(
              children: [
                // ── Decorative dot-grid background ────────────────────
                CustomPaint(
                  painter: _ChatBackgroundPainter(),
                  size: Size.infinite,
                ),

                // ── Main column: message list + input bar ─────────────
                Column(
                  children: [
                    Expanded(
                      child: !state.hasLoadedMessages && hasNoMessages
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,

                              // reverse:true keeps the latest messages at the
                              // visual bottom without any manual scrolling.
                              reverse: true,

                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: itemCount,
                              itemBuilder: (context, index) {
                                // ── Typing indicator (index 0, visual bottom) ──
                                if (index == 0 && state.isTyping) {
                                  return const TypingIndicator();
                                }

                                // ── Intro banner (visual top of chat content) ──
                                if (index == introIndex) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      2,
                                      16,
                                      10,
                                    ),
                                    child: _EmptyChatPlaceholder(
                                      dateLabel: _formatEmptyChatDateLabel(
                                        introDate,
                                      ),
                                      onEncryptionInfoTap:
                                          _showEncryptionInfoSheet,
                                    ),
                                  );
                                }

                                // ── Pagination loader (last index, visual top) ──
                                if (state.isPaginationLoading &&
                                    index == loaderIndex) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                // ── Message bubble ────────────────────────────
                                final messageIndex = index - typingOffset;
                                final message = reversedMessages[messageIndex];
                                final currentDay = _toLocalDateOnly(
                                  message.timestamp,
                                );
                                final nextMessage =
                                    messageIndex < reversedMessages.length - 1
                                    ? reversedMessages[messageIndex + 1]
                                    : null;
                                final nextDay = nextMessage == null
                                    ? null
                                    : _toLocalDateOnly(nextMessage.timestamp);
                                final shouldShowDateHeader =
                                    nextDay == null ||
                                    !_isSameDay(currentDay, nextDay);

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (shouldShowDateHeader)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.appBar.withValues(
                                                alpha: 0.85,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              _formatMessageDateLabel(
                                                message.timestamp,
                                              ),
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    MessageBubble(
                                      key: ValueKey(message.id),
                                      message: message,
                                      reactionsController: _reactionsController,
                                      onReactionChanged: () => setState(() {}),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),

                    // ── Input bar ─────────────────────────────────────
                    ChatInputBar(
                      channelId: widget.channelId,
                      onSend: (text) =>
                          cubit.sendMessage(widget.channelId, text),
                      onSendAudio: (file, duration) => cubit.sendAudioMessage(
                        widget.channelId,
                        file.path,
                        duration,
                      ),
                      onSendMedia: (url, isSticker) => cubit.sendMediaMessage(
                        widget.channelId,
                        url,
                        isSticker,
                      ),
                      onTypingStart: () =>
                          cubit.sendTypingStart(widget.channelId),
                      onTypingStop: () =>
                          cubit.sendTypingStop(widget.channelId),
                      onRecordingStart: () =>
                          cubit.sendRecordingStart(widget.channelId),
                      onRecordingStop: () =>
                          cubit.sendRecordingStop(widget.channelId),
                      replyingTo: state.replyingTo,
                      onCancelReply: cubit.clearReply,
                    ),
                  ],
                ),

                // ── Scroll-to-bottom FAB ──────────────────────────────
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 80,
                    child: FloatingActionButton.small(
                      heroTag: 'scroll_to_bottom',
                      backgroundColor: AppColors.accent,
                      onPressed: _scrollToBottom,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ),
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

class _EmptyChatPlaceholder extends StatelessWidget {
  final String dateLabel;
  final VoidCallback onEncryptionInfoTap;

  const _EmptyChatPlaceholder({
    required this.dateLabel,
    required this.onEncryptionInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2C34).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: const Color(0xFF2A3942).withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            dateLabel,
            style: const TextStyle(
              color: Color(0xFFE9EDEF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEncryptionInfoTap,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF30271C).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4A3D27).withValues(alpha: 0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.lock,
                        size: 14,
                        color: Color(0xFFE6C689),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Messages to this chat are now secured with end-to-end encryption. Tap for more info.',
                        style: TextStyle(
                          color: Color(0xFFE9D7A9),
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EncryptionInfoGraphic extends StatelessWidget {
  const _EncryptionInfoGraphic();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              width: 58,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.scaffold,
                size: 26,
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 18,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.lock_outline,
                color: AppColors.accent,
                size: 18,
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 6,
            child: Container(
              width: 28,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F2E8),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Color(0xFF8F7E5C),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EncryptionFeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _EncryptionFeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}
