import 'package:equatable/equatable.dart';

import '../../data/models/chat_channel.dart';
import '../../data/models/message.dart';
import '../../data/models/user_search.dart';

class ChatState extends Equatable {
  final List<ChatChannel> channels;
  final List<Message> messages;
  final ChatChannel? selectedChannel;
  final bool isTyping;
  final bool isOnline;
  final bool isSending;
  final bool isLoading;
  final bool isPaginationLoading;
  final bool hasMoreMessages;
  final String? error;
  final String searchQuery;
  final List<UserSearchResult> userSearchResults;
  final bool isUserSearchLoading;
  final String? userSearchError;

  /// Profile of the currently authenticated user (used for AppBar avatar).
  final UserSearchResult? currentUserProfile;

  /// View-once opened: messageId -> local file path (image fetched with auth).
  final Map<String, String> viewOnceLocalPaths;

  const ChatState({
    this.channels = const [],
    this.messages = const [],
    this.selectedChannel,
    this.isTyping = false,
    this.isOnline = false,
    this.isSending = false,
    this.isLoading = false,
    this.isPaginationLoading = false,
    this.hasMoreMessages = true,
    this.error,
    this.searchQuery = '',
    this.userSearchResults = const [],
    this.isUserSearchLoading = false,
    this.userSearchError,
    this.currentUserProfile,
    this.viewOnceLocalPaths = const {},
  });

  ChatState copyWith({
    List<ChatChannel>? channels,
    List<Message>? messages,
    ChatChannel? selectedChannel,
    bool? isTyping,
    bool? isOnline,
    bool? isSending,
    bool? isLoading,
    bool? isPaginationLoading,
    bool? hasMoreMessages,
    String? error,
    String? searchQuery,
    bool clearSelectedChannel = false,
    bool clearError = false,
    List<UserSearchResult>? userSearchResults,
    bool? isUserSearchLoading,
    String? userSearchError,
    bool clearUserSearchError = false,
    UserSearchResult? currentUserProfile,
    Map<String, String>? viewOnceLocalPaths,
  }) {
    return ChatState(
      channels: channels ?? this.channels,
      messages: messages ?? this.messages,
      selectedChannel: clearSelectedChannel
          ? null
          : (selectedChannel ?? this.selectedChannel),
      isTyping: isTyping ?? this.isTyping,
      isOnline: isOnline ?? this.isOnline,
      isSending: isSending ?? this.isSending,
      isLoading: isLoading ?? this.isLoading,
      isPaginationLoading: isPaginationLoading ?? this.isPaginationLoading,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      userSearchResults: userSearchResults ?? this.userSearchResults,
      isUserSearchLoading: isUserSearchLoading ?? this.isUserSearchLoading,
      userSearchError: clearUserSearchError
          ? null
          : (userSearchError ?? this.userSearchError),
      currentUserProfile: currentUserProfile ?? this.currentUserProfile,
      viewOnceLocalPaths: viewOnceLocalPaths ?? this.viewOnceLocalPaths,
    );
  }

  List<ChatChannel> get filteredChannels {
    if (searchQuery.isEmpty) return channels;
    final query = searchQuery.toLowerCase();
    return channels
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              c.lastMessage.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  List<Object?> get props => [
    channels,
    messages,
    selectedChannel,
    isTyping,
    isOnline,
    isSending,
    isLoading,
    isPaginationLoading,
    hasMoreMessages,
    error,
    searchQuery,
    userSearchResults,
    isUserSearchLoading,
    userSearchError,
    currentUserProfile,
    viewOnceLocalPaths,
  ];
}
