import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/responsive/three_panel_layout.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/error_banner.dart';
import '../../../widgets/skeleton_loader.dart';
import '../../calls/ui/incoming_call_banner.dart';
import '../../contacts/data/contact_sync_repository.dart';
import '../../contacts/ui/contact_sync_sheet.dart';
import '../../messages/ui/chat_screen.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/room_providers.dart';
import '../domain/room_with_last_message.dart';
import 'new_chat_screen.dart';
import 'room_detail_panel.dart';
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

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomListWithMessagesProvider);
    final width = MediaQuery.of(context).size.width;
    final showDetailPanel = AppBreakpoints.showDetailPanel(width);

    return ResponsiveLayout(
      mobileLayout: _buildMobileLayout(roomsAsync),
      tabletLayout: _buildTabletLayout(roomsAsync),
      desktopLayout: _buildDesktopLayout(roomsAsync, showDetailPanel),
    );
  }

  /// Mobile layout: Single-pane with stack navigation
  Widget _buildMobileLayout(AsyncValue<List<RoomWithLastMessage>> roomsAsync) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
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
                child: _buildRoomList(roomsAsync, isMobile: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tablet layout: 2-panel (Rooms | Chat)
  Widget _buildTabletLayout(AsyncValue<List<RoomWithLastMessage>> roomsAsync) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              const IncomingCallBanner(),
              Expanded(
                child: ThreePanelLayout(
                  leftPanel: _buildRoomListPanel(roomsAsync),
                  centerPanel: _buildChatPanel(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Desktop layout: 3-panel (Rooms | Chat | Details)
  Widget _buildDesktopLayout(
    AsyncValue<List<RoomWithLastMessage>> roomsAsync,
    bool showDetailPanel,
  ) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              const IncomingCallBanner(),
              Expanded(
                child: ThreePanelLayout(
                  leftPanel: _buildRoomListPanel(roomsAsync),
                  centerPanel: _buildChatPanel(),
                  rightPanel: showDetailPanel ? _buildDetailPanel() : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Room list panel for tablet/desktop layouts
  Widget _buildRoomListPanel(AsyncValue<List<RoomWithLastMessage>> roomsAsync) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToNewChat,
        tooltip: 'New Chat',
        child: const Icon(Icons.chat_bubble_outline),
      ),
      body: _buildRoomList(roomsAsync, isMobile: false),
    );
  }

  /// Chat panel for tablet/desktop layouts
  Widget _buildChatPanel() {
    if (_selectedRoomId != null) {
      return ChatScreen(
        roomId: _selectedRoomId!,
        roomName: _selectedRoomName ?? 'Chat',
        key: ValueKey(_selectedRoomId),
      );
    } else {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'Select a conversation',
        message: 'Choose a room from the list to start chatting',
      );
    }
  }

  /// Detail panel for desktop layout (room info, motions, transactions)
  Widget _buildDetailPanel() {
    if (_selectedRoomId != null && _selectedRoomName != null) {
      return RoomDetailPanel(
        roomId: _selectedRoomId!,
        roomName: _selectedRoomName!,
        key: ValueKey(_selectedRoomId),
      );
    } else {
      return const EmptyState(
        icon: Icons.info_outline,
        title: 'Room details',
        message: 'Select a room to view details',
      );
    }
  }

  Widget _buildRoomList(
    AsyncValue<List<RoomWithLastMessage>> roomsAsync, {
    required bool isMobile,
  }) {
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
                      !isMobile && room.id == _selectedRoomId;

                  return Container(
                    color: isSelected
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : null,
                    child: RoomListTile(
                      room: room,
                      onTap: () {
                        if (isMobile) {
                          // Navigate to chat screen
                          context.go(
                            '/chat/${room.id}?name=${Uri.encodeComponent(room.name)}',
                          );
                        } else {
                          // Update selected room for tablet/desktop
                          setState(() {
                            _selectedRoomId = room.id;
                            _selectedRoomName = room.name;
                          });
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
