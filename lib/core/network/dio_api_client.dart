import 'package:dio/dio.dart';

import '../../data/local/storage_service.dart';
import '../auth/jwt_utils.dart';

class DioApiClient {
  DioApiClient(this._storageService)
    : dio = Dio(
        BaseOptions(
          baseUrl: 'https://chatapp-backend-0kxr.onrender.com',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  final Dio dio;
  final StorageService _storageService;
  Future<void> Function()? _unauthorizedHandler;
  bool _isHandlingUnauthorized = false;

  void setUnauthorizedHandler(Future<void> Function() handler) {
    _unauthorizedHandler = handler;
  }

  void setAuthHeader(String token) {
    dio.options.headers['authorization'] = 'Bearer $token';
  }

  void clearAuthHeader() {
    dio.options.headers.remove('authorization');
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = _storageService.getToken();
    if (token != null && token.isNotEmpty) {
      if (JwtUtils.isExpired(token)) {
        await _handleUnauthorized();
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Session expired. Please sign in again.',
          ),
        );
        return;
      }
      options.headers['authorization'] = 'Bearer $token';
      dio.options.headers['authorization'] = 'Bearer $token';
    } else {
      options.headers.remove('authorization');
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (_shouldForceLogout(error)) {
      await _handleUnauthorized();
    }
    handler.next(error);
  }

  bool _shouldForceLogout(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401) return true;

    final responseData = error.response?.data;
    final responseText = responseData?.toString().toLowerCase() ?? '';
    final messageText = (error.message ?? '').toLowerCase();

    return responseText.contains('token expired') ||
        responseText.contains('jwt expired') ||
        messageText.contains('token expired') ||
        messageText.contains('jwt expired');
  }

  Future<void> _handleUnauthorized() async {
    if (_isHandlingUnauthorized) return;
    final handler = _unauthorizedHandler;
    if (handler == null) return;

    _isHandlingUnauthorized = true;
    try {
      await handler();
    } finally {
      _isHandlingUnauthorized = false;
    }
  }
}
