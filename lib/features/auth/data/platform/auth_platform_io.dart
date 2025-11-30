import 'package:openid_client/openid_client_io.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/logging/app_logger.dart';
import 'auth_platform.dart';

AuthPlatform getAuthPlatform() => AuthPlatformIO();

class AuthPlatformIO implements AuthPlatform {
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
        // Add timeout to discovery to prevent hanging
        _issuer = await Issuer.discover(
          Uri.parse(issuerUrl),
        ).timeout(const Duration(seconds: 15));
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
      throw StateError('AuthPlatformIO not initialized');
    }

    urlLauncher(String url) async {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        // Try platform default first (best for Android 11+)
        if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
          // Fallback to external application
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        AppLogger.error('Could not launch OIDC URL', data: {'url': url});
        throw 'Could not launch browser for authentication';
      }
    }

    final authenticator = Authenticator(
      _client!,
      scopes: scopes,
      port: 5170,
      urlLancher: urlLauncher,
    );

    final c = await authenticator.authorize();
    return await c.getTokenResponse();
  }

  @override
  Future<TokenResponse?> getRedirectResult() async {
    return null; // Not used on IO
  }
}
