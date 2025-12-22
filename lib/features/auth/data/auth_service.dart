import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openid_client/openid_client.dart';
import 'platform/auth_platform.dart';
import 'platform/auth_platform_stub.dart'
    if (dart.library.io) 'platform/auth_platform_io.dart'
    if (dart.library.html) 'platform/auth_platform_web.dart';
import '../../../core/logging/app_logger.dart';

class AuthService {
  final FlutterSecureStorage _storage;
  final String _issuerUrl;
  final String _clientId;
  final AuthPlatform _platform = getAuthPlatform();

  AuthService(
    this._storage, {
    required String issuerUrl,
    required String clientId,
  }) : _issuerUrl = issuerUrl,
       _clientId = clientId;

  /// Initialize OIDC issuer and client
  Future<void> _ensureInitialized() async {
    await _platform.initialize(_issuerUrl, _clientId);
  }

  /// Authenticate user with OIDC provider
  /// 
  /// Returns [TokenResponse] on success, null if redirect-based flow (web).
  /// Throws on error.
  Future<TokenResponse?> authenticate() async {
    try {
      AppLogger.info(
        'Starting OIDC authentication',
        data: {'issuerUrl': _issuerUrl},
      );
      await _ensureInitialized();

      final token = await _platform.authenticate([
        'openid',
        'profile',
        'contact',
        'offline_access',
      ]);

      if (token != null) {
        // Validate that we actually got an access token
        if (token.accessToken == null || token.accessToken!.isEmpty) {
          AppLogger.error('Token response missing access token', data: {
            'hasRefreshToken': token.refreshToken != null,
            'hasIdToken': token.idToken != null,
          });
          throw Exception('Authentication failed: No access token received');
        }
        
        await _saveTokens(token);
        
        // Verify the token was actually saved
        final savedToken = await getAccessToken();
        if (savedToken == null) {
          AppLogger.error('Failed to save token to secure storage');
          throw Exception('Authentication failed: Could not save credentials');
        }
        
        AppLogger.info('User authenticated successfully');
        return token;
      } else {
        // On Web, this might be null due to redirect
        AppLogger.info(
          'Authentication initiated (expecting redirect or popup)',
        );
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Authentication failed',
        error: e,
        stackTrace: stackTrace,
        data: {'issuerUrl': _issuerUrl},
      );
      rethrow;
    }
  }

  /// Cancel any ongoing authentication flow
  /// 
  /// Call this if the user wants to abort authentication or if the app
  /// needs to clean up before starting a new auth flow.
  Future<void> cancelAuthentication() async {
    try {
      await _platform.cancelAuthentication();
      AppLogger.debug('Authentication cancelled');
    } catch (e) {
      AppLogger.debug('Error cancelling authentication: $e');
    }
  }

  /// Save tokens to secure storage
  Future<void> _saveTokens(TokenResponse token) async {
    await _storage.write(key: 'access_token', value: token.accessToken);
    await _storage.write(key: 'refresh_token', value: token.refreshToken);
    try {
      // ignore: unnecessary_null_comparison
      if (token.idToken != null) {
        await _storage.write(
          key: 'id_token',
          value: token.idToken.toCompactSerialization(),
        );
      }
    } catch (_) {
      // ID token might be missing or throw on access
      AppLogger.debug('No ID token in response');
    }

    // Store token expiry timestamp
    if (token.expiresAt != null) {
      await _storage.write(
        key: 'token_expires_at',
        value: token.expiresAt!.millisecondsSinceEpoch.toString(),
      );
      AppLogger.debug(
        'Tokens saved to secure storage',
        data: {'expiresAt': token.expiresAt!.toIso8601String()},
      );
    }
  }

  /// Get current access token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  /// Get current refresh token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: 'refresh_token');
  }

  /// Get ID token
  Future<String?> getIdToken() async {
    return await _storage.read(key: 'id_token');
  }

  /// Check if access token is expired or about to expire
  /// Returns true if token expires within the next 2 minutes
  Future<bool> isTokenExpired() async {
    final expiresAtStr = await _storage.read(key: 'token_expires_at');
    if (expiresAtStr == null) {
      // If we don't have expiry info, assume token is valid
      // This shouldn't happen in normal flow
      return false;
    }

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      int.parse(expiresAtStr),
    );

    // Consider token expired if it expires within 2 minutes
    final now = DateTime.now();
    final bufferTime = const Duration(minutes: 2);

    return now.isAfter(expiresAt.subtract(bufferTime));
  }

  /// Refresh the access token using refresh token
  Future<TokenResponse?> refreshToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      AppLogger.warning('No refresh token available for token refresh');
      return null;
    }

    try {
      AppLogger.debug('Attempting to refresh access token');
      await _ensureInitialized();

      if (_platform.client == null) {
        throw StateError('Auth client not initialized');
      }

      final credential = _platform.client!.createCredential(
        accessToken: await getAccessToken(),
        refreshToken: refreshToken,
      );

      // Refresh the token
      final newCredential = await credential.getTokenResponse();
      await _saveTokens(newCredential);
      AppLogger.info('Access token refreshed successfully');

      return newCredential;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Token refresh failed',
        error: e,
        stackTrace: stackTrace,
        data: {'hasRefreshToken': true},
      );
      // If refresh fails, clear tokens to force re-authentication
      await logout();
      return null;
    }
  }

  /// Get user information from ID token
  Future<Map<String, dynamic>?> getUserInfo() async {
    final idToken = await getIdToken();
    if (idToken == null) return null;

    try {
      // Decode JWT (ID token is in format: header.payload.signature)
      final parts = idToken.split('.');
      if (parts.length != 3) return null;

      // Decode the payload (second part)
      final payload = parts[1];

      // Add padding if needed for base64 decoding
      var normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64.decode(normalized));

      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to decode ID token',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Check if user is authenticated
  /// Returns true if user has a valid access token OR a refresh token that can be used
  Future<bool> isAuthenticated() async {
    // Check for redirect result first (only matters for web)
    await _handleRedirectResult();
    
    final accessToken = await getAccessToken();
    if (accessToken != null) {
      return true;
    }
    
    // No access token, but check if we have a refresh token
    // If so, the user is still "logged in" and we can recover the session
    final refreshTokenValue = await getRefreshToken();
    return refreshTokenValue != null;
  }
  
  /// Check if user has a valid, usable access token
  /// This is different from isAuthenticated - this checks if we can make API calls right now
  Future<bool> hasValidAccessToken() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      return false;
    }
    
    // Check if token is expired
    final expired = await isTokenExpired();
    return !expired;
  }
  
  /// Ensure we have a valid access token, refreshing if necessary
  /// Returns the access token if successful, null if refresh failed
  Future<String?> ensureValidAccessToken() async {
    final accessToken = await getAccessToken();
    
    // If we have a token and it's not expired, return it
    if (accessToken != null) {
      final expired = await isTokenExpired();
      if (!expired) {
        return accessToken;
      }
    }
    
    // Token is missing or expired, try to refresh
    final refreshTokenValue = await getRefreshToken();
    if (refreshTokenValue == null) {
      AppLogger.debug('No refresh token available, user needs to login');
      return null;
    }
    
    // Attempt refresh
    AppLogger.debug('Access token missing/expired, attempting refresh');
    final newToken = await refreshToken();
    if (newToken != null) {
      return newToken.accessToken;
    }
    
    return null;
  }

  /// Handle redirect result from Web authentication
  /// 
  /// Returns true if a valid session was recovered from redirect.
  Future<bool> _handleRedirectResult() async {
    try {
      await _ensureInitialized();
      final token = await _platform.getRedirectResult();
      if (token != null) {
        AppLogger.info('Recovered session from redirect');
        await _saveTokens(token);
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      // Log the error but don't rethrow - we might not be returning from redirect
      AppLogger.warning(
        'Error handling redirect result',
        data: {'error': e.toString()},
      );
      AppLogger.debug('Redirect error details', data: {'stackTrace': stackTrace.toString()});
      return false;
    }
  }

  /// Logout and clear all stored tokens
  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'id_token');
    await _storage.delete(key: 'token_expires_at');
  }
}
