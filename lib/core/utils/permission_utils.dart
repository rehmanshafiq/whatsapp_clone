import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

class PermissionUtils {
  /// Requests a permission and shows a dialog if it's permanently denied.
  /// Returns true if granted, false otherwise.
  static Future<bool> requestPermission(
    BuildContext context,
    Permission permission, {
    required String title,
    required String message,
  }) async {
    final status = await permission.request();

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.appBar,
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.accent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    return false;
  }
}
