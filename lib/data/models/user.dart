import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String name;
  final String about;
  final String avatarUrl;

  const User({
    required this.id,
    required this.name,
    this.about = 'Hey there! I am using WhatsApp',
    this.avatarUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'about': about,
        'avatarUrl': avatarUrl,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        about: json['about'] as String? ?? 'Hey there! I am using WhatsApp',
        avatarUrl: json['avatarUrl'] as String? ?? '',
      );

  @override
  List<Object?> get props => [id, name, about, avatarUrl];
}
