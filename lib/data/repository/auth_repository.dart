import '../../core/network/api_exception.dart';
import '../local/storage_service.dart';
import '../services/web_socket_service.dart';
import 'auth_remote_data_source.dart';

class AuthRepository {
  AuthRepository(
    this._remoteDataSource,
    this._storageService,
    this._webSocketService,
  );

  final AuthRemoteDataSource _remoteDataSource;
  final StorageService _storageService;
  final WebSocketService _webSocketService;

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
      await _webSocketService.connect(token: token);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<void> logout() async {
    await _webSocketService.disconnect();
    _storageService.clearAll();
  }
}
