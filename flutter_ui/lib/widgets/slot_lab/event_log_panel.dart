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
import '../../services/event_registry.dart';
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

  /// Container integration - type of container used (if any)
  final ContainerType? containerType;
  /// Container integration - name of container used
  final String? containerName;
  /// Container integration - number of children/steps in container
  final int? containerChildCount;

  EventLogEntry({
    required this.timestamp,
    required this.type,
    required this.eventName,
    this.details,
    this.data,
    this.isError = false,
    this.containerType,
    this.containerName,
    this.containerChildCount,
  });

  /// Returns true if this entry used a container for playback
  bool get usesContainer => containerType != null && containerType != ContainerType.none;

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
  int _lastLoggedStageIndex = -1; // Track last logged stage to avoid duplicates
  int _lastLoggedSpinCount = -1; // Track spin count to reset on new spin
  int _lastTriggerCount = 0; // Track EventRegistry trigger count

  @override
  void initState() {
    super.initState();
    widget.slotLabProvider.addListener(_onSlotLabUpdate);
    widget.middlewareProvider.addListener(_onMiddlewareUpdate);
    eventRegistry.addListener(_onEventRegistryUpdate);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    widget.slotLabProvider.removeListener(_onSlotLabUpdate);
    widget.middlewareProvider.removeListener(_onMiddlewareUpdate);
    eventRegistry.removeListener(_onEventRegistryUpdate);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onEventRegistryUpdate() {
    if (_isPaused) return;

    // Check if a new audio was triggered
    final currentTriggerCount = eventRegistry.triggerCount;
    if (currentTriggerCount > _lastTriggerCount) {
      _lastTriggerCount = currentTriggerCount;

      // Get actual event name and stage from EventRegistry
      final eventName = eventRegistry.lastTriggeredEventName;
      final stageName = eventRegistry.lastTriggeredStage;
      final layers = eventRegistry.lastTriggeredLayers;
      final success = eventRegistry.lastTriggerSuccess;
      final error = eventRegistry.lastTriggerError;

      // Determine event type:
      // - AUDIO: has layers and triggered successfully
      // - STAGE: no audio event configured (just stage marker)
      // - ERROR: actual playback error
      final EventLogType logType;
      final bool isError;

      if (success && layers.isNotEmpty) {
        logType = EventLogType.audio;
        isError = false;
      } else if (eventName == '(no audio)' || layers.isEmpty) {
        // Stage without audio event — show as STAGE, not ERROR
        logType = EventLogType.stage;
        isError = false;
      } else {
        // Actual error (playback failed)
        logType = EventLogType.error;
        isError = true;
      }

      // Format display name based on type
      String displayName;
      if (logType == EventLogType.stage) {
        // Just show stage name for stages without audio
        displayName = stageName;
      } else {
        // COMPACT FORMAT: "Event Name → STAGE [files]"
        final layerList = layers.isNotEmpty ? ' [${layers.join(", ")}]' : '';
        displayName = '$eventName → $stageName$layerList';
      }

      // Details only show error info or voice/bus debug
      String? details;
      if (isError && error.isNotEmpty) {
        details = error;
      } else if (success && error.isNotEmpty) {
        // Success but has debug info (voice=X, bus=Y, section=Z)
        details = error;
      }

      // Get container info if event used container
      final containerType = eventRegistry.lastContainerType;
      final containerName = eventRegistry.lastContainerName;
      final containerChildCount = eventRegistry.lastContainerChildCount;

      _addEntry(EventLogEntry(
        timestamp: DateTime.now(),
        type: logType,
        eventName: displayName,
        details: details,
        data: {'triggerCount': currentTriggerCount, 'stage': stageName, 'event': eventName, 'layers': layers, 'success': success, 'error': error},
        isError: isError,
        containerType: containerType != ContainerType.none ? containerType : null,
        containerName: containerName,
        containerChildCount: containerChildCount,
      ));
    }

    // Force rebuild to update registered stages display
    if (mounted) setState(() {});
  }

  void _onSlotLabUpdate() {
    // STAGE events are now logged exclusively by _onEventRegistryUpdate
    // EventRegistry.triggerStage() increments counter for BOTH:
    // - Stages with audio (logged as AUDIO type with layer info)
    // - Stages without audio (logged as STAGE type, "(no audio)")
    // This prevents any duplicate entries
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
    // Determine visual style based on entry type and success
    final isAudioSuccess = entry.type == EventLogType.audio && !entry.isError;
    final isAudioMissing = entry.type == EventLogType.stage; // Stage without audio
    final isError = entry.isError;

    // Color coding for maximum clarity
    final Color leftBorderColor;
    final Color bgColor;
    final Color textColor;
    final IconData statusIcon;

    if (isAudioSuccess) {
      // SUCCESS: Green — audio played correctly
      leftBorderColor = const Color(0xFF40FF90);
      bgColor = const Color(0xFF40FF90).withOpacity(0.08);
      textColor = const Color(0xFF40FF90);
      statusIcon = Icons.volume_up;
    } else if (isAudioMissing) {
      // WARNING: Orange — stage fired but no audio configured
      leftBorderColor = const Color(0xFFFF9040);
      bgColor = const Color(0xFFFF9040).withOpacity(0.08);
      textColor = const Color(0xFFFF9040);
      statusIcon = Icons.volume_off;
    } else if (isError) {
      // ERROR: Red — something failed
      leftBorderColor = const Color(0xFFFF4040);
      bgColor = const Color(0xFFFF4040).withOpacity(0.08);
      textColor = const Color(0xFFFF4040);
      statusIcon = Icons.error_outline;
    } else {
      // DEFAULT: Use entry's type color
      leftBorderColor = entry.typeColor;
      bgColor = index.isEven ? Colors.transparent : Colors.white.withOpacity(0.02);
      textColor = Colors.white70;
      statusIcon = entry.typeIcon;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: leftBorderColor,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          // Status icon (prominent)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: leftBorderColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              statusIcon,
              size: 14,
              color: leftBorderColor,
            ),
          ),

          const SizedBox(width: 10),

          // Main content (single line when possible)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Event name — bold, colored
                Text(
                  entry.eventName,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Details — smaller, dimmed
                if (entry.details != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.details!,
                      style: TextStyle(
                        color: textColor.withOpacity(0.6),
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                // Container info — if event uses container
                if (entry.usesContainer)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildContainerBadge(entry),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Timestamp (right-aligned, compact)
          Text(
            entry.formattedTime.substring(0, 8), // HH:MM:SS without ms
            style: TextStyle(
              color: Colors.white24,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Build container type badge for log entry
  Widget _buildContainerBadge(EventLogEntry entry) {
    final containerType = entry.containerType;
    if (containerType == null || containerType == ContainerType.none) {
      return const SizedBox.shrink();
    }

    // Color based on container type
    final Color badgeColor;
    final IconData badgeIcon;
    final String typeName;

    switch (containerType) {
      case ContainerType.blend:
        badgeColor = Colors.purple;
        badgeIcon = Icons.tune;
        typeName = 'BLEND';
        break;
      case ContainerType.random:
        badgeColor = Colors.amber;
        badgeIcon = Icons.shuffle;
        typeName = 'RANDOM';
        break;
      case ContainerType.sequence:
        badgeColor = Colors.teal;
        badgeIcon = Icons.list;
        typeName = 'SEQ';
        break;
      case ContainerType.none:
        return const SizedBox.shrink();
    }

    final childLabel = containerType == ContainerType.sequence ? 'steps' : 'children';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: badgeColor.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(badgeIcon, size: 10, color: badgeColor),
              const SizedBox(width: 3),
              Text(
                typeName,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${entry.containerName ?? "?"} (${entry.containerChildCount ?? 0} $childLabel)',
          style: TextStyle(
            color: badgeColor.withOpacity(0.7),
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    // Get registered stages from EventRegistry
    final registeredEvents = eventRegistry.allEvents;
    final registeredCount = registeredEvents.length;
    final hasAudio = registeredEvents.any((e) => e.layers.isNotEmpty);

    // Status indicator
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (registeredCount == 0) {
      statusColor = const Color(0xFFFF4040); // Red
      statusIcon = Icons.warning_amber;
      statusText = 'No events — create events to hear audio';
    } else if (!hasAudio) {
      statusColor = const Color(0xFFFF9040); // Orange
      statusIcon = Icons.volume_off;
      statusText = '$registeredCount events (no audio files assigned)';
    } else {
      statusColor = const Color(0xFF40FF90); // Green
      statusIcon = Icons.check_circle;
      statusText = '$registeredCount events ready';
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      child: Row(
        children: [
          // Entry count (dimmed)
          Text(
            '${_filteredEntries.length} log entries',
            style: const TextStyle(color: Colors.white30, fontSize: 9),
          ),

          const Spacer(),

          // Main status indicator (prominent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  statusIcon,
                  size: 12,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

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
