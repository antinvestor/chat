// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contact_sync_orchestrator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for ContactSyncOrchestrator

@ProviderFor(contactSyncOrchestrator)
final contactSyncOrchestratorProvider = ContactSyncOrchestratorProvider._();

/// Provider for ContactSyncOrchestrator

final class ContactSyncOrchestratorProvider
    extends
        $FunctionalProvider<
          AsyncValue<ContactSyncOrchestrator>,
          ContactSyncOrchestrator,
          FutureOr<ContactSyncOrchestrator>
        >
    with
        $FutureModifier<ContactSyncOrchestrator>,
        $FutureProvider<ContactSyncOrchestrator> {
  /// Provider for ContactSyncOrchestrator
  ContactSyncOrchestratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contactSyncOrchestratorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contactSyncOrchestratorHash();

  @$internal
  @override
  $FutureProviderElement<ContactSyncOrchestrator> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ContactSyncOrchestrator> create(Ref ref) {
    return contactSyncOrchestrator(ref);
  }
}

String _$contactSyncOrchestratorHash() =>
    r'a1068aedbcfbbbbeeebf4758cfeb0cd0cbfeb46b';

/// Provider to check if contact sync is initialized

@ProviderFor(contactSyncInitialized)
final contactSyncInitializedProvider = ContactSyncInitializedProvider._();

/// Provider to check if contact sync is initialized

final class ContactSyncInitializedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider to check if contact sync is initialized
  ContactSyncInitializedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contactSyncInitializedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contactSyncInitializedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return contactSyncInitialized(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$contactSyncInitializedHash() =>
    r'9d08a0be29ca915fc719e251814e2b46601cf862';
