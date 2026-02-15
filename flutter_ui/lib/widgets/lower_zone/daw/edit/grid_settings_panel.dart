/// DAW Grid/Timeline Settings Panel (P0.1 Extracted)
///
/// Interactive timeline settings:
/// - Tempo (20-999 BPM) with tap-to-edit
/// - Time signature (2-12 / 2,4,8,16) with quick presets
/// - Snap to grid (1/64 - Bar) with visual preview
/// - Triplet grid mode
///
/// Controlled component — all state passed from parent.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1852-2432 + 5326-5385 (~640 LOC total)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GRID SETTINGS PANEL (CONTROLLED COMPONENT)
// ═══════════════════════════════════════════════════════════════════════════

class GridSettingsPanel extends StatefulWidget {
  // Timeline settings (from parent)
  final double tempo;
  final int timeSignatureNumerator;
  final int timeSignatureDenominator;
  final bool snapEnabled;
  final bool tripletGrid;
  final double snapValue; // In beats (0.0625 = 1/64, 1.0 = 1/4, 4.0 = Bar)

  // Callbacks to parent
  final ValueChanged<double>? onTempoChanged;
  final void Function(int numerator, int denominator)? onTimeSignatureChanged;
  final ValueChanged<bool>? onSnapEnabledChanged;
  final ValueChanged<bool>? onTripletGridChanged;
  final ValueChanged<double>? onSnapValueChanged;

  const GridSettingsPanel({
    super.key,
    this.tempo = 120.0,
    this.timeSignatureNumerator = 4,
    this.timeSignatureDenominator = 4,
    this.snapEnabled = true,
    this.tripletGrid = false,
    this.snapValue = 1.0, // 1/4 note default
    this.onTempoChanged,
    this.onTimeSignatureChanged,
    this.onSnapEnabledChanged,
    this.onTripletGridChanged,
    this.onSnapValueChanged,
  });

  @override
  State<GridSettingsPanel> createState() => _GridSettingsPanelState();
}

class _GridSettingsPanelState extends State<GridSettingsPanel>
    with SingleTickerProviderStateMixin {
  // Tap tempo state (Cubase-style: track last 8 taps, 2s reset gap)
  final List<DateTime> _tapTimes = [];
  static const int _maxTaps = 8;
  static const int _resetGapMs = 2000;

  // Pulse animation on each tap
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTapTempo() {
    final now = DateTime.now();

    // Reset if gap > 2 seconds since last tap
    if (_tapTimes.isNotEmpty &&
        now.difference(_tapTimes.last).inMilliseconds > _resetGapMs) {
      _tapTimes.clear();
    }

    _tapTimes.add(now);

    // Keep only last N taps
    while (_tapTimes.length > _maxTaps) {
      _tapTimes.removeAt(0);
    }

    // Pulse animation on every tap
    _pulseController.forward(from: 0);

    // Need at least 2 taps to calculate BPM
    if (_tapTimes.length >= 2) {
      double totalMs = 0;
      for (int i = 1; i < _tapTimes.length; i++) {
        totalMs += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
      }
      final avgMs = totalMs / (_tapTimes.length - 1);
      final bpm = 60000.0 / avgMs;
      if (bpm >= 20 && bpm <= 999) {
        widget.onTempoChanged?.call(double.parse(bpm.toStringAsFixed(1)));
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TIMELINE SETTINGS', Icons.settings),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column: Tempo & Time Signature
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tempo section
                        _buildSubSectionHeader('TEMPO'),
                        const SizedBox(height: 8),
                        _buildTempoControl(context),
                        const SizedBox(height: 16),
                        // Time Signature section
                        _buildSubSectionHeader('TIME SIGNATURE'),
                        const SizedBox(height: 8),
                        _buildTimeSignatureControl(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right column: Grid Settings
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSubSectionHeader('GRID'),
                        const SizedBox(height: 8),
                        // Snap Enable Toggle
                        _buildGridToggle(
                          label: 'Snap to Grid',
                          value: widget.snapEnabled,
                          icon: Icons.grid_on,
                          onChanged: widget.onSnapEnabledChanged,
                        ),
                        const SizedBox(height: 8),
                        // Grid Resolution Selector
                        _buildGridResolutionSelector(),
                        const SizedBox(height: 8),
                        // Triplet Grid Toggle
                        _buildGridToggle(
                          label: 'Triplet Grid',
                          value: widget.tripletGrid,
                          icon: Icons.grid_3x3,
                          onChanged: widget.onTripletGridChanged,
                        ),
                        const SizedBox(height: 12),
                        // Visual indicator of current snap
                        _buildSnapIndicator(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section Headers ───────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSubSectionHeader(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: LowerZoneColors.textMuted,
        letterSpacing: 0.5,
      ),
    );
  }

  // ─── Tempo Controls ────────────────────────────────────────────────────────

  Widget _buildTempoControl(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          // Tempo display (tap to edit)
          Expanded(
            child: GestureDetector(
              onTap: () => _showTempoEditDialog(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, size: 14, color: LowerZoneColors.dawAccent),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.tempo.toStringAsFixed(1)} BPM',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: LowerZoneColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap to edit',
                    style: TextStyle(
                      fontSize: 8,
                      color: LowerZoneColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tap tempo button (Cubase-style: tap repeatedly to set BPM)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnim.value,
              child: child,
            ),
            child: GestureDetector(
              onTap: _handleTapTempo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _tapTimes.length >= 2
                      ? LowerZoneColors.dawAccent.withValues(alpha: 0.15)
                      : LowerZoneColors.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _tapTimes.length >= 2
                        ? LowerZoneColors.dawAccent
                        : LowerZoneColors.border,
                  ),
                ),
                child: Text(
                  'TAP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _tapTimes.length >= 2
                        ? LowerZoneColors.dawAccent
                        : LowerZoneColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTempoEditDialog(BuildContext context) {
    final controller = TextEditingController(
      text: widget.tempo.toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LowerZoneColors.bgMid,
        title: const Text(
          'Set Tempo',
          style: TextStyle(color: LowerZoneColors.textPrimary, fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: LowerZoneColors.textPrimary),
          decoration: const InputDecoration(
            suffixText: 'BPM',
            suffixStyle: TextStyle(color: LowerZoneColors.textMuted),
          ),
          onSubmitted: (value) {
            final newTempo = double.tryParse(value);
            if (newTempo != null && newTempo >= 20 && newTempo <= 999) {
              widget.onTempoChanged?.call(newTempo);
            }
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTempo = double.tryParse(controller.text);
              if (newTempo != null && newTempo >= 20 && newTempo <= 999) {
                widget.onTempoChanged?.call(newTempo);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  // ─── Time Signature Controls ───────────────────────────────────────────────

  Widget _buildTimeSignatureControl() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 14, color: LowerZoneColors.dawAccent),
          const SizedBox(width: 8),
          // Numerator dropdown
          _buildTimeSignatureDropdown(
            value: widget.timeSignatureNumerator,
            items: const [2, 3, 4, 5, 6, 7, 8, 9, 12],
            onChanged: (v) => widget.onTimeSignatureChanged?.call(v, widget.timeSignatureDenominator),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '/',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textPrimary,
              ),
            ),
          ),
          // Denominator dropdown
          _buildTimeSignatureDropdown(
            value: widget.timeSignatureDenominator,
            items: const [2, 4, 8, 16],
            onChanged: (v) => widget.onTimeSignatureChanged?.call(widget.timeSignatureNumerator, v),
          ),
          const Spacer(),
          // Common presets
          _buildTimeSignaturePreset('4/4', 4, 4),
          const SizedBox(width: 4),
          _buildTimeSignaturePreset('3/4', 3, 4),
          const SizedBox(width: 4),
          _buildTimeSignaturePreset('6/8', 6, 8),
        ],
      ),
    );
  }

  Widget _buildTimeSignatureDropdown({
    required int value,
    required List<int> items,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<int>(
        value: items.contains(value) ? value : items.first,
        items: items.map((i) => DropdownMenuItem(
          value: i,
          child: Text(
            '$i',
            style: const TextStyle(color: LowerZoneColors.textPrimary, fontSize: 14),
          ),
        )).toList(),
        onChanged: (v) => v != null ? onChanged(v) : null,
        dropdownColor: LowerZoneColors.bgMid,
        underline: const SizedBox(),
        isDense: true,
        style: const TextStyle(color: LowerZoneColors.textPrimary, fontSize: 14),
      ),
    );
  }

  Widget _buildTimeSignaturePreset(String label, int num, int denom) {
    final isActive = widget.timeSignatureNumerator == num && widget.timeSignatureDenominator == denom;
    return GestureDetector(
      onTap: () => widget.onTimeSignatureChanged?.call(num, denom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
              : LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ─── Grid Controls ─────────────────────────────────────────────────────────

  Widget _buildGridToggle({
    required String label,
    required bool value,
    required IconData icon,
    ValueChanged<bool>? onChanged,
  }) {
    final isEnabled = onChanged != null;
    return GestureDetector(
      onTap: isEnabled ? () => onChanged(!value) : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: value
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.15)
              : LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value
                ? LowerZoneColors.dawAccent.withValues(alpha: 0.5)
                : LowerZoneColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: value ? LowerZoneColors.dawAccent : LowerZoneColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: value ? LowerZoneColors.textPrimary : LowerZoneColors.textSecondary,
                ),
              ),
            ),
            Container(
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                color: value ? LowerZoneColors.dawAccent : LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: value ? Colors.white : LowerZoneColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridResolutionSelector() {
    const resolutions = [
      (0.0625, '1/64'),
      (0.125, '1/32'),
      (0.25, '1/16'),
      (0.5, '1/8'),
      (1.0, '1/4'),
      (2.0, '1/2'),
      (4.0, 'Bar'),
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              const Text(
                'Grid Resolution',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
              ),
              const Spacer(),
              Text(
                _snapValueToLabel(widget.snapValue),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: LowerZoneColors.dawAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Resolution chips
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: resolutions.map((r) {
              final (value, label) = r;
              final isSelected = (widget.snapValue - value).abs() < 0.001;
              return GestureDetector(
                onTap: widget.onSnapValueChanged != null ? () => widget.onSnapValueChanged!(value) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.bgMid,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? Colors.white : LowerZoneColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapIndicator() {
    final snapLabel = _snapValueToLabel(widget.snapValue);
    final isActive = widget.snapEnabled;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive
            ? LowerZoneColors.dawAccent.withValues(alpha: 0.1)
            : LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.3)
              : LowerZoneColors.border,
        ),
      ),
      child: Row(
        children: [
          // Grid preview
          Container(
            width: 60,
            height: 24,
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(3),
            ),
            child: CustomPaint(
              painter: GridPreviewPainter(
                snapValue: widget.snapValue,
                isActive: isActive,
                accentColor: LowerZoneColors.dawAccent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Snap Active' : 'Snap Disabled',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textTertiary,
                  ),
                ),
                Text(
                  isActive
                      ? 'Grid: $snapLabel${widget.tripletGrid ? ' (Triplet)' : ''}'
                      : 'Free positioning enabled',
                  style: const TextStyle(
                    fontSize: 9,
                    color: LowerZoneColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isActive ? Icons.lock : Icons.lock_open,
            size: 16,
            color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textTertiary,
          ),
        ],
      ),
    );
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  String _snapValueToLabel(double value) {
    if (value <= 0.0625) return '1/64';
    if (value <= 0.125) return '1/32';
    if (value <= 0.25) return '1/16';
    if (value <= 0.5) return '1/8';
    if (value <= 1.0) return '1/4';
    if (value <= 2.0) return '1/2';
    return 'Bar';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GRID PREVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class GridPreviewPainter extends CustomPainter {
  final double snapValue;
  final bool isActive;
  final Color accentColor;

  const GridPreviewPainter({
    required this.snapValue,
    required this.isActive,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? accentColor.withValues(alpha: 0.6)
          : LowerZoneColors.textTertiary.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Calculate number of grid lines based on snap value
    // Assume 4 beats visible in preview
    const beatsVisible = 4.0;
    final gridLines = (beatsVisible / snapValue).round().clamp(2, 16);
    final spacing = size.width / gridLines;

    // Draw vertical grid lines
    for (int i = 0; i <= gridLines; i++) {
      final x = i * spacing;
      final isMajor = i % 4 == 0;
      paint.strokeWidth = isMajor ? 1.5 : 0.5;
      paint.color = isActive
          ? accentColor.withValues(alpha: isMajor ? 0.8 : 0.4)
          : LowerZoneColors.textTertiary.withValues(alpha: isMajor ? 0.5 : 0.2);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw a sample "clip" to show snap behavior
    if (isActive) {
      final clipPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      final clipRect = Rect.fromLTWH(
        spacing * 1.5,
        size.height * 0.2,
        spacing * 2,
        size.height * 0.6,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(clipRect, const Radius.circular(2)),
        clipPaint,
      );
    }
  }

  @override
  bool shouldRepaint(GridPreviewPainter oldDelegate) {
    return oldDelegate.snapValue != snapValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.accentColor != accentColor;
  }
}
