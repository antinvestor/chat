// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(RoomList)
final roomListProvider = RoomListProvider._();

final class RoomListProvider
    extends $AsyncNotifierProvider<RoomList, List<domain.Room>> {
  RoomListProvider._()
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

String _$roomListHash() => r'5201fece779454e434bdb02eb6b05fe72eca1f83';

abstract class _$RoomList extends $AsyncNotifier<List<domain.Room>> {
  FutureOr<List<domain.Room>> build();
  @$mustCallSuper
  @override
  void runBuild() {
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
    element.handleCreate(ref, build);
  }
}

@ProviderFor(RoomListWithMessages)
final roomListWithMessagesProvider = RoomListWithMessagesProvider._();

final class RoomListWithMessagesProvider
    extends
        $AsyncNotifierProvider<
          RoomListWithMessages,
          List<RoomWithLastMessage>
        > {
  RoomListWithMessagesProvider._()
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
    element.handleCreate(ref, build);
  }
}
