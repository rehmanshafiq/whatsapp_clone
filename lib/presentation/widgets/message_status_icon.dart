import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message_status.dart';

class MessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  final double size;

  const MessageStatusIcon({super.key, required this.status, this.size = 16});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(
          Icons.schedule, // WhatsApp-style sending clock
          size: size,
          color: AppColors.textSecondary,
        );
      case MessageStatus.sent:
        return Icon(Icons.done, size: size, color: AppColors.textSecondary);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: size, color: AppColors.textSecondary);
      case MessageStatus.seen:
        return Icon(Icons.done_all, size: size, color: AppColors.seenTick);
    }
  }
}
