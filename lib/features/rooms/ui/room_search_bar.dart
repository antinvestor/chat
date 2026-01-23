import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/room_search_providers.dart';

/// Search bar widget for filtering rooms
///
/// Features:
/// - Text search field with clear button
/// - Filter chips for All, Groups, Direct, Unread
/// - Real-time filtering as user types
class RoomSearchBar extends ConsumerStatefulWidget {
  const RoomSearchBar({super.key, this.onSearchChanged});

  /// Optional callback when search changes
  final ValueChanged<String>? onSearchChanged;

  @override
  ConsumerState<RoomSearchBar> createState() => _RoomSearchBarState();
}

class _RoomSearchBarState extends ConsumerState<RoomSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize controller with current search state
    final searchState = ref.read(roomSearchProvider);
    _searchController.text = searchState.query;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(roomSearchProvider.notifier).setQuery(value);
    widget.onSearchChanged?.call(value);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(roomSearchProvider.notifier).clearQuery();
    widget.onSearchChanged?.call('');
    _focusNode.unfocus();
  }

  void _onFilterSelected(RoomFilterType filter) {
    ref.read(roomSearchProvider.notifier).setFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchState = ref.watch(roomSearchProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search chats...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchState.hasActiveSearch
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                      tooltip: 'Clear search',
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                icon: Icons.forum_outlined,
                isSelected: searchState.filterType == RoomFilterType.all,
                onSelected: () => _onFilterSelected(RoomFilterType.all),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Groups',
                icon: Icons.group_outlined,
                isSelected: searchState.filterType == RoomFilterType.groups,
                onSelected: () => _onFilterSelected(RoomFilterType.groups),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Direct',
                icon: Icons.person_outline,
                isSelected: searchState.filterType == RoomFilterType.direct,
                onSelected: () => _onFilterSelected(RoomFilterType.direct),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Unread',
                icon: Icons.mark_chat_unread_outlined,
                isSelected: searchState.filterType == RoomFilterType.unread,
                onSelected: () => _onFilterSelected(RoomFilterType.unread),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Individual filter chip widget
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      selectedColor: AppTheme.primaryGreen,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      checkmarkColor: theme.colorScheme.onPrimary,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? AppTheme.primaryGreen
              : theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// Compact search bar for use in app bar
class CompactRoomSearchBar extends ConsumerStatefulWidget {
  const CompactRoomSearchBar({super.key, this.onClose});

  /// Callback when search is closed
  final VoidCallback? onClose;

  @override
  ConsumerState<CompactRoomSearchBar> createState() =>
      _CompactRoomSearchBarState();
}

class _CompactRoomSearchBarState extends ConsumerState<CompactRoomSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(roomSearchProvider);
    _searchController.text = searchState.query;
    // Auto-focus when opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(roomSearchProvider.notifier).setQuery(value);
  }

  void _clearAndClose() {
    ref.read(roomSearchProvider.notifier).clearAll();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchState = ref.watch(roomSearchProvider);

    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      onChanged: _onSearchChanged,
      style: TextStyle(color: theme.appBarTheme.foregroundColor),
      cursorColor: theme.appBarTheme.foregroundColor,
      decoration: InputDecoration(
        hintText: 'Search chats...',
        hintStyle: TextStyle(
          color: theme.appBarTheme.foregroundColor?.withValues(alpha: 0.6),
        ),
        border: InputBorder.none,
        suffixIcon: searchState.hasActiveSearch
            ? IconButton(
                icon: Icon(
                  Icons.clear,
                  color: theme.appBarTheme.foregroundColor,
                ),
                onPressed: () {
                  _searchController.clear();
                  ref.read(roomSearchProvider.notifier).clearQuery();
                },
              )
            : IconButton(
                icon: Icon(
                  Icons.close,
                  color: theme.appBarTheme.foregroundColor,
                ),
                onPressed: _clearAndClose,
              ),
      ),
    );
  }
}
