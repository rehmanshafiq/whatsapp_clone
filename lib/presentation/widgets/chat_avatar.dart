import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final String? heroTag;

  const ChatAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 26,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = _buildAvatar();
    if (heroTag != null) {
      return Hero(tag: heroTag!, child: avatar);
    }
    return avatar;
  }

  Widget _buildAvatar() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, _) => _PlaceholderAvatar(name: name, radius: radius),
          errorWidget: (_, _, _) => _PlaceholderAvatar(name: name, radius: radius),
        ),
      );
    }
    return _PlaceholderAvatar(name: name, radius: radius);
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const _PlaceholderAvatar({required this.name, required this.radius});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.divider,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}
