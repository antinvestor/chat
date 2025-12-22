import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Repository for tracking onboarding state
class OnboardingRepository {
  static const _contactsSyncedKey = 'contacts_synced';
  final FlutterSecureStorage _storage;

  OnboardingRepository(this._storage);

  /// Check if contacts have been synced
  Future<bool> hasContactsSynced() async {
    final value = await _storage.read(key: _contactsSyncedKey);
    return value == 'true';
  }

  /// Mark contacts as synced
  Future<void> markContactsSynced() async {
    await _storage.write(key: _contactsSyncedKey, value: 'true');
  }

  /// Reset onboarding state (for testing or logout)
  Future<void> reset() async {
    await _storage.delete(key: _contactsSyncedKey);
  }
}

/// Provider for OnboardingRepository
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(const FlutterSecureStorage());
});

/// Provider to check if contacts sync is needed
final needsContactSyncProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(onboardingRepositoryProvider);
  final hasSynced = await repo.hasContactsSynced();
  return !hasSynced;
});
