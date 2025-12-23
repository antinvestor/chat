import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import 'auth_repository.dart';

part 'token_refresh_service.g.dart';

/// Service that handles automatic token refresh in the background
class TokenRefreshService {
  final AuthRepository _authRepository;
  final Future<void> Function() _onLogoutNeeded;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  TokenRefreshService(this._authRepository, this._onLogoutNeeded);

  /// Start the token refresh service
  /// Checks token expiry every 60 seconds
  void start() {
    stop(); // Cancel any existing timer

    AppLogger.info('Token refresh service started (checking every 60s)');

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _checkAndRefreshToken(),
    );

    // Also check immediately on start
    _checkAndRefreshToken();
  }

  /// Stop the token refresh service
  void stop() {
    AppLogger.info('Token refresh service stopped');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _isRefreshing = false;
  }

  /// Check if token is expired and refresh if needed
  Future<void> _checkAndRefreshToken() async {
    // Prevent concurrent refresh attempts
    if (_isRefreshing) {
      return;
    }

    try {
      _isRefreshing = true;

      final isLoggedIn = await _authRepository.isLoggedIn();
      if (!isLoggedIn) {
        // User is not logged in, stop the service
        AppLogger.debug('User not logged in, stopping token refresh service');
        stop();
        return;
      }

      final isExpired = await _authRepository.isTokenExpired();
      if (isExpired) {
        AppLogger.info('Token expired or about to expire, refreshing...');

        try {
          await _authRepository.refreshToken();
          AppLogger.info('Background token refresh successful');
        } catch (e, stackTrace) {
          AppLogger.error(
            'Background token refresh failed, logging out user',
            error: e,
            stackTrace: stackTrace,
          );

          // If refresh fails, logout the user
          await _onLogoutNeeded();
          stop();
        }
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Manually trigger a token refresh
  Future<void> refreshNow() async {
    await _checkAndRefreshToken();
  }
}

/// Provider for the token refresh service
@riverpod
TokenRefreshService tokenRefreshService(Ref ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  // Create service with logout callback
  final service = TokenRefreshService(authRepository, () async {
    // Logout by clearing tokens
    await authRepository.logout();
  });

  // Cleanup when provider is disposed
  ref.onDispose(() {
    service.stop();
  });

  return service;
}
