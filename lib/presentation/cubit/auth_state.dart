import 'package:equatable/equatable.dart';

class AuthState extends Equatable {
  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final String? errorMessage;

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[isLoading, isAuthenticated, errorMessage];
}

