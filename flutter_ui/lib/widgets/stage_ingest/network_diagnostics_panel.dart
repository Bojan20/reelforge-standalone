// ═══════════════════════════════════════════════════════════════════════════════
// NETWORK DIAGNOSTICS PANEL — Real-time connection health monitoring
// ═══════════════════════════════════════════════════════════════════════════════
//
// P3.11: Comprehensive network diagnostics for Stage Ingest live connections.
// Shows latency, packet loss, throughput, errors, and connection history.

import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../../providers/stage_ingest_provider.dart';
import 'latency_histogram_panel.dart';

/// Network statistics sample
class NetworkSample {
  final DateTime timestamp;
  final double latencyMs;
  final int eventsReceived;
  final int bytesReceived;
  final bool hadError;

  NetworkSample({
    required this.timestamp,
    required this.latencyMs,
    required this.eventsReceived,
    required this.bytesReceived,
    this.hadError = false,
  });
}

/// Connection history entry
class ConnectionHistoryEntry {
  final DateTime timestamp;
  final ConnectorState state;
  final String message;

  ConnectionHistoryEntry({
    required this.timestamp,
    required this.state,
    required this.message,
  });
}

/// Network diagnostics data model
class NetworkDiagnostics {
  /// Rolling window of samples (last 60 seconds)
  final Queue<NetworkSample> samples = Queue();
  static const int maxSamples = 600; // 10 samples/sec * 60 sec

  /// Connection history
  final List<ConnectionHistoryEntry> history = [];
  static const int maxHistory = 100;

  /// Cumulative stats
  int totalEventsReceived = 0;
  int totalBytesReceived = 0;
  int totalErrors = 0;
  int reconnectCount = 0;
  DateTime? connectedAt;
  DateTime? lastEventAt;

  /// Add sample
  void addSample(NetworkSample sample) {
    samples.addLast(sample);
    while (samples.length > maxSamples) {
      samples.removeFirst();
    }
    totalEventsReceived += sample.eventsReceived;
    totalBytesReceived += sample.bytesReceived;
    if (sample.hadError) totalErrors++;
    if (sample.eventsReceived > 0) lastEventAt = sample.timestamp;
  }

  /// Add history entry
  void addHistory(ConnectionHistoryEntry entry) {
    history.insert(0, entry);
    while (history.length > maxHistory) {
      history.removeLast();
    }
    if (entry.state == ConnectorState.connected) {
      connectedAt = entry.timestamp;
    } else if (entry.state == ConnectorState.reconnecting) {
      reconnectCount++;
    }
  }

  /// Calculate average latency (last 100 samples)
  double get avgLatency {
    final recent = samples.toList().reversed.take(100).toList();
    if (recent.isEmpty) return 0;
    final sum = recent.fold<double>(0, (s, e) => s + e.latencyMs);
    return sum / recent.length;
  }

  /// Calculate min latency (last 100 samples)
  double get minLatency {
    final recent = samples.toList().reversed.take(100).toList();
    if (recent.isEmpty) return 0;
    return recent.map((e) => e.latencyMs).reduce((a, b) => a < b ? a : b);
  }

  /// Calculate max latency (last 100 samples)
  double get maxLatency {
    final recent = samples.toList().reversed.take(100).toList();
    if (recent.isEmpty) return 0;
    return recent.map((e) => e.latencyMs).reduce((a, b) => a > b ? a : b);
  }

  /// Calculate P95 latency
  double get p95Latency {
    final recent = samples.toList().reversed.take(100).toList();
    if (recent.isEmpty) return 0;
    final sorted = recent.map((e) => e.latencyMs).toList()..sort();
    final idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[idx];
  }

  /// Calculate packet loss percentage (samples with errors / total)
  double get packetLoss {
    final recent = samples.toList().reversed.take(100).toList();
    if (recent.isEmpty) return 0;
    final errors = recent.where((e) => e.hadError).length;
    return (errors / recent.length) * 100;
  }

  /// Calculate events per second
  double get eventsPerSecond {
    final recent = samples.toList().reversed.take(10).toList();
    if (recent.length < 2) return 0;
    final timeSpan = recent.first.timestamp.difference(recent.last.timestamp);
    if (timeSpan.inMilliseconds == 0) return 0;
    final events = recent.fold<int>(0, (s, e) => s + e.eventsReceived);
    return events / (timeSpan.inMilliseconds / 1000);
  }

  /// Calculate throughput (bytes per second)
  double get bytesPerSecond {
    final recent = samples.toList().reversed.take(10).toList();
    if (recent.length < 2) return 0;
    final timeSpan = recent.first.timestamp.difference(recent.last.timestamp);
    if (timeSpan.inMilliseconds == 0) return 0;
    final bytes = recent.fold<int>(0, (s, e) => s + e.bytesReceived);
    return bytes / (timeSpan.inMilliseconds / 1000);
  }

  /// Get connection uptime
  Duration? get uptime {
    if (connectedAt == null) return null;
    return DateTime.now().difference(connectedAt!);
  }

  /// Get latency history for graph (last 60 samples)
  List<double> get latencyHistory {
    return samples.toList().reversed.take(60).map((e) => e.latencyMs).toList().reversed.toList();
  }

  /// Reset all stats
  void reset() {
    samples.clear();
    history.clear();
    totalEventsReceived = 0;
    totalBytesReceived = 0;
    totalErrors = 0;
    reconnectCount = 0;
    connectedAt = null;
    lastEventAt = null;
  }
}

/// Network diagnostics panel widget
class NetworkDiagnosticsPanel extends StatefulWidget {
  final StageIngestProvider provider;
  final int? connectorId;

  const NetworkDiagnosticsPanel({
    super.key,
    required this.provider,
    this.connectorId,
  });

  @override
  State<NetworkDiagnosticsPanel> createState() => _NetworkDiagnosticsPanelState();
}

class _NetworkDiagnosticsPanelState extends State<NetworkDiagnosticsPanel> {
  final NetworkDiagnostics _diagnostics = NetworkDiagnostics();
  Timer? _sampleTimer;
  Timer? _pingTimer;
  DateTime? _lastPingTime;
  ConnectorState? _lastState;
  StreamSubscription<IngestStageEvent>? _eventSubscription;
  int _eventsSinceLastSample = 0;
  int _bytesSinceLastSample = 0;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
    _eventSubscription = widget.provider.liveEvents.listen(_onEvent);
  }

  @override
  void didUpdateWidget(NetworkDiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectorId != widget.connectorId) {
      _diagnostics.reset();
      _lastState = null;
    }
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _pingTimer?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    // Sample every 100ms
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _collectSample();
    });

    // Ping every 1 second for latency
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _measureLatency();
    });
  }

  void _onEvent(IngestStageEvent event) {
    _eventsSinceLastSample++;
    // Estimate bytes from JSON
    _bytesSinceLastSample += event.stage.length + 50; // rough estimate
  }

  void _collectSample() {
    if (widget.connectorId == null) return;

    final connectorId = widget.connectorId!;
    final isConnected = widget.provider.isConnected(connectorId);
    final currentState = widget.provider.getConnectionState(connectorId);

    // Check for state changes
    if (_lastState != currentState) {
      _diagnostics.addHistory(ConnectionHistoryEntry(
        timestamp: DateTime.now(),
        state: currentState,
        message: _stateToMessage(currentState),
      ));
      _lastState = currentState;
    }

    // Only collect samples while connected
    if (!isConnected) {
      setState(() {});
      return;
    }

    final sample = NetworkSample(
      timestamp: DateTime.now(),
      latencyMs: _calculateLatency(),
      eventsReceived: _eventsSinceLastSample,
      bytesReceived: _bytesSinceLastSample,
      hadError: currentState == ConnectorState.error,
    );

    _diagnostics.addSample(sample);
    _eventsSinceLastSample = 0;
    _bytesSinceLastSample = 0;

    setState(() {});
  }

  void _measureLatency() {
    _lastPingTime = DateTime.now();
    // Note: Actual ping implementation would use FFI
    // For now we use a simulated value based on event timing
  }

  double _calculateLatency() {
    if (_diagnostics.lastEventAt == null) return 0;
    final diff = DateTime.now().difference(_diagnostics.lastEventAt!);
    // Clamp to reasonable values (0-500ms)
    return diff.inMilliseconds.clamp(0, 500).toDouble();
  }

  String _stateToMessage(ConnectorState state) {
    switch (state) {
      case ConnectorState.disconnected:
        return 'Disconnected';
      case ConnectorState.connecting:
        return 'Connecting...';
      case ConnectorState.connected:
        return 'Connected successfully';
      case ConnectorState.reconnecting:
        return 'Reconnecting...';
      case ConnectorState.error:
        return 'Connection error';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLatencySection(),
                  const SizedBox(height: 16),
                  _buildHistogramSection(),
                  const SizedBox(height: 16),
                  _buildThroughputSection(),
                  const SizedBox(height: 16),
                  _buildConnectionSection(),
                  const SizedBox(height: 16),
                  _buildHistorySection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isConnected = widget.connectorId != null &&
        widget.provider.isConnected(widget.connectorId!);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            color: Colors.white.withOpacity(0.7),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Network Diagnostics',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          _buildHealthIndicator(isConnected),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              _diagnostics.reset();
              setState(() {});
            },
            icon: Icon(
              Icons.refresh,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'Reset statistics',
          ),
        ],
      ),
    );
  }

  Widget _buildHealthIndicator(bool isConnected) {
    if (!isConnected) {
      return _buildStatusChip('Offline', Colors.grey);
    }

    final latency = _diagnostics.avgLatency;
    final packetLoss = _diagnostics.packetLoss;

    if (packetLoss > 5 || latency > 100) {
      return _buildStatusChip('Poor', const Color(0xFFff4040));
    } else if (packetLoss > 1 || latency > 50) {
      return _buildStatusChip('Fair', const Color(0xFFffff40));
    } else {
      return _buildStatusChip('Good', const Color(0xFF40ff90));
    }
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencySection() {
    return _buildSection(
      title: 'Latency',
      icon: Icons.speed,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildMetricCard('Average', '${_diagnostics.avgLatency.toStringAsFixed(1)} ms', _getLatencyColor(_diagnostics.avgLatency))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard('Min', '${_diagnostics.minLatency.toStringAsFixed(1)} ms', const Color(0xFF40ff90))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard('Max', '${_diagnostics.maxLatency.toStringAsFixed(1)} ms', const Color(0xFFff9040))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricCard('P95', '${_diagnostics.p95Latency.toStringAsFixed(1)} ms', const Color(0xFF4a9eff))),
            ],
          ),
          const SizedBox(height: 12),
          _buildLatencyGraph(),
        ],
      ),
    );
  }

  Widget _buildLatencyGraph() {
    final history = _diagnostics.latencyHistory;
    if (history.isEmpty) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'No data',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
          ),
        ),
      );
    }

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 60),
        painter: _LatencyGraphPainter(history),
      ),
    );
  }

  Widget _buildHistogramSection() {
    // Get latency samples for histogram
    final latencySamples = _diagnostics.samples
        .map((s) => s.latencyMs)
        .where((l) => l > 0)
        .toList();

    return _buildSection(
      title: 'Latency Distribution',
      icon: Icons.bar_chart,
      child: SizedBox(
        height: 200,
        child: LatencyHistogramPanel(
          samples: latencySamples,
          title: '',
          showStats: false,
          showPercentiles: true,
          compact: false,
        ),
      ),
    );
  }

  Widget _buildThroughputSection() {
    return _buildSection(
      title: 'Throughput',
      icon: Icons.trending_up,
      child: Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              'Events/sec',
              _diagnostics.eventsPerSecond.toStringAsFixed(1),
              const Color(0xFF4a9eff),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Throughput',
              '${_formatBytes(_diagnostics.bytesPerSecond)}/s',
              const Color(0xFF40c8ff),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Total Events',
              _formatNumber(_diagnostics.totalEventsReceived),
              const Color(0xFF40ff90),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Packet Loss',
              '${_diagnostics.packetLoss.toStringAsFixed(2)}%',
              _getPacketLossColor(_diagnostics.packetLoss),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSection() {
    final uptime = _diagnostics.uptime;

    return _buildSection(
      title: 'Connection',
      icon: Icons.wifi,
      child: Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              'Uptime',
              uptime != null ? _formatDuration(uptime) : '--:--',
              const Color(0xFF4a9eff),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Reconnects',
              _diagnostics.reconnectCount.toString(),
              _diagnostics.reconnectCount > 0
                  ? const Color(0xFFff9040)
                  : const Color(0xFF40ff90),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Errors',
              _diagnostics.totalErrors.toString(),
              _diagnostics.totalErrors > 0
                  ? const Color(0xFFff4040)
                  : const Color(0xFF40ff90),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetricCard(
              'Total Data',
              _formatBytes(_diagnostics.totalBytesReceived.toDouble()),
              const Color(0xFF40c8ff),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return _buildSection(
      title: 'Connection History',
      icon: Icons.history,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 150),
        decoration: BoxDecoration(
          color: const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _diagnostics.history.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No connection history',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: _diagnostics.history.length,
                itemBuilder: (context, index) {
                  final entry = _diagnostics.history[index];
                  return _buildHistoryRow(entry);
                },
              ),
      ),
    );
  }

  Widget _buildHistoryRow(ConnectionHistoryEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStateColor(entry.state),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(entry.timestamp),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.5)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getLatencyColor(double latency) {
    if (latency > 100) return const Color(0xFFff4040);
    if (latency > 50) return const Color(0xFFff9040);
    if (latency > 20) return const Color(0xFFffff40);
    return const Color(0xFF40ff90);
  }

  Color _getPacketLossColor(double loss) {
    if (loss > 5) return const Color(0xFFff4040);
    if (loss > 1) return const Color(0xFFff9040);
    if (loss > 0) return const Color(0xFFffff40);
    return const Color(0xFF40ff90);
  }

  Color _getStateColor(ConnectorState state) {
    switch (state) {
      case ConnectorState.connected:
        return const Color(0xFF40ff90);
      case ConnectorState.connecting:
      case ConnectorState.reconnecting:
        return const Color(0xFFffff40);
      case ConnectorState.error:
        return const Color(0xFFff4040);
      case ConnectorState.disconnected:
        return Colors.grey;
    }
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatNumber(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(2)}M';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

/// Custom painter for latency sparkline graph
class _LatencyGraphPainter extends CustomPainter {
  final List<double> data;
  static const double maxLatency = 200.0;

  _LatencyGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF4a9eff)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x404a9eff),
          Color(0x004a9eff),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1).clamp(1, double.infinity);

    for (var i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] / maxLatency * size.height).clamp(0.0, size.height);

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

    // Draw threshold lines
    final thresholdPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 50ms threshold (warning)
    thresholdPaint.color = const Color(0x40ffff40);
    final y50 = size.height - (50 / maxLatency * size.height);
    canvas.drawLine(Offset(0, y50), Offset(size.width, y50), thresholdPaint);

    // 100ms threshold (critical)
    thresholdPaint.color = const Color(0x40ff4040);
    final y100 = size.height - (100 / maxLatency * size.height);
    canvas.drawLine(Offset(0, y100), Offset(size.width, y100), thresholdPaint);
  }

  @override
  bool shouldRepaint(_LatencyGraphPainter oldDelegate) => true;
}

/// Compact network status badge
class NetworkStatusBadge extends StatelessWidget {
  final NetworkDiagnostics diagnostics;
  final bool isConnected;

  const NetworkStatusBadge({
    super.key,
    required this.diagnostics,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return _buildBadge('Offline', Colors.grey, Icons.wifi_off);
    }

    final latency = diagnostics.avgLatency;
    final packetLoss = diagnostics.packetLoss;

    if (packetLoss > 5 || latency > 100) {
      return _buildBadge(
        '${latency.toStringAsFixed(0)}ms',
        const Color(0xFFff4040),
        Icons.signal_cellular_alt_1_bar,
      );
    } else if (packetLoss > 1 || latency > 50) {
      return _buildBadge(
        '${latency.toStringAsFixed(0)}ms',
        const Color(0xFFffff40),
        Icons.signal_cellular_alt_2_bar,
      );
    } else {
      return _buildBadge(
        '${latency.toStringAsFixed(0)}ms',
        const Color(0xFF40ff90),
        Icons.signal_cellular_alt,
      );
    }
  }

  Widget _buildBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
