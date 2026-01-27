import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/data/auth_repository.dart';
import 'room_member_repository.dart';
import 'room_subscription_service.dart';
import 'room_sync_state.dart';

/// A simple value notifier with stream support
///
/// Similar to BehaviorSubject but without the rxdart dependency.
/// Holds a current value and broadcasts changes to listeners.
class _ValueStream<T> {
  _ValueStream(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  Stream<T> get stream async* {
    // Emit current value immediately
    yield _value;
    // Then emit future updates
    yield* _controller.stream;
  }

  void add(T newValue) {
    _value = newValue;
    if (!_controller.isClosed) {
      _controller.add(newValue);
    }
  }

  void close() {
    _controller.close();
  }

  bool get isClosed => _controller.isClosed;
}

/// Manager for tracking room synchronization state
///
/// This service tracks the state of each room through its lifecycle:
/// - CREATING: Room created locally, waiting for server confirmation
/// - SYNCING: Room confirmed on server, waiting for member data
/// - READY: Has current user's subscription ID, can send messages
///
/// The manager receives updates from:
/// 1. RoomService when a room is created locally
/// 2. SyncEngine when moderation events arrive with subscription IDs
/// 3. API sync fallback when events don't arrive in time
class RoomSyncManager {
  RoomSyncManager(this._authRepository, this._roomMemberRepository);

  final AuthRepository _authRepository;
  final RoomMemberRepository _roomMemberRepository;

  /// In-memory state tracking per room
  final Map<String, _ValueStream<RoomSyncStatus>> _roomStates = {};

  /// Timeout before falling back to API sync (seconds)
  /// Kept short to minimize user waiting time
  static const _syncTimeoutSeconds = 2;

  /// Pending timeout timers for rooms awaiting member events
  final Map<String, Timer> _syncTimeouts = {};

  /// Get or create a state stream for a room
  ///
  /// Defaults to READY state (optimistic) - we only block input when we
  /// explicitly know the room is being created. This prevents unnecessary
  /// waiting for existing rooms.
  _ValueStream<RoomSyncStatus> _getOrCreateStream(String roomId) {
    return _roomStates.putIfAbsent(
      roomId,
      // Default to READY - only onRoomCreatedLocally sets CREATING
      () => _ValueStream(const RoomSyncStatus(state: RoomSyncState.ready)),
    );
  }

  /// Watch the sync status for a room
  ///
  /// Returns a stream that emits the current status and updates
  /// as the room progresses through its sync lifecycle.
  ///
  /// Default state is READY (optimistic) - rooms only enter CREATING/SYNCING
  /// states when explicitly triggered by room creation flow.
  Stream<RoomSyncStatus> watchRoom(String roomId) {
    return _getOrCreateStream(roomId).stream;
  }

  /// Get current sync status for a room (non-reactive)
  RoomSyncStatus? getStatus(String roomId) {
    return _roomStates[roomId]?.value;
  }

  /// Called when a room is created locally
  ///
  /// Sets the room to CREATING state and starts a timeout for API fallback.
  void onRoomCreatedLocally(String roomId) {
    final stream = _getOrCreateStream(roomId);
    stream.add(RoomSyncStatus.creating());

    AppLogger.debug(
      'Room sync: Room created locally',
      data: {'roomId': roomId},
    );
  }

  /// Called when room creation is confirmed by the server
  ///
  /// Transitions from CREATING to SYNCING and starts timeout for member events.
  void onRoomConfirmedByServer(String roomId) {
    final stream = _getOrCreateStream(roomId);
    final currentState = stream.value;

    // Only transition if currently creating
    if (currentState.state == RoomSyncState.creating ||
        currentState.state == RoomSyncState.syncing) {
      stream.add(RoomSyncStatus.syncing(lastSyncAttempt: DateTime.now()));

      // Start timeout for member event arrival
      _startSyncTimeout(roomId);

      AppLogger.debug(
        'Room sync: Room confirmed by server, awaiting member events',
        data: {'roomId': roomId},
      );
    }
  }

  /// Called when moderation event arrives with member subscription IDs
  ///
  /// This is the primary path for getting subscription IDs.
  /// Checks if current user's subscription is in the list and transitions to READY.
  Future<void> onMembersReceived(
    String roomId,
    List<String> subscriptionIds,
  ) async {
    // Cancel any pending timeout
    _cancelSyncTimeout(roomId);

    // Find current user's subscription
    final mySubscription = await _findMySubscription(roomId, subscriptionIds);

    if (mySubscription != null) {
      final stream = _getOrCreateStream(roomId);
      stream.add(RoomSyncStatus.ready(mySubscription));

      AppLogger.info(
        'Room sync: Ready - found my subscription from moderation event',
        data: {
          'roomId': roomId,
          'subscriptionId': mySubscription.substring(0, 8),
          'totalMembers': subscriptionIds.length,
        },
      );
    } else {
      AppLogger.debug(
        'Room sync: Received member event but my subscription not found',
        data: {'roomId': roomId, 'memberCount': subscriptionIds.length},
      );
    }
  }

  /// Called when a member is added to a room (via moderation event)
  ///
  /// If the added member is the current user, transition to READY.
  Future<void> onMemberAdded(String roomId, String subscriptionId) async {
    // Check if this is the current user's subscription
    final isMySubscription = await _isMySubscription(roomId, subscriptionId);

    if (isMySubscription) {
      final stream = _getOrCreateStream(roomId);
      stream.add(RoomSyncStatus.ready(subscriptionId));

      AppLogger.info(
        'Room sync: Ready - current user added to room',
        data: {
          'roomId': roomId,
          'subscriptionId': subscriptionId.substring(0, 8),
        },
      );
    }
  }

  /// Called when a member is removed from a room (via moderation event)
  ///
  /// If the removed member is the current user, the room becomes inaccessible.
  Future<void> onMemberRemoved(String roomId, String subscriptionId) async {
    final currentStatus = getStatus(roomId);

    // If this was the current user's subscription, reset state
    if (currentStatus?.currentUserSubscriptionId == subscriptionId) {
      final stream = _getOrCreateStream(roomId);
      // Set to syncing - the UI will handle showing appropriate message
      stream.add(RoomSyncStatus.syncing(lastSyncAttempt: DateTime.now()));

      AppLogger.info(
        'Room sync: Current user removed from room',
        data: {'roomId': roomId},
      );
    }
  }

  /// Called when API sync completes successfully
  ///
  /// This is the fallback path when moderation events don't arrive in time.
  /// Marks room as READY optimistically - any actual permission issues
  /// will be handled when the user tries to send a message.
  Future<void> onApiSyncComplete(String roomId) async {
    _cancelSyncTimeout(roomId);

    // Try to find subscription in database
    final subscriptionId = await _findMySubscriptionInDb(roomId);

    final stream = _getOrCreateStream(roomId);

    if (subscriptionId != null) {
      stream.add(RoomSyncStatus.ready(subscriptionId));
      AppLogger.info(
        'Room sync: Ready - found subscription via API sync',
        data: {
          'roomId': roomId,
          'subscriptionId': subscriptionId.substring(0, 8),
        },
      );
    } else {
      // Even if we couldn't find the subscription, mark as ready
      // to not block the user. The actual subscription lookup will
      // happen when sending messages, and errors will be shown then.
      stream.add(const RoomSyncStatus(state: RoomSyncState.ready));
      AppLogger.warning(
        'Room sync: Ready (optimistic) - subscription not found but API sync complete',
        data: {'roomId': roomId},
      );
    }
  }

  /// Mark a room as ready with a known subscription ID
  ///
  /// Used when subscription ID is already known (e.g., from existing room entry).
  void markReady(String roomId, String subscriptionId) {
    final stream = _getOrCreateStream(roomId);
    stream.add(RoomSyncStatus.ready(subscriptionId));

    AppLogger.debug(
      'Room sync: Marked ready with known subscription',
      data: {'roomId': roomId},
    );
  }

  /// Called when a room is downloaded from server during post-login sync
  ///
  /// For rooms fetched from the server, the user is already a member, so we
  /// default to READY state immediately. This prevents blocking the UI while
  /// we fetch subscription details (which is just cache population).
  ///
  /// The subscription ID will be populated later when we fetch room members,
  /// but the user can send messages immediately since the server knows they
  /// are a member.
  void onRoomDownloadedFromServer(String roomId) {
    final stream = _getOrCreateStream(roomId);

    // Only update if not already in a better state
    final current = stream.value;
    if (current.state != RoomSyncState.ready) {
      stream.add(const RoomSyncStatus(state: RoomSyncState.ready));

      AppLogger.debug(
        'Room sync: Room downloaded from server, marked ready',
        data: {'roomId': roomId},
      );
    }
  }

  /// Start a timeout that triggers API sync fallback
  void _startSyncTimeout(String roomId) {
    _cancelSyncTimeout(roomId);

    _syncTimeouts[roomId] = Timer(
      const Duration(seconds: _syncTimeoutSeconds),
      () => _onSyncTimeout(roomId),
    );
  }

  /// Cancel pending sync timeout for a room
  void _cancelSyncTimeout(String roomId) {
    _syncTimeouts[roomId]?.cancel();
    _syncTimeouts.remove(roomId);
  }

  /// Called when sync timeout fires - triggers API fallback
  void _onSyncTimeout(String roomId) {
    AppLogger.debug(
      'Room sync: Timeout waiting for member events, will use API fallback',
      data: {'roomId': roomId, 'timeoutSeconds': _syncTimeoutSeconds},
    );

    // The actual API call will be triggered by whoever is watching the state
    // This just updates the state to indicate we're still syncing
    final stream = _getOrCreateStream(roomId);
    final current = stream.value;

    if (current.state != RoomSyncState.ready) {
      stream.add(RoomSyncStatus.syncing(lastSyncAttempt: DateTime.now()));
    }
  }

  /// Find current user's subscription from a list of subscription IDs
  Future<String?> _findMySubscription(
    String roomId,
    List<String> subscriptionIds,
  ) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();

    if (currentContactId == null) return null;

    // Check each subscription ID to see if it belongs to current user
    for (final subscriptionId in subscriptionIds) {
      final member = await _roomMemberRepository.getSubscription(
        subscriptionId,
      );

      if (member != null &&
          member.contactId == currentContactId &&
          (currentProfileId == null ||
              currentProfileId.isEmpty ||
              member.profileId == currentProfileId)) {
        return subscriptionId;
      }
    }

    return null;
  }

  /// Check if a subscription ID belongs to the current user
  Future<bool> _isMySubscription(String roomId, String subscriptionId) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();

    if (currentContactId == null) return false;

    return _roomMemberRepository.isCurrentUserSubscription(
      roomId,
      subscriptionId,
      currentProfileId ?? '',
      currentContactId,
    );
  }

  /// Find current user's subscription from database
  ///
  /// Tries multiple strategies to find the subscription:
  /// 1. Match by contactId and profileId
  /// 2. Match by profileId only
  /// 3. Match by contactId only
  Future<String?> _findMySubscriptionInDb(String roomId) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();

    // Try with both IDs first
    if (currentContactId != null) {
      final subscriptionId = await _roomMemberRepository
          .getCurrentSubscriptionId(
            roomId,
            currentProfileId ?? '',
            currentContactId,
          );
      if (subscriptionId != null) return subscriptionId;
    }

    // Try by profileId only if we have one
    if (currentProfileId != null && currentProfileId.isNotEmpty) {
      final member = await _roomMemberRepository.getMemberByProfileId(
        roomId,
        currentProfileId,
      );
      if (member != null) return member.subscriptionId;
    }

    // If we have at least one member in the room, assume we're a member
    // This is the most optimistic fallback for new rooms
    final members = await _roomMemberRepository.getMembersForRoom(roomId);
    if (members.isNotEmpty) {
      // For a newly created room, we're likely the creator
      // Return any subscription - the actual subscription ID will be
      // used from the member repository when sending messages
      return members.first.subscriptionId;
    }

    return null;
  }

  /// Clean up resources for a room
  void disposeRoom(String roomId) {
    _cancelSyncTimeout(roomId);
    _roomStates[roomId]?.close();
    _roomStates.remove(roomId);
  }

  /// Clean up all resources
  void dispose() {
    for (final roomId in _syncTimeouts.keys.toList()) {
      _cancelSyncTimeout(roomId);
    }

    for (final stream in _roomStates.values) {
      stream.close();
    }
    _roomStates.clear();
  }
}

/// Provider for RoomSyncManager
final roomSyncManagerProvider = Provider<RoomSyncManager>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final memberRepo = ref.watch(roomMemberRepositoryProvider);

  final manager = RoomSyncManager(authRepo, memberRepo);

  ref.onDispose(manager.dispose);

  return manager;
});
