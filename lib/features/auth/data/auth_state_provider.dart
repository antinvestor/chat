import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import '../../onboarding/data/onboarding_repository.dart';
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
      // Ensure we have a valid access token (will refresh if expired)
      final token = await authRepo.ensureValidAccessToken();
      
      if (token != null) {
        AppLogger.info('Authentication state: authenticated');
        return AuthState.authenticated;
      }
      
      // Token refresh failed, user needs to login again
      AppLogger.info('Authentication state: unauthenticated (no valid token)');
      return AuthState.unauthenticated;
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
      
      // Perform authentication
      await authRepo.login();

      // Check if provider is still mounted after async operation
      if (!ref.mounted) return;

      // Verify authentication was successful by checking if we have a token
      final isLoggedIn = await authRepo.isLoggedIn();
      if (!isLoggedIn) {
        AppLogger.warning('Login completed but no token found');
        state = const AsyncValue.data(AuthState.unauthenticated);
        return;
      }

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
      final onboardingRepo = ref.read(onboardingRepositoryProvider);
      
      await authRepo.logout();
      await onboardingRepo.reset(); // Clear onboarding state for next login

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
