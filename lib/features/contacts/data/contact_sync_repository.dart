import 'package:drift/drift.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as flutter_contacts;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../apis/profile/v1/profile.pb.dart' as pb;
import '../../../apis/profile/v1/profile.connect.client.dart';
import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';
import '../../../core/networking/authenticated_transport.dart';

/// Repository for syncing device contacts with server roster
class ContactSyncRepository {
  final ProfileServiceClient _profileClient;
  final AppDatabase _database;
  final TransportFactory _transportFactory;

  ContactSyncRepository(
    this._profileClient,
    this._database,
    this._transportFactory,
  );

  /// Sync device contacts with server
  /// Returns list of contacts that are registered on the platform
  Future<List<SyncedContact>> syncContacts() async {
    try {
      AppLogger.info('Starting contact sync');

      // Get device contacts
      final hasPermission = await flutter_contacts.FlutterContacts.requestPermission();
      if (!hasPermission) {
        AppLogger.warning('Contact permission denied');
        return [];
      }

      final deviceContacts = await flutter_contacts.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false, // Don't load photos during sync for performance
      );

      if (deviceContacts.isEmpty) {
        AppLogger.debug('No device contacts to sync');
        return [];
      }

      // Extract phone numbers and create hash for privacy
      final contactRequests = <pb.AddContactRequest>[];
      final phoneToContact = <String, flutter_contacts.Contact>{};

      for (final contact in deviceContacts) {
        for (final phone in contact.phones) {
          final normalizedPhone = _normalizePhone(phone.number);
          if (normalizedPhone.isNotEmpty) {
            final phoneHash = _hashPhone(normalizedPhone);
            phoneToContact[phoneHash] = contact;

            contactRequests.add(pb.AddContactRequest(
              contact: normalizedPhone,
            ));
          }
        }

        // Also check emails
        for (final email in contact.emails) {
          if (email.address.isNotEmpty) {
            contactRequests.add(pb.AddContactRequest(
              contact: email.address.toLowerCase(),
            ));
          }
        }
      }

      if (contactRequests.isEmpty) {
        AppLogger.debug('No valid contact details to sync');
        return [];
      }

      // Send to server in batches to avoid overwhelming
      final syncedContacts = <SyncedContact>[];
      const batchSize = 50;

      for (var i = 0; i < contactRequests.length; i += batchSize) {
        final batch = contactRequests.skip(i).take(batchSize).toList();
        final results = await _syncBatch(batch);
        syncedContacts.addAll(results);
      }

      // Store synced contacts locally
      await _storeSyncedContacts(syncedContacts);

      AppLogger.info(
        'Contact sync completed',
        data: {
          'deviceContacts': deviceContacts.length,
          'syncedContacts': syncedContacts.length,
        },
      );

      return syncedContacts;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Contact sync failed',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  Future<List<SyncedContact>> _syncBatch(List<pb.AddContactRequest> batch) async {
    try {
      final headers = await _transportFactory.getAuthHeaders();

      final request = pb.AddRosterRequest(data: batch);
      final response = await _profileClient.addRoster(
        request,
        headers: headers,
      );

      return response.data.map((roster) {
        return SyncedContact(
          id: roster.id,
          profileId: roster.profileId,
          displayName: roster.hasContact() ? roster.contact.detail : roster.profileId,
          contactType: roster.hasContact() && roster.contact.type == pb.ContactType.MSISDN
              ? ContactSyncType.phone
              : ContactSyncType.email,
          isVerified: roster.hasContact() ? roster.contact.verified : false,
        );
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Batch sync failed',
        error: e,
        stackTrace: stackTrace,
        data: {'batchSize': batch.length},
      );
      return [];
    }
  }

  /// Get roster from server
  Future<List<SyncedContact>> getRoster() async {
    try {
      final headers = await _transportFactory.getAuthHeaders();
      final request = pb.SearchRosterRequest();

      final syncedContacts = <SyncedContact>[];

      await for (final response in _profileClient.searchRoster(
        request,
        headers: headers,
      )) {
        for (final roster in response.data) {
          syncedContacts.add(SyncedContact(
            id: roster.id,
            profileId: roster.profileId,
            displayName: roster.hasContact() ? roster.contact.detail : roster.profileId,
            contactType: roster.hasContact() && roster.contact.type == pb.ContactType.MSISDN
                ? ContactSyncType.phone
                : ContactSyncType.email,
            isVerified: roster.hasContact() ? roster.contact.verified : false,
          ));
        }
      }

      return syncedContacts;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get roster',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  Future<void> _storeSyncedContacts(List<SyncedContact> contacts) async {
    for (final contact in contacts) {
      await _database.into(_database.contacts).insertOnConflictUpdate(
        ContactsCompanion.insert(
          id: contact.id,
          profileId: contact.profileId,
          displayName: Value(contact.displayName),
          phoneHash: Value(contact.contactType == ContactSyncType.phone
              ? _hashPhone(contact.displayName)
              : null),
          isBlocked: const Value(false),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
  }

  /// Get locally stored synced contacts
  Future<List<SyncedContact>> getLocalSyncedContacts() async {
    final query = _database.select(_database.contacts)
      ..where((t) => t.isBlocked.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.displayName)]);
    
    final results = await query.get();

    return results.map((row) {
      return SyncedContact(
        id: row.id,
        profileId: row.profileId,
        displayName: row.displayName ?? '',
        contactType: row.phoneHash != null
            ? ContactSyncType.phone
            : ContactSyncType.email,
        isVerified: true,
      );
    }).toList();
  }

  String _normalizePhone(String phone) {
    // Remove all non-digit characters except leading +
    final hasPlus = phone.startsWith('+');
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    return hasPlus ? '+$digits' : digits;
  }

  String _hashPhone(String phone) {
    // Simple hash for phone number
    var hash = 0;
    for (var i = 0; i < phone.length; i++) {
      hash = ((hash << 5) - hash) + phone.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}

enum ContactSyncType { phone, email }

class SyncedContact {
  final String id;
  final String profileId;
  final String displayName;
  final ContactSyncType contactType;
  final bool isVerified;

  SyncedContact({
    required this.id,
    required this.profileId,
    required this.displayName,
    required this.contactType,
    this.isVerified = false,
  });
}

// Providers
final contactSyncRepositoryProvider = Provider<ContactSyncRepository>((ref) {
  final profileClient = ref.watch(profileServiceClientProvider);
  final transportFactory = ref.watch(transportFactoryProvider);

  return ContactSyncRepository(
    profileClient,
    AppDatabase.instance,
    transportFactory,
  );
});

final syncedContactsProvider = FutureProvider<List<SyncedContact>>((ref) async {
  final repo = ref.watch(contactSyncRepositoryProvider);
  // First try to get local contacts, then sync in background
  final local = await repo.getLocalSyncedContacts();
  if (local.isEmpty) {
    return await repo.syncContacts();
  }
  // Trigger background sync
  repo.syncContacts();
  return local;
});

final contactSyncTriggerProvider = FutureProvider<List<SyncedContact>>((ref) async {
  final repo = ref.watch(contactSyncRepositoryProvider);
  return await repo.syncContacts();
});
