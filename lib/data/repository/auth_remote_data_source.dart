import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  static const String _baseUrl = 'https://chatapp-backend-0kxr.onrender.com';
  static const String _apiKey = 'chatapp-test-key';

  Future<void> register({
    required String username,
    required String password,
    required String displayName,
    required String? avatarUrl,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/api/v1/app/users',
        data: <String, dynamic>{
          'username': username,
          'password': password,
          'display_name': displayName,
          'avatar_url': avatarUrl,
        },
        options: Options(
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'x-api-key': _apiKey,
          },
        ),
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to register. Please try again.';

      if (statusCode == 400 || statusCode == 409) {
        message = 'User already exists. Please choose a different username.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and try again.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '$_baseUrl/api/v1/auth/login',
        data: <String, dynamic>{
          'username': username,
          'password': password,
        },
        options: Options(
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'x-api-key': _apiKey,
          },
        ),
      );

      final dynamic raw = response.data;
      Map<String, dynamic> data;

      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is String) {
        data = json.decode(raw) as Map<String, dynamic>;
      } else {
        throw const ApiException(
          message: 'Invalid login response from server.',
        );
      }

      if (!data.containsKey('token') || !data.containsKey('user_id')) {
        throw const ApiException(
          message: 'Invalid login response from server.',
        );
      }

      return data;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      String message = 'Failed to sign in. Please try again.';

      if (statusCode == 400 || statusCode == 401) {
        message = 'Invalid credentials. Please check your username and password.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        message = 'Network error. Please check your connection and try again.';
      }

      throw ApiException(message: message, statusCode: statusCode);
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }
}

