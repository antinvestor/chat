import 'package:connectrpc/connect.dart' as connect;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';

/// Auth interceptor for Connect RPC
/// Provides JWT authorization headers for all API calls
class AuthInterceptor {
  final FlutterSecureStorage _storage;
  String? _cachedToken;
  DateTime? _cacheTime;
  static const _cacheValidDuration = Duration(seconds: 30);

  AuthInterceptor(this._storage);

  /// Get auth headers with token caching for performance
  /// Caches token for 30 seconds to reduce secure storage reads
  Future<connect.Headers> getAuthHeaders() async {
    final headers = connect.Headers();
    
    // Check if cached token is still valid
    final now = DateTime.now();
    if (_cachedToken != null && 
        _cacheTime != null && 
        now.difference(_cacheTime!) < _cacheValidDuration) {
      headers['Authorization'] = 'Bearer $_cachedToken';
      return headers;
    }
    
    // Read fresh token
    final token = await _storage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      _cachedToken = token;
      _cacheTime = now;
      headers['Authorization'] = 'Bearer $token';
      AppLogger.debug('Auth headers refreshed');
    }
    return headers;
  }

  /// Invalidate the cached token (call after logout or token refresh)
  void invalidateCache() {
    _cachedToken = null;
    _cacheTime = null;
  }
}
