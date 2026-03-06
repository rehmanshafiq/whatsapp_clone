import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GifService {
  final Dio _dio;

  GifService({Dio? dio}) : _dio = dio ?? Dio() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'https://api.whatsapp-clone.mock/v1';
    _dio.options.baseUrl = baseUrl;
  }

  Future<List<String>> getTrendingGifs({int offset = 0, int limit = 20}) async {
    try {
      // In a real Klippy API integration, this would be the actual endpoint
      // e.g., final response = await _dio.get('/gifs/trending', queryParameters: {'offset': offset, 'limit': limit});
      
      // Since this is a mock environment, we return a list of dummy GIF URLs
      await Future.delayed(const Duration(milliseconds: 800));
      return List.generate(
        limit,
        (index) => 'https://media0.giphy.com/media/v1.Y2lkPTc5MGI3NjExc29teWZobmE1d211ajJtZWxkNGY2YmRxZjJxcWwxdndxeDNpdnR2diZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/3o7TKSjRrfIPjeiVyM/giphy.gif',
      );
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> searchGifs(String query, {int offset = 0, int limit = 20}) async {
    try {
      // final response = await _dio.get('/gifs/search', queryParameters: {'q': query, 'offset': offset, 'limit': limit});
      
      await Future.delayed(const Duration(milliseconds: 800));
      // Return a different dummy GIF for search
      return List.generate(
        limit,
        (index) => 'https://media1.giphy.com/media/v1.Y2lkPTc5MGI3NjExdW9tYndoeGJvYW90YXFwcWZxdW1xaDVyeGZzZWJqdHRrMm5xbHB2eCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/l41lFw057lAJQMwg0/giphy.gif',
      );
    } catch (e) {
      return [];
    }
  }
}
