import 'package:flutter/material.dart';

import '../../../core/navigation/navigation_helper.dart';
import '../../../core/responsive/responsive_layout.dart';
import 'room_detail_panel.dart';

/// Room detail screen showing full room information
/// Accessed when clicking on room avatar
class RoomDetailScreen extends StatelessWidget {
  final String roomId;
  final String roomName;

  const RoomDetailScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileLayout: _buildMobileLayout(context),
      tabletLayout: _buildTabletLayout(context),
      desktopLayout: _buildDesktopLayout(context),
    );
  }

  /// Mobile layout: Full screen room details
  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(roomName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back using navigation helper
            context.navigateBack();
          },
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              // Navigate to chat screen using navigation helper
              context.navigateToChat(roomId: roomId, roomName: roomName);
            },
            tooltip: 'Open chat',
          ),
        ],
      ),
      body: RoomDetailPanel(roomId: roomId, roomName: roomName),
    );
  }

  /// Tablet layout: Room details with room list
  Widget _buildTabletLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(roomName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back using navigation helper
            context.navigateBack();
          },
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              // Navigate to chat screen using navigation helper
              context.navigateToChat(roomId: roomId, roomName: roomName);
            },
            tooltip: 'Open chat',
          ),
        ],
      ),
      body: Row(
        children: [
          // Room list panel (smaller)
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: _buildCompactRoomList(context),
            ),
          ),
          // Room detail panel
          Expanded(
            flex: 2,
            child: RoomDetailPanel(roomId: roomId, roomName: roomName),
          ),
        ],
      ),
    );
  }

  /// Desktop layout: Room details with room list and chat
  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(roomName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back using navigation helper
            context.navigateBack();
          },
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              // Navigate to chat screen using navigation helper
              context.navigateToChat(roomId: roomId, roomName: roomName);
            },
            tooltip: 'Open chat',
          ),
        ],
      ),
      body: Row(
        children: [
          // Room list panel (smaller)
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: _buildCompactRoomList(context),
            ),
          ),
          // Chat panel
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: _buildChatPanel(context),
            ),
          ),
          // Room detail panel
          Expanded(
            flex: 2,
            child: RoomDetailPanel(roomId: roomId, roomName: roomName),
          ),
        ],
      ),
    );
  }

  /// Compact room list for side panel
  Widget _buildCompactRoomList(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: const Center(child: Text('Room list placeholder')),
    );
  }

  /// Chat panel for desktop layout
  Widget _buildChatPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(child: Text('Chat placeholder')),
    );
  }
}
