import 'package:connectrpc/connect.dart' as connect;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Auth interceptor for Connect RPC
/// TODO: Implement proper interceptor when Connect adds support
class AuthInterceptor {
  final FlutterSecureStorage _storage;

  AuthInterceptor(this._storage);

  Future<connect.Headers> getAuthHeaders() async {
    final headers = connect.Headers();
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
