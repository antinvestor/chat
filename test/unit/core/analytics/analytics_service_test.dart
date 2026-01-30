import 'package:flutter_test/flutter_test.dart';

import 'package:stawi/core/analytics/analytics_event.dart';
import 'package:stawi/core/analytics/analytics_service.dart';

void main() {
  group('AnalyticsService', () {
    late AnalyticsService analyticsService;

    setUp(() {
      analyticsService = AnalyticsService(
        config: const AnalyticsConfig(enabled: true, enableDebugLogging: false),
      );
    });

    group('configuration', () {
      test('can be disabled via config', () {
        final service = AnalyticsService(
          config: const AnalyticsConfig(enabled: false),
        );

        // When disabled, tracking should not add events
        service.trackEvent('test_event');
        expect(service.pendingEventCount, equals(0));
      });

      test('respects batch size configuration', () {
        const config = AnalyticsConfig(batchSize: 100);
        expect(config.batchSize, equals(100));
      });

      test('respects flush interval configuration', () {
        const config = AnalyticsConfig(flushIntervalSeconds: 120);
        expect(config.flushIntervalSeconds, equals(120));
      });
    });

    group('event tracking', () {
      test('trackEvent adds event to queue', () {
        analyticsService.trackEvent('test_event');
        expect(analyticsService.pendingEventCount, equals(1));
      });

      test('trackScreenView adds event to queue', () {
        analyticsService.trackScreenView('HomeScreen');
        expect(analyticsService.pendingEventCount, equals(1));
      });

      test('trackEvent with properties', () {
        analyticsService.trackEvent(
          'button_tap',
          properties: {'button_id': 'send_message'},
        );
        expect(analyticsService.pendingEventCount, equals(1));
      });

      test('trackMessageSent creates correct event', () {
        analyticsService.trackMessageSent(
          roomId: 'room-1',
          messageType: 'text',
          hasAttachment: false,
          isReply: true,
        );
        expect(analyticsService.pendingEventCount, equals(1));
      });

      test('trackFeatureUsed creates correct event', () {
        analyticsService.trackFeatureUsed(
          'starred_messages',
          properties: {'action': 'view'},
        );
        expect(analyticsService.pendingEventCount, equals(1));
      });

      test('trackError creates correct event', () {
        analyticsService.trackError(
          errorType: 'NetworkError',
          errorMessage: 'Connection timeout',
          screenName: 'ChatScreen',
        );
        expect(analyticsService.pendingEventCount, equals(1));
      });
    });

    group('user management', () {
      test('setUserId updates current user', () {
        analyticsService.setUserId('user-123');
        expect(analyticsService.currentSession?.userId, equals('user-123'));
      });

      test('setUserId can clear user', () {
        analyticsService.setUserId('user-123');
        analyticsService.setUserId(null);
        expect(analyticsService.currentSession?.userId, isNull);
      });

      test('setUserProperties updates properties', () {
        const properties = AnalyticsUserProperties(
          displayName: 'Test User',
          appVersion: '1.0.0',
        );
        analyticsService.setUserProperties(properties);
        expect(
          analyticsService.userProperties?.displayName,
          equals('Test User'),
        );
      });

      test('updateUserProperty adds custom property', () {
        analyticsService.updateUserProperty('premium_user', true);
        expect(
          analyticsService.userProperties?.customProperties?['premium_user'],
          isTrue,
        );
      });
    });

    group('session management', () {
      test('tracks screen view count in session', () {
        analyticsService.trackScreenView('Screen1');
        analyticsService.trackScreenView('Screen2');
        expect(analyticsService.currentSession?.screenViewCount, equals(2));
      });

      test('tracks event count in session', () {
        analyticsService.trackEvent('event1');
        analyticsService.trackEvent('event2');
        analyticsService.trackEvent('event3');
        expect(analyticsService.currentSession?.eventCount, equals(3));
      });

      test('tracks entry and exit screens', () {
        analyticsService.trackScreenView('EntryScreen');
        analyticsService.trackScreenView('MiddleScreen');
        analyticsService.trackScreenView('ExitScreen');
        expect(
          analyticsService.currentSession?.entryScreen,
          equals('EntryScreen'),
        );
        expect(
          analyticsService.currentSession?.exitScreen,
          equals('ExitScreen'),
        );
      });

      test('trackUserLogout resets session', () {
        analyticsService.trackEvent('event1');
        analyticsService.trackUserLogout();
        expect(analyticsService.currentSession?.eventCount, equals(0));
      });
    });

    group('setting tracking', () {
      test('trackSettingChanged records old and new values', () {
        analyticsService.trackSettingChanged('theme', 'light', 'dark');
        expect(analyticsService.pendingEventCount, equals(1));
      });
    });
  });

  group('AnalyticsEvent', () {
    test('screenView factory creates correct event', () {
      final event = AnalyticsEvent.screenView(
        id: 'event-1',
        screenName: 'HomeScreen',
        userId: 'user-1',
        sessionId: 'session-1',
      );

      expect(event.type, equals(AnalyticsEventType.screenView));
      expect(event.name, equals('screen_view'));
      expect(event.screenName, equals('HomeScreen'));
      expect(event.properties?['screen_name'], equals('HomeScreen'));
    });

    test('messageSent factory creates correct event', () {
      final event = AnalyticsEvent.messageSent(
        id: 'event-2',
        roomId: 'room-1',
        messageType: 'text',
        hasAttachment: true,
        isReply: false,
      );

      expect(event.type, equals(AnalyticsEventType.messageSent));
      expect(event.properties?['room_id'], equals('room-1'));
      expect(event.properties?['message_type'], equals('text'));
      expect(event.properties?['has_attachment'], isTrue);
      expect(event.properties?['is_reply'], isFalse);
    });

    test('error factory creates correct event', () {
      final event = AnalyticsEvent.error(
        id: 'event-3',
        errorType: 'NetworkError',
        errorMessage: 'Connection failed',
        screenName: 'ChatScreen',
      );

      expect(event.type, equals(AnalyticsEventType.errorOccurred));
      expect(event.properties?['error_type'], equals('NetworkError'));
      expect(event.properties?['error_message'], equals('Connection failed'));
    });

    test('featureUsed factory creates correct event', () {
      final event = AnalyticsEvent.featureUsed(
        id: 'event-4',
        featureName: 'starred_messages',
        properties: {'action': 'star'},
      );

      expect(event.type, equals(AnalyticsEventType.featureUsed));
      expect(event.properties?['feature_name'], equals('starred_messages'));
      expect(event.properties?['action'], equals('star'));
    });

    test('custom factory creates correct event', () {
      final event = AnalyticsEvent.custom(
        id: 'event-5',
        eventName: 'custom_action',
        properties: {'key': 'value'},
      );

      expect(event.type, equals(AnalyticsEventType.custom));
      expect(event.name, equals('custom_action'));
    });
  });

  group('AnalyticsSession', () {
    test('calculates duration correctly', () {
      final session = AnalyticsSession(
        id: 'session-1',
        startTime: DateTime.now().subtract(const Duration(minutes: 5)),
        endTime: DateTime.now(),
      );

      expect(session.durationSeconds, greaterThanOrEqualTo(299));
      expect(session.durationSeconds, lessThanOrEqualTo(301));
    });

    test('isActive returns true when no end time', () {
      final session = AnalyticsSession(
        id: 'session-1',
        startTime: DateTime.now(),
      );

      expect(session.isActive, isTrue);
    });

    test('isActive returns false when end time is set', () {
      final session = AnalyticsSession(
        id: 'session-1',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now(),
      );

      expect(session.isActive, isFalse);
    });
  });

  group('AnalyticsUserProperties', () {
    test('can create with all properties', () {
      final props = AnalyticsUserProperties(
        userId: 'user-1',
        displayName: 'Test User',
        email: 'test@example.com',
        phoneNumber: '+1234567890',
        accountCreatedAt: DateTime(2024, 1, 1),
        lastLoginAt: DateTime.now(),
        appVersion: '1.0.0',
        platform: 'android',
        deviceModel: 'Pixel 6',
        osVersion: '14',
        locale: 'en_US',
        totalRooms: 10,
        totalContacts: 50,
        customProperties: {'premium': true},
      );

      expect(props.userId, equals('user-1'));
      expect(props.displayName, equals('Test User'));
      expect(props.customProperties?['premium'], isTrue);
    });
  });

  group('AnalyticsEventType', () {
    test('all event types are defined', () {
      expect(AnalyticsEventType.values, isNotEmpty);
      expect(AnalyticsEventType.screenView, isNotNull);
      expect(AnalyticsEventType.messageSent, isNotNull);
      expect(AnalyticsEventType.callStarted, isNotNull);
      expect(AnalyticsEventType.roomCreated, isNotNull);
      expect(AnalyticsEventType.userLogin, isNotNull);
      expect(AnalyticsEventType.errorOccurred, isNotNull);
      expect(AnalyticsEventType.custom, isNotNull);
    });
  });

  group('AnalyticsConfig', () {
    test('has sensible defaults', () {
      const config = AnalyticsConfig();

      expect(config.enabled, isTrue);
      expect(config.batchSize, equals(50));
      expect(config.flushIntervalSeconds, equals(60));
      expect(config.maxStoredEvents, equals(1000));
      expect(config.enableDebugLogging, isFalse);
    });

    test('can be customized', () {
      const config = AnalyticsConfig(
        enabled: false,
        batchSize: 100,
        flushIntervalSeconds: 120,
        maxStoredEvents: 500,
        enableDebugLogging: true,
      );

      expect(config.enabled, isFalse);
      expect(config.batchSize, equals(100));
      expect(config.flushIntervalSeconds, equals(120));
      expect(config.maxStoredEvents, equals(500));
      expect(config.enableDebugLogging, isTrue);
    });
  });
}
