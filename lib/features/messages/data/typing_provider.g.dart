// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'typing_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Typing)
final typingProvider = TypingFamily._();

final class TypingProvider extends $NotifierProvider<Typing, Set<String>> {
  TypingProvider._({
    required TypingFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'typingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$typingHash();

  @override
  String toString() {
    return r'typingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  Typing create() => Typing();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TypingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$typingHash() => r'a1922d69aa196b4dd1797166378c1690aca3a7ef';

final class TypingFamily extends $Family
    with
        $ClassFamilyOverride<
          Typing,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  TypingFamily._()
    : super(
        retry: null,
        name: r'typingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TypingProvider call(String roomId) =>
      TypingProvider._(argument: roomId, from: this);

  @override
  String toString() => r'typingProvider';
}

abstract class _$Typing extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get roomId => _$args;

  Set<String> build(String roomId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
