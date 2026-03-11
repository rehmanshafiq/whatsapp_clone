import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/message.dart';
import '../../data/models/message_status.dart';
import '../../data/models/user.dart';
import '../../data/models/user_search.dart';
import '../../data/repository/chat_repository.dart';
import 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatRepository _repository;
  final _random = Random();
  final Map<String, Timer> _replyTimers = {};
  final Map<String, List<Timer>> _statusTimers = {};
  final Map<String, Timer> _liveLocationTimers = {};
  StreamSubscription<dynamic>? _socketSubscription;

  ChatCubit(this._repository) : super(const ChatState()) {
    _socketSubscription = _repository.socketMessages.listen(
      _handleSocketMessage,
    );
  }
  ChatRepository get repository => _repository;

  Future<void> loadChats() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final chats = await _repository.getChats();
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      emit(state.copyWith(channels: chats, isLoading: false));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  Future<void> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      emit(
        state.copyWith(
          userSearchResults: const <UserSearchResult>[],
          isUserSearchLoading: false,
          clearUserSearchError: true,
        ),
      );
      return;
    }

    emit(state.copyWith(isUserSearchLoading: true, clearUserSearchError: true));
    try {
      final results = await _repository.searchUsers(trimmed);
      emit(
        state.copyWith(userSearchResults: results, isUserSearchLoading: false),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(isUserSearchLoading: false, userSearchError: e.message),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isUserSearchLoading: false,
          userSearchError: e.toString(),
        ),
      );
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
        updatedChats.sort(
          (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
        );
        emit(
          state.copyWith(
            messages: messages,
            selectedChannel: channel.copyWith(unreadCount: 0),
            isOnline: channel.isOnline,
            isLoading: false,
            channels: updatedChats,
          ),
        );
      } else {
        emit(state.copyWith(messages: messages, isLoading: false));
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

  void _handleSocketMessage(dynamic event) {
    if (isClosed) return;

    Map<String, dynamic>? data;
    if (event is Map<String, dynamic>) {
      data = event;
    } else if (event is String) {
      try {
        final decoded = jsonDecode(event);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (e) {
        debugPrint('Failed to decode socket event: $e');
        return;
      }
    } else {
      return;
    }

    // Some backends wrap payload under "data" key.
    if (data?['data'] is Map<String, dynamic>) {
      data = data?['data'] as Map<String, dynamic>;
    }

    final conversationId =
        (data?['conversation_id'] ?? data?['chat_id'] ?? data?['channel_id'])
            as String?;
    if (conversationId == null || conversationId.isEmpty) return;

    final text =
        (data?['message'] ?? data?['text'] ?? data?['last_message_text'])
            as String? ??
        '';
    final timestampRaw =
        data?['timestamp'] ??
        data?['created_at'] ??
        data?['sent_at'] ??
        data?['last_message_at'];
    DateTime timestamp;
    if (timestampRaw is String) {
      timestamp = DateTime.tryParse(timestampRaw)?.toLocal() ?? DateTime.now();
    } else if (timestampRaw is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        timestampRaw,
        isUtc: true,
      ).toLocal();
    } else {
      timestamp = DateTime.now();
    }

    final channels = List.of(state.channels);
    final idx = channels.indexWhere((c) => c.id == conversationId);
    if (idx == -1) {
      return;
    }

    final current = channels[idx];
    final isOpen = state.selectedChannel?.id == conversationId;
    final updated = current.copyWith(
      lastMessage: text.isNotEmpty ? text : current.lastMessage,
      lastMessageTime: timestamp,
      unreadCount: isOpen ? current.unreadCount : current.unreadCount + 1,
    );

    channels[idx] = updated;
    channels.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    emit(state.copyWith(channels: channels));
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

  Future<void> sendMediaMessage(
    String channelId,
    String mediaUrl,
    bool isSticker,
  ) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendMediaMessage(
        channelId,
        mediaUrl,
        isSticker,
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

  Future<void> sendImageMessage(
    String channelId,
    String imagePath, {
    String text = '',
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendImageMessage(
        channelId,
        imagePath,
        text: text,
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

  Future<void> sendVideoMessage(
    String channelId,
    String videoPath, {
    String text = '',
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendVideoMessage(
        channelId,
        videoPath,
        text: text,
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

  Future<void> sendLocationMessage(
    String channelId, {
    required double latitude,
    required double longitude,
    required String locationName,
    required String locationAddress,
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendLocationMessage(
        channelId,
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        locationAddress: locationAddress,
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

  Future<void> startLiveLocationSharing(
    String channelId, {
    required double latitude,
    required double longitude,
    required String locationName,
    required String locationAddress,
    required Duration duration,
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final liveLocationEndsAt = DateTime.now().add(duration);
      final message = await _repository.sendLocationMessage(
        channelId,
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        locationAddress: locationAddress,
        isLiveLocation: true,
        isLiveLocationActive: true,
        liveLocationEndsAt: liveLocationEndsAt,
      );
      final updatedMessages = List<Message>.from(state.messages)..add(message);
      emit(state.copyWith(messages: updatedMessages, isSending: false));

      _simulateMessageLifecycle(message);
      _scheduleAutoReply(channelId);
      _refreshChannelList();
      _scheduleLiveLocationUpdates(message, duration);
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isSending: false));
    }
  }

  Future<void> sendContactMessage(
    String channelId, {
    required String name,
    required String phone,
    String? contactId,
    Uint8List? photo,
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendContactMessage(
        channelId,
        name: name,
        phone: phone,
        contactId: contactId,
        photo: photo,
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

  Future<void> sendDocumentMessage(
    String channelId, {
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendDocumentMessage(
        channelId,
        filePath: filePath,
        fileName: fileName,
        fileSize: fileSize,
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

    timers.add(
      Timer(AppConstants.sendDelay, () {
        _updateLocalMessageStatus(message.id, MessageStatus.sent);
      }),
    );

    timers.add(
      Timer(AppConstants.deliverDelay, () {
        _updateLocalMessageStatus(message.id, MessageStatus.delivered);
      }),
    );

    timers.add(
      Timer(AppConstants.seenDelay, () {
        _updateLocalMessageStatus(message.id, MessageStatus.seen);
      }),
    );

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

    final delay =
        AppConstants.minReplyDelay +
        Duration(
          milliseconds: _random.nextInt(
            AppConstants.maxReplyDelay.inMilliseconds -
                AppConstants.minReplyDelay.inMilliseconds,
          ),
        );

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
      emit(state.copyWith(messages: updatedMessages, isTyping: false));
      _refreshChannelList();

      Timer(const Duration(seconds: 2), () {
        if (!isClosed) {
          emit(state.copyWith(isOnline: false));
        }
      });
    });
  }

  void _scheduleLiveLocationUpdates(Message message, Duration duration) {
    _liveLocationTimers[message.id]?.cancel();
    final liveLocationEndsAt =
        message.liveLocationEndsAt ?? DateTime.now().add(duration);

    _liveLocationTimers[message.id] = Timer.periodic(
      const Duration(seconds: 15),
      (timer) async {
        if (DateTime.now().isAfter(liveLocationEndsAt)) {
          timer.cancel();
          _liveLocationTimers.remove(message.id);
          _setLiveLocationActive(message.id, false);
          return;
        }

        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
            ),
          );
          final resolvedAddress = await _resolveAddress(
            position.latitude,
            position.longitude,
          );
          final resolvedName = await _resolveLocationName(
            position.latitude,
            position.longitude,
          );

          _repository.updateLocationMessage(
            message.id,
            latitude: position.latitude,
            longitude: position.longitude,
            locationName: resolvedName,
            locationAddress: resolvedAddress,
            liveLocationUpdatedAt: DateTime.now(),
            isLiveLocationActive: true,
          );

          final currentMessage = _messageById(message.id);
          if (currentMessage == null || isClosed) return;

          final updatedMessage = currentMessage.copyWith(
            latitude: position.latitude,
            longitude: position.longitude,
            locationName: resolvedName,
            locationAddress: resolvedAddress,
            text: resolvedAddress,
            liveLocationUpdatedAt: DateTime.now(),
            isLiveLocationActive: true,
          );
          _replaceMessageInState(updatedMessage);
        } catch (_) {
          // Keep the live-location timer running even if one GPS lookup fails.
        }
      },
    );
  }

  void _setLiveLocationActive(String messageId, bool isActive) {
    final currentMessage = _messageById(messageId);
    if (currentMessage == null) return;

    _repository.updateLocationMessage(
      messageId,
      latitude: currentMessage.latitude ?? 0,
      longitude: currentMessage.longitude ?? 0,
      locationName: currentMessage.locationName ?? 'Live location',
      locationAddress: currentMessage.locationAddress ?? currentMessage.text,
      liveLocationUpdatedAt: DateTime.now(),
      isLiveLocationActive: isActive,
    );

    _replaceMessageInState(
      currentMessage.copyWith(
        liveLocationUpdatedAt: DateTime.now(),
        isLiveLocationActive: isActive,
      ),
    );
  }

  Message? _messageById(String messageId) {
    for (final message in state.messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  void _replaceMessageInState(Message updatedMessage) {
    final index = state.messages.indexWhere((m) => m.id == updatedMessage.id);
    if (index == -1 || isClosed) return;

    final updatedMessages = List<Message>.from(state.messages);
    updatedMessages[index] = updatedMessage;
    emit(state.copyWith(messages: updatedMessages));
  }

  Future<String> _resolveAddress(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        return _formatCoordinates(latitude, longitude);
      }
      final placemark = placemarks.first;
      final parts =
          [
                placemark.street,
                placemark.subLocality,
                placemark.locality,
                placemark.administrativeArea,
              ]
              .whereType<String>()
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toSet()
              .toList();

      return parts.isEmpty
          ? _formatCoordinates(latitude, longitude)
          : parts.join(', ');
    } catch (_) {
      return _formatCoordinates(latitude, longitude);
    }
  }

  Future<String> _resolveLocationName(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return 'Live location';

      final placemark = placemarks.first;
      final candidates = [
        placemark.name,
        placemark.street,
        placemark.subLocality,
        placemark.locality,
      ];
      for (final candidate in candidates) {
        if (candidate != null && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    } catch (_) {}

    return 'Live location';
  }

  String _formatCoordinates(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  void _refreshChannelList() {
    try {
      final chats = _repository
          .getChannel(state.selectedChannel?.id ?? '')
          ?.let((ch) {
            final allChats = state.channels.map((c) {
              if (c.id == ch.id) return _repository.getChannel(c.id) ?? c;
              return c;
            }).toList();
            allChats.sort(
              (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
            );
            return allChats;
          });
      if (chats != null && !isClosed) {
        emit(state.copyWith(channels: chats));
      }
    } catch (_) {}
  }

  void reactToMessage(String messageId, String emoji) {
    final updatedMessages = state.messages.map((m) {
      if (m.id != messageId) return m;
      final reactions = Map<String, List<String>>.from(
        m.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
      );
      final users = reactions[emoji] ?? [];
      if (users.contains(AppConstants.currentUserId)) {
        users.remove(AppConstants.currentUserId);
        if (users.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = users;
        }
      } else {
        reactions[emoji] = [...users, AppConstants.currentUserId];
      }
      return m.copyWith(reactions: reactions);
    }).toList();
    emit(state.copyWith(messages: updatedMessages));

    final msg = updatedMessages.firstWhere((m) => m.id == messageId);
    _repository.updateMessageReactions(messageId, msg.reactions);
  }

  void updateSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  void deleteChat(String channelId) {
    _repository.deleteChat(channelId);
    final updated = List.of(state.channels)
      ..removeWhere((c) => c.id == channelId);
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
    emit(
      state.copyWith(
        clearSelectedChannel: true,
        isTyping: false,
        isOnline: false,
      ),
    );
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
    for (final timer in _liveLocationTimers.values) {
      timer.cancel();
    }
    _socketSubscription?.cancel();
    return super.close();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
