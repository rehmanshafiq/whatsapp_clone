import 'package:equatable/equatable.dart';

import '../../data/models/chat_channel.dart';
import '../../data/models/message.dart';

class ChatState extends Equatable {
  final List<ChatChannel> channels;
  final List<Message> messages;
  final ChatChannel? selectedChannel;
  final bool isTyping;
  final bool isOnline;
  final bool isSending;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  const ChatState({
    this.channels = const [],
    this.messages = const [],
    this.selectedChannel,
    this.isTyping = false,
    this.isOnline = false,
    this.isSending = false,
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  ChatState copyWith({
    List<ChatChannel>? channels,
    List<Message>? messages,
    ChatChannel? selectedChannel,
    bool? isTyping,
    bool? isOnline,
    bool? isSending,
    bool? isLoading,
    String? error,
    String? searchQuery,
    bool clearSelectedChannel = false,
    bool clearError = false,
  }) {
    return ChatState(
      channels: channels ?? this.channels,
      messages: messages ?? this.messages,
      selectedChannel: clearSelectedChannel ? null : (selectedChannel ?? this.selectedChannel),
      isTyping: isTyping ?? this.isTyping,
      isOnline: isOnline ?? this.isOnline,
      isSending: isSending ?? this.isSending,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<ChatChannel> get filteredChannels {
    if (searchQuery.isEmpty) return channels;
    final query = searchQuery.toLowerCase();
    return channels
        .where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.lastMessage.toLowerCase().contains(query))
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
        error,
        searchQuery,
      ];
}
