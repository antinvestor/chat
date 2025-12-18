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
    return await _authService.isAuthenticated();
  }

  Future<bool> isTokenExpired() async {
    return await _authService.isTokenExpired();
  }

  Future<void> refreshToken() async {
    await _authService.refreshToken();
  }

  Future<Map<String, dynamic>?> getUserInfo() async {
    return await _authService.getUserInfo();
  }

  Future<String?> getAccessToken() async {
    return await _authService.getAccessToken();
  }
}

@riverpod
AuthRepository authRepository(Ref ref) {
  // Use centralized API config for OAuth2 settings
  const issuerUrl = 'https://oauth2.antinvestor.com';
  const clientId = '9bsv0s0hijjg02qk7l1g';

  const storage = FlutterSecureStorage();
  final authService = AuthService(
    storage,
    issuerUrl: issuerUrl,
    clientId: clientId,
  );

  return AuthRepository(authService);
}
