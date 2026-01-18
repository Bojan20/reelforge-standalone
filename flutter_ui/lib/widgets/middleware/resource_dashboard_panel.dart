// Resource Dashboard Panel
//
// Comprehensive monitoring for:
// - Voice pool usage (48 voices)
// - Memory budget (per soundbank)
// - CPU usage estimation
// - DSP load
// - Streaming buffers
// - Alert system

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/advanced_middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

class ResourceDashboardPanel extends StatefulWidget {
  const ResourceDashboardPanel({super.key});

  @override
  State<ResourceDashboardPanel> createState() => _ResourceDashboardPanelState();
}

class _ResourceDashboardPanelState extends State<ResourceDashboardPanel> {
  // Voice pool
  final VoicePool _voicePool = VoicePool();

  // Memory manager
  final MemoryBudgetManager _memoryManager = MemoryBudgetManager();

  // Simulated metrics
  double _cpuUsage = 0.0;
  double _dspLoad = 0.0;
  double _streamingBufferUsage = 0.0;
  int _activeStreams = 0;
  int _maxStreams = 8;

  // History for graphs
  final List<double> _cpuHistory = List.filled(60, 0.0);
  final List<double> _voiceHistory = List.filled(60, 0.0);
  final List<double> _memoryHistory = List.filled(60, 0.0);

  // Alerts
  final List<_ResourceAlert> _alerts = [];

  Timer? _updateTimer;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initDemoData();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _initDemoData() {
    // Register soundbanks
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
      name: 'Voice/VO',
      estimatedSizeBytes: 12 * 1024 * 1024,
      priority: LoadPriority.normal,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'bigwins',
      name: 'Big Win Sounds',
      estimatedSizeBytes: 16 * 1024 * 1024,
      priority: LoadPriority.streaming,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'ambience',
      name: 'Ambience',
      estimatedSizeBytes: 6 * 1024 * 1024,
      priority: LoadPriority.normal,
    ));
    _memoryManager.registerBank(SoundBank(
      bankId: 'ui_sounds',
      name: 'UI Sounds',
      estimatedSizeBytes: 2 * 1024 * 1024,
      priority: LoadPriority.critical,
    ));

    // Load critical banks
    _memoryManager.loadBank('base_sfx');
    _memoryManager.loadBank('ui_sounds');
    _memoryManager.loadBank('music');

    // Simulate some active voices
    _voicePool.requestVoice(soundId: 1, busId: 0, priority: 100);
    _voicePool.requestVoice(soundId: 2, busId: 1, priority: 80);
    _voicePool.requestVoice(soundId: 3, busId: 1, priority: 60);
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        _updateSimulatedMetrics();
        setState(() {});
      }
    });
  }

  void _updateSimulatedMetrics() {
    // Simulate CPU usage (random walk)
    _cpuUsage += (_rng.nextDouble() - 0.5) * 5;
    _cpuUsage = _cpuUsage.clamp(5.0, 35.0);

    // DSP load based on voice count
    final voiceStats = _voicePool.getStats();
    _dspLoad = (voiceStats.activeVoices / voiceStats.maxVoices) * 100 * 0.8;
    _dspLoad += (_rng.nextDouble() - 0.5) * 5;
    _dspLoad = _dspLoad.clamp(0.0, 100.0);

    // Streaming buffer
    _activeStreams = _rng.nextInt(4) + 1;
    _streamingBufferUsage = (_activeStreams / _maxStreams) * 100;

    // Update history
    _cpuHistory.removeAt(0);
    _cpuHistory.add(_cpuUsage);

    _voiceHistory.removeAt(0);
    _voiceHistory.add(voiceStats.utilizationPercent);

    final memStats = _memoryManager.getStats();
    _memoryHistory.removeAt(0);
    _memoryHistory.add(memStats.residentPercent * 100);

    // Check for alerts
    _checkAlerts(voiceStats, memStats);
  }

  void _checkAlerts(VoicePoolStats voiceStats, MemoryStats memStats) {
    final now = DateTime.now();
    final memPercent = memStats.residentPercent * 100;

    // Voice pool warning
    if (voiceStats.utilizationPercent > 80 &&
        !_alerts.any((a) => a.type == _AlertType.voiceHigh && now.difference(a.time).inSeconds < 30)) {
      _alerts.add(_ResourceAlert(
        type: _AlertType.voiceHigh,
        message: 'Voice pool at ${voiceStats.utilizationPercent.toStringAsFixed(0)}%',
        time: now,
        severity: voiceStats.utilizationPercent > 95 ? _AlertSeverity.critical : _AlertSeverity.warning,
      ));
    }

    // Memory warning
    if (memPercent > 80 &&
        !_alerts.any((a) => a.type == _AlertType.memoryHigh && now.difference(a.time).inSeconds < 30)) {
      _alerts.add(_ResourceAlert(
        type: _AlertType.memoryHigh,
        message: 'Memory at ${memPercent.toStringAsFixed(0)}%',
        time: now,
        severity: memPercent > 95 ? _AlertSeverity.critical : _AlertSeverity.warning,
      ));
    }

    // Keep only last 10 alerts
    if (_alerts.length > 10) {
      _alerts.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voiceStats = _voicePool.getStats();
    final memoryStats = _memoryManager.getStats();

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Main content
          Expanded(
            child: Row(
              children: [
                // Left: Voice pool & CPU
                Expanded(
                  flex: 2,
                  child: _buildLeftColumn(voiceStats),
                ),

                // Divider
                Container(width: 1, color: FluxForgeTheme.borderSubtle),

                // Center: Memory budget
                Expanded(
                  flex: 3,
                  child: _buildCenterColumn(memoryStats),
                ),

                // Divider
                Container(width: 1, color: FluxForgeTheme.borderSubtle),

                // Right: Alerts & streaming
                Expanded(
                  flex: 2,
                  child: _buildRightColumn(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dashboard, size: 14, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 8),
          const Text(
            'RESOURCE DASHBOARD',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Status indicator
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final voiceStats = _voicePool.getStats();
    final memStats = _memoryManager.getStats();
    final memPercent = memStats.residentPercent * 100;

    final isWarning = voiceStats.utilizationPercent >= 80 || memPercent >= 80;
    final isCritical = voiceStats.utilizationPercent >= 95 || memPercent >= 95;

    final Color color;
    final String label;
    if (isCritical) {
      color = FluxForgeTheme.accentRed;
      label = 'CRITICAL';
    } else if (isWarning) {
      color = FluxForgeTheme.accentOrange;
      label = 'WARNING';
    } else {
      color = FluxForgeTheme.accentGreen;
      label = 'HEALTHY';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn(VoicePoolStats voiceStats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Voice Pool Section
          _buildSectionHeader('VOICE POOL', Icons.graphic_eq),
          const SizedBox(height: 8),
          _buildVoicePoolMeter(voiceStats),
          const SizedBox(height: 12),
          _buildVoiceGraph(),

          const SizedBox(height: 20),

          // CPU/DSP Section
          _buildSectionHeader('PERFORMANCE', Icons.speed),
          const SizedBox(height: 8),
          _buildPerformanceMeters(),
          const SizedBox(height: 12),
          _buildCpuGraph(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 12, color: FluxForgeTheme.accentBlue),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildVoicePoolMeter(VoicePoolStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.activeVoices}',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '/ ${stats.maxVoices}',
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Meter bar
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  // Fill
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (stats.utilizationPercent / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            FluxForgeTheme.accentGreen,
                            stats.utilizationPercent > 70
                                ? FluxForgeTheme.accentOrange
                                : FluxForgeTheme.accentGreen,
                            stats.utilizationPercent > 90
                                ? FluxForgeTheme.accentRed
                                : (stats.utilizationPercent > 70
                                    ? FluxForgeTheme.accentOrange
                                    : FluxForgeTheme.accentGreen),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Voice slots
                  Row(
                    children: List.generate(
                      stats.maxVoices,
                      (i) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          color: i < stats.activeVoices
                              ? Colors.transparent
                              : FluxForgeTheme.bgMid.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.utilizationPercent.toStringAsFixed(0)}% used',
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
              Text(
                '${stats.stealCount} steals',
                style: TextStyle(
                  color: stats.stealCount > 0
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceGraph() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _HistoryGraphPainter(
          values: _voiceHistory,
          maxValue: 100,
          color: FluxForgeTheme.accentGreen,
          warningThreshold: 80,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildPerformanceMeters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildMeterRow('CPU', _cpuUsage, 100, FluxForgeTheme.accentBlue),
          const SizedBox(height: 8),
          _buildMeterRow('DSP', _dspLoad, 100, FluxForgeTheme.accentPurple),
        ],
      ),
    );
  }

  Widget _buildMeterRow(String label, double value, double max, Color color) {
    final percent = (value / max * 100).clamp(0.0, 100.0);
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${percent.toStringAsFixed(0)}%',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCpuGraph() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _HistoryGraphPainter(
          values: _cpuHistory,
          maxValue: 100,
          color: FluxForgeTheme.accentBlue,
          warningThreshold: 50,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildCenterColumn(MemoryStats memStats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('MEMORY BUDGET', Icons.memory),
          const SizedBox(height: 8),
          _buildMemoryOverview(memStats),
          const SizedBox(height: 12),
          _buildSoundbankList(),
          const SizedBox(height: 12),
          _buildMemoryGraph(),
        ],
      ),
    );
  }

  Widget _buildMemoryOverview(MemoryStats stats) {
    final percent = stats.residentPercent * 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // Circular progress
          SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: _CircularProgressPainter(
                value: stats.residentPercent,
                color: percent < 80
                    ? FluxForgeTheme.accentGreen
                    : percent < 95
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.accentRed,
              ),
              child: Center(
                child: Text(
                  '${percent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMemoryStat('Used', _formatBytes(stats.residentBytes)),
                _buildMemoryStat('Budget', _formatBytes(stats.residentMaxBytes)),
                _buildMemoryStat('Loaded', '${stats.loadedBankCount}/${stats.totalBankCount} banks'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Widget _buildSoundbankList() {
    final banks = _memoryManager.allBanks;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'SOUNDBANK',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'SIZE',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 50,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          // Banks
          ...banks.map((bank) => _buildBankRow(bank)),
        ],
      ),
    );
  }

  Widget _buildBankRow(SoundBank bank) {
    final isLoaded = _memoryManager.isBankLoaded(bank.bankId);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isLoaded) {
            _memoryManager.unloadBank(bank.bankId);
          } else {
            _memoryManager.loadBank(bank.bankId);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Priority indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getPriorityColor(bank.priority),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              flex: 3,
              child: Text(
                bank.name,
                style: TextStyle(
                  color: isLoaded
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Size
            Expanded(
              flex: 1,
              child: Text(
                _formatBytes(bank.estimatedSizeBytes),
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            // Status badge
            SizedBox(
              width: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isLoaded
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  isLoaded ? 'LOADED' : 'UNLOAD',
                  style: TextStyle(
                    color: isLoaded
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textSecondary,
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(LoadPriority priority) {
    switch (priority) {
      case LoadPriority.critical:
        return FluxForgeTheme.accentRed;
      case LoadPriority.high:
        return FluxForgeTheme.accentOrange;
      case LoadPriority.normal:
        return FluxForgeTheme.accentGreen;
      case LoadPriority.streaming:
        return FluxForgeTheme.accentPurple;
    }
  }

  Widget _buildMemoryGraph() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _HistoryGraphPainter(
          values: _memoryHistory,
          maxValue: 100,
          color: FluxForgeTheme.accentCyan,
          warningThreshold: 80,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildRightColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('STREAMING', Icons.stream),
          const SizedBox(height: 8),
          _buildStreamingStats(),

          const SizedBox(height: 20),

          _buildSectionHeader('ALERTS', Icons.warning_amber),
          const SizedBox(height: 8),
          _buildAlertsList(),
        ],
      ),
    );
  }

  Widget _buildStreamingStats() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Streams',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
              Text(
                '$_activeStreams / $_maxStreams',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stream slots visualization
          Row(
            children: List.generate(
              _maxStreams,
              (i) => Expanded(
                child: Container(
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: i < _activeStreams
                        ? FluxForgeTheme.accentPurple.withValues(alpha: 0.7)
                        : FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: i < _activeStreams
                          ? FluxForgeTheme.accentPurple
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildMeterRow('Buffer', _streamingBufferUsage, 100, FluxForgeTheme.accentPurple),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    if (_alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: const Center(
          child: Text(
            'No alerts',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: _alerts.reversed.take(5).map((alert) => _buildAlertRow(alert)).toList(),
      ),
    );
  }

  Widget _buildAlertRow(_ResourceAlert alert) {
    final color = alert.severity == _AlertSeverity.critical
        ? FluxForgeTheme.accentRed
        : FluxForgeTheme.accentOrange;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            alert.severity == _AlertSeverity.critical
                ? Icons.error
                : Icons.warning,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.message,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatTime(alert.time),
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

// Alert types and models
enum _AlertType { voiceHigh, memoryHigh, cpuHigh, streamingError }

enum _AlertSeverity { warning, critical }

class _ResourceAlert {
  final _AlertType type;
  final String message;
  final DateTime time;
  final _AlertSeverity severity;

  _ResourceAlert({
    required this.type,
    required this.message,
    required this.time,
    required this.severity,
  });
}

// Custom painters
class _HistoryGraphPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color color;
  final double warningThreshold;

  _HistoryGraphPainter({
    required this.values,
    required this.maxValue,
    required this.color,
    required this.warningThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Warning zone
    if (warningThreshold < maxValue) {
      final warningY = size.height * (1 - warningThreshold / maxValue);
      final warningPaint = Paint()
        ..color = FluxForgeTheme.accentOrange.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, warningY),
        warningPaint,
      );
    }

    // Fill
    final fillPath = Path();
    fillPath.moveTo(0, size.height);

    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - values[i] / maxValue);
      fillPath.lineTo(x, y.clamp(0, size.height));
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - values[i] / maxValue);

      if (i == 0) {
        linePath.moveTo(x, y.clamp(0, size.height));
      } else {
        linePath.lineTo(x, y.clamp(0, size.height));
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _HistoryGraphPainter oldDelegate) => true;
}

class _CircularProgressPainter extends CustomPainter {
  final double value;
  final Color color;

  _CircularProgressPainter({
    required this.value,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // Background circle
    final bgPaint = Paint()
      ..color = FluxForgeTheme.bgDeep
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      value.clamp(0.0, 1.0) * 2 * math.pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}
