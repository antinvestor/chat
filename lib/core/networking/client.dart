import 'dart:io' as io;

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
import 'api_config.dart';

/// Secure storage provider for token access
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Token manager provider using antinvestor_api_common TokenManager
/// 
/// TokenManager handles:
/// - Persistent storage of tokens
/// - Reactive refresh on 401 (via interceptor)
/// - Concurrent refresh prevention
/// - Logout on permanent errors
final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  
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
        return TokenPair(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      }
      return null;
    },
    onRefreshToken: (String? refreshToken) async {
      // Use the auth repository to refresh the token via OIDC
      final result = await authRepo.refreshTokenWithResult();
      if (result.result != TokenRefreshResult.success) {
        throw Exception(result.error ?? 'Token refresh failed');
      }
      final newToken = await authRepo.getAccessToken();
      if (newToken == null) {
        throw Exception('Failed to get new access token after refresh');
      }
      return newToken;
    },
    onLogout: () async {
      // Clear auth state when permanent error occurs
      await authRepo.logout();
    },
  );
  
  ref.onDispose(() {
    tokenManager.dispose();
  });
  
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

/// Transport factory function for creating Connect transports
connect.Transport createTransport(Uri baseUrl, List<connect.Interceptor> interceptors) {
  final httpClient = io.HttpClient()
    ..connectionTimeout = ApiConfig.connectionTimeout
    ..idleTimeout = ApiConfig.idleTimeout
    ..maxConnectionsPerHost = 4
    ..autoUncompress = true;
  
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
  
  // Initialize token manager if not already initialized
  await tokenManager.initialize();
  
  return await newChatClient(
    createTransport: createTransport,
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Gateway client provider - uses newGatewayClient with proper interceptors
final gatewayClientProvider = FutureProvider<GatewayClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  
  // Initialize token manager if not already initialized
  await tokenManager.initialize();
  
  return await newGatewayClient(
    createTransport: createTransport,
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Device client provider - uses newDeviceClient with proper interceptors
final deviceClientProvider = FutureProvider<DeviceClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  
  // Initialize token manager if not already initialized
  await tokenManager.initialize();
  
  return await newDeviceClient(
    createTransport: createTransport,
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Profile client provider - uses newProfileClient with proper interceptors
final profileClientProvider = FutureProvider<ProfileClient>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final onTokenRefresh = ref.watch(tokenRefreshCallbackProvider);
  
  // Initialize token manager if not already initialized
  await tokenManager.initialize();
  
  return await newProfileClient(
    createTransport: createTransport,
    tokenManager: tokenManager,
    onTokenRefresh: onTokenRefresh,
  );
});

/// Legacy providers for backward compatibility - expose the underlying service clients
final chatServiceClientProvider = FutureProvider<ChatServiceClient>((ref) async {
  final client = await ref.watch(chatClientProvider.future);
  return client.stub;
});

final gatewayServiceClientProvider = FutureProvider<GatewayServiceClient>((ref) async {
  final client = await ref.watch(gatewayClientProvider.future);
  return client.stub;
});

final deviceServiceClientProvider = FutureProvider<DeviceServiceClient>((ref) async {
  final client = await ref.watch(deviceClientProvider.future);
  return client.stub;
});

final profileServiceClientProvider = FutureProvider<ProfileServiceClient>((ref) async {
  final client = await ref.watch(profileClientProvider.future);
  return client.stub;
});

// ============================================================================
// Helper Functions for Authenticated API Calls
// ============================================================================

/// Helper to get current auth headers for API calls
/// Usage: final headers = await ref.read(getAuthHeadersProvider.future);
final getAuthHeadersProvider = FutureProvider.autoDispose<connect.Headers>((ref) async {
  final tokenManager = ref.watch(tokenManagerProvider);
  final headers = connect.Headers();
  final token = tokenManager.accessToken;
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
});
