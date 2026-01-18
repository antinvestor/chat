import 'package:flutter/widgets.dart';

import 'package:antinvestor_api_common/antinvestor_api_common.dart'
    show TokenRefreshResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openid_client/openid_client.dart' show TokenResponse;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chat/features/auth/data/auth_repository.dart';
import 'package:chat/features/auth/data/auth_service.dart';

/// Mock AuthService for testing
class MockAuthService extends AuthService {
  bool _isAuthenticated = false;
  bool _shouldThrowError = false;

  MockAuthService()
    : super(
        const FlutterSecureStorage(),
        issuerUrl: 'https://mock-oauth.com',
        clientId: 'mock-client-id',
      );

  void setAuthenticated(bool authenticated) {
    _isAuthenticated = authenticated;
  }

  void setShouldThrowError(bool shouldThrow) {
    _shouldThrowError = shouldThrow;
  }

  @override
  Future<bool> isAuthenticated() async {
    if (_shouldThrowError) {
      throw Exception('Mock authentication error');
    }
    return _isAuthenticated;
  }

  @override
  Future<void> logout() async {
    _isAuthenticated = false;
  }

  @override
  Future<bool> isTokenExpired({
    Duration buffer = const Duration(minutes: 2),
  }) async {
    return false; // Mock token never expires
  }

  @override
  Future<TokenResponse?> refreshToken() async {
    // Mock refresh - no network calls, return null for simplicity
    return _isAuthenticated ? null : null;
  }

  @override
  Future<({TokenRefreshResult result, TokenResponse? token, String? error})>
  refreshTokenWithResult() async {
    return (
      result: TokenRefreshResult.success,
      token: _isAuthenticated ? null : null,
      error: null,
    );
  }

  @override
  Future<Duration?> getTimeUntilRefreshNeeded() async {
    return const Duration(hours: 1); // Mock 1 hour until refresh
  }

  @override
  Future<bool> hasValidAccessToken() async {
    return _isAuthenticated;
  }

  @override
  Future<({String? token, bool needsRelogin})>
  ensureValidAccessTokenWithStatus({
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    if (_shouldThrowError) {
      return (token: null, needsRelogin: true);
    }
    return (token: _isAuthenticated ? 'mock-token' : null, needsRelogin: false);
  }

  Future<String?> getCurrentProfileId() async {
    return _isAuthenticated ? 'mock-profile-id' : null;
  }
}

/// Mock AuthRepository for testing
class MockAuthRepository extends AuthRepository {
  final MockAuthService _mockAuthService;

  MockAuthRepository(this._mockAuthService) : super(_mockAuthService);

  void setAuthenticated(bool authenticated) {
    _mockAuthService.setAuthenticated(authenticated);
  }

  void setShouldThrowError(bool shouldThrow) {
    _mockAuthService.setShouldThrowError(shouldThrow);
  }
}

/// Provider overrides for testing
class TestHelpers {
  static final mockAuthService = MockAuthService();
  static final mockAuthRepository = MockAuthRepository(mockAuthService);

  static List<Override> get overrides => [
    authRepositoryProvider.overrideWithValue(mockAuthRepository),
    // Add other provider overrides as needed
  ];

  static void resetMocks() {
    mockAuthService.setAuthenticated(false);
    mockAuthService.setShouldThrowError(false);
  }

  static void setAuthenticated(bool authenticated) {
    mockAuthService.setAuthenticated(authenticated);
  }

  static void setShouldThrowAuthError(bool shouldThrow) {
    mockAuthService.setShouldThrowError(shouldThrow);
  }
}

/// Extension to make it easier to create ProviderScope with mocks in tests
extension ProviderScopeTest on WidgetTester {
  Future<void> pumpWidgetWithMocks(Widget child) async {
    await pumpWidget(
      ProviderScope(overrides: TestHelpers.overrides, child: child),
    );
  }
}
