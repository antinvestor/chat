// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_subscription_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for RoomSubscriptionService

@ProviderFor(roomSubscriptionService)
final roomSubscriptionServiceProvider = RoomSubscriptionServiceProvider._();

/// Provider for RoomSubscriptionService

final class RoomSubscriptionServiceProvider
    extends
        $FunctionalProvider<
          RoomSubscriptionService,
          RoomSubscriptionService,
          RoomSubscriptionService
        >
    with $Provider<RoomSubscriptionService> {
  /// Provider for RoomSubscriptionService
  RoomSubscriptionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomSubscriptionServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomSubscriptionServiceHash();

  @$internal
  @override
  $ProviderElement<RoomSubscriptionService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RoomSubscriptionService create(Ref ref) {
    return roomSubscriptionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomSubscriptionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomSubscriptionService>(value),
    );
  }
}

String _$roomSubscriptionServiceHash() =>
    r'5f5dd3d1b081216e469ae9ab8cc70b2e87b1c345';
