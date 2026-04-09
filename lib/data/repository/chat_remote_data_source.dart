import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Result of opening a view-once message (URL valid 60 seconds).
class ViewOnceOpenResult {
  final String attachmentUrl;
  final DateTime viewOnceOpenedAt;

  const ViewOnceOpenResult({
    required this.attachmentUrl,
    required this.viewOnceOpenedAt,
  });
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

  Future<ChatChannel> createGroup({
    required String token,
    required String name,
    String description = '',
    String avatarUrl = '',
    required List<String> memberIds,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/v1/chat/groups',
        data: <String, dynamic>{
          'name': name,
          'description': description,
          'avatar_url': avatarUrl,
          'member_ids': memberIds,
        },
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
        message: 'Invalid group response from server.',
        statusCode: 500,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to create group.';

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
      final hasMoreVal =
          data['has_more'] ?? data['hasMore'] ?? data['has_next'];
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
    final channelId =
        _asString(json['conversation_id']) ??
        _asString(json['channel_id']) ??
        _asString(json['channelId']) ??
        '';
    final senderId =
        _asString(json['sender_id']) ??
        _asString(json['user_id']) ??
        _asString(json['from_user_id']) ??
        _asString(json['senderId']) ??
        '';
    final text =
        _asString(json['text']) ??
        _asString(json['message']) ??
        _asString(json['content']) ??
        _asString(json['body']) ??
        '';
    final ts =
        _asDateTime(json['timestamp']) ??
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
    final attachmentUrl =
        _asString(json['attachment_url']) ?? _asString(json['mediaUrl']) ?? '';
    final attachmentType =
        _asString(json['attachment_type'])?.toLowerCase() ?? '';
    final audioDuration = _parseAudioDurationFromPayload(json);
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
    final editedAt =
        _asDateTime(json['edited_at']) ?? _asDateTime(json['editedAt']);
    final editedAtValid =
        editedAt != null && editedAt.isAfter(DateTime.utc(2000, 1, 1))
        ? editedAt
        : null;
    final deliveredAt =
        _asDateTime(json['delivered_at']) ?? _asDateTime(json['deliveredAt']);
    final readAt = _asDateTime(json['read_at']) ?? _asDateTime(json['readAt']);
    final isViewOnce =
        json['is_view_once'] == true || json['isViewOnce'] == true;
    final viewOnceOpenedAt =
        _asDateTime(json['view_once_opened_at']) ??
        _asDateTime(json['viewOnceOpenedAt']);
    final replyToMessageId =
        _asString(json['reply_to_message_id']) ??
        _asString(json['replyToMessageId']);
    final replyToSenderId =
        _asString(json['reply_to_sender_id']) ??
        _asString(json['replyToSenderId']);
    final replyToBody =
        _asString(json['reply_to_body']) ?? _asString(json['replyToBody']);
    final replyToAttachmentType =
        _asString(json['reply_to_attachment_type']) ??
        _asString(json['replyToAttachmentType']);
    final isForwarded =
        json['is_forwarded'] == true || json['isForwarded'] == true;
    return Message(
      id: id.isEmpty ? 'msg_${ts.millisecondsSinceEpoch}' : id,
      channelId: channelId,
      senderId: senderId,
      text: text,
      timestamp: ts,
      status: status,
      type: type,
      mediaUrl: attachmentUrl.isEmpty ? null : attachmentUrl,
      audioDuration: type == MessageType.audio ? audioDuration : null,
      deliveredAt: deliveredAt,
      readAt: readAt,
      isEdited: isEdited,
      editedAt: editedAtValid,
      isViewOnce: isViewOnce,
      viewOnceOpenedAt: viewOnceOpenedAt,
      replyToMessageId: replyToMessageId,
      replyToSenderId: replyToSenderId,
      replyToBody: replyToBody,
      replyToAttachmentType: replyToAttachmentType,
      isForwarded: isForwarded,
      reactions: _parseReactionsFromApi(json),
    );
  }

  Map<String, List<String>> _parseReactionsFromApi(Map<String, dynamic> json) {
    final raw = json['reactions'];
    if (raw == null) return const {};

    // Shape A: { "👍": ["user1","user2"], "😂": ["user3"] }
    if (raw is Map<String, dynamic>) {
      final mapped = <String, List<String>>{};
      raw.forEach((emoji, usersRaw) {
        if (emoji.isEmpty) return;
        if (usersRaw is List) {
          final users = usersRaw
              .map((u) => u?.toString() ?? '')
              .where((u) => u.isNotEmpty)
              .toList();
          if (users.isNotEmpty) mapped[emoji] = users;
        }
      });
      if (mapped.isNotEmpty) return mapped;
    }

    // Shape B: [ { "emoji":"👍", "user_id":"u1" }, ... ]
    if (raw is List) {
      final mapped = <String, List<String>>{};
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final emoji = item['emoji']?.toString() ?? '';
        final userId = (item['user_id'] ?? item['userId'])?.toString() ?? '';
        if (emoji.isEmpty || userId.isEmpty) continue;
        mapped.putIfAbsent(emoji, () => <String>[]);
        if (!mapped[emoji]!.contains(userId)) {
          mapped[emoji]!.add(userId);
        }
      }
      if (mapped.isNotEmpty) return mapped;
    }

    return const {};
  }

  /// Open a view-once message. Returns temporary attachment_url (valid 60 seconds).
  /// POST /api/v1/chat/messages/{message_id}/view-once-open
  Future<ViewOnceOpenResult> openViewOnceMessage({
    required String messageId,
    required String token,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/v1/chat/messages/$messageId/view-once-open',
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
          message: 'Invalid view-once-open response.',
          statusCode: 500,
        );
      }
      final attachmentUrl = _asString(data['attachment_url']) ?? '';
      final openedAtStr = _asString(data['view_once_opened_at']);
      final viewOnceOpenedAt = openedAtStr != null && openedAtStr.isNotEmpty
          ? DateTime.tryParse(openedAtStr)
          : DateTime.now();
      if (attachmentUrl.isEmpty) {
        throw const ApiException(
          message: 'View-once open response missing attachment_url.',
          statusCode: 500,
        );
      }
      return ViewOnceOpenResult(
        attachmentUrl: attachmentUrl,
        viewOnceOpenedAt: viewOnceOpenedAt ?? DateTime.now(),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to open view-once message.';
      if (statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      } else if (statusCode == 404) {
        message = 'Message not found or already opened.';
      }
      throw ApiException(message: message, statusCode: statusCode);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Fetches image bytes with auth (for view-once and other protected media).
  Future<Uint8List> fetchImageBytes({
    required String url,
    required String token,
  }) async {
    final fullUrl = url.startsWith('http')
        ? url
        : '${AppConstants.apiBaseUrl}$url';
    final response = await _dio.get<dynamic>(
      fullUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, String>{
          'authorization': 'Bearer $token',
          'x-api-key': _apiKey,
        },
      ),
    );
    final data = response.data;
    if (data == null)
      throw const ApiException(
        message: 'Empty image response',
        statusCode: 500,
      );
    if (data is! Uint8List)
      throw const ApiException(
        message: 'Invalid image response',
        statusCode: 500,
      );
    return data;
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

  /// Upload media file. Returns full URL for use in send_message.
  /// POST /api/v1/upload/media
  Future<String> uploadMedia({
    required String filePath,
    required String type,
    required String token,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw const ApiException(message: 'File not found', statusCode: 400);
      }
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      if (fileName.isEmpty) {
        throw const ApiException(message: 'Invalid file path', statusCode: 400);
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      // Backend expects type as query param: /api/v1/upload/media?type=image
      final response = await _dio.post<dynamic>(
        '/api/v1/upload/media',
        data: formData,
        queryParameters: <String, dynamic>{'type': type},
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
          message: 'Invalid upload response from server.',
          statusCode: 500,
        );
      }

      final url = _asString(data['url']);
      if (url == null || url.isEmpty) {
        throw const ApiException(
          message: 'Upload response missing url.',
          statusCode: 500,
        );
      }

      // Prepend base URL if the response URL is relative
      final baseUrl = AppConstants.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
      final path = url.startsWith('/') ? url : '/$url';
      return '$baseUrl$path';
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to upload media.';
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

  /// Clears all messages for a conversation (current user only).
  /// DELETE /api/v1/chat/conversations/{conv_id}/messages → 204
  Future<void> clearChatMessages({
    required String conversationId,
    required String token,
  }) async {
    try {
      await _dio.delete<dynamic>(
        '/api/v1/chat/conversations/$conversationId/messages',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to clear chat.';
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

  /// Deletes a conversation (current user only).
  /// DELETE /api/v1/chat/conversations/{conv_id} → 204
  Future<void> deleteConversation({
    required String conversationId,
    required String token,
  }) async {
    try {
      await _dio.delete<dynamic>(
        '/api/v1/chat/conversations/$conversationId',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to delete conversation.';
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

  /// Sets mute state on a conversation.
  /// PUT /api/v1/chat/conversations/{conv_id}/mute with body { "is_muted": true/false }.
  Future<bool> toggleMuteConversation({
    required String conversationId,
    required String token,
    required bool isMuted,
  }) async {
    try {
      final response = await _dio.put<dynamic>(
        '/api/v1/chat/conversations/$conversationId/mute',
        data: <String, dynamic>{'is_muted': isMuted},
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
        final serverValue = _asBool(data['is_muted']);
        if (serverValue != null) return serverValue;
      }
      // If server returns 200 without body, trust requested state.
      return isMuted;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to toggle mute.';
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

  /// Blocks a user and prevents messaging in both directions.
  /// POST /api/v1/chat/users/{user_id}/block
  Future<void> blockUser({
    required String userId,
    required String token,
  }) async {
    try {
      await _dio.post<dynamic>(
        '/api/v1/chat/users/$userId/block',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to block user.';
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

  /// Unblocks a previously blocked user.
  /// DELETE /api/v1/chat/users/{user_id}/block
  Future<void> unblockUser({
    required String userId,
    required String token,
  }) async {
    try {
      await _dio.delete<dynamic>(
        '/api/v1/chat/users/$userId/block',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to unblock user.';
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

  /// Returns currently blocked users for authenticated user.
  /// GET /api/v1/chat/blocked-users
  Future<List<UserSearchResult>> fetchBlockedUsers({
    required String token,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/blocked-users',
        options: Options(
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'x-api-key': _apiKey,
          },
        ),
      );

      final dynamic raw = response.data;
      final dynamic data = raw is String ? json.decode(raw) : raw;
      // Backend may return either:
      // - List<user> (legacy / docs)
      // - { blocked_users: List<user>, blocked_by_me: [...], blocked_by_others: [...] }
      final dynamic listCandidate = switch (data) {
        List _ => data,
        Map<String, dynamic> _ => data['blocked_users'],
        _ => null,
      };

      if (listCandidate is! List) {
        throw ApiException(
          message:
              'Invalid blocked users response from server. Expected a list or { blocked_users: [...] }.',
          statusCode: 500,
        );
      }

      return listCandidate
          .whereType<Map<String, dynamic>>()
          .map(_mapUserSearch)
          .toList();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to load blocked users.';
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

  /// Returns a set of all blocked user ids (blocked by me OR blocked by others).
  /// GET /api/v1/chat/blocked-users
  Future<Set<String>> fetchBlockedUserIds({required String token}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/chat/blocked-users',
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
        final ids = <String>{};
        final blockedByMe = data['blocked_by_me'];
        final blockedByOthers = data['blocked_by_others'];
        if (blockedByMe is List) {
          ids.addAll(blockedByMe.map((e) => _asString(e)).whereType<String>());
        }
        if (blockedByOthers is List) {
          ids.addAll(
            blockedByOthers.map((e) => _asString(e)).whereType<String>(),
          );
        }
        // Some backends may only send blocked_users objects.
        final blockedUsers = data['blocked_users'];
        if (blockedUsers is List) {
          ids.addAll(
            blockedUsers
                .whereType<Map<String, dynamic>>()
                .map((m) => _asString(m['user_id']))
                .whereType<String>(),
          );
        }
        return ids;
      }

      // If backend returns a list, we cannot infer ids reliably from docs shape.
      return <String>{};
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to load blocked users.';
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
      isMuted:
          _asBool(json['is_muted']) ??
          _asBool(json['isMuted']) ??
          _asBool(json['muted']) ??
          false,
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

  Duration? _parseAudioDurationFromPayload(Map<String, dynamic> data) {
    Duration? parseFromMap(Map<String, dynamic> map) {
      const msKeys = [
        'audio_duration_ms',
        'voice_duration_ms',
        'duration_ms',
        'audioDurationMs',
        'voiceDurationMs',
        'durationMs',
      ];
      for (final key in msKeys) {
        final raw = _asInt(map[key]);
        if (raw != null && raw > 0) {
          return Duration(milliseconds: raw);
        }
      }

      const secKeys = [
        'audio_duration',
        'voice_duration',
        'duration',
        'audioDuration',
        'voiceDuration',
      ];
      for (final key in secKeys) {
        final raw = _asInt(map[key]);
        if (raw == null || raw <= 0) continue;
        // Heuristic: plain duration fields are commonly seconds.
        // If unusually large, treat as milliseconds.
        if (raw <= 600) {
          return Duration(seconds: raw);
        }
        return Duration(milliseconds: raw);
      }

      return null;
    }

    final direct = parseFromMap(data);
    if (direct != null) return direct;

    for (final nestedKey in const [
      'metadata',
      'attachment_metadata',
      'audio',
      'voice',
      'attachment',
    ]) {
      final nested = data[nestedKey];
      if (nested is Map<String, dynamic>) {
        final nestedDuration = parseFromMap(nested);
        if (nestedDuration != null) return nestedDuration;
      }
    }

    return null;
  }

  bool? _asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
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
