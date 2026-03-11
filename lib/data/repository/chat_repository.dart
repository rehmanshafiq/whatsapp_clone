import 'dart:math';
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
  final _random = Random();

  ChatRepository(
    this._remoteDataSource,
    this._storageService,
    this._webSocketService,
  );

  Stream<dynamic> get socketMessages => _webSocketService.messagesStream;

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
      final localMessages = _storageService.getMessagesForChannel(channelId);
      if (localMessages.isNotEmpty) return localMessages;

      final remoteMessages = await _remoteDataSource.fetchMessages(channelId);
      final allMessages = _storageService.getMessages();
      allMessages.addAll(remoteMessages);
      _storageService.saveMessages(allMessages);
      return remoteMessages;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendMessage(String channelId, String text) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
      );

      _sendMessageOverSocket(
        conversationId: channelId,
        text: text,
        timestamp: message.timestamp,
      );
      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      _updateChannelLastMessage(channelId, text);
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Message> sendAudioMessage(
    String channelId,
    String audioPath,
    Duration audioDuration,
  ) async {
    try {
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_audio',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.audio,
        audioPath: audioPath,
        audioDuration: audioDuration,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      _updateChannelLastMessage(channelId, '\u{1F3A4} Voice message');
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
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_media',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: '',
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: isSticker ? MessageType.sticker : MessageType.gif,
        mediaUrl: mediaUrl,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      _updateChannelLastMessage(channelId, isSticker ? 'Sticker' : 'GIF');
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
      final message = Message(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_image',
        channelId: channelId,
        senderId: AppConstants.currentUserId,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        type: MessageType.image,
        mediaUrl: imagePath,
      );

      await _remoteDataSource.sendMessage(message);
      _persistMessage(message);
      _updateChannelLastMessage(channelId, '\u{1F4F7} Photo');
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
      _updateChannelLastMessage(channelId, '\u{1F3A5} Video');
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
      _updateChannelLastMessage(
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
      _updateChannelLastMessage(channelId, '\u{1F464} $name');
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
      _updateChannelLastMessage(channelId, '\u{1F4C4} $fileName');
      return message;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Message generateAutoReply(String channelId) {
    final reply = AppConstants
        .autoReplies[_random.nextInt(AppConstants.autoReplies.length)];
    final message = Message(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}_reply',
      channelId: channelId,
      senderId: channelId,
      text: reply,
      timestamp: DateTime.now(),
      status: MessageStatus.seen,
    );
    _persistMessage(message);
    _updateChannelLastMessage(channelId, reply);
    return message;
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

  void _updateChannelLastMessage(String channelId, String text) {
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
        participantId: user.userId,
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
    required String conversationId,
    required String text,
    required DateTime timestamp,
  }) {
    if (!_webSocketService.isConnected) return;

    final payload = <String, dynamic>{
      'conversation_id': conversationId,
      'sender_id': AppConstants.currentUserId,
      'message': text,
      'timestamp': timestamp.toIso8601String(),
    };

    _webSocketService.send(payload);
  }
}
