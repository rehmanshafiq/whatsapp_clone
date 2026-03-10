import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message.dart';
import 'message_status_icon.dart';

class LocationMessageBubble extends StatelessWidget {
  final Message message;

  const LocationMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final subtitle = (message.locationAddress ?? '').trim().isNotEmpty
        ? message.locationAddress!.trim()
        : _formatCoordinates(message);
    final liveStatus = message.isLiveLocation
        ? message.isLiveLocationActive
              ? 'Live until ${_formatClock(message.liveLocationEndsAt ?? message.timestamp)}'
              : 'Live location ended'
        : 'Tap to view shared location';

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        margin: EdgeInsets.only(
          left: isOutgoing ? 64 : 8,
          right: isOutgoing ? 8 : 64,
          top: 2,
          bottom: 2,
        ),
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
            Container(
              height: 132,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.9),
                    const Color(0xFF128C7E),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        color: Colors.black.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _MapGridPainter()),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  if (message.isLiveLocation)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location,
                              size: 13,
                              color: message.isLiveLocationActive
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              message.isLiveLocationActive ? 'LIVE' : 'ENDED',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.locationName?.trim().isNotEmpty == true
                        ? message.locationName!.trim()
                        : (message.isLiveLocation
                              ? 'Live location'
                              : 'Current location'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    liveStatus,
                    style: TextStyle(
                      color: message.isLiveLocationActive
                          ? const Color(0xFF7BF0A8)
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: message.isLiveLocationActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        child: Text(
                          _formatClock(message.timestamp),
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.78,
                            ),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (isOutgoing)
                        MessageStatusIcon(status: message.status, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCoordinates(Message message) {
    final latitude = message.latitude;
    final longitude = message.longitude;
    if (latitude == null || longitude == null) {
      return 'Coordinates unavailable';
    }
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  String _formatClock(DateTime time) {
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = time.hour % 12;
    return '${hourRaw == 0 ? 12 : hourRaw}:${time.minute.toString().padLeft(2, '0')} $period';
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const step = 28.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
