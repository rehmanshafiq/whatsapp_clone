import 'package:equatable/equatable.dart';

/// Immutable state for the main shell bottom navigation.
final class BottomNavigationState extends Equatable {
  const BottomNavigationState({this.currentIndex = 0});

  /// Active tab: 0 Chats, 1 Calls, 2 Profile.
  final int currentIndex;

  @override
  List<Object?> get props => [currentIndex];
}
