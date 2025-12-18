import 'package:connectrpc/connect.dart' as connect;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../apis/chat/v1/chat.connect.client.dart';
import '../../apis/device/v1/device.connect.client.dart';
import '../../apis/profile/v1/profile.connect.client.dart';
import '../../features/auth/data/auth_repository.dart';
import 'authenticated_transport.dart';

/// Secure storage provider for token access
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Token provider that integrates with auth repository
final tokenProviderProvider = Provider<TokenProvider>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  
  return SecureStorageTokenProvider(
    storage,
    onExpired: () async {
      // Try to refresh token when expired
      await authRepo.refreshToken();
    },
  );
});

/// Transport factory provider - creates authenticated transports
final transportFactoryProvider = Provider<TransportFactory>((ref) {
  final tokenProvider = ref.watch(tokenProviderProvider);
  final factory = TransportFactory(tokenProvider);
  
  ref.onDispose(() {
    factory.dispose();
  });
  
  return factory;
});

/// Auth headers provider for manual header injection
final authHeadersProvider = FutureProvider<connect.Headers>((ref) async {
  final factory = ref.watch(transportFactoryProvider);
  return await factory.getAuthHeaders();
});

// ============================================================================
// Service Client Providers
// ============================================================================

/// Chat service client - uses chat.antinvestor.com
final chatServiceClientProvider = Provider<ChatServiceClient>((ref) {
  final factory = ref.watch(transportFactoryProvider);
  return ChatServiceClient(factory.chatTransport);
});

/// Gateway service client - uses gateway.antinvestor.com for real-time connections
final gatewayServiceClientProvider = Provider<GatewayServiceClient>((ref) {
  final factory = ref.watch(transportFactoryProvider);
  return GatewayServiceClient(factory.gatewayTransport);
});

/// Device service client - uses devices.antinvestor.com
final deviceServiceClientProvider = Provider<DeviceServiceClient>((ref) {
  final factory = ref.watch(transportFactoryProvider);
  return DeviceServiceClient(factory.deviceTransport);
});

/// Profile service client - uses profile.antinvestor.com
final profileServiceClientProvider = Provider<ProfileServiceClient>((ref) {
  final factory = ref.watch(transportFactoryProvider);
  return ProfileServiceClient(factory.profileTransport);
});

// ============================================================================
// Helper Functions for Authenticated API Calls
// ============================================================================

/// Helper to get current auth headers for API calls
/// Usage: final headers = await ref.read(getAuthHeadersProvider.future);
final getAuthHeadersProvider = FutureProvider.autoDispose<connect.Headers>((ref) async {
  final factory = ref.watch(transportFactoryProvider);
  return await factory.getAuthHeaders();
});
