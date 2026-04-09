import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../local/storage_service.dart';
import '../models/chat_channel.dart';
import '../models/group_details.dart';
import '../models/group_member.dart';
import '../models/message.dart';
import '../models/message_status.dart';
import '../models/user.dart';
import '../models/user_search.dart';
import '../services/web_socket_service.dart';
import 'chat_remote_data_source.dart';

export '../models/message.dart' show MessageType;
export 'chat_remote_data_source.dart' show ViewOnceOpenResult;

class ChatRepository {
  final ChatRemoteDataSource _remoteDataSource;
  final StorageService _storageService;
  final WebSocketService _webSocketService;

  UserSearchResult? _cachedCurrentUserProfile;

  ChatRepository(
    this._remoteDataSource,
    this._storageService,
    this._webSocketService,
  );

  Stream<dynamic> get socketMessages => _webSocketService.messagesStream;

  /// Current user's id from backend (stored at login). Used to normalize
  /// message senderId so UI can show sent (right) vs received (left).
  String? getCurrentUserId() => _storageService.getUserId();

  /// Headers for loading media from our API (Bearer + x-api-key). Used by
  /// CachedNetworkImage so /uploads/... requests succeed.
  Map<String, String>? getAuthHeadersForMedia() {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) return null;
    return <String, String>{
      'Authorization': 'Bearer $token',
      'x-api-key': AppConstants.apiKey,
    };
  }

  /// Fetches image bytes with auth (for view-once so image loads reliably).
  Future<Uint8List> fetchImageBytes(String url) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return _remoteDataSource.fetchImageBytes(url: url, token: token);
  }

  UserSearchResult? get currentUserProfile => _cachedCurrentUserProfile;

  Future<UserSearchResult> fetchCurrentUserProfile() async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      final profile = await _remoteDataSource.fetchCurrentUserProfile(
        token: token,
      );
      _cachedCurrentUserProfile = profile;
      return profile;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

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
      // Filter out chats with blocked users so they don't reappear after refresh.
      Set<String> blockedIds = <String>{};
      try {
        blockedIds = await _remoteDataSource.fetchBlockedUserIds(token: token);
      } catch (_) {
        // If blocked endpoint fails, fall back to showing chats.
      }

      final filtered = blockedIds.isEmpty
          ? remoteChats
          : remoteChats
                .where(
                  (c) =>
                      c.peerUserId == null ||
                      c.peerUserId!.isEmpty ||
                      !blockedIds.contains(c.peerUserId),
                )
                .toList();

      _storageService.saveChats(filtered);
      return filtered;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Fetches messages from local storage instantly for immediate UI display.
  List<Message> getLocalMessages(String channelId) {
    try {
      final fromStorage = _storageService.getMessagesForChannel(channelId);
      return _normalizeMessageSenderIds(fromStorage);
    } catch (_) {
      return [];
    }
  }

  /// Fetches the latest [limit] messages for [channelId]. Used for initial chat load.
  Future<MessagesPage> getMessages(
    String channelId, {
    int limit = ChatRemoteDataSource.defaultMessagesLimit,
  }) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final page = await _remoteDataSource.fetchMessages(
        channelId,
        token: token,
        limit: limit,
      );
      var normalized = _normalizeMessageSenderIds(page.messages);
      final allMessages = _storageService.getMessages();
      final existingById = <String, Message>{
        for (final m in allMessages.where((m) => m.channelId == channelId))
          m.id: m,
      };
      normalized = _mergeReactionsFromLocal(
        incoming: normalized,
        existingById: existingById,
      );
      allMessages.removeWhere((m) => m.channelId == channelId);
      allMessages.addAll(normalized);
      _storageService.saveMessages(allMessages);
      return MessagesPage(
        messages: normalized,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Fetches older messages for pagination. Use [beforeMessageId] of the
  /// oldest message currently in the list, or [cursor] if the backend returns it.
  Future<MessagesPage> loadOlderMessages(
    String channelId, {
    required String? beforeMessageId,
    String? cursor,
    int limit = ChatRemoteDataSource.defaultMessagesLimit,
  }) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final page = await _remoteDataSource.fetchMessages(
        channelId,
        token: token,
        limit: limit,
        before: beforeMessageId,
        cursor: cursor,
      );
      var normalized = _normalizeMessageSenderIds(page.messages);
      // Merge into storage: older messages go to the front of the channel's list
      final allMessages = _storageService.getMessages();
      final existing = allMessages
          .where((m) => m.channelId == channelId)
          .toList();
      final existingById = <String, Message>{for (final m in existing) m.id: m};
      normalized = _mergeReactionsFromLocal(
        incoming: normalized,
        existingById: existingById,
      );
      final existingIds = existing.map((m) => m.id).toSet();
      final newOlder = normalized
          .where((m) => !existingIds.contains(m.id))
          .toList();
      allMessages.removeWhere((m) => m.channelId == channelId);
      existing.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      newOlder.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      allMessages.addAll([...newOlder, ...existing]);
      _storageService.saveMessages(allMessages);
      return MessagesPage(
        messages: normalized,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
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
        .map(
          (m) => m.senderId == myId
              ? m.copyWith(senderId: AppConstants.currentUserId)
              : m,
        )
        .toList();
  }

  /// Normalizes sender IDs for display (e.g. when loading from storage or emitting state).
  /// Call before showing messages in the UI so own messages show on the right.
  List<Message> normalizeMessageSenderIds(List<Message> messages) {
    return _normalizeMessageSenderIds(messages);
  }

  List<Message> _mergeReactionsFromLocal({
    required List<Message> incoming,
    required Map<String, Message> existingById,
  }) {
    return incoming.map((m) {
      if (m.reactions.isNotEmpty) return m;
      final existing = existingById[m.id];
      if (existing == null || existing.reactions.isEmpty) return m;
      return m.copyWith(reactions: existing.reactions);
    }).toList();
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

      final page = await _remoteDataSource.fetchMessages(
        channelId,
        token: token,
        limit: ChatRemoteDataSource.defaultMessagesLimit,
      );
      var normalized = _normalizeMessageSenderIds(page.messages);
      final allMessages = _storageService.getMessages();
      final existingById = <String, Message>{
        for (final m in allMessages.where((m) => m.channelId == channelId))
          m.id: m,
      };
      normalized = _mergeReactionsFromLocal(
        incoming: normalized,
        existingById: existingById,
      );
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

  Future<Message> sendMessage(
    String channelId,
    String text, {
    String replyToMessageId = '',
    bool isForwarded = false,
  }) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        replyToMessageId: replyToMessageId.isEmpty ? null : replyToMessageId,
        isForwarded: isForwarded,
      );

      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: text,
        attachmentType: '',
        attachmentUrl: '',
        replyToMessageId: replyToMessageId,
        isForwarded: isForwarded,
      );
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
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final mediaUrl = await _remoteDataSource.uploadMedia(
        filePath: audioPath,
        token: token,
        type: 'audio',
      );
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
        mediaUrl: mediaUrl,
        audioDuration: audioDuration,
      );

      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: '',
        attachmentType: 'voice',
        attachmentUrl: mediaUrl,
        audioDuration: audioDuration,
      );

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

      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: '',
        attachmentType: isSticker ? 'sticker' : 'gif',
        attachmentUrl: mediaUrl,
      );

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
    bool isViewOnce = false,
  }) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final mediaUrl = await _remoteDataSource.uploadMedia(
        filePath: imagePath,
        token: token,
        type: 'image',
      );
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_image';
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.image,
        mediaUrl: mediaUrl,
        isViewOnce: isViewOnce,
      );

      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: text,
        attachmentType: 'image',
        attachmentUrl: mediaUrl,
        isViewOnce: isViewOnce,
      );

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
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final mediaUrl = await _remoteDataSource.uploadMedia(
        filePath: videoPath,
        token: token,
        type: 'video',
      );
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_video';
      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: text,
        attachmentType: 'video',
        attachmentUrl: mediaUrl,
      );
      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.video,
        mediaUrl: mediaUrl,
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
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }
      final mediaUrl = await _remoteDataSource.uploadMedia(
        filePath: filePath,
        token: token,
        type: 'document',
      );
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_document',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.document,
        mediaUrl: mediaUrl,
        documentFileName: fileName,
        documentFileSize: fileSize,
      );

      _sendMessageOverSocket(
        clientMsgId: message.id,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: '',
        attachmentType: 'document',
        attachmentUrl: mediaUrl,
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

  Future<Message> forwardMessageToChannel({
    required String channelId,
    required Message source,
  }) async {
    try {
      final clientMsgId = 'msg_${DateTime.now().millisecondsSinceEpoch}_fwd';
      final attachmentType = _attachmentTypeForMessage(source);
      final attachmentUrl = source.mediaUrl ?? '';
      final body = source.text;
      _sendMessageOverSocket(
        clientMsgId: clientMsgId,
        conversationId: channelId,
        peerUserId: _getPeerUserIdForChannel(channelId),
        body: body,
        attachmentType: attachmentType,
        attachmentUrl: attachmentUrl,
        audioDuration: source.isAudio ? source.audioDuration : null,
        isViewOnce: source.isViewOnce,
        replyToMessageId: source.replyToMessageId ?? '',
        isForwarded: true,
      );

      final message = Message(
        id: clientMsgId,
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: body,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: source.type,
        mediaUrl: source.mediaUrl,
        audioPath: source.audioPath,
        audioDuration: source.audioDuration,
        latitude: source.latitude,
        longitude: source.longitude,
        locationName: source.locationName,
        locationAddress: source.locationAddress,
        isLiveLocation: source.isLiveLocation,
        isLiveLocationActive: source.isLiveLocationActive,
        liveLocationEndsAt: source.liveLocationEndsAt,
        liveLocationUpdatedAt: source.liveLocationUpdatedAt,
        contactId: source.contactId,
        contactName: source.contactName,
        contactPhone: source.contactPhone,
        contactPhotoBase64: source.contactPhotoBase64,
        documentFileName: source.documentFileName,
        documentFileSize: source.documentFileSize,
        isViewOnce: source.isViewOnce,
        isForwarded: true,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      updateChannelLastMessage(channelId, _channelPreviewForMessage(message));
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  String _attachmentTypeForMessage(Message message) {
    if (message.isImage) return 'image';
    if (message.isVideo) return 'video';
    if (message.isAudio) return 'voice';
    if (message.isGif) return 'gif';
    if (message.isSticker) return 'sticker';
    if (message.isDocument) return 'document';
    if (message.isLocation) return 'location';
    return '';
  }

  String _channelPreviewForMessage(Message message) {
    if (message.text.trim().isNotEmpty) return message.text.trim();
    if (message.isImage) return '\u{1F4F7} Photo';
    if (message.isVideo) return '\u{1F3A5} Video';
    if (message.isAudio) return '\u{1F3A4} Voice message';
    if (message.isDocument) {
      return '\u{1F4C4} ${message.documentFileName ?? 'Document'}';
    }
    if (message.isLocation) return '\u{1F4CD} Location';
    if (message.isGif) return 'GIF';
    if (message.isSticker) return 'Sticker';
    return '\u{1F4DD} Message';
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

  /// Uploads a media file and returns the server URL.
  /// Used by the cubit for optimistic media sending (upload separately,
  /// then send the message with the returned URL).
  Future<String> uploadMedia({
    required String filePath,
    required String type,
  }) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return _remoteDataSource.uploadMedia(
      filePath: filePath,
      token: token,
      type: type,
    );
  }

  /// Public accessor for peer user id so the cubit can send socket messages.
  String? getPeerUserIdForChannel(String channelId) {
    return _getPeerUserIdForChannel(channelId);
  }

  /// Public accessor so the cubit can send messages over WebSocket directly.
  void sendMessageOverSocket({
    required String clientMsgId,
    required String conversationId,
    String? peerUserId,
    required String body,
    String attachmentType = '',
    String attachmentUrl = '',
    Duration? audioDuration,
    bool isViewOnce = false,
    String replyToMessageId = '',
    bool isForwarded = false,
  }) {
    _sendMessageOverSocket(
      clientMsgId: clientMsgId,
      conversationId: conversationId,
      peerUserId: peerUserId,
      body: body,
      attachmentType: attachmentType,
      attachmentUrl: attachmentUrl,
      audioDuration: audioDuration,
      isViewOnce: isViewOnce,
      replyToMessageId: replyToMessageId,
      isForwarded: isForwarded,
    );
  }

  /// Public wrapper so the cubit can persist messages after optimistic send.
  void persistMessage(Message message) {
    _persistMessage(message);
  }

  /// Public wrapper for sendMessage on the remote data source.
  Future<Message> sendRemoteMessage(Message message) {
    return _remoteDataSource.sendMessage(message);
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

  void handleMessageDeletedLocally(String messageId, String conversationId) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final msg = allMessages[idx];
      // Message is unread if it is incoming and status is not seen (or read)
      final isUnreadIncoming =
          !msg.isOutgoing && msg.status != MessageStatus.seen;

      allMessages[idx] = msg.copyWith(
        text: 'message deleted',
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
        replyToMessageId: '',
        replyToSenderId: '',
        replyToBody: '',
        replyToAttachmentType: '',
        isEdited: false,
      );
      _storageService.saveMessages(allMessages);

      if (isUnreadIncoming) {
        final chats = _storageService.getChats();
        final chatIdx = chats.indexWhere((c) => c.id == conversationId);
        if (chatIdx >= 0 && chats[chatIdx].unreadCount > 0) {
          chats[chatIdx] = chats[chatIdx].copyWith(
            unreadCount: chats[chatIdx].unreadCount - 1,
          );
          _storageService.saveChats(chats);
        }
      }
    }
  }

  void handleMessageEditedLocally(
    String messageId,
    String conversationId,
    String newBody,
    bool isEdited,
    DateTime? editedAt,
  ) {
    final allMessages = _storageService.getMessages();
    final idx = allMessages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      allMessages[idx] = allMessages[idx].copyWith(
        text: newBody,
        isEdited: isEdited,
        editedAt: editedAt,
      );
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

  Future<UserSearchResult> updateCurrentUserProfile({
    required UserSearchResult? current,
    String? displayName,
    String? avatarUrl,
    String? statusText,
  }) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      final Map<String, dynamic> body = <String, dynamic>{};
      if (displayName != null &&
          displayName.isNotEmpty &&
          displayName != current?.displayName) {
        body['display_name'] = displayName;
      }
      if (avatarUrl != null &&
          avatarUrl.isNotEmpty &&
          avatarUrl != current?.avatarUrl) {
        body['avatar_url'] = avatarUrl;
      }
      if (statusText != null && statusText != current?.statusText) {
        body['status_text'] = statusText;
      }

      if (body.isEmpty && current != null) {
        _cachedCurrentUserProfile = current;
        return current;
      }

      final updated = await _remoteDataSource.updateUserProfile(
        token: token,
        body: body,
      );
      _cachedCurrentUserProfile = updated;
      return updated;
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

  /// Clears all messages for [conversationId] via API, then wipes local messages
  /// and resets the channel's last message text.
  Future<void> clearChatMessages(String conversationId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    await _remoteDataSource.clearChatMessages(
      conversationId: conversationId,
      token: token,
    );
    // Remove local messages for this channel
    final messages = _storageService.getMessages();
    messages.removeWhere((m) => m.channelId == conversationId);
    _storageService.saveMessages(messages);
    // Reset last message on the channel
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(lastMessage: '');
      _storageService.saveChats(chats);
    }
  }

  /// Deletes a conversation via API, then removes the channel and its messages
  /// from local storage.
  Future<void> deleteConversationRemote(String conversationId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    await _remoteDataSource.deleteConversation(
      conversationId: conversationId,
      token: token,
    );
    // Remove locally
    deleteChat(conversationId);
  }

  /// Toggles mute on a conversation via API. Returns the new muted state
  /// and updates the local channel.
  Future<bool> toggleMuteConversation(String conversationId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    final chats = _storageService.getChats();
    final idx = chats.indexWhere((c) => c.id == conversationId);
    final currentMuted = idx >= 0 ? chats[idx].isMuted : false;
    final desiredMuted = !currentMuted;

    final isMuted = await _remoteDataSource.toggleMuteConversation(
      conversationId: conversationId,
      token: token,
      isMuted: desiredMuted,
    );
    // Update local channel
    if (idx >= 0) {
      chats[idx] = chats[idx].copyWith(isMuted: isMuted);
      _storageService.saveChats(chats);
    }
    return isMuted;
  }

  Future<void> blockUser(String userId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    await _remoteDataSource.blockUser(userId: userId, token: token);
  }

  Future<void> unblockUser(String userId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    await _remoteDataSource.unblockUser(userId: userId, token: token);
  }

  Future<List<UserSearchResult>> getBlockedUsers() async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return _remoteDataSource.fetchBlockedUsers(token: token);
  }

  /// Fetches presence (online status, last_seen) for the peer user of [channelId].
  /// Returns the channel with updated isOnline and lastSeen, or null on failure.
  Future<ChatChannel?> fetchPresenceForChannel(String channelId) async {
    try {
      final channel = getChannel(channelId);
      if (channel == null ||
          channel.peerUserId == null ||
          channel.peerUserId!.isEmpty) {
        return null;
      }
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) return null;

      final baseUser = UserSearchResult(
        userId: channel.peerUserId!,
        username: channel.name,
        displayName: channel.name,
        avatarUrl: channel.avatarUrl,
      );
      final withPresence = await _remoteDataSource.getUserPresence(
        token: token,
        userId: channel.peerUserId!,
        baseUser: baseUser,
      );
      DateTime? lastSeen;
      if (withPresence.lastSeen != null && withPresence.lastSeen! > 0) {
        lastSeen = DateTime.fromMillisecondsSinceEpoch(
          withPresence.lastSeen!,
          isUtc: true,
        ).toLocal();
      }
      return channel.copyWith(
        isOnline: withPresence.presenceStatus == 'online',
        lastSeen: lastSeen ?? channel.lastSeen,
      );
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
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

  Future<ChatChannel> createGroup({
    required String name,
    String description = '',
    String avatarUrl = '',
    required List<String> memberIds,
  }) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      final channel = await _remoteDataSource.createGroup(
        token: token,
        name: name,
        description: description,
        avatarUrl: avatarUrl,
        memberIds: memberIds,
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

  Future<GroupDetails> getGroupDetails(String groupId) async {
    try {
      final token = _storageService.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          message: 'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
      }

      return await _remoteDataSource.getGroupDetails(
        token: token,
        groupId: groupId,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<GroupDetails> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    final token = _requireToken();
    try {
      return await _remoteDataSource.updateGroup(
        token: token,
        groupId: groupId,
        name: name,
        description: description,
        avatarUrl: avatarUrl,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> deleteGroup(String groupId) async {
    final token = _requireToken();
    try {
      await _remoteDataSource.deleteGroup(token: token, groupId: groupId);
      final chats = _storageService.getChats();
      chats.removeWhere((c) => c.groupId == groupId);
      _storageService.saveChats(chats);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<List<GroupMember>> listGroupMembers(String groupId) async {
    final token = _requireToken();
    try {
      return await _remoteDataSource.listGroupMembers(
        token: token,
        groupId: groupId,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> addGroupMembers({
    required String groupId,
    required List<String> userIds,
  }) async {
    final token = _requireToken();
    try {
      await _remoteDataSource.addGroupMembers(
        token: token,
        groupId: groupId,
        userIds: userIds,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> removeGroupMember({
    required String groupId,
    required String userId,
  }) async {
    final token = _requireToken();
    try {
      await _remoteDataSource.removeGroupMember(
        token: token,
        groupId: groupId,
        userId: userId,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required String role,
  }) async {
    final token = _requireToken();
    try {
      await _remoteDataSource.updateMemberRole(
        token: token,
        groupId: groupId,
        userId: userId,
        role: role,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> leaveGroup(String groupId) async {
    final token = _requireToken();
    try {
      await _remoteDataSource.leaveGroup(token: token, groupId: groupId);
      final chats = _storageService.getChats();
      chats.removeWhere((c) => c.groupId == groupId);
      _storageService.saveChats(chats);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  String _requireToken() {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return token;
  }

  /// Opens a view-once message. Returns temporary image URL (valid 60 seconds).
  Future<ViewOnceOpenResult> openViewOnceMessage(String messageId) async {
    final token = _storageService.getToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Your session has expired. Please sign in again.',
        statusCode: 401,
      );
    }
    return _remoteDataSource.openViewOnceMessage(
      messageId: messageId,
      token: token,
    );
  }

  void _sendMessageOverSocket({
    required String clientMsgId,
    required String conversationId,
    String? peerUserId,
    required String body,
    String attachmentType = '',
    String attachmentUrl = '',
    Duration? audioDuration,
    bool isViewOnce = false,
    String replyToMessageId = '',
    bool isForwarded = false,
  }) {
    if (!_webSocketService.isConnected) return;

    final data = <String, dynamic>{
      'client_msg_id': clientMsgId,
      'conversation_id': conversationId,
      'body': body,
      'attachment_type': attachmentType,
      'attachment_url': attachmentUrl,
      if (audioDuration != null) ...{
        'audio_duration_ms': audioDuration.inMilliseconds,
        'audio_duration': audioDuration.inSeconds,
      },
      'is_view_once': isViewOnce,
      'reply_to_message_id': replyToMessageId,
      'is_forwarded': isForwarded,
    };

    if (peerUserId != null && peerUserId.isNotEmpty) {
      data['peer_user_id'] = peerUserId;
    }

    final envelope = <String, dynamic>{
      'event': 'send_message',
      'data': data,
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
    String? peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final data = <String, dynamic>{
      'message_id': messageId,
      'conversation_id': conversationId,
      'bucket': bucket,
    };

    if (peerUserId != null && peerUserId.isNotEmpty) {
      data['peer_user_id'] = peerUserId;
    }

    final envelope = <String, dynamic>{
      'event': 'delete_message',
      'data': data,
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
    String? peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final data = <String, dynamic>{
      'message_id': messageId,
      'conversation_id': conversationId,
      'bucket': bucket,
      'body': body,
    };

    if (peerUserId != null && peerUserId.isNotEmpty) {
      data['peer_user_id'] = peerUserId;
    }

    final envelope = <String, dynamic>{
      'event': 'edit_message',
      'data': data,
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

  /// Sends recording_start when user starts recording a voice note.
  void sendRecordingStart({
    required String conversationId,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'recording_start',
      'data': <String, dynamic>{
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends recording_stop when user stops/cancels/sends voice recording.
  void sendRecordingStop({
    required String conversationId,
    required String peerUserId,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'recording_stop',
      'data': <String, dynamic>{
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }

  /// Sends react_to_message over websocket.
  /// If [emoji] is empty, server removes the current user's reaction.
  void sendReactToMessage({
    required String messageId,
    required String conversationId,
    required String peerUserId,
    required String emoji,
  }) {
    if (!_webSocketService.isConnected) return;

    final envelope = <String, dynamic>{
      'event': 'react_to_message',
      'data': <String, dynamic>{
        'message_id': messageId,
        'conversation_id': conversationId,
        'emoji': emoji,
        'peer_user_id': peerUserId,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _webSocketService.send(envelope);
  }
}
