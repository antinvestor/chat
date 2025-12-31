import 'dart:async';

import 'package:antinvestor_api_common/antinvestor_api_common.dart' show TokenRefreshResult;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';
import 'auth_repository.dart';
import 'auth_state_provider.dart';

part 'token_refresh_service.g.dart';

/// Service that handles automatic token refresh in the background
/// 
/// This service implements a robust token refresh strategy:
/// - Proactive refresh: Refreshes tokens before they expire (5 min buffer)
/// - Smart scheduling: Schedules next refresh based on token expiry time
/// - Retry with backoff: Retries transient failures with exponential backoff
/// - Graceful degradation: Only logs out on permanent errors
/// - TokenManager sync: Updates TokenManager's in-memory cache after refresh
class TokenRefreshService {
  final AuthRepository _authRepository;
  final Future<void> Function() _onLogoutNeeded;
  final Future<void> Function(String token)? _onTokenRefreshed;
  Timer? _refreshTimer;
  Timer? _scheduledRefreshTimer;
  bool _isRefreshing = false;
  int _consecutiveFailures = 0;
  
  // Configuration
  static const _maxConsecutiveFailures = 5;
  static const _baseRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(minutes: 2);
  static const _fallbackCheckInterval = Duration(seconds: 30);

  TokenRefreshService(
    this._authRepository, 
    this._onLogoutNeeded, {
    Future<void> Function(String token)? onTokenRefreshed,
  }) : _onTokenRefreshed = onTokenRefreshed;

  /// Start the token refresh service
  /// Uses smart scheduling based on token expiry time
  void start() {
    stop(); // Cancel any existing timers

    AppLogger.info('Token refresh service started');

    // Schedule based on token expiry, with fallback periodic check
    _scheduleNextRefresh();
    
    // Fallback: periodic check every 30 seconds for edge cases
    _refreshTimer = Timer.periodic(
      _fallbackCheckInterval,
      (_) => _checkAndRefreshIfNeeded(),
    );

    // Also check immediately on start
    _checkAndRefreshIfNeeded();
  }

  /// Stop the token refresh service
  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _scheduledRefreshTimer?.cancel();
    _scheduledRefreshTimer = null;
    _isRefreshing = false;
    _consecutiveFailures = 0;
    AppLogger.debug('Token refresh service stopped');
  }

  /// Schedule the next refresh based on token expiry time
  Future<void> _scheduleNextRefresh() async {
    _scheduledRefreshTimer?.cancel();
    
    try {
      final timeUntilRefresh = await _authRepository.getTimeUntilRefreshNeeded();
      
      if (timeUntilRefresh == null) {
        // No expiry info, rely on fallback periodic check
        AppLogger.debug('No token expiry info, relying on fallback check');
        return;
      }
      
      if (timeUntilRefresh <= Duration.zero) {
        // Need to refresh now
        AppLogger.debug('Token refresh needed immediately');
        _checkAndRefreshIfNeeded();
        return;
      }
      
      // Schedule refresh for when token is about to expire
      AppLogger.info('Scheduled proactive token refresh', data: {
        'inSeconds': timeUntilRefresh.inSeconds,
        'inMinutes': timeUntilRefresh.inMinutes,
      });
      
      _scheduledRefreshTimer = Timer(timeUntilRefresh, () {
        _checkAndRefreshIfNeeded();
      });
    } catch (e) {
      AppLogger.warning('Failed to schedule token refresh', data: {'error': e.toString()});
    }
  }

  /// Check if token needs refresh and refresh if needed
  Future<void> _checkAndRefreshIfNeeded() async {
    // Prevent concurrent refresh attempts
    if (_isRefreshing) {
      return;
    }

    try {
      _isRefreshing = true;

      final isLoggedIn = await _authRepository.isLoggedIn();
      if (!isLoggedIn) {
        AppLogger.debug('User not logged in, stopping token refresh service');
        stop();
        return;
      }

      final isExpired = await _authRepository.isTokenExpired();
      if (!isExpired) {
        // Token is still valid, reschedule
        await _scheduleNextRefresh();
        return;
      }

      AppLogger.info('Token expired or about to expire, refreshing...');
      await _performRefreshWithRetry();
      
    } finally {
      _isRefreshing = false;
    }
  }

  /// Perform token refresh with retry logic for transient errors
  Future<void> _performRefreshWithRetry() async {
    final result = await _authRepository.refreshTokenWithResult();
    
    switch (result.result) {
      case TokenRefreshResult.success:
        _consecutiveFailures = 0;
        AppLogger.info('Background token refresh successful');
        
        // Update TokenManager's in-memory cache so Connect RPC clients use the new token
        if (_onTokenRefreshed != null) {
          final newToken = await _authRepository.getAccessToken();
          if (newToken != null) {
            await _onTokenRefreshed(newToken);
            AppLogger.debug('TokenManager updated with new token');
          }
        }
        
        // Schedule next refresh based on new token expiry
        await _scheduleNextRefresh();
        break;
        
      case TokenRefreshResult.permanentError:
        AppLogger.error(
          'Token refresh failed permanently - forcing re-login',
          data: {
            'error': result.error,
            'action': 'User will be redirected to login screen',
          },
        );
        await _onLogoutNeeded();
        stop();
        break;
        
      case TokenRefreshResult.transientError:
        _consecutiveFailures++;
        
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          AppLogger.error(
            'Max consecutive refresh failures reached, prompting re-login',
            data: {'failures': _consecutiveFailures},
          );
          await _onLogoutNeeded();
          stop();
          return;
        }
        
        // Calculate retry delay with exponential backoff
        final retryDelay = _calculateRetryDelay(_consecutiveFailures);
        AppLogger.warning(
          'Transient refresh error, will retry',
          data: {
            'consecutiveFailures': _consecutiveFailures,
            'retryInSeconds': retryDelay.inSeconds,
            'error': result.error,
          },
        );
        
        // Schedule retry
        _scheduledRefreshTimer?.cancel();
        _scheduledRefreshTimer = Timer(retryDelay, () {
          _checkAndRefreshIfNeeded();
        });
        break;
    }
  }

  /// Calculate retry delay with exponential backoff and jitter
  Duration _calculateRetryDelay(int failureCount) {
    // Exponential backoff: 5s, 10s, 20s, 40s, 80s (capped at 2 min)
    final exponentialDelay = _baseRetryDelay * (1 << (failureCount - 1));
    final cappedDelay = exponentialDelay > _maxRetryDelay ? _maxRetryDelay : exponentialDelay;
    
    // Add jitter (±20%) to prevent thundering herd
    final jitterMs = (cappedDelay.inMilliseconds * 0.2 * (DateTime.now().millisecond / 500 - 1)).toInt();
    
    return Duration(milliseconds: cappedDelay.inMilliseconds + jitterMs);
  }

  /// Manually trigger a token refresh
  Future<void> refreshNow() async {
    _consecutiveFailures = 0; // Reset on manual refresh
    await _checkAndRefreshIfNeeded();
  }
  
  /// Get current health status
  ({bool isHealthy, int consecutiveFailures}) get healthStatus => (
    isHealthy: _consecutiveFailures < _maxConsecutiveFailures,
    consecutiveFailures: _consecutiveFailures,
  );
}

/// Provider for the token refresh service
@riverpod
TokenRefreshService tokenRefreshService(Ref ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final tokenManager = ref.watch(tokenManagerProvider);

  // Create service with logout callback and TokenManager sync
  final service = TokenRefreshService(
    authRepository, 
    () async {
      AppLogger.warning('Token refresh service triggering re-login flow');
      
      // Logout by clearing tokens
      await authRepository.logout();
      
      // Invalidate the auth state notifier to trigger UI update
      // This ensures the user sees the login screen instead of hanging
      ref.invalidate(authStateProvider);
      
      AppLogger.info('Auth state invalidated - user should see login screen');
    },
    onTokenRefreshed: (String newToken) async {
      // Update TokenManager's in-memory cache so Connect RPC clients use the new token
      await tokenManager.setAccessToken(newToken);
      AppLogger.debug('TokenManager in-memory cache updated after background refresh');
    },
  );

  // Cleanup when provider is disposed
  ref.onDispose(() {
    service.stop();
  });

  return service;
}
