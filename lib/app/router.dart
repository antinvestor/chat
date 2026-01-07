import 'package:flutter/foundation.dart';

import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/auth_state_provider.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/messages/ui/chat_screen.dart';
import '../features/rooms/ui/room_list_screen.dart';
import '../features/rooms/ui/room_detail_screen.dart';

part 'router.g.dart';

/// Notifier that triggers router refresh when auth state changes
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(Ref ref) {
    // Listen to auth state changes and notify router to re-evaluate redirects
    ref.listen(authStateProvider, (previous, next) {
      notifyListeners();
    });
  }
}

/// Provider for the auth change notifier
@riverpod
AuthChangeNotifier authChangeNotifier(Ref ref) {
  return AuthChangeNotifier(ref);
}

@riverpod
GoRouter router(Ref ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final authChangeNotifier = ref.watch(authChangeProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authChangeNotifier,
    redirect: (context, state) async {
      final isLoggedIn = await authRepository.isLoggedIn();
      final isLoginRoute = state.matchedLocation == '/login';

      // If not logged in and not on login page, redirect to login
      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      // If logged in and on login page, go to home
      if (isLoggedIn && isLoginRoute) {
        return '/';
      }

      return null; // No redirect needed
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/', builder: (context, state) => const RoomListScreen()),
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId']!;
          final roomName = state.uri.queryParameters['name'] ?? 'Chat';
          return ChatScreen(roomId: roomId, roomName: roomName);
        },
      ),
      GoRoute(
        path: '/room/:roomId/details',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId']!;
          final roomName = state.uri.queryParameters['name'] ?? 'Room Details';
          return RoomDetailScreen(roomId: roomId, roomName: roomName);
        },
      ),
    ],
  );
}
