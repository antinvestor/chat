import 'dart:async';
import 'dart:convert';

import 'package:antinvestor_api_common/antinvestor_api_common.dart' show TokenManager;
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart' as pb;
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart';
import 'package:connectrpc/connect.dart' as connect;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as flutter_contacts;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';

// Sync metadata keys
const _kContactsHashKey = 'roster_contacts_hash';
const _kLastSyncTimeKey = 'roster_last_sync';

/// Contact type enum matching the server's ContactType
enum RosterContactType {
  email(0),
  msisdn(1);

  final int value;
  const RosterContactType(this.value);

  static RosterContactType fromValue(int value) {
    return RosterContactType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RosterContactType.email,
    );
  }

  static RosterContactType fromProto(pb.ContactType type) {
    return type == pb.ContactType.MSISDN ? msisdn : email;
  }
}

/// Local roster entry model
class RosterEntry {
  final String id;
  final String profileId;
  final String? contactId;
  final RosterContactType contactType;
  final String contactDetail;
  final bool isVerified;
  final String? displayName;
  final bool isBlocked;
  final DateTime? syncedAt;
  final DateTime? createdAt;

  RosterEntry({
    required this.id,
    required this.profileId,
    this.contactId,
    required this.contactType,
    required this.contactDetail,
    this.isVerified = false,
    this.displayName,
    this.isBlocked = false,
    this.syncedAt,
    this.createdAt,
  });

  factory RosterEntry.fromDbRow(RosterData row) {
    return RosterEntry(
      id: row.id,
      profileId: row.profileId,
      contactId: row.contactId,
      contactType: RosterContactType.fromValue(row.contactType),
      contactDetail: row.contactDetail,
      isVerified: row.isVerified,
      displayName: row.displayName,
      isBlocked: row.isBlocked,
      syncedAt: row.syncedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.syncedAt!)
          : null,
      createdAt: row.createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.createdAt!)
          : null,
    );
  }

  factory RosterEntry.fromProto(
    pb.RosterObject roster, {
    String? localDisplayName,
  }) {
    final contact = roster.hasContact() ? roster.contact : null;
    return RosterEntry(
      id: roster.id,
      profileId: roster.profileId,
      contactId: contact?.id,
      contactType: contact != null
          ? RosterContactType.fromProto(contact.type)
          : RosterContactType.email,
      contactDetail: contact?.detail ?? '',
      isVerified: contact?.verified ?? false,
      displayName: localDisplayName ?? contact?.detail ?? roster.profileId,
      syncedAt: DateTime.now(),
    );
  }

  RosterCompanion toCompanion() {
    return RosterCompanion(
      id: Value(id),
      profileId: Value(profileId),
      contactId: Value(contactId),
      contactType: Value(contactType.value),
      contactDetail: Value(contactDetail),
      isVerified: Value(isVerified),
      displayName: Value(displayName),
      isBlocked: Value(isBlocked),
      syncedAt: Value(syncedAt?.millisecondsSinceEpoch),
      createdAt: Value(createdAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch),
    );
  }
}

/// Callback for sync progress updates
typedef SyncProgressCallback = void Function(SyncProgress progress);

/// Sync progress information
class SyncProgress {
  final SyncState state;
  final int totalContacts;
  final int processedContacts;
  final int foundOnPlatform;
  final String? message;

  const SyncProgress({
    required this.state,
    this.totalContacts = 0,
    this.processedContacts = 0,
    this.foundOnPlatform = 0,
    this.message,
  });

  double get progress => totalContacts > 0 ? processedContacts / totalContacts : 0;
}

enum SyncState {
  idle,
  requestingPermission,
  readingContacts,
  uploading,
  completed,
  permissionDenied,
  error,
}

/// Production-quality repository for syncing device contacts with server roster
/// 
/// Features:
/// - Hash-based change detection to minimize unnecessary syncs
/// - Batch processing for efficiency
/// - Mutex to prevent concurrent sync operations
/// - Reconciliation with server roster
/// - Proper error handling and logging
class RosterRepository {
  final ProfileServiceClient _profileClient;
  final AppDatabase _database;
  final TokenManager _tokenManager;

  // Mutex for sync operations
  Completer<void>? _syncCompleter;
  bool _isSyncing = false;

  // Configuration
  static const _batchSize = 100;

  RosterRepository(
    this._profileClient,
    this._database,
    this._tokenManager,
  );

  /// Get current auth headers for API calls
  connect.Headers _getAuthHeaders() {
    final headers = connect.Headers();
    final token = _tokenManager.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ============================================================================
  // Sync Metadata Management
  // ============================================================================

  Future<String?> _getSyncMetadata(String key) async {
    final query = _database.select(_database.syncMetadata)
      ..where((t) => t.key.equals(key));
    final result = await query.getSingleOrNull();
    return result?.value;
  }

  Future<void> _setSyncMetadata(String key, String value) async {
    await _database.into(_database.syncMetadata).insertOnConflictUpdate(
          SyncMetadataCompanion.insert(
            key: key,
            value: Value(value),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// Get the last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final value = await _getSyncMetadata(_kLastSyncTimeKey);
    if (value == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(int.parse(value));
    } catch (_) {
      return null;
    }
  }

  // ============================================================================
  // Hash-based Change Detection
  // ============================================================================

  /// Compute a stable hash of all device contacts for change detection
  String _computeContactsHash(List<flutter_contacts.Contact> contacts) {
    // Sort contacts by ID for stable ordering
    final sortedContacts = List<flutter_contacts.Contact>.from(contacts)
      ..sort((a, b) => a.id.compareTo(b.id));

    // Build a string representation of all contact data we care about
    final buffer = StringBuffer();
    for (final contact in sortedContacts) {
      buffer.write(contact.id);
      for (final phone in contact.phones) {
        buffer.write(_normalizePhone(phone.number));
      }
      for (final email in contact.emails) {
        buffer.write(email.address.toLowerCase().trim());
      }
    }

    // Compute SHA256 hash
    final bytes = utf8.encode(buffer.toString());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Check if device contacts have changed since last sync
  Future<bool> needsSync() async {
    try {
      final hasPermission = await flutter_contacts.FlutterContacts
          .requestPermission(readonly: true);
      if (!hasPermission) {
        return false;
      }

      final deviceContacts = await flutter_contacts.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final currentHash = _computeContactsHash(deviceContacts);
      final storedHash = await _getSyncMetadata(_kContactsHashKey);

      if (storedHash == null) {
        AppLogger.debug('No previous contacts hash found, sync needed');
        return true;
      }

      final hashChanged = currentHash != storedHash;
      if (hashChanged) {
        AppLogger.debug('Contacts hash changed, sync needed');
      }

      return hashChanged;
    } catch (e) {
      AppLogger.warning('Failed to check if sync needed',
          data: {'error': e.toString()});
      return true; // Err on the side of syncing
    }
  }

  // ============================================================================
  // Core Sync Operations
  // ============================================================================

  /// Sync device contacts with server only if changes detected
  /// Returns list of roster entries
  /// Set [force] to true to bypass hash check
  Future<List<RosterEntry>> syncIfNeeded({bool force = false}) async {
    // If sync is already in progress, wait for it
    if (_isSyncing && _syncCompleter != null) {
      AppLogger.debug('Sync already in progress, waiting...');
      await _syncCompleter!.future;
      return await getLocalRoster();
    }

    if (!force) {
      final syncNeeded = await needsSync();
      if (!syncNeeded) {
        AppLogger.debug('Contacts unchanged, skipping sync');
        return await getLocalRoster();
      }
    }

    return await syncContacts();
  }

  /// Full sync of device contacts with server
  /// Returns list of roster entries that are registered on the platform
  /// Optionally accepts a [progressCallback] to report sync progress
  Future<List<RosterEntry>> syncContacts({SyncProgressCallback? progressCallback}) async {
    // Mutex check
    if (_isSyncing) {
      AppLogger.debug('[ContactSync] Sync already in progress, waiting for existing sync');
      if (_syncCompleter != null) {
        await _syncCompleter!.future;
      }
      return await getLocalRoster();
    }

    _isSyncing = true;
    _syncCompleter = Completer<void>();

    void reportProgress(SyncProgress progress) {
      AppLogger.debug('[ContactSync] Progress: ${progress.state.name}', data: {
        'message': progress.message,
        'total': progress.totalContacts,
        'processed': progress.processedContacts,
        'found': progress.foundOnPlatform,
      });
      progressCallback?.call(progress);
    }

    try {
      AppLogger.info('[ContactSync] ========== STARTING CONTACT SYNC ==========');
      final stopwatch = Stopwatch()..start();

      reportProgress(const SyncProgress(
        state: SyncState.requestingPermission,
        message: 'Requesting permission...',
      ));

      // Check and request contact permission using permission_handler
      // (flutter_contacts.requestPermission can get out of sync with system state)
      AppLogger.debug('[ContactSync] Checking contact permission status...');
      var permissionStatus = await Permission.contacts.status;
      AppLogger.debug('[ContactSync] Current permission status', data: {
        'isGranted': permissionStatus.isGranted,
        'isDenied': permissionStatus.isDenied,
        'isPermanentlyDenied': permissionStatus.isPermanentlyDenied,
        'isRestricted': permissionStatus.isRestricted,
      });
      
      if (!permissionStatus.isGranted) {
        AppLogger.debug('[ContactSync] Permission not granted, requesting...');
        permissionStatus = await Permission.contacts.request();
        AppLogger.debug('[ContactSync] Permission request result', data: {
          'isGranted': permissionStatus.isGranted,
          'isDenied': permissionStatus.isDenied,
          'isPermanentlyDenied': permissionStatus.isPermanentlyDenied,
        });
      }
      
      if (!permissionStatus.isGranted) {
        final message = permissionStatus.isPermanentlyDenied
            ? 'Permission denied. Please enable in Settings.'
            : 'Contact permission denied';
        AppLogger.warning('[ContactSync] Contact permission DENIED', data: {
          'isPermanentlyDenied': permissionStatus.isPermanentlyDenied,
        });
        reportProgress(SyncProgress(
          state: SyncState.permissionDenied,
          message: message,
        ));
        return [];
      }
      
      AppLogger.info('[ContactSync] Permission GRANTED, reading contacts...');

      reportProgress(const SyncProgress(
        state: SyncState.readingContacts,
        message: 'Reading contacts...',
      ));

      final deviceContacts = await flutter_contacts.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      AppLogger.info('[ContactSync] Read ${deviceContacts.length} contacts from device');

      if (deviceContacts.isEmpty) {
        AppLogger.debug('[ContactSync] No device contacts found, nothing to sync');
        reportProgress(const SyncProgress(
          state: SyncState.completed,
          message: 'No contacts to sync',
        ));
        return [];
      }

      // Compute hash for change detection
      final contactsHash = _computeContactsHash(deviceContacts);

      // Build contact requests and lookup map
      final contactRequests = <pb.AddContactRequest>[];
      final contactLookup = <String, flutter_contacts.Contact>{};

      for (final contact in deviceContacts) {
        // Process phone numbers
        for (final phone in contact.phones) {
          final normalized = _normalizePhone(phone.number);
          if (normalized.isNotEmpty && normalized.length >= 6) {
            contactLookup[normalized] = contact;
            contactRequests.add(pb.AddContactRequest(contact: normalized));
          }
        }

        // Process emails
        for (final email in contact.emails) {
          final normalized = email.address.toLowerCase().trim();
          if (normalized.isNotEmpty && normalized.contains('@')) {
            contactLookup[normalized] = contact;
            contactRequests.add(pb.AddContactRequest(contact: normalized));
          }
        }
      }

      if (contactRequests.isEmpty) {
        AppLogger.warning('[ContactSync] No valid phone numbers or emails found in contacts');
        reportProgress(const SyncProgress(
          state: SyncState.completed,
          message: 'No valid contact details found',
        ));
        return [];
      }

      // Remove duplicates
      final uniqueRequests = <String, pb.AddContactRequest>{};
      for (final req in contactRequests) {
        uniqueRequests[req.contact] = req;
      }
      final deduplicatedRequests = uniqueRequests.values.toList();

      AppLogger.info('[ContactSync] Prepared contacts for server sync', data: {
        'deviceContacts': deviceContacts.length,
        'rawContactDetails': contactRequests.length,
        'uniqueDetails': deduplicatedRequests.length,
        'duplicatesRemoved': contactRequests.length - deduplicatedRequests.length,
      });

      reportProgress(SyncProgress(
        state: SyncState.uploading,
        totalContacts: deduplicatedRequests.length,
        processedContacts: 0,
        message: 'Syncing with server...',
      ));

      // Sync in batches
      final syncedEntries = <RosterEntry>[];
      var processedCount = 0;
      final totalBatches = (deduplicatedRequests.length / _batchSize).ceil();
      var batchNum = 0;
      
      AppLogger.info('[ContactSync] Starting server upload in $totalBatches batches (batch size: $_batchSize)');
      
      for (var i = 0; i < deduplicatedRequests.length; i += _batchSize) {
        batchNum++;
        final batch = deduplicatedRequests.skip(i).take(_batchSize).toList();
        
        AppLogger.debug('[ContactSync] Uploading batch $batchNum/$totalBatches (${batch.length} contacts)');
        
        final results = await _syncBatch(batch, contactLookup);
        syncedEntries.addAll(results);
        processedCount += batch.length;
        
        AppLogger.debug('[ContactSync] Batch $batchNum result: ${results.length} contacts found on platform');
        
        reportProgress(SyncProgress(
          state: SyncState.uploading,
          totalContacts: deduplicatedRequests.length,
          processedContacts: processedCount,
          foundOnPlatform: syncedEntries.length,
          message: 'Found ${syncedEntries.length} contacts on platform...',
        ));
      }

      // Store in local database
      AppLogger.debug('[ContactSync] Storing ${syncedEntries.length} entries in local database');
      await _storeRosterEntries(syncedEntries);

      // Update sync metadata
      await _setSyncMetadata(_kContactsHashKey, contactsHash);
      await _setSyncMetadata(
          _kLastSyncTimeKey, DateTime.now().millisecondsSinceEpoch.toString());

      stopwatch.stop();
      AppLogger.info('[ContactSync] ========== SYNC COMPLETED ==========', data: {
        'deviceContacts': deviceContacts.length,
        'contactDetailsChecked': deduplicatedRequests.length,
        'foundOnPlatform': syncedEntries.length,
        'durationMs': stopwatch.elapsedMilliseconds,
        'hashPrefix': contactsHash.substring(0, 8),
      });

      reportProgress(SyncProgress(
        state: SyncState.completed,
        totalContacts: deduplicatedRequests.length,
        processedContacts: deduplicatedRequests.length,
        foundOnPlatform: syncedEntries.length,
        message: syncedEntries.isEmpty
            ? 'No contacts found on platform'
            : 'Found ${syncedEntries.length} contacts!',
      ));

      return syncedEntries;
    } catch (e, stackTrace) {
      AppLogger.error('[ContactSync] ========== SYNC FAILED ==========', 
          error: e, stackTrace: stackTrace);
      reportProgress(SyncProgress(
        state: SyncState.error,
        message: 'Sync failed: ${e.toString()}',
      ));
      return [];
    } finally {
      _isSyncing = false;
      _syncCompleter?.complete();
      _syncCompleter = null;
      AppLogger.debug('[ContactSync] Sync mutex released');
    }
  }

  /// Sync a batch of contacts with the server
  Future<List<RosterEntry>> _syncBatch(
    List<pb.AddContactRequest> batch,
    Map<String, flutter_contacts.Contact> contactLookup,
  ) async {
    try {
      final headers = _getAuthHeaders();
      final hasAuth = headers['Authorization']?.isNotEmpty ?? false;
      AppLogger.debug('[ContactSync] Sending batch to server', data: {
        'batchSize': batch.length,
        'hasAuth': hasAuth,
      });
      
      final request = pb.AddRosterRequest(data: batch);
      final response = await _profileClient.addRoster(request, headers: headers);

      AppLogger.debug('[ContactSync] Server response received', data: {
        'responseCount': response.data.length,
      });

      return response.data.map((roster) {
        // Get local display name from device contacts
        String? localDisplayName;
        if (roster.hasContact()) {
          final detail = roster.contact.detail;
          final localContact = contactLookup[detail];
          if (localContact != null && localContact.displayName.isNotEmpty) {
            localDisplayName = localContact.displayName;
          }
        }

        return RosterEntry.fromProto(roster, localDisplayName: localDisplayName);
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error('[ContactSync] Batch upload FAILED',
          error: e, stackTrace: stackTrace, data: {'batchSize': batch.length});
      return [];
    }
  }

  /// Store roster entries in local database efficiently
  Future<void> _storeRosterEntries(List<RosterEntry> entries) async {
    if (entries.isEmpty) return;

    await _database.batch((batch) {
      for (final entry in entries) {
        batch.insert(
          _database.roster,
          entry.toCompanion(),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  // ============================================================================
  // Server Roster Operations
  // ============================================================================

  /// Fetch complete roster from server
  Future<List<RosterEntry>> fetchServerRoster() async {
    try {
      final headers = _getAuthHeaders();
      final request = pb.SearchRosterRequest();
      final entries = <RosterEntry>[];

      await for (final response
          in _profileClient.searchRoster(request, headers: headers)) {
        for (final roster in response.data) {
          entries.add(RosterEntry.fromProto(roster));
        }
      }

      return entries;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch server roster',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Reconcile local roster with server
  /// Ensures local database matches server state
  Future<void> reconcileWithServer() async {
    try {
      AppLogger.info('Reconciling roster with server');
      final stopwatch = Stopwatch()..start();

      // Fetch server roster
      final serverEntries = await fetchServerRoster();
      final serverIds = serverEntries.map((e) => e.id).toSet();

      // Get local roster
      final localEntries = await getLocalRoster();
      final localIds = localEntries.map((e) => e.id).toSet();

      // Entries to add locally (on server but not local)
      final toAdd = serverEntries.where((e) => !localIds.contains(e.id)).toList();

      // Entries to remove locally (local but not on server)
      final toRemove = localIds.difference(serverIds);

      // Batch operations
      await _database.batch((batch) {
        // Add missing entries
        for (final entry in toAdd) {
          batch.insert(
            _database.roster,
            entry.toCompanion(),
            mode: InsertMode.insertOrReplace,
          );
        }

        // Remove stale entries
        for (final id in toRemove) {
          batch.deleteWhere(
            _database.roster,
            (t) => t.id.equals(id),
          );
        }
      });

      stopwatch.stop();
      AppLogger.info('Roster reconciliation completed', data: {
        'added': toAdd.length,
        'removed': toRemove.length,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
    } catch (e, stackTrace) {
      AppLogger.error('Roster reconciliation failed',
          error: e, stackTrace: stackTrace);
    }
  }

  // ============================================================================
  // Local Roster Operations
  // ============================================================================

  /// Get all roster entries from local database
  Future<List<RosterEntry>> getLocalRoster({bool includeBlocked = false}) async {
    var query = _database.select(_database.roster);
    if (!includeBlocked) {
      query = query..where((t) => t.isBlocked.equals(false));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.displayName)]);

    final results = await query.get();
    return results.map(RosterEntry.fromDbRow).toList();
  }

  /// Get a single roster entry by ID
  Future<RosterEntry?> getRosterEntry(String id) async {
    final query = _database.select(_database.roster)
      ..where((t) => t.id.equals(id));
    final result = await query.getSingleOrNull();
    return result != null ? RosterEntry.fromDbRow(result) : null;
  }

  /// Get roster entry by profile ID
  Future<RosterEntry?> getRosterByProfileId(String profileId) async {
    final query = _database.select(_database.roster)
      ..where((t) => t.profileId.equals(profileId));
    final result = await query.getSingleOrNull();
    return result != null ? RosterEntry.fromDbRow(result) : null;
  }

  /// Search roster entries by display name or contact detail
  Future<List<RosterEntry>> searchRoster(String query) async {
    final pattern = '%${query.toLowerCase()}%';
    final dbQuery = _database.select(_database.roster)
      ..where((t) =>
          t.displayName.lower().like(pattern) |
          t.contactDetail.lower().like(pattern))
      ..where((t) => t.isBlocked.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.displayName)]);

    final results = await dbQuery.get();
    return results.map(RosterEntry.fromDbRow).toList();
  }

  /// Remove a contact from the roster (server and local)
  Future<void> removeRosterEntry(String id) async {
    try {
      final headers = _getAuthHeaders();
      final request = pb.RemoveRosterRequest(id: id);
      await _profileClient.removeRoster(request, headers: headers);

      await (_database.delete(_database.roster)..where((t) => t.id.equals(id)))
          .go();

      AppLogger.info('Roster entry removed', data: {'id': id});
    } catch (e, stackTrace) {
      AppLogger.error('Failed to remove roster entry',
          error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Block a roster entry locally
  Future<void> blockRosterEntry(String id) async {
    await (_database.update(_database.roster)..where((t) => t.id.equals(id)))
        .write(const RosterCompanion(isBlocked: Value(true)));
  }

  /// Unblock a roster entry locally
  Future<void> unblockRosterEntry(String id) async {
    await (_database.update(_database.roster)..where((t) => t.id.equals(id)))
        .write(const RosterCompanion(isBlocked: Value(false)));
  }

  /// Get blocked roster entries
  Future<List<RosterEntry>> getBlockedEntries() async {
    final query = _database.select(_database.roster)
      ..where((t) => t.isBlocked.equals(true));
    final results = await query.get();
    return results.map(RosterEntry.fromDbRow).toList();
  }

  /// Get roster count
  Future<int> getRosterCount() async {
    final count = await _database.roster.count().getSingle();
    return count;
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  String _normalizePhone(String phone) {
    // Remove all non-digit characters except leading +
    final hasPlus = phone.startsWith('+');
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  /// Watch roster entries as a stream
  Stream<List<RosterEntry>> watchRoster() {
    final query = _database.select(_database.roster)
      ..where((t) => t.isBlocked.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.displayName)]);

    return query.watch().map((rows) => rows.map(RosterEntry.fromDbRow).toList());
  }
}

// ============================================================================
// Providers
// ============================================================================

final rosterRepositoryProvider = FutureProvider<RosterRepository>((ref) async {
  final profileClient = await ref.watch(profileServiceClientProvider.future);
  final tokenManager = ref.watch(tokenManagerProvider);

  return RosterRepository(
    profileClient,
    AppDatabase.instance,
    tokenManager,
  );
});

/// Provider for roster entries - uses hash-based change detection
/// Returns local roster immediately and syncs in background only if needed
final rosterEntriesProvider = FutureProvider<List<RosterEntry>>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);

  // First get local roster
  final local = await repo.getLocalRoster();
  if (local.isEmpty) {
    // No local roster, must sync
    return await repo.syncContacts();
  }

  // Trigger background sync only if contacts have changed
  repo.syncIfNeeded();
  return local;
});

/// Provider for watching roster entries reactively
final rosterStreamProvider = StreamProvider<List<RosterEntry>>((ref) async* {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  yield* repo.watchRoster();
});

/// Provider to force a roster sync
final rosterSyncTriggerProvider = FutureProvider<List<RosterEntry>>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  return await repo.syncIfNeeded(force: true);
});

/// Provider to reconcile local roster with server
final rosterReconcileProvider = FutureProvider<void>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  await repo.reconcileWithServer();
});

/// Provider to check if sync is needed
final rosterSyncNeededProvider = FutureProvider<bool>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  return await repo.needsSync();
});

/// Provider for blocked roster entries
final blockedRosterEntriesProvider =
    FutureProvider<List<RosterEntry>>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  return await repo.getBlockedEntries();
});

/// Provider for roster count
final rosterCountProvider = FutureProvider<int>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  return await repo.getRosterCount();
});
