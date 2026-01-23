/// Event Debugger Panel
///
/// Advanced debugging panel for audio event system:
/// - Stage→Event resolution trace visualization
/// - Event mapping browser (all registered events)
/// - Error diagnostics with root cause analysis
/// - Real-time trigger monitoring
/// - Voice allocation tracking
///
/// Part of P3.2: Event debugger/tracer panel
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/event_registry.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TRACE ENTRY MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Represents a single step in event resolution
class TraceStep {
  final String label;
  final String? value;
  final TraceStepStatus status;
  final String? detail;

  const TraceStep({
    required this.label,
    this.value,
    this.status = TraceStepStatus.success,
    this.detail,
  });
}

enum TraceStepStatus { success, warning, error, skipped }

/// Complete trace of event resolution
class EventTrace {
  final DateTime timestamp;
  final String stageName;
  final List<TraceStep> steps;
  final bool success;
  final Duration? latency;

  const EventTrace({
    required this.timestamp,
    required this.stageName,
    required this.steps,
    required this.success,
    this.latency,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// EVENT DEBUGGER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class EventDebuggerPanel extends StatefulWidget {
  const EventDebuggerPanel({super.key});

  @override
  State<EventDebuggerPanel> createState() => _EventDebuggerPanelState();
}

class _EventDebuggerPanelState extends State<EventDebuggerPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<EventTrace> _traces = [];
  final ScrollController _traceScrollController = ScrollController();
  int _lastTriggerCount = 0;
  bool _autoScroll = true;
  bool _isPaused = false;

  // Stats
  int _totalEvents = 0;
  int _successCount = 0;
  int _errorCount = 0;
  int _noAudioCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    eventRegistry.addListener(_onEventRegistryUpdate);
  }

  @override
  void dispose() {
    eventRegistry.removeListener(_onEventRegistryUpdate);
    _tabController.dispose();
    _traceScrollController.dispose();
    super.dispose();
  }

  void _onEventRegistryUpdate() {
    if (_isPaused) return;

    final currentTriggerCount = eventRegistry.triggerCount;
    if (currentTriggerCount > _lastTriggerCount) {
      _lastTriggerCount = currentTriggerCount;
      _captureTrace();
    }
  }

  void _captureTrace() {
    final stageName = eventRegistry.lastTriggeredStage;
    final eventName = eventRegistry.lastTriggeredEventName;
    final layers = eventRegistry.lastTriggeredLayers;
    final success = eventRegistry.lastTriggerSuccess;
    final error = eventRegistry.lastTriggerError;
    final containerType = eventRegistry.lastContainerType;
    final containerName = eventRegistry.lastContainerName;

    final steps = <TraceStep>[];

    // Step 1: Stage received
    steps.add(TraceStep(
      label: 'Stage Received',
      value: stageName,
      status: TraceStepStatus.success,
    ));

    // Step 2: Event lookup
    if (eventName == '(no audio)') {
      steps.add(const TraceStep(
        label: 'Event Lookup',
        value: 'No mapping found',
        status: TraceStepStatus.warning,
        detail: 'Create an event with this stage to hear audio',
      ));
      _noAudioCount++;
    } else {
      steps.add(TraceStep(
        label: 'Event Lookup',
        value: eventName,
        status: TraceStepStatus.success,
      ));
    }

    // Step 3: Container check
    if (containerType != ContainerType.none && containerName != null) {
      steps.add(TraceStep(
        label: 'Container',
        value: '${_containerTypeLabel(containerType)}: $containerName',
        status: TraceStepStatus.success,
      ));
    }

    // Step 4: Layers
    if (layers.isNotEmpty) {
      steps.add(TraceStep(
        label: 'Audio Layers',
        value: '${layers.length} layer(s)',
        status: TraceStepStatus.success,
        detail: layers.join('\n'),
      ));
    } else if (eventName != '(no audio)') {
      steps.add(const TraceStep(
        label: 'Audio Layers',
        value: 'No layers',
        status: TraceStepStatus.warning,
        detail: 'Event has no audio layers configured',
      ));
    }

    // Step 5: Playback result
    if (success && layers.isNotEmpty) {
      // Parse voice/bus info from error field (which contains debug info on success)
      steps.add(TraceStep(
        label: 'Playback',
        value: 'Success',
        status: TraceStepStatus.success,
        detail: error.isNotEmpty ? error : null,
      ));
      _successCount++;
    } else if (eventName == '(no audio)') {
      steps.add(const TraceStep(
        label: 'Playback',
        value: 'Skipped',
        status: TraceStepStatus.skipped,
        detail: 'No audio event mapped to this stage',
      ));
    } else {
      steps.add(TraceStep(
        label: 'Playback',
        value: 'Failed',
        status: TraceStepStatus.error,
        detail: error.isNotEmpty ? error : 'Unknown error',
      ));
      _errorCount++;
    }

    _totalEvents++;

    final trace = EventTrace(
      timestamp: DateTime.now(),
      stageName: stageName,
      steps: steps,
      success: success && layers.isNotEmpty,
    );

    setState(() {
      _traces.add(trace);
      // Keep max 200 traces
      if (_traces.length > 200) {
        _traces.removeAt(0);
      }
    });

    // Auto-scroll to bottom
    if (_autoScroll && _traceScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _traceScrollController.animateTo(
          _traceScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      });
    }
  }

  String _containerTypeLabel(ContainerType type) {
    switch (type) {
      case ContainerType.blend:
        return 'Blend';
      case ContainerType.random:
        return 'Random';
      case ContainerType.sequence:
        return 'Sequence';
      case ContainerType.none:
        return '';
    }
  }

  void _clearTraces() {
    setState(() {
      _traces.clear();
      _totalEvents = 0;
      _successCount = 0;
      _errorCount = 0;
      _noAudioCount = 0;
    });
  }

  void _copyTracesToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('=== FluxForge Event Trace Export ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('Total: $_totalEvents | Success: $_successCount | Errors: $_errorCount | No Audio: $_noAudioCount');
    buffer.writeln('');

    for (final trace in _traces) {
      buffer.writeln('--- ${trace.timestamp.toIso8601String()} ---');
      buffer.writeln('Stage: ${trace.stageName}');
      for (final step in trace.steps) {
        final statusIcon = switch (step.status) {
          TraceStepStatus.success => '✓',
          TraceStepStatus.warning => '⚠',
          TraceStepStatus.error => '✗',
          TraceStepStatus.skipped => '○',
        };
        buffer.writeln('  $statusIcon ${step.label}: ${step.value ?? '-'}');
        if (step.detail != null) {
          buffer.writeln('    └─ ${step.detail}');
        }
      }
      buffer.writeln('');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trace log copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header with stats
          _buildHeader(),
          // Tab bar
          _buildTabBar(),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTraceTab(),
                _buildMappingsTab(),
                _buildStatsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgMid)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          const Text(
            'EVENT DEBUGGER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 16),
          // Stats badges
          _buildStatBadge('Total', _totalEvents, Colors.white70),
          const SizedBox(width: 8),
          _buildStatBadge('OK', _successCount, Colors.green),
          const SizedBox(width: 8),
          _buildStatBadge('Err', _errorCount, Colors.red),
          const SizedBox(width: 8),
          _buildStatBadge('No Audio', _noAudioCount, Colors.orange),
          const Spacer(),
          // Controls
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              size: 16,
              color: _isPaused ? Colors.amber : Colors.white54,
            ),
            onPressed: () => setState(() => _isPaused = !_isPaused),
            tooltip: _isPaused ? 'Resume' : 'Pause',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
              size: 16,
              color: _autoScroll ? FluxForgeTheme.accentBlue : Colors.white54,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
            onPressed: _copyTracesToClipboard,
            tooltip: 'Copy to clipboard',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white54),
            onPressed: _clearTraces,
            tooltip: 'Clear',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 4),
          Text(
            value.toString(),
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 32,
      color: FluxForgeTheme.bgDeep,
      child: TabBar(
        controller: _tabController,
        labelColor: FluxForgeTheme.accentBlue,
        unselectedLabelColor: Colors.white54,
        indicatorColor: FluxForgeTheme.accentBlue,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'TRACE'),
          Tab(text: 'MAPPINGS'),
          Tab(text: 'STATS'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTraceTab() {
    if (_traces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline, size: 48, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              'No events traced yet',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 4),
            Text(
              'Trigger a stage event to see the resolution trace',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _traceScrollController,
      itemCount: _traces.length,
      itemBuilder: (context, index) => _buildTraceCard(_traces[index]),
    );
  }

  Widget _buildTraceCard(EventTrace trace) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: trace.success
              ? Colors.green.withValues(alpha: 0.3)
              : trace.steps.any((s) => s.status == TraceStepStatus.error)
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              children: [
                Icon(
                  trace.success ? Icons.check_circle : Icons.warning,
                  size: 14,
                  color: trace.success ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  trace.stageName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(trace.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Steps
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                for (var i = 0; i < trace.steps.length; i++) ...[
                  _buildTraceStep(trace.steps[i], i == trace.steps.length - 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraceStep(TraceStep step, bool isLast) {
    final statusColor = switch (step.status) {
      TraceStepStatus.success => Colors.green,
      TraceStepStatus.warning => Colors.orange,
      TraceStepStatus.error => Colors.red,
      TraceStepStatus.skipped => Colors.grey,
    };

    final statusIcon = switch (step.status) {
      TraceStepStatus.success => Icons.check_circle,
      TraceStepStatus.warning => Icons.warning,
      TraceStepStatus.error => Icons.error,
      TraceStepStatus.skipped => Icons.remove_circle_outline,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connector line
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              if (!isLast)
                Container(
                  width: 1,
                  height: step.detail != null ? 40 : 20,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (step.value != null)
                    Expanded(
                      child: Text(
                        step.value!,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              if (step.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      step.detail!,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              SizedBox(height: isLast ? 0 : 8),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAPPINGS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMappingsTab() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                const SizedBox(height: 12),
                Text(
                  'No event mappings',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create composite events to map stages to audio',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                ),
              ],
            ),
          );
        }

        // Group events by their trigger stages
        final stageToEvents = <String, List<SlotCompositeEvent>>{};
        final unmappedEvents = <SlotCompositeEvent>[];

        for (final event in events) {
          if (event.triggerStages.isEmpty) {
            unmappedEvents.add(event);
          } else {
            for (final stage in event.triggerStages) {
              stageToEvents.putIfAbsent(stage, () => []).add(event);
            }
          }
        }

        final sortedStages = stageToEvents.keys.toList()..sort();

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            // Mapped stages
            for (final stage in sortedStages)
              _buildMappingCard(stage, stageToEvents[stage]!),
            // Unmapped events
            if (unmappedEvents.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning, size: 14, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          'Unmapped Events (${unmappedEvents.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: unmappedEvents.map((e) => Chip(
                        label: Text(e.name, style: const TextStyle(fontSize: 10)),
                        backgroundColor: Colors.orange.withValues(alpha: 0.2),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMappingCard(String stage, List<SlotCompositeEvent> events) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Stage name
          Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stage,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentBlue,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
          const SizedBox(width: 12),
          // Event(s)
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: events.map((e) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: e.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: e.color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: e.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.name,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${e.layers.length}L)',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsTab() {
    final successRate = _totalEvents > 0
        ? (_successCount / _totalEvents * 100).toStringAsFixed(1)
        : '0.0';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(child: _buildStatCard('Total Events', _totalEvents.toString(), Icons.timeline, Colors.white70)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Success', _successCount.toString(), Icons.check_circle, Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Errors', _errorCount.toString(), Icons.error, Colors.red)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('No Audio', _noAudioCount.toString(), Icons.volume_off, Colors.orange)),
            ],
          ),
          const SizedBox(height: 24),
          // Success rate meter
          Text(
            'Success Rate',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _totalEvents > 0 ? _successCount / _totalEvents : 0,
                    backgroundColor: Colors.red.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation(Colors.green),
                    minHeight: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$successRate%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Event registry info
          Text(
            'Event Registry',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Registered Events', '${eventRegistry.allEvents.length}'),
                _buildInfoRow('Trigger Count', '$_lastTriggerCount'),
                _buildInfoRow('Last Stage', eventRegistry.lastTriggeredStage),
                _buildInfoRow('Last Event', eventRegistry.lastTriggeredEventName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
