import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../calls/ui/incoming_call_banner.dart';
import '../../contacts/data/contact_sync_repository.dart';
import '../../contacts/ui/contact_sync_sheet.dart';
import '../../contacts/ui/contacts_screen.dart';
import '../../messages/ui/chat_screen.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/room_providers.dart';
import '../domain/room_with_last_message.dart';
import 'new_chat_screen.dart';
import 'room_list_tile.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  String? _selectedRoomId;
  String? _selectedRoomName;
  bool _hasCheckedContactSync = false;

  @override
  void initState() {
    super.initState();
    // Check if contact sync is needed after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowContactSync();
    });
  }

  Future<void> _checkAndShowContactSync() async {
    if (_hasCheckedContactSync) return;
    _hasCheckedContactSync = true;

    final onboardingRepo = ref.read(onboardingRepositoryProvider);
    final hasContactsSynced = await onboardingRepo.hasContactsSynced();
    
    // Also check if there are any profiles in the database
    final repo = await ref.read(rosterRepositoryProvider.future);
    final existingProfiles = await repo.getProfilesWithContacts();
    final hasProfiles = existingProfiles.isNotEmpty;
    
    AppLogger.debug('[RoomList] Contact sync check', data: {
      'hasContactsSynced': hasContactsSynced,
      'existingProfileCount': existingProfiles.length,
    });
    
    // Show sync sheet if never synced OR if there are no profiles to use
    if ((!hasContactsSynced || !hasProfiles) && mounted) {
      AppLogger.info('[RoomList] Showing contact sync sheet', data: {
        'reason': !hasContactsSynced ? 'never synced' : 'no profiles found',
      });
      
      await showContactSyncSheet(
        context: context,
        repository: repo,
        onComplete: () {
          AppLogger.info('[RoomList] Contact sync completed via sheet');
          onboardingRepo.markContactsSynced();
          // Refresh the profiles provider to show new contacts
          ref.invalidate(profilesWithContactsProvider);
        },
        onDismiss: () {
          AppLogger.info('[RoomList] Contact sync skipped by user');
          onboardingRepo.markContactsSynced();
        },
      );
    } else {
      AppLogger.debug('[RoomList] Contacts already synced with profiles available');
    }
  }

  void _navigateToNewChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }

  void _navigateToContacts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListWithMessagesProvider);
    final width = MediaQuery.of(context).size.width;
    final isLargeScreen =
        AppBreakpoints.isTablet(width) || AppBreakpoints.isDesktop(width);

    return Scaffold(
      appBar: isLargeScreen
          ? null
          : AppBar(
              title: const Text('Chats'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.contacts_outlined),
                  onPressed: _navigateToContacts,
                  tooltip: 'Contacts',
                ),
              ],
            ),
      drawer: isLargeScreen ? null : const AppDrawer(),
      floatingActionButton: isLargeScreen
          ? null
          : FloatingActionButton(
              onPressed: _navigateToNewChat,
              tooltip: 'New Chat',
              child: const Icon(Icons.chat_bubble_outline),
            ),
      body: Stack(
        children: [
          Column(
            children: [
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
                                    icon: const Icon(Icons.contacts_outlined),
                                    onPressed: _navigateToContacts,
                                    tooltip: 'Contacts',
                                  ),
                                ],
                              ),
                              drawer: const AppDrawer(),
                              floatingActionButton: FloatingActionButton(
                                onPressed: _navigateToNewChat,
                                tooltip: 'New Chat',
                                child: const Icon(Icons.chat_bubble_outline),
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
                                    message:
                                        'Choose a room from the list to start chatting',
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

  Widget _buildRoomList(
    AsyncValue<List<RoomWithLastMessage>> roomsAsync,
    bool isLargeScreen,
  ) {
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
                  onAction: _navigateToNewChat,
                );
              }
              return ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  final isSelected =
                      isLargeScreen && room.id == _selectedRoomId;

                  return Container(
                    color: isSelected
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : null,
                    child: RoomListTile(
                      room: room,
                      onTap: () {
                        if (isLargeScreen) {
                          setState(() {
                            _selectedRoomId = room.id;
                            _selectedRoomName = room.name;
                          });
                        } else {
                          context.go(
                            '/chat/${room.id}?name=${Uri.encodeComponent(room.name)}',
                          );
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
