import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'user_info_provider.dart';

part 'current_user_provider.g.dart';

/// Provider for the current user ID (from JWT 'sub' claim)
/// Returns null if the user is not authenticated or no user info is available
@riverpod
Future<String?> currentUserId(Ref ref) async {
  final userInfo = await ref.watch(userInfoProvider.future);
  return userInfo?.id;
}

/// Non-null version that throws if user ID is not available
/// Use this in contexts where authentication is required
@riverpod
Future<String> currentUserIdOrThrow(Ref ref) async {
  final userId = await ref.watch(currentUserIdProvider.future);
  if (userId == null) {
    throw Exception('User not authenticated - no user ID available');
  }
  return userId;
}
