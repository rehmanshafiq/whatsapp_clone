import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/chat_detail_screen.dart';
import '../../presentation/screens/chat_list_screen.dart';
import '../../presentation/screens/select_contact_screen.dart';
import '../../presentation/screens/responsive_shell.dart';

class AppRouter {
  static const String chats = 'chats';
  static const String chatDetail = 'chatDetail';
  static const String contacts = 'contacts';

  static final GoRouter router = GoRouter(
    initialLocation: '/chats',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ResponsiveShell(child: child),
        routes: [
          GoRoute(
            path: '/chats',
            name: chats,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ChatListScreen()),
            routes: [
              GoRoute(
                path: ':id',
                name: chatDetail,
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(
                    key: state.pageKey,
                    child: ChatDetailScreen(channelId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/contacts',
            name: contacts,
            pageBuilder: (context, state) =>
                const MaterialPage(child: SelectContactScreen()),
          ),
        ],
      ),
    ],
  );
}
