import 'package:equatable/equatable.dart';

import 'message_status.dart';

class Message extends Equatable {
  final String id;
  final String channelId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final MessageStatus status;

  const Message({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.status = MessageStatus.sending,
  });

  Message copyWith({
    String? id,
    String? channelId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'channelId': channelId,
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'status': status.index,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        channelId: json['channelId'] as String,
        senderId: json['senderId'] as String,
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: MessageStatus.values[json['status'] as int],
      );

  bool get isOutgoing => senderId == 'me';

  @override
  List<Object?> get props => [id, channelId, senderId, text, timestamp, status];
}
