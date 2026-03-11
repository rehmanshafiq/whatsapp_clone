import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Represents a selected document for the picker list.
class PickedDocument {
  final String path;
  final String name;
  final int size;
  final DateTime? lastModified;

  const PickedDocument({
    required this.path,
    required this.name,
    required this.size,
    this.lastModified,
  });

  static PickedDocument fromPlatformFile(PlatformFile file) {
    DateTime? modified;
    if (file.path != null) {
      try {
        final f = File(file.path!);
        if (f.existsSync()) {
          modified = f.lastModifiedSync();
        }
      } catch (_) {}
    }
    return PickedDocument(
      path: file.path ?? '',
      name: file.name,
      size: file.size,
      lastModified: modified,
    );
  }
}

/// Formats byte size to human-readable string (e.g. "1.2 MB").
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// WhatsApp-style list item for a document: icon, filename, size, last modified.
class DocumentListItem extends StatelessWidget {
  final PickedDocument document;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const DocumentListItem({
    super.key,
    required this.document,
    this.isSelected = false,
    this.onTap,
    this.onRemove,
  });

  IconData _iconForName(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF7B1FA2).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForName(document.name),
                  color: const Color(0xFF7B1FA2),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      document.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          formatFileSize(document.size),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (document.lastModified != null) ...[
                          const Text(
                            ' • ',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          Text(
                            _formatDate(document.lastModified),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                )
              else if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.accent,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
