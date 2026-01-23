// mock_engine_panel.dart — UI for MockEngineService (Staging Mode)
// P3.14: Staging mode for testing audio without real engine connection

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/mock_engine_service.dart';

/// Panel for controlling the mock engine in staging mode.
/// Allows testing audio events without connecting to a real game engine.
class MockEnginePanel extends StatefulWidget {
  /// Callback when a stage event is emitted
  final void Function(MockStageEvent event)? onStageEvent;

  const MockEnginePanel({
    super.key,
    this.onStageEvent,
  });

  @override
  State<MockEnginePanel> createState() => _MockEnginePanelState();
}

class _MockEnginePanelState extends State<MockEnginePanel> {
  final _service = MockEngineService.instance;
  StreamSubscription<MockStageEvent>? _eventSubscription;

  // Event log
  final List<_EventLogEntry> _eventLog = [];
  static const int _maxLogEntries = 100;
  final ScrollController _logScrollController = ScrollController();

  // UI state
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _service.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  void _onEvent(MockStageEvent event) {
    // Add to log
    setState(() {
      _eventLog.add(_EventLogEntry(
        timestamp: DateTime.now(),
        event: event,
      ));
      if (_eventLog.length > _maxLogEntries) {
        _eventLog.removeAt(0);
      }
    });

    // Auto-scroll
    if (_autoScroll && _logScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }

    // Forward to parent
    widget.onStageEvent?.call(event);
  }

  void _clearLog() {
    setState(() {
      _eventLog.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with status
        _buildHeader(),
        const Divider(height: 1),

        // Controls row
        _buildControlsRow(),
        const Divider(height: 1),

        // Quick actions
        _buildQuickActions(),
        const Divider(height: 1),

        // Sequences
        _buildSequenceButtons(),
        const Divider(height: 1),

        // Event log
        Expanded(child: _buildEventLog()),
      ],
    );
  }

  Widget _buildHeader() {
    final isRunning = _service.isRunning;
    final mode = _service.mode;
    final context = _service.currentContext;
    final spinCount = _service.spinCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isRunning ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning ? Colors.green : Colors.grey,
              boxShadow: isRunning
                  ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),

          // Title
          Text(
            'Mock Engine',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isRunning ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),

          // Mode badge
          _buildBadge(
            mode.name.toUpperCase(),
            _getModeColor(mode),
          ),
          const SizedBox(width: 8),

          // Context badge
          _buildBadge(
            context.name.toUpperCase(),
            _getContextColor(context),
          ),
          const SizedBox(width: 8),

          // Spin count
          Text(
            'Spins: $spinCount',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),

          const Spacer(),

          // Config preset
          DropdownButton<MockEngineConfig>(
            value: _service.config,
            isDense: true,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: MockEngineConfig.studio,
                child: Text('Studio', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: MockEngineConfig.turbo,
                child: Text('Turbo', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: MockEngineConfig.demo,
                child: Text('Demo', style: TextStyle(fontSize: 12)),
              ),
            ],
            onChanged: (config) {
              if (config != null) {
                setState(() {
                  _service.config = config;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getModeColor(MockEngineMode mode) {
    switch (mode) {
      case MockEngineMode.idle:
        return Colors.grey;
      case MockEngineMode.manual:
        return Colors.blue;
      case MockEngineMode.autoSpin:
        return Colors.orange;
      case MockEngineMode.sequence:
        return Colors.purple;
    }
  }

  Color _getContextColor(MockGameContext context) {
    switch (context) {
      case MockGameContext.base:
        return Colors.blue;
      case MockGameContext.freeSpins:
        return Colors.green;
      case MockGameContext.bonus:
        return Colors.amber;
      case MockGameContext.holdWin:
        return Colors.purple;
      case MockGameContext.gamble:
        return Colors.red;
    }
  }

  Widget _buildControlsRow() {
    final isRunning = _service.isRunning;
    final mode = _service.mode;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Start/Stop button
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                if (isRunning) {
                  _service.stop();
                } else {
                  _service.start();
                }
              });
            },
            icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 18),
            label: Text(isRunning ? 'Stop' : 'Start'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),

          // Mode selector
          SegmentedButton<MockEngineMode>(
            segments: const [
              ButtonSegment(
                value: MockEngineMode.manual,
                label: Text('Manual', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.touch_app, size: 16),
              ),
              ButtonSegment(
                value: MockEngineMode.autoSpin,
                label: Text('Auto', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.autorenew, size: 16),
              ),
              ButtonSegment(
                value: MockEngineMode.sequence,
                label: Text('Sequence', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.playlist_play, size: 16),
              ),
            ],
            selected: {mode == MockEngineMode.idle ? MockEngineMode.manual : mode},
            onSelectionChanged: (selection) {
              setState(() {
                _service.setMode(selection.first);
              });
            },
          ),
          const Spacer(),

          // Context selector
          const Text('Context: ', style: TextStyle(fontSize: 12)),
          DropdownButton<MockGameContext>(
            value: _service.currentContext,
            isDense: true,
            underline: const SizedBox(),
            items: MockGameContext.values.map((ctx) {
              return DropdownMenuItem(
                value: ctx,
                child: Text(ctx.name, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
            onChanged: (ctx) {
              if (ctx != null) {
                setState(() {
                  _service.setContext(ctx);
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final isRunning = _service.isRunning;
    final mode = _service.mode;
    final isManual = mode == MockEngineMode.manual;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Spin (with outcome)',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildOutcomeButton('Lose', MockWinTier.lose, Colors.grey, isRunning && isManual),
              _buildOutcomeButton('Small', MockWinTier.small, Colors.green, isRunning && isManual),
              _buildOutcomeButton('Medium', MockWinTier.medium, Colors.teal, isRunning && isManual),
              _buildOutcomeButton('Big', MockWinTier.big, Colors.blue, isRunning && isManual),
              _buildOutcomeButton('Mega', MockWinTier.mega, Colors.purple, isRunning && isManual),
              _buildOutcomeButton('Epic', MockWinTier.epic, Colors.orange, isRunning && isManual),
              _buildOutcomeButton('JP Mini', MockWinTier.jackpotMini, Colors.amber, isRunning && isManual),
              _buildOutcomeButton('JP Minor', MockWinTier.jackpotMinor, Colors.amber.shade700, isRunning && isManual),
              _buildOutcomeButton('JP Major', MockWinTier.jackpotMajor, Colors.deepOrange, isRunning && isManual),
              _buildOutcomeButton('JP Grand', MockWinTier.jackpotGrand, Colors.red, isRunning && isManual),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeButton(String label, MockWinTier tier, Color color, bool enabled) {
    return SizedBox(
      height: 28,
      child: ElevatedButton(
        onPressed: enabled
            ? () {
                _service.triggerSpinWithOutcome(tier);
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 10),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildSequenceButtons() {
    final isRunning = _service.isRunning;
    final mode = _service.mode;
    final canPlay = isRunning && mode != MockEngineMode.sequence;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Predefined Sequences',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildSequenceButton(
                'Normal Win',
                MockEventSequence.normalWin(),
                Icons.attach_money,
                Colors.green,
                canPlay,
              ),
              _buildSequenceButton(
                'Big Win',
                MockEventSequence.bigWin(),
                Icons.stars,
                Colors.blue,
                canPlay,
              ),
              _buildSequenceButton(
                'Free Spins',
                MockEventSequence.freeSpinsTrigger(),
                Icons.card_giftcard,
                Colors.purple,
                canPlay,
              ),
              _buildSequenceButton(
                'Cascade',
                MockEventSequence.cascade(),
                Icons.waterfall_chart,
                Colors.teal,
                canPlay,
              ),
              _buildSequenceButton(
                'Jackpot',
                MockEventSequence.jackpot(),
                Icons.emoji_events,
                Colors.amber,
                canPlay,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSequenceButton(
    String label,
    MockEventSequence sequence,
    IconData icon,
    Color color,
    bool enabled,
  ) {
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: enabled
            ? () {
                _service.playSequence(sequence);
              }
            : null,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildEventLog() {
    return Column(
      children: [
        // Log header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.grey.withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.list_alt, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Event Log (${_eventLog.length})',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Spacer(),
              // Auto-scroll toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Auto-scroll', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  SizedBox(
                    height: 20,
                    child: Switch(
                      value: _autoScroll,
                      onChanged: (v) => setState(() => _autoScroll = v),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Clear button
              IconButton(
                onPressed: _clearLog,
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Clear log',
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),

        // Log list
        Expanded(
          child: _eventLog.isEmpty
              ? const Center(
                  child: Text(
                    'No events yet.\nStart the mock engine and trigger a spin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _logScrollController,
                  itemCount: _eventLog.length,
                  itemBuilder: (context, index) {
                    final entry = _eventLog[index];
                    return _buildLogEntry(entry);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(_EventLogEntry entry) {
    final event = entry.event;
    final color = _getStageColor(event.stage);
    final timeStr = _formatTime(entry.timestamp);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 70,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
          ),

          // Stage indicator
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4, right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),

          // Stage name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.stage,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
                if (event.data.isNotEmpty)
                  Text(
                    _formatData(event.data),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStageColor(String stage) {
    if (stage.contains('SPIN')) return Colors.blue;
    if (stage.contains('REEL')) return Colors.teal;
    if (stage.contains('WIN') || stage.contains('ROLLUP')) return Colors.green;
    if (stage.contains('BIGWIN') || stage.contains('MEGAWIN') || stage.contains('EPICWIN')) {
      return Colors.orange;
    }
    if (stage.contains('JACKPOT')) return Colors.amber;
    if (stage.contains('CASCADE')) return Colors.purple;
    if (stage.contains('FREE') || stage.contains('SCATTER')) return Colors.pink;
    if (stage.contains('ANTICIPATION')) return Colors.cyan;
    if (stage.contains('BONUS') || stage.contains('FEATURE')) return Colors.deepPurple;
    return Colors.grey;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatData(Map<String, dynamic> data) {
    final parts = <String>[];
    for (final entry in data.entries) {
      if (entry.value is List) {
        parts.add('${entry.key}=[${(entry.value as List).length}]');
      } else {
        parts.add('${entry.key}=${entry.value}');
      }
    }
    return parts.join(', ');
  }
}

class _EventLogEntry {
  final DateTime timestamp;
  final MockStageEvent event;

  _EventLogEntry({
    required this.timestamp,
    required this.event,
  });
}

/// Compact badge showing mock engine status
class MockEngineBadge extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onTap;

  const MockEngineBadge({
    super.key,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.green.withOpacity(0.2)
              : Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isActive ? 'MOCK' : 'MOCK OFF',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
