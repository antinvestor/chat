/// API Client providers and transport configuration
///
/// This module provides Riverpod providers for all API clients used
/// in the application, including authentication, token management,
/// and service-specific clients.
library;

import 'package:antinvestor_api_chat/antinvestor_api_chat.dart';
import 'package:antinvestor_api_common/antinvestor_api_common.dart';
import 'package:antinvestor_api_device/antinvestor_api_device.dart';
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart';
import 'package:connectrpc/connect.dart' as connect;
import 'package:connectrpc/io.dart' as connect_io;
import 'package:connectrpc/protobuf.dart' as connect_protobuf;
import 'package:connectrpc/protocol/connect.dart' as connect_protocol;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/data/auth_repository.dart';
import '../auth/token_refresh_lock.dart';
import '../logging/app_logger.dart';
import 'certificate_pinning.dart';

/// Secure storage provider for token access
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// Token manager provider using antinvestor_api_common TokenManager
///
/// TokenManager handles:
/// - Persistent storage of tokens
/// - Reactive refresh on 401 (via interceptor)
/// - Concurrent refresh prevention
/// - Logout on permanent errors
///
/// CRITICAL: The onRefreshToken callback uses TokenRefreshLock to prevent
/// race conditions with TokenRefreshService and SyncEngine. Without this,
/// multiple concurrent refresh attempts could reuse the same refresh token,
/// causing the OAuth2 server to revoke all tokens.
final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  final tokenRefreshLock = ref.watch(tokenRefreshLockProvider);

  final tokenManager = TokenManager(
    persistTokens: (accessToken, refreshToken) async {
      if (accessToken != null) {
        await storage.write(key: 'access_token', value: accessToken);
      } else {
        await storage.delete(key: 'access_token');
      }
      if (refreshToken != null) {
        await storage.write(key: 'refresh_token', value: refreshToken);
      } else {
        await storage.delete(key: 'refresh_token');
      }
    },
    loadTokens: () async {
      final accessToken = await storage.read(key: 'access_token');
      final refreshToken = await storage.read(key: 'refresh_token');
      if (accessToken != null) {
        return TokenPair(accessToken: accessToken, refreshToken: refreshToken);
      }
      return null;
    },
    onRefreshToken: (String? refreshToken) async {
      // CRITICAL: Use shared lock to prevent concurrent refresh token usage
      // This coordinates with TokenRefreshService and SyncEngine to ensure
      // the refresh token is only used once at a time
      AppLogger.debug('TokenManager: onRefreshToken called, acquiring lock');

      final result = await tokenRefreshLock.acquireAndRefresh(() async {
        AppLogger.debug('TokenManager: Lock acquired, performing refresh');
        final refreshResult = await authRepo.refreshTokenWithResult();
        if (refreshResult.result != TokenRefreshResult.success) {
          throw Exception(refreshResult.error ?? 'Token refresh failed');
        }
        final newToken = await authRepo.getAccessToken();
        if (newToken == null) {
          throw Exception('Failed to get new access token after refresh');
        }
        AppLogger.debug('TokenManager: Refresh successful');
        return newToken;
      });

      // If result is null, another refresh was in progress and completed
      // Get the token from storage (which should now have the fresh token)
      if (result == null) {
        AppLogger.debug(
          'TokenManager: Refresh was handled by another caller, getting token from storage',
        );
        final newToken = await authRepo.getAccessToken();
        if (newToken == null) {
          throw Exception('No access token available after concurrent refresh');
        }
        return newToken;
      }

      return result;
    },
    onLogout: () async {
      // Clear auth state when permanent error occurs
      await authRepo.logout();
    },
  );

  ref.onDispose(tokenManager.dispose);

  return tokenManager;
});

/// Token refresh callback provider - delegates to TokenManager's performRefresh
final tokenRefreshCallbackProvider = Provider<TokenRefreshCallback>((ref) {
  final tokenManager = ref.watch(tokenManagerProvider);

  return (String? refreshToken) async {
    // Use TokenManager's built-in refresh which handles concurrent requests
    final result = await tokenManager.performRefresh();
    if (result != TokenRefreshResult.success) {
      throw Exception('Token refresh failed');
    }
    final token = tokenManager.accessToken;
    if (token == null) {
      throw Exception('No access token after refresh');
    }
    return token;
  };
});

/// Creates a transport factory that uses the provided CertificatePinning instance
///
/// This enables dependency injection of the CertificatePinning service
/// while maintaining compatibility with the client factory function signature.
typedef CreateTransportFn =
    connect.Transport Function(
      Uri baseUrl,
      List<connect.Interceptor> interceptors,
    );

/// Creates a transport factory bound to a CertificatePinning instance
///
/// Parameters:
/// - [certificatePinning]: The CertificatePinning instance to use
///
/// Returns a function that creates transports with certificate pinning enabled.
CreateTransportFn createTransportFactory(
  CertificatePinning certificatePinning,
) => (Uri baseUrl, List<connect.Interceptor> interceptors) {
  final httpClient = certificatePinning.createPinnedHttpClient();
  return connect_protocol.Transport(
    baseUrl: baseUrl.toString(),
    codec: const connect_protobuf.ProtoCodec(),
    httpClient: connect_io.createHttpClient(httpClient),
    interceptors: interceptors,
  );
};

/// Creates a Connect transport for API communication with certificate pinning
///
/// Configures HTTP client with appropriate timeouts, connection pooling,
/// and TLS certificate pinning for optimal performance and security.
///
/// Parameters:
/// - [baseUrl]: The base URL for the API endpoint
/// - [interceptors]: List of interceptors for auth, logging, etc.
///
/// Returns a configured [connect.Transport] instance with certificate pinning.
///
/// Note: Prefer using [createTransportFactory] with dependency injection
/// for better testability and single instance management.
///
/// Example:
/// ```dart
/// final transport = createTransport(
///   Uri.parse('https://api.example.com'),
///   [authInterceptor],
/// );
/// ```
connect.Transport createTransport(
  Uri baseUrl,
  List<connect.Interceptor> interceptors,
) {
  // Fallback: create a new instance (for backwards compatibility)
  final certificatePinning = CertificatePinning();
  final httpClient = certificatePinning.createPinnedHttpClient();

  return connect_protocol.Transport(
    baseUrl: baseUrl.toString(),
    codec: const connect_protobuf.ProtoCodec(),
    httpClient: connect_io.createHttpClient(httpClient),
    interceptors: interceptors,
  );
}

/// Auth headers provider for manual header injection
final authHeadersProvider = FutureProvider<connect.Headers>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final headers = connect.Headers();
  final token = tokenManager.accessToken;
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
});

// ============================================================================
// Service Client Providers
// ============================================================================

/// Chat client provider - uses newChatClient with proper interceptors
final chatClientProvider = FutureProvider<ChatClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  final certificatePinning = ref.watch(certificatePinningProvider);

  // Initialize token manager if not already initialized
  await tokenManager.initialize();

  return newChatClient(
    createTransport: createTransportFactory(certificatePinning),
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Gateway client provider - uses newGatewayClient with proper interceptors
final gatewayClientProvider = FutureProvider<GatewayClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  final certificatePinning = ref.watch(certificatePinningProvider);

  // Initialize token manager if not already initialized
  await tokenManager.initialize();

  return newGatewayClient(
    createTransport: createTransportFactory(certificatePinning),
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Device client provider - uses newDeviceClient with proper interceptors
final deviceClientProvider = FutureProvider<DeviceClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  final certificatePinning = ref.watch(certificatePinningProvider);

  // Initialize token manager if not already initialized
  await tokenManager.initialize();

  return newDeviceClient(
    createTransport: createTransportFactory(certificatePinning),
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Profile client provider - uses newProfileClient with proper interceptors
final profileClientProvider = FutureProvider<ProfileClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  final certificatePinning = ref.watch(certificatePinningProvider);

  // Initialize token manager if not already initialized
  await tokenManager.initialize();

  return newProfileClient(
    createTransport: createTransportFactory(certificatePinning),
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Legacy providers for backward compatibility - expose the underlying service clients
final chatServiceClientProvider = FutureProvider<ChatServiceClient>((
  ref,
) async {
  final client = await ref.watch(chatClientProvider.future);
  return client.stub;
});

final gatewayServiceClientProvider = FutureProvider<GatewayServiceClient>((
  ref,
) async {
  final client = await ref.watch(gatewayClientProvider.future);
  return client.stub;
});

final deviceServiceClientProvider = FutureProvider<DeviceServiceClient>((
  ref,
) async {
  final client = await ref.watch(deviceClientProvider.future);
  return client.stub;
});

final profileServiceClientProvider = FutureProvider<ProfileServiceClient>((
  ref,
) async {
  final client = await ref.watch(profileClientProvider.future);
  return client.stub;
});

// ============================================================================
// Helper Functions for Authenticated API Calls
// ============================================================================

/// Helper to get current auth headers for API calls
/// Usage: final headers = await ref.read(getAuthHeadersProvider.future);
final getAuthHeadersProvider = FutureProvider.autoDispose<connect.Headers>((
  ref,
) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final headers = connect.Headers();
  final token = tokenManager.accessToken;
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
});
