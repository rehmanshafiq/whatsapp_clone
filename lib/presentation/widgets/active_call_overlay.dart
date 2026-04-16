import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/webrtc_call_manager.dart';
import 'chat_avatar.dart';

/// Full-screen WhatsApp-style in-call UI driven by [WebRtcCallManager].
class ActiveCallOverlay extends StatefulWidget {
  const ActiveCallOverlay({super.key, required this.manager});

  final WebRtcCallManager manager;

  @override
  State<ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<ActiveCallOverlay> {
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _renderersReady = false;

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_onManager);
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _local.initialize();
    await _remote.initialize();
    _syncStreams();
    if (mounted) {
      setState(() => _renderersReady = true);
    }
  }

  void _onManager() {
    _syncStreams();
    if (mounted) setState(() {});
  }

  void _syncStreams() {
    final m = widget.manager;
    _local.srcObject = m.localStream;
    _remote.srcObject = m.remoteStream;
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManager);
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final phase = m.phase;

    return Material(
      color: const Color(0xFF0B141A),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (m.isVideo &&
                phase == CallSessionPhase.connected &&
                m.remoteStream != null &&
                _renderersReady)
              ColoredBox(
                color: Colors.black,
                child: RTCVideoView(
                  _remote,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              _BlurredAvatarBackdrop(
                name: m.peerDisplayName,
                avatarUrl: m.peerAvatarUrl,
                isVideo: m.isVideo,
              ),
            if (m.isVideo &&
                phase == CallSessionPhase.connected &&
                _renderersReady)
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 108,
                    height: 152,
                    child: ColoredBox(
                      color: Colors.black87,
                      child: RTCVideoView(
                        _local,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 20,
              right: 20,
              top: 24,
              child: Column(
                children: [
                  Text(
                    m.peerDisplayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusLabel(phase, m),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.95),
                      fontSize: 15,
                    ),
                  ),
                  if (phase == CallSessionPhase.connected) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatDuration(m.connectedDuration),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: _CallControls(
                phase: phase,
                isVideo: m.isVideo,
                micOn: m.isMicEnabled,
                onAccept: m.acceptIncoming,
                onReject: () => m.rejectIncoming(reason: 'rejected'),
                onHangUp: () => m.hangUp(),
                onToggleMute: m.toggleMute,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(CallSessionPhase phase, WebRtcCallManager m) {
    switch (phase) {
      case CallSessionPhase.ringingOut:
        return m.isVideo ? 'Calling…' : 'Calling…';
      case CallSessionPhase.ringingIn:
        return m.isVideo ? 'Incoming video call' : 'Incoming voice call';
      case CallSessionPhase.connecting:
        return 'Connecting…';
      case CallSessionPhase.connected:
        return m.isVideo ? 'Video' : 'Voice';
      case CallSessionPhase.idle:
        return '';
    }
  }
}

class _BlurredAvatarBackdrop extends StatelessWidget {
  const _BlurredAvatarBackdrop({
    required this.name,
    required this.avatarUrl,
    required this.isVideo,
  });

  final String name;
  final String? avatarUrl;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF1A2329),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 48),
          ChatAvatar(
            imageUrl: avatarUrl,
            name: name,
            radius: 72,
            heroTag: null,
            isGroup: false,
          ),
          const SizedBox(height: 28),
          Icon(
            isVideo ? Icons.videocam : Icons.call,
            size: 40,
            color: AppColors.accent.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.phase,
    required this.isVideo,
    required this.micOn,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onToggleMute,
  });

  final CallSessionPhase phase;
  final bool isVideo;
  final bool micOn;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    if (phase == CallSessionPhase.ringingIn) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundCallButton(
            color: const Color(0xFFE53935),
            icon: Icons.call_end,
            onPressed: onReject,
          ),
          _RoundCallButton(
            color: AppColors.accent,
            icon: Icons.call,
            onPressed: onAccept,
          ),
        ],
      );
    }

    if (phase == CallSessionPhase.connected) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundCallButton(
            color: AppColors.appBar,
            icon: micOn ? Icons.mic : Icons.mic_off,
            onPressed: onToggleMute,
          ),
          _RoundCallButton(
            color: const Color(0xFFE53935),
            icon: Icons.call_end,
            onPressed: onHangUp,
          ),
        ],
      );
    }

    // ringingOut / connecting
    return Center(
      child: _RoundCallButton(
        color: const Color(0xFFE53935),
        icon: Icons.call_end,
        onPressed: onHangUp,
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.color,
    required this.icon,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
