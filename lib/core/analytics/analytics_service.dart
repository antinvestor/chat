// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../logging/app_logger.dart';
import 'analytics_event.dart';

/// Configuration for the analytics service
class AnalyticsConfig {
  const AnalyticsConfig({
    this.enabled = true,
    this.batchSize = 50,
    this.flushIntervalSeconds = 60,
    this.maxStoredEvents = 1000,
    this.enableDebugLogging = false,
  });

  /// Whether analytics is enabled
  final bool enabled;

  /// Number of events to batch before sending
  final int batchSize;

  /// Interval in seconds between automatic flushes
  final int flushIntervalSeconds;

  /// Maximum number of events to store locally
  final int maxStoredEvents;

  /// Enable debug logging for analytics events
  final bool enableDebugLogging;
}

/// Analytics service for tracking user behavior and app usage
///
/// Features:
/// - Event tracking (screen views, user actions, errors)
/// - Session management
/// - User property tracking
/// - Local event storage with batch upload
/// - Privacy-compliant (no PII without consent)
///
/// Example:
/// ```dart
/// final analytics = AnalyticsService();
/// await analytics.initialize();
///
/// analytics.trackScreenView('HomeScreen');
/// analytics.trackEvent('button_tap', properties: {'button_id': 'send_message'});
/// ```
class AnalyticsService {
  AnalyticsService({AnalyticsConfig config = const AnalyticsConfig()})
    : _config = config;

  final AnalyticsConfig _config;
  static const _uuid = Uuid();

  // Session management
  AnalyticsSession? _currentSession;
  String? _currentUserId;
  AnalyticsUserProperties? _userProperties;

  // Event storage
  final List<AnalyticsEvent> _eventQueue = [];
  Timer? _flushTimer;
  bool _initialized = false;

  // Local storage
  String? _storagePath;

  /// Initialize the analytics service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Set up storage path
      if (!kIsWeb) {
        final directory = await getApplicationDocumentsDirectory();
        _storagePath = '${directory.path}/analytics';
        await Directory(_storagePath!).create(recursive: true);
      }

      // Load any pending events from storage
      await _loadPendingEvents();

      // Start a new session
      _startNewSession();

      // Set up periodic flush timer
      _flushTimer = Timer.periodic(
        Duration(seconds: _config.flushIntervalSeconds),
        (_) => _flushEvents(),
      );

      _initialized = true;
      _log('Analytics service initialized');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to initialize analytics',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Set the current user for analytics
  void setUserId(String? userId) {
    _currentUserId = userId;
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(userId: userId);
    }
    _log('User ID set: ${userId != null ? 'set' : 'cleared'}');
  }

  /// Set user properties
  void setUserProperties(AnalyticsUserProperties properties) {
    _userProperties = properties;
    _log('User properties updated');
  }

  /// Update specific user properties
  void updateUserProperty(String key, value) {
    final current = _userProperties?.customProperties ?? {};
    final updated = Map<String, dynamic>.from(current);
    updated[key] = value;
    _userProperties =
        _userProperties?.copyWith(customProperties: updated) ??
        AnalyticsUserProperties(customProperties: updated);
  }

  /// Track a screen view
  void trackScreenView(String screenName, {Map<String, dynamic>? properties}) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.screenView(
      id: _uuid.v4(),
      screenName: screenName,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      properties: properties,
    );

    _addEvent(event);

    // Update session
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        screenViewCount: _currentSession!.screenViewCount + 1,
        exitScreen: screenName,
      );
      if (_currentSession!.entryScreen == null) {
        _currentSession = _currentSession!.copyWith(entryScreen: screenName);
      }
    }

    _log('Screen view: $screenName');
  }

  /// Track a message sent event
  void trackMessageSent({
    required String roomId,
    required String messageType,
    bool hasAttachment = false,
    bool isReply = false,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.messageSent(
      id: _uuid.v4(),
      roomId: roomId,
      messageType: messageType,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      hasAttachment: hasAttachment,
      isReply: isReply,
    );

    _addEvent(event);
    _log('Message sent tracked');
  }

  /// Track a call event
  void trackCall({
    required AnalyticsEventType callEventType,
    required String roomId,
    required String callType,
    int? durationSeconds,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.call(
      id: _uuid.v4(),
      callEventType: callEventType,
      roomId: roomId,
      callType: callType,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      durationSeconds: durationSeconds,
    );

    _addEvent(event);
    _log('Call event tracked: ${callEventType.name}');
  }

  /// Track a room event
  void trackRoomEvent({
    required AnalyticsEventType roomEventType,
    required String roomId,
    required String roomType,
    int? memberCount,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.room(
      id: _uuid.v4(),
      roomEventType: roomEventType,
      roomId: roomId,
      roomType: roomType,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      memberCount: memberCount,
    );

    _addEvent(event);
    _log('Room event tracked: ${roomEventType.name}');
  }

  /// Track a feature usage event
  void trackFeatureUsed(
    String featureName, {
    Map<String, dynamic>? properties,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.featureUsed(
      id: _uuid.v4(),
      featureName: featureName,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      properties: properties,
    );

    _addEvent(event);
    _log('Feature used: $featureName');
  }

  /// Track a custom event
  void trackEvent(
    String eventName, {
    Map<String, dynamic>? properties,
    String? screenName,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.custom(
      id: _uuid.v4(),
      eventName: eventName,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      screenName: screenName,
      properties: properties,
    );

    _addEvent(event);
    _log('Custom event: $eventName');
  }

  /// Track an error event
  void trackError({
    required String errorType,
    required String errorMessage,
    String? screenName,
    StackTrace? stackTrace,
  }) {
    if (!_config.enabled) return;

    final event = AnalyticsEvent.error(
      id: _uuid.v4(),
      errorType: errorType,
      errorMessage: errorMessage,
      userId: _currentUserId,
      sessionId: _currentSession?.id,
      screenName: screenName,
      stackTrace: stackTrace?.toString(),
    );

    _addEvent(event);
    _log('Error tracked: $errorType');
  }

  /// Track user login
  void trackUserLogin({String? method}) {
    trackEvent(
      'user_login',
      properties: {
        if (method != null) 'method': method,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  /// Track user logout
  void trackUserLogout() {
    trackEvent(
      'user_logout',
      properties: {
        'session_duration_seconds': _currentSession?.durationSeconds,
        'events_in_session': _currentSession?.eventCount,
      },
    );
    _endSession();
    _startNewSession();
  }

  /// Track setting change
  void trackSettingChanged(String settingName, oldValue, newValue) {
    trackEvent(
      'setting_changed',
      properties: {
        'setting_name': settingName,
        'old_value': oldValue?.toString(),
        'new_value': newValue?.toString(),
      },
    );
  }

  /// Get current session
  AnalyticsSession? get currentSession => _currentSession;

  /// Get user properties
  AnalyticsUserProperties? get userProperties => _userProperties;

  /// Get pending event count
  int get pendingEventCount => _eventQueue.length;

  /// Manually flush events
  Future<void> flush() async {
    await _flushEvents();
  }

  /// End the current session and close the service
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    _endSession();
    await _flushEvents();
    await _savePendingEvents();

    _initialized = false;
    _log('Analytics service closed');
  }

  // Private methods

  void _startNewSession() {
    _currentSession = AnalyticsSession(
      id: _uuid.v4(),
      startTime: DateTime.now().toUtc(),
      userId: _currentUserId,
      deviceInfo: _getDeviceInfo(),
    );
    _log('New session started: ${_currentSession!.id}');
  }

  void _endSession() {
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        endTime: DateTime.now().toUtc(),
      );
      _log(
        'Session ended: ${_currentSession!.id}, duration: ${_currentSession!.durationSeconds}s',
      );
    }
  }

  void _addEvent(AnalyticsEvent event) {
    _eventQueue.add(event);

    // Update session event count
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        eventCount: _currentSession!.eventCount + 1,
      );
    }

    // Trim queue if needed
    while (_eventQueue.length > _config.maxStoredEvents) {
      _eventQueue.removeAt(0);
    }

    // Flush if batch size reached
    if (_eventQueue.length >= _config.batchSize) {
      _flushEvents();
    }
  }

  Future<void> _flushEvents() async {
    if (_eventQueue.isEmpty) return;

    final eventsToSend = List<AnalyticsEvent>.from(_eventQueue);

    try {
      // TODO(antinvestor): Send events to backend analytics service
      // For now, we just mark them as synced and clear
      // In production, this would send to your analytics backend:
      // await _sendEventsToBackend(eventsToSend);

      // Clear the sent events
      _eventQueue.removeWhere(
        (e) => eventsToSend.any((sent) => sent.id == e.id),
      );

      _log('Flushed ${eventsToSend.length} events');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to flush analytics events',
        error: e,
        stackTrace: stackTrace,
      );
      // Keep events in queue for retry
    }
  }

  Future<void> _savePendingEvents() async {
    if (_storagePath == null || _eventQueue.isEmpty) return;

    try {
      final file = File('$_storagePath/pending_events.json');
      final eventsJson = _eventQueue.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(eventsJson));
      _log('Saved ${_eventQueue.length} pending events');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to save pending events',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadPendingEvents() async {
    if (_storagePath == null) return;

    try {
      final file = File('$_storagePath/pending_events.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final eventsJson = jsonDecode(content) as List<dynamic>;
        for (final json in eventsJson) {
          _eventQueue.add(
            AnalyticsEvent.fromJson(json as Map<String, dynamic>),
          );
        }
        await file.delete();
        _log('Loaded ${_eventQueue.length} pending events');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load pending events',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic> _getDeviceInfo() {
    return {
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'is_debug': kDebugMode,
    };
  }

  void _log(String message) {
    if (_config.enableDebugLogging) {
      AppLogger.debug('Analytics: $message');
    }
  }
}

/// Provider for the analytics service
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final service = AnalyticsService(
    config: const AnalyticsConfig(enableDebugLogging: kDebugMode),
  );

  // Initialize on first access
  service.initialize();

  ref.onDispose(service.close);

  return service;
});
