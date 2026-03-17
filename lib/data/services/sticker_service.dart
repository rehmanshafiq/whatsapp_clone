import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StickerService {
  final Dio _dio;

  static const String _appKey = 'jcVWfs4rnAtZ6POPNb3i5VyMKbGGgcY0WUnJaSXEBQ0XmUVtQDnsuJkm5SNeY12Z';
  static const String _baseUrl = 'https://api.klipy.com/api/v1/$_appKey';

  StickerService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _baseUrl;
  }

  Future<List<String>> getTrendingStickers({int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get('/stickers/trending', queryParameters: {
        'page': page,
        'per_page': limit,
      });
      
      if (response.data['result'] == true && response.data['data'] != null) {
        final List<dynamic> items = response.data['data']['data'] ?? [];
        return items
            .map((item) => item['file']?['md']?['gif']?['url'] as String?)
            .whereType<String>()
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching trending stickers: $e');
      return [];
    }
  }

  Future<List<String>> searchStickers(String query, {int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get('/stickers/search', queryParameters: {
        'q': query,
        'page': page,
        'per_page': limit,
      });
      
      if (response.data['result'] == true && response.data['data'] != null) {
        final List<dynamic> items = response.data['data']['data'] ?? [];
        return items
            .map((item) => item['file']?['md']?['gif']?['url'] as String?)
            .whereType<String>()
            .toList();
      }
      return [];
    } catch (e) {
      print('Error searching stickers: $e');
      return [];
    }
  }
}
