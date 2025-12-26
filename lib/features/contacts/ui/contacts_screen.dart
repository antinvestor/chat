import 'package:flutter/material.dart';

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
    final syncedAsync = ref.watch(syncedContactsProvider);

    return syncedAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
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
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  contact.displayName.isNotEmpty
                      ? contact.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(contact.displayName),
              subtitle: Text(
                contact.contactType == ContactSyncType.msisdn ? 'Phone' : 'Email',
              ),
              trailing: contact.isVerified
                  ? const Icon(Icons.verified, color: Colors.green, size: 20)
                  : null,
              onTap: () => _startChatWithContact(contact),
            );
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
              onPressed: () => ref.invalidate(syncedContactsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
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
                // Show options to invite or view details
                _showContactOptions(contact.displayName);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
    );
  }

  void _startChatWithContact(SyncedContact contact) {
    // Navigate to create/open chat with this contact
    context.go('/chat/${contact.profileId}?name=${Uri.encodeComponent(contact.displayName)}');
  }

  void _showContactOptions(String name) {
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
