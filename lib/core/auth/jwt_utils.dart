import 'dart:convert';

class JwtUtils {
  const JwtUtils._();

  static Map<String, dynamic>? decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is! Map<String, dynamic>) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  static DateTime? expirationFromToken(String token) {
    final payload = decodePayload(token);
    if (payload == null) return null;
    final exp = payload['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    }
    if (exp is String) {
      final seconds = int.tryParse(exp);
      if (seconds == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    }
    return null;
  }

  static bool isExpired(String token, {DateTime? nowUtc}) {
    final expiration = expirationFromToken(token);
    if (expiration == null) return true;
    final now = nowUtc ?? DateTime.now().toUtc();
    return !expiration.isAfter(now);
  }
}
