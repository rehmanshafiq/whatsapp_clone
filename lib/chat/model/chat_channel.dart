import 'package:equatable/equatable.dart';

class ChatChannel extends Equatable {
  final String id;
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final String? imageUrl;
  final bool isDelivered;

  const ChatChannel({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.imageUrl,
    this.isDelivered = false,
  });

  @override
  List<Object?> get props => [id, name, lastMessage, time, unreadCount, imageUrl, isDelivered];
}