import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import 'room_member_repository.dart';

part 'room_subscription_service.g.dart';

/// Provider for RoomMemberRepository
final roomMemberRepositoryProvider = Provider<RoomMemberRepository>((ref) => RoomMemberRepository(AppDatabase.instance));

/// Service for managing room subscriptions and profile ID updates
/// Handles anonymous subscriptions and profile ID updates
/// Uses RoomMemberRepository for all database operations
class RoomSubscriptionService {

  RoomSubscriptionService(this._repository);
  final RoomMemberRepository _repository;

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
  }) async => _repository.updateSubscriptionProfile(
      subscriptionId: subscriptionId,
      profileId: profileId,
      contactId: contactId,
    );

  /// Get all subscriptions for a profile across all rooms
  /// Useful for finding all rooms a user is subscribed to
  ///
  /// @param profileId The profile ID to search for
  /// @return List of room memberships for this profile
  Future<List<RoomMember>> getProfileSubscriptions(String profileId) async => _repository.getProfileSubscriptions(profileId);

  /// Get all subscriptions without a profile ID (anonymous subscriptions)
  /// Useful for finding subscriptions that need profile assignment
  ///
  /// @param roomId Optional room filter
  /// @return List of anonymous subscriptions
  Future<List<RoomMember>> getAnonymousSubscriptions({String? roomId}) async => _repository.getAnonymousSubscriptions(roomId: roomId);

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
  }) async => _repository.createSubscription(
      subscriptionId: subscriptionId,
      roomId: roomId,
      profileId: profileId,
      contactId: contactId,
      role: role,
    );

  /// Remove a subscription from a room
  ///
  /// @param subscriptionId The subscription ID to remove
  /// @return true if removal was successful
  Future<bool> removeSubscription(String subscriptionId) async => _repository.removeSubscription(subscriptionId);

  /// Check if a subscription exists for a profile in a room
  ///
  /// @param roomId The room ID
  /// @param profileId The profile ID
  /// @return true if subscription exists
  Future<bool> hasSubscription(String roomId, String profileId) async => _repository.hasSubscription(roomId, profileId);

  /// Get subscription by subscription ID
  ///
  /// @param subscriptionId The subscription ID
  /// @return Room member if found, null otherwise
  Future<RoomMember?> getSubscription(String subscriptionId) async => _repository.getSubscription(subscriptionId);

  /// Get current profile's subscription ID for a specific room
  /// Returns null if the profile is not a member of the room
  ///
  /// @param roomId The room ID
  /// @param profileId The current profile's ID
  /// @param contactId The current contact's ID
  /// @return Subscription ID if found, null otherwise
  Future<String?> getCurrentSubscriptionId(
    String roomId,
    String profileId,
    String contactId,
  ) async => _repository.getCurrentSubscriptionId(
      roomId,
      profileId,
      contactId,
    );

  /// Check if a subscription ID belongs to the current profile's contact
  ///
  /// @param roomId The room context
  /// @param subscriptionId The subscription ID to check
  /// @param profileId The current profile's ID
  /// @param contactId The current contact's ID
  /// @return true if this subscription belongs to current profile's contact
  Future<bool> isCurrentUserSubscription(
    String roomId,
    String subscriptionId,
    String profileId,
    String contactId,
  ) async => _repository.isCurrentUserSubscription(
      roomId,
      subscriptionId,
      profileId,
      contactId,
    );
}

/// Provider for RoomSubscriptionService
@riverpod
RoomSubscriptionService roomSubscriptionService(Ref ref) => RoomSubscriptionService(RoomMemberRepository(AppDatabase.instance));
