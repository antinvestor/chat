import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/networking/certificate_pinning.dart';

void main() {
  group('CertificatePinning', () {
    late CertificatePinning certificatePinning;

    setUp(() {
      certificatePinning = CertificatePinning();
    });

    group('pinnedHosts', () {
      test('returns list of configured hosts', () {
        final hosts = certificatePinning.pinnedHosts;

        expect(hosts, isNotEmpty);
        expect(hosts, contains('chat.antinvestor.com'));
        expect(hosts, contains('gateway.antinvestor.com'));
        expect(hosts, contains('devices.antinvestor.com'));
        expect(hosts, contains('files.antinvestor.com'));
        expect(hosts, contains('profile.antinvestor.com'));
        expect(hosts, contains('oauth2.antinvestor.com'));
      });
    });

    group('hasPinsConfigured', () {
      test('returns true for configured host', () {
        expect(certificatePinning.hasPinsConfigured('chat.antinvestor.com'), isTrue);
      });

      test('returns false for unconfigured host', () {
        expect(certificatePinning.hasPinsConfigured('unknown.example.com'), isFalse);
      });
    });

    group('createPinnedHttpClient', () {
      test('creates an HttpClient', () {
        final httpClient = certificatePinning.createPinnedHttpClient();

        expect(httpClient, isNotNull);
        // Clean up
        httpClient.close();
      });

      // Note: badCertificateCallback getter is not accessible in test environment
      // The callback is set internally during createPinnedHttpClient()
    });

    group('updatePins', () {
      test('adds new pins for a host', () {
        const host = 'new.example.com';
        final pins = ['pin1', 'pin2'];

        certificatePinning.updatePins(host, pins);

        expect(certificatePinning.hasPinsConfigured(host), isTrue);
        expect(certificatePinning.pinnedHosts, contains(host));
      });

      test('does not update pins with empty list', () {
        const host = 'empty.example.com';

        certificatePinning.updatePins(host, []);

        expect(certificatePinning.hasPinsConfigured(host), isFalse);
      });
    });

    group('certificatePinningProvider', () {
      test('provider is available', () {
        expect(certificatePinningProvider, isNotNull);
      });
    });
  });
}
