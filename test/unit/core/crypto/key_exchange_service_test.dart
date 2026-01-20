import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/crypto/key_exchange_service.dart';
import 'package:chat/core/crypto/key_manager.dart';

void main() {
  group('KeyExchangeService', () {
    group('keyExchangeServiceProvider', () {
      test('provider is defined', () {
        expect(keyExchangeServiceProvider, isNotNull);
      });
    });
  });

  group('KeyManager', () {
    group('keyManagerProvider', () {
      test('provider is defined', () {
        expect(keyManagerProvider, isNotNull);
      });
    });
  });
}
