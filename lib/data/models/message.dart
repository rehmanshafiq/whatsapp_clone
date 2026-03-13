import 'package:equatable/equatable.dart';

import 'message_status.dart';

enum MessageType { text, audio, gif, sticker, image, video, location, contact, document }

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
  final String? mediaUrl; // For GIF or Sticker
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String? locationAddress;
  final bool isLiveLocation;
  final bool isLiveLocationActive;
  final DateTime? liveLocationEndsAt;
  final DateTime? liveLocationUpdatedAt;
  final String? contactId;
  final String? contactName;
  final String? contactPhone;
  final String? contactPhotoBase64;
  /// For document messages: display name of the file.
  final String? documentFileName;
  /// For document messages: file size in bytes.
  final int? documentFileSize;
  final Map<String, List<String>> reactions;
  /// When the message was delivered (from API delivered_at).
  final DateTime? deliveredAt;
  /// When the message was read (from API read_at).
  final DateTime? readAt;
  /// Whether the message was edited (from API is_edited).
  final bool isEdited;
  /// When the message was last edited (from API edited_at).
  final DateTime? editedAt;

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
    this.mediaUrl,
    this.latitude,
    this.longitude,
    this.locationName,
    this.locationAddress,
    this.isLiveLocation = false,
    this.isLiveLocationActive = false,
    this.liveLocationEndsAt,
    this.liveLocationUpdatedAt,
    this.contactId,
    this.contactName,
    this.contactPhone,
    this.contactPhotoBase64,
    this.documentFileName,
    this.documentFileSize,
    this.reactions = const {},
    this.deliveredAt,
    this.readAt,
    this.isEdited = false,
    this.editedAt,
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
    String? mediaUrl,
    double? latitude,
    double? longitude,
    String? locationName,
    String? locationAddress,
    bool? isLiveLocation,
    bool? isLiveLocationActive,
    DateTime? liveLocationEndsAt,
    DateTime? liveLocationUpdatedAt,
    String? contactId,
    String? contactName,
    String? contactPhone,
    String? contactPhotoBase64,
    String? documentFileName,
    int? documentFileSize,
    Map<String, List<String>>? reactions,
    DateTime? deliveredAt,
    DateTime? readAt,
    bool? isEdited,
    DateTime? editedAt,
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
      mediaUrl: mediaUrl ?? this.mediaUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      locationAddress: locationAddress ?? this.locationAddress,
      isLiveLocation: isLiveLocation ?? this.isLiveLocation,
      isLiveLocationActive: isLiveLocationActive ?? this.isLiveLocationActive,
      liveLocationEndsAt: liveLocationEndsAt ?? this.liveLocationEndsAt,
      liveLocationUpdatedAt:
          liveLocationUpdatedAt ?? this.liveLocationUpdatedAt,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      contactPhotoBase64: contactPhotoBase64 ?? this.contactPhotoBase64,
      documentFileName: documentFileName ?? this.documentFileName,
      documentFileSize: documentFileSize ?? this.documentFileSize,
      reactions: reactions ?? this.reactions,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
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
    'mediaUrl': mediaUrl,
    'latitude': latitude,
    'longitude': longitude,
    'locationName': locationName,
    'locationAddress': locationAddress,
    'isLiveLocation': isLiveLocation,
    'isLiveLocationActive': isLiveLocationActive,
    'liveLocationEndsAt': liveLocationEndsAt?.toIso8601String(),
    'liveLocationUpdatedAt': liveLocationUpdatedAt?.toIso8601String(),
    'contactId': contactId,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'contactPhotoBase64': contactPhotoBase64,
    'documentFileName': documentFileName,
    'documentFileSize': documentFileSize,
    'reactions': reactions.map((k, v) => MapEntry(k, v)),
    'deliveredAt': deliveredAt?.toIso8601String(),
    'readAt': readAt?.toIso8601String(),
    'isEdited': isEdited,
    'editedAt': editedAt?.toIso8601String(),
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
    mediaUrl: json['mediaUrl'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    locationName: json['locationName'] as String?,
    locationAddress: json['locationAddress'] as String?,
    isLiveLocation: json['isLiveLocation'] as bool? ?? false,
    isLiveLocationActive: json['isLiveLocationActive'] as bool? ?? false,
    liveLocationEndsAt: json['liveLocationEndsAt'] != null
        ? DateTime.parse(json['liveLocationEndsAt'] as String)
        : null,
    liveLocationUpdatedAt: json['liveLocationUpdatedAt'] != null
        ? DateTime.parse(json['liveLocationUpdatedAt'] as String)
        : null,
    contactId: json['contactId'] as String?,
    contactName: json['contactName'] as String?,
    contactPhone: json['contactPhone'] as String?,
    contactPhotoBase64: json['contactPhotoBase64'] as String?,
    documentFileName: json['documentFileName'] as String?,
    documentFileSize: json['documentFileSize'] as int?,
    reactions:
        (json['reactions'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, List<String>.from(v as List)),
        ) ??
        const {},
    deliveredAt: json['deliveredAt'] != null
        ? DateTime.parse(json['deliveredAt'] as String)
        : null,
    readAt: json['readAt'] != null
        ? DateTime.parse(json['readAt'] as String)
        : null,
    isEdited: json['isEdited'] as bool? ?? false,
    editedAt: json['editedAt'] != null
        ? DateTime.parse(json['editedAt'] as String)
        : null,
  );

  bool get isOutgoing => senderId == 'me';
  bool get isAudio => type == MessageType.audio;
  bool get isGif => type == MessageType.gif;
  bool get isSticker => type == MessageType.sticker;
  bool get isImage => type == MessageType.image;
  bool get isVideo => type == MessageType.video;
  bool get isLocation => type == MessageType.location;
  bool get isContact => type == MessageType.contact;
  bool get isDocument => type == MessageType.document;

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
    mediaUrl,
    latitude,
    longitude,
    locationName,
    locationAddress,
    isLiveLocation,
    isLiveLocationActive,
    liveLocationEndsAt,
    liveLocationUpdatedAt,
    contactId,
    contactName,
    contactPhone,
    contactPhotoBase64,
    documentFileName,
    documentFileSize,
    reactions,
    deliveredAt,
    readAt,
    isEdited,
    editedAt,
  ];
}
