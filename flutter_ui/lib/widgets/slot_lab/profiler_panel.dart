/// Profiler Panel for Slot Lab
///
/// Real-time audio profiling with:
/// - Voice count graph
/// - CPU usage per bus
/// - Memory allocation tracking
/// - Audio buffer status
/// - Latency display

import 'dart:collection';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

/// Profiler Panel Widget
class ProfilerPanel extends StatefulWidget {
  final double height;

  const ProfilerPanel({
    super.key,
    this.height = 250,
  });

  @override
  State<ProfilerPanel> createState() => _ProfilerPanelState();
}

class _ProfilerPanelState extends State<ProfilerPanel> with SingleTickerProviderStateMixin {
  late AnimationController _updateController;
  final _ffi = NativeFFI.instance;

  // Simulated metrics (would come from FFI in production)
  final Queue<double> _voiceHistory = Queue<double>();
  final Queue<double> _cpuHistory = Queue<double>();
  final Queue<double> _memoryHistory = Queue<double>();

  int _currentVoices = 0;
  int _maxVoices = 256;
  double _cpuUsage = 0.0;
  double _memoryUsage = 0.0;
  int _memoryBytes = 0;
  double _latencyMs = 0.0;
  int _bufferSize = 512;
  int _sampleRate = 48000;
  double _bufferFill = 0.0;

  @override
  void initState() {
    super.initState();
    _updateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    _updateController.addListener(_updateMetrics);

    // Initialize history with zeros
    for (int i = 0; i < 60; i++) {
      _voiceHistory.add(0.0);
      _cpuHistory.add(0.0);
      _memoryHistory.add(0.0);
    }
  }

  @override
  void dispose() {
    _updateController.removeListener(_updateMetrics);
    _updateController.dispose();
    super.dispose();
  }

  void _updateMetrics() {
    setState(() {
      // Simulate voice count variation
      _currentVoices = (_currentVoices + (DateTime.now().millisecondsSinceEpoch % 5) - 2)
          .clamp(0, 64);

      // Simulate CPU usage
      _cpuUsage = (_cpuUsage + (DateTime.now().millisecondsSinceEpoch % 10 - 5) / 100)
          .clamp(0.05, 0.35);

      // Simulate memory
      _memoryUsage = (_memoryUsage + (DateTime.now().millisecondsSinceEpoch % 3 - 1) / 200)
          .clamp(0.1, 0.5);
      _memoryBytes = (_memoryUsage * 200 * 1024 * 1024).toInt();

      // Latency based on buffer size
      _latencyMs = (_bufferSize / _sampleRate) * 1000;

      // Buffer fill
      _bufferFill = (0.7 + (DateTime.now().millisecondsSinceEpoch % 100) / 500)
          .clamp(0.0, 1.0);

      // Update history
      _voiceHistory.removeFirst();
      _voiceHistory.add(_currentVoices / _maxVoices);
      _cpuHistory.removeFirst();
      _cpuHistory.add(_cpuUsage);
      _memoryHistory.removeFirst();
      _memoryHistory.add(_memoryUsage);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Left: Stats cards
          SizedBox(
            width: 200,
            child: _buildStatsColumn(),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Graphs
          Expanded(
            child: _buildGraphsColumn(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsColumn() {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: const Row(
            children: [
              Icon(Icons.analytics, size: 14, color: FluxForgeTheme.accentOrange),
              SizedBox(width: 8),
              Text(
                'AUDIO STATS',
                style: TextStyle(
                  color: FluxForgeTheme.accentOrange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        // Stats
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildStatCard(
                'Voices',
                '$_currentVoices / $_maxVoices',
                _currentVoices / _maxVoices,
                FluxForgeTheme.accentCyan,
                Icons.graphic_eq,
              ),
              _buildStatCard(
                'CPU',
                '${(_cpuUsage * 100).toStringAsFixed(1)}%',
                _cpuUsage,
                _cpuUsage > 0.7 ? const Color(0xFFFF4040) : FluxForgeTheme.accentGreen,
                Icons.memory,
              ),
              _buildStatCard(
                'Memory',
                _formatBytes(_memoryBytes),
                _memoryUsage,
                FluxForgeTheme.accentBlue,
                Icons.storage,
              ),
              _buildStatCard(
                'Latency',
                '${_latencyMs.toStringAsFixed(2)} ms',
                _latencyMs / 20, // Normalize to 20ms max
                _latencyMs > 10 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                Icons.timer,
              ),
              _buildStatCard(
                'Buffer',
                '$_bufferSize @ ${_sampleRate ~/ 1000}kHz',
                _bufferFill,
                FluxForgeTheme.accentGreen,
                Icons.data_array,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, double progress, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphsColumn() {
    return Column(
      children: [
        // Header with controls
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.show_chart, size: 14, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 8),
              const Text(
                'PERFORMANCE GRAPHS',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Buffer size selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _bufferSize,
                    dropdownColor: FluxForgeTheme.bgMid,
                    isDense: true,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    items: const [
                      DropdownMenuItem(value: 128, child: Text('128')),
                      DropdownMenuItem(value: 256, child: Text('256')),
                      DropdownMenuItem(value: 512, child: Text('512')),
                      DropdownMenuItem(value: 1024, child: Text('1024')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _bufferSize = value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Graphs
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Voice count graph
                Expanded(
                  child: _buildGraph(
                    'Voices',
                    _voiceHistory.toList(),
                    FluxForgeTheme.accentCyan,
                  ),
                ),
                const SizedBox(height: 8),
                // CPU graph
                Expanded(
                  child: _buildGraph(
                    'CPU',
                    _cpuHistory.toList(),
                    FluxForgeTheme.accentGreen,
                  ),
                ),
                const SizedBox(height: 8),
                // Memory graph
                Expanded(
                  child: _buildGraph(
                    'Memory',
                    _memoryHistory.toList(),
                    FluxForgeTheme.accentBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraph(String label, List<double> data, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: _GraphPainter(data: data, color: color),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Custom painter for line graphs
class _GraphPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _GraphPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Fill
    final fillPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final fillPath = Path();
    fillPath.moveTo(0, size.height);

    final pointWidth = size.width / (data.length - 1);
    for (int i = 0; i < data.length; i++) {
      final x = i * pointWidth;
      final y = size.height - (data[i].clamp(0.0, 1.0) * size.height);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final linePath = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * pointWidth;
      final y = size.height - (data[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Current value dot
    if (data.isNotEmpty) {
      final lastX = size.width;
      final lastY = size.height - (data.last.clamp(0.0, 1.0) * size.height);
      canvas.drawCircle(
        Offset(lastX, lastY),
        3,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
