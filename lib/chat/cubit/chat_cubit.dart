import 'package:flutter_bloc/flutter_bloc.dart';
import '../model/chat_channel.dart';
import 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit() : super(const ChatInitial());

  Future<void> loadChannels() async {
    emit(const ChatLoading());

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    const mockChannels = [
      ChatChannel(
        id: '1',
        name: 'A User 18',
        lastMessage: 'How are you?',
        time: '3:34 PM',
        unreadCount: 0,
        isDelivered: true,
      ),
      ChatChannel(
        id: '2',
        name: 'D User 14',
        lastMessage: 'Hello',
        time: '10:01 AM',
        unreadCount: 2,
        imageUrl: 'https://picsum.photos/seed/user14/200',
      ),
      ChatChannel(
        id: '3',
        name: 'G User 4',
        lastMessage: 'Hi',
        time: 'Yesterday',
        unreadCount: 3,
        imageUrl: 'https://picsum.photos/seed/user4/200',
      ),
      ChatChannel(
        id: '4',
        name: 'I User 12',
        lastMessage: 'How are you?',
        time: 'Wednesday',
        unreadCount: 0,
        isDelivered: true,
      ),
      ChatChannel(
        id: '5',
        name: 'H User 10',
        lastMessage: 'Hi',
        time: 'Wednesday',
        unreadCount: 1,
        imageUrl: 'https://picsum.photos/seed/user10/200',
      ),
      ChatChannel(
        id: '6',
        name: 'C User 2',
        lastMessage: 'Hi',
        time: 'Tuesday',
        unreadCount: 2,
      ),
      ChatChannel(
        id: '7',
        name: 'D User 20',
        lastMessage: 'Hi',
        time: 'Tuesday',
        unreadCount: 0,
        isDelivered: true,
        imageUrl: 'https://picsum.photos/seed/user20/200',
      ),
      ChatChannel(
        id: '8',
        name: 'E User 23',
        lastMessage: 'Hello',
        time: 'Tuesday',
        unreadCount: 0,
      ),
      ChatChannel(
        id: '9',
        name: 'K User 7',
        lastMessage: 'Hey, are you there?',
        time: 'Tuesday',
        unreadCount: 0,
      ),
      ChatChannel(
        id: '10',
        name: 'M User 5',
        lastMessage: 'See you tomorrow!',
        time: 'Monday',
        unreadCount: 4,
        imageUrl: 'https://picsum.photos/seed/user5/200',
      ),
      ChatChannel(
        id: '11',
        name: 'R User 9',
        lastMessage: 'Thanks a lot!',
        time: 'Monday',
        unreadCount: 0,
        isDelivered: true,
      ),
      ChatChannel(
        id: '12',
        name: 'T User 1',
        lastMessage: 'Good morning!',
        time: 'Sunday',
        unreadCount: 7,
        imageUrl: 'https://picsum.photos/seed/user1/200',
      ),
    ];

    emit(const ChatLoaded(channels: mockChannels));
  }
}