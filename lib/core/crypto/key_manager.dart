import 'dart:convert';
import 'package:vodozemac/vodozemac.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyManager {
  final FlutterSecureStorage _storage;
  
  // Cache keys in memory
  IdentityKeyPair? _identityKeyPair;
  SignedPreKey? _signedPreKey;
  List<OneTimePreKey> _oneTimePreKeys = [];

  KeyManager(this._storage);

  Future<void> init() async {
    // Try to load from storage
    final idKeyStr = await _storage.read(key: 'identity_key');
    if (idKeyStr != null) {
      // Assuming pickle takes a key string
      _identityKeyPair = IdentityKeyPair.fromPickle(idKeyStr, "secret_key"); 
    } else {
      // Generate new
      _identityKeyPair = IdentityKeyPair.generate();
      await _storage.write(key: 'identity_key', value: _identityKeyPair!.pickle("secret_key"));
    }

    // Similar logic for SignedPreKey...
    // For now, just generate if missing
    if (_signedPreKey == null) {
       _signedPreKey = _identityKeyPair!.generateSignedPreKey(1); // Assuming ID is int
    }
  }

  IdentityKey get identityKey => _identityKeyPair!.publicKey;
  
  // Helper to get public bundle to upload
  Map<String, dynamic> getPublicBundle() {
    return {
      'identity_key': base64Encode(_identityKeyPair!.publicKey.toBytes()),
      'signed_pre_key': {
        'id': _signedPreKey!.id.value,
        'key': base64Encode(_signedPreKey!.publicKey.toBytes()),
        'signature': base64Encode(_signedPreKey!.signature.toBytes()),
      },
      // 'one_time_pre_keys': ...
    };
  }
}
