/// FluxForge Studio Ultimate Event Editor Panel
///
/// Professional Wwise/FMOD-level event editor with:
/// - Hierarchical event browser with categories and folders
/// - Visual action chain timeline with drag-and-drop
/// - Real-time waveform preview for audio assets
/// - Advanced property inspector with all parameters
/// - Multi-select with batch operations
/// - Keyboard shortcuts for power users
/// - Bus routing visualization with signal flow
/// - State/Switch condition editors
/// - RTPC curve integration
/// - Undo/redo support
/// - Search with advanced query syntax
/// - Import/export functionality
/// - Real-time testing with scope selection

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../services/stage_configuration_service.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const double _kEventListWidth = 320.0;
const double _kInspectorWidth = 340.0;
const double _kActionTimelineHeight = 200.0;
const double _kActionCardHeight = 72.0;
const double _kToolbarHeight = 44.0;
const double _kCategoryHeaderHeight = 32.0;
const double _kMinPanelWidth = 200.0;

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Ultimate Event Editor Panel - Professional middleware event authoring
class EventEditorPanel extends StatefulWidget {
  const EventEditorPanel({super.key});

  @override
  State<EventEditorPanel> createState() => _EventEditorPanelState();
}

class _EventEditorPanelState extends State<EventEditorPanel>
    with TickerProviderStateMixin {
  // Selection state
  String? _selectedEventId;
  final Set<String> _selectedActionIds = {};
  String? _hoveredEventId;
  String? _draggedActionId;

  // UI state
  bool _showInspector = true;
  bool _showTimeline = true;
  String _searchQuery = '';
  String _filterCategory = 'All';
  bool _isCreatingEvent = false;
  bool _isCreatingAction = false;
  _SortMode _sortMode = _SortMode.name;
  bool _sortAscending = true;

  // Resizable panel widths
  double _eventListWidth = _kEventListWidth;
  double _inspectorWidth = _kInspectorWidth;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newEventNameController = TextEditingController();
  final ScrollController _eventListScrollController = ScrollController();
  final ScrollController _actionTimelineScrollController = ScrollController();

  // Focus
  final FocusNode _keyboardFocusNode = FocusNode();

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Local event storage (provider integration later)
  final Map<String, MiddlewareEvent> _events = {};
  final Map<String, List<String>> _categoryFolders = {}; // category -> [eventIds]
  final Set<String> _expandedCategories = {'Music', 'SFX', 'Slot'};
  int _nextEventId = 1;
  int _nextActionId = 1;

  // Undo/Redo
  final List<_UndoAction> _undoStack = [];
  final List<_UndoAction> _redoStack = [];

  // Debounce timer for slider updates (P0.2 performance fix)
  Timer? _sliderDebounceTimer;

  // Track which event has pending local edits to prevent provider overwrite during debounce
  // BUG FIX: Without this, provider sync would overwrite local slider changes before debounce completes
  String? _pendingEditEventId;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initSampleData();
    _keyboardFocusNode.requestFocus();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _initSampleData() {
    // No placeholder data - events are created by user or synced from Slot Lab
    // Categories will be populated as events are added
  }

  String _nextId() => '${_nextActionId++}';

  void _addEvent(String name, String category, List<MiddlewareAction> actions) {
    final id = '${_nextEventId++}';
    _events[id] = MiddlewareEvent(
      id: id,
      name: name,
      category: category,
      actions: actions,
    );
    _categoryFolders.putIfAbsent(category, () => []).add(id);
  }

  /// Sync event to provider for FFI communication
  void _syncEventToProvider(MiddlewareEvent event) {
    final provider = context.read<MiddlewareProvider>();
    if (provider.getEvent(event.id) == null) {
      provider.registerEvent(event);
    } else {
      provider.updateEvent(event);
    }
  }

  /// Sync all events to provider
  void _syncAllEventsToProvider() {
    final provider = context.read<MiddlewareProvider>();
    for (final event in _events.values) {
      if (provider.getEvent(event.id) == null) {
        provider.registerEvent(event);
      } else {
        provider.updateEvent(event);
      }
    }
  }

  /// Sync events FROM provider (Slot Lab events appear in Event Editor)
  void _syncEventsFromProviderList(List<MiddlewareEvent> providerEvents) {
    // Provider.events already contains MiddlewareEvents synced from Slot Lab composites
    // via _syncCompositeToMiddleware() in the provider

    for (final event in providerEvents) {
      if (!_events.containsKey(event.id)) {
        // New event from provider
        _events[event.id] = event;
        _categoryFolders.putIfAbsent(event.category, () => []);
        if (!_categoryFolders[event.category]!.contains(event.id)) {
          _categoryFolders[event.category]!.add(event.id);
        }
        _expandedCategories.add(event.category);
      } else {
        // BUG FIX: Skip updating events with pending local edits (e.g., during slider drag)
        // This prevents provider from overwriting local slider changes during debounce period
        if (event.id == _pendingEditEventId) {
          continue;
        }

        // Update if changed - check name, category, or any action parameters
        final existing = _events[event.id]!;
        bool needsUpdate = existing.name != event.name ||
            existing.category != event.category ||
            existing.actions.length != event.actions.length;

        // Also check if any action parameters have changed (including pan, gain, etc.)
        if (!needsUpdate && existing.actions.length == event.actions.length) {
          for (int i = 0; i < existing.actions.length; i++) {
            final oldAction = existing.actions[i];
            final newAction = event.actions[i];
            if (oldAction.pan != newAction.pan ||
                oldAction.gain != newAction.gain ||
                oldAction.delay != newAction.delay ||
                oldAction.assetId != newAction.assetId ||
                oldAction.bus != newAction.bus ||
                oldAction.loop != newAction.loop) {
              needsUpdate = true;
              break;
            }
          }
        }

        if (needsUpdate) {
          _events[event.id] = event;
          if (existing.category != event.category) {
            _categoryFolders[existing.category]?.remove(event.id);
            _categoryFolders.putIfAbsent(event.category, () => []);
            if (!_categoryFolders[event.category]!.contains(event.id)) {
              _categoryFolders[event.category]!.add(event.id);
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _sliderDebounceTimer?.cancel();
    _searchController.dispose();
    _newEventNameController.dispose();
    _eventListScrollController.dispose();
    _actionTimelineScrollController.dispose();
    _keyboardFocusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Selector<MiddlewareProvider, List<MiddlewareEvent>>(
        selector: (_, p) => p.events,
        builder: (context, providerEvents, _) {
          // Sync events from provider (includes Slot Lab events)
          _syncEventsFromProviderList(providerEvents);

          return Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildToolbar(),
                Expanded(
                  child: Row(
                    children: [
                      // Event Browser
                      _buildEventBrowser(),
                      // Resize handle
                      _buildResizeHandle(
                        onDrag: (dx) {
                          setState(() {
                            _eventListWidth = (_eventListWidth + dx)
                                .clamp(_kMinPanelWidth, 500);
                          });
                        },
                      ),
                      // Main Editor Area
                      Expanded(child: _buildMainEditor()),
                      // Inspector
                      if (_showInspector) ...[
                        _buildResizeHandle(
                          onDrag: (dx) {
                            setState(() {
                              _inspectorWidth = (_inspectorWidth - dx)
                                  .clamp(_kMinPanelWidth, 500);
                            });
                          },
                        ),
                        _buildInspector(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOOLBAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    return Container(
      height: _kToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Title with icon
          _buildToolbarIcon(Icons.event_note, Colors.cyan),
          const SizedBox(width: 8),
          Text(
            'Event Editor',
            style: FluxForgeTheme.h3.copyWith(color: FluxForgeTheme.textPrimary),
          ),
          const SizedBox(width: 12),
          // Event count badge
          _buildBadge('${_events.length} Events', Colors.cyan),
          const SizedBox(width: 8),
          _buildBadge('${_getAllActions().length} Actions', Colors.amber),

          const Spacer(),

          // Undo/Redo
          _buildToolbarButton(
            icon: Icons.undo,
            tooltip: 'Undo (⌘Z)',
            enabled: _undoStack.isNotEmpty,
            onPressed: _undo,
          ),
          _buildToolbarButton(
            icon: Icons.redo,
            tooltip: 'Redo (⌘⇧Z)',
            enabled: _redoStack.isNotEmpty,
            onPressed: _redo,
          ),
          _buildDivider(),

          // View toggles
          _buildToolbarToggle(
            icon: Icons.timeline,
            tooltip: 'Timeline View',
            active: _showTimeline,
            onPressed: () => setState(() => _showTimeline = !_showTimeline),
          ),
          _buildToolbarToggle(
            icon: Icons.info_outline,
            tooltip: 'Inspector Panel',
            active: _showInspector,
            onPressed: () => setState(() => _showInspector = !_showInspector),
          ),
          _buildDivider(),

          // Sort dropdown
          _buildSortDropdown(),
          _buildDivider(),

          // Actions
          _buildToolbarButton(
            icon: Icons.file_download,
            tooltip: 'Import Events',
            onPressed: _importEvents,
          ),
          _buildToolbarButton(
            icon: Icons.file_upload,
            tooltip: 'Export Events',
            onPressed: _exportEvents,
          ),
          _buildDivider(),

          // Sync to Engine
          _buildToolbarButton(
            icon: Icons.sync,
            tooltip: 'Sync All to Engine',
            onPressed: () {
              _syncAllEventsToProvider();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text('Synced ${_events.length} events to engine'),
                    ],
                  ),
                  backgroundColor: FluxForgeTheme.bgSurface,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
          ),
          _buildDivider(),

          // New Event button (prominent)
          _buildPrimaryButton(
            icon: Icons.add,
            label: 'New Event',
            onPressed: () => setState(() => _isCreatingEvent = true),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    bool enabled = true,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? FluxForgeTheme.textSecondary
                : FluxForgeTheme.textDisabled,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarToggle({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.borderSubtle,
    );
  }

  Widget _buildSortDropdown() {
    return PopupMenuButton<_SortMode>(
      tooltip: 'Sort events',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              _sortMode.label,
              style: FluxForgeTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
      onSelected: (mode) {
        setState(() {
          if (_sortMode == mode) {
            _sortAscending = !_sortAscending;
          } else {
            _sortMode = mode;
            _sortAscending = true;
          }
        });
      },
      itemBuilder: (context) => _SortMode.values.map((mode) {
        return PopupMenuItem(
          value: mode,
          child: Row(
            children: [
              Icon(
                mode.icon,
                size: 16,
                color: _sortMode == mode
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                mode.label,
                style: TextStyle(
                  color: _sortMode == mode
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              FluxForgeTheme.accentCyan,
              FluxForgeTheme.accentBlue,
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT BROWSER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventBrowser() {
    return Container(
      width: _eventListWidth,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(
          right: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          // Category filter
          _buildCategoryFilter(),
          // Event list
          Expanded(child: _buildEventList()),
          // Create event inline form
          if (_isCreatingEvent) _buildCreateEventForm(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              Icons.search,
              size: 16,
              color: FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search events... (name:, cat:, has:)',
                  hintStyle: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              InkWell(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = <String>{'All', ..._categoryFolders.keys};

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: categories.map((cat) {
          final isSelected = _filterCategory == cat;
          final color = _getCategoryColor(cat);

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => setState(() => _filterCategory = cat),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cat != 'All') ...[
                      Icon(
                        _getCategoryIcon(cat),
                        size: 12,
                        color: isSelected ? color : FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      cat,
                      style: TextStyle(
                        color: isSelected ? color : FluxForgeTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventList() {
    final filteredEvents = _getFilteredEvents();
    final groupedByCategory = <String, List<MiddlewareEvent>>{};

    for (final event in filteredEvents) {
      groupedByCategory.putIfAbsent(event.category, () => []).add(event);
    }

    // Sort categories
    final sortedCategories = groupedByCategory.keys.toList()..sort();

    return ListView.builder(
      controller: _eventListScrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final events = groupedByCategory[category]!;
        final isExpanded = _expandedCategories.contains(category);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category header
            _buildCategoryHeader(category, events.length, isExpanded),
            // Events in category
            if (isExpanded)
              ...events.map((event) => _buildEventItem(event)),
          ],
        );
      },
    );
  }

  Widget _buildCategoryHeader(String category, int count, bool isExpanded) {
    final color = _getCategoryColor(category);

    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedCategories.remove(category);
          } else {
            _expandedCategories.add(category);
          }
        });
      },
      child: Container(
        height: _kCategoryHeaderHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
          border: Border(
            bottom: BorderSide(
              color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(_getCategoryIcon(category), size: 14, color: color),
            const SizedBox(width: 8),
            Text(
              category,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventItem(MiddlewareEvent event) {
    final isSelected = _selectedEventId == event.id;
    final isHovered = _hoveredEventId == event.id;
    final color = _getCategoryColor(event.category);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredEventId = event.id),
      onExit: (_) => setState(() => _hoveredEventId = null),
      child: InkWell(
        onTap: () => setState(() {
          _selectedEventId = event.id;
          _selectedActionIds.clear();
        }),
        onDoubleTap: () => _testEvent(event),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : isHovered
                    ? FluxForgeTheme.bgSurface.withValues(alpha: 0.5)
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? color : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              // Event icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  _getCategoryIcon(event.category),
                  size: 14,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              // Event name and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: TextStyle(
                        color: isSelected
                            ? FluxForgeTheme.textPrimary
                            : FluxForgeTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.flash_on,
                          size: 10,
                          color: Colors.amber.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${event.actions.length} actions',
                          style: TextStyle(
                            color: FluxForgeTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        if (_hasDelayedActions(event)) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.timer,
                            size: 10,
                            color: Colors.blue.withValues(alpha: 0.7),
                          ),
                        ],
                        if (_hasLoopingActions(event)) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.loop,
                            size: 10,
                            color: Colors.green.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Quick actions
              if (isHovered || isSelected) ...[
                _buildQuickAction(
                  Icons.play_arrow,
                  Colors.green,
                  'Test (F5)',
                  () => _testEvent(event),
                ),
                const SizedBox(width: 4),
                _buildQuickAction(
                  Icons.content_copy,
                  Colors.blue,
                  'Duplicate (⌘D)',
                  () => _duplicateEvent(event),
                ),
                const SizedBox(width: 4),
                _buildQuickAction(
                  Icons.delete_outline,
                  Colors.red,
                  'Delete (Del)',
                  () => _confirmDeleteEvent(event),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildCreateEventForm() {
    String selectedCategory = 'SFX';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.accentCyan),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setFormState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_circle, size: 16, color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 8),
                  Text(
                    'Create New Event',
                    style: FluxForgeTheme.h3.copyWith(
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _isCreatingEvent = false),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Event name
              TextField(
                controller: _newEventNameController,
                autofocus: true,
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Event Name',
                  labelStyle: FluxForgeTheme.bodySmall,
                  hintText: 'e.g., Play_Victory',
                  hintStyle: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                  ),
                  filled: true,
                  fillColor: FluxForgeTheme.bgSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: FluxForgeTheme.accentCyan),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _createEvent(selectedCategory),
              ),
              const SizedBox(height: 8),
              // Category selector
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['Music', 'SFX', 'Slot', 'Voice', 'UI', 'System'].map((cat) {
                  final isSelected = selectedCategory == cat;
                  final color = _getCategoryColor(cat);
                  return InkWell(
                    onTap: () => setFormState(() => selectedCategory = cat),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.2)
                            : FluxForgeTheme.bgSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? color : FluxForgeTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getCategoryIcon(cat),
                            size: 12,
                            color: isSelected ? color : FluxForgeTheme.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cat,
                            style: TextStyle(
                              color: isSelected ? color : FluxForgeTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _newEventNameController.clear();
                      setState(() => _isCreatingEvent = false);
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _createEvent(selectedCategory),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.accentCyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN EDITOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainEditor() {
    if (_selectedEventId == null) {
      return _buildEmptyState();
    }

    final event = _events[_selectedEventId];
    if (event == null) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Event header
        _buildEventHeader(event),
        // Action timeline
        if (_showTimeline) _buildActionTimeline(event),
        // Action list (always visible)
        Expanded(child: _buildActionList(event)),
        // Add action bar
        _buildAddActionBar(event),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _pulseAnimation.value * 0.5,
                child: Icon(
                  Icons.event_note,
                  size: 64,
                  color: FluxForgeTheme.textTertiary,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Select an event to edit',
            style: FluxForgeTheme.h2.copyWith(
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Or create a new event using the button above',
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textDisabled,
            ),
          ),
          const SizedBox(height: 24),
          // Quick create buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQuickCreateButton('Music Event', Icons.music_note, Colors.purple),
              const SizedBox(width: 12),
              _buildQuickCreateButton('SFX Event', Icons.speaker, Colors.orange),
              const SizedBox(width: 12),
              _buildQuickCreateButton('Slot Event', Icons.casino, Colors.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCreateButton(String label, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        setState(() {
          _isCreatingEvent = true;
          _newEventNameController.text = label.replaceAll(' Event', '_New');
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventHeader(MiddlewareEvent event) {
    final color = _getCategoryColor(event.category);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Event icon with glow
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(
              _getCategoryIcon(event.category),
              size: 24,
              color: color,
            ),
          ),
          const SizedBox(width: 16),
          // Event info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.name,
                      style: FluxForgeTheme.h2.copyWith(
                        color: FluxForgeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.category,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'ID: ${event.id}',
                      style: FluxForgeTheme.mono.copyWith(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.flash_on,
                      size: 12,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${event.actions.length} actions',
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.timer,
                      size: 12,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getTotalDuration(event),
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          _buildHeaderButton(
            Icons.play_arrow,
            'Test Event',
            Colors.green,
            () => _testEvent(event),
          ),
          const SizedBox(width: 8),
          _buildHeaderButton(
            Icons.content_copy,
            'Duplicate',
            Colors.blue,
            () => _duplicateEvent(event),
          ),
          const SizedBox(width: 8),
          _buildHeaderButton(
            Icons.edit,
            'Rename',
            Colors.orange,
            () => _renameEvent(event),
          ),
          const SizedBox(width: 8),
          _buildHeaderButton(
            Icons.delete_outline,
            'Delete',
            Colors.red,
            () => _confirmDeleteEvent(event),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildActionTimeline(MiddlewareEvent event) {
    if (event.actions.isEmpty) return const SizedBox();

    // Calculate timeline scale
    double maxTime = 0;
    for (final action in event.actions) {
      final endTime = action.delay + action.fadeTime;
      if (endTime > maxTime) maxTime = endTime;
    }
    if (maxTime < 1) maxTime = 1;

    return Container(
      height: _kActionTimelineHeight,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timeline,
                size: 14,
                color: FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                'Action Timeline',
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${maxTime.toStringAsFixed(2)}s',
                style: FluxForgeTheme.mono.copyWith(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final pixelsPerSecond = width / maxTime;

                return Stack(
                  children: [
                    // Time grid
                    _buildTimeGrid(maxTime, pixelsPerSecond),
                    // Action blocks
                    ...event.actions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final action = entry.value;
                      final isSelected = _selectedActionIds.contains(action.id);

                      final left = action.delay * pixelsPerSecond;
                      final actionWidth = math.max(
                        action.fadeTime * pixelsPerSecond,
                        40.0,
                      );

                      return Positioned(
                        left: left,
                        top: 20 + (index % 3) * 40,
                        child: _buildTimelineBlock(
                          action,
                          actionWidth,
                          isSelected,
                        ),
                      );
                    }),
                    // Playhead
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 2,
                        color: FluxForgeTheme.accentGreen,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeGrid(double maxTime, double pixelsPerSecond) {
    final gridLines = <Widget>[];
    final step = maxTime > 5 ? 1.0 : 0.25;

    for (double t = 0; t <= maxTime; t += step) {
      final x = t * pixelsPerSecond;
      gridLines.add(
        Positioned(
          left: x,
          top: 0,
          bottom: 0,
          child: Column(
            children: [
              Text(
                '${t.toStringAsFixed(t == t.roundToDouble() ? 0 : 2)}s',
                style: FluxForgeTheme.labelTiny.copyWith(
                  color: FluxForgeTheme.textDisabled,
                ),
              ),
              Expanded(
                child: Container(
                  width: 1,
                  color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(children: gridLines);
  }

  Widget _buildTimelineBlock(
    MiddlewareAction action,
    double width,
    bool isSelected,
  ) {
    final color = _getActionColor(action.type);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectedActionIds.contains(action.id)) {
            _selectedActionIds.remove(action.id);
          } else {
            _selectedActionIds.add(action.id);
          }
        });
      },
      child: Container(
        width: width,
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.4),
              color.withValues(alpha: 0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.white : color,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Icon(
              _getActionIcon(action.type),
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                action.type.displayName,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionList(MiddlewareEvent event) {
    if (event.actions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flash_off,
              size: 48,
              color: FluxForgeTheme.textDisabled,
            ),
            const SizedBox(height: 12),
            Text(
              'No actions defined',
              style: FluxForgeTheme.h3.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add actions to make this event do something',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textDisabled,
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: event.actions.length,
      onReorder: (oldIndex, newIndex) => _reorderActions(event, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final action = event.actions[index];
        final isSelected = _selectedActionIds.contains(action.id);

        return _buildActionCard(
          key: ValueKey(action.id),
          action: action,
          index: index,
          isSelected: isSelected,
          event: event,
        );
      },
    );
  }

  Widget _buildActionCard({
    required Key key,
    required MiddlewareAction action,
    required int index,
    required bool isSelected,
    required MiddlewareEvent event,
  }) {
    final color = _getActionColor(action.type);

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed) {
                if (_selectedActionIds.contains(action.id)) {
                  _selectedActionIds.remove(action.id);
                } else {
                  _selectedActionIds.add(action.id);
                }
              } else {
                _selectedActionIds.clear();
                _selectedActionIds.add(action.id);
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.1)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : FluxForgeTheme.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Action icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.3),
                        color.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Icon(
                    _getActionIcon(action.type),
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                // Action details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            action.type.displayName,
                            style: TextStyle(
                              color: FluxForgeTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (action.priority != ActionPriority.normal)
                            _buildPriorityBadge(action.priority),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getActionDescription(action),
                        style: FluxForgeTheme.bodySmall.copyWith(
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Parameters quick view
                _buildParameterChips(action),
                const SizedBox(width: 12),
                // Action buttons
                _buildQuickAction(
                  Icons.content_copy,
                  Colors.blue,
                  'Duplicate',
                  () => _duplicateAction(event, action),
                ),
                const SizedBox(width: 4),
                _buildQuickAction(
                  Icons.delete_outline,
                  Colors.red,
                  'Delete',
                  () => _removeAction(event, action),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(ActionPriority priority) {
    Color color;
    switch (priority) {
      case ActionPriority.highest:
        color = Colors.red;
        break;
      case ActionPriority.high:
        color = Colors.orange;
        break;
      case ActionPriority.aboveNormal:
        color = Colors.amber;
        break;
      case ActionPriority.normal:
        color = Colors.grey;
        break;
      case ActionPriority.belowNormal:
        color = Colors.blue;
        break;
      case ActionPriority.low:
        color = Colors.cyan;
        break;
      case ActionPriority.lowest:
        color = Colors.teal;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        priority.displayName,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParameterChips(MiddlewareAction action) {
    final chips = <Widget>[];

    if (action.delay > 0) {
      chips.add(_buildParamChip(
        Icons.timer,
        '+${(action.delay * 1000).toInt()}ms',
        Colors.blue,
      ));
    }

    if (action.fadeTime > 0) {
      chips.add(_buildParamChip(
        Icons.gradient,
        '${(action.fadeTime * 1000).toInt()}ms',
        Colors.purple,
      ));
    }

    if (action.loop) {
      chips.add(_buildParamChip(
        Icons.loop,
        'Loop',
        Colors.green,
      ));
    }

    if (action.gain != 1.0) {
      chips.add(_buildParamChip(
        Icons.volume_up,
        '${(action.gain * 100).toInt()}%',
        Colors.orange,
      ));
    }

    return Row(children: chips);
  }

  Widget _buildParamChip(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddActionBar(MiddlewareEvent event) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: _isCreatingAction
          ? _buildAddActionForm(event)
          : Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _isCreatingAction = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          'Add Action',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Quick add buttons for common actions
                ..._buildQuickAddButtons(event),
              ],
            ),
    );
  }

  List<Widget> _buildQuickAddButtons(MiddlewareEvent event) {
    final quickActions = [
      (ActionType.play, 'Play', Icons.play_arrow, Colors.green),
      (ActionType.stop, 'Stop', Icons.stop, Colors.red),
      (ActionType.setVolume, 'Volume', Icons.volume_up, Colors.blue),
      (ActionType.setRTPC, 'RTPC', Icons.tune, Colors.pink),
    ];

    return quickActions.map((item) {
      final (type, label, icon, color) = item;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Tooltip(
          message: 'Add $label action',
          child: InkWell(
            onTap: () => _addQuickAction(event, type),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAddActionForm(MiddlewareEvent event) {
    ActionType selectedType = ActionType.play;
    String selectedBus = 'Master';
    String selectedAsset = '';

    return StatefulBuilder(
      builder: (context, setFormState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'Add Action',
                  style: FluxForgeTheme.h3.copyWith(
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _isCreatingAction = false),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action type grid
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionType.play,
                ActionType.playAndContinue,
                ActionType.stop,
                ActionType.stopAll,
                ActionType.pause,
                ActionType.resume,
                ActionType.setVolume,
                ActionType.setPitch,
                ActionType.setLPF,
                ActionType.setHPF,
                ActionType.setState,
                ActionType.setSwitch,
                ActionType.setRTPC,
                ActionType.postEvent,
              ].map((type) {
                final isSelected = selectedType == type;
                final color = _getActionColor(type);
                return InkWell(
                  onTap: () => setFormState(() => selectedType = type),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.2)
                          : FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? color : FluxForgeTheme.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getActionIcon(type),
                          size: 14,
                          color: isSelected ? color : FluxForgeTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          type.displayName,
                          style: TextStyle(
                            color: isSelected ? color : FluxForgeTheme.textSecondary,
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Bus selector
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Bus',
                        style: FluxForgeTheme.label,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: FluxForgeTheme.borderSubtle),
                        ),
                        child: DropdownButton<String>(
                          value: selectedBus,
                          isExpanded: true,
                          underline: const SizedBox(),
                          dropdownColor: FluxForgeTheme.bgSurface,
                          style: FluxForgeTheme.body.copyWith(
                            color: FluxForgeTheme.textPrimary,
                          ),
                          items: kAllBuses.map((bus) {
                            return DropdownMenuItem(
                              value: bus,
                              child: Text(bus),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setFormState(() => selectedBus = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Asset selector (for play actions)
                if (selectedType == ActionType.play ||
                    selectedType == ActionType.playAndContinue)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Asset',
                          style: FluxForgeTheme.label,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: FluxForgeTheme.borderSubtle),
                          ),
                          child: DropdownButton<String>(
                            value: selectedAsset.isEmpty ? '—' : selectedAsset,
                            isExpanded: true,
                            underline: const SizedBox(),
                            dropdownColor: FluxForgeTheme.bgSurface,
                            style: FluxForgeTheme.body.copyWith(
                              color: FluxForgeTheme.textPrimary,
                            ),
                            items: const [
                              DropdownMenuItem(value: '—', child: Text('—')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setFormState(() => selectedAsset = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isCreatingAction = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _addAction(
                      event,
                      selectedType,
                      selectedBus,
                      selectedAsset.isEmpty ? '—' : selectedAsset,
                    );
                    setState(() => _isCreatingAction = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Add Action'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INSPECTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInspector() {
    return Container(
      width: _inspectorWidth,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          _buildInspectorHeader(),
          Expanded(
            child: _selectedActionIds.isEmpty
                ? _buildEventInspector()
                : _buildActionInspector(),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorHeader() {
    final hasSelection = _selectedActionIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasSelection ? Icons.flash_on : Icons.event_note,
            size: 16,
            color: hasSelection ? Colors.amber : Colors.cyan,
          ),
          const SizedBox(width: 8),
          Text(
            hasSelection
                ? '${_selectedActionIds.length} Action${_selectedActionIds.length > 1 ? 's' : ''}'
                : 'Event Properties',
            style: FluxForgeTheme.h3.copyWith(
              color: FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventInspector() {
    if (_selectedEventId == null) {
      return Center(
        child: Text(
          'Select an event',
          style: FluxForgeTheme.bodySmall.copyWith(
            color: FluxForgeTheme.textTertiary,
          ),
        ),
      );
    }

    final event = _events[_selectedEventId];
    if (event == null) return const SizedBox();

    // P1.3: Get available stages from StageConfigurationService
    final stageService = StageConfigurationService.instance;
    final allStages = ['', ...stageService.allStageNames]; // Empty = no binding

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildInspectorSection('General', [
          // P1.2: Editable Name TextField
          // P0.1 FIX: Added ValueKey to force rebuild when event changes
          _buildInspectorEditableField(
            'Name',
            event.name,
            (newName) => _updateEventProperty(event, name: newName),
            fieldKey: ValueKey('event_name_${event.id}'),
          ),
          // P1.3: Stage binding dropdown
          _buildInspectorDropdown(
            'Stage',
            event.stage.isEmpty ? '' : event.stage,
            allStages,
            (stage) => _updateEventProperty(event, stage: stage),
          ),
          _buildInspectorField('Category', event.category),
          _buildInspectorField('ID', event.id),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Statistics', [
          _buildInspectorField('Actions', '${event.actions.length}'),
          _buildInspectorField('Total Duration', _getTotalDuration(event)),
          _buildInspectorField('Buses Used', _getUniqueBuses(event).join(', ')),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Bus Routing', [
          _buildBusRoutingDiagram(event),
        ]),
      ],
    );
  }

  /// P1.2: Editable text field for inspector
  /// P0.1 FIX: Added fieldKey parameter to force rebuild when event changes
  Widget _buildInspectorEditableField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    Key? fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              // P0.1 FIX: Use key to force TextFormField rebuild when event changes
              child: TextFormField(
                key: fieldKey,
                initialValue: value,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onFieldSubmitted: onChanged,
                onTapOutside: (_) {
                  // Blur focus to trigger save
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// P1.2/P1.3: Update event property and sync to provider
  void _updateEventProperty(MiddlewareEvent event, {String? name, String? stage}) {
    final updatedEvent = event.copyWith(
      name: name,
      stage: stage,
    );
    setState(() {
      _events[event.id] = updatedEvent;
    });
    _syncEventToProvider(updatedEvent);
  }

  Widget _buildActionInspector() {
    if (_selectedEventId == null) return const SizedBox();
    final event = _events[_selectedEventId];
    if (event == null) return const SizedBox();

    // Get first selected action for display
    final actionId = _selectedActionIds.first;
    final action = event.actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => event.actions.first,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildInspectorSection('Type', [
          _buildActionTypeSelector(action, event),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Target', [
          _buildInspectorDropdown(
            'Bus',
            action.bus,
            kAllBuses,
            (value) => _updateAction(event, action, bus: value),
          ),
          if (action.type == ActionType.play ||
              action.type == ActionType.playAndContinue)
            _buildInspectorDropdown(
              'Asset',
              action.assetId.isEmpty ? '—' : action.assetId,
              [if (action.assetId.isNotEmpty) action.assetId, '—'],
              (value) => _updateAction(event, action, assetId: value == '—' ? '' : value),
            ),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Timing', [
          // P0.2: Debounced slider updates
          _buildInspectorSlider(
            'Delay',
            action.delay,
            0,
            5,
            'ms',
            1000,
            (value) => _updateActionDebounced(event, action, delay: value),
          ),
          // P0.2: Debounced slider updates
          _buildInspectorSlider(
            'Fade Time',
            action.fadeTime,
            0,
            5,
            'ms',
            1000,
            (value) => _updateActionDebounced(event, action, fadeTime: value),
          ),
          _buildInspectorDropdown(
            'Fade Curve',
            action.fadeCurve.displayName,
            FadeCurve.values.map((c) => c.displayName).toList(),
            (value) {
              final curve = FadeCurve.values.firstWhere(
                (c) => c.displayName == value,
                orElse: () => FadeCurve.linear,
              );
              _updateAction(event, action, fadeCurve: curve);
            },
          ),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Parameters', [
          // P0.3: Use dB slider for gain with debounced updates
          _buildGainSlider(
            'Gain',
            action.gain,
            (value) => _updateActionDebounced(event, action, gain: value),
          ),
          // P0.2: Debounced pan updates
          _buildPanSlider(
            'Pan',
            action.pan,
            (value) => _updateActionDebounced(event, action, pan: value),
          ),
          _buildInspectorToggle(
            'Loop',
            action.loop,
            (value) => _updateAction(event, action, loop: value),
          ),
        ]),
        const SizedBox(height: 16),
        // Extended Playback Parameters (2026-01-26)
        _buildInspectorSection('Extended Playback', [
          _buildInspectorSlider(
            'Fade In',
            action.fadeInMs,
            0,
            2000,
            'ms',
            1,
            (value) => _updateActionDebounced(event, action, fadeInMs: value),
          ),
          _buildInspectorSlider(
            'Fade Out',
            action.fadeOutMs,
            0,
            2000,
            'ms',
            1,
            (value) => _updateActionDebounced(event, action, fadeOutMs: value),
          ),
          _buildInspectorSlider(
            'Trim Start',
            action.trimStartMs,
            0,
            10000,
            'ms',
            1,
            (value) => _updateActionDebounced(event, action, trimStartMs: value),
          ),
          _buildInspectorSlider(
            'Trim End',
            action.trimEndMs,
            0,
            10000,
            'ms',
            1,
            (value) => _updateActionDebounced(event, action, trimEndMs: value),
          ),
        ]),
        const SizedBox(height: 16),
        // P0 WF-04: ALE Layer Assignment (2026-01-30)
        _buildInspectorSection('ALE Layer Assignment', [
          _buildInspectorDropdown(
            'Layer Level',
            _aleLayerDisplayName(action.aleLayerId),
            ['None', 'L1 - Calm', 'L2 - Tense', 'L3 - Excited', 'L4 - Intense', 'L5 - Epic'],
            (value) {
              final layerId = _parseAleLayerId(value);
              _updateAction(event, action, aleLayerId: layerId);
            },
          ),
        ]),
        const SizedBox(height: 16),
        _buildInspectorSection('Priority & Scope', [
          _buildInspectorDropdown(
            'Priority',
            action.priority.displayName,
            ActionPriority.values.map((p) => p.displayName).toList(),
            (value) {
              final priority = ActionPriority.values.firstWhere(
                (p) => p.displayName == value,
                orElse: () => ActionPriority.normal,
              );
              _updateAction(event, action, priority: priority);
            },
          ),
          _buildInspectorDropdown(
            'Scope',
            action.scope.displayName,
            ActionScope.values.map((s) => s.displayName).toList(),
            (value) {
              final scope = ActionScope.values.firstWhere(
                (s) => s.displayName == value,
                orElse: () => ActionScope.global,
              );
              _updateAction(event, action, scope: scope);
            },
          ),
        ]),
      ],
    );
  }

  Widget _buildInspectorSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInspectorField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: FluxForgeTheme.body.copyWith(
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    // Ensure value is in options list, fallback to first option
    final safeOptions = options.isEmpty ? ['—'] : options;
    final safeValue = safeOptions.contains(value) ? value : safeOptions.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: DropdownButton<String>(
                value: safeValue,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: FluxForgeTheme.bgSurface,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
                items: safeOptions.map((opt) {
                  return DropdownMenuItem(
                    value: opt,
                    child: Text(opt),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    double displayMultiplier,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * displayMultiplier).toStringAsFixed(0)}$unit',
                style: FluxForgeTheme.mono.copyWith(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.bgSurface,
              thumbColor: FluxForgeTheme.accentBlue,
              overlayColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// P0.3: Gain slider with dB display (0-200% → -∞ to +6dB)
  /// Uses debounced updates for performance
  Widget _buildGainSlider(
    String label,
    double gain,
    ValueChanged<double> onChanged,
  ) {
    // Convert linear gain to dB for display
    String gainToDb(double g) {
      if (g <= 0.001) return '-∞ dB';
      final db = 20 * math.log(g) / math.ln10;
      if (db >= 0) return '+${db.toStringAsFixed(1)} dB';
      return '${db.toStringAsFixed(1)} dB';
    }

    // Color based on gain value
    Color gainColor() {
      if (gain > 1.0) return Colors.orange; // Boost
      if (gain < 0.5) return FluxForgeTheme.textTertiary; // Low
      return FluxForgeTheme.accentBlue; // Normal
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const Spacer(),
              // P0.3: Show dB value instead of percentage
              Text(
                gainToDb(gain),
                style: FluxForgeTheme.mono.copyWith(
                  color: gainColor(),
                  fontSize: 10,
                  fontWeight: gain > 1.0 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: gainColor(),
              inactiveTrackColor: FluxForgeTheme.bgSurface,
              thumbColor: gainColor(),
              overlayColor: gainColor().withValues(alpha: 0.2),
            ),
            child: Slider(
              value: gain,
              min: 0,
              max: 2,
              onChanged: onChanged,
            ),
          ),
          // Gain presets: -12dB, -6dB, 0dB, +3dB, +6dB
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildGainPreset('-12', 0.25, gain, onChanged),
              _buildGainPreset('-6', 0.5, gain, onChanged),
              _buildGainPreset('0', 1.0, gain, onChanged),
              _buildGainPreset('+3', 1.41, gain, onChanged),
              _buildGainPreset('+6', 2.0, gain, onChanged),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGainPreset(String label, double preset, double current, ValueChanged<double> onChanged) {
    final isSelected = (current - preset).abs() < 0.05;
    final color = preset > 1.0 ? Colors.orange : FluxForgeTheme.accentBlue;
    return InkWell(
      onTap: () => onChanged(preset),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          '$label dB',
          style: TextStyle(
            fontSize: 9,
            color: isSelected ? color : FluxForgeTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Pan slider with L/R display (-1.0 to +1.0)
  Widget _buildPanSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    // Format pan value: L100, L50, C, R50, R100
    String formatPan(double v) {
      if (v.abs() < 0.01) return 'C';
      final percent = (v.abs() * 100).toInt();
      return v < 0 ? 'L$percent' : 'R$percent';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                formatPan(value),
                style: FluxForgeTheme.mono.copyWith(
                  color: Colors.cyan,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.cyan,
              inactiveTrackColor: FluxForgeTheme.bgSurface,
              thumbColor: Colors.cyan,
              overlayColor: Colors.cyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: -1.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
          // Pan presets: L100, L50, C, R50, R100
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPanPreset('L', -1.0, value, onChanged),
              _buildPanPreset('L50', -0.5, value, onChanged),
              _buildPanPreset('C', 0.0, value, onChanged),
              _buildPanPreset('R50', 0.5, value, onChanged),
              _buildPanPreset('R', 1.0, value, onChanged),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanPreset(String label, double preset, double current, ValueChanged<double> onChanged) {
    final isSelected = (current - preset).abs() < 0.05;
    return InkWell(
      onTap: () => onChanged(preset),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.cyan.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.cyan : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? Colors.cyan : FluxForgeTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorToggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: FluxForgeTheme.accentGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTypeSelector(MiddlewareAction action, MiddlewareEvent event) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: ActionType.values.map((type) {
        final isSelected = action.type == type;
        final color = _getActionColor(type);

        return InkWell(
          onTap: () => _updateAction(event, action, type: type),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? color : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getActionIcon(type),
                  size: 12,
                  color: isSelected ? color : FluxForgeTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  type.displayName,
                  style: TextStyle(
                    color: isSelected ? color : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBusRoutingDiagram(MiddlewareEvent event) {
    final buses = _getUniqueBuses(event);
    if (buses.isEmpty) {
      return Text(
        'No buses used',
        style: FluxForgeTheme.bodySmall.copyWith(
          color: FluxForgeTheme.textTertiary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: buses.map((bus) {
          final actionsOnBus = event.actions.where((a) => a.bus == bus).toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _getBusColor(bus),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  bus,
                  style: FluxForgeTheme.body.copyWith(
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${actionsOnBus.length} actions',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESIZE HANDLE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResizeHandle({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: FluxForgeTheme.borderSubtle,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<MiddlewareEvent> _getFilteredEvents() {
    var events = _events.values.toList();

    // Category filter
    if (_filterCategory != 'All') {
      events = events.where((e) => e.category == _filterCategory).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();

      // Advanced search syntax
      if (query.startsWith('name:')) {
        final nameQuery = query.substring(5).trim();
        events = events.where((e) =>
            e.name.toLowerCase().contains(nameQuery)).toList();
      } else if (query.startsWith('cat:')) {
        final catQuery = query.substring(4).trim();
        events = events.where((e) =>
            e.category.toLowerCase().contains(catQuery)).toList();
      } else if (query.startsWith('has:')) {
        final hasQuery = query.substring(4).trim();
        events = events.where((e) =>
            e.actions.any((a) =>
                a.type.displayName.toLowerCase().contains(hasQuery))).toList();
      } else {
        events = events.where((e) =>
            e.name.toLowerCase().contains(query) ||
            e.category.toLowerCase().contains(query)).toList();
      }
    }

    // Sort
    switch (_sortMode) {
      case _SortMode.name:
        events.sort((a, b) => _sortAscending
            ? a.name.compareTo(b.name)
            : b.name.compareTo(a.name));
        break;
      case _SortMode.category:
        events.sort((a, b) => _sortAscending
            ? a.category.compareTo(b.category)
            : b.category.compareTo(a.category));
        break;
      case _SortMode.actions:
        events.sort((a, b) => _sortAscending
            ? a.actions.length.compareTo(b.actions.length)
            : b.actions.length.compareTo(a.actions.length));
        break;
    }

    return events;
  }

  List<MiddlewareAction> _getAllActions() {
    return _events.values.expand((e) => e.actions).toList();
  }

  bool _hasDelayedActions(MiddlewareEvent event) {
    return event.actions.any((a) => a.delay > 0);
  }

  bool _hasLoopingActions(MiddlewareEvent event) {
    return event.actions.any((a) => a.loop);
  }

  String _getTotalDuration(MiddlewareEvent event) {
    double maxTime = 0;
    for (final action in event.actions) {
      final endTime = action.delay + action.fadeTime;
      if (endTime > maxTime) maxTime = endTime;
    }
    return '${(maxTime * 1000).toInt()}ms';
  }

  Set<String> _getUniqueBuses(MiddlewareEvent event) {
    return event.actions.map((a) => a.bus).toSet();
  }

  // P0 WF-04: ALE Layer Helpers (2026-01-30)
  String _aleLayerDisplayName(int? layerId) {
    if (layerId == null) return 'None';
    switch (layerId) {
      case 1: return 'L1 - Calm';
      case 2: return 'L2 - Tense';
      case 3: return 'L3 - Excited';
      case 4: return 'L4 - Intense';
      case 5: return 'L5 - Epic';
      default: return 'None';
    }
  }

  int? _parseAleLayerId(String displayName) {
    if (displayName == 'None') return null;
    if (displayName.startsWith('L1')) return 1;
    if (displayName.startsWith('L2')) return 2;
    if (displayName.startsWith('L3')) return 3;
    if (displayName.startsWith('L4')) return 4;
    if (displayName.startsWith('L5')) return 5;
    return null;
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note;
      case 'sfx':
        return Icons.speaker;
      case 'voice':
        return Icons.mic;
      case 'ambient':
      case 'ambience':
        return Icons.nature;
      case 'ui':
        return Icons.touch_app;
      case 'slot':
        return Icons.casino;
      case 'system':
        return Icons.settings;
      default:
        return Icons.event;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Colors.purple;
      case 'sfx':
        return Colors.orange;
      case 'voice':
        return Colors.blue;
      case 'ambient':
      case 'ambience':
        return Colors.green;
      case 'ui':
        return Colors.cyan;
      case 'slot':
        return Colors.amber;
      case 'system':
        return Colors.grey;
      case 'all':
        return FluxForgeTheme.textSecondary;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(ActionType type) {
    switch (type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return Icons.play_arrow;
      case ActionType.stop:
        return Icons.stop;
      case ActionType.stopAll:
        return Icons.stop_circle;
      case ActionType.pause:
      case ActionType.pauseAll:
        return Icons.pause;
      case ActionType.resume:
      case ActionType.resumeAll:
        return Icons.play_circle;
      case ActionType.break_:
        return Icons.stop;
      case ActionType.mute:
        return Icons.volume_off;
      case ActionType.unmute:
        return Icons.volume_up;
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return Icons.volume_up;
      case ActionType.setPitch:
        return Icons.tune;
      case ActionType.setLPF:
      case ActionType.setHPF:
        return Icons.graphic_eq;
      case ActionType.seek:
        return Icons.fast_forward;
      case ActionType.setState:
        return Icons.flag;
      case ActionType.setSwitch:
        return Icons.toggle_on;
      case ActionType.setRTPC:
      case ActionType.resetRTPC:
        return Icons.settings_input_component;
      case ActionType.trigger:
        return Icons.notifications;
      case ActionType.postEvent:
        return Icons.send;
    }
  }

  Color _getActionColor(ActionType type) {
    switch (type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return Colors.green;
      case ActionType.stop:
      case ActionType.stopAll:
      case ActionType.break_:
        return Colors.red;
      case ActionType.pause:
      case ActionType.pauseAll:
        return Colors.orange;
      case ActionType.resume:
      case ActionType.resumeAll:
        return Colors.green;
      case ActionType.mute:
      case ActionType.unmute:
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return Colors.blue;
      case ActionType.setPitch:
      case ActionType.setLPF:
      case ActionType.setHPF:
        return Colors.purple;
      case ActionType.seek:
        return Colors.teal;
      case ActionType.setState:
      case ActionType.setSwitch:
        return Colors.amber;
      case ActionType.setRTPC:
      case ActionType.resetRTPC:
        return Colors.pink;
      case ActionType.trigger:
        return Colors.lime;
      case ActionType.postEvent:
        return Colors.cyan;
    }
  }

  Color _getBusColor(String bus) {
    switch (bus.toLowerCase()) {
      case 'master':
        return Colors.red;
      case 'music':
        return Colors.purple;
      case 'sfx':
        return Colors.orange;
      case 'voice':
      case 'vo':
        return Colors.blue;
      case 'ui':
        return Colors.cyan;
      case 'ambience':
        return Colors.green;
      case 'reels':
        return Colors.amber;
      case 'wins':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  String _getActionDescription(MiddlewareAction action) {
    switch (action.type) {
      case ActionType.play:
      case ActionType.playAndContinue:
        return 'Play ${action.assetId.isNotEmpty ? action.assetId : "sound"} on ${action.bus}';
      case ActionType.stop:
        return 'Stop sounds on ${action.bus}';
      case ActionType.stopAll:
        return 'Stop all sounds';
      case ActionType.setVolume:
      case ActionType.setBusVolume:
        return 'Set ${action.bus} to ${(action.gain * 100).toInt()}%';
      case ActionType.setRTPC:
        return 'Set RTPC on ${action.bus}';
      case ActionType.setState:
        return 'Set state';
      case ActionType.setSwitch:
        return 'Set switch';
      case ActionType.postEvent:
        return 'Post event';
      default:
        return '${action.type.displayName} on ${action.bus}';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    // Undo/Redo
    if ((isCmd || isCtrl) && key == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _redo();
      } else {
        _undo();
      }
      return;
    }

    // Delete
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (_selectedActionIds.isNotEmpty && _selectedEventId != null) {
        final event = _events[_selectedEventId];
        if (event != null) {
          for (final actionId in _selectedActionIds.toList()) {
            final action = event.actions.firstWhere(
              (a) => a.id == actionId,
              orElse: () => event.actions.first,
            );
            _removeAction(event, action);
          }
        }
      } else if (_selectedEventId != null) {
        final event = _events[_selectedEventId];
        if (event != null) _confirmDeleteEvent(event);
      }
      return;
    }

    // Duplicate
    if ((isCmd || isCtrl) && key == LogicalKeyboardKey.keyD) {
      if (_selectedEventId != null) {
        final event = _events[_selectedEventId];
        if (event != null) _duplicateEvent(event);
      }
      return;
    }

    // Test event
    if (key == LogicalKeyboardKey.f5) {
      if (_selectedEventId != null) {
        final event = _events[_selectedEventId];
        if (event != null) _testEvent(event);
      }
      return;
    }

    // New event
    if ((isCmd || isCtrl) && key == LogicalKeyboardKey.keyN) {
      setState(() => _isCreatingEvent = true);
      return;
    }

    // Select all actions
    if ((isCmd || isCtrl) && key == LogicalKeyboardKey.keyA) {
      if (_selectedEventId != null) {
        final event = _events[_selectedEventId];
        if (event != null) {
          setState(() {
            _selectedActionIds.clear();
            _selectedActionIds.addAll(event.actions.map((a) => a.id));
          });
        }
      }
      return;
    }
  }

  void _createEvent(String category) {
    final name = _newEventNameController.text.trim();
    if (name.isEmpty) return;

    final id = '${_nextEventId++}';
    final event = MiddlewareEvent(
      id: id,
      name: name,
      category: category,
    );

    _pushUndo(_UndoAction.createEvent(event));

    setState(() {
      _events[id] = event;
      _categoryFolders.putIfAbsent(category, () => []).add(id);
      _selectedEventId = id;
      _selectedActionIds.clear();
      _isCreatingEvent = false;
      _expandedCategories.add(category);
    });

    _newEventNameController.clear();
  }

  void _duplicateEvent(MiddlewareEvent event) {
    final newId = '${_nextEventId++}';
    final newActions = event.actions.map((a) {
      return a.copyWith(id: _nextId());
    }).toList();

    final newEvent = event.copyWith(
      id: newId,
      name: '${event.name}_copy',
      actions: newActions,
    );

    _pushUndo(_UndoAction.createEvent(newEvent));

    setState(() {
      _events[newId] = newEvent;
      _categoryFolders.putIfAbsent(event.category, () => []).add(newId);
      _selectedEventId = newId;
      _selectedActionIds.clear();
    });
  }

  void _confirmDeleteEvent(MiddlewareEvent event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Text(
          'Delete Event',
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${event.name}"?',
          style: TextStyle(color: FluxForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteEvent(event);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteEvent(MiddlewareEvent event) {
    _pushUndo(_UndoAction.deleteEvent(event));

    setState(() {
      _events.remove(event.id);
      _categoryFolders[event.category]?.remove(event.id);
      if (_selectedEventId == event.id) {
        _selectedEventId = null;
        _selectedActionIds.clear();
      }
    });
  }

  void _renameEvent(MiddlewareEvent event) {
    final controller = TextEditingController(text: event.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: Text(
          'Rename Event',
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Event Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _pushUndo(_UndoAction.renameEvent(event, event.name, value));
              setState(() {
                _events[event.id] = event.copyWith(name: value);
              });
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                _pushUndo(_UndoAction.renameEvent(event, event.name, value));
                setState(() {
                  _events[event.id] = event.copyWith(name: value);
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _testEvent(MiddlewareEvent event) {
    try {
      final provider = context.read<MiddlewareProvider>();

      // Sync event to provider if not already registered
      if (provider.getEvent(event.id) == null) {
        provider.registerEvent(event);
      } else {
        provider.updateEvent(event);
      }

      // Check if event has any actions with audio
      if (event.actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event "${event.name}" has no actions to play'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      // P1.1 FIX: Use composite event playback for SlotLab events
      // This path supports pan/gain parameters via playFileToBus
      int playingId = 0;
      if (event.id.startsWith('mw_event_')) {
        // Convert middleware ID to composite ID (mw_event_XXX → event_XXX)
        final compositeId = event.id.substring(3);
        debugPrint('[EventEditor] Using composite playback for: $compositeId');

        // Ensure composite event is synced with latest action parameters
        provider.syncMiddlewareToComposite(event.id);

        // Play via composite path (supports pan/gain)
        playingId = provider.playCompositeEvent(compositeId);
      } else {
        // For non-SlotLab events (numeric IDs), play directly via AudioPlaybackService
        // This ensures pan/gain from actions are applied
        final playbackService = AudioPlaybackService.instance;
        int voicesStarted = 0;

        for (final action in event.actions) {
          if (action.type == ActionType.play && action.assetId.isNotEmpty) {
            // Get bus ID from bus name
            final busId = _busNameToId(action.bus);

            debugPrint('[EventEditor] Direct playback: ${action.assetId}, pan: ${action.pan}, gain: ${action.gain}');

            final voiceId = playbackService.playFileToBus(
              action.assetId,
              volume: action.gain,
              pan: action.pan,
              busId: busId,
            );

            if (voiceId >= 0) {
              voicesStarted++;
            }
          }
        }
        playingId = voicesStarted;
      }

      debugPrint('[EventEditor] Testing event: ${event.name} (playingId: $playingId)');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                playingId > 0 ? Icons.play_circle : Icons.info,
                color: playingId > 0 ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(playingId > 0
                  ? 'Playing: ${event.name}'
                  : 'Event posted: ${event.name} (no audio loaded)'),
            ],
          ),
          backgroundColor: FluxForgeTheme.bgSurface,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          action: playingId > 0
              ? SnackBarAction(
                  label: 'Stop',
                  textColor: FluxForgeTheme.accentBlue,
                  onPressed: () => provider.stopPlayingId(playingId),
                )
              : null,
        ),
      );
    } catch (e) {
      debugPrint('[EventEditor] Error testing event: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Convert bus name to engine bus ID
  int _busNameToId(String busName) {
    const busMap = {
      'Master': 5,
      'master': 5,
      'SFX': 0,
      'sfx': 0,
      'Music': 1,
      'music': 1,
      'Voice': 2,
      'voice': 2,
      'VO': 2,
      'vo': 2,
      'Ambience': 3,
      'ambience': 3,
      'Aux': 4,
      'aux': 4,
      'UI': 0,
      'ui': 0,
      'Reels': 0,
      'reels': 0,
      'Wins': 0,
      'wins': 0,
    };
    return busMap[busName] ?? 0;
  }

  void _addAction(
    MiddlewareEvent event,
    ActionType type,
    String bus,
    String assetId,
  ) {
    final action = MiddlewareAction(
      id: _nextId(),
      type: type,
      bus: bus,
      assetId: assetId,
    );

    _pushUndo(_UndoAction.addAction(event, action));

    setState(() {
      _events[event.id] = event.copyWith(
        actions: [...event.actions, action],
      );
    });

    // P1.1 FIX: Auto-sync to provider on add
    _syncEventToProvider(_events[event.id]!);
  }

  void _addQuickAction(MiddlewareEvent event, ActionType type) {
    final action = MiddlewareAction(
      id: _nextId(),
      type: type,
      bus: 'Master',
    );

    _pushUndo(_UndoAction.addAction(event, action));

    setState(() {
      _events[event.id] = event.copyWith(
        actions: [...event.actions, action],
      );
      _selectedActionIds.clear();
      _selectedActionIds.add(action.id);
    });

    // P1.1 FIX: Auto-sync to provider on quick add
    _syncEventToProvider(_events[event.id]!);
  }

  void _removeAction(MiddlewareEvent event, MiddlewareAction action) {
    _pushUndo(_UndoAction.removeAction(event, action));

    setState(() {
      _events[event.id] = event.copyWith(
        actions: event.actions.where((a) => a.id != action.id).toList(),
      );
      _selectedActionIds.remove(action.id);
    });

    // P1.1 FIX: Auto-sync to provider on remove
    _syncEventToProvider(_events[event.id]!);
  }

  void _duplicateAction(MiddlewareEvent event, MiddlewareAction action) {
    final newAction = action.copyWith(id: _nextId());

    _pushUndo(_UndoAction.addAction(event, newAction));

    final index = event.actions.indexWhere((a) => a.id == action.id);
    final newActions = List<MiddlewareAction>.from(event.actions);
    newActions.insert(index + 1, newAction);

    setState(() {
      _events[event.id] = event.copyWith(actions: newActions);
      _selectedActionIds.clear();
      _selectedActionIds.add(newAction.id);
    });

    // P1.1 FIX: Auto-sync to provider on duplicate
    _syncEventToProvider(_events[event.id]!);
  }

  void _reorderActions(MiddlewareEvent event, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final newActions = List<MiddlewareAction>.from(event.actions);
    final action = newActions.removeAt(oldIndex);
    newActions.insert(newIndex, action);

    setState(() {
      _events[event.id] = event.copyWith(actions: newActions);
    });

    // P1.1 FIX: Auto-sync to provider on reorder
    _syncEventToProvider(_events[event.id]!);
  }

  void _updateAction(
    MiddlewareEvent event,
    MiddlewareAction action, {
    ActionType? type,
    String? assetId,
    String? bus,
    ActionScope? scope,
    ActionPriority? priority,
    FadeCurve? fadeCurve,
    double? fadeTime,
    double? gain,
    double? pan,
    double? delay,
    bool? loop,
    // Extended playback parameters
    double? fadeInMs,
    double? fadeOutMs,
    double? trimStartMs,
    double? trimEndMs,
    // P0 WF-04: ALE layer assignment (2026-01-30)
    int? aleLayerId,
  }) {
    final newAction = action.copyWith(
      type: type,
      assetId: assetId,
      bus: bus,
      scope: scope,
      priority: priority,
      fadeCurve: fadeCurve,
      fadeTime: fadeTime,
      gain: gain,
      pan: pan,
      delay: delay,
      loop: loop,
      // Extended playback parameters
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      // P0 WF-04: ALE layer assignment (2026-01-30)
      aleLayerId: aleLayerId,
    );

    final newActions = event.actions.map((a) {
      return a.id == action.id ? newAction : a;
    }).toList();

    setState(() {
      _events[event.id] = event.copyWith(actions: newActions);
    });

    // DEBUG: Log parameter updates
    if (pan != null) {
      debugPrint('[EventEditor] Pan updated: eventId=${event.id}, actionId=${action.id}, oldPan=${action.pan}, newPan=$pan');
    }
    if (gain != null) {
      debugPrint('[EventEditor] Gain updated: eventId=${event.id}, gain=$gain');
    }

    // P1.1 FIX: Auto-sync to provider on edit
    _syncEventToProvider(_events[event.id]!);
  }

  /// Debounced version of _updateAction for sliders (P0.2 performance fix)
  /// Waits 50ms after last change before syncing to provider
  void _updateActionDebounced(
    MiddlewareEvent event,
    MiddlewareAction action, {
    double? gain,
    double? pan,
    double? delay,
    double? fadeTime,
    // Extended playback parameters
    double? fadeInMs,
    double? fadeOutMs,
    double? trimStartMs,
    double? trimEndMs,
  }) {
    // Mark this event as having pending edits to prevent provider overwrite
    _pendingEditEventId = event.id;

    // Update local state immediately for responsive UI
    final newAction = action.copyWith(
      gain: gain,
      pan: pan,
      delay: delay,
      fadeTime: fadeTime,
      // Extended playback parameters
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
    );

    final newActions = event.actions.map((a) {
      return a.id == action.id ? newAction : a;
    }).toList();

    setState(() {
      _events[event.id] = event.copyWith(actions: newActions);
    });

    // Debounce the provider sync
    _sliderDebounceTimer?.cancel();
    _sliderDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      _syncEventToProvider(_events[event.id]!);
      // Clear pending edit flag after sync completes
      _pendingEditEventId = null;
    });
  }

  void _importEvents() {
    showDialog(
      context: context,
      builder: (ctx) => _ImportEventsDialog(
        onImport: (events) {
          setState(() {
            for (final event in events) {
              _events[event.id] = event;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported ${events.length} events'),
              backgroundColor: FluxForgeTheme.accentGreen,
            ),
          );
        },
      ),
    );
  }

  void _exportEvents() {
    final selectedEvents = _selectedEventId == null
        ? _events.values.toList()
        : [_events[_selectedEventId]].whereType<MiddlewareEvent>().toList();

    if (selectedEvents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No events to export'),
          backgroundColor: FluxForgeTheme.accentOrange,
        ),
      );
      return;
    }

    final json = jsonEncode({
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'events': selectedEvents.map((e) => e.toJson()).toList(),
    });

    Clipboard.setData(ClipboardData(text: json));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${selectedEvents.length} events to clipboard'),
        backgroundColor: FluxForgeTheme.accentGreen,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  void _pushUndo(_UndoAction action) {
    _undoStack.add(action);
    _redoStack.clear();
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    _redoStack.add(action);
    _applyUndo(action);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    _undoStack.add(action);
    _applyRedo(action);
  }

  void _applyUndo(_UndoAction action) {
    setState(() {
      switch (action.type) {
        case _UndoActionType.createEvent:
          _events.remove(action.event!.id);
          _categoryFolders[action.event!.category]?.remove(action.event!.id);
          break;
        case _UndoActionType.deleteEvent:
          _events[action.event!.id] = action.event!;
          _categoryFolders.putIfAbsent(action.event!.category, () => [])
              .add(action.event!.id);
          break;
        case _UndoActionType.renameEvent:
          _events[action.event!.id] = action.event!.copyWith(name: action.oldName);
          break;
        case _UndoActionType.addAction:
          final event = _events[action.event!.id];
          if (event != null) {
            _events[event.id] = event.copyWith(
              actions: event.actions.where((a) => a.id != action.action!.id).toList(),
            );
          }
          break;
        case _UndoActionType.removeAction:
          final event = _events[action.event!.id];
          if (event != null) {
            _events[event.id] = event.copyWith(
              actions: [...event.actions, action.action!],
            );
          }
          break;
      }
    });
  }

  void _applyRedo(_UndoAction action) {
    setState(() {
      switch (action.type) {
        case _UndoActionType.createEvent:
          _events[action.event!.id] = action.event!;
          _categoryFolders.putIfAbsent(action.event!.category, () => [])
              .add(action.event!.id);
          break;
        case _UndoActionType.deleteEvent:
          _events.remove(action.event!.id);
          _categoryFolders[action.event!.category]?.remove(action.event!.id);
          break;
        case _UndoActionType.renameEvent:
          _events[action.event!.id] = action.event!.copyWith(name: action.newName);
          break;
        case _UndoActionType.addAction:
          final event = _events[action.event!.id];
          if (event != null) {
            _events[event.id] = event.copyWith(
              actions: [...event.actions, action.action!],
            );
          }
          break;
        case _UndoActionType.removeAction:
          final event = _events[action.event!.id];
          if (event != null) {
            _events[event.id] = event.copyWith(
              actions: event.actions.where((a) => a.id != action.action!.id).toList(),
            );
          }
          break;
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPORT CLASSES
// ═══════════════════════════════════════════════════════════════════════════════

enum _SortMode {
  name(Icons.sort_by_alpha, 'Name'),
  category(Icons.category, 'Category'),
  actions(Icons.flash_on, 'Actions');

  final IconData icon;
  final String label;
  const _SortMode(this.icon, this.label);
}

enum _UndoActionType {
  createEvent,
  deleteEvent,
  renameEvent,
  addAction,
  removeAction,
}

class _UndoAction {
  final _UndoActionType type;
  final MiddlewareEvent? event;
  final MiddlewareAction? action;
  final String? oldName;
  final String? newName;

  _UndoAction({
    required this.type,
    this.event,
    this.action,
    this.oldName,
    this.newName,
  });

  factory _UndoAction.createEvent(MiddlewareEvent event) {
    return _UndoAction(type: _UndoActionType.createEvent, event: event);
  }

  factory _UndoAction.deleteEvent(MiddlewareEvent event) {
    return _UndoAction(type: _UndoActionType.deleteEvent, event: event);
  }

  factory _UndoAction.renameEvent(MiddlewareEvent event, String oldName, String newName) {
    return _UndoAction(
      type: _UndoActionType.renameEvent,
      event: event,
      oldName: oldName,
      newName: newName,
    );
  }

  factory _UndoAction.addAction(MiddlewareEvent event, MiddlewareAction action) {
    return _UndoAction(type: _UndoActionType.addAction, event: event, action: action);
  }

  factory _UndoAction.removeAction(MiddlewareEvent event, MiddlewareAction action) {
    return _UndoAction(type: _UndoActionType.removeAction, event: event, action: action);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMPORT EVENTS DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _ImportEventsDialog extends StatefulWidget {
  final void Function(List<MiddlewareEvent>) onImport;

  const _ImportEventsDialog({required this.onImport});

  @override
  State<_ImportEventsDialog> createState() => _ImportEventsDialogState();
}

class _ImportEventsDialogState extends State<_ImportEventsDialog> {
  final _controller = TextEditingController();
  String? _error;
  List<MiddlewareEvent>? _parsedEvents;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parseJson() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Please paste JSON data';
        _parsedEvents = null;
      });
      return;
    }

    try {
      final data = jsonDecode(text);
      List<dynamic> eventsList;

      if (data is Map && data.containsKey('events')) {
        eventsList = data['events'] as List<dynamic>;
      } else if (data is List) {
        eventsList = data;
      } else {
        throw FormatException('Invalid format: expected array or object with "events" key');
      }

      final events = eventsList
          .map((e) => MiddlewareEvent.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _parsedEvents = events;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Parse error: $e';
        _parsedEvents = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.file_upload, color: FluxForgeTheme.accentBlue, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Import Events',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    color: FluxForgeTheme.textMuted,
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paste JSON data:',
                      style: TextStyle(
                        fontSize: 12,
                        color: FluxForgeTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          fontSize: 11,
                          color: FluxForgeTheme.textPrimary,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '{"events": [...]}',
                          hintStyle: const TextStyle(color: FluxForgeTheme.textMuted),
                          filled: true,
                          fillColor: FluxForgeTheme.bgVoid,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: FluxForgeTheme.accentBlue),
                          ),
                        ),
                        onChanged: (_) => _parseJson(),
                      ),
                    ),

                    // Status
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: FluxForgeTheme.accentRed, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: FluxForgeTheme.accentRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_parsedEvents != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Found ${_parsedEvents!.length} valid events',
                              style: const TextStyle(
                                fontSize: 11,
                                color: FluxForgeTheme.accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _controller.text = data!.text!;
                        _parseJson();
                      }
                    },
                    child: const Text('Paste from Clipboard'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _parsedEvents != null && _parsedEvents!.isNotEmpty
                        ? () {
                            widget.onImport(_parsedEvents!);
                            Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.accentBlue,
                      disabledBackgroundColor: FluxForgeTheme.bgSurface,
                    ),
                    child: const Text('Import'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
