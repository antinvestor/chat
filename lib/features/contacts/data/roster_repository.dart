import 'dart:async';
import 'dart:convert';

import 'package:antinvestor_api_common/antinvestor_api_common.dart' show TokenManager;
import 'package:flutter/widgets.dart';
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart' as pb;
import 'package:antinvestor_api_profile/antinvestor_api_profile.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as flutter_contacts;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:libphonenumber_plugin/libphonenumber_plugin.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';

// ============================================================================
// Contact Validation Utilities
// ============================================================================

/// Email validation regex pattern
final _emailRegex = RegExp(
  r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$',
);

/// Validate email format
bool isValidEmail(String email) {
  if (email.isEmpty) return false;
  final normalized = email.toLowerCase().trim();
  if (normalized.length < 5) return false; // a@b.c minimum
  if (!normalized.contains('@')) return false;
  return _emailRegex.hasMatch(normalized);
}

/// Validate phone number using libphonenumber
/// Returns the formatted E.164 number if valid, null otherwise
Future<String?> validateAndFormatPhoneNumber(String phone, {String? regionCode}) async {
  if (phone.isEmpty) return null;
  
  // Normalize the phone number first
  final hasPlus = phone.startsWith('+');
  final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty || digits.length < 6) return null;
  
  final normalized = hasPlus ? '+$digits' : digits;
  
  try {
    // Use provided region, or get from device locale
    final region = regionCode ?? _getDeviceRegionCode();
    
    // Check if the number is valid
    final isValid = await PhoneNumberUtil.isValidPhoneNumber(normalized, region);
    if (isValid != true) {
      return null;
    }
    
    // Format to E.164 for consistency
    final formatted = await PhoneNumberUtil.normalizePhoneNumber(normalized, region);
    return formatted;
  } catch (e) {
    AppLogger.debug('Phone validation failed', data: {'phone': normalized, 'error': e.toString()});
    return null;
  }
}

/// Get the device's region code from platform locale
String _getDeviceRegionCode() {
  try {
    // Get locale from platform dispatcher
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      return locale.countryCode!;
    }
  } catch (e) {
    AppLogger.debug('Failed to get locale region', data: {'error': e.toString()});
  }
  
  // Fallback if locale not available
  return 'US';
}

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

/// Profile data model for local storage
class ProfileData {
  final String id;
  final String? name;
  final String? avatarUrl;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata;

  ProfileData({
    required this.id,
    this.name,
    this.avatarUrl,
    this.updatedAt,
    this.metadata,
  });

  factory ProfileData.fromDbRow(Profile row) {
    Map<String, dynamic>? meta;
    if (row.metadata != null) {
      try {
        meta = json.decode(row.metadata!) as Map<String, dynamic>;
      } catch (_) {}
    }
    return ProfileData(
      id: row.id,
      name: row.name,
      avatarUrl: row.avatarUrl,
      updatedAt: row.updatedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.updatedAt!)
          : null,
      metadata: meta,
    );
  }

  ProfilesCompanion toCompanion() {
    return ProfilesCompanion(
      id: Value(id),
      name: Value(name),
      avatarUrl: Value(avatarUrl),
      updatedAt: Value(updatedAt?.millisecondsSinceEpoch),
      metadata: Value(metadata != null ? json.encode(metadata) : null),
    );
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

/// Profile with associated contacts (roster entries)
/// This is the primary display model - profile is the person,
/// contacts are the ways to reach them
class ProfileWithContacts {
  final ProfileData profile;
  final List<RosterEntry> contacts;

  ProfileWithContacts({
    required this.profile,
    required this.contacts,
  });

  /// Get display name - prefer profile name, fallback to first contact display name
  String get displayName {
    if (profile.name != null && profile.name!.isNotEmpty) {
      return profile.name!;
    }
    if (contacts.isNotEmpty && contacts.first.displayName != null) {
      return contacts.first.displayName!;
    }
    return profile.id;
  }

  /// Get avatar URL from profile
  String? get avatarUrl => profile.avatarUrl;

  /// Check if any contact is verified
  bool get hasVerifiedContact => contacts.any((c) => c.isVerified);

  /// Get primary contact (first verified, or first available)
  RosterEntry? get primaryContact {
    if (contacts.isEmpty) return null;
    return contacts.firstWhere(
      (c) => c.isVerified,
      orElse: () => contacts.first,
    );
  }

  /// Get contact summary for display (e.g., "2 contacts")
  String get contactSummary {
    if (contacts.isEmpty) return 'No contacts';
    if (contacts.length == 1) {
      final c = contacts.first;
      return c.contactType == RosterContactType.msisdn ? 'Phone' : 'Email';
    }
    return '${contacts.length} contacts';
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
  final int currentBatch;
  final int totalBatches;
  final String? message;

  const SyncProgress({
    required this.state,
    this.totalContacts = 0,
    this.processedContacts = 0,
    this.foundOnPlatform = 0,
    this.currentBatch = 0,
    this.totalBatches = 0,
    this.message,
  });

  double get progress => totalContacts > 0 ? processedContacts / totalContacts : 0;
  
  /// Whether new contacts were just stored and are ready for display
  bool get hasNewContacts => foundOnPlatform > 0;
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
  final TokenManager _tokenManager; // Keep for potential future use

  // Mutex for sync operations
  Completer<void>? _syncCompleter;
  bool _isSyncing = false;

  // Configuration
  static const _batchSize = 20;

  RosterRepository(
    this._profileClient,
    this._database,
    this._tokenManager,
  );

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

      // Build contact requests and lookup map with validation
      final contactRequests = <pb.RawContact>[];
      final contactLookup = <String, flutter_contacts.Contact>{};
      var invalidPhones = 0;
      var invalidEmails = 0;
      var validPhones = 0;
      var validEmails = 0;

      reportProgress(const SyncProgress(
        state: SyncState.readingContacts,
        message: 'Validating contacts...',
      ));

      for (final contact in deviceContacts) {
        // Process and validate phone numbers using libphonenumber
        for (final phone in contact.phones) {
          final validatedPhone = await validateAndFormatPhoneNumber(phone.number);
          if (validatedPhone != null) {
            contactLookup[validatedPhone] = contact;
            contactRequests.add(pb.RawContact(contact: validatedPhone));
            validPhones++;
          } else {
            invalidPhones++;
          }
        }

        // Process and validate emails
        for (final email in contact.emails) {
          final normalized = email.address.toLowerCase().trim();
          if (isValidEmail(normalized)) {
            contactLookup[normalized] = contact;
            contactRequests.add(pb.RawContact(contact: normalized));
            validEmails++;
          } else {
            invalidEmails++;
          }
        }
      }

      AppLogger.info('[ContactSync] Contact validation completed', data: {
        'validPhones': validPhones,
        'invalidPhones': invalidPhones,
        'validEmails': validEmails,
        'invalidEmails': invalidEmails,
      });

      if (contactRequests.isEmpty) {
        AppLogger.warning('[ContactSync] No valid phone numbers or emails found in contacts');
        reportProgress(const SyncProgress(
          state: SyncState.completed,
          message: 'No valid contact details found',
        ));
        return [];
      }

      // Remove duplicates
      final uniqueRequests = <String, pb.RawContact>{};
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

      // Sync in batches - serial processing with immediate storage
      final syncedEntries = <RosterEntry>[];
      var processedCount = 0;
      final totalBatches = (deduplicatedRequests.length / _batchSize).ceil();
      var batchNum = 0;
      
      AppLogger.info('[ContactSync] Starting server upload in $totalBatches batches (batch size: $_batchSize)');
      
      for (var i = 0; i < deduplicatedRequests.length; i += _batchSize) {
        batchNum++;
        final batch = deduplicatedRequests.skip(i).take(_batchSize).toList();
        
        AppLogger.debug('[ContactSync] Processing batch $batchNum/$totalBatches (${batch.length} contacts)');
        
        // Report batch starting
        reportProgress(SyncProgress(
          state: SyncState.uploading,
          totalContacts: deduplicatedRequests.length,
          processedContacts: processedCount,
          foundOnPlatform: syncedEntries.length,
          currentBatch: batchNum,
          totalBatches: totalBatches,
          message: 'Processing batch $batchNum of $totalBatches...',
        ));
        
        // Send batch to server and wait for response (serial processing)
        final results = await _syncBatch(batch, contactLookup);
        
        if (results.isNotEmpty) {
          // Store batch results immediately so contacts are available for use
          AppLogger.debug('[ContactSync] Storing ${results.length} entries from batch $batchNum');
          await _storeRosterEntries(results);
          
          // Fetch and store profile data for this batch immediately
          final batchProfileIds = results.map((e) => e.profileId).toSet().toList();
          await fetchAndStoreProfiles(batchProfileIds);
          
          syncedEntries.addAll(results);
        }
        
        processedCount += batch.length;
        
        AppLogger.debug('[ContactSync] Batch $batchNum completed: ${results.length} contacts found, total: ${syncedEntries.length}');
        
        // Report batch completion with updated counts
        reportProgress(SyncProgress(
          state: SyncState.uploading,
          totalContacts: deduplicatedRequests.length,
          processedContacts: processedCount,
          foundOnPlatform: syncedEntries.length,
          currentBatch: batchNum,
          totalBatches: totalBatches,
          message: 'Found ${syncedEntries.length} contacts (batch $batchNum/$totalBatches done)',
        ));
      }

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
    List<pb.RawContact> batch,
    Map<String, flutter_contacts.Contact> contactLookup,
  ) async {
    try {
      AppLogger.debug('[ContactSync] Sending batch to server', data: {
        'batchSize': batch.length,
      });
      
      final request = pb.AddRosterRequest(data: batch);
      // Don't pass manual headers - let the interceptor handle authorization
      // This ensures token refresh works correctly on 401
      final response = await _profileClient.addRoster(request);

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
      final request = pb.SearchRosterRequest();
      final entries = <RosterEntry>[];

      // Don't pass manual headers - let the interceptor handle authorization
      await for (final response
          in _profileClient.searchRoster(request)) {
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
      final request = pb.RemoveRosterRequest(id: id);
      // Don't pass manual headers - let the interceptor handle authorization
      await _profileClient.removeRoster(request);

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

  // ============================================================================
  // Profile Operations
  // ============================================================================

  /// Fetch profile data from server by ID
  Future<ProfileData?> fetchProfileFromServer(String profileId) async {
    try {
      final request = pb.GetByIdRequest(id: profileId);
      // Don't pass manual headers - let the interceptor handle authorization
      final response = await _profileClient.getById(request);

      if (!response.hasData()) return null;

      final profile = response.data;
      String? name;
      String? avatarUrl;

      // Extract name and avatar from properties
      if (profile.hasProperties()) {
        final props = profile.properties;
        if (props.fields.containsKey('name')) {
          name = props.fields['name']?.stringValue;
        }
        if (props.fields.containsKey('avatar')) {
          avatarUrl = props.fields['avatar']?.stringValue;
        }
        if (props.fields.containsKey('avatarUrl')) {
          avatarUrl = props.fields['avatarUrl']?.stringValue;
        }
      }

      return ProfileData(
        id: profile.id,
        name: name,
        avatarUrl: avatarUrl,
        updatedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      AppLogger.warning('Failed to fetch profile from server',
          data: {'profileId': profileId, 'error': e.toString()});
      AppLogger.debug('Profile fetch error details', data: {'stackTrace': stackTrace.toString()});
      return null;
    }
  }

  /// Fetch and store profile data for multiple profile IDs
  Future<void> fetchAndStoreProfiles(List<String> profileIds) async {
    if (profileIds.isEmpty) return;

    final uniqueIds = profileIds.toSet().toList();
    AppLogger.debug('[ProfileSync] Fetching ${uniqueIds.length} profiles from server');

    final profiles = <ProfileData>[];
    for (final profileId in uniqueIds) {
      final profile = await fetchProfileFromServer(profileId);
      if (profile != null) {
        profiles.add(profile);
      }
    }

    if (profiles.isNotEmpty) {
      await _storeProfiles(profiles);
      AppLogger.debug('[ProfileSync] Stored ${profiles.length} profiles');
    }
  }

  /// Store profiles in local database
  Future<void> _storeProfiles(List<ProfileData> profiles) async {
    if (profiles.isEmpty) return;

    await _database.batch((batch) {
      for (final profile in profiles) {
        batch.insert(
          _database.profiles,
          profile.toCompanion(),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Get profile from local database
  Future<ProfileData?> getLocalProfile(String profileId) async {
    final query = _database.select(_database.profiles)
      ..where((t) => t.id.equals(profileId));
    final result = await query.getSingleOrNull();
    return result != null ? ProfileData.fromDbRow(result) : null;
  }

  /// Get all profiles with their associated contacts (roster entries)
  /// This is the primary method for displaying contacts - groups by profile
  Future<List<ProfileWithContacts>> getProfilesWithContacts({
    bool includeBlocked = false,
  }) async {
    // Get all roster entries
    final rosterEntries = await getLocalRoster(includeBlocked: includeBlocked);
    if (rosterEntries.isEmpty) return [];

    // Group roster entries by profileId
    final groupedByProfile = <String, List<RosterEntry>>{};
    for (final entry in rosterEntries) {
      groupedByProfile.putIfAbsent(entry.profileId, () => []).add(entry);
    }

    // Get all profiles
    final profileIds = groupedByProfile.keys.toList();
    final query = _database.select(_database.profiles)
      ..where((t) => t.id.isIn(profileIds));
    final profileRows = await query.get();
    final profileMap = {for (final p in profileRows) p.id: ProfileData.fromDbRow(p)};

    // Build ProfileWithContacts list
    final result = <ProfileWithContacts>[];
    for (final profileId in groupedByProfile.keys) {
      final contacts = groupedByProfile[profileId]!;
      
      // Get profile or create placeholder from roster data
      var profile = profileMap[profileId];
      if (profile == null) {
        // Create placeholder profile from roster entry
        final firstContact = contacts.first;
        profile = ProfileData(
          id: profileId,
          name: firstContact.displayName,
        );
      }

      result.add(ProfileWithContacts(
        profile: profile,
        contacts: contacts,
      ));
    }

    // Sort by display name
    result.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return result;
  }

  /// Watch profiles with contacts as a stream
  Stream<List<ProfileWithContacts>> watchProfilesWithContacts() {
    return watchRoster().asyncMap((_) => getProfilesWithContacts());
  }

  /// Get all roster entries for a specific profile
  Future<List<RosterEntry>> getRosterEntriesForProfile(String profileId) async {
    final query = _database.select(_database.roster)
      ..where((t) => t.profileId.equals(profileId))
      ..where((t) => t.isBlocked.equals(false));
    final results = await query.get();
    return results.map(RosterEntry.fromDbRow).toList();
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

/// Provider for profiles with their associated contacts
/// This is the primary provider for displaying contacts - profile-centric view
final profilesWithContactsProvider = FutureProvider<List<ProfileWithContacts>>((ref) async {
  final repo = await ref.watch(rosterRepositoryProvider.future);

  // First get local data
  final local = await repo.getProfilesWithContacts();
  if (local.isEmpty) {
    // No local data, must sync first
    await repo.syncContacts();
    return await repo.getProfilesWithContacts();
  }

  // Trigger background sync only if contacts have changed
  repo.syncIfNeeded();
  return local;
});

/// Stream provider for watching profiles with contacts reactively
final profilesWithContactsStreamProvider = StreamProvider<List<ProfileWithContacts>>((ref) async* {
  final repo = await ref.watch(rosterRepositoryProvider.future);
  yield* repo.watchProfilesWithContacts();
});
