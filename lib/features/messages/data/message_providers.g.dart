// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(messageRepository)
const messageRepositoryProvider = MessageRepositoryProvider._();

final class MessageRepositoryProvider
    extends
        $FunctionalProvider<
          MessageRepository,
          MessageRepository,
          MessageRepository
        >
    with $Provider<MessageRepository> {
  const MessageRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'messageRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$messageRepositoryHash();

  @$internal
  @override
  $ProviderElement<MessageRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MessageRepository create(Ref ref) {
    return messageRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MessageRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MessageRepository>(value),
    );
  }
}

String _$messageRepositoryHash() => r'ddb39a1137562c50f3a63b77fe08d4c8652b1da6';

@ProviderFor(MessageList)
const messageListProvider = MessageListFamily._();

final class MessageListProvider
    extends $AsyncNotifierProvider<MessageList, List<RoomEvent>> {
  const MessageListProvider._({
    required MessageListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'messageListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$messageListHash();

  @override
  String toString() {
    return r'messageListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MessageList create() => MessageList();

  @override
  bool operator ==(Object other) {
    return other is MessageListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$messageListHash() => r'ba45e25728e37c995cb43adfd5fe486a9a437db7';

final class MessageListFamily extends $Family
    with
        $ClassFamilyOverride<
          MessageList,
          AsyncValue<List<RoomEvent>>,
          List<RoomEvent>,
          FutureOr<List<RoomEvent>>,
          String
        > {
  const MessageListFamily._()
    : super(
        retry: null,
        name: r'messageListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MessageListProvider call(String roomId) =>
      MessageListProvider._(argument: roomId, from: this);

  @override
  String toString() => r'messageListProvider';
}

abstract class _$MessageList extends $AsyncNotifier<List<RoomEvent>> {
  late final _$args = ref.$arg as String;
  String get roomId => _$args;

  FutureOr<List<RoomEvent>> build(String roomId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<AsyncValue<List<RoomEvent>>, List<RoomEvent>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<RoomEvent>>, List<RoomEvent>>,
              AsyncValue<List<RoomEvent>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
