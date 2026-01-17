// Event Profiler Panel
//
// Real-time visualization of audio events:
// - Event timeline
// - Latency histogram
// - Voice usage meter
// - Memory usage
// - Statistics

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/advanced_middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

class EventProfilerPanel extends StatefulWidget {
  const EventProfilerPanel({super.key});

  @override
  State<EventProfilerPanel> createState() => _EventProfilerPanelState();
}

class _EventProfilerPanelState extends State<EventProfilerPanel> {
  final EventProfiler _profiler = EventProfiler(maxEvents: 5000);
  final VoicePool _voicePool = VoicePool();
  final MemoryBudgetManager _memoryManager = MemoryBudgetManager();

  Timer? _updateTimer;
  bool _isRecording = true;
  bool _autoScroll = true;
  ProfilerEventType? _filterType;

  @override
  void initState() {
    super.initState();
    _startUpdateTimer();
    _initDemoData();
  }

  void _initDemoData() {
    // Register demo soundbanks
    _memoryManager.registerBank(SoundBank(
      bankId: 'base_sfx',
      name: 'Base SFX',
      estimatedSizeBytes: 8 * 1024 * 1024,
      priority: LoadPriority.critical,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'music',
      name: 'Music',
      estimatedSizeBytes: 24 * 1024 * 1024,
      priority: LoadPriority.high,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'voice',
      name: 'Voice',
      estimatedSizeBytes: 12 * 1024 * 1024,
      priority: LoadPriority.normal,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'bigwins',
      name: 'Big Wins',
      estimatedSizeBytes: 16 * 1024 * 1024,
      priority: LoadPriority.streaming,
    ));

    // Load some banks
    _memoryManager.loadBank('base_sfx');
    _memoryManager.loadBank('music');
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isRecording) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _simulateEvent(ProfilerEventType type) {
    final now = DateTime.now();
    String description;
    int? soundId;
    int? voiceId;
    double? value;

    switch (type) {
      case ProfilerEventType.eventPost:
        description = 'Post: Play_SpinStart';
        soundId = 1000;
        break;
      case ProfilerEventType.eventTrigger:
        description = 'Trigger: sfx_reel_stop';
        soundId = 1020;
        break;
      case ProfilerEventType.voiceStart:
        voiceId = _voicePool.requestVoice(soundId: 1000, busId: 2, priority: 50);
        description = 'Voice started: $voiceId';
        break;
      case ProfilerEventType.voiceStop:
        final firstVoice = _voicePool.firstActiveVoiceId;
        if (firstVoice != null) {
          voiceId = firstVoice;
          _voicePool.releaseVoice(voiceId);
          description = 'Voice stopped: $voiceId';
        } else {
          description = 'Voice stopped (none active)';
        }
        break;
      case ProfilerEventType.voiceSteal:
        description = 'Voice stolen: priority overflow';
        break;
      case ProfilerEventType.bankLoad:
        description = 'Bank loaded: voice';
        _memoryManager.loadBank('voice');
        break;
      case ProfilerEventType.bankUnload:
        description = 'Bank unloaded: voice';
        _memoryManager.unloadBank('voice');
        break;
      case ProfilerEventType.rtpcChange:
        description = 'RTPC: Tension = 0.75';
        value = 0.75;
        break;
      case ProfilerEventType.stateChange:
        description = 'State: GameState -> BigWin';
        break;
      case ProfilerEventType.error:
        description = 'Error: Sound not found';
        break;
    }

    _profiler.record(
      type: type,
      description: description,
      soundId: soundId,
      voiceId: voiceId,
      value: value,
      latencyUs: (50 + DateTime.now().millisecond % 200).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _profiler.getStats();
    final voiceStats = _voicePool.getStats();
    final memoryStats = _memoryManager.getStats();

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header
          _buildHeader(stats),

          // Stats row
          _buildStatsRow(stats, voiceStats, memoryStats),

          // Meters row
          _buildMetersRow(voiceStats, memoryStats),

          // Event list
          Expanded(
            child: _buildEventList(),
          ),

          // Controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader(ProfilerStats stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics,
            color: FluxForgeTheme.accentBlue,
            size: 16,
          ),
          const SizedBox(width: 8),
          const Text(
            'EVENT PROFILER',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Recording indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isRecording
                  ? FluxForgeTheme.accentRed.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _isRecording ? 'REC' : 'PAUSED',
                  style: TextStyle(
                    color: _isRecording
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Events per second
          Text(
            '${stats.eventsPerSecond} evt/s',
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    ProfilerStats stats,
    VoicePoolStats voiceStats,
    MemoryStats memoryStats,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _buildStatCard(
            'EVENTS',
            '${stats.totalEvents}',
            FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            'AVG LAT',
            '${stats.avgLatencyMs.toStringAsFixed(2)}ms',
            stats.avgLatencyMs < 1
                ? FluxForgeTheme.accentGreen
                : stats.avgLatencyMs < 5
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.accentRed,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            'PEAK LAT',
            '${stats.maxLatencyMs.toStringAsFixed(2)}ms',
            stats.maxLatencyMs < 5
                ? FluxForgeTheme.accentGreen
                : stats.maxLatencyMs < 10
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.accentRed,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            'VOICES',
            '${voiceStats.activeVoices}/${voiceStats.maxVoices}',
            voiceStats.utilizationPercent < 70
                ? FluxForgeTheme.accentGreen
                : voiceStats.utilizationPercent < 90
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.accentRed,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            'STEALS',
            '${stats.voiceSteals}',
            stats.voiceSteals == 0
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.accentOrange,
          ),
          const SizedBox(width: 8),
          _buildStatCard(
            'ERRORS',
            '${stats.errors}',
            stats.errors == 0
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.accentRed,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetersRow(VoicePoolStats voiceStats, MemoryStats memoryStats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Voice meter
          Expanded(
            child: _buildMeter(
              'VOICE POOL',
              voiceStats.utilizationPercent / 100,
              '${voiceStats.activeVoices}/${voiceStats.maxVoices}',
            ),
          ),
          const SizedBox(width: 8),
          // Memory meter
          Expanded(
            child: _buildMeter(
              'MEMORY',
              memoryStats.residentPercent,
              '${memoryStats.residentMb.toStringAsFixed(1)}MB',
              state: memoryStats.state,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeter(
    String label,
    double value,
    String text, {
    MemoryState state = MemoryState.normal,
  }) {
    Color color;
    if (state == MemoryState.critical || value > 0.9) {
      color = FluxForgeTheme.accentRed;
    } else if (state == MemoryState.warning || value > 0.75) {
      color = FluxForgeTheme.accentOrange;
    } else {
      color = FluxForgeTheme.accentGreen;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: FluxForgeTheme.bgDeep,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    final events = _filterType != null
        ? _profiler.getEventsByType(_filterType!)
        : _profiler.getRecentEvents(count: 500);

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Filter tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('ALL', null),
                  _buildFilterChip('EVENTS', ProfilerEventType.eventPost),
                  _buildFilterChip('VOICES', ProfilerEventType.voiceStart),
                  _buildFilterChip('RTPC', ProfilerEventType.rtpcChange),
                  _buildFilterChip('BANKS', ProfilerEventType.bankLoad),
                  _buildFilterChip('ERRORS', ProfilerEventType.error),
                ],
              ),
            ),
          ),

          // Event list
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text(
                      'No events recorded',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[events.length - 1 - index];
                      return _buildEventItem(event);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, ProfilerEventType? type) {
    final isSelected = _filterType == type;
    return GestureDetector(
      onTap: () => setState(() => _filterType = type),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEventItem(ProfilerEvent event) {
    final color = _getEventColor(event.type);
    final time = '${event.timestamp.hour.toString().padLeft(2, '0')}:'
        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
        '${event.timestamp.second.toString().padLeft(2, '0')}.'
        '${(event.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Timestamp
          SizedBox(
            width: 70,
            child: Text(
              time,
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Type indicator
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),

          // Description
          Expanded(
            child: Text(
              event.description,
              style: const TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Latency
          if (event.latencyUs > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: event.latencyUs < 1000
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                    : event.latencyUs < 5000
                        ? FluxForgeTheme.accentOrange.withValues(alpha: 0.2)
                        : FluxForgeTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '${(event.latencyUs / 1000).toStringAsFixed(2)}ms',
                style: TextStyle(
                  color: event.latencyUs < 1000
                      ? FluxForgeTheme.accentGreen
                      : event.latencyUs < 5000
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.accentRed,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getEventColor(ProfilerEventType type) {
    switch (type) {
      case ProfilerEventType.eventPost:
        return FluxForgeTheme.accentBlue;
      case ProfilerEventType.eventTrigger:
        return FluxForgeTheme.accentCyan;
      case ProfilerEventType.voiceStart:
        return FluxForgeTheme.accentGreen;
      case ProfilerEventType.voiceStop:
        return FluxForgeTheme.accentOrange;
      case ProfilerEventType.voiceSteal:
        return FluxForgeTheme.accentRed;
      case ProfilerEventType.bankLoad:
        return FluxForgeTheme.accentPurple;
      case ProfilerEventType.bankUnload:
        return FluxForgeTheme.accentPurple.withValues(alpha: 0.6);
      case ProfilerEventType.rtpcChange:
        return FluxForgeTheme.accentYellow;
      case ProfilerEventType.stateChange:
        return FluxForgeTheme.accentPink;
      case ProfilerEventType.error:
        return FluxForgeTheme.accentRed;
    }
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Record toggle
          _buildControlButton(
            icon: _isRecording ? Icons.pause : Icons.fiber_manual_record,
            label: _isRecording ? 'Pause' : 'Record',
            color: _isRecording ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentRed,
            onTap: () => setState(() => _isRecording = !_isRecording),
          ),
          const SizedBox(width: 8),

          // Clear
          _buildControlButton(
            icon: Icons.delete_outline,
            label: 'Clear',
            onTap: () => setState(() => _profiler.clear()),
          ),
          const SizedBox(width: 8),

          // Auto scroll toggle
          _buildControlButton(
            icon: Icons.vertical_align_bottom,
            label: 'Auto',
            color: _autoScroll ? FluxForgeTheme.accentGreen : null,
            onTap: () => setState(() => _autoScroll = !_autoScroll),
          ),

          const Spacer(),

          // Simulate events (for testing)
          Text(
            'TEST:',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 4),
          _buildSmallButton('Event', () => _simulateEvent(ProfilerEventType.eventPost)),
          _buildSmallButton('Voice+', () => _simulateEvent(ProfilerEventType.voiceStart)),
          _buildSmallButton('Voice-', () => _simulateEvent(ProfilerEventType.voiceStop)),
          _buildSmallButton('RTPC', () => _simulateEvent(ProfilerEventType.rtpcChange)),
          _buildSmallButton('Bank', () => _simulateEvent(ProfilerEventType.bankLoad)),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? FluxForgeTheme.textSecondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: (color ?? FluxForgeTheme.textSecondary).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: color ?? FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? FluxForgeTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
