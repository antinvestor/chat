// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'current_user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for the current user ID (from JWT 'sub' claim)
/// Returns null if the user is not authenticated or no user info is available

@ProviderFor(currentUserId)
final currentUserIdProvider = CurrentUserIdProvider._();

/// Provider for the current user ID (from JWT 'sub' claim)
/// Returns null if the user is not authenticated or no user info is available

final class CurrentUserIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// Provider for the current user ID (from JWT 'sub' claim)
  /// Returns null if the user is not authenticated or no user info is available
  CurrentUserIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserIdHash();

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    return currentUserId(ref);
  }
}

String _$currentUserIdHash() => r'14ab779e061d5b9a2bf25e93b779b95e65020e97';

/// Non-null version that throws if user ID is not available
/// Use this in contexts where authentication is required

@ProviderFor(currentUserIdOrThrow)
final currentUserIdOrThrowProvider = CurrentUserIdOrThrowProvider._();

/// Non-null version that throws if user ID is not available
/// Use this in contexts where authentication is required

final class CurrentUserIdOrThrowProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// Non-null version that throws if user ID is not available
  /// Use this in contexts where authentication is required
  CurrentUserIdOrThrowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserIdOrThrowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserIdOrThrowHash();

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    return currentUserIdOrThrow(ref);
  }
}

String _$currentUserIdOrThrowHash() =>
    r'013a32b246a3329f037a0f0e13bdde0608342112';
