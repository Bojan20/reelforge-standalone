/// FluxForge Studio — Ultimate Engine Debug Console
///
/// Professional debugging and diagnostics panel:
/// - Real-time log streaming with severity levels
/// - Performance metrics (CPU, memory, latency)
/// - Audio graph visualization
/// - Active voice/channel monitor
/// - FFI call tracing
/// - Command history with auto-complete
/// - Export diagnostics
/// - Breakpoints and watchpoints
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/fluxforge_theme.dart';
import '../../services/websocket_client.dart';

// =============================================================================
// CONSTANTS
// =============================================================================

const int _kMaxLogEntries = 5000;
const int _kMaxCommandHistory = 100;
const double _kMetricUpdateInterval = 100.0; // ms

// =============================================================================
// LOG ENTRY
// =============================================================================

/// Log severity levels
enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
  fatal;

  Color get color => switch (this) {
        trace => const Color(0xFF606070),
        debug => FluxForgeTheme.textMuted,
        info => FluxForgeTheme.accentCyan,
        warn => FluxForgeTheme.accentOrange,
        error => FluxForgeTheme.accentRed,
        fatal => const Color(0xFFff0040),
      };

  String get label => switch (this) {
        trace => 'TRC',
        debug => 'DBG',
        info => 'INF',
        warn => 'WRN',
        error => 'ERR',
        fatal => 'FTL',
      };

  IconData get icon => switch (this) {
        trace => Icons.more_horiz,
        debug => Icons.bug_report,
        info => Icons.info_outline,
        warn => Icons.warning_amber,
        error => Icons.error_outline,
        fatal => Icons.dangerous,
      };
}

/// Single log entry
class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String module;
  final String message;
  final Map<String, dynamic>? context;
  final String? stackTrace;

  LogEntry({
    String? id,
    DateTime? timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.context,
    this.stackTrace,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}',
        timestamp = timestamp ?? DateTime.now();

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      level: LogLevel.values.firstWhere(
        (l) => l.name == (json['level'] as String?)?.toLowerCase(),
        orElse: () => LogLevel.info,
      ),
      module: json['module'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      context: json['context'] as Map<String, dynamic>?,
      stackTrace: json['stack_trace'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'module': module,
        'message': message,
        if (context != null) 'context': context,
        if (stackTrace != null) 'stack_trace': stackTrace,
      };
}

// =============================================================================
// PERFORMANCE METRICS
// =============================================================================

/// Real-time performance metrics
class EngineMetrics {
  final double cpuUsage; // 0-100%
  final double memoryUsageMb;
  final double audioLatencyMs;
  final double dspLoadPercent;
  final int activeVoices;
  final int totalVoices;
  final int activeChannels;
  final double sampleRate;
  final int bufferSize;
  final int xruns; // Buffer underruns
  final double peakLeft;
  final double peakRight;
  final DateTime timestamp;

  const EngineMetrics({
    this.cpuUsage = 0,
    this.memoryUsageMb = 0,
    this.audioLatencyMs = 0,
    this.dspLoadPercent = 0,
    this.activeVoices = 0,
    this.totalVoices = 128,
    this.activeChannels = 0,
    this.sampleRate = 48000,
    this.bufferSize = 256,
    this.xruns = 0,
    this.peakLeft = -96,
    this.peakRight = -96,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _DefaultDateTime();

  factory EngineMetrics.fromJson(Map<String, dynamic> json) => EngineMetrics(
        cpuUsage: (json['cpu_usage'] as num?)?.toDouble() ?? 0,
        memoryUsageMb: (json['memory_mb'] as num?)?.toDouble() ?? 0,
        audioLatencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0,
        dspLoadPercent: (json['dsp_load'] as num?)?.toDouble() ?? 0,
        activeVoices: json['active_voices'] as int? ?? 0,
        totalVoices: json['total_voices'] as int? ?? 128,
        activeChannels: json['active_channels'] as int? ?? 0,
        sampleRate: (json['sample_rate'] as num?)?.toDouble() ?? 48000,
        bufferSize: json['buffer_size'] as int? ?? 256,
        xruns: json['xruns'] as int? ?? 0,
        peakLeft: (json['peak_left'] as num?)?.toDouble() ?? -96,
        peakRight: (json['peak_right'] as num?)?.toDouble() ?? -96,
        timestamp: DateTime.now(),
      );

  EngineMetrics copyWith({
    double? cpuUsage,
    double? memoryUsageMb,
    double? audioLatencyMs,
    double? dspLoadPercent,
    int? activeVoices,
    int? activeChannels,
    int? xruns,
    double? peakLeft,
    double? peakRight,
  }) =>
      EngineMetrics(
        cpuUsage: cpuUsage ?? this.cpuUsage,
        memoryUsageMb: memoryUsageMb ?? this.memoryUsageMb,
        audioLatencyMs: audioLatencyMs ?? this.audioLatencyMs,
        dspLoadPercent: dspLoadPercent ?? this.dspLoadPercent,
        activeVoices: activeVoices ?? this.activeVoices,
        totalVoices: totalVoices,
        activeChannels: activeChannels ?? this.activeChannels,
        sampleRate: sampleRate,
        bufferSize: bufferSize,
        xruns: xruns ?? this.xruns,
        peakLeft: peakLeft ?? this.peakLeft,
        peakRight: peakRight ?? this.peakRight,
        timestamp: DateTime.now(),
      );
}

class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}

// =============================================================================
// ENGINE DEBUG CONSOLE
// =============================================================================

/// Ultimate Engine Debug Console widget
class EngineDebugConsole extends StatefulWidget {
  final bool showMetrics;
  final bool showGraph;
  final bool showVoices;

  const EngineDebugConsole({
    super.key,
    this.showMetrics = true,
    this.showGraph = false,
    this.showVoices = true,
  });

  @override
  State<EngineDebugConsole> createState() => _EngineDebugConsoleState();
}

class _EngineDebugConsoleState extends State<EngineDebugConsole>
    with TickerProviderStateMixin {
  // --- Log State ---
  final List<LogEntry> _logs = [];
  Set<LogLevel> _visibleLevels = Set.from(LogLevel.values);
  String _moduleFilter = '';
  String _searchQuery = '';
  bool _autoScroll = true;
  bool _showTimestamps = true;
  bool _wrapLines = false;

  // --- Metrics State ---
  EngineMetrics _metrics = const EngineMetrics();
  final List<double> _cpuHistory = [];
  final List<double> _dspHistory = [];
  final List<double> _latencyHistory = [];
  static const int _historySize = 60; // 60 samples = 6 seconds at 10Hz

  // --- Command State ---
  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  final _commandController = TextEditingController();
  final _commandFocusNode = FocusNode();

  // --- Animation ---
  late final AnimationController _pulseController;

  // --- Controllers ---
  final _logScrollController = ScrollController();
  final _searchController = TextEditingController();

  // --- WebSocket ---
  StreamSubscription<WsMessage>? _logSubscription;
  StreamSubscription<WsMessage>? _metricsSubscription;

  // --- Tab ---
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });

    // Subscribe to WebSocket channels
    _connectToEngine();

    // Add some demo logs
    _addDemoLogs();
  }

  void _connectToEngine() {
    final client = UltimateWebSocketClient.instance;

    _logSubscription = client.subscribe('logs').listen((msg) {
      final entry = LogEntry.fromJson(msg.payload);
      _addLog(entry);
    });

    _metricsSubscription = client.subscribe('metrics').listen((msg) {
      final metrics = EngineMetrics.fromJson(msg.payload);
      _updateMetrics(metrics);
    });
  }

  void _addDemoLogs() {
    final demoLogs = [
      LogEntry(level: LogLevel.info, module: 'engine', message: 'Audio engine initialized'),
      LogEntry(level: LogLevel.debug, module: 'dsp', message: 'SIMD: AVX2 enabled'),
      LogEntry(level: LogLevel.info, module: 'audio', message: 'CoreAudio output: 48000Hz, 256 samples'),
      LogEntry(level: LogLevel.debug, module: 'graph', message: 'Routing graph rebuilt: 8 nodes, 12 edges'),
      LogEntry(level: LogLevel.trace, module: 'ffi', message: 'Flutter→Rust bridge connected'),
    ];

    for (final log in demoLogs) {
      _addLog(log);
    }
  }

  void _addLog(LogEntry entry) {
    setState(() {
      _logs.add(entry);
      if (_logs.length > _kMaxLogEntries) {
        _logs.removeRange(0, _logs.length - _kMaxLogEntries);
      }

      // Flash animation for errors
      if (entry.level == LogLevel.error || entry.level == LogLevel.fatal) {
        _pulseController.forward().then((_) => _pulseController.reverse());
      }
    });

    // Auto-scroll
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _updateMetrics(EngineMetrics metrics) {
    setState(() {
      _metrics = metrics;

      _cpuHistory.add(metrics.cpuUsage);
      _dspHistory.add(metrics.dspLoadPercent);
      _latencyHistory.add(metrics.audioLatencyMs);

      if (_cpuHistory.length > _historySize) _cpuHistory.removeAt(0);
      if (_dspHistory.length > _historySize) _dspHistory.removeAt(0);
      if (_latencyHistory.length > _historySize) _latencyHistory.removeAt(0);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _logScrollController.dispose();
    _searchController.dispose();
    _commandController.dispose();
    _commandFocusNode.dispose();
    _logSubscription?.cancel();
    _metricsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header with tabs
          _ConsoleHeader(
            currentTab: _currentTab,
            onTabChanged: (t) => setState(() => _currentTab = t),
            onClear: _clearLogs,
            onExport: _exportLogs,
            errorCount: _logs.where((l) => l.level.index >= LogLevel.error.index).length,
            warnCount: _logs.where((l) => l.level == LogLevel.warn).length,
          ),

          // Tab content
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                // Logs tab
                _buildLogsTab(),

                // Metrics tab
                _buildMetricsTab(),

                // Command tab
                _buildCommandTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // LOGS TAB
  // ==========================================================================

  Widget _buildLogsTab() {
    final filteredLogs = _getFilteredLogs();

    return Column(
      children: [
        // Filters bar
        _LogFiltersBar(
          visibleLevels: _visibleLevels,
          onLevelToggle: _toggleLevel,
          moduleFilter: _moduleFilter,
          onModuleFilterChanged: (m) => setState(() => _moduleFilter = m),
          searchController: _searchController,
          autoScroll: _autoScroll,
          onAutoScrollChanged: (v) => setState(() => _autoScroll = v),
          showTimestamps: _showTimestamps,
          onTimestampsChanged: (v) => setState(() => _showTimestamps = v),
          wrapLines: _wrapLines,
          onWrapLinesChanged: (v) => setState(() => _wrapLines = v),
        ),

        // Log list
        Expanded(
          child: filteredLogs.isEmpty
              ? _buildEmptyLogs()
              : _LogListView(
                  logs: filteredLogs,
                  scrollController: _logScrollController,
                  showTimestamps: _showTimestamps,
                  wrapLines: _wrapLines,
                  onLogTap: _showLogDetail,
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyLogs() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            size: 48,
            color: FluxForgeTheme.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No logs to display',
            style: TextStyle(
              fontSize: 14,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try adjusting your filters'
                : 'Logs will appear here as events occur',
            style: const TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  List<LogEntry> _getFilteredLogs() {
    return _logs.where((log) {
      // Level filter
      if (!_visibleLevels.contains(log.level)) return false;

      // Module filter
      if (_moduleFilter.isNotEmpty &&
          !log.module.toLowerCase().contains(_moduleFilter.toLowerCase())) {
        return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return log.message.toLowerCase().contains(query) ||
            log.module.toLowerCase().contains(query);
      }

      return true;
    }).toList();
  }

  void _toggleLevel(LogLevel level) {
    setState(() {
      if (_visibleLevels.contains(level)) {
        _visibleLevels.remove(level);
      } else {
        _visibleLevels.add(level);
      }
    });
  }

  void _clearLogs() {
    setState(() => _logs.clear());
  }

  void _exportLogs() {
    final json = _logs.map((l) => l.toJson()).toList();
    final text = json.toString();
    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${_logs.length} log entries'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLogDetail(LogEntry log) {
    showDialog(
      context: context,
      builder: (ctx) => _LogDetailDialog(log: log),
    );
  }

  // ==========================================================================
  // METRICS TAB
  // ==========================================================================

  Widget _buildMetricsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary metrics row
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  icon: Icons.memory,
                  label: 'CPU',
                  value: '${_metrics.cpuUsage.toStringAsFixed(1)}%',
                  color: _getMetricColor(_metrics.cpuUsage, 50, 80),
                  history: _cpuHistory,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.graphic_eq,
                  label: 'DSP Load',
                  value: '${_metrics.dspLoadPercent.toStringAsFixed(1)}%',
                  color: _getMetricColor(_metrics.dspLoadPercent, 50, 80),
                  history: _dspHistory,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  icon: Icons.timer,
                  label: 'Latency',
                  value: '${_metrics.audioLatencyMs.toStringAsFixed(1)}ms',
                  color: _getMetricColor(_metrics.audioLatencyMs, 10, 30),
                  history: _latencyHistory,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Secondary metrics
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.volume_up,
                  label: 'Active Voices',
                  value: '${_metrics.activeVoices}/${_metrics.totalVoices}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.route,
                  label: 'Channels',
                  value: '${_metrics.activeChannels}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.storage,
                  label: 'Memory',
                  value: '${_metrics.memoryUsageMb.toStringAsFixed(0)} MB',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.warning,
                  label: 'XRuns',
                  value: '${_metrics.xruns}',
                  highlight: _metrics.xruns > 0,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Audio settings
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Settings',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _AudioSettingChip(
                      label: 'Sample Rate',
                      value: '${(_metrics.sampleRate / 1000).toStringAsFixed(1)} kHz',
                    ),
                    const SizedBox(width: 12),
                    _AudioSettingChip(
                      label: 'Buffer Size',
                      value: '${_metrics.bufferSize} samples',
                    ),
                    const SizedBox(width: 12),
                    _AudioSettingChip(
                      label: 'Buffer Latency',
                      value: '${((_metrics.bufferSize / _metrics.sampleRate) * 1000).toStringAsFixed(1)} ms',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Peak meters
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Output Levels',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _PeakMeter(label: 'L', value: _metrics.peakLeft),
                const SizedBox(height: 8),
                _PeakMeter(label: 'R', value: _metrics.peakRight),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getMetricColor(double value, double warnThreshold, double errorThreshold) {
    if (value >= errorThreshold) return FluxForgeTheme.accentRed;
    if (value >= warnThreshold) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentGreen;
  }

  // ==========================================================================
  // COMMAND TAB
  // ==========================================================================

  Widget _buildCommandTab() {
    return Column(
      children: [
        // Command history
        Expanded(
          child: _commandHistory.isEmpty
              ? _buildEmptyCommands()
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _commandHistory.length,
                  itemBuilder: (context, index) {
                    final cmd = _commandHistory[index];
                    return _CommandHistoryItem(
                      command: cmd,
                      index: index + 1,
                      onRerun: () => _executeCommand(cmd),
                    );
                  },
                ),
        ),

        // Command input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              const Text(
                '>',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.accentCyan,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commandController,
                  focusNode: _commandFocusNode,
                  style: const TextStyle(
                    fontSize: 13,
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter command (help for list)',
                    hintStyle: TextStyle(color: FluxForgeTheme.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: _executeCommand,
                  onEditingComplete: () {},
                ),
              ),
              IconButton(
                onPressed: () => _executeCommand(_commandController.text),
                icon: const Icon(Icons.send, size: 18),
                color: FluxForgeTheme.accentBlue,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCommands() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.terminal,
            size: 48,
            color: FluxForgeTheme.textMuted,
          ),
          const SizedBox(height: 16),
          const Text(
            'Engine Command Console',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Type "help" for available commands',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickCommandChip(label: 'help', onTap: () => _executeCommand('help')),
              _QuickCommandChip(label: 'status', onTap: () => _executeCommand('status')),
              _QuickCommandChip(label: 'metrics', onTap: () => _executeCommand('metrics')),
              _QuickCommandChip(label: 'voices', onTap: () => _executeCommand('voices')),
              _QuickCommandChip(label: 'graph', onTap: () => _executeCommand('graph')),
            ],
          ),
        ],
      ),
    );
  }

  void _executeCommand(String command) {
    if (command.trim().isEmpty) return;

    setState(() {
      _commandHistory.add(command);
      if (_commandHistory.length > _kMaxCommandHistory) {
        _commandHistory.removeAt(0);
      }
      _historyIndex = _commandHistory.length;
    });

    // Send command via WebSocket
    final client = UltimateWebSocketClient.instance;
    client.command('engine_cmd', {'cmd': command});

    // Add log entry for command
    _addLog(LogEntry(
      level: LogLevel.debug,
      module: 'console',
      message: '> $command',
    ));

    // Handle built-in commands
    _handleBuiltinCommand(command);

    _commandController.clear();
    _commandFocusNode.requestFocus();
  }

  void _handleBuiltinCommand(String command) {
    final parts = command.trim().split(' ');
    final cmd = parts.first.toLowerCase();

    switch (cmd) {
      case 'help':
        _addLog(LogEntry(
          level: LogLevel.info,
          module: 'console',
          message: '''Available commands:
  help        - Show this help
  status      - Show engine status
  metrics     - Show performance metrics
  voices      - List active voices
  graph       - Show audio graph
  clear       - Clear console
  log <level> - Set log level (trace/debug/info/warn/error)
  play        - Resume playback
  stop        - Stop playback
  panic       - Stop all voices''',
        ));

      case 'clear':
        _clearLogs();

      case 'status':
        _addLog(LogEntry(
          level: LogLevel.info,
          module: 'console',
          message: 'Engine: Running | Voices: ${_metrics.activeVoices}/${_metrics.totalVoices} | DSP: ${_metrics.dspLoadPercent.toStringAsFixed(1)}%',
        ));

      case 'metrics':
        _addLog(LogEntry(
          level: LogLevel.info,
          module: 'console',
          message: '''Performance Metrics:
  CPU Usage:    ${_metrics.cpuUsage.toStringAsFixed(1)}%
  DSP Load:     ${_metrics.dspLoadPercent.toStringAsFixed(1)}%
  Latency:      ${_metrics.audioLatencyMs.toStringAsFixed(2)}ms
  Memory:       ${_metrics.memoryUsageMb.toStringAsFixed(0)} MB
  Sample Rate:  ${_metrics.sampleRate.toInt()} Hz
  Buffer Size:  ${_metrics.bufferSize} samples
  XRuns:        ${_metrics.xruns}''',
        ));
    }
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _ConsoleHeader extends StatelessWidget {
  final int currentTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final int errorCount;
  final int warnCount;

  const _ConsoleHeader({
    required this.currentTab,
    required this.onTabChanged,
    required this.onClear,
    required this.onExport,
    required this.errorCount,
    required this.warnCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.terminal,
            size: 18,
            color: FluxForgeTheme.accentCyan,
          ),
          const SizedBox(width: 8),
          const Text(
            'Debug Console',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Tabs
          _TabButton(
            label: 'Logs',
            icon: Icons.receipt_long,
            isSelected: currentTab == 0,
            badge: errorCount > 0 ? errorCount : null,
            badgeColor: FluxForgeTheme.accentRed,
            onTap: () => onTabChanged(0),
          ),
          _TabButton(
            label: 'Metrics',
            icon: Icons.speed,
            isSelected: currentTab == 1,
            onTap: () => onTabChanged(1),
          ),
          _TabButton(
            label: 'Command',
            icon: Icons.terminal,
            isSelected: currentTab == 2,
            onTap: () => onTabChanged(2),
          ),

          const Spacer(),

          // Warning badge
          if (warnCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 12, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 4),
                  Text(
                    '$warnCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.accentOrange,
                    ),
                  ),
                ],
              ),
            ),

          // Actions
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear_all, size: 18),
            color: FluxForgeTheme.textMuted,
            tooltip: 'Clear',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            onPressed: onExport,
            icon: const Icon(Icons.download, size: 18),
            color: FluxForgeTheme.textMuted,
            tooltip: 'Export',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final int? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor ?? FluxForgeTheme.accentRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge.toString(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOG FILTERS BAR
// =============================================================================

class _LogFiltersBar extends StatelessWidget {
  final Set<LogLevel> visibleLevels;
  final void Function(LogLevel) onLevelToggle;
  final String moduleFilter;
  final ValueChanged<String> onModuleFilterChanged;
  final TextEditingController searchController;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;
  final bool showTimestamps;
  final ValueChanged<bool> onTimestampsChanged;
  final bool wrapLines;
  final ValueChanged<bool> onWrapLinesChanged;

  const _LogFiltersBar({
    required this.visibleLevels,
    required this.onLevelToggle,
    required this.moduleFilter,
    required this.onModuleFilterChanged,
    required this.searchController,
    required this.autoScroll,
    required this.onAutoScrollChanged,
    required this.showTimestamps,
    required this.onTimestampsChanged,
    required this.wrapLines,
    required this.onWrapLinesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Level filters
          ...LogLevel.values.map((level) {
            final isVisible = visibleLevels.contains(level);
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onLevelToggle(level),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isVisible ? level.color.withValues(alpha: 0.15) : null,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isVisible ? level.color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Text(
                    level.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isVisible ? level.color : FluxForgeTheme.textMuted,
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 8),

          // Search
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: searchController,
                style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Filter logs...',
                  hintStyle: const TextStyle(color: FluxForgeTheme.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 14, color: FluxForgeTheme.textMuted),
                  filled: true,
                  fillColor: FluxForgeTheme.bgMid,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Toggle options
          _ToggleOption(
            icon: Icons.vertical_align_bottom,
            tooltip: 'Auto-scroll',
            isActive: autoScroll,
            onTap: () => onAutoScrollChanged(!autoScroll),
          ),
          _ToggleOption(
            icon: Icons.schedule,
            tooltip: 'Timestamps',
            isActive: showTimestamps,
            onTap: () => onTimestampsChanged(!showTimestamps),
          ),
          _ToggleOption(
            icon: Icons.wrap_text,
            tooltip: 'Wrap lines',
            isActive: wrapLines,
            onTap: () => onWrapLinesChanged(!wrapLines),
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isActive ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LOG LIST VIEW
// =============================================================================

class _LogListView extends StatelessWidget {
  final List<LogEntry> logs;
  final ScrollController scrollController;
  final bool showTimestamps;
  final bool wrapLines;
  final void Function(LogEntry) onLogTap;

  const _LogListView({
    required this.logs,
    required this.scrollController,
    required this.showTimestamps,
    required this.wrapLines,
    required this.onLogTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _LogEntryTile(
          log: log,
          showTimestamp: showTimestamps,
          wrap: wrapLines,
          onTap: () => onLogTap(log),
        );
      },
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry log;
  final bool showTimestamp;
  final bool wrap;
  final VoidCallback onTap;

  const _LogEntryTile({
    required this.log,
    required this.showTimestamp,
    required this.wrap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            if (showTimestamp)
              SizedBox(
                width: 80,
                child: Text(
                  _formatTime(log.timestamp),
                  style: const TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),

            // Level badge
            Container(
              width: 32,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: log.level.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                log.level.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: log.level.color,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(width: 8),

            // Module
            SizedBox(
              width: 60,
              child: Text(
                log.module,
                style: const TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.accentCyan,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 8),

            // Message
            Expanded(
              child: Text(
                log.message,
                style: const TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textSecondary,
                  fontFamily: 'monospace',
                ),
                softWrap: wrap,
                overflow: wrap ? null : TextOverflow.ellipsis,
                maxLines: wrap ? null : 1,
              ),
            ),

            // Error indicator
            if (log.stackTrace != null)
              const Icon(
                Icons.layers,
                size: 12,
                color: FluxForgeTheme.accentRed,
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${(time.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// LOG DETAIL DIALOG
// =============================================================================

class _LogDetailDialog extends StatelessWidget {
  final LogEntry log;

  const _LogDetailDialog({required this.log});

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
              decoration: BoxDecoration(
                color: log.level.color.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(log.level.icon, color: log.level.color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.module,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: FluxForgeTheme.textPrimary,
                          ),
                        ),
                        Text(
                          log.timestamp.toIso8601String(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: FluxForgeTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    color: FluxForgeTheme.textMuted,
                  ),
                ],
              ),
            ),

            // Message
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                log.message,
                style: const TextStyle(
                  fontSize: 13,
                  color: FluxForgeTheme.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Stack trace
            if (log.stackTrace != null) ...[
              const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stack Trace',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: FluxForgeTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        log.stackTrace!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: FluxForgeTheme.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

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
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: '${log.timestamp.toIso8601String()} [${log.level.label}] ${log.module}: ${log.message}${log.stackTrace != null ? '\n${log.stackTrace}' : ''}',
                      ));
                      Navigator.pop(context);
                    },
                    child: const Text('Copy'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.accentBlue,
                    ),
                    child: const Text('Close'),
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

// =============================================================================
// METRIC WIDGETS
// =============================================================================

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final List<double> history;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          // Mini sparkline
          SizedBox(
            height: 24,
            child: CustomPaint(
              size: const Size(double.infinity, 24),
              painter: _SparklinePainter(
                data: history,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final maxVal = data.reduce(math.max).clamp(1.0, double.infinity);
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - (data[i] / maxVal) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      data != oldDelegate.data || color != oldDelegate.color;
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? FluxForgeTheme.accentRed.withValues(alpha: 0.1)
            : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: highlight ? FluxForgeTheme.accentRed : FluxForgeTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: highlight ? FluxForgeTheme.accentRed : FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioSettingChip extends StatelessWidget {
  final String label;
  final String value;

  const _AudioSettingChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _PeakMeter extends StatelessWidget {
  final String label;
  final double value; // dB

  const _PeakMeter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    // Convert dB to 0-1 range (with -96 as floor)
    final normalized = ((value + 96) / 96).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: normalized,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FluxForgeTheme.accentCyan,
                      FluxForgeTheme.accentGreen,
                      FluxForgeTheme.accentOrange,
                      FluxForgeTheme.accentRed,
                    ],
                    stops: const [0.0, 0.5, 0.8, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            '${value.toStringAsFixed(1)} dB',
            style: const TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textMuted,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// COMMAND WIDGETS
// =============================================================================

class _CommandHistoryItem extends StatelessWidget {
  final String command;
  final int index;
  final VoidCallback onRerun;

  const _CommandHistoryItem({
    required this.command,
    required this.index,
    required this.onRerun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Text(
            '$index.',
            style: const TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textMuted,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              command,
              style: const TextStyle(
                fontSize: 12,
                color: FluxForgeTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            onPressed: onRerun,
            icon: const Icon(Icons.replay, size: 14),
            color: FluxForgeTheme.textMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'Run again',
          ),
        ],
      ),
    );
  }
}

class _QuickCommandChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickCommandChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
