import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/service_locator.dart';
import '../bloc/bottom_navigation/bottom_navigation_bloc.dart';
import '../bloc/bottom_navigation/bottom_navigation_event.dart';
import '../bloc/bottom_navigation/bottom_navigation_state.dart';
import '../bloc/calls/calls_bloc.dart';
import 'calls_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';

/// Root shell after authentication: WhatsApp-style bottom tabs with state kept
/// via [IndexedStack] so [ChatListScreen] is not disposed when visiting Calls/Profile.
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BottomNavigationBloc(),
      child: const _MainScreenContent(),
    );
  }
}

class _MainScreenContent extends StatelessWidget {
  const _MainScreenContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BottomNavigationBloc, BottomNavigationState>(
      builder: (context, state) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final unselected = theme.colorScheme.onSurface.withValues(alpha: 0.55);

        return Scaffold(
          body: IndexedStack(
            index: state.currentIndex,
            sizing: StackFit.expand,
            children: const [
              ChatListScreen(),
              _CallsTab(),
              ProfileScreen(),
            ],
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: BottomNavigationBar(
              elevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              type: BottomNavigationBarType.fixed,
              currentIndex: state.currentIndex,
              selectedItemColor: primary,
              unselectedItemColor: unselected,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              onTap: (index) {
                context.read<BottomNavigationBloc>().add(
                      BottomNavigationTabSelected(index),
                    );
              },
              items: [
                BottomNavigationBarItem(
                  icon: Icon(
                    state.currentIndex == 0
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                  ),
                  label: 'Chats',
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    state.currentIndex == 1 ? Icons.phone : Icons.phone_outlined,
                  ),
                  label: 'Calls',
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    state.currentIndex == 2
                        ? Icons.person
                        : Icons.person_outline,
                  ),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<CallsBloc>(),
      child: const CallsScreen(),
    );
  }
}
