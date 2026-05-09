/// FLUX_MASTER_TODO 3.6.1 — Audio Coverage Badge za HELIX Omnibar.
///
/// Sticky info pill: koliko stage-ova ima audio assignment od ukupne
/// stage palete.  Format: `🎵 27/56 · 48%`.  Klik otvara tooltip sa
/// breakdown-om po kategoriji (spin / win / feature / ui / music ...).
///
/// Reaguje na:
///   * `SlotLabProjectProvider` — `audioAssignments` mapa promene
///   * `StageConfigurationService` — kad se custom stage doda/registruje
///
/// Boja je adaptive po procentu pokrivenosti:
///   * < 30% → `accentRed` (project je u early state)
///   * 30 – 70% → `accentOrange` (work in progress)
///   * 70 – 99% → `accentYellow` (close to fully sounded)
///   * 100% → `accentGreen` (fully bound, ship-ready)
///
/// Single source of truth — UI bez polling-a, sve kroz dve ChangeNotifier
/// listenable-e koje već postoje.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Compact horizontal pill (height 22px) za Omnibar layout.
///
/// Width is adaptive to content; tooltip provides per-category split
/// without enlarging the resting state.
class AudioCoverageBadge extends StatelessWidget {
  const AudioCoverageBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to BOTH provider notifications so the badge refreshes
    // either when audio assignments change OR when the stage palette
    // grows (e.g. user adds custom stage via win-tier config).
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabProjectProvider>(),
        StageConfigurationService.instance,
      ]),
      builder: (context, _) {
        final proj = GetIt.instance<SlotLabProjectProvider>();
        final cfg = StageConfigurationService.instance;
        final allStages = cfg.getAllStages();
        final assigned = proj.audioAssignments;

        final total = allStages.length;
        final bound = assigned.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => e.key.toUpperCase())
            .toSet()
            .length;

        final pct = total > 0 ? (bound / total) : 0.0;
        final color = _coverageColor(pct);

        // Per-category breakdown for tooltip.
        final byCategory = <String, (int bound, int total)>{};
        for (final s in allStages) {
          final catName = s.category.name;
          final prev = byCategory[catName] ?? (0, 0);
          final stageBound =
              assigned[s.name]?.isNotEmpty ?? false;
          byCategory[catName] = (
            prev.$1 + (stageBound ? 1 : 0),
            prev.$2 + 1,
          );
        }
        final tooltipMsg = _buildTooltipMessage(bound, total, pct, byCategory);

        return Tooltip(
          message: tooltipMsg,
          waitDuration: const Duration(milliseconds: 500),
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: Colors.white,
            height: 1.4,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A12).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: color.withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  '$bound/$total',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                // Mini progress arc — visualizes the same percentage so
                // the user reads coverage at-a-glance without parsing
                // the X/Y fraction first.
                _MiniArc(progress: pct, color: color),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _coverageColor(double pct) {
    if (pct >= 1.0) return FluxForgeTheme.accentGreen;
    if (pct >= 0.7) return FluxForgeTheme.accentYellow;
    if (pct >= 0.3) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  static String _buildTooltipMessage(
    int bound,
    int total,
    double pct,
    Map<String, (int, int)> byCategory,
  ) {
    final pctStr = (pct * 100).toStringAsFixed(0);
    final lines = <String>[
      '🎵 Audio Coverage — $bound / $total stages bound ($pctStr%)',
      '',
    ];
    final sortedCats = byCategory.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    for (final entry in sortedCats) {
      final catName = entry.key;
      final (b, t) = entry.value;
      final pctCat = t > 0 ? ((b / t) * 100).toStringAsFixed(0) : '0';
      lines.add('  $catName: $b/$t  ($pctCat%)');
    }
    if (bound < total) {
      lines.add('');
      lines.add('Tip: Auto-Bind orb (AUDIO dock) → drop folder → fills gaps');
    }
    return lines.join('\n');
  }
}

/// Compact circular progress arc used inside the badge to visualise
/// the coverage percentage without taking horizontal space.
class _MiniArc extends StatelessWidget {
  final double progress; // 0..1
  final Color color;

  const _MiniArc({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: CustomPaint(
        painter: _MiniArcPainter(progress: progress, color: color),
      ),
    );
  }
}

class _MiniArcPainter extends CustomPainter {
  final double progress;
  final Color color;

  _MiniArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 1;

    // Track (full circle, faint)
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc (clockwise from 12-o'clock)
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final sweep = (progress.clamp(0.0, 1.0)) * 6.28318530718;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5707963267948966, // -π/2 (top)
        sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniArcPainter old) =>
      old.progress != progress || old.color != color;
}
