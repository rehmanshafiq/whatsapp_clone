import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/chat_channel.dart';
import '../../data/models/message.dart';
import '../../data/models/message_status.dart';
import '../../data/models/user.dart';
import '../../data/models/user_search.dart';
import '../../data/repository/chat_repository.dart';
import 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatRepository _repository;
  final Map<String, List<Timer>> _statusTimers = {};
  final Map<String, Timer> _liveLocationTimers = {};
  StreamSubscription<dynamic>? _socketSubscription;

  ChatCubit(this._repository) : super(const ChatState()) {
    _socketSubscription = _repository.socketMessages.listen(
      _handleSocketMessage,
      onError: (Object e, StackTrace st) {
        debugPrint('[ChatCubit] Socket stream error: $e');
      },
      cancelOnError: false,
    );
    debugPrint('[ChatCubit] Subscribed to socket stream');
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

  /// Fetches conversations from the server and updates the list without
  /// showing loading. Use for polling when the backend does not push over WebSocket.
  Future<void> refreshChatList() async {
    if (isClosed) return;
    try {
      final chats = await _repository.getChats();
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      if (!isClosed) emit(state.copyWith(channels: chats));
    } catch (_) {
      // Silent fail for background refresh
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
      final raw = await _repository.getMessages(channelId);
      final messages = _repository.normalizeMessageSenderIds(raw);
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (channel != null) {
        _repository.clearUnread(channelId);
        // Send message_read for every unread received message (double blue tick).
        // peer_user_id = sender of the message (avoids DB lookup on backend).
        for (final m in messages) {
          if (!m.isOutgoing && m.status != MessageStatus.seen) {
            final peerUserId = m.senderId; // sender of the message
            if (peerUserId.isNotEmpty && peerUserId != AppConstants.currentUserId) {
              final bucket = _bucketFromTimestamp(m.timestamp);
              _repository.sendMessageRead(
                messageId: m.id,
                conversationId: channelId,
                bucket: bucket,
                peerUserId: peerUserId,
              );
              _repository.updateMessageStatus(m.id, MessageStatus.seen);
            }
          }
        }
        final updatedChats = await _repository.getChats();
        updatedChats.sort(
          (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
        );
        final messagesWithSeen = messages.map((m) {
          if (!m.isOutgoing && m.status != MessageStatus.seen) {
            return m.copyWith(status: MessageStatus.seen);
          }
          return m;
        }).toList();
        emit(
          state.copyWith(
            messages: messagesWithSeen,
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

  /// Polls the server for new messages in [channelId] and updates state.
  /// Use when WebSocket does not push (e.g. backend only echoes to sender).
  Future<void> refreshMessages(String channelId) async {
    if (isClosed) return;
    try {
      final raw = await _repository.refreshMessagesFromServer(channelId);
      final messages = _repository.normalizeMessageSenderIds(raw);
      if (!isClosed && state.selectedChannel?.id == channelId) {
        final updatedChats = await _repository.getChats();
        updatedChats.sort(
          (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
        );
        emit(state.copyWith(messages: messages, channels: updatedChats));
      }
    } catch (_) {
      // Silent fail for background refresh
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
      _refreshChannelList();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isSending: false));
    }
  }

  void _handleSocketMessage(dynamic event) {
    debugPrint('[ChatCubit] _handleSocketMessage called (isClosed=$isClosed)');
    if (isClosed) return;

    Map<String, dynamic>? raw;
    if (event is Map<String, dynamic>) {
      raw = event;
    } else if (event is String) {
      try {
        final decoded = jsonDecode(event);
        if (decoded is Map<String, dynamic>) {
          raw = decoded;
        }
      } catch (e) {
        debugPrint('[ChatCubit] Failed to decode socket event: $e');
        return;
      }
    } else {
      debugPrint('[ChatCubit] Ignoring non-Map event: ${event.runtimeType}');
      return;
    }

    if (raw == null) return;

    // Backend uses event-based format: {"event":"ping|pong|send_message|...","data":{...}}
    final eventType = _stringFrom(raw['event']);
    if (eventType == 'ping' || eventType == 'pong') return;
    if (eventType == 'typing_start' || eventType == 'typing_stop') {
      _handleTypingEvent(eventType!, raw);
      return;
    }
    if (eventType == 'presence_update') {
      _handlePresenceUpdate(raw);
      return;
    }
    if (eventType == 'message_sent_ack') {
      _handleMessageSentAck(raw);
      return;
    }

    // Only process message events (send_message, new_message, or legacy payload without event)
    final isMessageEvent = eventType == null ||
        eventType == 'send_message' ||
        eventType == 'new_message' ||
        eventType == 'message';
    if (!isMessageEvent) return;

    Map<String, dynamic> data = raw;
    if (raw['data'] is Map<String, dynamic>) {
      data = raw['data'] as Map<String, dynamic>;
    } else if (raw['payload'] is Map<String, dynamic>) {
      data = raw['payload'] as Map<String, dynamic>;
    }

    final conversationId = _stringFrom(data['conversation_id']) ??
        _stringFrom(data['chat_id']) ??
        _stringFrom(data['channel_id']);
    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('[ChatCubit] No conversation_id in payload. Keys: ${data.keys.toList()}');
      return;
    }

    debugPrint('[ChatCubit] Socket message for conversation: $conversationId');

    // Backend sends message text in "body" for send_message
    final text = _stringFrom(data['body']) ??
        _stringFrom(data['message']) ??
        _stringFrom(data['text']) ??
        _stringFrom(data['last_message_text']) ??
        '';
    final timestampRaw = data['timestamp'] ??
        data['created_at'] ??
        data['sent_at'] ??
        data['last_message_at'] ??
        raw['timestamp'];
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

    // peer_user_id = recipient. When it equals currentUserId, we're the recipient (incoming).
    final peerUserId = _stringFrom(data['peer_user_id']);
    final senderId = _stringFrom(data['sender_id']) ?? _stringFrom(data['from_user_id']);
    final isOutgoing = peerUserId != null && peerUserId != AppConstants.currentUserId;
    final isOpen = state.selectedChannel?.id == conversationId;

    final channels = List<ChatChannel>.of(state.channels);
    final idx = channels.indexWhere((c) => c.id == conversationId);
    if (idx == -1) {
      debugPrint('[ChatCubit] Conversation $conversationId not in local list, reloading...');
      loadChats();
      return;
    }

    final current = channels[idx];

    int unread = current.unreadCount;
    if (!isOpen && !isOutgoing) {
      unread = unread + 1;
      _repository.incrementUnread(conversationId);
    }

    final displayText = text.isNotEmpty ? text : current.lastMessage;
    final updated = current.copyWith(
      lastMessage: displayText,
      lastMessageTime: timestamp,
      unreadCount: isOpen ? 0 : unread,
    );

    channels[idx] = updated;
    channels.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

    // Persist the channel update so _refreshChannelList stays in sync.
    if (text.isNotEmpty) {
      _repository.updateChannelLastMessage(conversationId, displayText);
    }

    // If the conversation is currently open, append the message to the
    // messages list so the chat detail screen updates in real time (like WhatsApp).
    // Include incoming messages even when text is empty (e.g. media) using a fallback.
    List<Message>? updatedMessages;
    if (isOpen) {
      final rawSenderId = senderId ?? conversationId;
      final myBackendId = _repository.getCurrentUserId();
      // Show "message deleted" on the right (outgoing) when backend omits sender_id
      // or when sender is current user, so mobile and web match.
      final bool isDeletedMessage = text == 'message deleted';
      final bool senderMissing = senderId == null || senderId.isEmpty;
      String normalizedSenderId;
      if (myBackendId != null && myBackendId.isNotEmpty) {
        if (rawSenderId == myBackendId) {
          normalizedSenderId = AppConstants.currentUserId;
        } else if (isDeletedMessage && senderMissing) {
          normalizedSenderId = AppConstants.currentUserId;
        } else {
          normalizedSenderId = rawSenderId;
        }
      } else {
        normalizedSenderId = rawSenderId;
      }

      final displayText = text.isNotEmpty
          ? text
          : (_stringFrom(data['type']) == 'image'
              ? '\u{1F4F7} Photo'
              : _stringFrom(data['type']) == 'audio'
                  ? '\u{1F3A4} Voice message'
                  : _stringFrom(data['type']) == 'video'
                      ? '\u{1F3A5} Video'
                      : '\u{1F4DD} Message');

      final message = Message(
        id: _stringFrom(data['client_msg_id']) ??
            _stringFrom(data['message_id']) ??
            _stringFrom(data['id']) ??
            'msg_socket_${DateTime.now().millisecondsSinceEpoch}',
        channelId: conversationId,
        senderId: normalizedSenderId,
        text: displayText,
        timestamp: timestamp,
        status: MessageStatus.sent,
      );

      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        _repository.addOrUpdateMessage(message);
        updatedMessages = List<Message>.from(state.messages)..add(message);
        // Send message_delivered when we receive new_message (double grey tick).
        if (!isOutgoing) {
          final serverMsgId = _stringFrom(data['message_id']) ??
              _stringFrom(data['id']) ??
              message.id;
          final bucket = _bucketFromTimestamp(timestamp);
          final senderIdForDelivered = senderId ?? message.senderId;
          if (senderIdForDelivered.isNotEmpty) {
            _repository.sendMessageDelivered(
              messageId: serverMsgId,
              conversationId: conversationId,
              bucket: bucket,
              peerUserId: senderIdForDelivered,
            );
          }
        }
      }
    }

    debugPrint('[ChatCubit] Emitting updated channels (count: ${channels.length})');
    emit(state.copyWith(
      channels: channels,
      messages: updatedMessages,
    ));
  }

  void _handleTypingEvent(String eventType, Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final conversationId = _stringFrom(data['conversation_id']);
    if (conversationId == null || state.selectedChannel?.id != conversationId) return;
    final isTyping = eventType == 'typing_start';
    emit(state.copyWith(isTyping: isTyping));
  }

  void _handleMessageSentAck(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final clientMsgId = _stringFrom(data['client_msg_id']);
    final serverMessageId = _stringFrom(data['message_id']) ?? _stringFrom(data['id']);
    if (clientMsgId == null || serverMessageId == null) return;
    final messages = state.messages;
    final idx = messages.indexWhere((m) => m.id == clientMsgId);
    if (idx == -1) return;
    _statusTimers[clientMsgId]?.forEach((t) => t.cancel());
    _statusTimers.remove(clientMsgId);
    _repository.replaceOptimisticMessageId(clientMsgId, serverMessageId);
    final updatedMessages = messages.map((m) {
      if (m.id == clientMsgId) return m.copyWith(id: serverMessageId, status: MessageStatus.sent);
      return m;
    }).toList();
    emit(state.copyWith(messages: updatedMessages));
  }

  void _handlePresenceUpdate(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final userId = _stringFrom(data['user_id']) ?? _stringFrom(data['peer_user_id']);
    if (userId == null) return;
    final status = _stringFrom(data['status']);
    final lastSeenMs = data['last_seen'];
    DateTime? lastSeen;
    if (lastSeenMs is int) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs, isUtc: true);
    } else if (lastSeenMs is String) {
      lastSeen = DateTime.tryParse(lastSeenMs);
    }
    final isOnline = status == 'online';
    final channels = List<ChatChannel>.from(state.channels);
    var updated = false;
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      if (c.peerUserId == userId) {
        channels[i] = c.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen ?? c.lastSeen,
        );
        updated = true;
        break;
      }
      if (c.id == 'channel_$userId') {
        channels[i] = c.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen ?? c.lastSeen,
          peerUserId: c.peerUserId ?? userId,
        );
        updated = true;
        break;
      }
    }
    if (updated) {
      final isSelectedPeer = state.selectedChannel?.peerUserId == userId ||
          state.selectedChannel?.id == 'channel_$userId';
      emit(state.copyWith(
        channels: channels,
        isOnline: isSelectedPeer ? isOnline : state.isOnline,
      ));
    }
  }

  static String _bucketFromTimestamp(DateTime timestamp) {
    final y = timestamp.year;
    final m = timestamp.month;
    final d = timestamp.day;
    return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
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

  /// Deletes one of the current user's sent messages (soft delete).
  Future<void> deleteMessage(Message message) async {
    if (!message.isOutgoing) return;
    final peerUserId = _resolvePeerUserIdForChannel(message.channelId);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      final bucket = _bucketFromTimestamp(message.timestamp);
      _repository.sendDeleteMessage(
        messageId: message.id,
        conversationId: message.channelId,
        bucket: bucket,
        peerUserId: peerUserId,
      );
    }

    final deleted = message.copyWith(
      text: 'message deleted',
      isEdited: false,
    );
    _repository.addOrUpdateMessage(deleted);
    _replaceMessageInState(deleted);
  }

  String? _resolvePeerUserIdForChannel(String channelId) {
    final channel = _repository.getChannel(channelId);
    if (channel?.peerUserId != null && channel!.peerUserId!.isNotEmpty) {
      return channel.peerUserId;
    }
    if (channelId.startsWith('channel_')) {
      return channelId.replaceFirst('channel_', '');
    }
    return null;
  }

  /// Sends typing_start (re-send on each keystroke to reset server 4s TTL).
  void sendTypingStart(String channelId) {
    final peerUserId = _repository.getChannel(channelId)?.peerUserId ??
        (channelId.startsWith('channel_')
            ? channelId.replaceFirst('channel_', '')
            : null);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendTypingStart(
        conversationId: channelId,
        peerUserId: peerUserId,
      );
    }
  }

  /// Sends typing_stop when input cleared, message sent, or screen left.
  void sendTypingStop(String channelId) {
    final peerUserId = _repository.getChannel(channelId)?.peerUserId ??
        (channelId.startsWith('channel_')
            ? channelId.replaceFirst('channel_', '')
            : null);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendTypingStop(
        conversationId: channelId,
        peerUserId: peerUserId,
      );
    }
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

  static String? _stringFrom(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    return v.toString();
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}
