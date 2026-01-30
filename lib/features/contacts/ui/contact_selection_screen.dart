import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/roster_repository.dart';
import '../services/contact_service.dart';
import '../services/contact_sync_orchestrator.dart';
import 'contact_permission_view.dart';

/// Contact selection screen for starting new chats
/// Features: search, fast scroller, alphabetical list
class ContactSelectionScreen extends ConsumerStatefulWidget {
  const ContactSelectionScreen({super.key});

  @override
  ConsumerState<ContactSelectionScreen> createState() =>
      _ContactSelectionScreenState();
}

class _ContactSelectionScreenState extends ConsumerState<ContactSelectionScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late TextEditingController _searchController;
  Timer? _searchDebounceTimer;
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
          _isSearching = query.isNotEmpty;
        });
      }
    });
  }

  void _startNewChat() {
    // Navigate to group creation screen
    context.go('/contacts/select');
  }

  void _addNewContact() {
    // Navigate to contacts screen for adding new contact
    context.go('/contacts');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      controller: _scrollController,
      slivers: [
        _buildSliverAppBar(),
        _buildActionButtons(),
        _buildContactsList(),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      tooltip: 'Select Contact',
      onPressed: () => context.go('/contacts/select'),
      backgroundColor: AppTheme.primaryGreen,
      child: const Icon(Icons.person_add, color: Colors.white),
    ),
  );

  Widget _buildSliverAppBar() => SliverAppBar(
    floating: true,
    snap: true,
    pinned: true,
    backgroundColor: AppTheme.primaryGreen,
    foregroundColor: Colors.white,
    title: const Text('Select Contact', style: AppTheme.headerText),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.primaryGreen,
          border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              suffixIcon: _isSearching
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white70),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildActionButtons() => SliverToBoxAdapter(
    child: Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.group_add,
              label: 'New Group',
              onTap: _startNewChat,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _buildActionButton(
              icon: Icons.person_add,
              label: 'New Contact',
              onTap: _addNewContact,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: AppTheme.primaryGreen),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildContactsList() => Consumer(
    builder: (context, ref, child) {
      final permissionAsync = ref.watch(contactPermissionGrantedProvider);

      return permissionAsync.when(
        data: (hasPermission) {
          // Show permission view when permission not granted
          if (!hasPermission) {
            return SliverFillRemaining(
              child: ContactPermissionView(
                onPermissionGranted: () async {
                  // Invalidate permission provider to refresh state
                  ref.invalidate(contactPermissionGrantedProvider);
                  // Trigger sync via orchestrator
                  final orchestrator = await ref.read(
                    contactSyncOrchestratorProvider.future,
                  );
                  if (context.mounted) {
                    await orchestrator.ensureContactsSynced(context: context);
                  }
                  ref.invalidate(profilesWithContactsProvider);
                },
              ),
            );
          }

          // Permission granted - show contacts
          final contactsAsync = ref.watch(profilesWithContactsProvider);

          return contactsAsync.when(
            data: (contacts) {
              if (contacts.isEmpty) {
                return SliverFillRemaining(child: _buildEmptyState());
              }

              final filteredContacts = _filterContacts(contacts);
              final groupedContacts = _groupContactsAlphabetically(
                filteredContacts,
              );

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index >= groupedContacts.length) return null;

                  final entry = groupedContacts.entries.elementAt(index);
                  final letter = entry.key;
                  final sectionContacts = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Text(
                          letter,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGreen,
                              ),
                        ),
                      ),
                      // Contacts in this section
                      ...sectionContacts.map(_buildContactTile),
                    ],
                  );
                }, childCount: groupedContacts.length),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading contacts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(profilesWithContactsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error checking permission: $error'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(contactPermissionGrantedProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.people_outline,
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'No contacts found',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'None of your contacts are on the app yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _buildContactTile(ProfileWithContacts profileWithContacts) {
    final displayName = profileWithContacts.displayName;
    final avatarUrl = profileWithContacts.avatarUrl;
    final hasVerified = profileWithContacts.hasVerifiedContact;
    final contactSummary = profileWithContacts.contactSummary;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAvatar(displayName, avatarUrl),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasVerified) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.verified,
                size: 16,
                color: AppTheme.primaryGreen,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              contactSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (profileWithContacts.hasVerifiedContact)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'On App',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(
          Icons.chat_bubble_outline,
          color: AppTheme.primaryGreen,
          size: 20,
        ),
        onTap: () => _startChatWithContact(profileWithContacts),
      ),
    );
  }

  Widget _buildAvatar(String displayName, String? avatarUrl) {
    final initials = displayName.isNotEmpty
        ? displayName
              .split(' ')
              .map((word) => word[0])
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, _) {},
        backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
        child: Text(
          initials,
          style: const TextStyle(
            color: AppTheme.primaryGreen,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: AppTheme.primaryGreen.withValues(alpha: 0.1),
      child: Text(
        initials,
        style: const TextStyle(
          color: AppTheme.primaryGreen,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<ProfileWithContacts> _filterContacts(
    List<ProfileWithContacts> contacts,
  ) {
    if (_searchQuery.isEmpty) return contacts;

    final query = _searchQuery.toLowerCase();
    return contacts.where((contact) {
      final displayName = contact.displayName.toLowerCase();
      final contactSummary = contact.contactSummary.toLowerCase();

      return displayName.contains(query) || contactSummary.contains(query);
    }).toList();
  }

  Map<String, List<ProfileWithContacts>> _groupContactsAlphabetically(
    List<ProfileWithContacts> contacts,
  ) {
    final grouped = <String, List<ProfileWithContacts>>{};

    for (final contact in contacts) {
      final displayName = contact.displayName.trim();
      if (displayName.isEmpty) {
        const defaultGroup = '#';
        grouped.putIfAbsent(defaultGroup, () => []).add(contact);
        continue;
      }

      final firstLetter = displayName[0].toUpperCase();
      final group = RegExp('[A-Z]').hasMatch(firstLetter) ? firstLetter : '#';

      grouped.putIfAbsent(group, () => []).add(contact);
    }

    // Sort within each group and sort the groups
    for (final group in grouped.values) {
      group.sort((a, b) => a.displayName.compareTo(b.displayName));
    }

    // Sort groups alphabetically, with '#' at the end
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  void _startChatWithContact(ProfileWithContacts profileWithContacts) {
    final profileId = profileWithContacts.profile.id;
    final name = profileWithContacts.displayName;

    // Navigate to chat screen
    context.go('/chat/$profileId?name=${Uri.encodeComponent(name)}');
  }
}
