abstract class AppConstants {
  static const String currentUserId = 'me';
  static const String currentUserName = 'You';

  static const Duration sendDelay = Duration(seconds: 1);
  static const Duration deliverDelay = Duration(seconds: 2);
  static const Duration seenDelay = Duration(seconds: 3);
  static const Duration minReplyDelay = Duration(seconds: 2);
  static const Duration maxReplyDelay = Duration(seconds: 4);

  static const String storageChatsKey = 'chats';
  static const String storageMessagesKey = 'messages';

  static const List<String> autoReplies = [
    'Sure, sounds good!',
    'I\'ll get back to you on that.',
    'That\'s interesting!',
    'Let me think about it.',
    'Haha, nice one!',
    'Okay, no problem.',
    'Can we talk later?',
    'I\'m busy right now.',
    'Thanks for letting me know!',
    'Got it!',
    'Will do!',
    'What do you think?',
    'Absolutely!',
    'I agree!',
    'Perfect!',
  ];

  static const List<String> placeholderAvatars = [
    'https://i.pravatar.cc/150?img=1',
    'https://i.pravatar.cc/150?img=2',
    'https://i.pravatar.cc/150?img=3',
    'https://i.pravatar.cc/150?img=4',
    'https://i.pravatar.cc/150?img=5',
    'https://i.pravatar.cc/150?img=6',
    'https://i.pravatar.cc/150?img=7',
    'https://i.pravatar.cc/150?img=8',
    'https://i.pravatar.cc/150?img=9',
    'https://i.pravatar.cc/150?img=10',
    'https://i.pravatar.cc/150?img=11',
    'https://i.pravatar.cc/150?img=12',
    'https://i.pravatar.cc/150?img=13',
    'https://i.pravatar.cc/150?img=14',
    'https://i.pravatar.cc/150?img=15',
    'https://i.pravatar.cc/150?img=16',
    'https://i.pravatar.cc/150?img=17',
    'https://i.pravatar.cc/150?img=18',
    'https://i.pravatar.cc/150?img=19',
    'https://i.pravatar.cc/150?img=20',
  ];

  static const List<String> contactNames = [
    'Alice Johnson',
    'Bob Smith',
    'Charlie Brown',
    'Diana Prince',
    'Edward Norton',
    'Fiona Apple',
    'George Lucas',
    'Hannah Montana',
    'Ivan Petrov',
    'Jessica Alba',
    'Kevin Hart',
    'Laura Palmer',
    'Michael Scott',
    'Nancy Drew',
    'Oscar Wilde',
    'Patricia Arquette',
    'Quincy Jones',
    'Rachel Green',
    'Steve Rogers',
    'Tina Turner',
  ];
}
