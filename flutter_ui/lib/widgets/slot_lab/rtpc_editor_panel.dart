/// RTPC Editor Panel for Slot Lab
///
/// Visual editor for Real-Time Parameter Control:
/// - List of all RTPC parameters with current values
/// - Interactive sliders for real-time manipulation
/// - Visual curve editor for RTPC → parameter mapping
/// - Binding management (RTPC → Volume, Pitch, LPF, etc.)
/// - Real-time value visualization with activity indicators

import 'dart:async';
import 'dart:math' as math;
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

class _RtpcEditorPanelState extends State<RtpcEditorPanel> with TickerProviderStateMixin {
  int? _selectedRtpcId;
  bool _showBindings = false;
  RtpcTargetParameter _selectedTarget = RtpcTargetParameter.volume;

  // Local RTPC values for real-time feedback
  final Map<int, double> _localValues = {};

  // Track which RTPCs were recently changed for visual feedback
  final Map<int, DateTime> _recentChanges = {};
  Timer? _activityTimer;

  // P3.1: Value history for sparklines (last 60 samples at ~50ms = 3 seconds)
  final Map<int, List<double>> _valueHistory = {};
  static const int _historyLength = 60;
  Timer? _historyTimer;

  // Curve points per RTPC (editable)
  final Map<int, List<Offset>> _curvePoints = {};

  @override
  void initState() {
    super.initState();
    _initializeLocalValues();
    _initializeCurvePoints();
    _initializeValueHistory();
    _startActivityTimer();
    _startHistoryTimer();
  }

  @override
  void dispose() {
    _activityTimer?.cancel();
    _historyTimer?.cancel();
    super.dispose();
  }

  /// P3.1: Initialize value history for all RTPCs
  void _initializeValueHistory() {
    final rtpcs = SlotRtpcFactory.createAllRtpcs();
    for (final rtpc in rtpcs) {
      final value = _localValues[rtpc.id] ?? rtpc.defaultValue;
      _valueHistory[rtpc.id] = List.filled(_historyLength, value);
    }
  }

  /// P3.1: Start timer to record value history
  void _startHistoryTimer() {
    _historyTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        _updateValueHistory();
      }
    });
  }

  /// P3.1: Update history with current values
  void _updateValueHistory() {
    final rtpcs = SlotRtpcFactory.createAllRtpcs();
    for (final rtpc in rtpcs) {
      final value = _localValues[rtpc.id] ?? rtpc.defaultValue;
      final history = _valueHistory[rtpc.id] ?? [];
      if (history.length >= _historyLength) {
        history.removeAt(0);
      }
      history.add(value);
      _valueHistory[rtpc.id] = history;
    }
    if (mounted) setState(() {});
  }

  void _startActivityTimer() {
    _activityTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        // Clear old activity indicators (older than 500ms)
        final now = DateTime.now();
        _recentChanges.removeWhere((_, time) => now.difference(time).inMilliseconds > 500);
        setState(() {}); // Refresh UI
      }
    });
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

  void _initializeCurvePoints() {
    // Default linear curve for each RTPC
    final defaultCurve = [
      const Offset(0.0, 0.0),
      const Offset(0.25, 0.25),
      const Offset(0.5, 0.5),
      const Offset(0.75, 0.75),
      const Offset(1.0, 1.0),
    ];

    _curvePoints[SlotRtpcIds.winMultiplier] = List.from(defaultCurve);
    _curvePoints[SlotRtpcIds.betLevel] = List.from(defaultCurve);
    _curvePoints[SlotRtpcIds.volatility] = List.from(defaultCurve);
    _curvePoints[SlotRtpcIds.tension] = [
      const Offset(0.0, 0.0),
      const Offset(0.3, 0.1),
      const Offset(0.6, 0.4),
      const Offset(0.8, 0.7),
      const Offset(1.0, 1.0),
    ]; // Exponential for tension
    _curvePoints[SlotRtpcIds.cascadeDepth] = List.from(defaultCurve);
    _curvePoints[SlotRtpcIds.featureProgress] = List.from(defaultCurve);
    _curvePoints[SlotRtpcIds.rollupSpeed] = [
      const Offset(0.0, 0.25),
      const Offset(0.5, 0.5),
      const Offset(1.0, 1.0),
    ]; // Capped minimum
    _curvePoints[SlotRtpcIds.jackpotPool] = List.from(defaultCurve);
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
    final isRecentlyChanged = _recentChanges.containsKey(rtpc.id);

    return GestureDetector(
      onTap: () => setState(() => _selectedRtpcId = rtpc.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withOpacity(0.15)
              : isRecentlyChanged
                  ? _getValueColor(normalizedValue).withOpacity(0.1)
                  : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : isRecentlyChanged
                    ? _getValueColor(normalizedValue).withOpacity(0.5)
                    : FluxForgeTheme.borderSubtle,
            width: isRecentlyChanged ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name and value
            Row(
              children: [
                // Activity indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isRecentlyChanged
                        ? _getValueColor(normalizedValue)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    boxShadow: isRecentlyChanged
                        ? [BoxShadow(color: _getValueColor(normalizedValue), blurRadius: 4)]
                        : null,
                  ),
                ),
                Text(
                  rtpc.name.replaceAll('_', ' '),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Animated value badge
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getValueColor(normalizedValue).withOpacity(isRecentlyChanged ? 0.4 : 0.2),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: isRecentlyChanged
                        ? [BoxShadow(color: _getValueColor(normalizedValue).withOpacity(0.5), blurRadius: 6)]
                        : null,
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
            // Visual bar + slider
            Stack(
              children: [
                // Background bar showing full range
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Value fill bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 50),
                  height: 20,
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: normalizedValue.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getValueColor(normalizedValue).withOpacity(0.6),
                            _getValueColor(normalizedValue).withOpacity(0.3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                // Slider overlay
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: _getValueColor(normalizedValue),
                      overlayColor: _getValueColor(normalizedValue).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: value.clamp(rtpc.min, rtpc.max),
                      min: rtpc.min,
                      max: rtpc.max,
                      onChanged: (newValue) {
                        setState(() {
                          _localValues[rtpc.id] = newValue;
                          _recentChanges[rtpc.id] = DateTime.now();
                        });
                        _sendRtpcToEngine(rtpc.id, newValue);
                      },
                    ),
                  ),
                ),
              ],
            ),
            // Range labels
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rtpc.min.toStringAsFixed(rtpc.min == rtpc.min.roundToDouble() ? 0 : 1),
                    style: const TextStyle(color: Colors.white38, fontSize: 8),
                  ),
                  Text(
                    rtpc.max.toStringAsFixed(rtpc.max == rtpc.max.roundToDouble() ? 0 : 1),
                    style: const TextStyle(color: Colors.white38, fontSize: 8),
                  ),
                ],
              ),
            ),
            // P3.1: Sparkline history visualization
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: CustomPaint(
                size: const Size(double.infinity, 16),
                painter: _RtpcSparklinePainter(
                  values: _valueHistory[rtpc.id] ?? [],
                  minValue: rtpc.min,
                  maxValue: rtpc.max,
                  color: _getValueColor(normalizedValue),
                ),
              ),
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

    final currentValue = _localValues[_selectedRtpcId!] ?? 0.5;
    final rtpcs = SlotRtpcFactory.createAllRtpcs();
    final selectedRtpc = rtpcs.firstWhere((r) => r.id == _selectedRtpcId);
    final normalizedValue = (currentValue - selectedRtpc.min) / (selectedRtpc.max - selectedRtpc.min);
    final curvePoints = _curvePoints[_selectedRtpcId!] ?? _getDefaultCurvePoints();

    // Calculate output value based on curve
    final outputValue = _evaluateCurve(curvePoints, normalizedValue);

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
              Text(
                'CURVE: ${selectedRtpc.name.replaceAll('_', ' ')}',
                style: const TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Curve presets
              _buildCurvePresetButton('Linear', Icons.trending_flat, _applyLinearCurve),
              const SizedBox(width: 4),
              _buildCurvePresetButton('Exp', Icons.trending_up, _applyExpCurve),
              const SizedBox(width: 4),
              _buildCurvePresetButton('S-Curve', Icons.timeline, _applySCurve),
              const SizedBox(width: 4),
              _buildCurvePresetButton('Log', Icons.trending_down, _applyLogCurve),
            ],
          ),
        ),
        // Current value indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: FluxForgeTheme.bgDeep,
          child: Row(
            children: [
              Text('Input: ', style: TextStyle(color: Colors.white54, fontSize: 10)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  normalizedValue.toStringAsFixed(2),
                  style: const TextStyle(color: FluxForgeTheme.accentOrange, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.arrow_forward, size: 12, color: Colors.white38),
              const SizedBox(width: 16),
              Text('Output: ', style: TextStyle(color: Colors.white54, fontSize: 10)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  outputValue.toStringAsFixed(2),
                  style: const TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
              const Spacer(),
              Text(
                'Target: ${_selectedTarget.name.toUpperCase()}',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) => _handleCurveTap(details, constraints.biggest, curvePoints),
                  child: CustomPaint(
                    painter: _CurveEditorPainter(
                      points: curvePoints,
                      color: FluxForgeTheme.accentCyan,
                      currentX: normalizedValue,
                      currentY: outputValue,
                    ),
                    size: constraints.biggest,
                  ),
                );
              },
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
              _buildTargetChip('Volume', RtpcTargetParameter.volume),
              const SizedBox(width: 4),
              _buildTargetChip('Pitch', RtpcTargetParameter.pitch),
              const SizedBox(width: 4),
              _buildTargetChip('LPF', RtpcTargetParameter.lowPassFilter),
              const SizedBox(width: 4),
              _buildTargetChip('HPF', RtpcTargetParameter.highPassFilter),
              const SizedBox(width: 4),
              _buildTargetChip('Pan', RtpcTargetParameter.pan),
            ],
          ),
        ),
      ],
    );
  }

  void _handleCurveTap(TapDownDetails details, Size size, List<Offset> points) {
    // Find closest point and update it
    final tapX = details.localPosition.dx / size.width;
    final tapY = 1.0 - (details.localPosition.dy / size.height);

    // Find closest point index (excluding first and last)
    int closestIdx = 1;
    double closestDist = double.infinity;

    for (int i = 1; i < points.length - 1; i++) {
      final dist = (points[i].dx - tapX).abs();
      if (dist < closestDist) {
        closestDist = dist;
        closestIdx = i;
      }
    }

    // Update point Y value (keep X fixed for simplicity)
    if (_selectedRtpcId != null) {
      setState(() {
        final newPoints = List<Offset>.from(points);
        newPoints[closestIdx] = Offset(points[closestIdx].dx, tapY.clamp(0.0, 1.0));
        _curvePoints[_selectedRtpcId!] = newPoints;
      });
    }
  }

  double _evaluateCurve(List<Offset> points, double x) {
    // Simple linear interpolation between curve points
    for (int i = 0; i < points.length - 1; i++) {
      if (x >= points[i].dx && x <= points[i + 1].dx) {
        final t = (x - points[i].dx) / (points[i + 1].dx - points[i].dx);
        return points[i].dy + t * (points[i + 1].dy - points[i].dy);
      }
    }
    return points.last.dy;
  }

  void _applyLinearCurve() {
    if (_selectedRtpcId == null) return;
    setState(() {
      _curvePoints[_selectedRtpcId!] = [
        const Offset(0.0, 0.0),
        const Offset(0.25, 0.25),
        const Offset(0.5, 0.5),
        const Offset(0.75, 0.75),
        const Offset(1.0, 1.0),
      ];
    });
  }

  void _applyExpCurve() {
    if (_selectedRtpcId == null) return;
    setState(() {
      _curvePoints[_selectedRtpcId!] = [
        const Offset(0.0, 0.0),
        const Offset(0.25, 0.0625),
        const Offset(0.5, 0.25),
        const Offset(0.75, 0.5625),
        const Offset(1.0, 1.0),
      ];
    });
  }

  void _applySCurve() {
    if (_selectedRtpcId == null) return;
    setState(() {
      _curvePoints[_selectedRtpcId!] = [
        const Offset(0.0, 0.0),
        const Offset(0.25, 0.1),
        const Offset(0.5, 0.5),
        const Offset(0.75, 0.9),
        const Offset(1.0, 1.0),
      ];
    });
  }

  void _applyLogCurve() {
    if (_selectedRtpcId == null) return;
    setState(() {
      _curvePoints[_selectedRtpcId!] = [
        const Offset(0.0, 0.0),
        const Offset(0.25, 0.5),
        const Offset(0.5, 0.75),
        const Offset(0.75, 0.875),
        const Offset(1.0, 1.0),
      ];
    });
  }

  Widget _buildCurvePresetButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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

  Widget _buildTargetChip(String label, RtpcTargetParameter target) {
    final isSelected = _selectedTarget == target;
    return GestureDetector(
      onTap: () => setState(() => _selectedTarget = target),
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
      Offset(0.25, 0.25),
      Offset(0.5, 0.5),
      Offset(0.75, 0.75),
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

/// Custom painter for curve editor with real-time value indicator
class _CurveEditorPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double? currentX;
  final double? currentY;

  _CurveEditorPainter({
    required this.points,
    required this.color,
    this.currentX,
    this.currentY,
  });

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

    // Draw axis labels background
    final labelBgPaint = Paint()..color = Colors.black.withOpacity(0.5);

    // Y-axis label (Output)
    canvas.save();
    canvas.translate(12, size.height / 2);
    canvas.rotate(-math.pi / 2);
    final yLabelSpan = TextSpan(
      text: 'OUTPUT',
      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1),
    );
    final yLabelPainter = TextPainter(text: yLabelSpan, textDirection: TextDirection.ltr);
    yLabelPainter.layout();
    yLabelPainter.paint(canvas, Offset(-yLabelPainter.width / 2, 0));
    canvas.restore();

    // X-axis label (Input)
    final xLabelSpan = TextSpan(
      text: 'INPUT',
      style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1),
    );
    final xLabelPainter = TextPainter(text: xLabelSpan, textDirection: TextDirection.ltr);
    xLabelPainter.layout();
    xLabelPainter.paint(canvas, Offset((size.width - xLabelPainter.width) / 2, size.height - 14));

    if (points.isEmpty) return;

    // Draw fill under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0.05)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final fillPath = Path();
    fillPath.moveTo(0, size.height);
    for (final point in points) {
      fillPath.lineTo(
        point.dx * size.width,
        size.height - point.dy * size.height,
      );
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

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

    // Draw current value crosshair and indicator
    if (currentX != null && currentY != null) {
      final currentPosX = currentX! * size.width;
      final currentPosY = size.height - currentY! * size.height;

      // Vertical line (input)
      canvas.drawLine(
        Offset(currentPosX, 0),
        Offset(currentPosX, size.height),
        Paint()
          ..color = FluxForgeTheme.accentOrange.withOpacity(0.5)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // Horizontal line (output)
      canvas.drawLine(
        Offset(0, currentPosY),
        Offset(size.width, currentPosY),
        Paint()
          ..color = FluxForgeTheme.accentGreen.withOpacity(0.5)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // Current point indicator
      canvas.drawCircle(
        Offset(currentPosX, currentPosY),
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(currentPosX, currentPosY),
        8,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(currentPosX, currentPosY),
        4,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }

    // Draw control points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final pos = Offset(
        point.dx * size.width,
        size.height - point.dy * size.height,
      );

      // First and last points are smaller (not editable)
      final radius = (i == 0 || i == points.length - 1) ? 4.0 : 6.0;

      canvas.drawCircle(pos, radius, pointPaint);
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurveEditorPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.currentX != currentX ||
      oldDelegate.currentY != currentY;
}

/// P3.1: Compact sparkline painter for RTPC value history
class _RtpcSparklinePainter extends CustomPainter {
  final List<double> values;
  final double minValue;
  final double maxValue;
  final Color color;

  _RtpcSparklinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // Draw background
    final bgPaint = Paint()..color = Colors.white.withOpacity(0.03);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(2),
      ),
      bgPaint,
    );

    // Draw center line
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );

    // Normalize values
    final range = maxValue - minValue;
    if (range <= 0) return;

    // Create path for sparkline
    final path = Path();
    final fillPath = Path();
    bool first = true;

    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final normalizedY = (values[i] - minValue) / range;
      final y = size.height - (normalizedY * size.height);

      if (first) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Complete fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Draw current value dot at end
    if (values.isNotEmpty) {
      final lastY = size.height - ((values.last - minValue) / range * size.height);
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width - 2, lastY), 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RtpcSparklinePainter oldDelegate) => true;
}
