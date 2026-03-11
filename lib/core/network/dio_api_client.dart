import 'package:dio/dio.dart';

class DioApiClient {
  DioApiClient()
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
        )..interceptors.add(
            LogInterceptor(
              requestBody: true,
              responseBody: true,
            ),
          );

  final Dio dio;
}

