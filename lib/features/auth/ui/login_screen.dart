import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import '../../../core/logging/app_logger.dart';
import '../data/auth_state_provider.dart';

/// Login screen that presents an OpenID Connect button to users
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    // Check connectivity first
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      setState(() {
        _errorMessage =
            'No internet connection. Please connect to the internet and try again.';
      });
      AppLogger.warning('Login attempted while offline');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authStateProvider.notifier).login();
      // Navigation will be handled by router redirect
    } catch (e, stackTrace) {
      AppLogger.error(
        'User login attempt failed',
        error: e,
        stackTrace: stackTrace,
      );

      // Provide better error messages based on error type
      String errorMessage = 'Authentication failed. Please try again.';

      // Check for common network-related errors
      if (e is SocketException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage =
            'Cannot connect to server. Please check your internet connection.';
      } else if (e.toString().contains('404')) {
        errorMessage =
            'Authentication service unavailable. Please try again later.';
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('TimeoutException')) {
        errorMessage =
            'Connection timed out. Please check your internet connection.';
      } else if (e.toString().contains('Could not launch browser')) {
        errorMessage =
            'Unable to open web browser. Please check your device settings.';
      }

      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo / Icon
                Hero(
                  tag: 'info-logo',
                  child: Image.asset('assets/banner_transparent_black.png'),
                ),
                const SizedBox(height: 12),

                const SizedBox(height: 64),

                // Error message if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Login Button
                FilledButton.icon(
                  onPressed: _isLoading ? null : _handleLogin,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login),
                  label: Text(_isLoading ? 'Signing in...' : 'Get started'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Info text
                Text(
                  'By signing in, you agree to our terms of service and privacy policy',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
