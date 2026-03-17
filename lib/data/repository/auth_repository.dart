import 'package:flutter/foundation.dart';

import '../../core/auth/jwt_utils.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_api_client.dart';
import '../local/storage_service.dart';
import '../services/web_socket_service.dart';
import 'auth_remote_data_source.dart';

class AuthRepository {
  AuthRepository(
    this._remoteDataSource,
    this._storageService,
    this._webSocketService,
    this._dioApiClient,
  );

  final AuthRemoteDataSource _remoteDataSource;
  final StorageService _storageService;
  final WebSocketService _webSocketService;
  final DioApiClient _dioApiClient;
  final ValueNotifier<bool> _authState = ValueNotifier<bool>(false);
  bool _isLoggingOut = false;

  ValueListenable<bool> get authStateListenable => _authState;

  bool get isAuthenticated => _isSessionValid();

  String? getToken() => _storageService.getToken();

  Future<void> initializeSession() async {
    final wasValid = _isSessionValid();
    if (!wasValid) {
      await _performLocalLogout();
    } else {
      final token = _storageService.getToken();
      if (token != null && token.isNotEmpty) {
        _dioApiClient.setAuthHeader(token);
      }
    }
    _authState.value = wasValid;
  }

  Future<void> validateOrLogoutExpiredSession() async {
    if (_isSessionValid()) return;
    await logout();
  }

  Future<void> handleUnauthorized() async {
    await logout();
  }

  Future<void> registerAndLogin({
    required String username,
    required String password,
    required String displayName,
    required String? avatarUrl,
  }) async {
    try {
      await _remoteDataSource.register(
        username: username,
        password: password,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );

      await login(username: username, password: password);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    try {
      final data = await _remoteDataSource.login(
        username: username,
        password: password,
      );

      final token = data['token'] as String;
      final userId = data['user_id'] as String;
      _storageService.saveAuth(token: token, userId: userId);
      _dioApiClient.setAuthHeader(token);
      _authState.value = true;
      await _webSocketService.connect(token: token);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> logout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    try {
      await _performLocalLogout();
      _authState.value = false;
    } finally {
      _isLoggingOut = false;
    }
  }

  bool _isSessionValid() {
    final token = _storageService.getToken();
    final userId = _storageService.getUserId();
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      return false;
    }
    return !JwtUtils.isExpired(token);
  }

  Future<void> _performLocalLogout() async {
    await _webSocketService.disconnect();
    _dioApiClient.clearAuthHeader();
    _storageService.clearAll();
  }
}
