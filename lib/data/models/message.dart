import 'package:equatable/equatable.dart';

import 'message_status.dart';

enum MessageType { text, audio }

class Message extends Equatable {
  final String id;
  final String channelId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final MessageStatus status;
  final MessageType type;
  final String? audioPath;
  final Duration? audioDuration;

  const Message({
    required this.id,
    required this.channelId,
    required this.senderId,
    this.text = '',
    required this.timestamp,
    this.status = MessageStatus.sending,
    this.type = MessageType.text,
    this.audioPath,
    this.audioDuration,
  });

  Message copyWith({
    String? id,
    String? channelId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    MessageStatus? status,
    MessageType? type,
    String? audioPath,
    Duration? audioDuration,
  }) {
    return Message(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      audioPath: audioPath ?? this.audioPath,
      audioDuration: audioDuration ?? this.audioDuration,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'channelId': channelId,
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'status': status.index,
        'type': type.index,
        'audioPath': audioPath,
        'audioDuration': audioDuration?.inMilliseconds,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        channelId: json['channelId'] as String,
        senderId: json['senderId'] as String,
        text: json['text'] as String? ?? '',
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: MessageStatus.values[json['status'] as int],
        type: json['type'] != null
            ? MessageType.values[json['type'] as int]
            : MessageType.text,
        audioPath: json['audioPath'] as String?,
        audioDuration: json['audioDuration'] != null
            ? Duration(milliseconds: json['audioDuration'] as int)
            : null,
      );

  bool get isOutgoing => senderId == 'me';
  bool get isAudio => type == MessageType.audio;

  @override
  List<Object?> get props => [
        id,
        channelId,
        senderId,
        text,
        timestamp,
        status,
        type,
        audioPath,
        audioDuration,
      ];
}
