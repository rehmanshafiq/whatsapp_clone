import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StickerService {
  final Dio _dio;

  StickerService({Dio? dio}) : _dio = dio ?? Dio() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'https://api.whatsapp-clone.mock/v1';
    _dio.options.baseUrl = baseUrl;
  }

  Future<List<String>> getTrendingStickers({int offset = 0, int limit = 20}) async {
    try {
      // In a real Klippy API integration, this would be the actual endpoint
      // e.g., final response = await _dio.get('/stickers/trending', queryParameters: {'offset': offset, 'limit': limit});
      
      await Future.delayed(const Duration(milliseconds: 800));
      // Dummy sticker URLs
      return List.generate(
        limit,
        (index) => 'https://media2.giphy.com/media/v1.Y2lkPTc5MGI3NjExcHJsdGRwb3MwODU1Y3psamY0amZ0anMxdXR6ZmxkZjVlbnkwcmhtMyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9cw/l4pTfx2qLszoacZRS/giphy.gif',
      );
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> searchStickers(String query, {int offset = 0, int limit = 20}) async {
    try {
      // final response = await _dio.get('/stickers/search', queryParameters: {'q': query, 'offset': offset, 'limit': limit});
      
      await Future.delayed(const Duration(milliseconds: 800));
      // Dummy search sticker URLs
      return List.generate(
        limit,
        (index) => 'https://media1.giphy.com/media/v1.Y2lkPTc5MGI3NjExMjRteHlzZDgyaXYyYzcwNWw4YW9qOTdrdXVyNDIzMzYxZG0xbHNubSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9cw/3o7TKsy4E4A1Z7sFjy/giphy.gif',
      );
    } catch (e) {
      return [];
    }
  }
}
