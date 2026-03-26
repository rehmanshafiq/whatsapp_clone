import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ForwardedLabel extends StatelessWidget {
  const ForwardedLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forward,
              size: 13,
              color: AppColors.iconMuted,
            ),
            SizedBox(width: 4),
            Text(
              'Forwarded',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
