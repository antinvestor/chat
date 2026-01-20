import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';

/// Provider for TURN credentials service
final turnCredentialsServiceProvider = FutureProvider<TurnCredentialsService>((
  ref,
) async {
  final deviceClient = await ref.watch(deviceServiceClientProvider.future);
  return TurnCredentialsService(deviceClient);
});

/// Cached TURN server credentials
class TurnCredentials {
  final String url;
  final String? username;
  final String? credential;
  final DateTime expiresAt;

  TurnCredentials({
    required this.url,
    this.username,
    this.credential,
    required this.expiresAt,
  });

  /// Check if credentials are expired or about to expire (within 5 minutes)
  bool get isExpired {
    return DateTime.now().isAfter(
      expiresAt.subtract(const Duration(minutes: 5)),
    );
  }

  /// Convert to WebRTC ICE server configuration
  Map<String, dynamic> toIceServer() {
    if (username != null && credential != null) {
      return {'urls': url, 'username': username, 'credential': credential};
    }
    return {'urls': url};
  }
}

/// Service for managing TURN server credentials
///
/// Handles:
/// - Fetching TURN credentials from backend
/// - Caching credentials with TTL
/// - Credential refresh before expiry
/// - Fallback to STUN if TURN unavailable
class TurnCredentialsService {
  final dynamic _deviceClient;

  /// Cached TURN credentials
  List<TurnCredentials>? _cachedCredentials;

  /// Default STUN servers for fallback
  static const List<Map<String, dynamic>> _defaultStunServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  /// AntInvestor TURN servers (configured with dynamic credentials)
  static const List<String> _turnServerUrls = [
    'turn:turn.antinvestor.com:3478',
    'turn:turn.antinvestor.com:3478?transport=tcp',
    'turns:turn.antinvestor.com:5349',
  ];

  TurnCredentialsService(this._deviceClient);

  /// Get ICE server configuration for WebRTC
  ///
  /// Returns a configuration map with:
  /// - STUN servers (always included for fallback)
  /// - TURN servers with dynamic credentials (if available)
  ///
  /// Example:
  /// ```dart
  /// final config = await turnService.getIceServers();
  /// _peerConnection = await createPeerConnection(config);
  /// ```
  Future<Map<String, dynamic>> getIceServers() async {
    final iceServers = <Map<String, dynamic>>[];

    // Always include STUN servers for fallback
    iceServers.addAll(_defaultStunServers);

    try {
      // Get TURN credentials
      final turnCredentials = await _getTurnCredentials();

      if (turnCredentials.isNotEmpty) {
        // Add TURN servers with credentials
        for (final cred in turnCredentials) {
          iceServers.add(cred.toIceServer());
        }

        AppLogger.info(
          'ICE servers configured with TURN',
          data: {'turnServerCount': turnCredentials.length},
        );
      } else {
        AppLogger.warning('No TURN credentials available, using STUN only');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get TURN credentials',
        error: e,
        stackTrace: stackTrace,
      );
      // Continue with STUN-only configuration
    }

    return {'iceServers': iceServers};
  }

  /// Get TURN credentials, using cache if valid
  Future<List<TurnCredentials>> _getTurnCredentials() async {
    // Check if cached credentials are still valid
    if (_cachedCredentials != null && _cachedCredentials!.isNotEmpty) {
      final allValid = _cachedCredentials!.every((c) => !c.isExpired);
      if (allValid) {
        AppLogger.debug('Using cached TURN credentials');
        return _cachedCredentials!;
      }
    }

    // Fetch fresh credentials
    _cachedCredentials = await _fetchTurnCredentials();
    return _cachedCredentials!;
  }

  /// Fetch TURN credentials from the backend
  ///
  /// This calls the Device API to get temporary TURN credentials.
  /// The backend generates short-lived credentials for security.
  Future<List<TurnCredentials>> _fetchTurnCredentials() async {
    try {
      // For now, use static credentials until the API endpoint is implemented
      // TODO: Implement actual API call when Device API supports TURN credentials
      //
      // The implementation would look like:
      // final request = GetTurnCredentialsRequest();
      // final response = await _deviceClient.getTurnCredentials(request);
      //
      // return response.servers.map((server) => TurnCredentials(
      //   url: server.url,
      //   username: server.username,
      //   credential: server.credential,
      //   expiresAt: DateTime.fromMillisecondsSinceEpoch(server.expiresAt * 1000),
      // )).toList();

      // Placeholder: Return empty list (STUN-only mode)
      // Remove this when API is implemented
      AppLogger.debug(
        'TURN credentials API not yet implemented, using STUN only',
      );
      return [];
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error fetching TURN credentials from API',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Force refresh of cached credentials
  ///
  /// Call this when experiencing connection issues that might
  /// be caused by expired credentials
  Future<void> refreshCredentials() async {
    _cachedCredentials = null;
    await _getTurnCredentials();
  }

  /// Clear cached credentials (call on logout)
  void clearCache() {
    _cachedCredentials = null;
    AppLogger.debug('TURN credentials cache cleared');
  }
}
