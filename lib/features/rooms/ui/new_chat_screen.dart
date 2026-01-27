import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../../contacts/data/contact_sync_repository.dart';
import '../../contacts/ui/contact_sync_sheet.dart';
import '../data/room_service.dart';

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
  bool _hasCheckedPermission = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    // Check permission and sync contacts when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionAndSync();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndSync() async {
    if (_hasCheckedPermission) return;
    _hasCheckedPermission = true;

    if (!_isMobile) {
      // On desktop/web, just trigger sync directly
      await _triggerSync();
      return;
    }

    // Check current permission status
    final status = await Permission.contacts.status;

    if (status.isGranted) {
      // Already have permission, trigger sync
      await _triggerSync();
    } else if (status.isPermanentlyDenied) {
      // Show explanation dialog with settings option
      if (mounted) {
        await _showPermissionExplanationDialog(isPermanentlyDenied: true);
      }
    } else {
      // Need to request permission - show explanation first
      if (mounted) {
        await _showPermissionExplanationDialog(isPermanentlyDenied: false);
      }
    }
  }

  Future<void> _showPermissionExplanationDialog({
    required bool isPermanentlyDenied,
  }) async {
    final theme = Theme.of(context);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.contacts_outlined,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Access Your Contacts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'To help you find friends and create group chats, we need access to your contacts.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildBenefitRow(
                    theme,
                    Icons.group_add,
                    'Find friends already on the app',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitRow(
                    theme,
                    Icons.chat_bubble_outline,
                    'Start chats with your contacts',
                  ),
                  const SizedBox(height: 8),
                  _buildBenefitRow(
                    theme,
                    Icons.lock_outline,
                    'Your contacts stay private on your device',
                  ),
                ],
              ),
            ),
            if (isPermanentlyDenied) ...[
              const SizedBox(height: 16),
              Text(
                'You previously denied this permission. Please enable it in Settings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isPermanentlyDenied ? 'Open Settings' : 'Continue'),
          ),
        ],
      ),
    );

    if ((result ?? false) && mounted) {
      if (isPermanentlyDenied) {
        // Open app settings
        await openAppSettings();
        // Check again after returning from settings
        if (mounted) {
          final newStatus = await Permission.contacts.status;
          if (newStatus.isGranted) {
            await _triggerSync();
          }
        }
      } else {
        // Request permission from system
        final status = await Permission.contacts.request();
        if (status.isGranted && mounted) {
          await _triggerSync();
        } else if (status.isPermanentlyDenied && mounted) {
          // User denied again, show settings option
          await _showPermissionExplanationDialog(isPermanentlyDenied: true);
        }
      }
    }
  }

  Widget _buildBenefitRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }

  Future<void> _triggerSync() async {
    final repo = await ref.read(rosterRepositoryProvider.future);
    if (mounted) {
      await showContactSyncSheet(
        context: context,
        repository: repo,
        onComplete: () {
          // Refresh the contacts list
          ref.invalidate(rosterEntriesProvider);
        },
      );
    }
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
                label: Text(
                  _selectedContacts.length == 1 ? 'Chat' : 'Create Group',
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                          _getInitials(
                            contact.displayName ?? contact.contactDetail,
                          ),
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
                                    _getInitials(
                                      contact.displayName ??
                                          contact.contactDetail,
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
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
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
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
                      selectedTileColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
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

  Widget _buildEmptyState(ThemeData theme) => Center(
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
    // Reset flag so we go through permission check again
    _hasCheckedPermission = false;
    await _checkPermissionAndSync();
  }

  /// Get the correct contact identifier based on priority:
  /// 1. contactId (if available) - from server
  /// 2. contactDetail (phone/email) - fallback
  String _getContactIdentifier(RosterEntry contact) {
    // Priority 1: Use contactId if available (from server)
    if (contact.contactId != null && contact.contactId!.isNotEmpty) {
      return contact.contactId!;
    }
    // Priority 2: Use contactDetail (phone/email)
    return contact.contactDetail;
  }

  Future<void> _createRoom() async {
    if (_selectedContacts.isEmpty) return;

    setState(() => _isCreatingRoom = true);

    try {
      final roomService = await ref.read(roomServiceProvider.future);

      // Get all contact identifiers using priority logic - server will handle routing
      final contactIds = _selectedContacts.map(_getContactIdentifier).toList();

      // Generate room name
      final roomName = _selectedContacts.length == 1
          ? (_selectedContacts.first.displayName ??
                _selectedContacts.first.contactDetail)
          : '${_selectedContacts.map((c) => c.displayName ?? c.contactDetail).take(3).join(', ')}${_selectedContacts.length > 3 ? '...' : ''}';

      final roomType = _selectedContacts.length == 1 ? 'direct' : 'group';

      AppLogger.info(
        '[NewChat] Creating room',
        data: {
          'name': roomName,
          'type': roomType,
          'memberCount': contactIds.length,
        },
      );

      // Create room - server handles member routing and billing
      final room = await roomService.createRoom(
        name: roomName,
        type: roomType,
        contactIds: contactIds,
      );

      if (mounted) {
        // Navigate to the new chat room
        context.go('/chat/${room.id}?name=${Uri.encodeComponent(room.name)}');
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        '[NewChat] Failed to create room',
        error: e,
        stackTrace: stackTrace,
      );
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
