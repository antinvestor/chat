import 'package:antinvestor_api_common/antinvestor_api_common.dart' show TokenRefreshResult;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_service.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final AuthService _authService;

  AuthRepository(this._authService);

  Future<void> login() async {
    final token = await _authService.authenticate();
    if (token == null) {
      // On IO platforms, authenticate() should always return a token
      // On web, it might return null due to redirect flow
      throw Exception('Authentication did not return a token');
    }
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
  
  /// Refresh token with detailed result information
  /// Returns result type, token if successful, and error message if failed
  Future<({TokenRefreshResult result, dynamic token, String? error})> refreshTokenWithResult() async {
    return await _authService.refreshTokenWithResult();
  }
  
  /// Get the time until a token refresh is needed
  /// Returns null if no expiry info available
  Future<Duration?> getTimeUntilRefreshNeeded() async {
    return await _authService.getTimeUntilRefreshNeeded();
  }
  
  /// Get the token expiry time
  Future<DateTime?> getTokenExpiryTime() async {
    return await _authService.getTokenExpiryTime();
  }

  Future<Map<String, dynamic>?> getUserInfo() async {
    return await _authService.getUserInfo();
  }

  Future<String?> getAccessToken() async {
    return await _authService.getAccessToken();
  }

  /// Ensure we have a valid access token, refreshing if necessary
  /// Returns the access token if successful, null if user needs to re-login
  Future<String?> ensureValidAccessToken() async {
    return await _authService.ensureValidAccessToken();
  }
  
  /// Ensure valid access token with detailed status
  /// Returns token and whether re-login is needed
  Future<({String? token, bool needsRelogin})> ensureValidAccessTokenWithStatus({
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    return await _authService.ensureValidAccessTokenWithStatus(
      maxRetries: maxRetries,
      retryDelay: retryDelay,
    );
  }

  /// Check if we have a valid, usable access token right now
  Future<bool> hasValidAccessToken() async {
    return await _authService.hasValidAccessToken();
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
