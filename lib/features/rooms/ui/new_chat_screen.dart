import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../contacts/data/contact_sync_repository.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchController = TextEditingController();
  final _selectedContacts = <RosterEntry>{};
  String _searchQuery = '';
  bool _isCreatingRoom = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rosterAsync = ref.watch(rosterEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        actions: [
          // Create room button
          if (_selectedContacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _isCreatingRoom ? null : _createRoom,
                icon: _isCreatingRoom
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(_selectedContacts.length == 1 ? 'Chat' : 'Create Group'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),

          // Selected contacts chips
          if (_selectedContacts.isNotEmpty) ...[
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedContacts.length,
                itemBuilder: (context, index) {
                  final contact = _selectedContacts.elementAt(index);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          _getInitials(contact.displayName ?? contact.contactDetail),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      label: Text(contact.displayName ?? contact.contactDetail),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() => _selectedContacts.remove(contact));
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
          ],

          // Contact list
          Expanded(
            child: rosterAsync.when(
              data: (contacts) {
                final filteredContacts = _filterContacts(contacts);
                
                if (contacts.isEmpty) {
                  return _buildEmptyState(theme);
                }

                if (filteredContacts.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No contacts match "$_searchQuery"',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = filteredContacts[index];
                    final isSelected = _selectedContacts.contains(contact);

                    return ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primaryContainer,
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    color: theme.colorScheme.onPrimary,
                                  )
                                : Text(
                                    _getInitials(contact.displayName ?? contact.contactDetail),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                          ),
                          if (contact.isVerified)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        contact.displayName ?? contact.contactDetail,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: contact.displayName != null
                          ? Text(
                              contact.contactDetail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : null,
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      selected: isSelected,
                      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedContacts.remove(contact);
                          } else {
                            _selectedContacts.add(contact);
                          }
                        });
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load contacts',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(rosterEntriesProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No contacts yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sync your contacts to find friends on the app',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _syncContacts,
              icon: const Icon(Icons.sync),
              label: const Text('Sync Contacts'),
            ),
          ],
        ),
      ),
    );
  }

  List<RosterEntry> _filterContacts(List<RosterEntry> contacts) {
    if (_searchQuery.isEmpty) {
      return contacts;
    }

    return contacts.where((contact) {
      final name = (contact.displayName ?? '').toLowerCase();
      final detail = contact.contactDetail.toLowerCase();
      return name.contains(_searchQuery) || detail.contains(_searchQuery);
    }).toList();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Future<void> _syncContacts() async {
    // Navigate to contacts screen or trigger sync
    final repo = await ref.read(rosterRepositoryProvider.future);
    await repo.syncContacts();
    ref.invalidate(rosterEntriesProvider);
  }

  Future<void> _createRoom() async {
    if (_selectedContacts.isEmpty) return;

    setState(() => _isCreatingRoom = true);

    try {
      AppLogger.info('[NewChat] Creating room', data: {
        'contactCount': _selectedContacts.length,
        'contacts': _selectedContacts.map((c) => c.contactDetail).toList(),
      });

      // TODO: Implement room creation via gateway API
      // For now, show a message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedContacts.length == 1
                  ? 'Starting chat with ${_selectedContacts.first.displayName ?? _selectedContacts.first.contactDetail}...'
                  : 'Creating group with ${_selectedContacts.length} contacts...',
            ),
          ),
        );
        
        // Pop back to room list
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      AppLogger.error('[NewChat] Failed to create room', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingRoom = false);
      }
    }
  }
}
