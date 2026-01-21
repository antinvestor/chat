import 'package:chat/features/calls/domain/call_stats.dart';
import 'package:chat/features/calls/services/turn_credentials_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnCredentials', () {
    test('isExpired returns false for future expiry', () {
      final creds = TurnCredentials(
        url: 'turn:test.com:3478',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(creds.isExpired, isFalse);
    });

    test('isExpired returns true for past expiry', () {
      final creds = TurnCredentials(
        url: 'turn:test.com:3478',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(creds.isExpired, isTrue);
    });

    test('isExpired returns true when expiring within 5 minutes', () {
      final creds = TurnCredentials(
        url: 'turn:test.com:3478',
        expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      );

      expect(creds.isExpired, isTrue);
    });

    test('isExpired returns false when more than 5 minutes until expiry', () {
      final creds = TurnCredentials(
        url: 'turn:test.com:3478',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );

      expect(creds.isExpired, isFalse);
    });

    test('toIceServer returns correct structure with credentials', () {
      final creds = TurnCredentials(
        url: 'turn:example.com:3478',
        username: 'user',
        credential: 'pass',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final iceServer = creds.toIceServer();

      expect(iceServer['urls'], equals('turn:example.com:3478'));
      expect(iceServer['username'], equals('user'));
      expect(iceServer['credential'], equals('pass'));
    });

    test('toIceServer returns structure without credentials when not set', () {
      final creds = TurnCredentials(
        url: 'stun:example.com:3478',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final iceServer = creds.toIceServer();

      expect(iceServer['urls'], equals('stun:example.com:3478'));
      expect(iceServer.containsKey('username'), isFalse);
      expect(iceServer.containsKey('credential'), isFalse);
    });

    test('toIceServer returns only urls when username is null', () {
      final creds = TurnCredentials(
        url: 'turn:example.com:3478',
        credential: 'pass',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final iceServer = creds.toIceServer();

      expect(iceServer['urls'], equals('turn:example.com:3478'));
      expect(iceServer.containsKey('username'), isFalse);
    });

    test('toIceServer returns only urls when credential is null', () {
      final creds = TurnCredentials(
        url: 'turn:example.com:3478',
        username: 'user',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final iceServer = creds.toIceServer();

      expect(iceServer['urls'], equals('turn:example.com:3478'));
      expect(iceServer.containsKey('credential'), isFalse);
    });
  });

  group('TurnCredentialsService static servers', () {
    test('turnCredentialsServiceProvider is available', () {
      expect(turnCredentialsServiceProvider, isNotNull);
    });
  });

  group('CallQualityService BitrateConfig integration', () {
    test('excellent quality returns max bitrate', () {
      final bitrate = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.excellent,
      );

      expect(bitrate, equals(BitrateConfig.maxVideoBitrate));
    });

    test('veryPoor quality returns reduced bitrate above minimum', () {
      final bitrate = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.veryPoor,
      );

      // veryPoor returns 25% of max, which is above minimum
      final expectedBitrate = (BitrateConfig.maxVideoBitrate * 0.25).round();
      expect(bitrate, equals(expectedBitrate));
      expect(bitrate, greaterThanOrEqualTo(BitrateConfig.minVideoBitrate));
    });

    test('bitrate decreases as quality degrades', () {
      final excellent = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.excellent,
      );
      final good = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.good,
      );
      final fair = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.fair,
      );
      final poor = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.poor,
      );
      final veryPoor = BitrateConfig.getRecommendedVideoBitrate(
        ConnectionQuality.veryPoor,
      );

      expect(excellent, greaterThan(good));
      expect(good, greaterThan(fair));
      expect(fair, greaterThanOrEqualTo(poor));
      expect(poor, greaterThan(veryPoor));
    });

    test('frame rate for excellent quality is 30 fps', () {
      final fps = BitrateConfig.getRecommendedFrameRate(
        ConnectionQuality.excellent,
      );

      expect(fps, equals(30));
    });

    test('frame rate for veryPoor quality is minimum 10 fps', () {
      final fps = BitrateConfig.getRecommendedFrameRate(
        ConnectionQuality.veryPoor,
      );

      expect(fps, greaterThanOrEqualTo(10));
    });

    test('frame rate decreases as quality degrades', () {
      final excellent = BitrateConfig.getRecommendedFrameRate(
        ConnectionQuality.excellent,
      );
      final poor = BitrateConfig.getRecommendedFrameRate(
        ConnectionQuality.poor,
      );

      expect(excellent, greaterThan(poor));
    });
  });

  group('CallQualityService Quality Calculation', () {
    test('excellent quality for low RTT and no packet loss', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 30,
        packetLossPercent: 0.5,
        jitterMs: 10,
      );

      expect(quality, equals(ConnectionQuality.excellent));
    });

    test('good quality for moderate RTT', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 80,
        packetLossPercent: 1.5,
        jitterMs: 20,
      );

      expect(quality, equals(ConnectionQuality.good));
    });

    test('fair quality for higher RTT', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 180,
        packetLossPercent: 3.5,
        jitterMs: 50,
      );

      expect(quality, equals(ConnectionQuality.fair));
    });

    test('poor quality for high RTT and packet loss', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 350,
        packetLossPercent: 7,
        jitterMs: 100,
      );

      expect(quality, equals(ConnectionQuality.poor));
    });

    test('veryPoor quality for extreme conditions', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 600,
        packetLossPercent: 15,
        jitterMs: 200,
      );

      expect(quality, equals(ConnectionQuality.veryPoor));
    });

    test('high packet loss alone causes veryPoor quality', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 50,
        packetLossPercent: 20,
        jitterMs: 10,
      );

      expect(quality, equals(ConnectionQuality.veryPoor));
    });

    test('high RTT alone causes veryPoor quality', () {
      final quality = CallStatsQuality.calculateQuality(
        roundTripTimeMs: 600,
        packetLossPercent: 0.5,
        jitterMs: 10,
      );

      expect(quality, equals(ConnectionQuality.veryPoor));
    });
  });

  group('CallStats video quality assessment', () {
    test('isVideoQualityAcceptable true for excellent', () {
      const stats = CallStats(quality: ConnectionQuality.excellent);
      expect(stats.isVideoQualityAcceptable, isTrue);
    });

    test('isVideoQualityAcceptable true for good', () {
      const stats = CallStats(quality: ConnectionQuality.good);
      expect(stats.isVideoQualityAcceptable, isTrue);
    });

    test('isVideoQualityAcceptable true for fair', () {
      const stats = CallStats(quality: ConnectionQuality.fair);
      expect(stats.isVideoQualityAcceptable, isTrue);
    });

    test('isVideoQualityAcceptable false for poor', () {
      const stats = CallStats(quality: ConnectionQuality.poor);
      expect(stats.isVideoQualityAcceptable, isFalse);
    });

    test('isVideoQualityAcceptable false for veryPoor', () {
      const stats = CallStats(quality: ConnectionQuality.veryPoor);
      expect(stats.isVideoQualityAcceptable, isFalse);
    });
  });

  group('CallStats warning conditions', () {
    test('shouldShowWarning false for excellent quality', () {
      const stats = CallStats(quality: ConnectionQuality.excellent);
      expect(stats.shouldShowWarning, isFalse);
    });

    test('shouldShowWarning false for good quality', () {
      const stats = CallStats(quality: ConnectionQuality.good);
      expect(stats.shouldShowWarning, isFalse);
    });

    test('shouldShowWarning true for poor quality', () {
      const stats = CallStats(quality: ConnectionQuality.poor);
      expect(stats.shouldShowWarning, isTrue);
    });

    test('shouldShowWarning true for veryPoor quality', () {
      const stats = CallStats(quality: ConnectionQuality.veryPoor);
      expect(stats.shouldShowWarning, isTrue);
    });

    test('shouldShowWarning true when reconnecting', () {
      const stats = CallStats(
        quality: ConnectionQuality.good,
        isReconnecting: true,
      );
      expect(stats.shouldShowWarning, isTrue);
    });

    test('shouldShowWarning false when video disabled but quality is fair', () {
      // Note: shouldShowWarning only checks quality and isReconnecting,
      // not isVideoDisabledDueToPoorConnection (that's handled separately in UI)
      const stats = CallStats(
        quality: ConnectionQuality.fair,
        isVideoDisabledDueToPoorConnection: true,
      );
      expect(stats.shouldShowWarning, isFalse);
    });
  });

  group('CallStats description strings', () {
    test('qualityDescription for all levels', () {
      expect(
        const CallStats(
          quality: ConnectionQuality.excellent,
        ).qualityDescription,
        equals('Excellent'),
      );
      expect(
        const CallStats(quality: ConnectionQuality.good).qualityDescription,
        equals('Good'),
      );
      expect(
        const CallStats(quality: ConnectionQuality.fair).qualityDescription,
        equals('Fair'),
      );
      expect(
        const CallStats(quality: ConnectionQuality.poor).qualityDescription,
        equals('Poor'),
      );
      expect(
        const CallStats(quality: ConnectionQuality.veryPoor).qualityDescription,
        equals('Very Poor'),
      );
      expect(
        const CallStats().qualityDescription,
        equals('Checking...'),
      );
    });

    test('latencyDescription for various RTT values', () {
      expect(
        const CallStats(roundTripTimeMs: 30).latencyDescription,
        equals('< 50ms'),
      );
      expect(
        const CallStats(roundTripTimeMs: 100).latencyDescription,
        equals('100ms'),
      );
      expect(
        const CallStats(roundTripTimeMs: 200).latencyDescription,
        equals('200ms (high)'),
      );
      expect(
        const CallStats(roundTripTimeMs: 400).latencyDescription,
        equals('400ms (very high)'),
      );
    });

    test('packetLossDescription for various loss values', () {
      expect(
        const CallStats(packetLossPercent: 0.5).packetLossDescription,
        equals('< 1%'),
      );
      expect(
        const CallStats(packetLossPercent: 2).packetLossDescription,
        equals('2.0%'),
      );
      expect(
        const CallStats(packetLossPercent: 4).packetLossDescription,
        equals('4.0% (high)'),
      );
      expect(
        const CallStats(packetLossPercent: 8).packetLossDescription,
        equals('8.0% (very high)'),
      );
    });
  });

  group('CallStats copyWith', () {
    test('copyWith updates specified fields', () {
      const original = CallStats(
        roundTripTimeMs: 50,
        quality: ConnectionQuality.good,
      );

      final updated = original.copyWith(
        roundTripTimeMs: 100,
        quality: ConnectionQuality.fair,
      );

      expect(updated.roundTripTimeMs, equals(100));
      expect(updated.quality, equals(ConnectionQuality.fair));
    });

    test('copyWith preserves unspecified fields', () {
      const original = CallStats(
        roundTripTimeMs: 50,
        jitterMs: 10,
        packetLossPercent: 1,
        quality: ConnectionQuality.good,
      );

      final updated = original.copyWith(quality: ConnectionQuality.fair);

      expect(updated.roundTripTimeMs, equals(50));
      expect(updated.jitterMs, equals(10));
      expect(updated.packetLossPercent, equals(1.0));
      expect(updated.quality, equals(ConnectionQuality.fair));
    });

    test('copyWith can update reconnection state', () {
      const original = CallStats();

      final updated = original.copyWith(
        isReconnecting: true,
        reconnectionAttempts: 2,
      );

      expect(updated.isReconnecting, isTrue);
      expect(updated.reconnectionAttempts, equals(2));
    });
  });
}
