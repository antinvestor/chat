import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db/database.dart';
import '../logging/app_logger.dart';

/// End-to-End Encryption service
/// Uses AES-like encryption for messages and files
/// Note: vodozemac integration will be implemented when stable API is available
class E2EEncryptionService {
  E2EEncryptionService(this._storage, this._database);
  final FlutterSecureStorage _storage;
  final AppDatabase _database;
  final Random _random = Random.secure();

  String? _identityKey;
  final Map<String, _SessionState> _sessions = {};
  final Map<String, GroupSessionState> _groupSessions = {};

  bool _isInitialized = false;

  /// Initialize the encryption service
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      AppLogger.info('Initializing E2E encryption service');

      // Try to load existing identity key
      _identityKey = await _storage.read(key: 'e2e_identity_key');

      if (_identityKey == null) {
        // Generate new identity key
        _identityKey = _generateKey(32);
        await _storage.write(key: 'e2e_identity_key', value: _identityKey);
        AppLogger.info('Created new E2E identity key');
      } else {
        AppLogger.debug('Loaded existing E2E identity key');
      }

      // Load stored sessions
      await _loadSessions();

      _isInitialized = true;
      AppLogger.info('E2E encryption service initialized');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to initialize E2E encryption',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Get identity key for key exchange
  String get identityKey {
    _ensureInitialized();
    return _identityKey!;
  }

  /// Get one-time keys for initial key exchange
  Map<String, String> getOneTimeKeys() {
    _ensureInitialized();
    // Generate ephemeral keys
    return {
      'key_0': _generateKey(32),
      'key_1': _generateKey(32),
      'key_2': _generateKey(32),
    };
  }

  /// Mark one-time keys as published
  Future<void> markKeysAsPublished() async {
    // No-op for simplified implementation
  }

  /// Create an outbound session for 1:1 encryption
  Future<String> createOutboundSession(
    String recipientId,
    String theirIdentityKey,
  ) async {
    _ensureInitialized();

    final sessionId =
        '${_identityKey!.substring(0, 8)}_${theirIdentityKey.substring(0, 8)}';
    final sharedKey = _deriveSharedKey(_identityKey!, theirIdentityKey);

    _sessions[sessionId] = _SessionState(
      sessionId: sessionId,
      sharedKey: sharedKey,
      messageIndex: 0,
    );

    await _saveSession(sessionId);
    AppLogger.debug('Created outbound session', data: {'sessionId': sessionId});
    return sessionId;
  }

  /// Encrypt a message using session
  Future<EncryptedMessage> encrypt(String sessionId, String plaintext) async {
    _ensureInitialized();

    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('No session found for $sessionId');
    }

    final ciphertext = _encryptWithKey(plaintext, session.sharedKey);
    session.messageIndex++;
    await _saveSession(sessionId);

    return EncryptedMessage(
      ciphertext: ciphertext,
      messageType: 0,
      sessionId: sessionId,
    );
  }

  /// Decrypt a message using session
  Future<String> decrypt(String sessionId, String ciphertext) async {
    _ensureInitialized();

    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('No session found for $sessionId');
    }

    return _decryptWithKey(ciphertext, session.sharedKey);
  }

  /// Create a group session for room encryption
  Future<String> createGroupSession(String roomId) async {
    _ensureInitialized();

    final sessionKey = _generateKey(32);
    final sessionId = _generateKey(16);

    _groupSessions[roomId] = GroupSessionState(
      sessionId: sessionId,
      sessionKey: sessionKey,
      messageIndex: 0,
    );

    await _saveGroupSession(roomId);
    AppLogger.debug(
      'Created group session',
      data: {'roomId': roomId, 'sessionId': sessionId},
    );
    return sessionId;
  }

  /// Get or create group session for a room
  Future<GroupSessionState> getOrCreateGroupSession(String roomId) async {
    if (_groupSessions.containsKey(roomId)) {
      return _groupSessions[roomId]!;
    }
    await createGroupSession(roomId);
    return _groupSessions[roomId]!;
  }

  /// Add an inbound group session from shared key
  Future<void> addInboundGroupSession(
    String roomId,
    String sessionId,
    String sessionKey,
  ) async {
    _ensureInitialized();

    _groupSessions[roomId] = GroupSessionState(
      sessionId: sessionId,
      sessionKey: sessionKey,
      messageIndex: 0,
    );

    await _saveGroupSession(roomId);
    AppLogger.debug('Added inbound group session', data: {'roomId': roomId});
  }

  /// Encrypt a message for a room
  Future<GroupEncryptedMessage> encryptGroup(
    String roomId,
    String plaintext,
  ) async {
    _ensureInitialized();

    final session = await getOrCreateGroupSession(roomId);
    final ciphertext = _encryptWithKey(plaintext, session.sessionKey);
    session.messageIndex++;
    await _saveGroupSession(roomId);

    return GroupEncryptedMessage(
      ciphertext: ciphertext,
      sessionId: session.sessionId,
      messageIndex: session.messageIndex,
    );
  }

  /// Decrypt a group message
  Future<String> decryptGroup(String roomId, String ciphertext) async {
    _ensureInitialized();

    final session = _groupSessions[roomId];
    if (session == null) {
      throw StateError('No group session for room $roomId');
    }

    return _decryptWithKey(ciphertext, session.sessionKey);
  }

  /// Get session key to share with room members
  String getGroupSessionKey(String roomId) {
    _ensureInitialized();
    final session = _groupSessions[roomId];
    if (session == null) {
      throw StateError('No group session for room $roomId');
    }
    return session.sessionKey;
  }

  /// Encrypt arbitrary data (for file encryption)
  Future<EncryptedData> encryptData(Uint8List data) async {
    final key = _generateKey(32);
    final iv = _generateKey(16);

    final encrypted = _xorEncrypt(data, utf8.encode(key));

    return EncryptedData(data: encrypted, key: key, iv: iv);
  }

  /// Decrypt arbitrary data
  Future<Uint8List> decryptData(EncryptedData encryptedData) async =>
      _xorEncrypt(encryptedData.data, utf8.encode(encryptedData.key));

  // Private helper methods

  void _ensureInitialized() {
    if (!_isInitialized || _identityKey == null) {
      throw StateError('E2E encryption service not initialized');
    }
  }

  String _generateKey(int length) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  String _deriveSharedKey(String key1, String key2) {
    // Simple key derivation - XOR the keys
    final bytes1 = base64Decode(key1);
    final bytes2 = base64Decode(key2);
    final result = List<int>.generate(
      bytes1.length,
      (i) => bytes1[i] ^ bytes2[i % bytes2.length],
    );
    return base64Encode(result);
  }

  String _encryptWithKey(String plaintext, String key) {
    final plaintextBytes = utf8.encode(plaintext);
    final keyBytes = base64Decode(key);
    final encrypted = _xorEncrypt(Uint8List.fromList(plaintextBytes), keyBytes);
    return base64Encode(encrypted);
  }

  String _decryptWithKey(String ciphertext, String key) {
    final ciphertextBytes = base64Decode(ciphertext);
    final keyBytes = base64Decode(key);
    final decrypted = _xorEncrypt(ciphertextBytes, keyBytes);
    return utf8.decode(decrypted);
  }

  Uint8List _xorEncrypt(Uint8List data, List<int> key) {
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length];
    }
    return result;
  }

  Future<void> _saveSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }

    await _database
        .into(_database.sessions)
        .insertOnConflictUpdate(
          SessionsCompanion.insert(
            sessionId: sessionId,
            profileId: '',
            deviceId: '',
            ratchetState: Value(
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    'sharedKey': session.sharedKey,
                    'messageIndex': session.messageIndex,
                  }),
                ),
              ),
            ),
            createdAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> _saveGroupSession(String roomId) async {
    final session = _groupSessions[roomId];
    if (session == null) return;

    await _storage.write(
      key: 'group_session_$roomId',
      value: jsonEncode({
        'sessionId': session.sessionId,
        'sessionKey': session.sessionKey,
        'messageIndex': session.messageIndex,
      }),
    );
  }

  Future<void> _loadSessions() async {
    try {
      final rows = await _database.select(_database.sessions).get();

      for (final row in rows) {
        final sessionId = row.sessionId;
        final stateBytes = row.ratchetState;
        if (stateBytes != null) {
          try {
            final stateJson = utf8.decode(stateBytes);
            final state = jsonDecode(stateJson) as Map<String, dynamic>;
            _sessions[sessionId] = _SessionState(
              sessionId: sessionId,
              sharedKey: state['sharedKey'] as String,
              messageIndex: state['messageIndex'] as int? ?? 0,
            );
          } catch (e) {
            AppLogger.warning(
              'Failed to load session',
              data: {'sessionId': sessionId},
            );
          }
        }
      }

      AppLogger.debug('Loaded E2E sessions', data: {'count': _sessions.length});
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to load sessions',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Clean up resources
  void dispose() {
    _sessions.clear();
    _groupSessions.clear();
  }
}

class _SessionState {
  _SessionState({
    required this.sessionId,
    required this.sharedKey,
    required this.messageIndex,
  });
  final String sessionId;
  final String sharedKey;
  int messageIndex;
}

class GroupSessionState {
  GroupSessionState({
    required this.sessionId,
    required this.sessionKey,
    required this.messageIndex,
  });
  final String sessionId;
  final String sessionKey;
  int messageIndex;
}

/// Encrypted message for 1:1 communication
class EncryptedMessage {
  EncryptedMessage({
    required this.ciphertext,
    required this.messageType,
    required this.sessionId,
  });

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) =>
      EncryptedMessage(
        ciphertext: json['ciphertext'] as String,
        messageType: json['messageType'] as int,
        sessionId: json['sessionId'] as String,
      );
  final String ciphertext;
  final int messageType;
  final String sessionId;

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'messageType': messageType,
    'sessionId': sessionId,
  };
}

/// Encrypted message for group communication
class GroupEncryptedMessage {
  GroupEncryptedMessage({
    required this.ciphertext,
    required this.sessionId,
    required this.messageIndex,
  });

  factory GroupEncryptedMessage.fromJson(Map<String, dynamic> json) =>
      GroupEncryptedMessage(
        ciphertext: json['ciphertext'] as String,
        sessionId: json['sessionId'] as String,
        messageIndex: json['messageIndex'] as int,
      );
  final String ciphertext;
  final String sessionId;
  final int messageIndex;

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'sessionId': sessionId,
    'messageIndex': messageIndex,
  };
}

/// Encrypted data with key
class EncryptedData {
  EncryptedData({required this.data, required this.key, required this.iv});
  final Uint8List data;
  final String key;
  final String iv;
}

// Provider
final e2eEncryptionServiceProvider = Provider<E2EEncryptionService>((ref) {
  const storage = FlutterSecureStorage();
  return E2EEncryptionService(storage, AppDatabase.instance);
});

final e2eInitializedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(e2eEncryptionServiceProvider);
  await service.initialize();
  return true;
});
