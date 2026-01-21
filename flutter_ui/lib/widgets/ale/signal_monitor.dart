/// Signal Monitor Widget
///
/// Real-time visualization of ALE signal values with history graphs.

import 'dart:collection';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Signal history for graphing
class SignalHistory {
  final int maxLength;
  final Queue<double> _values = Queue<double>();

  SignalHistory({this.maxLength = 120}); // ~2 seconds at 60fps

  void add(double value) {
    _values.addLast(value);
    while (_values.length > maxLength) {
      _values.removeFirst();
    }
  }

  List<double> get values => _values.toList();
  double get current => _values.isNotEmpty ? _values.last : 0.0;
  double get min => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a < b ? a : b);
  double get max => _values.isEmpty ? 1.0 : _values.reduce((a, b) => a > b ? a : b);
}

/// Real-time signal monitor widget
class SignalMonitor extends StatefulWidget {
  final List<String>? signalIds;
  final bool showGraph;
  final bool showNormalized;
  final double height;

  const SignalMonitor({
    super.key,
    this.signalIds,
    this.showGraph = true,
    this.showNormalized = true,
    this.height = 200,
  });

  @override
  State<SignalMonitor> createState() => _SignalMonitorState();
}

class _SignalMonitorState extends State<SignalMonitor> {
  final Map<String, SignalHistory> _histories = {};
  String? _selectedSignal;

  // Default signals to monitor
  static const List<String> _defaultSignals = [
    'winTier',
    'momentum',
    'volatility',
    'sessionProgress',
    'featureProgress',
    'betMultiplier',
    'recentWinRate',
    'timeSinceWin',
    'comboCount',
    'nearMissRate',
  ];

  List<String> get _signalIds => widget.signalIds ?? _defaultSignals;

  @override
  void initState() {
    super.initState();
    for (final id in _signalIds) {
      _histories[id] = SignalHistory();
    }
  }

  void _updateHistories(Map<String, double> signals) {
    for (final entry in signals.entries) {
      if (_histories.containsKey(entry.key)) {
        _histories[entry.key]!.add(entry.value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        // Update histories with current values
        _updateHistories(ale.currentSignals);

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(),

              // Signal list or graph
              Expanded(
                child: _selectedSignal != null && widget.showGraph
                    ? _buildSignalGraph(_selectedSignal!)
                    : _buildSignalList(ale),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor_heart, color: Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Signal Monitor',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (_selectedSignal != null)
            TextButton.icon(
              onPressed: () => setState(() => _selectedSignal = null),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4a9eff),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignalList(AleProvider ale) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _signalIds.length,
      itemBuilder: (context, index) {
        final id = _signalIds[index];
        final value = ale.currentSignals[id] ?? 0.0;
        final normalized = widget.showNormalized
            ? ale.getSignalNormalized(id)
            : value;
        final history = _histories[id];

        return _SignalRow(
          signalId: id,
          value: value,
          normalizedValue: normalized,
          history: history,
          showMiniGraph: widget.showGraph,
          onTap: widget.showGraph
              ? () => setState(() => _selectedSignal = id)
              : null,
        );
      },
    );
  }

  Widget _buildSignalGraph(String signalId) {
    final history = _histories[signalId];
    if (history == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                signalId,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                history.current.toStringAsFixed(3),
                style: const TextStyle(
                  color: Color(0xFF4a9eff),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CustomPaint(
              painter: _SignalGraphPainter(
                values: history.values,
                color: _getSignalColor(signalId),
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Min: ${history.min.toStringAsFixed(3)}',
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                ),
              ),
              Text(
                'Max: ${history.max.toStringAsFixed(3)}',
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(String signalId) {
    return switch (signalId) {
      'winTier' => const Color(0xFFff9040),
      'momentum' => const Color(0xFF40ff90),
      'volatility' => const Color(0xFFff4060),
      'sessionProgress' => const Color(0xFF4a9eff),
      'featureProgress' => const Color(0xFFffff40),
      'betMultiplier' => const Color(0xFF40c8ff),
      'recentWinRate' => const Color(0xFFff40ff),
      'timeSinceWin' => const Color(0xFFff8040),
      'comboCount' => const Color(0xFF40ffff),
      'nearMissRate' => const Color(0xFFffcc40),
      _ => const Color(0xFF4a9eff),
    };
  }
}

/// Individual signal row
class _SignalRow extends StatelessWidget {
  final String signalId;
  final double value;
  final double normalizedValue;
  final SignalHistory? history;
  final bool showMiniGraph;
  final VoidCallback? onTap;

  const _SignalRow({
    required this.signalId,
    required this.value,
    required this.normalizedValue,
    this.history,
    this.showMiniGraph = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getSignalColor(signalId);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF121216),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // Signal name
            Expanded(
              flex: 3,
              child: Text(
                signalId,
                style: const TextStyle(
                  color: Color(0xFFcccccc),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Mini graph
            if (showMiniGraph && history != null)
              SizedBox(
                width: 60,
                height: 20,
                child: CustomPaint(
                  painter: _MiniGraphPainter(
                    values: history!.values,
                    color: color,
                  ),
                ),
              ),

            const SizedBox(width: 8),

            // Value bar
            SizedBox(
              width: 60,
              child: Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2a2a35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: normalizedValue.clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Value text
            SizedBox(
              width: 50,
              child: Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
              ),
            ),

            if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF666666),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Color _getSignalColor(String signalId) {
    return switch (signalId) {
      'winTier' => const Color(0xFFff9040),
      'momentum' => const Color(0xFF40ff90),
      'volatility' => const Color(0xFFff4060),
      'sessionProgress' => const Color(0xFF4a9eff),
      'featureProgress' => const Color(0xFFffff40),
      'betMultiplier' => const Color(0xFF40c8ff),
      'recentWinRate' => const Color(0xFFff40ff),
      'timeSinceWin' => const Color(0xFFff8040),
      'comboCount' => const Color(0xFF40ffff),
      'nearMissRate' => const Color(0xFFffcc40),
      _ => const Color(0xFF4a9eff),
    };
  }
}

/// Mini sparkline graph painter
class _MiniGraphPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _MiniGraphPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = range > 0 ? (values[i] - minVal) / range : 0.5;
      final y = size.height - normalized * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniGraphPainter oldDelegate) => true;
}

/// Full signal graph painter
class _SignalGraphPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SignalGraphPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Draw grid
    final gridPaint = Paint()
      ..color = const Color(0xFF2a2a35)
      ..strokeWidth = 1.0;

    // Horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = i / 4 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines
    for (int i = 0; i <= 6; i++) {
      final x = i / 6 * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw filled area
    final fillPath = Path();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    fillPath.moveTo(0, size.height);
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = range > 0 ? (values[i] - minVal) / range : 0.5;
      final y = size.height - normalized * size.height;
      fillPath.lineTo(x, y);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [color.withValues(alpha: 0.3), color.withValues(alpha: 0.0)],
      );
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = range > 0 ? (values[i] - minVal) / range : 0.5;
      final y = size.height - normalized * size.height;

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, linePaint);

    // Draw current value dot
    if (values.isNotEmpty) {
      final lastNormalized = range > 0 ? (values.last - minVal) / range : 0.5;
      final lastY = size.height - lastNormalized * size.height;

      canvas.drawCircle(
        Offset(size.width, lastY),
        4,
        Paint()..color = color,
      );
      canvas.drawCircle(
        Offset(size.width, lastY),
        6,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalGraphPainter oldDelegate) => true;
}
