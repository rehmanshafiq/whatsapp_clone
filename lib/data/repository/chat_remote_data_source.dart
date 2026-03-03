import 'dart:math';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/chat_channel.dart';
import '../models/message.dart';
import '../models/message_status.dart';
import '../models/user.dart';

class ChatRemoteDataSource {
  final ApiClient apiClient;
  final _random = Random();

  ChatRemoteDataSource(this.apiClient);

  Future<List<ChatChannel>> fetchChats() async {
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      return _generateMockChats();
    } catch (e) {
      throw const ApiException(
        message: 'Failed to fetch chats',
        statusCode: 500,
      );
    }
  }

  Future<List<Message>> fetchMessages(String channelId) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      return _generateMockMessages(channelId);
    } catch (e) {
      throw const ApiException(
        message: 'Failed to fetch messages',
        statusCode: 500,
      );
    }
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

  List<ChatChannel> _generateMockChats() {
    final now = DateTime.now();
    final names = List<String>.from(AppConstants.contactNames)..shuffle(_random);
    return List.generate(12, (i) {
      final name = names[i % names.length];
      return ChatChannel(
        id: 'channel_${i + 1}',
        name: name,
        avatarUrl: AppConstants.placeholderAvatars[i % AppConstants.placeholderAvatars.length],
        lastMessage: AppConstants.autoReplies[i % AppConstants.autoReplies.length],
        lastMessageTime: now.subtract(Duration(hours: i * 3, minutes: _random.nextInt(60))),
        unreadCount: i % 3 == 0 ? _random.nextInt(8) : 0,
        isOnline: i % 4 == 0,
      );
    });
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
        avatarUrl: AppConstants.placeholderAvatars[i % AppConstants.placeholderAvatars.length],
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
