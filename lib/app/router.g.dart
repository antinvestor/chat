// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for the auth change notifier

@ProviderFor(authChangeNotifier)
final authChangeProvider = AuthChangeNotifierProvider._();

/// Provider for the auth change notifier

final class AuthChangeNotifierProvider
    extends
        $FunctionalProvider<
          AuthChangeNotifier,
          AuthChangeNotifier,
          AuthChangeNotifier
        >
    with $Provider<AuthChangeNotifier> {
  /// Provider for the auth change notifier
  AuthChangeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authChangeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authChangeNotifierHash();

  @$internal
  @override
  $ProviderElement<AuthChangeNotifier> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AuthChangeNotifier create(Ref ref) {
    return authChangeNotifier(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthChangeNotifier value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthChangeNotifier>(value),
    );
  }
}

String _$authChangeNotifierHash() =>
    r'909b689b91d50d4b5a2ca08c721b201beae7b44b';

@ProviderFor(router)
final routerProvider = RouterProvider._();

final class RouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  RouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routerHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return router(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$routerHash() => r'b53793f95a89a30bc3382d741838227f39715aef';
