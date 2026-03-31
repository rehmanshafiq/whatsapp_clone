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

  /// Requests storage/photos permission based on Android version.
  static Future<bool> requestStoragePermission(BuildContext context) async {
    // On Android 13+, we should check READ_MEDIA_IMAGES (mapped to Permission.photos)
    // On Android 12 and below, we check READ_EXTERNAL_STORAGE (mapped to Permission.storage)
    
    // Attempt photos first as it's the more specific modern one.
    // If it's not supported or not in manifest (older device), fallback to storage.
    Permission permissionToRequest = Permission.photos;
    
    // Check if the permission is available in the manifest/system.
    // status.isDenied is a safe check.
    try {
      final status = await Permission.photos.status;
      // Note: No permissions found in manifest error is thrown if we try to request 
      // something not there. But status usually doesn't throw, it just returns restricted.
    } catch (_) {
      permissionToRequest = Permission.storage;
    }

    return await requestPermission(
      context,
      permissionToRequest,
      title: permissionToRequest == Permission.photos ? 'Gallery Permission' : 'Storage Permission',
      message: 'Permission is required to access files. Please allow it in settings.',
    );
  }
}

