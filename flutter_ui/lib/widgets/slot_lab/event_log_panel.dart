/// Event Log Panel
///
/// Real-time log of all triggered audio events:
/// - Timestamped event entries
/// - Color-coded by event type (Stage, Middleware, RTPC, State)
/// - Filtering by event type
/// - Search functionality
/// - Export log option
/// - Auto-scroll with manual pause
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/slot_lab_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EVENT LOG ENTRY MODEL
// ═══════════════════════════════════════════════════════════════════════════

enum EventLogType {
  stage,      // Stage events (spin_start, reel_stop, etc.)
  middleware, // Middleware events (Post Event, Set State)
  rtpc,       // RTPC parameter changes
  state,      // State/Switch changes
  audio,      // Audio playback events
  error,      // Error events
}

class EventLogEntry {
  final DateTime timestamp;
  final EventLogType type;
  final String eventName;
  final String? details;
  final Map<String, dynamic>? data;
  final bool isError;

  EventLogEntry({
    required this.timestamp,
    required this.type,
    required this.eventName,
    this.details,
    this.data,
    this.isError = false,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  Color get typeColor {
    switch (type) {
      case EventLogType.stage:
        return const Color(0xFF4A9EFF);
      case EventLogType.middleware:
        return const Color(0xFFFF9040);
      case EventLogType.rtpc:
        return const Color(0xFF40FF90);
      case EventLogType.state:
        return const Color(0xFFE040FB);
      case EventLogType.audio:
        return const Color(0xFF40C8FF);
      case EventLogType.error:
        return const Color(0xFFFF4040);
    }
  }

  IconData get typeIcon {
    switch (type) {
      case EventLogType.stage:
        return Icons.timeline;
      case EventLogType.middleware:
        return Icons.send;
      case EventLogType.rtpc:
        return Icons.tune;
      case EventLogType.state:
        return Icons.toggle_on;
      case EventLogType.audio:
        return Icons.volume_up;
      case EventLogType.error:
        return Icons.error_outline;
    }
  }

  String get typeLabel {
    switch (type) {
      case EventLogType.stage:
        return 'STAGE';
      case EventLogType.middleware:
        return 'MW';
      case EventLogType.rtpc:
        return 'RTPC';
      case EventLogType.state:
        return 'STATE';
      case EventLogType.audio:
        return 'AUDIO';
      case EventLogType.error:
        return 'ERROR';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT LOG PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class EventLogPanel extends StatefulWidget {
  final SlotLabProvider slotLabProvider;
  final MiddlewareProvider middlewareProvider;
  final double height;
  final int maxEntries;

  const EventLogPanel({
    super.key,
    required this.slotLabProvider,
    required this.middlewareProvider,
    this.height = 300,
    this.maxEntries = 500,
  });

  @override
  State<EventLogPanel> createState() => _EventLogPanelState();
}

class _EventLogPanelState extends State<EventLogPanel> {
  final List<EventLogEntry> _entries = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _autoScroll = true;
  bool _isPaused = false;
  Set<EventLogType> _activeFilters = EventLogType.values.toSet();
  String _searchQuery = '';
  int _lastMiddlewareEventCount = 0;

  @override
  void initState() {
    super.initState();
    widget.slotLabProvider.addListener(_onSlotLabUpdate);
    widget.middlewareProvider.addListener(_onMiddlewareUpdate);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    widget.slotLabProvider.removeListener(_onSlotLabUpdate);
    widget.middlewareProvider.removeListener(_onMiddlewareUpdate);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSlotLabUpdate() {
    if (_isPaused) return;

    final stages = widget.slotLabProvider.lastStages;
    final currentIndex = widget.slotLabProvider.currentStageIndex;

    if (currentIndex >= 0 && currentIndex < stages.length) {
      final stage = stages[currentIndex];
      _addEntry(EventLogEntry(
        timestamp: DateTime.now(),
        type: EventLogType.stage,
        eventName: stage.stageType.toUpperCase().replaceAll('_', ' '),
        details: stage.payload.isNotEmpty ? stage.payload.toString() : null,
        data: stage.payload,
      ));
    }
  }

  void _onMiddlewareUpdate() {
    if (_isPaused) return;

    // MiddlewareProvider doesn't have eventHistory, skip this for now
    // TODO: Add event history tracking to MiddlewareProvider if needed
  }

  // Placeholder for future middleware event logging
  void _logMiddlewareEvent(String eventName, String targetBus, int priority, String eventId) {
    _addEntry(EventLogEntry(
      timestamp: DateTime.now(),
      type: EventLogType.middleware,
      eventName: eventName,
      details: 'Bus: $targetBus | Priority: $priority',
      data: {
        'event_id': eventId,
        'target_bus': targetBus,
        'priority': priority,
      },
    ));
  }

  void _addEntry(EventLogEntry entry) {
    setState(() {
      _entries.add(entry);

      // Limit entries
      if (_entries.length > widget.maxEntries) {
        _entries.removeAt(0);
      }
    });

    // Auto-scroll to bottom
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _addRtpcEntry(String paramName, double value) {
    if (_isPaused) return;

    _addEntry(EventLogEntry(
      timestamp: DateTime.now(),
      type: EventLogType.rtpc,
      eventName: paramName,
      details: 'Value: ${value.toStringAsFixed(3)}',
      data: {'value': value},
    ));
  }

  void _addStateEntry(String stateGroup, String stateName) {
    if (_isPaused) return;

    _addEntry(EventLogEntry(
      timestamp: DateTime.now(),
      type: EventLogType.state,
      eventName: '$stateGroup: $stateName',
    ));
  }

  void _addAudioEntry(String audioEvent, {String? details}) {
    if (_isPaused) return;

    _addEntry(EventLogEntry(
      timestamp: DateTime.now(),
      type: EventLogType.audio,
      eventName: audioEvent,
      details: details,
    ));
  }

  void _clearLog() {
    setState(() {
      _entries.clear();
    });
  }

  void _copyLogToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('FluxForge Slot Lab Event Log');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('=' * 60);

    for (final entry in _filteredEntries) {
      buffer.writeln('[${entry.formattedTime}] [${entry.typeLabel}] ${entry.eventName}');
      if (entry.details != null) {
        buffer.writeln('  Details: ${entry.details}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Log copied to clipboard (${_filteredEntries.length} entries)'),
        backgroundColor: FluxForgeTheme.accentGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<EventLogEntry> get _filteredEntries {
    return _entries.where((entry) {
      // Type filter
      if (!_activeFilters.contains(entry.type)) return false;

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesName = entry.eventName.toLowerCase().contains(_searchQuery);
        final matchesDetails = entry.details?.toLowerCase().contains(_searchQuery) ?? false;
        if (!matchesName && !matchesDetails) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(child: _buildLogList()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long,
            size: 14,
            color: _isPaused ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Text(
            'EVENT LOG',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),

          // Search box
          SizedBox(
            width: 150,
            height: 20,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 10),
                prefixIcon: Icon(Icons.search, size: 12, color: Colors.white38),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
                filled: true,
                fillColor: FluxForgeTheme.bgDeep,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Pause button
          _buildIconButton(
            icon: _isPaused ? Icons.play_arrow : Icons.pause,
            tooltip: _isPaused ? 'Resume' : 'Pause',
            color: _isPaused ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
            onPressed: () => setState(() => _isPaused = !_isPaused),
          ),

          // Auto-scroll toggle
          _buildIconButton(
            icon: Icons.vertical_align_bottom,
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            color: _autoScroll ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),

          // Clear button
          _buildIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Clear log',
            color: FluxForgeTheme.textSecondary,
            onPressed: _clearLog,
          ),

          // Copy button
          _buildIconButton(
            icon: Icons.copy,
            tooltip: 'Copy to clipboard',
            color: FluxForgeTheme.textSecondary,
            onPressed: _copyLogToClipboard,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Filter:',
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const SizedBox(width: 8),
          ...EventLogType.values.map((type) {
            final isActive = _activeFilters.contains(type);
            final entry = EventLogEntry(
              timestamp: DateTime.now(),
              type: type,
              eventName: '',
            );

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (isActive) {
                      _activeFilters.remove(type);
                    } else {
                      _activeFilters.add(type);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? entry.typeColor.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isActive
                          ? entry.typeColor
                          : entry.typeColor.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.typeIcon,
                        size: 10,
                        color: isActive
                            ? entry.typeColor
                            : entry.typeColor.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.typeLabel,
                        style: TextStyle(
                          color: isActive
                              ? entry.typeColor
                              : entry.typeColor.withOpacity(0.5),
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Show all / Show none
          InkWell(
            onTap: () {
              setState(() {
                if (_activeFilters.length == EventLogType.values.length) {
                  _activeFilters.clear();
                } else {
                  _activeFilters = EventLogType.values.toSet();
                }
              });
            },
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                _activeFilters.length == EventLogType.values.length
                    ? 'HIDE ALL'
                    : 'SHOW ALL',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    final entries = _filteredEntries;

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.hourglass_empty,
              size: 32,
              color: Colors.white24,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching events'
                  : 'Waiting for events...',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (_isPaused)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PAUSED',
                    style: TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _buildLogEntry(entries[index], index);
      },
    );
  }

  Widget _buildLogEntry(EventLogEntry entry, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.transparent : Colors.white.withOpacity(0.02),
        border: Border(
          left: BorderSide(
            color: entry.typeColor,
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 70,
            child: Text(
              entry.formattedTime,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Type badge
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: entry.typeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.typeIcon, size: 8, color: entry.typeColor),
                const SizedBox(width: 2),
                Text(
                  entry.typeLabel,
                  style: TextStyle(
                    color: entry.typeColor,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Event name and details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.eventName,
                  style: TextStyle(
                    color: entry.isError ? FluxForgeTheme.accentRed : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (entry.details != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.details!,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      child: Row(
        children: [
          // Entry count
          Text(
            '${_filteredEntries.length} / ${_entries.length} events',
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          const Spacer(),

          // Status indicators
          if (_isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Icon(Icons.pause, size: 8, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 2),
                  Text(
                    'PAUSED',
                    style: TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          if (_autoScroll && !_isPaused)
            Row(
              children: [
                Icon(Icons.vertical_align_bottom, size: 10, color: FluxForgeTheme.accentBlue),
                const SizedBox(width: 2),
                Text(
                  'AUTO-SCROLL',
                  style: TextStyle(
                    color: FluxForgeTheme.accentBlue,
                    fontSize: 7,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT EVENT LOG STRIP
// ═══════════════════════════════════════════════════════════════════════════

/// Compact horizontal log strip for footer/header use
class EventLogStrip extends StatelessWidget {
  final SlotLabProvider slotLabProvider;
  final MiddlewareProvider middlewareProvider;
  final int maxVisible;
  final double height;

  const EventLogStrip({
    super.key,
    required this.slotLabProvider,
    required this.middlewareProvider,
    this.maxVisible = 5,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([slotLabProvider, middlewareProvider]),
      builder: (context, child) {
        final stages = slotLabProvider.lastStages;
        final currentIndex = slotLabProvider.currentStageIndex;

        // Get last N stages
        final visibleStages = currentIndex >= 0
            ? stages.sublist(
                (currentIndex - maxVisible + 1).clamp(0, stages.length),
                (currentIndex + 1).clamp(0, stages.length),
              )
            : <dynamic>[];

        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long, size: 12, color: Colors.white38),
              const SizedBox(width: 8),
              Expanded(
                child: visibleStages.isEmpty
                    ? Text(
                        'No events',
                        style: TextStyle(color: Colors.white38, fontSize: 9),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: visibleStages.length,
                        itemBuilder: (context, index) {
                          final stage = visibleStages[index];
                          final isLatest = index == visibleStages.length - 1;

                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isLatest
                                    ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: isLatest
                                      ? FluxForgeTheme.accentBlue
                                      : Colors.transparent,
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                stage.stageType.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  color: isLatest
                                      ? FluxForgeTheme.accentBlue
                                      : Colors.white54,
                                  fontSize: 8,
                                  fontWeight:
                                      isLatest ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
