import 'package:connectrpc/connectrpc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;

  AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(Request request) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
  }
}
