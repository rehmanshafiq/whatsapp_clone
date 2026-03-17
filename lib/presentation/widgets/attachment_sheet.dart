import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/theme/app_theme.dart';
import '../screens/camera_screen.dart';
import '../screens/contact_picker_screen.dart';
import '../screens/document_picker_screen.dart';
import '../screens/location_share_screen.dart';
import '../screens/media_preview_screen.dart';
import 'gallery_picker.dart';

/// Data model for each attachment option in the grid.
class AttachmentOption {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// Shows the WhatsApp-style attachment bottom sheet.
void showAttachmentSheet(BuildContext context, String channelId) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AttachmentSheet(channelId: channelId),
  );
}

class _AttachmentSheet extends StatelessWidget {
  final String channelId;
  const _AttachmentSheet({required this.channelId});

  // ── Callbacks ──────────────────────────────────────────

  void _openGallery(BuildContext context) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      if (!context.mounted) return;

      // Close attachment sheet first
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return GalleryPickerSheet(
            onAssetSelected: (asset) async {
              Navigator.pop(context);
              final file = await asset.file;
              if (file != null && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaPreviewScreen(
                      channelId: channelId,
                      mediaPath: file.path,
                      isVideo: asset.type == AssetType.video,
                    ),
                  ),
                );
              }
            },
          );
        },
      );
    }
  }

  void _openCamera(BuildContext context) {
    Navigator.pop(context); // Close attachment sheet
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(channelId: channelId)),
    );
  }

  void _shareLocation(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => LocationShareScreen(channelId: channelId),
      ),
    );
  }

  void _shareContact(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactPickerScreen(channelId: channelId),
      ),
    );
  }

  void _pickDocument(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentPickerScreen(channelId: channelId),
      ),
    );
  }
  void _pickAudio() => debugPrint('Pick Audio');
  void _createPoll() => debugPrint('Create Poll');

  @override
  Widget build(BuildContext context) {
    final options = [
      AttachmentOption(
        icon: Icons.photo,
        label: 'Gallery',
        color: const Color(0xFF7C4DFF),
        onTap: () => _openGallery(context),
      ),
      AttachmentOption(
        icon: Icons.camera_alt,
        label: 'Camera',
        color: const Color(0xFFE91E63),
        onTap: () => _openCamera(context),
      ),
      AttachmentOption(
        icon: Icons.location_on,
        label: 'Location',
        color: const Color(0xFF25D366),
        onTap: () => _shareLocation(context),
      ),
      AttachmentOption(
        icon: Icons.person,
        label: 'Contact',
        color: const Color(0xFF2196F3),
        onTap: () => _shareContact(context),
      ),
      AttachmentOption(
        icon: Icons.insert_drive_file,
        label: 'Document',
        color: const Color(0xFF7B1FA2),
        onTap: () => _pickDocument(context),
      ),
      // AttachmentOption(
      //   icon: Icons.headphones,
      //   label: 'Audio',
      //   color: const Color(0xFFFF5722),
      //   onTap: _pickAudio,
      // ),
      AttachmentOption(
        icon: Icons.poll,
        label: 'Poll',
        color: const Color(0xFF00BFA5),
        onTap: _createPoll,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.scaffold,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24, left: 20, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.iconMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // 3-column grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.95,
            children: options
                .map((opt) => AttachmentOptionItem(option: opt))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// A single attachment option item with a circular icon, label, and
/// scale animation on tap.
class AttachmentOptionItem extends StatefulWidget {
  final AttachmentOption option;

  const AttachmentOptionItem({super.key, required this.option});

  @override
  State<AttachmentOptionItem> createState() => _AttachmentOptionItemState();
}

class _AttachmentOptionItemState extends State<AttachmentOptionItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 0.1,
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _scaleCtrl.forward();
  void _onTapUp(TapUpDetails _) {
    _scaleCtrl.reverse();
    widget.option.onTap();
  }

  void _onTapCancel() => _scaleCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    final opt = widget.option;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular icon container with subtle dark-mode glow
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: opt.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: opt.color.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: opt.color.withValues(alpha: 0.20),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(opt.icon, color: opt.color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              opt.label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
