sealed class BottomNavigationEvent {
  const BottomNavigationEvent();
}

final class BottomNavigationTabSelected extends BottomNavigationEvent {
  const BottomNavigationTabSelected(this.index);

  final int index;
}
