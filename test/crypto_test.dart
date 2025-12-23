import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:chat/core/crypto/key_manager.dart';

class MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('KeyManager compilation check', () {
    final storage = MockStorage();
    final manager = KeyManager(storage);
    expect(manager, isNotNull);
  });
}
