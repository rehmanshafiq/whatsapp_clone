import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_exception.dart';
import '../../data/repository/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState());

  final AuthRepository _repository;

  Future<void> login({
    required String username,
    required String password,
  }) async {
    if (state.isLoading) return;

    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await _repository.login(username: username, password: password);
      emit(
        state.copyWith(
          isLoading: false,
          isAuthenticated: true,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> registerAndLogin({
    required String username,
    required String password,
    required String displayName,
    required String? avatarUrl,
  }) async {
    if (state.isLoading) return;

    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await _repository.registerAndLogin(
        username: username,
        password: password,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
      emit(
        state.copyWith(
          isLoading: false,
          isAuthenticated: true,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }
}

