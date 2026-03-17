import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../cubit/chat_cubit.dart';
import '../widgets/document_list_item.dart';

class DocumentPickerScreen extends StatefulWidget {
  final String channelId;

  const DocumentPickerScreen({super.key, required this.channelId});

  @override
  State<DocumentPickerScreen> createState() => _DocumentPickerScreenState();
}

class _DocumentPickerScreenState extends State<DocumentPickerScreen> {
  final List<PickedDocument> _documents = [];
  bool _isLoading = false;
  String? _error;

  Future<void> _pickDocuments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
        withReadStream: false,
      );

      if (!mounted) return;

      if (result != null && result.files.isNotEmpty) {
        final newDocs = <PickedDocument>[];
        for (final file in result.files) {
          if (file.path != null && file.path!.isNotEmpty) {
            newDocs.add(PickedDocument.fromPlatformFile(file));
          } else if (file.name.isNotEmpty && file.size >= 0) {
            // Some platforms may not return path; we still show the file but sending may fail
            newDocs.add(PickedDocument(
              path: file.path ?? '',
              name: file.name,
              size: file.size,
              lastModified: null,
            ));
          }
        }
        setState(() {
          _documents.addAll(newDocs);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not access files. ${e.toString()}';
        });
      }
    }
  }

  void _removeDocument(int index) {
    setState(() => _documents.removeAt(index));
  }

  /// Copies the picked file to app documents so the path stays valid for opening later.
  Future<String?> _copyToAppDocuments(String sourcePath, String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final docsDir = Directory('${appDir.path}/documents');
      if (!await docsDir.exists()) {
        await docsDir.create(recursive: true);
      }
      final safeName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final destFile = File('${docsDir.path}/$uniqueName');
      await File(sourcePath).copy(destFile.path);
      return destFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendDocuments() async {
    if (_documents.isEmpty) return;

    final cubit = context.read<ChatCubit>();
    final channelId = widget.channelId;

    setState(() => _isLoading = true);

    try {
      for (final doc in _documents) {
        if (doc.path.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not send "${doc.name}": file path unavailable.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          continue;
        }
        final persistentPath = await _copyToAppDocuments(doc.path, doc.name);
        if (persistentPath == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not save "${doc.name}" for sending.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          continue;
        }
        await cubit.sendDocumentMessage(
          channelId,
          filePath: persistentPath,
          fileName: doc.name,
          fileSize: doc.size,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.appBar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Send Document',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: Colors.red.shade900.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _isLoading && _documents.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.accent),
                        SizedBox(height: 16),
                        Text(
                          'Opening file picker...',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _documents.isEmpty
                    ? _EmptyState(onTap: _pickDocuments)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _documents.length,
                        itemBuilder: (context, index) {
                          final doc = _documents[index];
                          return DocumentListItem(
                            document: doc,
                            isSelected: true,
                            onRemove: () => _removeDocument(index),
                          );
                        },
                      ),
          ),
          if (_documents.isNotEmpty)
            _SendBar(
              count: _documents.length,
              onSend: _sendDocuments,
              onAddMore: _pickDocuments,
              isLoading: _isLoading,
            ),
        ],
      ),
      floatingActionButton: _documents.isEmpty && !_isLoading
          ? null
          : _documents.isNotEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _isLoading ? null : _pickDocuments,
                  backgroundColor: AppColors.accent,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Browse',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF7B1FA2).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.insert_drive_file,
                size: 40,
                color: Color(0xFF7B1FA2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No documents selected',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Browse" to choose a file from your device.\nPDF, Word, Excel, and more.',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('Browse files'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendBar extends StatelessWidget {
  final int count;
  final VoidCallback onSend;
  final VoidCallback onAddMore;
  final bool isLoading;

  const _SendBar({
    required this.count,
    required this.onSend,
    required this.onAddMore,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.appBar,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: isLoading ? null : onAddMore,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.accent),
              tooltip: 'Add more',
            ),
            Expanded(
              child: Text(
                count == 1
                    ? '1 document selected'
                    : '$count documents selected',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: isLoading ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
              label: Text(isLoading ? 'Sending...' : 'Send'),
            ),
          ],
        ),
      ),
    );
  }
}
