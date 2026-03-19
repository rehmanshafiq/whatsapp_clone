import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
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

  /// Auth headers for loading media from our API (Bearer + x-api-key).
  Map<String, String>? get authHeadersForMedia => _repository.getAuthHeadersForMedia();

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

  Future<void> loadCurrentUserProfile() async {
    try {
      final profile = await _repository.fetchCurrentUserProfile();
      if (!isClosed) {
        emit(state.copyWith(currentUserProfile: profile));
      }
    } on ApiException {
      // Silent failure – avatar fallback will be used.
    } catch (_) {
      // Ignore generic errors for profile load to avoid blocking chat list.
    }
  }

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

  Future<UserSearchResult?> updateCurrentUserProfile({
    required String displayName,
    required String statusText,
    required String avatarUrl,
  }) async {
    try {
      final updated = await _repository.updateCurrentUserProfile(
        current: state.currentUserProfile,
        displayName: displayName,
        avatarUrl: avatarUrl,
        statusText: statusText,
      );
      if (!isClosed) {
        emit(state.copyWith(currentUserProfile: updated));
      }
      return updated;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
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
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        isTyping: false,
        isRecordingAudio: false,
      ),
    );
    try {
      final channel = _repository.getChannel(channelId);
      final page = await _repository.getMessages(channelId);
      final messages = page.messages; // Already normalized by repository
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
        // Fetch presence (online, last_seen) from API for initial load.
        final channelWithPresence =
            await _repository.fetchPresenceForChannel(channelId);
        final effectiveChannel = (channelWithPresence ?? channel).copyWith(
          unreadCount: 0,
        );
        final updatedChats = await _repository.getChats();
        updatedChats.sort(
          (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
        );
        // Preserve presence (API getChats may not include lastSeen).
        if (channelWithPresence != null) {
          final idx = updatedChats.indexWhere((c) => c.id == channelId);
          if (idx >= 0) {
            final merged = updatedChats[idx].copyWith(
              isOnline: channelWithPresence.isOnline,
              lastSeen: channelWithPresence.lastSeen,
            );
            updatedChats[idx] = merged;
            _repository.upsertChannel(merged);
          }
        }
        final messagesWithSeen = messages.map((m) {
          if (!m.isOutgoing && m.status != MessageStatus.seen) {
            return m.copyWith(status: MessageStatus.seen);
          }
          return m;
        }).toList();
        // Preserve isOnline from state.channels (updated by presence_update) or
        // state.isOnline, since repo may have stale data. Otherwise "online"
        // disappears when loadMessages completes after a presence event.
        final channelFromState =
            state.channels.where((c) => c.id == channelId).firstOrNull;
        final effectiveIsOnline = channelFromState?.isOnline ??
            (state.selectedChannel?.id == channelId ? state.isOnline : null) ??
            effectiveChannel.isOnline;
        emit(
          state.copyWith(
            messages: messagesWithSeen,
            selectedChannel: effectiveChannel,
            isOnline: effectiveIsOnline,
            isLoading: false,
            hasMoreMessages: page.hasMore,
            channels: updatedChats,
          ),
        );
      } else {
        emit(state.copyWith(
          messages: messages,
          isLoading: false,
          hasMoreMessages: page.hasMore,
        ));
      }
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  /// Loads older messages when user scrolls to top. Appends to the beginning
  /// of the list and preserves scroll position. Prevents duplicate calls.
  Future<void> loadOlderMessages(String channelId) async {
    if (state.isPaginationLoading || !state.hasMoreMessages) return;
    final messagesForChannel =
        state.messages.where((m) => m.channelId == channelId).toList();
    if (messagesForChannel.isEmpty) return;

    emit(state.copyWith(isPaginationLoading: true));
    try {
      messagesForChannel.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final oldestMessageId = messagesForChannel.first.id;

      final page = await _repository.loadOlderMessages(
        channelId,
        beforeMessageId: oldestMessageId,
      );

      if (page.messages.isEmpty) {
        if (!isClosed) {
          emit(state.copyWith(isPaginationLoading: false, hasMoreMessages: false));
        }
        return;
      }

      if (!isClosed && state.selectedChannel?.id == channelId) {
        final normalized = _repository.normalizeMessageSenderIds(page.messages);
        final merged = [...normalized, ...state.messages];
        final uniqueById = <String, Message>{};
        for (final m in merged) {
          uniqueById[m.id] = m;
        }
        final deduped = uniqueById.values.toList();
        deduped.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        emit(state.copyWith(
          messages: deduped,
          isPaginationLoading: false,
          hasMoreMessages: page.hasMore,
        ));
      } else {
        emit(state.copyWith(isPaginationLoading: false, hasMoreMessages: page.hasMore));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isPaginationLoading: false));
      }
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

  /// Clears all messages for [conversationId] via API, updates local state.
  Future<void> clearChat(String conversationId) async {
    try {
      await _repository.clearChatMessages(conversationId);
      if (isClosed) return;
      final channels = state.channels
          .map((c) => c.id == conversationId ? c.copyWith(lastMessage: '') : c)
          .toList();
      // If this conversation is currently open, clear messages too.
      final isOpen = state.selectedChannel?.id == conversationId;
      emit(state.copyWith(
        channels: channels,
        messages: isOpen ? const <Message>[] : null,
      ));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Deletes a conversation via API and removes it from local state.
  Future<void> deleteConversation(String conversationId) async {
    try {
      await _repository.deleteConversationRemote(conversationId);
      if (isClosed) return;
      final channels =
          state.channels.where((c) => c.id != conversationId).toList();
      emit(state.copyWith(channels: channels));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Toggles mute on a conversation via API and updates local state.
  Future<void> toggleMute(String conversationId) async {
    try {
      final isMuted = await _repository.toggleMuteConversation(conversationId);
      if (isClosed) return;
      final channels = state.channels
          .map(
              (c) => c.id == conversationId ? c.copyWith(isMuted: isMuted) : c)
          .toList();
      emit(state.copyWith(channels: channels));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _repository.blockUser(userId);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _repository.unblockUser(userId);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<List<UserSearchResult>> getBlockedUsers() async {
    try {
      return await _repository.getBlockedUsers();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> sendMessage(
    String channelId,
    String text, {
    String replyToMessageId = '',
    bool isForwarded = false,
  }) async {
    if (text.trim().isEmpty) return;

    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendMessage(
        channelId,
        text.trim(),
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
      );
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

    debugPrint('[ChatCubit] Raw socket payload: $raw');

    // Backend uses event-based format: {"event":"ping|pong|send_message|...","data":{...}}
    final eventType = _stringFrom(raw['event']);
    if (eventType == 'ping' || eventType == 'pong') return;
    if (eventType == 'typing_indicator' || eventType == 'typing_start' || eventType == 'typing_stop') {
      _handleTypingEvent(eventType!, raw);
      return;
    }
    if (eventType == 'recording_start' || eventType == 'recording_stop') {
      _handleRecordingEvent(eventType!, raw);
      return;
    }
    if (eventType == 'recording_indicator') {
      _handleRecordingIndicatorEvent(raw);
      return;
    }
    if (eventType == 'presence_update') {
      _handlePresenceUpdate(raw);
      return;
    }
    if (eventType == 'block_status') {
      _handleBlockStatus(raw);
      return;
    }
    if (eventType == 'message_sent_ack') {
      _handleMessageSentAck(raw);
      return;
    }
    if (eventType == 'message_status_update') {
      _handleMessageStatusUpdate(raw);
      return;
    }
    if (eventType == 'message_deleted') {
      _handleMessageDeleted(raw);
      return;
    }
    if (eventType == 'message_edited') {
      _handleMessageEdited(raw);
      return;
    }
    if (eventType == 'conversation_upserted') {
      _handleConversationUpserted(raw);
      return;
    }
    if (eventType == 'message_reaction') {
      _handleMessageReaction(raw);
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
    var idx = channels.indexWhere((c) => c.id == conversationId);

    // [New Message Processing: Step 2]
    // If the conversation doesn't exist (first-ever message), create a placeholder
    if (idx == -1 && eventType == 'new_message') {
      debugPrint('[ChatCubit] Creating placeholder channel for $conversationId');
      
      final senderDisplayName = _stringFrom(data['sender_display_name']) ?? 'Unknown';
      var senderAvatarUrl = _stringFrom(data['sender_avatar_url']) ?? '';
      
      // Some server payloads send relative avatar paths.
      if (senderAvatarUrl.isNotEmpty && !senderAvatarUrl.startsWith('http')) {
        senderAvatarUrl = '${AppConstants.apiBaseUrl}$senderAvatarUrl';
      }

      final newChannel = ChatChannel(
        id: conversationId,
        name: senderDisplayName,
        avatarUrl: senderAvatarUrl,
        lastMessage: text,
        lastMessageTime: timestamp,
        peerUserId: senderId,
        unreadCount: isOpen ? 0 : 1, // Start with 1 unread if closed
      );

      channels.insert(0, newChannel);
      idx = 0; // Point to newly inserted channel
      
      // Force save so next lookup finds it locally
      _repository.createChat(User(
        id: senderId ?? '', 
        name: senderDisplayName, 
        avatarUrl: senderAvatarUrl
      ));
    } else if (idx == -1) {
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

    // Socket may send type in "type" or "attachment_type" (e.g. web app sends attachment_type).
    final messageTypeStr = _stringFrom(data['type']) ??
        _stringFrom(data['attachment_type'])?.toLowerCase() ??
        '';
    final attachmentUrlRaw = _stringFrom(data['attachment_url']) ??
        _stringFrom(data['mediaUrl']) ??
        '';
    final String resolvedPayloadText;
    if (text.isNotEmpty) {
      resolvedPayloadText = text;
    } else {
      switch (messageTypeStr) {
        case 'image':
          resolvedPayloadText = '\u{1F4F7} Photo';
          break;
        case 'audio':
        case 'voice':
          resolvedPayloadText = '\u{1F3A4} Voice message';
          break;
        case 'video':
          resolvedPayloadText = '\u{1F3A5} Video';
          break;
        case 'document':
          resolvedPayloadText = '\u{1F4C4} Document';
          break;
        case 'gif':
          resolvedPayloadText = 'GIF';
          break;
        case 'sticker':
          resolvedPayloadText = 'Sticker';
          break;
        case 'location':
          resolvedPayloadText = '\u{1F4CD} Location';
          break;
        default:
          resolvedPayloadText =
              messageTypeStr.isNotEmpty ? '\u{1F4DD} Message' : '';
      }
    }

    final displayText = resolvedPayloadText.isNotEmpty ? resolvedPayloadText : current.lastMessage;
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

      final messageTextForList = resolvedPayloadText.isNotEmpty
          ? resolvedPayloadText
          : '\u{1F4DD} Message';

      // Resolve message type and media URL from socket payload (e.g. web app sends attachment_type + attachment_url).
      MessageType resolvedType = MessageType.text;
      if (attachmentUrlRaw.isNotEmpty || messageTypeStr.isNotEmpty) {
        switch (messageTypeStr) {
          case 'image':
            resolvedType = MessageType.image;
            break;
          case 'video':
            resolvedType = MessageType.video;
            break;
          case 'audio':
          case 'voice':
            resolvedType = MessageType.audio;
            break;
          case 'gif':
            resolvedType = MessageType.gif;
            break;
          case 'sticker':
            resolvedType = MessageType.sticker;
            break;
          case 'document':
            resolvedType = MessageType.document;
            break;
          case 'location':
            resolvedType = MessageType.location;
            break;
          default:
            if (attachmentUrlRaw.isNotEmpty) resolvedType = MessageType.image;
        }
      }
      final String? resolvedMediaUrl;
      if (attachmentUrlRaw.isEmpty) {
        resolvedMediaUrl = null;
      } else if (attachmentUrlRaw.startsWith('http')) {
        resolvedMediaUrl = attachmentUrlRaw;
      } else if (attachmentUrlRaw.startsWith('/uploads/')) {
        resolvedMediaUrl = '${AppConstants.apiBaseUrl}$attachmentUrlRaw';
      } else {
        resolvedMediaUrl = attachmentUrlRaw;
      }

      // Don't store "Photo" as caption for image messages — show image only.
      final bool isPlaceholderCaption = messageTextForList == 'Photo' ||
          messageTextForList == '\u{1F4F7} Photo';
      final String messageText = (resolvedType == MessageType.image &&
              isPlaceholderCaption)
          ? ''
          : messageTextForList;

      final isViewOnce = data['is_view_once'] == true || data['isViewOnce'] == true;
      final replyToMessageId = _stringFrom(data['reply_to_message_id']) ??
          _stringFrom(data['replyToMessageId']);
      final isForwarded =
          data['is_forwarded'] == true || data['isForwarded'] == true;
      final viewOnceOpenedAtRaw = data['view_once_opened_at'] ?? data['viewOnceOpenedAt'];
      final DateTime? viewOnceOpenedAt = viewOnceOpenedAtRaw != null
          ? (viewOnceOpenedAtRaw is String
              ? DateTime.tryParse(viewOnceOpenedAtRaw)
              : viewOnceOpenedAtRaw is int
                  ? DateTime.fromMillisecondsSinceEpoch(viewOnceOpenedAtRaw, isUtc: true)
                  : null)
          : null;

      final message = Message(
        id: _stringFrom(data['client_msg_id']) ??
            _stringFrom(data['message_id']) ??
            _stringFrom(data['id']) ??
            'msg_socket_${DateTime.now().millisecondsSinceEpoch}',
        channelId: conversationId,
        senderId: normalizedSenderId,
        text: messageText,
        timestamp: timestamp,
        status: MessageStatus.sent,
        type: resolvedType,
        mediaUrl: resolvedMediaUrl,
        isViewOnce: isViewOnce,
        viewOnceOpenedAt: viewOnceOpenedAt,
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
      );

      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        _repository.addOrUpdateMessage(message);
        updatedMessages = List<Message>.from(state.messages)..add(message);
      }
    }

    // [New Message Processing: Step 4 / 5]
    // Send delivered / read receipts correctly mapped by sender_id bucket
    if (eventType == 'new_message' && !isOutgoing) {
      final serverMsgId = _stringFrom(data['message_id']) ?? _stringFrom(data['id']) ?? 'unknown';
      final bucket = _stringFrom(data['bucket']) ?? _bucketFromTimestamp(timestamp);
      final senderIdForDelivered = senderId ?? 'unknown';

      if (senderIdForDelivered.isNotEmpty && serverMsgId != 'unknown') {
         // Step 4: Send text delivered successfully
        _repository.sendMessageDelivered(
          messageId: serverMsgId,
          conversationId: conversationId,
          bucket: bucket,
          peerUserId: senderIdForDelivered,
        );

        // Step 5: Send read if open
        if (isOpen) {
           _repository.sendMessageRead(
            messageId: serverMsgId,
            conversationId: conversationId,
            bucket: bucket,
            peerUserId: senderIdForDelivered,
          );
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
    final isTyping = eventType == 'typing_indicator' ? data['is_typing'] == true : eventType == 'typing_start';
    emit(state.copyWith(isTyping: isTyping));
  }

  void _handleRecordingEvent(String eventType, Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final conversationId = _stringFrom(data['conversation_id']);
    if (conversationId == null || state.selectedChannel?.id != conversationId) return;
    final isRecording = eventType == 'recording_start';
    emit(state.copyWith(isRecordingAudio: isRecording));
  }

  void _handleRecordingIndicatorEvent(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final conversationId = _stringFrom(data['conversation_id']);
    if (conversationId == null || state.selectedChannel?.id != conversationId) {
      return;
    }

    final isRecordingRaw = data['is_recording'];
    final isRecording =
        isRecordingRaw == true || _stringFrom(isRecordingRaw) == 'true';
    emit(state.copyWith(isRecordingAudio: isRecording));
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

  void _handleMessageStatusUpdate(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final messageId = _stringFrom(data['message_id']);
    final conversationId = _stringFrom(data['conversation_id']);
    final statusStr = _stringFrom(data['status']);
    if (messageId == null || conversationId == null || statusStr == null) return;

    final status = statusStr == 'read' ? MessageStatus.seen : MessageStatus.delivered;

    _repository.updateMessageStatus(messageId, status);

    if (state.selectedChannel?.id == conversationId) {
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) return m.copyWith(status: status);
        return m;
      }).toList();
      emit(state.copyWith(messages: updatedMessages));
    }

    final channels = List<ChatChannel>.from(state.channels);
    var idx = channels.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      final channel = channels[idx];
      if (channel.lastMessageSenderId == AppConstants.currentUserId) {
        MessageStatus? currentStatus = channel.lastMessageStatus;
        if (currentStatus == null || currentStatus.index < status.index) {
          channels[idx] = channel.copyWith(lastMessageStatus: status);
          emit(state.copyWith(channels: channels));
          _repository.updateChannelStatus(conversationId, status);
        }
      }
    }
  }

  void _handleConversationUpserted(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    
    final conversationId = _stringFrom(data['conversation_id']);
    if (conversationId == null) return;

    final peerUserId = _stringFrom(data['peer_user_id']);
    final peerDisplayName = _stringFrom(data['peer_display_name']) ?? 'Unknown';
    var peerAvatarUrl = _stringFrom(data['peer_avatar_url']) ?? '';
    if (peerAvatarUrl.isNotEmpty && !peerAvatarUrl.startsWith('http')) {
      peerAvatarUrl = '${AppConstants.apiBaseUrl}$peerAvatarUrl';
    }

    final lastMessageText = _stringFrom(data['last_message_text']) ?? '';
    final lastMessageSender = _stringFrom(data['last_message_sender']);
    
    final statusStr = _stringFrom(data['last_message_status']);
    MessageStatus? lastMessageStatus;
    if (statusStr == 'read' || statusStr == 'seen') {
      lastMessageStatus = MessageStatus.seen;
    } else if (statusStr == 'delivered') {
      lastMessageStatus = MessageStatus.delivered;
    } else if (statusStr == 'sent') {
      lastMessageStatus = MessageStatus.sent;
    } else if (statusStr == 'sending') {
      lastMessageStatus = MessageStatus.sending;
    }

    final timestampRaw = data['last_message_at'];
    DateTime timestamp = DateTime.now();
    if (timestampRaw is String) {
       timestamp = DateTime.tryParse(timestampRaw)?.toLocal() ?? DateTime.now();
    } else if (timestampRaw is int) {
       timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw, isUtc: true).toLocal();
    }

    int unreadCount = data['unread_count'] is int ? data['unread_count'] as int : 0;
    
    final isOpen = state.selectedChannel?.id == conversationId;
    if (isOpen) {
      unreadCount = 0;
    }

    final channels = List<ChatChannel>.from(state.channels);
    var idx = channels.indexWhere((c) => c.id == conversationId);

    ChatChannel updated;
    if (idx != -1) {
      updated = channels[idx].copyWith(
        name: peerDisplayName,
        avatarUrl: peerAvatarUrl,
        lastMessage: lastMessageText,
        lastMessageTime: timestamp,
        lastMessageStatus: lastMessageStatus,
        lastMessageSenderId: lastMessageSender,
        unreadCount: unreadCount,
        peerUserId: peerUserId,
      );
      channels[idx] = updated;
    } else {
      updated = ChatChannel(
        id: conversationId,
        name: peerDisplayName,
        avatarUrl: peerAvatarUrl,
        lastMessage: lastMessageText,
        lastMessageTime: timestamp,
        lastMessageStatus: lastMessageStatus,
        lastMessageSenderId: lastMessageSender,
        unreadCount: unreadCount,
        peerUserId: peerUserId,
      );
      channels.insert(0, updated);
    }

    channels.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    _repository.upsertChannel(updated);
    
    emit(state.copyWith(channels: channels));
  }

  void _handleMessageReaction(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    final messageId = _stringFrom(data['message_id']);
    final conversationId = _stringFrom(data['conversation_id']);
    final userIdRaw = _stringFrom(data['user_id']);
    final emoji = _stringFrom(data['emoji']) ?? '';
    if (messageId == null || conversationId == null || userIdRaw == null) return;
    final userId = _normalizeReactionUserId(userIdRaw);

    _applyReactionUpdate(
      messageId: messageId,
      conversationId: conversationId,
      userId: userId,
      emoji: emoji,
    );
  }

  void _handleMessageDeleted(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic> ? raw['data'] as Map<String, dynamic> : raw;
    final messageId = _stringFrom(data['message_id']);
    final conversationId = _stringFrom(data['conversation_id']);
    if (messageId == null || conversationId == null) return;

    if (state.selectedChannel?.id == conversationId) {
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(
            text: 'This message was deleted',
            type: MessageType.text,
            audioPath: null,
            mediaUrl: null,
            documentFileName: null,
            documentFileSize: null,
            latitude: null,
            longitude: null,
            locationAddress: null,
            locationName: null,
            contactName: null,
            contactPhone: null,
          );
        }
        return m;
      }).toList();
      emit(state.copyWith(messages: updatedMessages));
    }

    _repository.handleMessageDeletedLocally(messageId, conversationId);
    
    // We update the channel list in case the deleted message was the last message displayed.
    // It will fetch updated channels from DB.
    refreshChatList();
  }

  void _handleMessageEdited(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic> ? raw['data'] as Map<String, dynamic> : raw;
    final messageId = _stringFrom(data['message_id']);
    final conversationId = _stringFrom(data['conversation_id']);
    final newBody = _stringFrom(data['body']);
    final isEdited = data['is_edited'] == true;
    final editedAtStr = _stringFrom(data['edited_at']);
    if (messageId == null || conversationId == null || newBody == null) return;

    DateTime? editedAt = editedAtStr != null ? DateTime.tryParse(editedAtStr)?.toLocal() : DateTime.now();
    
    if (state.selectedChannel?.id == conversationId) {
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(
            text: newBody,
            isEdited: isEdited,
            editedAt: editedAt,
          );
        }
        return m;
      }).toList();
      emit(state.copyWith(messages: updatedMessages));
    }

    _repository.handleMessageEditedLocally(messageId, conversationId, newBody, isEdited, editedAt);
    
    refreshChatList();
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
        final updatedChannel = c.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen ?? c.lastSeen,
        );
        channels[i] = updatedChannel;
        _repository.upsertChannel(updatedChannel);
        updated = true;
        break;
      }
      if (c.id == 'channel_$userId') {
        final updatedChannel = c.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen ?? c.lastSeen,
          peerUserId: c.peerUserId ?? userId,
        );
        channels[i] = updatedChannel;
        _repository.upsertChannel(updatedChannel);
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

  void _handleBlockStatus(Map<String, dynamic> raw) {
    if (isClosed) return;
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;

    final blocked = data['blocked'] == true;
    final blockedId =
        _stringFrom(data['blocked_id']) ?? _stringFrom(data['user_id']);
    if (blockedId == null || blockedId.isEmpty) return;

    if (blocked) {
      final updatedChannels = List<ChatChannel>.from(state.channels)
        ..removeWhere(
          (c) =>
              c.peerUserId == blockedId ||
              c.id == 'channel_$blockedId' ||
              c.id == blockedId,
        );
      emit(state.copyWith(channels: updatedChannels));
    } else {
      // Unblocked: refresh from server so chat list reappears if backend includes it.
      refreshChatList();
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
    bool isViewOnce = false,
  }) async {
    emit(state.copyWith(isSending: true));
    try {
      final message = await _repository.sendImageMessage(
        channelId,
        imagePath,
        text: text,
        isViewOnce: isViewOnce,
      );
      final updatedMessages = List<Message>.from(state.messages)..add(message);
      emit(state.copyWith(messages: updatedMessages, isSending: false));

      _simulateMessageLifecycle(message);
      _refreshChannelList();
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isSending: false));
    }
  }

  /// Opens a view-once image message. Fetches temporary URL (valid 60s), downloads
  /// image with auth, saves to temp file, and updates the message so it displays.
  Future<void> openViewOnceMessage(String messageId) async {
    final messages = state.messages;
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final message = messages[idx];
    if (!message.isImage || !message.isViewOnce || message.isOutgoing) return;
    if (message.viewOnceOpenedAt != null) return; // Already opened

    try {
      final result = await _repository.openViewOnceMessage(messageId);
      final attachmentUrl = result.attachmentUrl;
      final resolvedUrl = attachmentUrl.startsWith('http')
          ? attachmentUrl
          : attachmentUrl.startsWith('/')
              ? '${AppConstants.apiBaseUrl}$attachmentUrl'
              : '${AppConstants.apiBaseUrl}/$attachmentUrl';

      // Fetch image bytes with same auth as API so it loads reliably
      final bytes = await _repository.fetchImageBytes(resolvedUrl);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/view_once_$messageId.jpg');
      await file.writeAsBytes(bytes);
      final localPath = file.path;

      final updated = message.copyWith(
        mediaUrl: resolvedUrl,
        viewOnceOpenedAt: result.viewOnceOpenedAt,
      );
      _repository.addOrUpdateMessage(updated);
      final updatedMessages = List<Message>.from(messages)..[idx] = updated;
      final paths = Map<String, String>.from(state.viewOnceLocalPaths)
        ..[messageId] = localPath;
      emit(state.copyWith(
        messages: updatedMessages,
        viewOnceLocalPaths: paths,
      ));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
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
              if (c.id == ch.id) {
                final repoChannel = _repository.getChannel(c.id) ?? c;
                // Preserve isOnline/lastSeen from state (presence_update) since repo has stale data
                return repoChannel.copyWith(
                  isOnline: c.isOnline,
                  lastSeen: c.lastSeen,
                );
              }
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
    final message = _messageById(messageId);
    if (message == null) return;

    final currentEmoji = _emojiForUser(
      reactions: message.reactions,
      userId: AppConstants.currentUserId,
    );
    final nextEmoji = currentEmoji == emoji ? '' : emoji;

    _applyReactionUpdate(
      messageId: messageId,
      conversationId: message.channelId,
      userId: AppConstants.currentUserId,
      emoji: nextEmoji,
    );

    final peerUserId = _resolvePeerUserIdForChannel(message.channelId);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendReactToMessage(
        messageId: messageId,
        conversationId: message.channelId,
        emoji: nextEmoji,
        peerUserId: peerUserId,
      );
    }
  }

  void removeReaction(String messageId, String emoji) {
    final message = _messageById(messageId);
    if (message == null) return;
    final currentEmoji = _emojiForUser(
      reactions: message.reactions,
      userId: AppConstants.currentUserId,
    );
    if (currentEmoji != emoji) return;

    _applyReactionUpdate(
      messageId: messageId,
      conversationId: message.channelId,
      userId: AppConstants.currentUserId,
      emoji: '',
    );

    final peerUserId = _resolvePeerUserIdForChannel(message.channelId);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendReactToMessage(
        messageId: messageId,
        conversationId: message.channelId,
        emoji: '',
        peerUserId: peerUserId,
      );
    }
  }

  String? _emojiForUser({
    required Map<String, List<String>> reactions,
    required String userId,
  }) {
    final normalizedUserId = _normalizeReactionUserId(userId);
    for (final entry in reactions.entries) {
      if (entry.value.contains(normalizedUserId)) return entry.key;
    }
    return null;
  }

  String _normalizeReactionUserId(String userId) {
    final myBackendId = _repository.getCurrentUserId();
    if (myBackendId != null &&
        myBackendId.isNotEmpty &&
        userId == myBackendId) {
      return AppConstants.currentUserId;
    }
    return userId;
  }

  void _applyReactionUpdate({
    required String messageId,
    required String conversationId,
    required String userId,
    required String emoji,
  }) {
    final normalizedUserId = _normalizeReactionUserId(userId);
    final myBackendId = _repository.getCurrentUserId();
    final idsToRemove = <String>{normalizedUserId};
    if (normalizedUserId == AppConstants.currentUserId &&
        myBackendId != null &&
        myBackendId.isNotEmpty) {
      // Migrate any older reaction entries that used backend UUID.
      idsToRemove.add(myBackendId);
    }

    final updatedMessages = state.messages.map((m) {
      if (m.id != messageId || m.channelId != conversationId) return m;
      final reactions = Map<String, List<String>>.from(
        m.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
      );

      // One reaction per user per message.
      for (final key in reactions.keys.toList()) {
        final users = reactions[key]!;
        users.removeWhere((u) => idsToRemove.contains(u));
        if (users.isEmpty) {
          reactions.remove(key);
        } else {
          reactions[key] = users;
        }
      }

      if (emoji.isNotEmpty) {
        final users = reactions[emoji] ?? <String>[];
        if (!users.contains(normalizedUserId)) users.add(normalizedUserId);
        reactions[emoji] = users;
      }

      return m.copyWith(reactions: reactions);
    }).toList();

    emit(state.copyWith(messages: updatedMessages));
    final msg = updatedMessages.where((m) => m.id == messageId).firstOrNull;
    if (msg != null) {
      _repository.updateMessageReactions(messageId, msg.reactions);
    }
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

  /// Sends recording_start when user starts recording voice note.
  void sendRecordingStart(String channelId) {
    final peerUserId = _repository.getChannel(channelId)?.peerUserId ??
        (channelId.startsWith('channel_')
            ? channelId.replaceFirst('channel_', '')
            : null);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendRecordingStart(
        conversationId: channelId,
        peerUserId: peerUserId,
      );
    }
  }

  /// Sends recording_stop when user stops/cancels/sends voice note.
  void sendRecordingStop(String channelId) {
    final peerUserId = _repository.getChannel(channelId)?.peerUserId ??
        (channelId.startsWith('channel_')
            ? channelId.replaceFirst('channel_', '')
            : null);
    if (peerUserId != null && peerUserId.isNotEmpty) {
      _repository.sendRecordingStop(
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
        isRecordingAudio: false,
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
