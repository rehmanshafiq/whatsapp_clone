import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

const _defaultReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const _pickerSentinel = '+';

Future<String?> showReactionPicker({
  required BuildContext context,
  required Rect messageRect,
  required bool isOutgoing,
}) {
  final mediaQuery = MediaQuery.of(context);
  final statusBarHeight = mediaQuery.padding.top;
  final screenHeight = mediaQuery.size.height;
  const barHeight = 52.0;
  const barMargin = 8.0;

  final showAbove = messageRect.top > statusBarHeight + barHeight + barMargin;
  final barTop = showAbove
      ? messageRect.top - barHeight - barMargin
      : messageRect.bottom + barMargin;
  final clampedTop = barTop.clamp(
    statusBarHeight + barMargin,
    screenHeight - barHeight - barMargin,
  );

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss reactions',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.0).animate(curved),
          alignment:
              isOutgoing ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, __) {
      return Stack(
        children: [
          Positioned(
            top: clampedTop,
            left: isOutgoing ? null : 16,
            right: isOutgoing ? 16 : null,
            child: _ReactionBar(
              onSelect: (emoji) => Navigator.of(context).pop(emoji),
              onPlusTap: () => Navigator.of(context).pop(_pickerSentinel),
            ),
          ),
        ],
      );
    },
  );
}

Future<String?> showEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.appBar,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _EmojiPickerGrid(
      onSelect: (emoji) => Navigator.of(context).pop(emoji),
    ),
  );
}

Future<void> handleReactionResult({
  required BuildContext context,
  required String? result,
  required void Function(String emoji) onReact,
}) async {
  if (result == null) return;
  if (result == _pickerSentinel) {
    final emoji = await showEmojiPickerSheet(context);
    if (emoji != null) onReact(emoji);
  } else {
    onReact(result);
  }
}

class _ReactionBar extends StatelessWidget {
  final ValueChanged<String> onSelect;
  final VoidCallback onPlusTap;

  const _ReactionBar({required this.onSelect, required this.onPlusTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.appBar,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._defaultReactions.map(
              (emoji) => _ReactionEmoji(
                emoji: emoji,
                onTap: () => onSelect(emoji),
              ),
            ),
            _PlusButton(onTap: onPlusTap),
          ],
        ),
      ),
    );
  }
}

class _ReactionEmoji extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionEmoji({required this.emoji, required this.onTap});

  @override
  State<_ReactionEmoji> createState() => _ReactionEmojiState();
}

class _ReactionEmojiState extends State<_ReactionEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.35)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 50),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _controller.forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}

class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: AppColors.divider,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: AppColors.textPrimary, size: 20),
      ),
    );
  }
}

class _EmojiPickerGrid extends StatelessWidget {
  final ValueChanged<String> onSelect;

  const _EmojiPickerGrid({required this.onSelect});

  static const _emojis = [
    // Smileys
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂',
    '🙂', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘',
    '😋', '😛', '😜', '🤪', '😝', '🤗', '🤭', '🤔',
    '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😌',
    '😔', '😪', '😴', '😷', '🤒', '🤕', '🤢', '🤮',
    '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎',
    '🤓', '😕', '😟', '🙁', '😮', '😯', '😲', '😳',
    '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭',
    // Gestures
    '👍', '👎', '👏', '🤝', '🙌', '💪', '🤞', '✌️',
    '🤘', '👌', '🫶', '🙏', '👋', '✋', '🤚', '🖐️',
    // Hearts & symbols
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '💖', '💕', '❣️', '💔', '💯', '💢', '💥', '💫',
    '⭐', '✨', '💎', '🔥', '✅', '❌', '⚡', '💦',
    // Celebrations
    '🎉', '🎊', '🎂', '🎁', '🏆', '🥇', '🎯', '🎵',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: _emojis.length,
              itemBuilder: (_, index) {
                final emoji = _emojis[index];
                return GestureDetector(
                  onTap: () => onSelect(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
