import 'dart:io';
import 'package:openid_client/openid_client_io.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/logging/app_logger.dart';
import 'auth_platform.dart';

AuthPlatform getAuthPlatform() => AuthPlatformIO();

class AuthPlatformIO implements AuthPlatform {
  Issuer? _issuer;
  Client? _client;
  Uri? _redirectUri;

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
        _redirectUri = Uri.parse(
          'http://localhost:5170?partition_id=$clientId',
        );
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
      var uri = Uri.parse(url);
      // Force external application to avoid CCT closing issues
      if (await canLaunchUrl(uri) || Platform.isAndroid) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
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
      redirectUri: _redirectUri!,
    );

    AppLogger.debug('Starting authorization...');
    final c = await authenticator.authorize().timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        throw 'Authentication timed out';
      },
    );
    AppLogger.debug('Authorization completed');

    if (Platform.isAndroid || Platform.isIOS) {
      closeInAppWebView();
    }

    return await c.getTokenResponse();
  }

  @override
  Future<TokenResponse?> getRedirectResult() async {
    return null; // Not used on IO
  }
}
