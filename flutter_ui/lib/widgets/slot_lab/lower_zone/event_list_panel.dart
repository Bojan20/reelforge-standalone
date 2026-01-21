/// Event List Panel — Auto Event Builder Event Browser
///
/// Browsable list of all committed events with:
/// - Search/filter by name, tag, bus, target
/// - Bulk selection and actions
/// - Event details preview
/// - Quick edit actions
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.7
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';

class EventListPanel extends StatefulWidget {
  const EventListPanel({super.key});

  @override
  State<EventListPanel> createState() => _EventListPanelState();
}

class _EventListPanelState extends State<EventListPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterBus = 'All';
  String _sortBy = 'name';
  bool _sortAscending = true;
  final Set<String> _selectedEventIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CommittedEvent> _filterAndSortEvents(List<CommittedEvent> events) {
    var filtered = events.where((e) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!e.eventId.toLowerCase().contains(query) &&
            !e.bus.toLowerCase().contains(query) &&
            !e.tags.any((t) => t.toLowerCase().contains(query))) {
          return false;
        }
      }

      // Bus filter
      if (_filterBus != 'All' && !e.bus.startsWith(_filterBus)) {
        return false;
      }

      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'name':
          cmp = a.eventId.compareTo(b.eventId);
          break;
        case 'bus':
          cmp = a.bus.compareTo(b.bus);
          break;
        case 'date':
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  void _toggleSelect(String eventId) {
    setState(() {
      if (_selectedEventIds.contains(eventId)) {
        _selectedEventIds.remove(eventId);
      } else {
        _selectedEventIds.add(eventId);
      }
    });
  }

  void _selectAll(List<CommittedEvent> events) {
    setState(() {
      _selectedEventIds.addAll(events.map((e) => e.eventId));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedEventIds.clear();
    });
  }

  void _deleteSelected(AutoEventBuilderProvider provider) {
    for (final id in _selectedEventIds.toList()) {
      provider.deleteEvent(id);
    }
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, child) {
        final events = _filterAndSortEvents(provider.events);
        final busOptions = _getBusOptions(provider.events);

        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Toolbar
              _Toolbar(
                searchController: _searchController,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                filterBus: _filterBus,
                busOptions: busOptions,
                onBusChanged: (v) => setState(() => _filterBus = v ?? 'All'),
                sortBy: _sortBy,
                sortAscending: _sortAscending,
                onSortChanged: (field, asc) => setState(() {
                  _sortBy = field;
                  _sortAscending = asc;
                }),
                selectedCount: _selectedEventIds.length,
                totalCount: events.length,
                onSelectAll: () => _selectAll(events),
                onClearSelection: _clearSelection,
                onDeleteSelected: () => _deleteSelected(provider),
              ),

              const SizedBox(height: 8),

              // Event list
              Expanded(
                child: events.isEmpty
                    ? _EmptyState(hasFilter: _searchQuery.isNotEmpty || _filterBus != 'All')
                    : _EventListView(
                        events: events,
                        selectedIds: _selectedEventIds,
                        onToggleSelect: _toggleSelect,
                        onDelete: provider.deleteEvent,
                        bindings: provider.bindings,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _getBusOptions(List<CommittedEvent> events) {
    final buses = events.map((e) {
      final parts = e.bus.split('/');
      return parts.isNotEmpty ? parts.first : e.bus;
    }).toSet().toList();
    buses.sort();
    return ['All', ...buses];
  }
}

// =============================================================================
// TOOLBAR
// =============================================================================

class _Toolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String filterBus;
  final List<String> busOptions;
  final ValueChanged<String?> onBusChanged;
  final String sortBy;
  final bool sortAscending;
  final void Function(String field, bool ascending) onSortChanged;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onDeleteSelected;

  const _Toolbar({
    required this.searchController,
    required this.onSearchChanged,
    required this.filterBus,
    required this.busOptions,
    required this.onBusChanged,
    required this.sortBy,
    required this.sortAscending,
    required this.onSortChanged,
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 2,
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: TextField(
              controller: searchController,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                hintText: 'Search events...',
                hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
                prefixIcon: Icon(Icons.search, size: 16, color: FluxForgeTheme.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Bus filter
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: filterBus,
              dropdownColor: FluxForgeTheme.bgMid,
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
              icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
              items: busOptions.map((b) {
                return DropdownMenuItem(value: b, child: Text(b));
              }).toList(),
              onChanged: onBusChanged,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Sort
        _SortButton(
          sortBy: sortBy,
          sortAscending: sortAscending,
          onChanged: onSortChanged,
        ),

        const SizedBox(width: 12),

        // Selection info / actions
        if (selectedCount > 0) ...[
          Text(
            '$selectedCount selected',
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete selected',
            color: FluxForgeTheme.accentRed,
            onPressed: onDeleteSelected,
          ),
          const SizedBox(width: 4),
          _SmallButton(
            icon: Icons.close,
            tooltip: 'Clear selection',
            onPressed: onClearSelection,
          ),
        ] else ...[
          Text(
            '$totalCount events',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(
            icon: Icons.select_all,
            tooltip: 'Select all',
            onPressed: totalCount > 0 ? onSelectAll : null,
          ),
        ],
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  final String sortBy;
  final bool sortAscending;
  final void Function(String field, bool ascending) onChanged;

  const _SortButton({
    required this.sortBy,
    required this.sortAscending,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      offset: const Offset(0, 32),
      color: FluxForgeTheme.bgMid,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(
              sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: FluxForgeTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              sortBy.substring(0, 1).toUpperCase() + sortBy.substring(1),
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _sortMenuItem('name', 'Name'),
        _sortMenuItem('bus', 'Bus'),
        _sortMenuItem('date', 'Date'),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '_toggle_order',
          child: Row(
            children: [
              Icon(
                sortAscending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 14,
                color: FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(sortAscending ? 'Descending' : 'Ascending'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == '_toggle_order') {
          onChanged(sortBy, !sortAscending);
        } else {
          onChanged(value, sortAscending);
        }
      },
    );
  }

  PopupMenuItem<String> _sortMenuItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (sortBy == value)
            Icon(Icons.check, size: 14, color: FluxForgeTheme.accentBlue)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onPressed;

  const _SmallButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textMuted;
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? c : c.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EVENT LIST VIEW
// =============================================================================

class _EventListView extends StatelessWidget {
  final List<CommittedEvent> events;
  final Set<String> selectedIds;
  final void Function(String eventId) onToggleSelect;
  final void Function(String eventId) onDelete;
  final List<EventBinding> bindings;

  const _EventListView({
    required this.events,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDelete,
    required this.bindings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isSelected = selectedIds.contains(event.eventId);
        final bindingCount = bindings.where((b) => b.eventId == event.eventId).length;

        return _EventListItem(
          event: event,
          isSelected: isSelected,
          bindingCount: bindingCount,
          onToggleSelect: () => onToggleSelect(event.eventId),
          onDelete: () => onDelete(event.eventId),
        );
      },
    );
  }
}

class _EventListItem extends StatefulWidget {
  final CommittedEvent event;
  final bool isSelected;
  final int bindingCount;
  final VoidCallback onToggleSelect;
  final VoidCallback onDelete;

  const _EventListItem({
    required this.event,
    required this.isSelected,
    required this.bindingCount,
    required this.onToggleSelect,
    required this.onDelete,
  });

  @override
  State<_EventListItem> createState() => _EventListItemState();
}

class _EventListItemState extends State<_EventListItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onToggleSelect,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
                : _isHovering
                    ? FluxForgeTheme.bgMid.withValues(alpha: 0.7)
                    : FluxForgeTheme.bgMid.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
            border: widget.isSelected
                ? Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isSelected
                        ? FluxForgeTheme.accentBlue
                        : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),

              const SizedBox(width: 12),

              // Event info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.eventId,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.route,
                          label: widget.event.bus,
                          color: FluxForgeTheme.accentBlue,
                        ),
                        const SizedBox(width: 6),
                        _InfoChip(
                          icon: Icons.link,
                          label: '${widget.bindingCount} binding${widget.bindingCount == 1 ? '' : 's'}',
                          color: FluxForgeTheme.accentGreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Tags
              if (widget.event.tags.isNotEmpty) ...[
                const SizedBox(width: 8),
                Wrap(
                  spacing: 4,
                  children: widget.event.tags.take(3).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeep,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: FluxForgeTheme.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Actions (show on hover)
              if (_isHovering) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.accentRed),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Delete',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilter ? Icons.search_off : Icons.folder_open_outlined,
            size: 48,
            color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'No events match your filter' : 'No events created yet',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasFilter
                ? 'Try adjusting your search or filters'
                : 'Drop audio onto slot elements to create events',
            style: TextStyle(
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
