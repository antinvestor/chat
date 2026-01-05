import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room detail panel showing room information, motions, transactions, and media
/// Displayed in the right panel on desktop layouts
class RoomDetailPanel extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;

  const RoomDetailPanel({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  ConsumerState<RoomDetailPanel> createState() => _RoomDetailPanelState();
}

class _RoomDetailPanelState extends ConsumerState<RoomDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Details', style: TextStyle(fontSize: 16)),
            Text(
              widget.roomName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Info', icon: Icon(Icons.info_outline, size: 18)),
            Tab(text: 'Motions', icon: Icon(Icons.how_to_vote, size: 18)),
            Tab(text: 'Transactions', icon: Icon(Icons.account_balance, size: 18)),
            Tab(text: 'Media', icon: Icon(Icons.photo_library, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(),
          _buildMotionsTab(),
          _buildTransactionsTab(),
          _buildMediaTab(),
        ],
      ),
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Room info section
        _buildSectionHeader('Room Information'),
        const SizedBox(height: 8),
        _buildInfoTile(
          icon: Icons.group,
          title: 'Room Type',
          subtitle: 'Group Chat',
        ),
        _buildInfoTile(
          icon: Icons.lock,
          title: 'Encryption',
          subtitle: 'End-to-end encrypted',
        ),
        const SizedBox(height: 24),

        // Members section
        _buildSectionHeader('Members'),
        const SizedBox(height: 8),
        _buildMembersList(),
      ],
    );
  }

  Widget _buildMotionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Active Motions'),
        const SizedBox(height: 16),
        // TODO: Use activeMotionsProvider to display active motions
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.how_to_vote, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No active motions',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Admins can create motions for voting',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Recent Transactions'),
        const SizedBox(height: 16),
        // TODO: Use transactionsProvider to display transactions
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No transactions yet',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Group transactions will appear here',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Shared Media'),
        const SizedBox(height: 16),
        // TODO: Use roomMediaProvider to display shared images/videos
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No shared media',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Photos and videos shared in chat will appear here',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _buildMembersList() {
    // TODO: Use roomMembersProvider to display actual members
    return Column(
      children: [
        _buildMemberTile(
          name: 'Loading members...',
          role: 'Please wait',
          avatarColor: Colors.grey,
        ),
      ],
    );
  }

  Widget _buildMemberTile({
    required String name,
    required String role,
    required Color avatarColor,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: avatarColor.withOpacity(0.2),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: avatarColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(role, style: const TextStyle(fontSize: 12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
