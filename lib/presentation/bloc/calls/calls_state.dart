import 'package:equatable/equatable.dart';

import '../../../data/models/call_log.dart';

final class CallsState extends Equatable {
  const CallsState({
    this.calls = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery = '',
    this.refreshErrorMessage,
  });

  final List<CallLog> calls;
  final bool isLoading;

  /// Full-screen error when [calls] is empty.
  final String? errorMessage;

  final String searchQuery;

  /// Shown as SnackBar when a refresh fails but [calls] is non-empty.
  final String? refreshErrorMessage;

  bool get showInitialLoading => isLoading && calls.isEmpty;

  List<CallLog> get filteredCalls {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return calls;
    return calls
        .where((c) => c.peerDisplayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  List<Object?> get props =>
      [calls, isLoading, errorMessage, searchQuery, refreshErrorMessage];
}
