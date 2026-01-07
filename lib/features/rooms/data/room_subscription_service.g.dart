// GENERATED CODE - DO NOT MODIFY BY HAND
part of 'room_subscription_service.dart';

// **************************************************************************
// Riverpod Generator
// **************************************************************************

/// Provider for RoomSubscriptionService
final roomSubscriptionServiceProvider = Provider<RoomSubscriptionService>((
  ref,
) {
  return RoomSubscriptionService(ref.watch(roomMemberRepositoryProvider));
});
