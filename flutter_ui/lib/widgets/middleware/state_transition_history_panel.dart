/// State Transition History Panel
///
/// Real-time log of state group and switch group transitions for debugging.
/// Displays:
/// - StateGroup transitions (global states)
/// - SwitchGroup transitions (per-object switches)
/// - Timestamps with ms precision
/// - From/To state names
/// - Transition duration
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/subsystems/state_groups_provider.dart';
import '../../providers/subsystems/switch_groups_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Types of state transitions
enum TransitionType {
  stateGroup,
  switchGroup,
}

/// A single transition event
class TransitionEvent {
  final int id;
  final TransitionType type;
  final String groupName;
  final int groupId;
  final String fromState;
  final String toState;
  final DateTime timestamp;
  final double? transitionDuration;

  const TransitionEvent({
    required this.id,
    required this.type,
    required this.groupName,
    required this.groupId,
    required this.fromState,
    required this.toState,
    required this.timestamp,
    this.transitionDuration,
  });

  String get typeLabel => type == TransitionType.stateGroup ? 'STATE' : 'SWITCH';

  Color get typeColor => type == TransitionType.stateGroup
      ? FluxForgeTheme.accentBlue
      : FluxForgeTheme.accentOrange;

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }
}

/// State Transition History Log Panel
class StateTransitionHistoryPanel extends StatefulWidget {
  final int maxEvents;
  final bool showStateGroups;
  final bool showSwitchGroups;
  final bool autoScroll;

  const StateTransitionHistoryPanel({
    super.key,
    this.maxEvents = 200,
    this.showStateGroups = true,
    this.showSwitchGroups = true,
    this.autoScroll = true,
  });

  @override
  State<StateTransitionHistoryPanel> createState() =>
      _StateTransitionHistoryPanelState();
}

class _StateTransitionHistoryPanelState
    extends State<StateTransitionHistoryPanel> {
  final List<TransitionEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  int _nextEventId = 0;
  bool _isPaused = false;
  String _filterText = '';
  TransitionType? _typeFilter;

  // Cached state for detecting changes
  Map<int, int> _lastStateGroupStates = {};
  Map<int, Map<int, int>> _lastSwitchGroupStates = {};

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll for state changes every 50ms
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_isPaused) _checkForChanges();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    if (!mounted) return;

    final stateGroupsProvider = context.read<StateGroupsProvider>();
    final switchGroupsProvider = context.read<SwitchGroupsProvider>();

    // Check StateGroups
    if (widget.showStateGroups) {
      for (final group in stateGroupsProvider.stateGroups.values) {
        final lastState = _lastStateGroupStates[group.id];
        if (lastState != null && lastState != group.currentStateId) {
          _addEvent(TransitionEvent(
            id: _nextEventId++,
            type: TransitionType.stateGroup,
            groupName: group.name,
            groupId: group.id,
            fromState: group.stateName(lastState) ?? 'Unknown',
            toState: group.currentStateName,
            timestamp: DateTime.now(),
            transitionDuration: group.transitionTimeSecs,
          ));
        }
        _lastStateGroupStates[group.id] = group.currentStateId;
      }
    }

    // Check SwitchGroups
    // Note: Switch groups are per-object, so we need to track each object's switch state
    if (widget.showSwitchGroups) {
      for (final group in switchGroupsProvider.switchGroups.values) {
        _lastSwitchGroupStates[group.id] ??= {};
        // Iterate all known objects that have switches for this group
        // This is a simplified approach - in production, you'd track all registered objects
        final knownObjects = _lastSwitchGroupStates[group.id]!.keys.toList();
        for (final objectId in knownObjects) {
          final currentState = switchGroupsProvider.getSwitch(objectId, group.id) ?? group.defaultSwitchId;
          final lastState = _lastSwitchGroupStates[group.id]?[objectId];
          if (lastState != null && lastState != currentState) {
            _addEvent(TransitionEvent(
              id: _nextEventId++,
              type: TransitionType.switchGroup,
              groupName: '${group.name}[obj:$objectId]',
              groupId: group.id,
              fromState: group.switchName(lastState) ?? 'Unknown',
              toState: group.switchName(currentState) ?? 'Unknown',
              timestamp: DateTime.now(),
            ));
          }
          _lastSwitchGroupStates[group.id]![objectId] = currentState;
        }
      }
    }
  }

  void _addEvent(TransitionEvent event) {
    setState(() {
      _events.add(event);
      while (_events.length > widget.maxEvents) {
        _events.removeAt(0);
      }
    });

    // Auto-scroll to bottom
    if (widget.autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _clearEvents() {
    setState(() {
      _events.clear();
      _nextEventId = 0;
    });
  }

  void _copyToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('State Transition History');
    buffer.writeln('========================');
    for (final event in _filteredEvents) {
      buffer.writeln(
          '${event.formattedTime} [${event.typeLabel}] ${event.groupName}: ${event.fromState} → ${event.toState}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }

  List<TransitionEvent> get _filteredEvents {
    return _events.where((event) {
      // Type filter
      if (_typeFilter != null && event.type != _typeFilter) return false;
      // Text filter
      if (_filterText.isNotEmpty) {
        final search = _filterText.toLowerCase();
        return event.groupName.toLowerCase().contains(search) ||
            event.fromState.toLowerCase().contains(search) ||
            event.toState.toLowerCase().contains(search);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEvents;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Filter bar
          _buildFilterBar(),
          // Events list
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildEventRow(filtered[index]),
                  ),
          ),
          // Footer
          _buildFooter(filtered.length),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 8),
          Text(
            'STATE TRANSITIONS',
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Pause toggle
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              size: 14,
            ),
            onPressed: () => setState(() => _isPaused = !_isPaused),
            splashRadius: 12,
            color: _isPaused ? FluxForgeTheme.accentOrange : Colors.white38,
            tooltip: _isPaused ? 'Resume' : 'Pause',
          ),
          // Copy
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            onPressed: _events.isNotEmpty ? _copyToClipboard : null,
            splashRadius: 12,
            color: Colors.white38,
            tooltip: 'Copy to clipboard',
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 14),
            onPressed: _events.isNotEmpty ? _clearEvents : null,
            splashRadius: 12,
            color: Colors.white38,
            tooltip: 'Clear history',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: SizedBox(
              height: 24,
              child: TextField(
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Filter...',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                  prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white24),
                  filled: true,
                  fillColor: FluxForgeTheme.bgDeep,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onChanged: (value) => setState(() => _filterText = value),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Type filter chips
          _buildTypeChip('All', null),
          const SizedBox(width: 4),
          _buildTypeChip('STATE', TransitionType.stateGroup),
          const SizedBox(width: 4),
          _buildTypeChip('SWITCH', TransitionType.switchGroup),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, TransitionType? type) {
    final isSelected = _typeFilter == type;
    final color = type == null
        ? Colors.white54
        : type == TransitionType.stateGroup
            ? FluxForgeTheme.accentBlue
            : FluxForgeTheme.accentOrange;

    return GestureDetector(
      onTap: () => setState(() => _typeFilter = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : FluxForgeTheme.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 32,
            color: Colors.white12,
          ),
          const SizedBox(height: 8),
          Text(
            _isPaused ? 'Paused' : 'Waiting for state changes...',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 11,
            ),
          ),
          if (_filterText.isNotEmpty || _typeFilter != null) ...[
            const SizedBox(height: 4),
            Text(
              '(filtered)',
              style: TextStyle(
                color: Colors.white12,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventRow(TransitionEvent event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Timestamp
          SizedBox(
            width: 85,
            child: Text(
              event.formattedTime,
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: event.typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              event.typeLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: event.typeColor,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Group name
          Expanded(
            flex: 2,
            child: Text(
              event.groupName,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Transition arrow
          const SizedBox(width: 4),
          Text(
            event.fromState,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward, size: 10, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 4),
          Expanded(
            flex: 1,
            child: Text(
              event.toState,
              style: TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Duration (if available)
          if (event.transitionDuration != null && event.transitionDuration! > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${(event.transitionDuration! * 1000).toStringAsFixed(0)}ms',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(int filteredCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$filteredCount events',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
          if (_filterText.isNotEmpty || _typeFilter != null) ...[
            Text(
              ' (${_events.length} total)',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 9,
              ),
            ),
          ],
          const Spacer(),
          if (_isPaused)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'PAUSED',
                style: TextStyle(
                  color: FluxForgeTheme.accentOrange,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact inline state transition indicator
class StateTransitionIndicator extends StatefulWidget {
  const StateTransitionIndicator({super.key});

  @override
  State<StateTransitionIndicator> createState() => _StateTransitionIndicatorState();
}

class _StateTransitionIndicatorState extends State<StateTransitionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _hasRecentTransition = false;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _resetTimer?.cancel();
    super.dispose();
  }

  void showTransition() {
    setState(() => _hasRecentTransition = true);
    _pulseController.forward(from: 0.0);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _hasRecentTransition = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _hasRecentTransition
                ? FluxForgeTheme.accentGreen.withValues(alpha: 1.0 - _pulseController.value * 0.5)
                : Colors.white12,
            shape: BoxShape.circle,
            boxShadow: _hasRecentTransition
                ? [
                    BoxShadow(
                      color: FluxForgeTheme.accentGreen.withValues(alpha: 0.5 * (1.0 - _pulseController.value)),
                      blurRadius: 4 * (1.0 + _pulseController.value),
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
