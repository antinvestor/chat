import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final AuthService _authService;

  AuthRepository(this._authService);

  Future<void> login() async {
    await _authService.authenticate();
  }

  Future<void> logout() async {
    await _authService.logout();
  }

  Future<bool> isLoggedIn() async {
    final token = await _authService.getAccessToken();
    return token != null;
  }
}

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  // TODO: Move config to environment variables
  const issuerUrl = 'https://auth.antinvestor.com'; 
  const clientId = 'chat_app';
  
  const storage = FlutterSecureStorage();
  final authService = AuthService(storage, issuerUrl: issuerUrl, clientId: clientId);
  
  return AuthRepository(authService);
}
