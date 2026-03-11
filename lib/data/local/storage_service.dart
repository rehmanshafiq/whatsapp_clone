import 'dart:convert';

import 'package:get_storage/get_storage.dart';

import '../../core/constants/app_constants.dart';
import '../models/chat_channel.dart';
import '../models/message.dart';

class StorageService {
  final GetStorage _box;

  StorageService(this._box);

  List<ChatChannel> getChats() {
    final raw = _box.read<String>(AppConstants.storageChatsKey);
    if (raw == null) return [];
    final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((e) => ChatChannel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void saveChats(List<ChatChannel> chats) {
    final encoded = json.encode(chats.map((c) => c.toJson()).toList());
    _box.write(AppConstants.storageChatsKey, encoded);
  }

  List<Message> getMessages() {
    final raw = _box.read<String>(AppConstants.storageMessagesKey);
    if (raw == null) return [];
    final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
    return decoded
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void saveMessages(List<Message> messages) {
    final encoded = json.encode(messages.map((m) => m.toJson()).toList());
    _box.write(AppConstants.storageMessagesKey, encoded);
  }

  List<Message> getMessagesForChannel(String channelId) {
    return getMessages().where((m) => m.channelId == channelId).toList();
  }

  void clearAll() {
    _box.erase();
  }

  String? getToken() {
    return _box.read<String>(AppConstants.storageTokenKey);
  }

  String? getUserId() {
    return _box.read<String>(AppConstants.storageUserIdKey);
  }

  void saveAuth({
    required String token,
    required String userId,
  }) {
    _box.write(AppConstants.storageTokenKey, token);
    _box.write(AppConstants.storageUserIdKey, userId);
  }
}
