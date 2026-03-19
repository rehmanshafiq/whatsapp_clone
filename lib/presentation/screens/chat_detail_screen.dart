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
    final hour12 = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:${local.minute.toString().padLeft(2, '0')} $ampm';
    return 'last seen $timeStr';
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
          prev.isPaginationLoading != curr.isPaginationLoading ||
          prev.isTyping != curr.isTyping ||
          prev.isRecordingAudio != curr.isRecordingAudio ||
          prev.isOnline != curr.isOnline ||
          prev.selectedChannel?.lastSeen != curr.selectedChannel?.lastSeen ||
          prev.channels.where((c) => c.id == widget.channelId).firstOrNull?.isOnline !=
              curr.channels.where((c) => c.id == widget.channelId).firstOrNull?.isOnline,

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
        final atBottom = _scrollController.hasClients &&
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

        final channelIsOnline = state.channels
            .where((c) => c.id == widget.channelId)
            .firstOrNull
            ?.isOnline ??
            false;
        final isOnline = state.isOnline || channelIsOnline;

        // Only show messages for this conversation (handles socket updates).
        final messagesForThisChat = state.messages
            .where((m) => m.channelId == widget.channelId)
            .toList();

        // reversed so index 0 == latest message (sits at visual bottom
        // because ListView has reverse:true).
        final reversedMessages = messagesForThisChat.reversed.toList();

        // Total item count:
        //   • optional typing indicator at index 0 (visual bottom)
        //   • messages
        //   • optional pagination loader at the last index (visual top)
        final typingOffset = state.isTyping ? 1 : 0;
        final itemCount = reversedMessages.length +
            typingOffset +
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
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
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
                                    color: AppColors.accent, fontSize: 12),
                              ),
                            ],
                          )
                        else if (state.isTyping)
                          const Text(
                            'typing...',
                            style: TextStyle(
                                color: AppColors.accent, fontSize: 12),
                          )
                        else if (isOnline)
                          const Text(
                            'online',
                            style: TextStyle(
                                color: AppColors.accent, fontSize: 12),
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
                      child: state.isLoading && messagesForThisChat.isEmpty
                          ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent),
                      )
                          : ListView.builder(
                        controller: _scrollController,

                        // reverse:true keeps the latest messages at the
                        // visual bottom without any manual scrolling.
                        reverse: true,

                        padding:
                        const EdgeInsets.symmetric(vertical: 8),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          // ── Typing indicator (index 0, visual bottom) ──
                          if (index == 0 && state.isTyping) {
                            return const TypingIndicator();
                          }

                          // ── Pagination loader (last index, visual top) ──
                          final loaderIndex =
                              typingOffset + reversedMessages.length;
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
                          return MessageBubble(
                            message: reversedMessages[messageIndex],
                            reactionsController: _reactionsController,
                            onReactionChanged: () => setState(() {}),
                          );
                        },
                      ),
                    ),

                    // ── Input bar ─────────────────────────────────────
                    ChatInputBar(
                      channelId: widget.channelId,
                      onSend: (text) =>
                          cubit.sendMessage(widget.channelId, text),
                      onSendAudio: (file, duration) =>
                          cubit.sendAudioMessage(
                            widget.channelId,
                            file.path,
                            duration,
                          ),
                      onSendMedia: (url, isSticker) =>
                          cubit.sendMediaMessage(
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
