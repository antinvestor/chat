import 'package:openid_client/openid_client_browser.dart';
import '../../../../core/logging/app_logger.dart';
import 'auth_platform.dart';

AuthPlatform getAuthPlatform() => AuthPlatformWeb();

class AuthPlatformWeb implements AuthPlatform {
  Issuer? _issuer;
  Client? _client;

  @override
  Issuer? get issuer => _issuer;

  @override
  Client? get client => _client;

  @override
  Future<void> initialize(String issuerUrl, String clientId) async {
    if (_issuer == null || _client == null) {
      try {
        _issuer = await Issuer.discover(Uri.parse(issuerUrl));
        _client = Client(_issuer!, clientId);
      } catch (e) {
        AppLogger.error(
          'Failed to discover OIDC issuer',
          error: e,
          data: {'url': issuerUrl},
        );
        rethrow;
      }
    }
  }

  @override
  Future<TokenResponse?> authenticate(List<String> scopes) async {
    if (_client == null) {
      throw StateError('AuthPlatformWeb not initialized');
    }

    final authenticator = Authenticator(_client!, scopes: scopes);

    // On web, authorize() typically redirects the page.
    // If it returns, it might be a popup flow, but standard is redirect.
    // openid_client_browser handles the flow.

    // Check if we are returning from a redirect
    // Note: This logic might need to be called on app start too,
    // but for now we implement the authenticate method.

    authenticator.authorize();

    // Since authorize redirects, this might not return immediately or at all in the same session.
    // However, if using popup or if the library handles it, we might get a result.
    // For standard redirect flow, the app reloads.

    // We need to handle the callback.
    // In openid_client_browser, we usually check for credential on load.

    // For this implementation, we will assume the caller handles the redirect flow
    // or we might need to adjust AuthService to check for tokens on init.

    return null;
  }

  @override
  Future<TokenResponse?> getRedirectResult() async {
    if (_client == null) return null;
    final authenticator = Authenticator(_client!);
    final credential = await authenticator.credential;
    if (credential != null) {
      return await credential.getTokenResponse();
    }
    return null;
  }

  /// Helper to check for token on page load (redirect back)
  Future<TokenResponse?> checkCredential() async {
    return getRedirectResult();
  }
}
