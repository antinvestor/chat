import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/logging/app_logger.dart';
import 'auth_repository.dart';

part 'auth_state_provider.g.dart';

/// Authentication state
enum AuthState { authenticated, unauthenticated, loading }

/// Authentication state notifier that watches auth status
@riverpod
class AuthStateNotifier extends _$AuthStateNotifier {
  @override
  Future<AuthState> build() async {
    final authRepo = ref.watch(authRepositoryProvider);
    final isLoggedIn = await authRepo.isLoggedIn();

    if (isLoggedIn) {
      // Check if token needs refresh
      final isExpired = await authRepo.isTokenExpired();
      if (isExpired) {
        // Try to refresh token
        try {
          AppLogger.debug('Token expired on app start, attempting refresh');
          await authRepo.refreshToken();
          AppLogger.info('Authentication state: authenticated (after refresh)');
          return AuthState.authenticated;
        } catch (e, stackTrace) {
          AppLogger.error(
            'Token refresh failed on app start',
            error: e,
            stackTrace: stackTrace,
          );
          AppLogger.info(
            'Authentication state: unauthenticated (refresh failed)',
          );
          // If refresh fails, user needs to login again
          return AuthState.unauthenticated;
        }
      }
      AppLogger.info('Authentication state: authenticated');
      return AuthState.authenticated;
    }

    AppLogger.info('Authentication state: unauthenticated');
    return AuthState.unauthenticated;
  }

  /// Trigger login
  Future<void> login() async {
    state = const AsyncValue.loading();

    try {
      AppLogger.info('Login initiated');
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.login();

      // Check if provider is still mounted after async operation
      if (!ref.mounted) return;

      state = const AsyncValue.data(AuthState.authenticated);
      AppLogger.info('Login successful, state changed to authenticated');
    } catch (e, stack) {
      AppLogger.error('Login failed', error: e, stackTrace: stack);

      // Always set error state and rethrow first
      // Only skip state update if already unmounted (to avoid Riverpod error)
      // but still rethrow so UI can handle it
      if (ref.mounted) {
        state = AsyncValue.error(e, stack);
      }
      rethrow;
    }
  }

  /// Trigger logout
  Future<void> logout() async {
    state = const AsyncValue.loading();

    try {
      AppLogger.info('Logout initiated');
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.logout();

      // Check if provider is still mounted after async operation
      if (!ref.mounted) return;

      state = const AsyncValue.data(AuthState.unauthenticated);
      AppLogger.info('Logout successful, state changed to unauthenticated');
    } catch (e, stack) {
      AppLogger.error('Logout failed', error: e, stackTrace: stack);

      // Only set error state if still mounted (to avoid Riverpod error)
      if (ref.mounted) {
        state = AsyncValue.error(e, stack);
      }
    }
  }

  /// Refresh authentication state
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final authRepo = ref.read(authRepositoryProvider);
      final isLoggedIn = await authRepo.isLoggedIn();

      if (isLoggedIn) {
        return AuthState.authenticated;
      }
      return AuthState.unauthenticated;
    });
  }
}
