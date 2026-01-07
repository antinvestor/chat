import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_error.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/responsive/three_panel_layout.dart';
import '../../../core/theme/app_theme.dart';
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
import '../data/room_service.dart';
import '../domain/room_with_last_message.dart';
import 'chat_list_item.dart';
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
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isMultiSelectMode = false;
  final Set<String> _selectedRoomIds = <String>{};

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

    AppLogger.debug(
      '[RoomList] Contact sync check',
      data: {
        'hasContactsSynced': hasContactsSynced,
        'existingProfileCount': existingProfiles.length,
      },
    );

    // Show sync sheet if never synced OR if there are no profiles to use
    if ((!hasContactsSynced || !hasProfiles) && mounted) {
      AppLogger.info(
        '[RoomList] Showing contact sync sheet',
        data: {
          'reason': !hasContactsSynced ? 'never synced' : 'no profiles found',
        },
      );

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
      AppLogger.debug(
        '[RoomList] Contacts already synced with profiles available',
      );
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'settings':
        context.go('/settings');
        break;
      case 'select_multiple':
        _toggleMultiSelectMode();
        break;
      case 'mark_all_read':
        _markAllAsRead();
        break;
    }
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedRoomIds.clear();
      }
    });
  }

  void _markAllAsRead() async {
    final rooms = ref.read(roomListWithMessagesProvider).value ?? [];
    final unreadRooms = rooms.where((room) => room.unreadCount > 0).toList();

    if (unreadRooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No unread messages'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final roomRepo = ref.read(roomRepositoryProvider);

      // Mark all rooms as read
      for (final room in unreadRooms) {
        await roomRepo.updateUnreadCount(room.id, 0);
      }

      // Refresh the room list to show updated counts
      ref.read(roomListWithMessagesProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Marked ${unreadRooms.length} conversation${unreadRooms.length == 1 ? '' : 's'} as read',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark messages as read: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _archiveRoom(RoomWithLastMessage room) {
    // TODO: Implement actual archive logic when repository is available
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Archive functionality coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showMoreOptions(RoomWithLastMessage room) {
    // TODO: Implement more options dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('More options coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  List<RoomWithLastMessage> _filterRooms(List<RoomWithLastMessage> rooms) {
    if (_searchQuery.isEmpty) return rooms;

    return rooms.where((room) {
      return room.name.toLowerCase().contains(_searchQuery) ||
          (room.lastMessageText?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  void _navigateToNewChat() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NewChatScreen()));
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
      body: CustomScrollView(
        slivers: [
          // Floating app bar that hides on scroll
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: true,
            title: Text(
              'Chats',
              style: AppTheme.headerText.copyWith(
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
            ),
            actions: [
              // Search button or back button
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.arrow_back : Icons.search,
                  color: Theme.of(context).appBarTheme.foregroundColor,
                ),
                onPressed: _toggleSearch,
                tooltip: _isSearching ? 'Back' : 'Search',
              ),
              // Search field or more options
              if (_isSearching)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search conversations...',
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).appBarTheme.foregroundColor?.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).appBarTheme.foregroundColor,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                    ),
                  ),
                )
              else
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Theme.of(context).appBarTheme.foregroundColor,
                  ),
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'select_multiple',
                      child: Text('Select Multiple'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'mark_all_read',
                      child: Text('Mark All Read'),
                    ),
                  ],
                ),
            ],
          ),

          // Call banner
          const SliverToBoxAdapter(child: IncomingCallBanner()),

          // Chat list
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final rooms = roomsAsync.value;
              if (rooms == null) {
                return null;
              }

              final filteredRooms = _filterRooms(rooms);
              if (index >= filteredRooms.length) {
                return null;
              }

              final room = filteredRooms[index];
              return Dismissible(
                key: ValueKey(room.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.blue,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.archive, color: Colors.white),
                ),
                secondaryBackground: Container(
                  color: Colors.grey,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.more_horiz, color: Colors.white),
                ),
                onDismissed: (direction) {
                  if (direction == DismissDirection.endToStart) {
                    _archiveRoom(room);
                  } else if (direction == DismissDirection.startToEnd) {
                    _showMoreOptions(room);
                  }
                },
                child: RepaintBoundary(
                  key: ValueKey(room.id),
                  child: ChatListItem(
                    room: room,
                    onTap: () {
                      if (_isMultiSelectMode) {
                        setState(() {
                          if (_selectedRoomIds.contains(room.id)) {
                            _selectedRoomIds.remove(room.id);
                          } else {
                            _selectedRoomIds.add(room.id);
                          }
                        });
                      } else {
                        // Navigate to chat screen for mobile layout
                        context.go(
                          '/chat/${room.id}?name=${Uri.encodeComponent(room.name)}',
                        );
                      }
                    },
                    isSelected: _selectedRoomIds.contains(room.id),
                    isMultiSelectMode: _isMultiSelectMode,
                    onLongPress: () {
                      _toggleMultiSelectMode();
                      setState(() {
                        _selectedRoomIds.add(room.id);
                      });
                    },
                    onSelectionChanged: (isSelected) {
                      setState(() {
                        if (isSelected) {
                          _selectedRoomIds.add(room.id);
                        } else {
                          _selectedRoomIds.remove(room.id);
                        }
                      });
                    },
                  ),
                ),
              );
            }, childCount: _filterRooms(roomsAsync.value ?? []).length),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToNewChat,
        backgroundColor: AppTheme.primaryGreen,
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
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
      appBar: AppBar(title: const Text('Chats')),
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
                  final isSelected = !isMobile && room.id == _selectedRoomId;

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
