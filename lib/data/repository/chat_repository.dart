import 'dart:typed_data';
import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../local/storage_service.dart';
import '../models/chat_channel.dart';
import '../models/message.dart';
import '../models/message_status.dart';
import '../models/user.dart';
import '../models/user_search.dart';
import '../services/web_socket_service.dart';
import 'chat_remote_data_source.dart';

export '../models/message.dart' show MessageType;

class ChatRepository {
  final ChatRemoteDataSource _remoteDataSource;
  final StorageService _storageService;
  final WebSocketService _webSocketService;

  ChatRepository(
    this._remoteDataSource,
    this._storageService,
    this._webSocketService,
  );

  Stream<dynamic> get socketMessages => _webSocketService.messagesStream;

  /// Current user's id from backend (stored at login). Used to normalize
  /// message senderId so UI can show sent (right) vs received (left).
  String? getCurrentUserId() => _storageService.getUserId();

  Future<List<ChatChannel>> getChats() async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      await _webSocketService.connect(token: token);
      final remoteChats = await _remoteDataSource.fetchChats(token: token);
      _storageService.saveChats(remoteChats);
      return remoteChats;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<List<Message>> getMessages(String channelId) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final remoteMessages =
          await _remoteDataSource.fetchMessages(channelId, token: token);
      final normalized = _normalizeMessageSenderIds(remoteMessages);
      final allMessages = _storageService.getMessages();
      allMessages.removeWhere((m) => m.channelId == channelId);
      allMessages.addAll(normalized);
      _storageService.saveMessages(allMessages);
      return normalized;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Ensures messages from the current user have senderId == AppConstants.currentUserId
  /// so Message.isOutgoing (senderId == 'me') shows bubbles on the right.
  List<Message> _normalizeMessageSenderIds(List<Message> messages) {
    final myId = _storageService.getUserId();
    if (myId == null || myId.isEmpty) return messages;
    return messages
        .map((m) =>
            m.senderId == myId
                ? m.copyWith(senderId: AppConstants.currentUserId)
                : m)
        .toList();
  }

  /// Normalizes sender IDs for display (e.g. when loading from storage or emitting state).
  /// Call before showing messages in the UI so own messages show on the right.
  List<Message> normalizeMessageSenderIds(List<Message> messages) {
    return _normalizeMessageSenderIds(messages);
  }

  /// Fetches messages for [channelId] from the server and updates local
  /// storage. Use for polling so new messages appear without WebSocket.
  Future<List<Message>> refreshMessagesFromServer(String channelId) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        final fromStorage = _storageService.getMessagesForChannel(channelId);
        return _normalizeMessageSenderIds(fromStorage);
      }

      final remoteMessages =
          await _remoteDataSource.fetchMessages(channelId, token: token);
      final normalized = _normalizeMessageSenderIds(remoteMessages);
      final allMessages = _storageService.getMessages();
      allMessages.removeWhere((m) => m.channelId == channelId);
      allMessages.addAll(normalized);
      _storageService.saveMessages(allMessages);
      normalized.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return normalized;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendMessage(String channelId, String text) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
      );

      final peerUserId = _getPeerUserIdForChannel(channelId);
      if (peerUserId != null) {
        _sendMessageOverSocket(
          clientMsgId: clientMsgId,
          conversationId: channelId,
          peerUserId: peerUserId,
          body: text,
          attachmentType: '',
          attachmentUrl: '',
        );
      }
      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, text);
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Resolves peer user id for a channel (from stored channel or channel_ prefix).
  String? _getPeerUserIdForChannel(String channelId) {
    final channel = getChannel(channelId);
    if (channel?.peerUserId != null && channel!.peerUserId!.isNotEmpty) {
      return channel.peerUserId;
    }
    if (channelId.startsWith('channel_')) {
      return channelId.replaceFirst('channel_', '');
    }
    return null;
  }

  Future<Message> sendAudioMessage(
    String channelId,
    String audioPath,
    Duration audioDuration,
  ) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_audio';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.audio,
        audioPath: audioPath,
        audioDuration: audioDuration,
      );

      final peerUserId = _getPeerUserIdForChannel(channelId);
      if (peerUserId != null) {
        _sendMessageOverSocket(
          clientMsgId: clientMsgId,
          conversationId: channelId,
          peerUserId: peerUserId,
          body: '',
          // Backend contract: "voice" for voice notes.
          attachmentType: 'voice',
          attachmentUrl: audioPath,
        );
      }

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, '\u{1F3A4} Voice message');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendMediaMessage(
    String channelId,
    String mediaUrl,
    bool isSticker,
  ) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_media';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: isSticker ? MessageType.sticker : MessageType.gif,
        mediaUrl: mediaUrl,
      );

      final peerUserId = _getPeerUserIdForChannel(channelId);
      if (peerUserId != null) {
        _sendMessageOverSocket(
          clientMsgId: clientMsgId,
          conversationId: channelId,
          peerUserId: peerUserId,
          body: '',
          attachmentType: isSticker ? 'sticker' : 'gif',
          attachmentUrl: mediaUrl,
        );
      }

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, isSticker ? 'Sticker' : 'GIF');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendImageMessage(
    String channelId,
    String imagePath, {
    String text = '',
  }) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_image';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.image,
        mediaUrl: imagePath,
      );

      final peerUserId = _getPeerUserIdForChannel(channelId);
      if (peerUserId != null) {
        _sendMessageOverSocket(
          clientMsgId: clientMsgId,
          conversationId: channelId,
          peerUserId: peerUserId,
          body: text,
          attachmentType: 'image',
          attachmentUrl: imagePath,
        );
      }

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, '\u{1F4F7} Photo');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendVideoMessage(
    String channelId,
    String videoPath, {
    String text = '',
  }) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_video',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.video,
        mediaUrl: videoPath,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, '\u{1F3A5} Video');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendLocationMessage(
    String channelId, {
    required double latitude,
    required double longitude,
    required String locationName,
    required String locationAddress,
    bool isLiveLocation = false,
    bool isLiveLocationActive = false,
    DateTime? liveLocationEndsAt,
  }) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_location',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: locationAddress,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.location,
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        locationAddress: locationAddress,
        isLiveLocation: isLiveLocation,
        isLiveLocationActive: isLiveLocationActive,
        liveLocationEndsAt: liveLocationEndsAt,
        liveLocationUpdatedAt: DateTime.now(),
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(
        channelId,
        isLiveLocation ? '\u{1F4CD} Live location' : '\u{1F4CD} Location',
      );
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendContactMessage(
    String channelId, {
    required String name,
    required String phone,
    String? contactId,
    Uint8List? photo,
  }) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_contact',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '$name\n$phone',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.contact,
        contactId: contactId,
        contactName: name,
        contactPhone: phone,
        contactPhotoBase64: photo != null ? base64Encode(photo) : null,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, '\u{1F464} $name');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendDocumentMessage(
    String channelId, {
    required String filePath,
    required String fileName,
    required int fileSize,
  }) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_document',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.document,
        mediaUrl: filePath,
        documentFileName: fileName,
        documentFileSize: fileSize,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, '\u{1F4C4} $fileName');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  void _persistMessage(Message message) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      allMessages[idx] = message;
    } else {
      allMessages.add(message);
    }
    _storageService.saveMessages(allMessages);
  }

  /// Persists an incoming message (e.g. from WebSocket) so it appears in
  /// the chat and survives app restarts. Use when the cubit receives a
  /// message for the open channel.
  void addOrUpdateMessage(Message message) {
    _persistMessage(message);
  }

  /// Replaces optimistic message id with server-assigned id (from message_sent_ack).
  void replaceOptimisticMessageId(String clientMsgId, String serverMessageId) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == clientMsgId);
    if (idx == -1) return;
    allMessages[idx] = allMessages[idx].copyWith(
      id: serverMessageId,
      status: MessageStatus.sent,
    );
    _storageService.saveMessages(allMessages);
  }

  void updateMessageStatus(String messageId, MessageStatus status) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      allMessages[idx] = allMessages[idx].copyWith(status: status);
      _storageService.saveMessages(allMessages);
    }
  }

  void updateMessageReactions(
    String messageId,
    Map<String, List<String>> reactions,
  ) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      allMessages[idx] = allMessages[idx].copyWith(reactions: reactions);
      _storageService.saveMessages(allMessages);
    }
  }

  void updateLocationMessage(
    String messageId, {
    required double latitude,
    required double longitude,
    required String locationName,
    required String locationAddress,
    required DateTime liveLocationUpdatedAt,
    bool? isLiveLocationActive,
  }) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      allMessages[idx] = allMessages[idx].copyWith(
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        locationAddress: locationAddress,
        text: locationAddress,
        liveLocationUpdatedAt: liveLocationUpdatedAt,
        isLiveLocationActive:
            isLiveLocationActive ?? allMessages[idx].isLiveLocationActive,
      );
      _storageService.saveMessages(allMessages);
    }
  }

  void updateChannelLastMessage(String channelId, String text) {
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(
        lastMessage: text,
        lastMessageTime: DateTime.now(),
      );
      _storageService.saveChats(chats);
    }
  }

  void updateChannelStatus(String channelId, MessageStatus status) {
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(lastMessageStatus: status);
      _storageService.saveChats(chats);
    }
  }

  void upsertChannel(ChatChannel channel) {
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == channel.id);
    if (idx >= 0) {
      chats[idx] = channel;
    } else {
      chats.insert(0, channel);
    }
    // Re-sort to maintain order
    chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    _storageService.saveChats(chats);
  }

  void clearUnread(String channelId) {
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(unreadCount: 0);
      _storageService.saveChats(chats);
    }
  }

  void incrementUnread(String channelId) {
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == channelId);
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(unreadCount: chats[idx].unreadCount + 1);
      _storageService.saveChats(chats);
    }
  }

  void deleteChat(String channelId) {
    final chats = _storageService.getChats();
    chats.removeWhere((c) => c.id == channelId);
    _storageService.saveChats(chats);

    final messages = _storageService.getMessages();
    messages.removeWhere((m) => m.channelId == channelId);
    _storageService.saveMessages(messages);
  }

  ChatChannel createChat(User contact) {
    final chats = _storageService.getChats();
    final existing = chats.where((c) => c.id == 'channel_${contact.id}');
    if (existing.isNotEmpty) return existing.first;

    final channel = ChatChannel(
      id: 'channel_${contact.id}',
      name: contact.name,
      avatarUrl: contact.avatarUrl,
      lastMessageTime: DateTime.now(),
      peerUserId: contact.id,
    );
    chats.insert(0, channel);
    _storageService.saveChats(chats);
    return channel;
  }

  Future<List<User>> getContacts() async {
    try {
      return await _remoteDataSource.fetchContacts();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  ChatChannel? getChannel(String channelId) {
    final chats = _storageService.getChats();
    final matches = chats.where((c) => c.id == channelId);
    return matches.isNotEmpty ? matches.first : null;
  }

  Future<List<UserSearchResult>> searchUsers(String username) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      final baseResults = await _remoteDataSource.searchUsers(
        token: token,
        username: username,
      );

      if (baseResults.isEmpty) return baseResults;

      final List<UserSearchResult> enriched = [];
      for (final user in baseResults) {
        try {
          final withPresence = await _remoteDataSource.getUserPresence(
            token: token,
            userId: user.userId,
            baseUser: user,
          );
          enriched.add(withPresence);
        } on ApiException {
          enriched.add(user);
        }
      }

      return enriched;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<ChatChannel> createOrGetConversationForUser(
    UserSearchResult user,
  ) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      final channel = await _remoteDataSource.createConversation(
        token: token,
        peerUserId: user.userId,
      );

      final chats = _storageService.getChats();
      final idx = chats.indexWhere((c) => c.id == channel.id);
      if (idx >= 0) {
        chats[idx] = channel;
      } else {
        chats.insert(0, channel);
      }
      _storageService.saveChats(chats);
      return channel;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  void _sendMessageOverSocket({
    required String clientMsgId,
    required String conversationId,
    required String peerUserId,
    required String body,
    String attachmentType = '',
    String attachmentUrl = '',
  }) {
    if (!_webSocketService.isConnected) return;

    // Message envelope: event, data (object, never null), optional id, timestamp (Unix ms).
    final envelope = <String, dynamic>{
      'event': 'send_message',
      'data': <String, dynamic>{
        'client_msg_id': clientMsgId,
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
        'body': body,
        'attachment_type': attachmentType,
        'attachment_url': attachmentUrl,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends message_delivered when we receive a new_message (double grey tick).
  void sendMessageDelivered({
    required String messageId,
    required String conversationId,
    required String bucket,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'message_delivered',
      'data': <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationId,
        'bucket': bucket,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends message_read when user opens/views the conversation (double blue tick).
  void sendMessageRead({
    required String messageId,
    required String conversationId,
    required String bucket,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'message_read',
      'data': <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationId,
        'bucket': bucket,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Deletes one of the current user's sent messages (soft delete: body -> "message deleted").
  void sendDeleteMessage({
    required String messageId,
    required String conversationId,
    required String bucket,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'delete_message',
      'data': <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationId,
        'bucket': bucket,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Edits one of the current user's sent messages (blocked once peer has read it).
  void sendEditMessage({
    required String messageId,
    required String conversationId,
    required String bucket,
    required String body,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'edit_message',
      'data': <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationId,
        'bucket': bucket,
        'body': body,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends typing_start when the user begins typing. Re-send on each keystroke to reset server 4s TTL.
  void sendTypingStart({
    required String conversationId,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'typing_start',
      'data': <String, dynamic>{
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends typing_stop when the user stops typing (input cleared, message sent, or screen left).
  void sendTypingStop({
    required String conversationId,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'typing_stop',
      'data': <String, dynamic>{
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }
}
