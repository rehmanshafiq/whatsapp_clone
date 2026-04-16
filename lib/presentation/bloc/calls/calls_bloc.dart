import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repository/chat_repository.dart';
import 'calls_event.dart';
import 'calls_state.dart';

class CallsBloc extends Bloc<CallsEvent, CallsState> {
  CallsBloc(this._chatRepository) : super(const CallsState()) {
    on<CallsLoadRequested>(_onLoadRequested);
    on<CallsSearchQueryChanged>(_onSearchQueryChanged);
    on<CallsRefreshErrorConsumed>(_onRefreshErrorConsumed);
  }

  final ChatRepository _chatRepository;

  Future<void> _onLoadRequested(
    CallsLoadRequested event,
    Emitter<CallsState> emit,
  ) async {
    final previousCalls = state.calls;
    final searchQuery = state.searchQuery;
    emit(CallsState(
      calls: previousCalls,
      isLoading: true,
      searchQuery: searchQuery,
    ));
    try {
      final list = await _chatRepository.fetchCallHistory();
      emit(CallsState(
        calls: list,
        isLoading: false,
        searchQuery: searchQuery,
      ));
    } on ApiException catch (e) {
      final hadData = previousCalls.isNotEmpty;
      emit(CallsState(
        calls: previousCalls,
        isLoading: false,
        errorMessage: hadData ? null : e.message,
        searchQuery: searchQuery,
        refreshErrorMessage: hadData ? e.message : null,
      ));
    } catch (e) {
      final hadData = previousCalls.isNotEmpty;
      final msg = e.toString();
      emit(CallsState(
        calls: previousCalls,
        isLoading: false,
        errorMessage: hadData ? null : msg,
        searchQuery: searchQuery,
        refreshErrorMessage: hadData ? msg : null,
      ));
    }
  }

  void _onSearchQueryChanged(
    CallsSearchQueryChanged event,
    Emitter<CallsState> emit,
  ) {
    emit(CallsState(
      calls: state.calls,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      searchQuery: event.query,
      refreshErrorMessage: state.refreshErrorMessage,
    ));
  }

  void _onRefreshErrorConsumed(
    CallsRefreshErrorConsumed event,
    Emitter<CallsState> emit,
  ) {
    emit(CallsState(
      calls: state.calls,
      isLoading: state.isLoading,
      errorMessage: state.errorMessage,
      searchQuery: state.searchQuery,
    ));
  }
}
