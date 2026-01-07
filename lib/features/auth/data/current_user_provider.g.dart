// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'current_user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for the current user's PROFILE ID (from JWT 'sub' claim)
/// This represents the entity (person/organization) identity
/// NOT to be confused with contact ID or subscription ID
/// Returns null if the user is not authenticated or no profile info is available

@ProviderFor(currentUserId)
final currentUserIdProvider = CurrentUserIdProvider._();

/// Provider for the current user's PROFILE ID (from JWT 'sub' claim)
/// This represents the entity (person/organization) identity
/// NOT to be confused with contact ID or subscription ID
/// Returns null if the user is not authenticated or no profile info is available

final class CurrentUserIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// Provider for the current user's PROFILE ID (from JWT 'sub' claim)
  /// This represents the entity (person/organization) identity
  /// NOT to be confused with contact ID or subscription ID
  /// Returns null if the user is not authenticated or no profile info is available
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

/// Non-null version that throws if profile ID is not available
/// Use this in contexts where authentication is required

@ProviderFor(currentUserIdOrThrow)
final currentUserIdOrThrowProvider = CurrentUserIdOrThrowProvider._();

/// Non-null version that throws if profile ID is not available
/// Use this in contexts where authentication is required

final class CurrentUserIdOrThrowProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// Non-null version that throws if profile ID is not available
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
    r'11e186065db5618fe13075035d5f8abb1d923cd9';
