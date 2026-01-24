/// Spatial Event Visualizer — Real-time 2D radar view
///
/// Features:
/// - Real-time radar of active events
/// - Pan/width/distance indicators
/// - Color-coded by bus type
/// - Click to inspect event details

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import '../../spatial/auto_spatial.dart';

/// Spatial Event Visualizer widget
class SpatialEventVisualizer extends StatefulWidget {
  final bool compact;

  const SpatialEventVisualizer({
    super.key,
    this.compact = false,
  });

  @override
  State<SpatialEventVisualizer> createState() => _SpatialEventVisualizerState();
}

class _SpatialEventVisualizerState extends State<SpatialEventVisualizer> {
  Timer? _refreshTimer;
  String? _selectedEventId;
  final Map<String, SpatialOutput> _outputs = {};

  @override
  void initState() {
    super.initState();
    // Refresh at 30Hz for smooth visualization
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _updateOutputs();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateOutputs() {
    final provider = AutoSpatialProvider.instance;
    if (!provider.isInitialized) return;

    final newOutputs = provider.engine.update();
    if (mounted) {
      setState(() {
        _outputs.clear();
        _outputs.addAll(newOutputs);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoSpatialProvider>(
      builder: (context, provider, _) {
        if (widget.compact) {
          return _buildCompactLayout(provider);
        }

        return Row(
          children: [
            // Left: Radar
            Expanded(
              flex: 2,
              child: _buildRadarView(provider),
            ),

            const VerticalDivider(width: 1, color: Color(0xFF3a3a4a)),

            // Right: Event list + details
            SizedBox(
              width: 240,
              child: _buildEventPanel(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactLayout(AutoSpatialProvider provider) {
    return _buildRadarView(provider);
  }

  Widget _buildRadarView(AutoSpatialProvider provider) {
    return Container(
      color: const Color(0xFF121216),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Radar background
              CustomPaint(
                painter: _RadarPainter(),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),

              // Event markers
              for (final entry in _outputs.entries)
                _buildEventMarker(
                  entry.key,
                  entry.value,
                  constraints,
                  entry.key == _selectedEventId,
                ),

              // Legend
              Positioned(
                left: 8,
                top: 8,
                child: _buildLegend(),
              ),

              // Pan meter
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildPanMeter(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEventMarker(
    String eventId,
    SpatialOutput output,
    BoxConstraints constraints,
    bool isSelected,
  ) {
    // Convert pan (-1 to +1) to x position
    final centerX = constraints.maxWidth / 2;
    final centerY = constraints.maxHeight / 2;

    // Use azimuth and elevation for position
    final radius = (constraints.maxWidth / 2 - 30) * (1 - output.distance);
    final x = centerX + math.sin(output.azimuthRad) * radius;
    final y = centerY - math.cos(output.azimuthRad) * radius * 0.7; // Flatten for 2D

    // Estimate bus from event ID
    final bus = _guessBusFromEventId(eventId);
    final color = _busColor(bus);

    // Width visualization
    final widthRadius = output.width * 20 + 8;

    return Positioned(
      left: x - widthRadius,
      top: y - widthRadius,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedEventId = isSelected ? null : eventId;
        }),
        child: Container(
          width: widthRadius * 2,
          height: widthRadius * 2,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3 * output.confidence),
            borderRadius: BorderRadius.circular(widthRadius),
            border: Border.all(
              color: isSelected ? Colors.white : color,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: _busColor(SpatialBus.ui), label: 'UI'),
          _LegendItem(color: _busColor(SpatialBus.reels), label: 'Reels'),
          _LegendItem(color: _busColor(SpatialBus.sfx), label: 'SFX'),
          _LegendItem(color: _busColor(SpatialBus.vo), label: 'Voice'),
          _LegendItem(color: _busColor(SpatialBus.music), label: 'Music'),
          _LegendItem(color: _busColor(SpatialBus.ambience), label: 'Amb'),
        ],
      ),
    );
  }

  Widget _buildPanMeter() {
    // Aggregate pan from all outputs
    double totalPan = 0;
    double totalWeight = 0;
    for (final output in _outputs.values) {
      totalPan += output.pan * output.confidence;
      totalWeight += output.confidence;
    }
    final avgPan = totalWeight > 0 ? totalPan / totalWeight : 0.0;

    return Container(
      height: 24,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3a3a4a)),
      ),
      child: Stack(
        children: [
          // Center line
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 1,
                color: Colors.white24,
              ),
            ),
          ),

          // Pan indicator
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            bottom: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final indicatorX =
                    (constraints.maxWidth / 2) + (avgPan * (constraints.maxWidth / 2 - 8));
                return Stack(
                  children: [
                    Positioned(
                      left: indicatorX - 4,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4a9eff),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Labels
          const Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text('L', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ),
          ),
          const Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Text('R', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventPanel(AutoSpatialProvider provider) {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Icon(Icons.radar, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Active Events',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF40ff90).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_outputs.length}',
                  style: const TextStyle(
                    color: Color(0xFF40ff90),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFF3a3a4a)),

        // Event list
        Expanded(
          child: _outputs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radio_button_unchecked,
                          color: Colors.white24, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'No active events',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Send test events to see them here',
                        style: TextStyle(color: Colors.white24, fontSize: 9),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _outputs.length,
                  itemBuilder: (context, index) {
                    final entry = _outputs.entries.elementAt(index);
                    final isSelected = _selectedEventId == entry.key;

                    return _EventListTile(
                      eventId: entry.key,
                      output: entry.value,
                      isSelected: isSelected,
                      onTap: () => setState(() {
                        _selectedEventId = isSelected ? null : entry.key;
                      }),
                    );
                  },
                ),
        ),

        const Divider(height: 1, color: Color(0xFF3a3a4a)),

        // Details or test panel
        SizedBox(
          height: 200,
          child: _selectedEventId != null && _outputs.containsKey(_selectedEventId)
              ? _buildEventDetails(_outputs[_selectedEventId]!)
              : _buildTestPanel(provider),
        ),
      ],
    );
  }

  Widget _buildEventDetails(SpatialOutput output) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'Event Details',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: () => setState(() => _selectedEventId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stereo
          _DetailRow(label: 'Pan', value: output.pan.toStringAsFixed(3)),
          _DetailRow(label: 'Width', value: output.width.toStringAsFixed(3)),
          _DetailRow(label: 'L Gain', value: output.gains.left.toStringAsFixed(3)),
          _DetailRow(label: 'R Gain', value: output.gains.right.toStringAsFixed(3)),
          const SizedBox(height: 8),

          // Position
          _DetailRow(label: 'Distance', value: output.distance.toStringAsFixed(3)),
          _DetailRow(
            label: 'Azimuth',
            value: '${(output.azimuthRad * 180 / math.pi).toStringAsFixed(1)}°',
          ),
          _DetailRow(
            label: 'Elevation',
            value: '${(output.elevationRad * 180 / math.pi).toStringAsFixed(1)}°',
          ),
          const SizedBox(height: 8),

          // Effects
          _DetailRow(
            label: 'Dist Gain',
            value: '${(output.distanceGain * 100).toStringAsFixed(1)}%',
          ),
          _DetailRow(
            label: 'Doppler',
            value: 'x${output.dopplerShift.toStringAsFixed(3)}',
          ),
          _DetailRow(
            label: 'Air Abs',
            value: '${output.airAbsorptionDb.toStringAsFixed(1)}dB',
          ),
          _DetailRow(
            label: 'Reverb',
            value: '${(output.reverbSend * 100).toStringAsFixed(0)}%',
          ),
          _DetailRow(
            label: 'Confidence',
            value: '${(output.confidence * 100).toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  Widget _buildTestPanel(AutoSpatialProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Test Events',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Test buttons grid
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _TestEventButton(
                label: 'Spin Start',
                intent: 'SPIN_START',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Reel L',
                intent: 'REEL_STOP_0',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Reel C',
                intent: 'REEL_STOP_2',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Reel R',
                intent: 'REEL_STOP_4',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Big Win',
                intent: 'BIG_WIN',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Mega Win',
                intent: 'MEGA_WIN',
                provider: provider,
              ),
              _TestEventButton(
                label: 'UI Click',
                intent: 'UI_CLICK',
                provider: provider,
              ),
              _TestEventButton(
                label: 'Coin Fly',
                intent: 'COIN_FLY_TO_BALANCE',
                provider: provider,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Clear button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white24),
              ),
              onPressed: provider.clearEvents,
              child: const Text('Clear All Events', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  SpatialBus _guessBusFromEventId(String eventId) {
    final lower = eventId.toLowerCase();
    if (lower.contains('ui') || lower.contains('click') || lower.contains('hover')) {
      return SpatialBus.ui;
    }
    if (lower.contains('reel') || lower.contains('spin')) {
      return SpatialBus.reels;
    }
    if (lower.contains('win') || lower.contains('bonus') || lower.contains('jackpot')) {
      return SpatialBus.sfx;
    }
    if (lower.contains('vo') || lower.contains('voice') || lower.contains('announce')) {
      return SpatialBus.vo;
    }
    if (lower.contains('music') || lower.contains('bgm')) {
      return SpatialBus.music;
    }
    if (lower.contains('amb') || lower.contains('loop')) {
      return SpatialBus.ambience;
    }
    return SpatialBus.sfx;
  }

  Color _busColor(SpatialBus bus) => switch (bus) {
        SpatialBus.ui => const Color(0xFF4a9eff),
        SpatialBus.reels => const Color(0xFF40ff90),
        SpatialBus.sfx => const Color(0xFFff9040),
        SpatialBus.vo => const Color(0xFFff4060),
        SpatialBus.music => const Color(0xFF40c8ff),
        SpatialBus.ambience => const Color(0xFF9040ff),
      };
}

/// Radar painter
class _RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final maxRadius = math.min(centerX, centerY) - 30;

    final gridPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Concentric circles
    for (var i = 1; i <= 4; i++) {
      final r = maxRadius * i / 4;
      canvas.drawCircle(Offset(centerX, centerY), r, gridPaint);
    }

    // Cross lines
    canvas.drawLine(
      Offset(centerX - maxRadius, centerY),
      Offset(centerX + maxRadius, centerY),
      gridPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - maxRadius * 0.7),
      Offset(centerX, centerY + maxRadius * 0.7),
      gridPaint,
    );

    // Diagonal lines
    final diagPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final dx = math.cos(angle) * maxRadius;
      final dy = math.sin(angle) * maxRadius;
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + dx, centerY + dy),
        diagPaint,
      );
    }

    // Center dot
    canvas.drawCircle(
      Offset(centerX, centerY),
      3,
      Paint()..color = Colors.white24,
    );

    // Labels
    final labelStyle = TextStyle(
      color: Colors.white24,
      fontSize: 9,
    );

    final frontPainter = TextPainter(
      text: TextSpan(text: 'FRONT', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    frontPainter.paint(
      canvas,
      Offset(centerX - frontPainter.width / 2, 8),
    );

    final backPainter = TextPainter(
      text: TextSpan(text: 'BACK', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    backPainter.paint(
      canvas,
      Offset(centerX - backPainter.width / 2, size.height - 28),
    );

    final leftPainter = TextPainter(
      text: TextSpan(text: 'L', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    leftPainter.paint(
      canvas,
      Offset(8, centerY - leftPainter.height / 2),
    );

    final rightPainter = TextPainter(
      text: TextSpan(text: 'R', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    rightPainter.paint(
      canvas,
      Offset(size.width - 16, centerY - rightPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Legend item
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8)),
        ],
      ),
    );
  }
}

/// Event list tile
class _EventListTile extends StatelessWidget {
  final String eventId;
  final SpatialOutput output;
  final bool isSelected;
  final VoidCallback onTap;

  const _EventListTile({
    required this.eventId,
    required this.output,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? const Color(0xFF4a9eff).withValues(alpha: 0.15)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // Pan indicator
              SizedBox(
                width: 20,
                child: Text(
                  output.pan < -0.3
                      ? 'L'
                      : output.pan > 0.3
                          ? 'R'
                          : 'C',
                  style: TextStyle(
                    color: const Color(0xFF4a9eff),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  eventId.length > 20 ? '${eventId.substring(0, 18)}...' : eventId,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(output.confidence * 100).round()}%',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail row
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Test event button
class _TestEventButton extends StatelessWidget {
  final String label;
  final String intent;
  final AutoSpatialProvider provider;

  const _TestEventButton({
    required this.label,
    required this.intent,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => provider.sendTestEvent(intent: intent),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF121216),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF3a3a4a)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
      ),
    );
  }
}
