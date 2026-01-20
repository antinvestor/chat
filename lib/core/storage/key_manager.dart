import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Provider for KeyManager
final keyManagerProvider = Provider<KeyManager>((ref) {
  return KeyManager();
});

/// Manages secure storage of keys and device identifiers
///
/// Handles:
/// - Device ID generation and storage
/// - Secure storage of sensitive data
class KeyManager {
  static const _deviceIdKey = 'device_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Get or create a unique device ID
  ///
  /// The device ID is generated once and stored securely.
  /// It persists across app reinstalls on iOS (keychain) but not on Android.
  Future<String> getDeviceId() async {
    var deviceId = await _storage.read(key: _deviceIdKey);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: deviceId);
    }

    return deviceId;
  }

  /// Delete all stored keys (call on logout/account deletion)
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
