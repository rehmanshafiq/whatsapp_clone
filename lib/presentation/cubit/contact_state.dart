import 'package:equatable/equatable.dart';

import '../../data/models/user.dart';

class ContactState extends Equatable {
  final List<User> contacts;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  const ContactState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  ContactState copyWith({
    List<User>? contacts,
    bool? isLoading,
    String? error,
    String? searchQuery,
    bool clearError = false,
  }) {
    return ContactState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<User> get filteredContacts {
    if (searchQuery.isEmpty) return contacts;
    final query = searchQuery.toLowerCase();
    return contacts.where((c) => c.name.toLowerCase().contains(query)).toList();
  }

  @override
  List<Object?> get props => [contacts, isLoading, error, searchQuery];
}
