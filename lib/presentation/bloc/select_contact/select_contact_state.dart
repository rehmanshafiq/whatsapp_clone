part of 'select_contact_bloc.dart';

final class SelectContactState extends Equatable {
  const SelectContactState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.selectedUsers = const {},
    this.isGroupMode = false,
    this.isSearching = true,
    this.navigateToConversationId,
    this.isCreatingConversation = false,
  });

  final String query;
  final List<UserSearchResult> results;
  final bool isLoading;
  final String? error;
  final Set<UserSearchResult> selectedUsers;
  final bool isGroupMode;
  final bool isSearching;
  final String? navigateToConversationId;
  final bool isCreatingConversation;

  SelectContactState copyWith({
    String? query,
    List<UserSearchResult>? results,
    bool? isLoading,
    String? error,
    bool clearError = false,
    Set<UserSearchResult>? selectedUsers,
    bool? isGroupMode,
    bool? isSearching,
    String? navigateToConversationId,
    bool clearNavigation = false,
    bool? isCreatingConversation,
  }) {
    return SelectContactState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selectedUsers: selectedUsers ?? this.selectedUsers,
      isGroupMode: isGroupMode ?? this.isGroupMode,
      isSearching: isSearching ?? this.isSearching,
      navigateToConversationId: clearNavigation
          ? null
          : (navigateToConversationId ?? this.navigateToConversationId),
      isCreatingConversation:
          isCreatingConversation ?? this.isCreatingConversation,
    );
  }

  @override
  List<Object?> get props => [
        query,
        results,
        isLoading,
        error,
        selectedUsers,
        isGroupMode,
        isSearching,
        navigateToConversationId,
        isCreatingConversation,
      ];
}
