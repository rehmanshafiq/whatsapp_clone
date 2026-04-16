sealed class CallsEvent {
  const CallsEvent();
}

/// Loads or refreshes call history from the API.
final class CallsLoadRequested extends CallsEvent {
  const CallsLoadRequested();
}

final class CallsSearchQueryChanged extends CallsEvent {
  const CallsSearchQueryChanged(this.query);

  final String query;
}

/// Clears [CallsState.refreshErrorMessage] after showing a SnackBar.
final class CallsRefreshErrorConsumed extends CallsEvent {
  const CallsRefreshErrorConsumed();
}
