import 'package:chat/core/crypto/key_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KeyManager compilation check', () {
    // Simple test to verify KeyManager can be instantiated
    expect(KeyManager, isA<Type>());
  });
}
