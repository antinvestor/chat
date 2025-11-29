import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/room_providers.dart';
import '../domain/room_with_last_message.dart';
import 'room_list_tile.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../../widgets/connection_banner.dart';
import '../../calls/ui/incoming_call_banner.dart';
import '../../../core/error/app_error.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../messages/ui/chat_screen.dart';
import '../../contacts/ui/contacts_screen.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  String? _selectedRoomId;
  String? _selectedRoomName;

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListWithMessagesProvider);
    final width = MediaQuery.of(context).size.width;
    final isLargeScreen = AppBreakpoints.isTablet(width) || AppBreakpoints.isDesktop(width);

    return Scaffold(
      appBar: isLargeScreen ? null : AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Navigate to create room screen
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const ConnectionBanner(),
              const IncomingCallBanner(),
              Expanded(
                child: isLargeScreen
                    ? Row(
                        children: [
                          SizedBox(
                            width: 350,
                            child: Scaffold(
                              appBar: AppBar(
                                title: const Text('Chats'),
                                actions: [
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      // TODO: Navigate to create room screen
                                    },
                                  ),
                                ],
                              ),
                              body: _buildRoomList(roomsAsync, isLargeScreen),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _selectedRoomId != null
                                ? ChatScreen(
                                    roomId: _selectedRoomId!,
                                    roomName: _selectedRoomName ?? 'Chat',
                                    key: ValueKey(_selectedRoomId),
                                  )
                                : const EmptyState(
                                    icon: Icons.chat_bubble_outline,
                                    title: 'Select a conversation',
                                    message: 'Choose a room from the list to start chatting',
                                  ),
                          ),
                        ],
                      )
                    : _buildRoomList(roomsAsync, isLargeScreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomList(AsyncValue<List<RoomWithLastMessage>> roomsAsync, bool isLargeScreen) {
    return Column(
      children: [
        Expanded(
          child: roomsAsync.when(
            data: (rooms) {
              if (rooms.isEmpty) {
                return EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'No conversations yet',
                  message: 'Start a new conversation to begin chatting',
                  actionLabel: 'New Chat',
                  onAction: () {
                    // TODO: Navigate to create room screen
                  },
                );
              }
              return ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  final isSelected = isLargeScreen && room.id == _selectedRoomId;
                  
                  return Container(
                    color: isSelected ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
                    child: RoomListTile(
                      room: room,
                      onTap: () {
                        if (isLargeScreen) {
                          setState(() {
                            _selectedRoomId = room.id;
                            _selectedRoomName = room.name;
                          });
                        } else {
                          context.go('/chat/${room.id}?name=${Uri.encodeComponent(room.name)}');
                        }
                      },
                    ),
                  );
                },
              );
            },
            loading: () => ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) => const RoomListSkeleton(),
            ),
            error: (error, stack) {
              final appError = AppError.fromException(error, stack);
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ErrorBanner(
                      error: appError,
                      onRetry: () => ref.refresh(roomListWithMessagesProvider),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load rooms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
