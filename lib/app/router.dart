import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../features/rooms/ui/room_list_screen.dart';
import '../features/messages/ui/chat_screen.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/data/auth_repository.dart';

part 'router.g.dart';

@riverpod
GoRouter router(Ref ref) {
  final authRepository = ref.watch(authRepositoryProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final isLoggedIn = await authRepository.isLoggedIn();
      final isLoginRoute = state.matchedLocation == '/login';

      // If not logged in and not on login page, redirect to login
      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      // If logged in and on login page, redirect to home
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
    ],
  );
}
