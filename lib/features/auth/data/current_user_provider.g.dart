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

@ProviderFor(currentProfileId)
final currentProfileIdProvider = CurrentProfileIdProvider._();

/// Provider for the current user's PROFILE ID (from JWT 'sub' claim)
/// This represents the entity (person/organization) identity
/// NOT to be confused with contact ID or subscription ID
/// Returns null if the user is not authenticated or no profile info is available

final class CurrentProfileIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// Provider for the current user's PROFILE ID (from JWT 'sub' claim)
  /// This represents the entity (person/organization) identity
  /// NOT to be confused with contact ID or subscription ID
  /// Returns null if the user is not authenticated or no profile info is available
  CurrentProfileIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentProfileIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentProfileIdHash();

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    return currentProfileId(ref);
  }
}

String _$currentProfileIdHash() => r'd0baf85ca2059f938b8b3a4e8147f41ab9513f8c';

/// Non-null version that throws if profile ID is not available
/// Use this in contexts where authentication is required

@ProviderFor(currentProfileIdOrThrow)
final currentProfileIdOrThrowProvider = CurrentProfileIdOrThrowProvider._();

/// Non-null version that throws if profile ID is not available
/// Use this in contexts where authentication is required

final class CurrentProfileIdOrThrowProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// Non-null version that throws if profile ID is not available
  /// Use this in contexts where authentication is required
  CurrentProfileIdOrThrowProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentProfileIdOrThrowProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentProfileIdOrThrowHash();

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    return currentProfileIdOrThrow(ref);
  }
}

String _$currentProfileIdOrThrowHash() =>
    r'0725a0d41e7cae441b04332a5f466173d9969f66';
