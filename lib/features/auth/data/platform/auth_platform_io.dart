import 'dart:async';
import 'dart:io';
import 'package:openid_client/openid_client_io.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/logging/app_logger.dart';
import 'auth_platform.dart';

/// Custom authenticator that provides better error handling and logging
class _CustomAuthenticator {
  final Flow flow;
  final Future<void> Function(String url) urlLauncher;
  final String successHtml;
  HttpServer? _server;
  bool _cancelled = false;

  _CustomAuthenticator({
    required this.flow,
    required this.urlLauncher,
    required this.successHtml,
  });

  Future<Credential> authorize() async {
    final completer = Completer<Credential>();

    try {
      // Start local server to receive callback
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, flow.redirectUri.port);
      AppLogger.debug('Started auth callback server', data: {'port': flow.redirectUri.port});

      // Handle incoming requests
      _server!.listen((request) async {
        if (_cancelled) {
          request.response.statusCode = HttpStatus.gone;
          request.response.write('Authentication cancelled');
          await request.response.close();
          return;
        }

        try {
          AppLogger.debug('Received callback request', data: {
            'uri': request.uri.toString(),
            'queryParams': request.uri.queryParameters,
          });

          // Check for OAuth error response
          final error = request.uri.queryParameters['error'];
          if (error != null) {
            final errorDesc = request.uri.queryParameters['error_description'] ?? error;
            AppLogger.error('OAuth error from provider', data: {'error': error, 'description': errorDesc});
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write('Authentication error: $errorDesc');
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(Exception('OAuth error: $errorDesc'));
            }
            return;
          }

          // Get authorization code
          final code = request.uri.queryParameters['code'];
          final state = request.uri.queryParameters['state'];

          if (code == null) {
            AppLogger.warning('No code in callback', data: {'uri': request.uri.toString()});
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write('Missing authorization code');
            await request.response.close();
            return;
          }

          AppLogger.debug('Processing auth callback', data: {'hasCode': true, 'hasState': state != null});

          // Return success page
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.html;
          request.response.write(successHtml);
          await request.response.close();

          // Exchange code for tokens
          try {
            final credential = await flow.callback({
              'code': code,
              if (state != null) 'state': state,
            });
            AppLogger.debug('Code exchange successful');
            if (!completer.isCompleted) {
              completer.complete(credential);
            }
          } catch (e, stackTrace) {
            AppLogger.error('Code exchange failed', error: e, stackTrace: stackTrace);
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }
        } catch (e, stackTrace) {
          AppLogger.error('Error handling callback request', error: e, stackTrace: stackTrace);
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Internal error');
            await request.response.close();
          } catch (_) {}
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        }
      });

      // Launch browser
      final authUri = flow.authenticationUri;
      AppLogger.debug('Launching auth URL', data: {'url': authUri.toString()});
      await urlLauncher(authUri.toString());

      return await completer.future;
    } catch (e) {
      await cancel();
      rethrow;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _server?.close(force: true);
      _server = null;
    } catch (e) {
      AppLogger.debug('Error closing auth server: $e');
    }
  }
}

AuthPlatform getAuthPlatform() => AuthPlatformIO();

class AuthPlatformIO implements AuthPlatform {
  static const int _authPort = 5170;
  static const Duration _authTimeout = Duration(minutes: 3);
  
  Issuer? _issuer;
  Client? _client;
  Uri? _redirectUri;
  _CustomAuthenticator? _currentAuthenticator;

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
        // Redirect URI with partition_id as required by the OAuth provider
        _redirectUri = Uri.parse('http://localhost:$_authPort?partition_id=$clientId');
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

    // Cancel any previous authentication attempt
    await cancelAuthentication();

    Future<void> urlLauncher(String url) async {
      final uri = Uri.parse(url);
      AppLogger.debug('Launching auth URL', data: {'url': url});
      
      try {
        // Use external application mode to ensure proper redirect handling
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (!launched) {
          // Fallback: try platform view on mobile
          if (Platform.isAndroid || Platform.isIOS) {
            final fallbackLaunched = await launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
            );
            if (!fallbackLaunched) {
              throw Exception('Could not launch authentication URL');
            }
          } else {
            throw Exception('Could not launch authentication URL');
          }
        }
      } catch (e) {
        AppLogger.error('Failed to launch auth URL', error: e, data: {'url': url});
        rethrow;
      }
    }

    final flow = Flow.authorizationCodeWithPKCE(_client!)
      ..scopes.addAll(scopes)
      ..redirectUri = _redirectUri!;

    // Custom HTML page that auto-closes and provides user feedback
    const htmlPage = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Authentication Complete</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 2rem;
      background: rgba(255,255,255,0.1);
      border-radius: 16px;
      backdrop-filter: blur(10px);
    }
    h1 { margin-bottom: 1rem; }
    p { opacity: 0.9; }
    .spinner {
      width: 40px;
      height: 40px;
      border: 3px solid rgba(255,255,255,0.3);
      border-top-color: white;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 1rem auto;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="container">
    <h1>Authentication Successful!</h1>
    <div class="spinner"></div>
    <p>Returning to the app...</p>
    <p><small>You can close this window if it doesn't close automatically.</small></p>
  </div>
  <script>
    setTimeout(function() { window.close(); }, 1500);
  </script>
</body>
</html>
''';

    _currentAuthenticator = _CustomAuthenticator(
      flow: flow,
      urlLauncher: urlLauncher,
      successHtml: htmlPage,
    );

    AppLogger.debug('Starting authorization flow...', data: {
      'redirectUri': _redirectUri.toString(),
      'scopes': scopes,
    });
    
    try {
      final credential = await _currentAuthenticator!.authorize().timeout(
        _authTimeout,
        onTimeout: () {
          AppLogger.warning('Authentication timed out after $_authTimeout');
          cancelAuthentication();
          throw TimeoutException('Authentication timed out. Please try again.', _authTimeout);
        },
      );
      
      AppLogger.debug('Authorization flow completed, getting token response...');
      
      // Close any in-app browser on mobile
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          closeInAppWebView();
        } catch (_) {
          // Ignore errors closing webview
        }
      }

      // Add a small delay on mobile to allow network to stabilize after browser redirect
      if (Platform.isAndroid || Platform.isIOS) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Get token response with retry for network errors
      final tokenResponse = await _retryWithBackoff(
        () async {
          AppLogger.debug('Attempting to get token response...');
          final response = await credential.getTokenResponse();
          AppLogger.debug('Token response received', data: {
            'hasAccessToken': response.accessToken != null,
            'hasRefreshToken': response.refreshToken != null,
            'expiresAt': response.expiresAt?.toIso8601String(),
          });
          return response;
        },
        maxAttempts: 3,
        initialDelay: const Duration(seconds: 1),
      );
      
      // Clean up
      await _currentAuthenticator?.cancel();
      _currentAuthenticator = null;
      
      AppLogger.info('Authentication successful');
      return tokenResponse;
    } catch (e, stackTrace) {
      AppLogger.error('Authentication failed', error: e, stackTrace: stackTrace);
      await _currentAuthenticator?.cancel();
      _currentAuthenticator = null;
      rethrow;
    }
  }

  @override
  Future<void> cancelAuthentication() async {
    if (_currentAuthenticator != null) {
      try {
        await _currentAuthenticator!.cancel();
        AppLogger.debug('Cancelled previous authentication flow');
      } catch (e) {
        // Ignore cancellation errors
        AppLogger.debug('Error cancelling auth flow: $e');
      }
      _currentAuthenticator = null;
    }
  }

  @override
  Future<TokenResponse?> getRedirectResult() async {
    return null; // Not used on IO
  }

  /// Retry an async operation with exponential backoff for network errors
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    required int maxAttempts,
    required Duration initialDelay,
  }) async {
    Duration delay = initialDelay;
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation().timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Operation timed out');
          },
        );
      } catch (e) {
        final isNetworkError = e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('Network is unreachable') ||
            e is TimeoutException;
        
        if (!isNetworkError || attempt == maxAttempts) {
          rethrow;
        }
        
        AppLogger.warning(
          'Network error on attempt $attempt/$maxAttempts, retrying in ${delay.inSeconds}s...',
          data: {'error': e.toString()},
        );
        
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    
    throw StateError('Retry loop completed without returning');
  }
}
