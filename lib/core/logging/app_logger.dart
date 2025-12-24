import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';

/// Simple log printer - one line per message, easy to scan
class _SimpleLogPrinter extends LogPrinter {
  static const _levelPrefixes = {
    Level.trace: '🔍 TRACE',
    Level.debug: '🐛 DEBUG',
    Level.info: '✓ INFO',
    Level.warning: '⚠ WARN',
    Level.error: '❌ ERROR',
    Level.fatal: '💀 FATAL',
  };

  @override
  List<String> log(LogEvent event) {
    final prefix = _levelPrefixes[event.level] ?? '?';
    final time = DateTime.now().toString().substring(11, 19); // HH:MM:SS
    final lines = <String>['$time $prefix  ${event.message}'];
    
    if (event.error != null) {
      lines.add('         └─ ${event.error}');
    }
    if (event.stackTrace != null && event.level.index >= Level.error.index) {
      // Only show first 3 frames for errors
      final frames = event.stackTrace.toString().split('\n').take(3);
      for (final frame in frames) {
        if (frame.trim().isNotEmpty) {
          lines.add('            $frame');
        }
      }
    }
    return lines;
  }
}

/// Centralized application logger
class AppLogger {
  static final Logger _logger = Logger(
    printer: _SimpleLogPrinter(),
    level: kDebugMode ? Level.debug : Level.info,
  );

  /// Verbose logging - most detailed
  /// Use for very granular debugging information
  static void verbose(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.t(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Debug logging - detailed information for debugging
  /// Use for debugging flow and state changes
  static void debug(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.d(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Info logging - general information
  /// Use for important events and state changes
  static void info(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.i(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Warning logging - potentially harmful situations
  /// Use for recoverable errors or unexpected situations
  static void warning(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.w(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Error logging - error events
  /// Use for errors that don't crash the app but need attention
  static void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.e(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );

    // Hook for error reporting services (Sentry, Firebase Crashlytics, etc.)
    _reportError(message, error, stackTrace, data);
  }

  /// Fatal logging - very severe error events
  /// Use for critical errors that might lead to application crash
  static void fatal(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _logger.f(
      _formatMessage(message, data),
      error: error,
      stackTrace: stackTrace,
    );

    // Always report fatal errors
    _reportError(message, error, stackTrace, data, isFatal: true);
  }

  /// Format message with additional data
  static String _formatMessage(String message, Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return message;
    }

    final dataStr = data.entries.map((e) => '${e.key}: ${e.value}').join(', ');

    return '$message | Data: {$dataStr}';
  }

  /// Report error to external error reporting service
  /// This is a placeholder for integration with services like Sentry, Firebase Crashlytics, etc.
  static void _reportError(
    String message,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data, {
    bool isFatal = false,
  }) {
    // Only report errors in release mode to avoid noise during development
    if (!kReleaseMode) {
      return;
    }

    // TODO: Integrate with error reporting service
    // Example for Sentry:
    // Sentry.captureException(
    //   error,
    //   stackTrace: stackTrace,
    //   hint: Hint.withMap({
    //     'message': message,
    //     'data': data,
    //     'isFatal': isFatal,
    //   }),
    // );

    // Example for Firebase Crashlytics:
    // FirebaseCrashlytics.instance.recordError(
    //   error,
    //   stackTrace,
    //   reason: message,
    //   fatal: isFatal,
    //   information: data?.entries.map((e) => '${e.key}: ${e.value}').toList() ?? [],
    // );
  }

  /// Close the logger (cleanup)
  static void close() {
    _logger.close();
  }
}
