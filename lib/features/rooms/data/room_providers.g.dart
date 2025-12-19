// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(roomRepository)
const roomRepositoryProvider = RoomRepositoryProvider._();

final class RoomRepositoryProvider
    extends $FunctionalProvider<RoomRepository, RoomRepository, RoomRepository>
    with $Provider<RoomRepository> {
  const RoomRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomRepositoryHash();

  @$internal
  @override
  $ProviderElement<RoomRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomRepository create(Ref ref) {
    return roomRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomRepository>(value),
    );
  }
}

String _$roomRepositoryHash() => r'8599dc9bf5fc727e8556974fdaedabbe3a8c28ce';

@ProviderFor(RoomList)
const roomListProvider = RoomListProvider._();

final class RoomListProvider
    extends $AsyncNotifierProvider<RoomList, List<domain.Room>> {
  const RoomListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomListHash();

  @$internal
  @override
  RoomList create() => RoomList();
}

String _$roomListHash() => r'4998cc462eeff2dfd5f61d1c2eb71ead5f56e6be';

abstract class _$RoomList extends $AsyncNotifier<List<domain.Room>> {
  FutureOr<List<domain.Room>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<List<domain.Room>>, List<domain.Room>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<domain.Room>>, List<domain.Room>>,
              AsyncValue<List<domain.Room>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(RoomListWithMessages)
const roomListWithMessagesProvider = RoomListWithMessagesProvider._();

final class RoomListWithMessagesProvider
    extends
        $AsyncNotifierProvider<
          RoomListWithMessages,
          List<RoomWithLastMessage>
        > {
  const RoomListWithMessagesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomListWithMessagesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomListWithMessagesHash();

  @$internal
  @override
  RoomListWithMessages create() => RoomListWithMessages();
}

String _$roomListWithMessagesHash() =>
    r'7b3ee5491e207673bdca7ee7377b0c9f9ba72d35';

abstract class _$RoomListWithMessages
    extends $AsyncNotifier<List<RoomWithLastMessage>> {
  FutureOr<List<RoomWithLastMessage>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<RoomWithLastMessage>>,
              List<RoomWithLastMessage>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<RoomWithLastMessage>>,
                List<RoomWithLastMessage>
              >,
              AsyncValue<List<RoomWithLastMessage>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
