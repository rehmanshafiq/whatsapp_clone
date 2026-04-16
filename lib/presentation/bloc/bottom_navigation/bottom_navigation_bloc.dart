import 'package:flutter_bloc/flutter_bloc.dart';

import 'bottom_navigation_event.dart';
import 'bottom_navigation_state.dart';

class BottomNavigationBloc extends Bloc<BottomNavigationEvent, BottomNavigationState> {
  BottomNavigationBloc() : super(const BottomNavigationState()) {
    on<BottomNavigationTabSelected>(_onTabSelected);
  }

  static const int _tabCount = 3;

  void _onTabSelected(
    BottomNavigationTabSelected event,
    Emitter<BottomNavigationState> emit,
  ) {
    final clamped = event.index.clamp(0, _tabCount - 1);
    if (clamped == state.currentIndex) return;
    emit(BottomNavigationState(currentIndex: clamped));
  }
}
