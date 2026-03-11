import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/message.dart';
import 'document_list_item.dart' show formatFileSize;
import 'message_status_icon.dart';

class DocumentMessageBubble extends StatelessWidget {
  final Message message;

  const DocumentMessageBubble({super.key, required this.message});

  static IconData _iconForName(String? name) {
    if (name == null || name.isEmpty) return Icons.insert_drive_file;
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

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final period = message.timestamp.hour >= 12 ? 'PM' : 'AM';
    final hourRaw = message.timestamp.hour % 12;
    final time =
        '${hourRaw == 0 ? 12 : hourRaw}:${message.timestamp.minute.toString().padLeft(2, '0')} $period';
    final fileName = message.documentFileName ?? 'Document';
    final fileSize = message.documentFileSize ?? 0;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDocument(context),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: EdgeInsets.only(
            left: isOutgoing ? 64 : 8,
            right: isOutgoing ? 8 : 64,
            top: 2,
            bottom: 2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _iconForName(message.documentFileName),
                      color: const Color(0xFF7B1FA2),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (fileSize > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatFileSize(fileSize),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.download_outlined,
                    size: 22,
                    color: AppColors.accent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  if (isOutgoing) ...[
                    const SizedBox(width: 4),
                    MessageStatusIcon(status: message.status, size: 14),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDocument(BuildContext context) async {
    final path = message.mediaUrl;
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is not available.')),
        );
      }
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File no longer exists.')),
        );
      }
      return;
    }
    try {
      final result = await OpenFile.open(path);
      if (!context.mounted) return;
      switch (result.type) {
        case ResultType.done:
          break;
        case ResultType.noAppToOpen:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No app found to open this file.')),
          );
          break;
        case ResultType.fileNotFound:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File not found.')),
          );
          break;
        case ResultType.permissionDenied:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission denied to open file.')),
          );
          break;
        case ResultType.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: ${result.message}')),
          );
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }
}
