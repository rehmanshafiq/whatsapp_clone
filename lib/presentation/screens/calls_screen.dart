import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Placeholder for the Calls tab until call features are implemented.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone, size: 64, color: AppColors.iconMuted),
            SizedBox(height: 16),
            Text(
              'Calls',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
