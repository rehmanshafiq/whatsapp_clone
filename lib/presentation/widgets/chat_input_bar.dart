import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:social_media_recorder/audio_encoder_type.dart';
import 'package:social_media_recorder/screen/social_media_recorder.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/permission_utils.dart';
import '../../data/models/message.dart';
import '../cubit/chat_cubit.dart';
import 'attachment_sheet.dart';
import 'gif_picker_widget.dart';
import 'sticker_picker_widget.dart';
import '../screens/camera_screen.dart';


class ChatInputBar extends StatefulWidget {
  final String channelId;
  final ValueChanged<String> onSend;
  final void Function(File audioFile, Duration duration) onSendAudio;
  final void Function(String mediaUrl, bool isSticker) onSendMedia;
  /// Called when user begins typing. Re-sent on keystrokes to reset server 4s TTL.
  final VoidCallback? onTypingStart;
  /// Called when user stops typing (input cleared, message sent, or screen left).
  final VoidCallback? onTypingStop;
  /// Called when user starts recording audio.
  final VoidCallback? onRecordingStart;
  /// Called when user stops/cancels/sends recording.
  final VoidCallback? onRecordingStop;
  final Message? replyingTo;
  final VoidCallback? onCancelReply;

  const ChatInputBar({
    super.key,
    required this.channelId,
    required this.onSend,
    required this.onSendAudio,
    required this.onSendMedia,
    this.onTypingStart,
    this.onTypingStop,
    this.onRecordingStart,
    this.onRecordingStop,
    this.replyingTo,
    this.onCancelReply,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _textFocusNode = FocusNode();

  bool _hasText = false;
  bool _isEmojiVisible = false;

  /// True only after microphone permission has been granted AND the user
  /// has long-pressed to activate the recorder widget.
  bool _isRecorderActive = false;

  String? _voiceNoteDir;
  late final TabController _tabController;

  /// Throttle: re-send typing_start every 2 s while typing to reset server TTL.
  Timer? _typingThrottleTimer;
  bool _typingSent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _controller.addListener(_onTextChanged);
    _initVoiceDir();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasReplying = oldWidget.replyingTo != null;
    final isReplying = widget.replyingTo != null;
    if (!wasReplying && isReplying) {
      if (_isEmojiVisible) {
        setState(() => _isEmojiVisible = false);
      }
      // Ensure keyboard opens when user taps "Reply".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _textFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.onTypingStop?.call();
    widget.onRecordingStop?.call();
    _typingThrottleTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _tabController.dispose();
    _controller.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
    }
    if (has) {
      if (!_typingSent) {
        _typingSent = true;
        widget.onTypingStart?.call();
      }
      _scheduleTypingRefresh();
    } else {
      _typingSent = false;
      _typingThrottleTimer?.cancel();
      _typingThrottleTimer = null;
      widget.onTypingStop?.call();
    }
  }

  /// Re-send typing_start every 2 s while the user types to reset the
  /// server's 4 s TTL.
  void _scheduleTypingRefresh() {
    _typingThrottleTimer?.cancel();
    if (!mounted || _controller.text.trim().isEmpty) return;
    _typingThrottleTimer = Timer(const Duration(seconds: 2), () {
      _typingThrottleTimer = null;
      if (!mounted) return;
      if (_controller.text.trim().isEmpty) return;
      widget.onTypingStart?.call();
      _scheduleTypingRefresh();
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    widget.onTypingStop?.call();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Voice-note helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initVoiceDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${dir.path}/voice_notes');
    if (!voiceDir.existsSync()) {
      voiceDir.createSync(recursive: true);
    }
    if (mounted) {
      setState(() => _voiceNoteDir = voiceDir.path);
    }
  }

  Duration _parseRecordingTime(String time) {
    final parts = time.split(':');
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]) ?? 0;
      final seconds = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: minutes, seconds: seconds);
    }
    return Duration.zero;
  }

  /// The recorder produces filenames with colons from timestamps
  /// (e.g. `2026-03-03-14:12.m4a`). Android's MediaPlayer rejects colons
  /// in file paths. Copy to a safely named file in app-documents.
  Future<File?> _ensureSafePath(File source) async {
    if (!source.existsSync() || source.lengthSync() == 0) return null;

    final dir = _voiceNoteDir;
    if (dir == null) return null;

    final safeName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final dest = File('$dir/$safeName');

    try {
      await source.copy(dest.path);
      try {
        await source.delete();
      } catch (_) {}
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleAudioSend(File soundFile, String time) async {
    widget.onRecordingStop?.call();

    final duration = _parseRecordingTime(time);
    if (duration.inSeconds < 1) {
      try {
        soundFile.deleteSync();
      } catch (_) {}
      return;
    }

    // Small delay to ensure the recorder has fully flushed the file to disk.
    await Future.delayed(const Duration(milliseconds: 300));

    final safeFile = await _ensureSafePath(soundFile);
    if (safeFile != null) {
      widget.onSendAudio(safeFile, duration);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Permission helper — REQUEST and only activate recorder when granted
  // ─────────────────────────────────────────────────────────────────────────

  /// Called when the user long-presses the placeholder mic button.
  ///
  /// Key fix: we call [Permission.microphone.request()] (not just .status)
  /// so the OS permission dialog is actually shown on the first press.
  /// We only set [_isRecorderActive] = true when the result is [isGranted].
  Future<void> _requestMicAndActivate() async {
    // request() shows the OS dialog on first call; returns cached result after.
    final status = await Permission.microphone.request();
    if (!mounted) return;

    if (status.isGranted) {
      // ✅ Permission granted — swap in the real SocialMediaRecorder widget.
      setState(() => _isRecorderActive = true);
    } else if (status.isPermanentlyDenied) {
      // User tapped "Never ask again" — guide them to Settings.
      if (context.mounted) {
        await PermissionUtils.requestPermission(
          context,
          Permission.microphone,
          title: 'Microphone Permission',
          message:
          'Microphone permission is required to record voice notes. '
              'Please allow it in Settings.',
        );
      }
    }
    // status.isDenied → user tapped "Deny" on the OS dialog.
    // Do nothing; they can long-press again to be prompted once more
    // (Android allows re-prompting until they choose "Never ask again").
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Emoji picker
  // ─────────────────────────────────────────────────────────────────────────

  void _toggleEmojiPicker() {
    if (_isEmojiVisible) {
      setState(() => _isEmojiVisible = false);
      _textFocusNode.requestFocus();
    } else {
      _textFocusNode.unfocus();
      setState(() => _isEmojiVisible = true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input bar — single stable layout, keyboard never closes.
          Container(
            color: AppColors.scaffold,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: _buildInputRow(),
          ),

          // Emoji / GIF / Sticker picker panel
          if (_isEmojiVisible)
            SizedBox(
              height: 320,
              child: Column(
                children: [
                  Container(
                    height: 40,
                    color: AppColors.appBar,
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.accent,
                      labelColor: AppColors.accent,
                      unselectedLabelColor: AppColors.iconMuted,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(icon: Icon(Icons.emoji_emotions_outlined)),
                        Tab(text: 'GIF'),
                        Tab(icon: Icon(Icons.sticky_note_2_outlined)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildEmojiPicker(),
                        GifPickerWidget(
                          onGifSelected: (url) =>
                              widget.onSendMedia(url, false),
                        ),
                        StickerPickerWidget(
                          onStickerSelected: (url) =>
                              widget.onSendMedia(url, true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reply preview
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReplyPreview(Message replyingTo) {
    final cubit = context.read<ChatCubit>();
    final myBackendId = cubit.repository.getCurrentUserId();
    final sid = replyingTo.senderId;
    final isMe = replyingTo.isOutgoing ||
        sid == AppConstants.currentUserId ||
        (myBackendId != null && myBackendId.isNotEmpty && sid == myBackendId);

    final replySender =
    isMe ? 'You' : (cubit.state.selectedChannel?.name ?? sid);

    String replyText = replyingTo.text.trim();
    if (replyText.isEmpty) {
      if (replyingTo.isImage) {
        replyText = 'Photo';
      } else if (replyingTo.isVideo) {
        replyText = 'Video';
      } else if (replyingTo.isAudio) {
        replyText = 'Voice message';
      } else if (replyingTo.isDocument) {
        replyText = replyingTo.documentFileName ?? 'Document';
      } else if (replyingTo.isLocation) {
        replyText = 'Location';
      } else if (replyingTo.isGif) {
        replyText = 'GIF';
      } else if (replyingTo.isSticker) {
        replyText = 'Sticker';
      }
    }

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppColors.scaffold.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured left bar
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      replySender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      replyText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 2),
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: AppColors.iconMuted, size: 18),
                  onPressed: widget.onCancelReply,
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Input row (Stack layout so recorder can expand freely)
  // ─────────────────────────────────────────────────────────────────────────

  /// Single stable layout.
  ///
  /// The TextField is ALWAYS in the tree (keyboard never closes).
  /// When text is present the send button replaces the mic at the trailing end.
  ///
  /// The recorder sits in a Stack so that when the user holds the mic and the
  /// recorder widget expands to full width, it can do so freely — it is NOT
  /// constrained inside the Row next to the TextField.
  Widget _buildInputRow() {
    const double trailingWidth = 54.0;

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        // ── Bottom layer: text field with reserved space for trailing button ──
        Row(
          children: [
            Expanded(child: _buildTextField()),
            const SizedBox(width: trailingWidth),
          ],
        ),

        // ── Top layer: send button OR recorder ──────────────────────────────
        if (_hasText)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _CircleButton(icon: Icons.send, onPressed: _send),
          )
        else if (_voiceNoteDir != null)
          _isRecorderActive
          // ── Real recorder (permission already granted) ──────────────
              ? SocialMediaRecorder(
            sendRequestFunction: (File soundFile, String time) {
              _handleAudioSend(soundFile, time);
            },
            startRecording: () async {
              widget.onTypingStop?.call();
              widget.onRecordingStart?.call();

              // Guard: if permission was revoked after the widget was
              // activated, reset to the placeholder mic so the user goes
              // through the proper request flow again.
              final status = await Permission.microphone.status;
              if (!status.isGranted && mounted) {
                setState(() => _isRecorderActive = false);
              }
            },

            stopRecording: (_) {
              widget.onRecordingStop?.call();
            },
            storeSoundRecoringPath: _voiceNoteDir,
            encode: AudioEncoderType.AAC,
            initRecordPackageWidth: 48,
            fullRecordPackageHeight: 48,
            recordIcon: const _CircleButton(icon: Icons.mic),
            recordIconWhenLockedRecord: const Icon(
              Icons.send,
              color: Colors.white,
              size: 22,
            ),
            recordIconBackGroundColor: AppColors.accent,
            recordIconWhenLockBackGroundColor: AppColors.accent,
            backGroundColor: AppColors.inputBar,
            counterBackGroundColor: AppColors.inputBar,
            slideToCancelText: '  Slide to cancel  ◀',
            slideToCancelTextStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            cancelTextStyle: const TextStyle(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            counterTextStyle: const TextStyle(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            cancelTextBackGroundColor: AppColors.inputBar,
            sendButtonIcon: const Icon(
              Icons.send,
              color: Colors.white,
              size: 22,
            ),
            lockButton: const Icon(
              Icons.lock,
              color: AppColors.textSecondary,
              size: 20,
            ),
            radius: BorderRadius.circular(24),
          )
          // ── Placeholder mic (permission not yet granted / checked) ──
              : GestureDetector(
            onLongPressStart: (_) => _requestMicAndActivate(),
            child: const _CircleButton(icon: Icons.mic),
          )
        else
        // _voiceNoteDir still loading — show non-interactive mic
          const _CircleButton(icon: Icons.mic),
      ],
    );
  }

  Widget _buildEmojiPicker() {
    return EmojiPicker(
      // This automatically inserts/deletes emoji at the current cursor
      // position in the linked TextField:
      textEditingController: _controller,

      // Optional callbacks – you can hook analytics/metrics here.
      onEmojiSelected: (category, emoji) {
        setState(() => _isEmojiVisible = false);
      },
      onBackspacePressed: () {
        // Backspace is also handled automatically for the controller.
      },

      config: Config(
        height: 280,
        checkPlatformCompatibility: true,
        // Slightly larger on iOS to match native feel
        emojiViewConfig: EmojiViewConfig(
          columns: 8,
          emojiSizeMax: 28 *
              (foundation.defaultTargetPlatform ==
                  TargetPlatform.iOS
                  ? 1.20
                  : 1.0),
          backgroundColor: AppColors.chatBackground,
          gridPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          recentsLimit: 40,
        ),
        // Enable skin tones
        skinToneConfig: const SkinToneConfig(),
        // Category bar (top)
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: AppColors.appBar,
          indicatorColor: AppColors.accent,
          iconColor: AppColors.iconMuted,
          iconColorSelected: AppColors.accent,
          backspaceColor: AppColors.accent,
          initCategory: Category.RECENT,
          recentTabBehavior: RecentTabBehavior.RECENT,
        ),
        // Bottom action bar (search + backspace)
        bottomActionBarConfig: BottomActionBarConfig(
          enabled: true,
          showBackspaceButton: true,
          showSearchViewButton: true,
          backgroundColor: AppColors.appBar,
          buttonColor: AppColors.accent,
          buttonIconColor: AppColors.textPrimary,
        ),
        // Search bar
        searchViewConfig: SearchViewConfig(
          backgroundColor: AppColors.appBar,
          buttonIconColor: AppColors.textSecondary,
          hintText: 'Search emoji',
        ),
        // Layout order: top = categories, middle = emojis, bottom = search
        viewOrderConfig: const ViewOrderConfig(
          top: EmojiPickerItem.categoryBar,
          middle: EmojiPickerItem.emojiView,
          bottom: EmojiPickerItem.searchBar,
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBar,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.replyingTo != null) _buildReplyPreview(widget.replyingTo!),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isEmojiVisible
                      ? Icons.keyboard
                      : Icons.emoji_emotions_outlined,
                  color: AppColors.iconMuted,
                ),
                onPressed: _toggleEmojiPicker,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _textFocusNode,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  minLines: 1,
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppColors.iconMuted),
                onPressed: () async {
                  final granted = await PermissionUtils.requestStoragePermission(context);
                  if (granted && context.mounted) {
                    showAttachmentSheet(context, widget.channelId);
                  }
                },
              ),

              // Camera icon only visible when no text has been entered
              if (!_hasText)
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: AppColors.iconMuted),
                  onPressed: () async {
                    final granted = await PermissionUtils.requestPermission(
                      context,
                      Permission.camera,
                      title: 'Camera Permission',
                      message: 'Camera permission is required to take photos and videos. Please allow it in settings.',
                    );
                    if (granted && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CameraScreen(channelId: widget.channelId),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _CircleButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.accent,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}