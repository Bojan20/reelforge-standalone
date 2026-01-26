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

class GridSettingsPanel extends StatelessWidget {
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
                          value: snapEnabled,
                          icon: Icons.grid_on,
                          onChanged: onSnapEnabledChanged,
                        ),
                        const SizedBox(height: 8),
                        // Grid Resolution Selector
                        _buildGridResolutionSelector(),
                        const SizedBox(height: 8),
                        // Triplet Grid Toggle
                        _buildGridToggle(
                          label: 'Triplet Grid',
                          value: tripletGrid,
                          icon: Icons.grid_3x3,
                          onChanged: onTripletGridChanged,
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
                        '${tempo.toStringAsFixed(1)} BPM',
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
          // Tap tempo button
          GestureDetector(
            onTap: () {
              // Tap tempo feature - could track tap intervals
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tap Tempo - keep tapping to set BPM'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: LowerZoneColors.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: const Text(
                'TAP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textSecondary,
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
      text: tempo.toStringAsFixed(1),
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
              onTempoChanged?.call(newTempo);
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
                onTempoChanged?.call(newTempo);
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
            value: timeSignatureNumerator,
            items: const [2, 3, 4, 5, 6, 7, 8, 9, 12],
            onChanged: (v) => onTimeSignatureChanged?.call(v, timeSignatureDenominator),
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
            value: timeSignatureDenominator,
            items: const [2, 4, 8, 16],
            onChanged: (v) => onTimeSignatureChanged?.call(timeSignatureNumerator, v),
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
    final isActive = timeSignatureNumerator == num && timeSignatureDenominator == denom;
    return GestureDetector(
      onTap: () => onTimeSignatureChanged?.call(num, denom),
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
                _snapValueToLabel(snapValue),
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
              final isSelected = (snapValue - value).abs() < 0.001;
              return GestureDetector(
                onTap: onSnapValueChanged != null ? () => onSnapValueChanged!(value) : null,
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
    final snapLabel = _snapValueToLabel(snapValue);
    final isActive = snapEnabled;

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
                snapValue: snapValue,
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
                      ? 'Grid: $snapLabel${tripletGrid ? ' (Triplet)' : ''}'
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
