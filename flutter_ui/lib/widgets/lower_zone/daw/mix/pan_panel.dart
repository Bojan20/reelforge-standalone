/// DAW Pan Panel (P0.1 Extracted)
///
/// Stereo panning controls with:
/// - Pan law selection (0dB, -3dB, -4.5dB, -6dB)
/// - Mono/Stereo panner modes
/// - Dual pan knobs (Pro Tools style)
/// - Stereo width visualization
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1468-1762 + 3548-3623 (~370 LOC total)
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/mixer_provider.dart';
import '../../../mixer/knob.dart';
import '../../../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PAN PANEL
// ═══════════════════════════════════════════════════════════════════════════

class PanPanel extends StatefulWidget {
  /// Currently selected track ID
  final int? selectedTrackId;

  const PanPanel({super.key, this.selectedTrackId});

  @override
  State<PanPanel> createState() => _PanPanelState();
}

class _PanPanelState extends State<PanPanel> {
  String _selectedPanLaw = '-3dB'; // Default: Equal Power

  @override
  Widget build(BuildContext context) {
    // Try to get MixerProvider
    MixerProvider? mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      // Provider not available
    }

    final selectedChannel = _getSelectedChannel(mixerProvider);
    final pan = selectedChannel?.pan ?? 0.0;
    final panRight = selectedChannel?.panRight ?? 0.0;
    final isStereo = selectedChannel?.isStereo ?? true;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.surround_sound, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              Text(
                isStereo ? 'STEREO PANNER' : 'MONO PANNER',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              if (selectedChannel != null)
                Text(
                  selectedChannel.name,
                  style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
                )
              else
                const Text(
                  'No track selected',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Pan Law selection row
          Row(
            children: [
              const Text(
                'Pan Law:',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
              ),
              const SizedBox(width: 8),
              ..._buildPanLawChips(),
              const Spacer(),
              // Pan law info tooltip
              Tooltip(
                message: _getPanLawDescription(_selectedPanLaw),
                child: const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: LowerZoneColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: _buildPannerWidget(
                pan: pan,
                panRight: panRight,
                isStereo: isStereo,
                onPanChanged: mixerProvider != null && selectedChannel != null
                    ? (newPan) {
                        mixerProvider?.setChannelPan(selectedChannel.id, newPan);
                      }
                    : null,
                onPanRightChanged: mixerProvider != null && selectedChannel != null && isStereo
                    ? (newPan) {
                        mixerProvider?.setChannelPanRight(selectedChannel.id, newPan);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  MixerChannel? _getSelectedChannel(MixerProvider? provider) {
    if (provider == null || widget.selectedTrackId == null) return null;
    try {
      final trackIdStr = widget.selectedTrackId.toString();
      return provider.channels.firstWhere((ch) => ch.id == trackIdStr);
    } catch (_) {
      return null;
    }
  }

  PanLaw _stringToPanLaw(String law) {
    return switch (law) {
      '0dB' => PanLaw.noCenterAttenuation,
      '-3dB' => PanLaw.constantPower,
      '-4.5dB' => PanLaw.compromise,
      '-6dB' => PanLaw.linear,
      _ => PanLaw.constantPower, // Default to -3dB
    };
  }

  void _applyPanLaw(String law) {
    final panLaw = _stringToPanLaw(law);
    final ffi = NativeFFI.instance;
    final mixer = context.read<MixerProvider>();

    // Apply to all audio tracks
    for (final channel in mixer.channels) {
      final trackId = int.tryParse(channel.id) ?? 0;
      ffi.stereoImagerSetPanLaw(trackId, panLaw);
    }
  }

  List<Widget> _buildPanLawChips() {
    const panLaws = ['0dB', '-3dB', '-4.5dB', '-6dB'];
    return panLaws.map((law) {
      final isSelected = _selectedPanLaw == law;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedPanLaw = law);
            _applyPanLaw(law);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? LowerZoneColors.dawAccent : LowerZoneColors.border,
                width: 1,
              ),
            ),
            child: Text(
              law,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : LowerZoneColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  String _getPanLawDescription(String panLaw) {
    return switch (panLaw) {
      '0dB' => 'Linear Pan Law (0dB)\n'
          'No center attenuation. Sum of L+R at center = +6dB.\n'
          'Use for: LCR panning, hard-panned sources.',
      '-3dB' => 'Equal Power Pan Law (-3dB)\n'
          'Center attenuated by -3dB. Constant perceived loudness.\n'
          'Use for: Most mixing scenarios. Industry standard.',
      '-4.5dB' => 'Compromise Pan Law (-4.5dB)\n'
          'Between -3dB and -6dB. Good for dense mixes.\n'
          'Use for: Film/TV, orchestral, ambient.',
      '-6dB' => 'Linear Sum Pan Law (-6dB)\n'
          'Center attenuated by -6dB. Linear voltage sum.\n'
          'Use for: Broadcast, mastering, mono-compatible mixes.',
      _ => 'Pan law controls center channel attenuation.',
    };
  }

  Widget _buildPannerWidget({
    required double pan,
    required double panRight,
    required bool isStereo,
    ValueChanged<double>? onPanChanged,
    ValueChanged<double>? onPanRightChanged,
  }) {
    String panText(double p) {
      if (p.abs() < 0.01) return 'C';
      final percent = (p.abs() * 100).round();
      return p < 0 ? 'L$percent' : 'R$percent';
    }

    if (!isStereo) {
      // Mono: single pan knob
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PAN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textPrimary)),
          const SizedBox(height: 8),
          LargeKnob(
            label: '',
            value: pan,
            bipolar: true,
            size: 72,
            accentColor: LowerZoneColors.dawAccent,
            onChanged: onPanChanged,
          ),
          const SizedBox(height: 4),
          Text(panText(pan), style: const TextStyle(fontSize: 11, color: LowerZoneColors.textSecondary)),
        ],
      );
    }

    // Stereo: dual pan knobs (Pro Tools style)
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Left channel pan
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('L', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            LargeKnob(
              label: '',
              value: pan,
              bipolar: true,
              size: 56,
              accentColor: LowerZoneColors.dawAccent,
              onChanged: onPanChanged,
            ),
            const SizedBox(height: 4),
            Text(panText(pan), style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ],
        ),
        const SizedBox(width: 32),
        // Width indicator
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('WIDTH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: LowerZoneColors.bgDeepest,
                shape: BoxShape.circle,
                border: Border.all(color: LowerZoneColors.border),
              ),
              child: CustomPaint(
                painter: StereoWidthPainter(
                  panL: pan,
                  panR: panRight,
                  color: LowerZoneColors.dawAccent,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${((panRight - pan).abs() * 50 + 50).round()}%',
              style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(width: 32),
        // Right channel pan
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('R', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: LowerZoneColors.textMuted)),
            const SizedBox(height: 8),
            LargeKnob(
              label: '',
              value: panRight,
              bipolar: true,
              size: 56,
              accentColor: LowerZoneColors.dawAccent,
              onChanged: onPanRightChanged,
            ),
            const SizedBox(height: 4),
            Text(panText(panRight), style: const TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO WIDTH PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class StereoWidthPainter extends CustomPainter {
  final double panL;
  final double panR;
  final Color color;

  const StereoWidthPainter({
    required this.panL,
    required this.panR,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    final bgPaint = Paint()
      ..color = LowerZoneColors.bgSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius - 8, bgPaint);

    // Width indicator (pie slice showing stereo image)
    // Map -1..1 to left..right on a semicircle (top half)
    final startAngle = -3.14159 + (panL + 1) * 3.14159 / 2;
    final endAngle = -3.14159 + (panR + 1) * 3.14159 / 2;
    final sweepAngle = endAngle - startAngle;

    if (sweepAngle.abs() > 0.01) {
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius - 8),
          startAngle,
          sweepAngle,
          false,
        )
        ..close();

      canvas.drawPath(path, fillPaint);

      // Edge lines
      final edgePaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final lX = center.dx + (radius - 8) * math.cos(startAngle);
      final lY = center.dy + (radius - 8) * math.sin(startAngle);
      final rX = center.dx + (radius - 8) * math.cos(endAngle);
      final rY = center.dy + (radius - 8) * math.sin(endAngle);

      canvas.drawLine(center, Offset(lX, lY), edgePaint);
      canvas.drawLine(center, Offset(rX, rY), edgePaint);
    }

    // Center marker
    final centerPaint = Paint()
      ..color = LowerZoneColors.textMuted
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 4),
      Offset(center.dx, center.dy - 8),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(StereoWidthPainter oldDelegate) =>
      panL != oldDelegate.panL || panR != oldDelegate.panR;
}
