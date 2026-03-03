import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:social_media_recorder/audio_encoder_type.dart';
import 'package:social_media_recorder/screen/social_media_recorder.dart';

import '../../core/theme/app_theme.dart';

class ChatInputBar extends StatefulWidget {
  final ValueChanged<String> onSend;
  final void Function(File audioFile, Duration duration) onSendAudio;

  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onSendAudio,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;
  String? _voiceNoteDir;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _initVoiceDir();
  }

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
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
  /// (e.g. `22026-03-03-14:12.m4a`). Android's MediaPlayer rejects colons
  /// in file paths. Copy to a safely named file in app-documents.
  Future<File?> _ensureSafePath(File source) async {
    if (!source.existsSync() || source.lengthSync() == 0) return null;

    final dir = _voiceNoteDir;
    if (dir == null) return null;

    final safeName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final dest = File('$dir/$safeName');

    try {
      await source.copy(dest.path);
      try { await source.delete(); } catch (_) {}
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleAudioSend(File soundFile, String time) async {
    final duration = _parseRecordingTime(time);
    if (duration.inSeconds < 1) {
      try { soundFile.deleteSync(); } catch (_) {}
      return;
    }

    // Small delay to ensure the recorder has flushed the file
    await Future.delayed(const Duration(milliseconds: 300));

    final safeFile = await _ensureSafePath(soundFile);
    if (safeFile != null) {
      widget.onSendAudio(safeFile, duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: AppColors.scaffold,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: _hasText ? _buildTextMode() : _buildRecorderMode(),
      ),
    );
  }

  Widget _buildTextMode() {
    return Row(
      children: [
        Expanded(child: _buildTextField()),
        const SizedBox(width: 6),
        _CircleButton(icon: Icons.send, onPressed: _send),
      ],
    );
  }

  /// The SocialMediaRecorder expands to full screen width when recording
  /// starts. It MUST be the only child in its row — placing it beside the
  /// text field causes overflow. Use a Stack so the recorder overlays the
  /// text field during recording.
  Widget _buildRecorderMode() {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Row(
          children: [
            Expanded(child: _buildTextField(showCamera: true)),
            const SizedBox(width: 54),
          ],
        ),
        if (_voiceNoteDir != null)
          SocialMediaRecorder(
            sendRequestFunction: (File soundFile, String time) {
              _handleAudioSend(soundFile, time);
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
        else
          const _CircleButton(icon: Icons.mic),
      ],
    );
  }

  Widget _buildTextField({bool showCamera = false}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBar,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined,
                color: AppColors.iconMuted),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 16),
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
            onPressed: () {},
          ),
          if (showCamera)
            IconButton(
              icon: const Icon(Icons.camera_alt, color: AppColors.iconMuted),
              onPressed: () {},
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
