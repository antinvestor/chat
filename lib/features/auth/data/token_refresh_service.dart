import 'dart:async';

import 'package:antinvestor_api_common/antinvestor_api_common.dart'
    show TokenRefreshResult;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/token_refresh_lock.dart';
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
/// - Connectivity awareness: Doesn't count failures when offline
/// - TokenManager sync: Updates TokenManager's in-memory cache after refresh
///
/// IMPORTANT: This service is designed to minimize re-login requirements.
/// Users should only need to re-login when:
/// 1. The refresh token is explicitly revoked by the server
/// 2. The refresh token expires (typically months/years)
/// 3. The user explicitly logs out
///
/// Network issues, server errors, and other transient failures will NOT
/// cause logout - the service will keep retrying indefinitely.
class TokenRefreshService {
  TokenRefreshService(
    this._authRepository,
    this._onLogoutNeeded, {
    Future<void> Function(String token)? onTokenRefreshed,
    TokenRefreshLock? tokenRefreshLock,
  }) : _onTokenRefreshed = onTokenRefreshed,
       _tokenRefreshLock = tokenRefreshLock;
  final AuthRepository _authRepository;
  final Future<void> Function() _onLogoutNeeded;
  final Future<void> Function(String token)? _onTokenRefreshed;
  final TokenRefreshLock? _tokenRefreshLock;
  Timer? _refreshTimer;
  Timer? _scheduledRefreshTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isRefreshing = false;
  int _consecutiveFailures = 0;
  bool _isWaitingForConnectivity = false;

  // Configuration
  // Note: We use a high failure threshold because transient errors should
  // never cause logout - only permanent OAuth errors should.
  static const _maxConsecutiveFailures = 10;
  static const _baseRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(minutes: 5);
  static const _fallbackCheckInterval = Duration(seconds: 30);
  // After this many failures, we'll wait for connectivity before retrying
  static const _waitForConnectivityThreshold = 3;

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

    // Listen for connectivity changes to retry when coming back online
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
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
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isRefreshing = false;
    _consecutiveFailures = 0;
    _isWaitingForConnectivity = false;
    AppLogger.debug('Token refresh service stopped');
  }

  /// Handle connectivity changes - retry when coming back online
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );

    if (hasConnection && _isWaitingForConnectivity) {
      AppLogger.info(
        'Connectivity restored, resuming token refresh',
        data: {'previousFailures': _consecutiveFailures},
      );
      _isWaitingForConnectivity = false;
      // Reset failure counter when connectivity returns
      // This gives the user a fresh set of retry attempts
      _consecutiveFailures = 0;
      _checkAndRefreshIfNeeded();
    }
  }

  /// Schedule the next refresh based on token expiry time
  Future<void> _scheduleNextRefresh() async {
    _scheduledRefreshTimer?.cancel();

    try {
      final timeUntilRefresh = await _authRepository
          .getTimeUntilRefreshNeeded();

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
      AppLogger.info(
        'Scheduled proactive token refresh',
        data: {
          'inSeconds': timeUntilRefresh.inSeconds,
          'inMinutes': timeUntilRefresh.inMinutes,
        },
      );

      _scheduledRefreshTimer = Timer(
        timeUntilRefresh,
        _checkAndRefreshIfNeeded,
      );
    } catch (e) {
      AppLogger.warning(
        'Failed to schedule token refresh',
        data: {'error': e.toString()},
      );
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
        AppLogger.debug(
          'Profile not logged in, stopping token refresh service',
        );
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
    // Use shared lock if available to prevent concurrent refreshes
    final lock = _tokenRefreshLock;
    if (lock != null) {
      final lockResult = await lock.acquireAndRefresh(() async {
        return _authRepository.refreshTokenWithResult();
      });

      // If lockResult is null, another refresh was in progress
      if (lockResult == null) {
        AppLogger.debug(
          'Token refresh was handled by another caller (SyncEngine)',
        );
        _consecutiveFailures = 0;
        await _scheduleNextRefresh();
        return;
      }

      await _handleRefreshResult(lockResult);
      return;
    }

    // No lock available, proceed normally
    final result = await _authRepository.refreshTokenWithResult();
    await _handleRefreshResult(result);
  }

  /// Handle the result of a token refresh operation
  Future<void> _handleRefreshResult(
    ({TokenRefreshResult result, dynamic token, String? error}) result,
  ) async {
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

        // After several failures, check connectivity before continuing
        if (_consecutiveFailures >= _waitForConnectivityThreshold) {
          final connectivity = await Connectivity().checkConnectivity();
          final hasConnection = connectivity.any(
            (r) =>
                r == ConnectivityResult.wifi ||
                r == ConnectivityResult.mobile ||
                r == ConnectivityResult.ethernet,
          );

          if (!hasConnection) {
            // No connectivity - wait for it to return instead of retrying
            AppLogger.info(
              'No connectivity detected, waiting for network to resume',
              data: {'consecutiveFailures': _consecutiveFailures},
            );
            _isWaitingForConnectivity = true;
            // Don't schedule retry - connectivity listener will trigger it
            return;
          }
        }

        // Even with max failures, we DON'T logout on transient errors
        // The user has valid credentials, just network/server issues
        if (_consecutiveFailures >= _maxConsecutiveFailures) {
          AppLogger.warning(
            'Many consecutive refresh failures, but keeping session active',
            data: {
              'failures': _consecutiveFailures,
              'action': 'Will keep retrying with longer delays',
            },
          );
          // Don't logout - just use max delay and keep trying
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
        _scheduledRefreshTimer = Timer(retryDelay, _checkAndRefreshIfNeeded);
        break;
    }
  }

  /// Calculate retry delay with exponential backoff and jitter
  Duration _calculateRetryDelay(int failureCount) {
    // Exponential backoff: 5s, 10s, 20s, 40s, 80s (capped at 2 min)
    final exponentialDelay = _baseRetryDelay * (1 << (failureCount - 1));
    final cappedDelay = exponentialDelay > _maxRetryDelay
        ? _maxRetryDelay
        : exponentialDelay;

    // Add jitter (±20%) to prevent thundering herd
    final jitterMs =
        (cappedDelay.inMilliseconds *
                0.2 *
                (DateTime.now().millisecond / 500 - 1))
            .toInt();

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
  final tokenRefreshLock = ref.watch(tokenRefreshLockProvider);

  // Create service with logout callback, TokenManager sync, and shared lock
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
    tokenRefreshLock: tokenRefreshLock,
    onTokenRefreshed: (String newToken) async {
      // Update TokenManager's in-memory cache so Connect RPC clients use the new token
      await tokenManager.setAccessToken(newToken);
      AppLogger.debug(
        'TokenManager in-memory cache updated after background refresh',
      );
    },
  );

  // Cleanup when provider is disposed
  ref.onDispose(service.stop);

  return service;
}
