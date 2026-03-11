import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../cubit/chat_cubit.dart';

class ContactPickerScreen extends StatefulWidget {
  final String channelId;

  const ContactPickerScreen({super.key, required this.channelId});

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Contact> _contacts = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final hasPermission = await FlutterContacts.requestPermission();
      if (!hasPermission) {
        setState(() {
          _isLoading = false;
          _error = 'Contacts permission denied.';
        });
        return;
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );

      contacts.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

      final validContacts = contacts
          .where((contact) => contact.phones.isNotEmpty)
          .toList();

      setState(() {
        _contacts = validContacts;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _error = 'Unable to load contacts.';
      });
    }
  }

  List<Contact> get _filteredContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((contact) {
      final name = contact.displayName.toLowerCase();
      final phone = contact.phones.isNotEmpty
          ? contact.phones.first.number
          : '';
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  Future<void> _onContactTap(Contact contact) async {
    final phone = contact.phones.first.number;
    final shouldSend = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.appBar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send contact',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _ContactRow(
                  name: contact.displayName,
                  phone: phone,
                  photo: contact.photo,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Send Contact'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldSend != true || !mounted) return;

    await context.read<ChatCubit>().sendContactMessage(
      widget.channelId,
      name: contact.displayName,
      phone: phone,
      contactId: contact.id,
      photo: contact.photo,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _filteredContacts;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.appBar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Select contact',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.iconMuted,
                ),
                filled: true,
                fillColor: AppColors.inputBar,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 44,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton(
                            onPressed: _loadContacts,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    interactive: true,
                    child: ListView.separated(
                      itemCount: contacts.length,
                      separatorBuilder: (context, index) => Divider(
                        color: AppColors.divider.withValues(alpha: 0.5),
                        indent: 72,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final phone = contact.phones.isNotEmpty
                            ? contact.phones.first.number
                            : '';
                        return ListTile(
                          onTap: () => _onContactTap(contact),
                          leading: _ContactAvatar(
                            name: contact.displayName,
                            photo: contact.photo,
                          ),
                          title: Text(
                            contact.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String phone;
  final Uint8List? photo;

  const _ContactRow({
    required this.name,
    required this.phone,
    required this.photo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ContactAvatar(name: name, photo: photo, radius: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactAvatar extends StatelessWidget {
  final String name;
  final Uint8List? photo;
  final double radius;

  const _ContactAvatar({
    required this.name,
    required this.photo,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final firstChar = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : '?';
    if (photo != null && photo!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: MemoryImage(photo!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.iconMuted.withValues(alpha: 0.28),
      child: Text(
        firstChar,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
