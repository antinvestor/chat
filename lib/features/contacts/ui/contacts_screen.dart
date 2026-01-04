import 'package:flutter/material.dart';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/contact_sync_repository.dart';
import '../services/contact_service.dart';
import 'contact_sync_sheet.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _syncContacts() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final repo = await ref.read(rosterRepositoryProvider.future);
      
      if (!mounted) return;
      
      await showContactSyncSheet(
        context: context,
        repository: repo,
        onComplete: () {
          ref.invalidate(syncedContactsProvider);
          ref.invalidate(rosterEntriesProvider);
        },
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _syncContacts,
              tooltip: 'Sync contacts with server',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'On App', icon: Icon(Icons.people)),
            Tab(text: 'Device', icon: Icon(Icons.contacts)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSyncedContactsList(),
          _buildDeviceContactsList(),
        ],
      ),
    );
  }

  Widget _buildSyncedContactsList() {
    final profilesAsync = ref.watch(profilesWithContactsProvider);

    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('No synced contacts yet'),
                const SizedBox(height: 8),
                const Text(
                  'Tap sync to find contacts on this app',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isSyncing ? null : _syncContacts,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profileWithContacts = profiles[index];
            return _buildProfileCard(profileWithContacts);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(profilesWithContactsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a profile card showing profile info enriched with contacts
  Widget _buildProfileCard(ProfileWithContacts profileWithContacts) {
    final theme = Theme.of(context);
    final displayName = profileWithContacts.displayName;
    final avatarUrl = profileWithContacts.avatarUrl;
    final hasVerified = profileWithContacts.hasVerifiedContact;
    final contactSummary = profileWithContacts.contactSummary;
    final contacts = profileWithContacts.contacts;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _startChatWithProfile(profileWithContacts),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              _buildAvatar(displayName, avatarUrl, theme),
              const SizedBox(width: 12),
              // Profile info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name with verified and on-platform badges
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasVerified)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.verified,
                              color: theme.colorScheme.primary,
                              size: 18,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 10,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'On App',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Contact summary
                    Text(
                      contactSummary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // Show contact details if multiple
                    if (contacts.length > 1) ..._buildContactChips(contacts, theme),
                  ],
                ),
              ),
              // Action button
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => _startChatWithProfile(profileWithContacts),
                tooltip: 'Start chat',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String displayName, String? avatarUrl, ThemeData theme) {
    final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, __) {},
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          initials,
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _buildContactChips(List<RosterEntry> contacts, ThemeData theme) {
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: contacts.take(3).map((contact) {
          final isPhone = contact.contactType == RosterContactType.msisdn;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPhone ? Icons.phone : Icons.email,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _truncateContact(contact.contactDetail),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (contact.isVerified) ...[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.verified,
                    size: 10,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    ];
  }

  String _truncateContact(String detail) {
    if (detail.length <= 15) return detail;
    return '${detail.substring(0, 12)}...';
  }

  Widget _buildDeviceContactsList() {
    final contactsAsync = ref.watch(contactsProvider);

    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.contacts, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No contacts found'),
                SizedBox(height: 8),
                Text(
                  'Grant permission to access contacts',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return ListTile(
              leading: (contact.photo != null)
                  ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
                  : CircleAvatar(
                      child: Text(
                        contact.displayName.isNotEmpty
                            ? contact.displayName[0]
                            : '?',
                      ),
                    ),
              title: Text(contact.displayName),
              subtitle: contact.phones.isNotEmpty
                  ? Text(contact.phones.first.number)
                  : contact.emails.isNotEmpty
                      ? Text(contact.emails.first.address)
                      : null,
              onTap: () {
                // Show options to message, invite or view details
                _showContactOptions(contact);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }

  void _startChatWithProfile(ProfileWithContacts profileWithContacts) {
    // Navigate to create/open chat with this profile
    final profileId = profileWithContacts.profile.id;
    final name = profileWithContacts.displayName;
    context.go('/chat/$profileId?name=${Uri.encodeComponent(name)}');
  }

  void _showContactOptions(Contact contact) {
    final name = contact.displayName;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Invite to App'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invite sent to $name')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
