import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';

/// Repository for managing room members and subscriptions
/// Handles all database access for room membership operations
class RoomMemberRepository {
  RoomMemberRepository(this._database);
  final AppDatabase _database;

  /// Update profile ID for an existing subscription
  /// Used when a user authenticates and their profile ID becomes known
  ///
  /// @param subscriptionId The room subscription to update
  /// @param profileId The profile ID to associate with this subscription
  /// @param contactId Optional contact ID used for this subscription
  /// @return true if update was successful, false if subscription not found
  Future<bool> updateSubscriptionProfile({
    required String subscriptionId,
    required String profileId,
    String? contactId,
  }) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.subscriptionId.equals(subscriptionId));

      final existingMember = await query.getSingleOrNull();
      if (existingMember == null) {
        AppLogger.warning(
          'Subscription not found for profile update',
          data: {'subscriptionId': subscriptionId},
        );
        return false;
      }

      // Update the subscription with profile information
      await (_database.update(
        _database.roomMembers,
      )..where((t) => t.subscriptionId.equals(subscriptionId))).write(
        RoomMembersCompanion(
          profileId: Value(profileId),
          contactId: contactId != null
              ? Value(contactId)
              : const Value.absent(),
          joinedAt: existingMember.joinedAt != null
              ? Value(existingMember.joinedAt)
              : Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      AppLogger.info(
        'Subscription profile updated successfully',
        data: {
          'subscriptionId': subscriptionId,
          'profileId': profileId,
          'contactId': contactId,
        },
      );

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to update subscription profile',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get all subscriptions for a profile across all rooms
  /// Useful for finding all rooms a user is subscribed to
  ///
  /// @param profileId The profile ID to search for
  /// @return List of room memberships for this profile
  Future<List<RoomMember>> getProfileSubscriptions(String profileId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.profileId.equals(profileId));

      return await query.get();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get profile subscriptions',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get all subscriptions without a profile ID (anonymous subscriptions)
  /// Useful for finding subscriptions that need profile assignment
  ///
  /// @param roomId Optional room filter
  /// @return List of anonymous subscriptions
  Future<List<RoomMember>> getAnonymousSubscriptions({String? roomId}) async {
    try {
      var query = _database.select(_database.roomMembers)
        ..where((t) => t.profileId.isNull());

      if (roomId != null) {
        query = query..where((t) => t.roomId.equals(roomId));
      }

      return await query.get();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get anonymous subscriptions',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Create a new subscription (can be anonymous initially)
  ///
  /// @param subscriptionId The subscription ID from API
  /// @param roomId The room ID
  /// @param profileId Optional profile ID (can be null for anonymous)
  /// @param contactId Optional contact ID
  /// @param role Optional role in the room
  /// @return true if creation was successful
  Future<bool> createSubscription({
    required String subscriptionId,
    required String roomId,
    String? profileId,
    String? contactId,
    String? role,
  }) async {
    try {
      await _database
          .into(_database.roomMembers)
          .insert(
            RoomMembersCompanion.insert(
              subscriptionId: subscriptionId,
              roomId: roomId,
              profileId: profileId != null
                  ? Value(profileId)
                  : const Value.absent(),
              contactId: contactId != null
                  ? Value(contactId)
                  : const Value.absent(),
              role: role != null ? Value(role) : const Value.absent(),
              joinedAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );

      AppLogger.info(
        'Subscription created successfully',
        data: {
          'subscriptionId': subscriptionId,
          'roomId': roomId,
          'profileId': profileId,
          'contactId': contactId,
          'role': role,
        },
      );

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to create subscription',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Remove a subscription from a room
  ///
  /// @param subscriptionId The subscription ID to remove
  /// @return true if removal was successful
  Future<bool> removeSubscription(String subscriptionId) async {
    try {
      final deleteCount = await (_database.delete(
        _database.roomMembers,
      )..where((t) => t.subscriptionId.equals(subscriptionId))).go();

      final success = deleteCount > 0;

      if (success) {
        AppLogger.info(
          'Subscription removed successfully',
          data: {'subscriptionId': subscriptionId},
        );
      } else {
        AppLogger.warning(
          'Subscription not found for removal',
          data: {'subscriptionId': subscriptionId},
        );
      }

      return success;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to remove subscription',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if a subscription exists for a profile in a room
  ///
  /// @param roomId The room ID
  /// @param profileId The profile ID
  /// @return true if subscription exists
  Future<bool> hasSubscription(String roomId, String profileId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId) & t.profileId.equals(profileId));

      final member = await query.getSingleOrNull();
      return member != null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to check subscription existence',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get subscription by subscription ID
  ///
  /// @param subscriptionId The subscription ID
  /// @return Room member if found, null otherwise
  Future<RoomMember?> getSubscription(String subscriptionId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.subscriptionId.equals(subscriptionId));

      return await query.getSingleOrNull();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get subscription',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get current profile's subscription ID for a specific room
  /// Returns null if the profile is not a member of the room
  ///
  /// @param roomId The room ID
  /// @param profileId The current profile's ID (can be empty for anonymous subscriptions)
  /// @param contactId The current contact's ID
  /// @return Subscription ID if found, null otherwise
  Future<String?> getCurrentSubscriptionId(
    String roomId,
    String profileId,
    String contactId,
  ) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where(
          (t) =>
              t.roomId.equals(roomId) &
              t.contactId.equals(contactId) &
              // Only include profileId in query if it's not empty
              (profileId.isEmpty
                  ? t.profileId.isNull()
                  : t.profileId.equals(profileId)),
        );

      final member = await query.getSingleOrNull();
      return member?.subscriptionId;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get current profile subscription ID',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get all members for a room
  /// Returns all room members ordered by join date
  ///
  /// @param roomId The room ID
  /// @return List of room members
  Future<List<RoomMember>> getMembersForRoom(String roomId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId))
        ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]);

      return await query.get();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get room members',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Watch members for a room - provides reactive updates
  ///
  /// @param roomId The room ID
  /// @return Stream of room members
  Stream<List<RoomMember>> watchMembersForRoom(String roomId) {
    final query = _database.select(_database.roomMembers)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]);

    return query.watch();
  }

  /// Get member count for a room
  ///
  /// @param roomId The room ID
  /// @return Number of members in the room
  Future<int> getMemberCount(String roomId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId));
      final members = await query.get();
      return members.length;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get member count',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  /// Check if a subscription ID belongs to the current profile's contact
  ///
  /// @param roomId The room context
  /// @param subscriptionId The subscription ID to check
  /// @param profileId The current profile's ID (can be empty for anonymous subscriptions)
  /// @param contactId The current contact's ID
  /// @return true if this subscription belongs to current profile's contact
  Future<bool> isCurrentUserSubscription(
    String roomId,
    String subscriptionId,
    String profileId,
    String contactId,
  ) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where(
          (t) =>
              t.roomId.equals(roomId) &
              t.subscriptionId.equals(subscriptionId) &
              t.contactId.equals(contactId) &
              // Only include profileId in query if it's not empty
              (profileId.isEmpty
                  ? t.profileId.isNull()
                  : t.profileId.equals(profileId)),
        );

      final member = await query.getSingleOrNull();
      return member != null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to check if subscription belongs to current profile',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Update a member's role in a room
  ///
  /// @param subscriptionId The subscription ID to update
  /// @param newRole The new role to assign
  /// @return true if update was successful
  Future<bool> updateMemberRole({
    required String subscriptionId,
    required String newRole,
  }) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.subscriptionId.equals(subscriptionId));

      final existingMember = await query.getSingleOrNull();
      if (existingMember == null) {
        AppLogger.warning(
          'Subscription not found for role update',
          data: {'subscriptionId': subscriptionId},
        );
        return false;
      }

      await (_database.update(_database.roomMembers)
            ..where((t) => t.subscriptionId.equals(subscriptionId)))
          .write(RoomMembersCompanion(role: Value(newRole)));

      AppLogger.info(
        'Member role updated successfully',
        data: {'subscriptionId': subscriptionId, 'newRole': newRole},
      );

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to update member role',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get all members with a specific role in a room
  ///
  /// @param roomId The room ID
  /// @param role The role to filter by
  /// @return List of room members with the specified role
  Future<List<RoomMember>> getMembersByRole(String roomId, String role) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where(
          (t) => t.roomId.equals(roomId) & t.role.equals(role.toLowerCase()),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.joinedAt)]);

      return await query.get();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get members by role',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Check if a profile is an admin of a room
  ///
  /// @param roomId The room ID
  /// @param profileId The profile ID to check
  /// @return true if the profile is an admin or owner
  Future<bool> isRoomAdmin(String roomId, String profileId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId) & t.profileId.equals(profileId));

      final member = await query.getSingleOrNull();
      if (member == null) return false;

      final role = member.role?.toLowerCase() ?? '';
      return role == 'admin' || role == 'owner';
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to check if profile is room admin',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Check if a profile is the owner of a room
  ///
  /// @param roomId The room ID
  /// @param profileId The profile ID to check
  /// @return true if the profile is the owner
  Future<bool> isRoomOwner(String roomId, String profileId) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId) & t.profileId.equals(profileId));

      final member = await query.getSingleOrNull();
      if (member == null) return false;

      final role = member.role?.toLowerCase() ?? '';
      return role == 'owner';
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to check if profile is room owner',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Get member by profile ID in a room
  ///
  /// @param roomId The room ID
  /// @param profileId The profile ID
  /// @return Room member if found, null otherwise
  Future<RoomMember?> getMemberByProfileId(
    String roomId,
    String profileId,
  ) async {
    try {
      final query = _database.select(_database.roomMembers)
        ..where((t) => t.roomId.equals(roomId) & t.profileId.equals(profileId));

      return await query.getSingleOrNull();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get member by profile ID',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
