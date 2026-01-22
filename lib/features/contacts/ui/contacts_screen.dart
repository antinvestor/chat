import 'package:flutter/material.dart';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/empty_state.dart';
import '../data/contact_search_provider.dart';
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
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        // Clear search state in provider
        try {
          ref.read(contactSearchProvider.notifier).clearSearch();
        } catch (_) {
          // Provider might not be available yet
        }
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _onSearchChanged(String query) {
    try {
      ref.read(contactSearchProvider.notifier).updateQuery(query);
    } catch (_) {
      // Provider might not be available yet
    }
  }

  void _showSortOptions() {
    final currentSort = ref.read(contactSortOptionProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Sort by',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...ContactSortOption.values.map(
              (option) => ListTile(
                leading: Radio<ContactSortOption>(
                  value: option,
                  groupValue: currentSort,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(contactSortOptionProvider.notifier).state =
                          value;
                      try {
                        ref
                            .read(contactSearchProvider.notifier)
                            .setSortOption(value);
                      } catch (_) {
                        // Provider might not be available yet
                      }
                      Navigator.pop(context);
                    }
                  },
                ),
                title: Text(option.displayName),
                onTap: () {
                  ref.read(contactSortOptionProvider.notifier).state = option;
                  try {
                    ref
                        .read(contactSearchProvider.notifier)
                        .setSortOption(option);
                  } catch (_) {
                    // Provider might not be available yet
                  }
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _isSearching
          ? TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or email...',
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
              onChanged: _onSearchChanged,
            )
          : const Text('Contacts'),
      actions: [
        // Search toggle
        IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
          tooltip: _isSearching ? 'Close search' : 'Search contacts',
        ),
        // Sort button (only when searching)
        if (_isSearching)
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
            tooltip: 'Sort options',
          ),
        // Sync button
        if (!_isSearching)
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
      bottom: _isSearching
          ? null
          : TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'On App', icon: Icon(Icons.people)),
                Tab(text: 'Device', icon: Icon(Icons.contacts)),
              ],
            ),
    ),
    body: _isSearching
        ? _buildSearchResults()
        : TabBarView(
            controller: _tabController,
            children: [_buildSyncedContactsList(), _buildDeviceContactsList()],
          ),
  );

  Widget _buildSearchResults() {
    final searchState = ref.watch(contactSearchProvider);

    // Show loading indicator while searching
    if (searchState.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error if search failed
    if (searchState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Search Error', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              searchState.error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Show empty state if no query entered yet
    if (!searchState.hasSearched && searchState.query.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search Contacts',
        message: 'Enter a name, phone number, or email to search',
      );
    }

    // Show no results state
    if (searchState.hasNoResults) {
      return EmptyState(
        icon: Icons.person_search,
        title: 'No contacts found',
        message: 'No contacts match "${searchState.query}"',
      );
    }

    // Show search results
    return _buildSearchResultsList(searchState.results);
  }

  Widget _buildSearchResultsList(List<RosterEntry> results) {
    final theme = Theme.of(context);
    final sortOption = ref.watch(contactSortOptionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Results header with count and sort info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text(
                '${results.length} result${results.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Sorted by: ${sortOption.displayName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Results list
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final entry = results[index];
              return _buildRosterEntryTile(entry);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRosterEntryTile(RosterEntry entry) {
    final theme = Theme.of(context);
    final displayName = entry.displayName ?? entry.contactDetail;
    final isPhone = entry.contactType == RosterContactType.msisdn;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(displayName, style: theme.textTheme.titleMedium),
      subtitle: Row(
        children: [
          Icon(
            isPhone ? Icons.phone : Icons.email,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              entry.contactDetail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.isVerified)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.verified,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      trailing: entry.profileId != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 12,
                    color: Colors.green.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'On App',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : null,
      onTap: () => _onContactTap(entry),
    );
  }

  void _onContactTap(RosterEntry entry) {
    if (entry.profileId != null) {
      // Navigate to chat with this profile
      final name = entry.displayName ?? entry.contactDetail;
      context.go('/chat/${entry.profileId}?name=${Uri.encodeComponent(name)}');
    } else {
      // Show options for off-platform contact
      _showContactOptions(entry);
    }
  }

  void _showContactOptions(RosterEntry entry) {
    final name = entry.displayName ?? entry.contactDetail;

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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Invite sent to $name')));
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
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
                    if (contacts.length > 1)
                      ..._buildContactChips(contacts, theme),
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
    final initials = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : '?';

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, _) {},
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

  List<Widget> _buildContactChips(
    List<RosterEntry> contacts,
    ThemeData theme,
  ) => [
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
                _showDeviceContactOptions(contact);
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

  void _showDeviceContactOptions(Contact contact) {
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Invite sent to $name')));
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
