import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'api_config.dart';

/// Provider for certificate pinning service
final certificatePinningProvider = Provider<CertificatePinning>((ref) => CertificatePinning());

/// Service for TLS certificate pinning to prevent MITM attacks
///
/// Implements public key pinning using SHA-256 hashes of the certificate's
/// DER encoding. Supports multiple pins per domain for certificate rotation.
///
/// Features:
/// - Pin validation for all API endpoints
/// - Backup pins for certificate rotation
/// - Debug bypass for development builds
/// - Graceful error handling
/// - Dynamic pin updates for remote configuration
///
/// ## IMPORTANT: Production Setup Required
///
/// The default pins are **placeholders** and MUST be replaced with actual
/// certificate hashes before production deployment. To generate a pin:
///
/// ```bash
/// # Get certificate and generate SHA-256 hash:
/// openssl s_client -connect chat.antinvestor.com:443 -servername chat.antinvestor.com \
///   </dev/null 2>/dev/null | openssl x509 -outform DER | openssl sha256 -binary | base64
/// ```
///
/// Include both current and backup pins to support certificate rotation.
class CertificatePinning {
  /// SHA-256 hashes of pinned certificates per domain
  ///
  /// Format: `Map<hostname, List<base64-encoded SHA-256 hash>>`
  /// Multiple pins per domain support certificate rotation
  ///
  /// **WARNING**: These are placeholder values. Replace with actual certificate
  /// hashes before deploying to production. See class documentation for instructions.
  final Map<String, List<String>> _pinnedHashes = {
    // Chat API - REPLACE WITH ACTUAL HASHES
    'chat.antinvestor.com': [
      // Primary certificate pin (current) - PLACEHOLDER
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      // Backup pin (next certificate) - PLACEHOLDER
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
    // Gateway API - REPLACE WITH ACTUAL HASHES
    'gateway.antinvestor.com': [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
    // Device API - REPLACE WITH ACTUAL HASHES
    'devices.antinvestor.com': [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
    // Files API - REPLACE WITH ACTUAL HASHES
    'files.antinvestor.com': [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
    // Profile API - REPLACE WITH ACTUAL HASHES
    'profile.antinvestor.com': [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
    // OAuth2 Provider - REPLACE WITH ACTUAL HASHES
    'oauth2.antinvestor.com': [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
  };

  /// Create an HTTP client with certificate pinning enabled
  ///
  /// Returns an [io.HttpClient] configured with:
  /// - Connection timeout from [ApiConfig]
  /// - Idle timeout from [ApiConfig]
  /// - Certificate validation callback for pin checking
  ///
  /// Example:
  /// ```dart
  /// final httpClient = certificatePinning.createPinnedHttpClient();
  /// ```
  io.HttpClient createPinnedHttpClient() {
    final httpClient = io.HttpClient()
      ..connectionTimeout = ApiConfig.connectionTimeout
      ..idleTimeout = ApiConfig.idleTimeout
      ..maxConnectionsPerHost = 4
      ..autoUncompress = true;

    // Set up certificate validation callback
    httpClient.badCertificateCallback = _validateCertificate;

    return httpClient;
  }

  /// Validate a certificate against pinned public key hashes
  ///
  /// Returns true if the certificate is valid (either pinned or in debug mode).
  /// Returns false if the certificate fails pin validation.
  bool _validateCertificate(
    io.X509Certificate certificate,
    String host,
    int port,
  ) {
    // Allow all certificates in debug mode for development
    if (kDebugMode && _shouldBypassPinning(host)) {
      AppLogger.debug(
        'Certificate pinning bypassed (debug mode)',
        data: {'host': host},
      );
      return true;
    }

    // Get pinned hashes for this host
    final pins = _pinnedHashes[host];

    // If no pins configured for this host, reject by default in release mode
    if (pins == null || pins.isEmpty) {
      if (kDebugMode) {
        AppLogger.warning(
          'No certificate pins configured for host',
          data: {'host': host},
        );
        return true; // Allow in debug mode
      }
      AppLogger.error(
        'Certificate validation failed: no pins configured',
        data: {'host': host},
      );
      return false;
    }

    // Calculate the SHA-256 hash of the certificate
    final certHash = _calculateCertificateHash(certificate);

    if (certHash == null) {
      AppLogger.error(
        'Failed to calculate certificate hash',
        data: {'host': host},
      );
      return false;
    }

    // Check if the certificate hash matches any of the pinned hashes
    final isValid = pins.contains(certHash);

    if (isValid) {
      AppLogger.debug('Certificate pin validated', data: {'host': host});
    } else {
      AppLogger.error(
        'Certificate pin validation failed',
        data: {'host': host, 'certHash': certHash, 'expectedPins': pins},
      );
    }

    return isValid;
  }

  /// Calculate SHA-256 hash of the certificate's DER encoding
  ///
  /// Returns base64-encoded hash or null on error
  ///
  /// Note: This hashes the full DER-encoded certificate rather than just
  /// the SPKI (Subject Public Key Info). While SPKI-only hashing is more
  /// robust against certificate metadata changes, extracting SPKI requires
  /// ASN.1 parsing which adds complexity. For most use cases, full certificate
  /// hashing works well as long as both current and backup pins are configured
  /// to handle certificate rotation gracefully.
  String? _calculateCertificateHash(io.X509Certificate certificate) {
    try {
      // Get the DER-encoded certificate
      final derBytes = certificate.der;

      // Hash the full certificate DER encoding
      final digest = sha256.convert(derBytes);

      return base64.encode(digest.bytes);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error calculating certificate hash',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Check if pinning should be bypassed for a host in debug mode
  ///
  /// Used for localhost and test environments
  bool _shouldBypassPinning(String host) => host == 'localhost' ||
        host == '127.0.0.1' ||
        host.endsWith('.local') ||
        host.endsWith('.test');

  /// Validate that a host has pins configured
  ///
  /// Useful for startup validation
  bool hasPinsConfigured(String host) {
    final pins = _pinnedHashes[host];
    return pins != null && pins.isNotEmpty;
  }

  /// Get all configured hosts with certificate pins
  List<String> get pinnedHosts => _pinnedHashes.keys.toList();

  /// Update pins for a specific host (for remote pin updates)
  ///
  /// Note: This should only be called with pins received over a
  /// trusted channel (e.g., signed configuration from server)
  void updatePins(String host, List<String> newPins) {
    if (newPins.isEmpty) {
      AppLogger.warning(
        'Attempted to set empty pins for host',
        data: {'host': host},
      );
      return;
    }

    _pinnedHashes[host] = List.unmodifiable(newPins);
    AppLogger.info(
      'Certificate pins updated',
      data: {'host': host, 'pinCount': newPins.length},
    );
  }
}

/// Extension to use certificate pinning in HTTP client creation
extension CertificatePinningExtension on CertificatePinning {
  /// Create an HTTP client with certificate pinning and background task settings
  ///
  /// Reduced connection pool for background tasks to conserve resources
  io.HttpClient createPinnedHttpClientForBackground() {
    final httpClient = createPinnedHttpClient();
    httpClient.maxConnectionsPerHost = 2; // Reduced for background tasks
    return httpClient;
  }
}
