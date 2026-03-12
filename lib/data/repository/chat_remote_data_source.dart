import 'dart:convert';
import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../models/chat_channel.dart';
import '../models/message.dart';
import '../models/message_status.dart';
import '../models/user.dart';
import '../models/user_search.dart';

class ChatRemoteDataSource {
  ChatRemoteDataSource(this._dio);

  final Dio _dio;
  static const String _apiKey = 'chatapp-test-key';

  Future<List<ChatChannel>> fetchChats({required String token}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/conversations',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );

      final data = response.data;
      final conversations = _extractConversationList(data);
      return conversations.map(_mapConversationToChannel).toList();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to fetch conversations.';

      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and retry.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<List<UserSearchResult>> searchUsers({
    required String token,
    required String username,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/users/search',
        queryParameters: <String, dynamic>{'username': username},
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );

      final dynamic raw = response.data;
      final dynamic data = raw is String ? json.decode(raw) : raw;
      if (data == null) return const <UserSearchResult>[];

      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(_mapUserSearch)
            .toList();
      }
      if (data is Map<String, dynamic>) {
        return <UserSearchResult>[_mapUserSearch(data)];
      }

      throw const ApiException(
        message: 'Invalid user search response from server.',
        statusCode: 500,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to search users.';

      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and retry.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<UserSearchResult> getUserPresence({
    required String token,
    required String userId,
    required UserSearchResult baseUser,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/users/$userId/presence',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );

      final dynamic raw = response.data;
      final dynamic data = raw is String ? json.decode(raw) : raw;
      if (data is! Map<String, dynamic>) {
        throw const ApiException(
          message: 'Invalid presence response from server.',
          statusCode: 500,
        );
      }

      final status = data['status'] as String?;
      final lastSeen = data['last_seen'] is int
          ? data['last_seen'] as int
          : null;

      return baseUser.copyWith(presenceStatus: status, lastSeen: lastSeen);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to load presence.';

      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and retry.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<ChatChannel> createConversation({
    required String token,
    required String participantId,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/v1/chat/conversations',
        data: <String, dynamic>{'participant_id': participantId},
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );

      final dynamic raw = response.data;
      final dynamic data = raw is String ? json.decode(raw) : raw;
      if (data is Map<String, dynamic>) {
        return _mapConversationToChannel(data);
      }
      if (data is List &&
          data.isNotEmpty &&
          data.first is Map<String, dynamic>) {
        return _mapConversationToChannel(data.first as Map<String, dynamic>);
      }

      throw const ApiException(
        message: 'Invalid conversation response from server.',
        statusCode: 500,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to create conversation.';

      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and retry.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<List<Message>> fetchMessages(
    String channelId, {
    required String token,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/conversations/$channelId/messages',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
      final data = response.data;
      final list = _extractMessageList(data);
      return list.map(_mapMessageFromApi).whereType<Message>().toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return [];
      final statusCode = e.response?.statusCode;
      String message = 'Failed to fetch messages';
      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and retry.';
      }
      throw ApiException(message: message, statusCode: statusCode);
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  List<Map<String, dynamic>> _extractMessageList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final list = data['data'] ?? data['messages'] ?? data['items'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
    }
    return [];
  }

  Message _mapMessageFromApi(Map<String, dynamic> json) {
    final id = _asString(json['id']) ?? _asString(json['message_id']) ?? '';
    final channelId = _asString(json['conversation_id']) ??
        _asString(json['channel_id']) ??
        _asString(json['channelId']) ??
        '';
    final senderId = _asString(json['sender_id']) ??
        _asString(json['user_id']) ??
        _asString(json['from_user_id']) ??
        _asString(json['senderId']) ??
        '';
    final text = _asString(json['text']) ??
        _asString(json['message']) ??
        _asString(json['content']) ??
        _asString(json['body']) ??
        '';
    final ts = _asDateTime(json['timestamp']) ??
        _asDateTime(json['created_at']) ??
        _asDateTime(json['sent_at']) ??
        _asDateTime(json['last_message_at']) ??
        DateTime.now();
    final statusStr = _asString(json['status'])?.toLowerCase();
    MessageStatus status = MessageStatus.sent;
    if (statusStr == 'sending') status = MessageStatus.sending;
    if (statusStr == 'delivered') status = MessageStatus.delivered;
    if (statusStr == 'seen' || statusStr == 'read') status = MessageStatus.seen;
    if (json['status'] is int) {
      final i = json['status'] as int;
      if (i >= 0 && i < MessageStatus.values.length) {
        status = MessageStatus.values[i];
      }
    }
    return Message(
      id: id.isEmpty ? 'msg_${ts.millisecondsSinceEpoch}' : id,
      channelId: channelId,
      senderId: senderId,
      text: text,
      timestamp: ts,
      status: status,
    );
  }

  Future<Message> sendMessage(Message message) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      return message;
    } catch (e) {
      throw const ApiException(
        message: 'Failed to send message',
        statusCode: 500,
      );
    }
  }

  Future<List<User>> fetchContacts() async {
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      return _generateMockContacts();
    } catch (e) {
      throw const ApiException(
        message: 'Failed to fetch contacts',
        statusCode: 500,
      );
    }
  }

  List<Map<String, dynamic>> _extractConversationList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final list = data['data'] ?? data['conversations'] ?? data['items'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
    }
    throw const ApiException(
      message: 'Invalid conversations response from server.',
      statusCode: 500,
    );
  }

  ChatChannel _mapConversationToChannel(Map<String, dynamic> json) {
    final lastMessageObj = json['last_message'];
    final lastMessageMap = lastMessageObj is Map<String, dynamic>
        ? lastMessageObj
        : null;
    final otherUser = json['other_user'];
    final otherUserMap = otherUser is Map<String, dynamic> ? otherUser : null;

    final id =
        _asString(json['conversation_id']) ??
        _asString(json['id']) ??
        _asString(json['chat_id']);
    if (id == null || id.isEmpty) {
      throw const ApiException(
        message: 'Conversation id missing in response.',
        statusCode: 500,
      );
    }

    final name =
        _asString(json['peer_display_name']) ??
        _asString(json['name']) ??
        _asString(json['title']) ??
        _asString(json['display_name']) ??
        _asString(otherUserMap?['display_name']) ??
        _asString(otherUserMap?['username']) ??
        'Unknown';
    final avatarUrl =
        _asString(json['peer_avatar_url']) ??
        _asString(json['avatar_url']) ??
        _asString(json['avatar']) ??
        _asString(otherUserMap?['avatar_url']) ??
        '';
    final lastMessage =
        _asString(json['last_message_text']) ??
        _asString(lastMessageMap?['text']) ??
        _asString(lastMessageMap?['content']) ??
        _asString(lastMessageMap?['message']) ??
        _asString(json['last_message']) ??
        '';

    final lastMessageTime =
        _asDateTime(json['last_message_at']) ??
        _asDateTime(lastMessageMap?['created_at']) ??
        _asDateTime(lastMessageMap?['timestamp']) ??
        _asDateTime(json['updated_at']) ??
        _asDateTime(json['last_message_time']) ??
        _asDateTime(json['created_at']) ??
        DateTime.now();

    return ChatChannel(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: _asInt(json['unread_count']) ?? 0,
      isOnline: json['is_online'] == true,
    );
  }

  UserSearchResult _mapUserSearch(Map<String, dynamic> json) {
    final userId = _asString(json['user_id']) ?? '';
    final username = _asString(json['username']) ?? '';
    final displayName = _asString(json['display_name']) ?? username;
    final avatarUrl = _asString(json['avatar_url']) ?? '';
    final statusText = _asString(json['status_text']);

    return UserSearchResult(
      userId: userId,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      statusText: statusText,
    );
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      final ms = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  List<Message> _generateMockMessages(String channelId) {
    final now = DateTime.now();
    return List.generate(20, (i) {
      final isOutgoing = i % 3 != 0;
      return Message(
        id: '${channelId}_msg_$i',
        channelId: channelId,
        senderId: isOutgoing ? AppConstants.currentUserId : channelId,
        text: _sampleTexts[i % _sampleTexts.length],
        timestamp: now.subtract(Duration(minutes: (20 - i) * 5)),
        status: isOutgoing ? MessageStatus.seen : MessageStatus.seen,
      );
    });
  }

  List<User> _generateMockContacts() {
    return List.generate(AppConstants.contactNames.length, (i) {
      return User(
        id: 'user_${i + 1}',
        name: AppConstants.contactNames[i],
        avatarUrl: AppConstants
            .placeholderAvatars[i % AppConstants.placeholderAvatars.length],
      );
    })..sort((a, b) => a.name.compareTo(b.name));
  }

  static const _sampleTexts = [
    'Hey, how are you?',
    'I\'m doing great, thanks!',
    'What are you up to?',
    'Not much, just chilling.',
    'Did you see the new update?',
    'Yeah, it looks awesome!',
    'Want to grab lunch?',
    'Sure, where should we meet?',
    'How about that place downtown?',
    'Sounds good!',
    'See you there at noon.',
    'Perfect, see you then!',
    'Don\'t forget to bring the documents.',
    'Got it, I\'ll have them ready.',
    'Thanks a lot!',
    'No problem!',
    'Have a great day!',
    'You too!',
    'Talk to you later.',
    'Bye!',
  ];
}
