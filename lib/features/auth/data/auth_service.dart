import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openid_client/openid_client_io.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  final FlutterSecureStorage _storage;
  final String _issuerUrl;
  final String _clientId;

  AuthService(this._storage, {required String issuerUrl, required String clientId})
      : _issuerUrl = issuerUrl,
        _clientId = clientId;

  Future<TokenResponse?> authenticate() async {
    final issuer = await Issuer.discover(Uri.parse(_issuerUrl));
    final client = Client(issuer, _clientId);

    urlLauncher(String url) async {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }

    final authenticator = Authenticator(
      client,
      scopes: ['openid', 'profile', 'email', 'offline_access'],
      port: 4000,
      urlLancher: urlLauncher,
    );

    final c = await authenticator.authorize();
    final token = await c.getTokenResponse();

    await _storage.write(key: 'access_token', value: token.accessToken);
    await _storage.write(key: 'refresh_token', value: token.refreshToken);
    await _storage.write(key: 'id_token', value: token.idToken);

    return token;
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }
}
