import 'package:antinvestor_api_device/antinvestor_api_device.dart' as pb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../networking/client.dart';
import 'e2e_encryption_service.dart';
import 'key_manager.dart';

/// Service for managing E2EE key exchange with the Device API
///
/// Handles:
/// - Uploading identity keys (curve25519, ed25519) on login
/// - Uploading one-time prekeys for session establishment
/// - Fetching recipient's keys for new conversations
/// - Sharing Megolm session keys with room members
class KeyExchangeService {
  KeyExchangeService(
    this._encryptionService,
    this._deviceClient,
    this._keyManager,
  );
  final E2EEncryptionService _encryptionService;
  final pb.DeviceServiceClient _deviceClient;
  final KeyManager _keyManager;

  /// Upload identity keys to the backend after login
  ///
  /// Should be called once after user authentication to publish
  /// the device's public keys for other users to initiate sessions.
  Future<void> uploadIdentityKeys() async {
    try {
      final deviceId = await _keyManager.getDeviceId();

      // Upload Curve25519 identity key (as base64-encoded bytes)
      await _deviceClient.addKey(
        pb.AddKeyRequest(
          deviceId: deviceId,
          keyType: pb.KeyType.CURVE25519_KEY,
          data: _stringToBytes(_encryptionService.identityKey),
        ),
      );

      // Upload Ed25519 signing key
      await _deviceClient.addKey(
        pb.AddKeyRequest(
          deviceId: deviceId,
          keyType: pb.KeyType.ED25519_KEY,
          data: _stringToBytes(_encryptionService.signingKey),
        ),
      );

      AppLogger.info('Identity keys uploaded', data: {'deviceId': deviceId});
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to upload identity keys',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Convert string to bytes for API
  List<int> _stringToBytes(String s) => s.codeUnits;

  /// Convert bytes to string from API
  String _bytesToString(List<int> bytes) => String.fromCharCodes(bytes);

  /// Upload one-time prekeys to the backend
  ///
  /// These keys are used by other users to establish new Olm sessions.
  /// The backend should manage key consumption and notify when more are needed.
  Future<void> uploadOneTimeKeys() async {
    try {
      final deviceId = await _keyManager.getDeviceId();
      final oneTimeKeys = _encryptionService.getOneTimeKeys();

      for (final entry in oneTimeKeys.entries) {
        await _deviceClient.addKey(
          pb.AddKeyRequest(
            deviceId: deviceId,
            keyType: pb.KeyType.CURVE25519_KEY,
            data: _stringToBytes(entry.value),
          ),
        );
      }

      // Mark keys as published so they won't be reused
      await _encryptionService.markKeysAsPublished();

      AppLogger.info(
        'One-time keys uploaded',
        data: {'deviceId': deviceId, 'count': oneTimeKeys.length},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to upload one-time keys',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get a recipient's keys for establishing a session
  ///
  /// Searches by device ID or query string (backend may support profile lookup).
  /// Returns the recipient's Curve25519 identity key for key exchange.
  Future<String?> getRecipientKey(String deviceIdOrQuery) async {
    try {
      final response = await _deviceClient.searchKey(
        pb.SearchKeyRequest(
          query: deviceIdOrQuery,
          keyTypes: [pb.KeyType.CURVE25519_KEY],
        ),
      );

      if (response.data.isEmpty) {
        AppLogger.warning(
          'No keys found for recipient',
          data: {'query': deviceIdOrQuery},
        );
        return null;
      }

      // Return the first available key
      final keyObj = response.data.first;
      AppLogger.debug(
        'Retrieved recipient key',
        data: {'query': deviceIdOrQuery, 'keyId': keyObj.id},
      );

      return _bytesToString(keyObj.key);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get recipient key',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Share Megolm session key with room members
  ///
  /// When creating a new group session, the session key needs to be
  /// shared with all room members so they can decrypt messages.
  Future<void> shareSessionKey({
    required String roomId,
    required List<String> memberProfileIds,
  }) async {
    try {
      final sessionKey = _encryptionService.getGroupSessionKey(roomId);
      final sessionId = _encryptionService.getGroupSessionId(roomId);

      if (sessionId == null) {
        AppLogger.warning('No session to share', data: {'roomId': roomId});
        return;
      }

      // In a full implementation, session keys would be:
      // 1. Encrypted to each member's Curve25519 key
      // 2. Sent via a key-sharing message in the room
      // For now, log the intent
      AppLogger.info(
        'Session key sharing requested',
        data: {
          'roomId': roomId,
          'sessionId': sessionId,
          'memberCount': memberProfileIds.length,
          'hasSessionKey': sessionKey.isNotEmpty,
        },
      );

      // TODO: Implement actual key sharing via room messages
      // This would involve:
      // - For each member, encrypt session key with their curve25519 key
      // - Send as m.room_key type message
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to share session key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Process an incoming session key from another user
  ///
  /// When receiving a shared session key, add it as an inbound session.
  Future<void> receiveSessionKey({
    required String roomId,
    required String sessionId,
    required String sessionKey,
    required String senderKey,
  }) async {
    try {
      await _encryptionService.addInboundGroupSession(
        roomId,
        sessionId,
        sessionKey,
        senderKey: senderKey,
      );

      AppLogger.info(
        'Received and stored session key',
        data: {
          'roomId': roomId,
          'sessionId': sessionId,
          'senderKey': senderKey.substring(0, 8),
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to process received session key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Provider for KeyExchangeService
final keyExchangeServiceProvider = FutureProvider<KeyExchangeService>((
  ref,
) async {
  final encryptionService = ref.watch(e2eEncryptionServiceProvider);
  final deviceClient = await ref.watch(deviceServiceClientProvider.future);
  final keyManager = ref.watch(keyManagerProvider);

  // Ensure encryption service is initialized
  await encryptionService.initialize();

  return KeyExchangeService(encryptionService, deviceClient, keyManager);
});
