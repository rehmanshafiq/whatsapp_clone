import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/message.dart';
import '../../data/models/message_status.dart';
import '../../data/models/user.dart';
import '../../data/repository/chat_repository.dart';
import 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatRepository _repository;
  final _random = Random();
  final Map<String, Timer> _replyTimers = {};
  final Map<String, List<Timer>> _statusTimers = {};

  ChatCubit(this._repository) : super(const ChatState());

  Future<void> loadChats() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final chats = await _repository.getChats();
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      emit(state.copyWith(channels: chats, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  Future<void> loadMessages(String channelId) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final channel = _repository.getChannel(channelId);
      final messages = await _repository.getMessages(channelId);
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (channel != null) {
        _repository.clearUnread(channelId);
        final updatedChats = await _repository.getChats();
        updatedChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        emit(state.copyWith(
          messages: messages,
          selectedChannel: channel.copyWith(unreadCount: 0),
          isOnline: channel.isOnline,
          isLoading: false,
          channels: updatedChats,
        ));
      } else {
        emit(state.copyWith(
          messages: messages,
          isLoading: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  Future<void> sendMessage(String channelId, String text) async {
    if (text.trim().isEmpty) return;

    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendMessage(channelId, text.trim());
      final updatedMessages = List<Message>.from(state.messages)..add(message);
      emit(state.copyWith(messages: updatedMessages, isSending: false));

      _simulateMessageLifecycle(message);
      _scheduleAutoReply(channelId);
      _refreshChannelList();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isSending: false));
    }
  }

  Future<void> sendAudioMessage(
    String channelId,
    String audioPath,
    Duration audioDuration,
  ) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendAudioMessage(
        channelId,
        audioPath,
        audioDuration,
      );
      final updatedMessages = List<Message>.from(state.messages)..add(message);
      emit(state.copyWith(messages: updatedMessages, isSending: false));

      _simulateMessageLifecycle(message);
      _scheduleAutoReply(channelId);
      _refreshChannelList();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isSending: false));
    }
  }

  void _simulateMessageLifecycle(Message message) {
    final timers = <Timer>[];

    timers.add(Timer(AppConstants.sendDelay, () {
      _updateLocalMessageStatus(message.id, MessageStatus.sent);
    }));

    timers.add(Timer(AppConstants.deliverDelay, () {
      _updateLocalMessageStatus(message.id, MessageStatus.delivered);
    }));

    timers.add(Timer(AppConstants.seenDelay, () {
      _updateLocalMessageStatus(message.id, MessageStatus.seen);
    }));

    _statusTimers[message.id] = timers;
  }

  void _updateLocalMessageStatus(String messageId, MessageStatus status) {
    _repository.updateMessageStatus(messageId, status);
    final updatedMessages = state.messages.map((m) {
      if (m.id == messageId) return m.copyWith(status: status);
      return m;
    }).toList();
    if (!isClosed) {
      emit(state.copyWith(messages: updatedMessages));
    }
  }

  void _scheduleAutoReply(String channelId) {
    _replyTimers[channelId]?.cancel();

    final delay = AppConstants.minReplyDelay +
        Duration(milliseconds: _random.nextInt(
            AppConstants.maxReplyDelay.inMilliseconds -
                AppConstants.minReplyDelay.inMilliseconds));

    if (!isClosed) {
      emit(state.copyWith(isOnline: true));
    }

    final typingDelay = Duration(milliseconds: delay.inMilliseconds - 1500);
    Timer(typingDelay > Duration.zero ? typingDelay : Duration.zero, () {
      if (!isClosed) {
        emit(state.copyWith(isTyping: true));
      }
    });

    _replyTimers[channelId] = Timer(delay, () {
      if (isClosed) return;
      final reply = _repository.generateAutoReply(channelId);
      final updatedMessages = List<Message>.from(state.messages)..add(reply);
      emit(state.copyWith(
        messages: updatedMessages,
        isTyping: false,
      ));
      _refreshChannelList();

      Timer(const Duration(seconds: 2), () {
        if (!isClosed) {
          emit(state.copyWith(isOnline: false));
        }
      });
    });
  }

  void _refreshChannelList() {
    try {
      final chats = _repository.getChannel(state.selectedChannel?.id ?? '')
          ?.let((ch) {
        final allChats = state.channels.map((c) {
          if (c.id == ch.id) return _repository.getChannel(c.id) ?? c;
          return c;
        }).toList();
        allChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        return allChats;
      });
      if (chats != null && !isClosed) {
        emit(state.copyWith(channels: chats));
      }
    } catch (_) {}
  }

  void updateSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  void deleteChat(String channelId) {
    _repository.deleteChat(channelId);
    final updated = List.of(state.channels)..removeWhere((c) => c.id == channelId);
    emit(state.copyWith(channels: updated));
  }

  Future<String> openOrCreateChat(User contact) async {
    final channel = _repository.createChat(contact);
    final updatedChats = await _repository.getChats();
    updatedChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    emit(state.copyWith(channels: updatedChats));
    return channel.id;
  }

  void clearSelectedChannel() {
    emit(state.copyWith(clearSelectedChannel: true, isTyping: false, isOnline: false));
  }

  @override
  Future<void> close() {
    for (final timer in _replyTimers.values) {
      timer.cancel();
    }
    for (final timers in _statusTimers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    return super.close();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
