/// RTPC Editor Panel for Slot Lab
///
/// Visual editor for Real-Time Parameter Control:
/// - List of all RTPC parameters with current values
/// - Interactive sliders for real-time manipulation
/// - Visual curve editor for RTPC → parameter mapping
/// - Binding management (RTPC → Volume, Pitch, LPF, etc.)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// RTPC Editor Panel Widget
class RtpcEditorPanel extends StatefulWidget {
  final double height;

  const RtpcEditorPanel({
    super.key,
    this.height = 250,
  });

  @override
  State<RtpcEditorPanel> createState() => _RtpcEditorPanelState();
}

class _RtpcEditorPanelState extends State<RtpcEditorPanel> {
  int? _selectedRtpcId;
  bool _showBindings = false;

  // Local RTPC values for real-time feedback
  final Map<int, double> _localValues = {};

  @override
  void initState() {
    super.initState();
    _initializeLocalValues();
  }

  void _initializeLocalValues() {
    // Initialize with slot RTPC defaults
    _localValues[SlotRtpcIds.winMultiplier] = 0.0;
    _localValues[SlotRtpcIds.betLevel] = 0.5;
    _localValues[SlotRtpcIds.volatility] = 1.0;
    _localValues[SlotRtpcIds.tension] = 0.0;
    _localValues[SlotRtpcIds.cascadeDepth] = 0.0;
    _localValues[SlotRtpcIds.featureProgress] = 0.0;
    _localValues[SlotRtpcIds.rollupSpeed] = 1.0;
    _localValues[SlotRtpcIds.jackpotPool] = 0.3;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Left: RTPC List with sliders
          Expanded(
            flex: 2,
            child: _buildRtpcList(),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Curve editor or bindings
          Expanded(
            flex: 3,
            child: _showBindings ? _buildBindingsPanel() : _buildCurveEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildRtpcList() {
    final rtpcs = SlotRtpcFactory.createAllRtpcs();

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.tune, size: 14, color: FluxForgeTheme.accentOrange),
              const SizedBox(width: 8),
              const Text(
                'RTPC PARAMETERS',
                style: TextStyle(
                  color: FluxForgeTheme.accentOrange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Toggle bindings view
              GestureDetector(
                onTap: () => setState(() => _showBindings = !_showBindings),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _showBindings
                        ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _showBindings
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Text(
                    'BINDINGS',
                    style: TextStyle(
                      color: _showBindings ? FluxForgeTheme.accentBlue : Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // RTPC items
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: rtpcs.length,
            itemBuilder: (context, index) {
              final rtpc = rtpcs[index];
              final isSelected = _selectedRtpcId == rtpc.id;
              return _buildRtpcItem(rtpc, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRtpcItem(RtpcDefinition rtpc, bool isSelected) {
    final value = _localValues[rtpc.id] ?? rtpc.defaultValue;
    final normalizedValue = (value - rtpc.min) / (rtpc.max - rtpc.min);

    return GestureDetector(
      onTap: () => setState(() => _selectedRtpcId = rtpc.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withOpacity(0.15)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and value
            Row(
              children: [
                Text(
                  rtpc.name.replaceAll('_', ' '),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getValueColor(normalizedValue).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    value.toStringAsFixed(2),
                    style: TextStyle(
                      color: _getValueColor(normalizedValue),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Slider
            Row(
              children: [
                Text(
                  rtpc.min.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white38, fontSize: 8),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: _getValueColor(normalizedValue),
                      inactiveTrackColor: FluxForgeTheme.bgDeep,
                      thumbColor: _getValueColor(normalizedValue),
                      overlayColor: _getValueColor(normalizedValue).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: value.clamp(rtpc.min, rtpc.max),
                      min: rtpc.min,
                      max: rtpc.max,
                      onChanged: (newValue) {
                        setState(() => _localValues[rtpc.id] = newValue);
                        _sendRtpcToEngine(rtpc.id, newValue);
                      },
                    ),
                  ),
                ),
                Text(
                  rtpc.max.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white38, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getValueColor(double normalizedValue) {
    if (normalizedValue < 0.33) return FluxForgeTheme.accentGreen;
    if (normalizedValue < 0.66) return FluxForgeTheme.accentOrange;
    return const Color(0xFFFF4040);
  }

  void _sendRtpcToEngine(int rtpcId, double value) {
    try {
      final mw = Provider.of<MiddlewareProvider>(context, listen: false);
      mw.setRtpc(rtpcId, value, interpolationMs: 50);
    } catch (e) {
      debugPrint('[RtpcEditor] Error setting RTPC: $e');
    }
  }

  Widget _buildCurveEditor() {
    if (_selectedRtpcId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 40, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 8),
            const Text(
              'Select an RTPC to edit curve',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.show_chart, size: 14, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 8),
              const Text(
                'CURVE EDITOR',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Curve presets
              _buildCurvePresetButton('Linear', Icons.trending_flat),
              const SizedBox(width: 4),
              _buildCurvePresetButton('Exp', Icons.trending_up),
              const SizedBox(width: 4),
              _buildCurvePresetButton('S-Curve', Icons.timeline),
            ],
          ),
        ),
        // Curve canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: CustomPaint(
              painter: _CurveEditorPainter(
                points: _getDefaultCurvePoints(),
                color: FluxForgeTheme.accentCyan,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        // Target parameter selector
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid.withOpacity(0.5),
          child: Row(
            children: [
              const Text(
                'Target:',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(width: 8),
              _buildTargetChip('Volume', true),
              const SizedBox(width: 4),
              _buildTargetChip('Pitch', false),
              const SizedBox(width: 4),
              _buildTargetChip('LPF', false),
              const SizedBox(width: 4),
              _buildTargetChip('HPF', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurvePresetButton(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        // Apply curve preset
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: Colors.white54),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        // Select target parameter
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentCyan.withOpacity(0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? FluxForgeTheme.accentCyan : Colors.white54,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  List<Offset> _getDefaultCurvePoints() {
    return const [
      Offset(0.0, 0.0),
      Offset(0.25, 0.2),
      Offset(0.5, 0.5),
      Offset(0.75, 0.8),
      Offset(1.0, 1.0),
    ];
  }

  Widget _buildBindingsPanel() {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.link, size: 14, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 8),
              const Text(
                'RTPC BINDINGS',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Add binding button
              GestureDetector(
                onTap: _addBinding,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: FluxForgeTheme.accentGreen),
                      SizedBox(width: 4),
                      Text(
                        'ADD',
                        style: TextStyle(
                          color: FluxForgeTheme.accentGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Bindings list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildBindingItem('Tension → Music LPF', 'Cut frequency based on tension', true),
              _buildBindingItem('Win Multiplier → SFX Volume', 'Louder for bigger wins', true),
              _buildBindingItem('Feature Progress → Music Pitch', '+3 semitones at max', false),
              _buildBindingItem('Cascade Depth → Reverb Mix', 'More reverb for combo', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBindingItem(String name, String description, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive
            ? FluxForgeTheme.accentGreen.withOpacity(0.1)
            : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? FluxForgeTheme.accentGreen.withOpacity(0.5) : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Active indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? FluxForgeTheme.accentGreen : Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            icon: const Icon(Icons.edit, size: 14),
            color: Colors.white38,
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 14),
            color: Colors.white38,
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  void _addBinding() {
    // Show binding creation dialog
  }
}

/// Custom painter for curve editor
class _CurveEditorPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  _CurveEditorPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (points.isEmpty) return;

    // Draw curve
    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final firstPoint = Offset(
      points[0].dx * size.width,
      size.height - points[0].dy * size.height,
    );
    path.moveTo(firstPoint.dx, firstPoint.dy);

    for (int i = 1; i < points.length; i++) {
      final point = Offset(
        points[i].dx * size.width,
        size.height - points[i].dy * size.height,
      );
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, curvePaint);

    // Draw points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final point in points) {
      final pos = Offset(
        point.dx * size.width,
        size.height - point.dy * size.height,
      );
      canvas.drawCircle(pos, 5, pointPaint);
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurveEditorPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
