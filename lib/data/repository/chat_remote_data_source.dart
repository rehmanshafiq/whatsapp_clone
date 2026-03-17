import 'dart:convert';
import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../models/chat_channel.dart';
import '../models/message.dart';
import '../models/message_status.dart';
import '../models/user.dart';
import '../models/user_search.dart';

/// Paginated response for messages API. Supports cursor, before, or page-based pagination.
class MessagesPage {
  final List<Message> messages;
  final String? nextCursor;
  final bool hasMore;

  const MessagesPage({
    required this.messages,
    this.nextCursor,
    this.hasMore = false,
  });

  static const MessagesPage empty = MessagesPage(messages: [], hasMore: false);
}

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

  Future<UserSearchResult> fetchCurrentUserProfile({
    required String token,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/users/me',
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
          message: 'Invalid profile response from server.',
          statusCode: 500,
        );
      }

      return _mapUserSearch(data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to load profile.';

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

  Future<UserSearchResult> updateUserProfile({
    required String token,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/v1/chat/users/profile',
        data: body,
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
          message: 'Invalid profile update response from server.',
          statusCode: 500,
        );
      }

      return _mapUserSearch(data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to update profile.';

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
    required String peerUserId,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/v1/chat/conversations',
        data: <String, dynamic>{'peer_user_id': peerUserId},
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

  /// Paginated messages response: list plus next cursor / hasMore for older messages.
  static const int defaultMessagesLimit = 50;

  Future<MessagesPage> fetchMessages(
    String channelId, {
    required String token,
    int limit = defaultMessagesLimit,
    String? before,
    String? cursor,
    int? page,
  }) async {
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (before != null && before.isNotEmpty) {
        queryParams['before'] = before;
      } else if (cursor != null && cursor.isNotEmpty) {
        queryParams['cursor'] = cursor;
      } else if (page != null && page > 1) {
        queryParams['page'] = page;
      }

      final response = await _dio.get<dynamic>(
        '/api/v1/chat/conversations/$channelId/messages',
        queryParameters: queryParams,
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
      final data = response.data;
      final list = _extractMessageList(data);
      final messages = list.map(_mapMessageFromApi).toList();
      final pageInfo = _extractPageInfo(data, list);
      return MessagesPage(
        messages: messages,
        nextCursor: pageInfo.nextCursor,
        hasMore: pageInfo.hasMore,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return MessagesPage.empty;
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

  ({String? nextCursor, bool hasMore}) _extractPageInfo(
    dynamic data,
    List<Map<String, dynamic>> messageList,
  ) {
    String? nextCursor;
    bool hasMore = false;

    if (data is Map<String, dynamic>) {
      nextCursor = _asString(
        data['next_cursor'] ?? data['cursor'] ?? data['next_cursor_token'],
      );
      final hasMoreVal = data['has_more'] ?? data['hasMore'] ?? data['has_next'];
      if (hasMoreVal is bool) {
        hasMore = hasMoreVal;
      } else if (hasMoreVal != null) {
        hasMore = hasMoreVal == true || hasMoreVal == 1;
      }
      // Infer hasMore from nextCursor or from list size vs limit
      if (nextCursor != null && nextCursor.isNotEmpty) {
        hasMore = true;
      }
    }

    return (nextCursor: nextCursor, hasMore: hasMore);
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
    final attachmentUrl = _asString(json['attachment_url']) ??
        _asString(json['mediaUrl']) ??
        '';
    final attachmentType = _asString(json['attachment_type'])?.toLowerCase() ?? '';
    MessageType type = MessageType.text;
    if (attachmentUrl.isNotEmpty || attachmentType.isNotEmpty) {
      switch (attachmentType) {
        case 'image':
          type = MessageType.image;
          break;
        case 'video':
          type = MessageType.video;
          break;
        case 'audio':
        case 'voice': // Treat voice notes as audio messages
          type = MessageType.audio;
          break;
        case 'gif':
          type = MessageType.gif;
          break;
        case 'sticker':
          type = MessageType.sticker;
          break;
        case 'document':
          type = MessageType.document;
          break;
        case 'location':
          type = MessageType.location;
          break;
        default:
          if (attachmentUrl.isNotEmpty) type = MessageType.image;
      }
    }
    final isEdited = json['is_edited'] == true || json['isEdited'] == true;
    final editedAt = _asDateTime(json['edited_at']) ?? _asDateTime(json['editedAt']);
    final editedAtValid = editedAt != null &&
        editedAt.isAfter(DateTime.utc(2000, 1, 1))
        ? editedAt
        : null;
    final deliveredAt = _asDateTime(json['delivered_at']) ?? _asDateTime(json['deliveredAt']);
    final readAt = _asDateTime(json['read_at']) ?? _asDateTime(json['readAt']);
    return Message(
      id: id.isEmpty ? 'msg_${ts.millisecondsSinceEpoch}' : id,
      channelId: channelId,
      senderId: senderId,
      text: text,
      timestamp: ts,
      status: status,
      type: type,
      mediaUrl: attachmentUrl.isEmpty ? null : attachmentUrl,
      deliveredAt: deliveredAt,
      readAt: readAt,
      isEdited: isEdited,
      editedAt: editedAtValid,
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

    final peerUserId =
        _asString(json['peer_user_id']) ?? _asString(otherUserMap?['id']);

    return ChatChannel(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: _asInt(json['unread_count']) ?? 0,
      isOnline: json['is_online'] == true,
      peerUserId: peerUserId,
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
}
