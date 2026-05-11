/// FAZA 4.4 — Predictive Event Routing
///
/// `PredictiveConfidenceBadge` — glassmorphism kartica koja prikazuje
/// confidence prediction nad DragTarget-om tokom drag-a audio fajla.
///
/// Format: `🎯 87% reel_stop` (high) / `👍 62% reel_stop` (mid) / `🤔 38% …`
///
/// Pozicija: pozicionirana iznad / pored DragTarget-a, glassmorphism
/// pozadina sa color-coded border tier (zelena/žuta/narandžasta).
///
/// Korišćenje:
/// ```dart
/// PredictiveConfidenceBadge(
///   candidate: candidate,        // StageCandidate? — null sakriva badge
///   stageHint: 'REEL_STOP',      // očekivani stage (za "match/mismatch" text)
/// )
/// ```
///
/// Sve TextStyle preko `FluxForgeTheme.dockSans()` tokena — pinned ratchet-om.
library;

import 'package:flutter/material.dart';

import '../../providers/slot_lab/spectral_dna_classifier.dart';
import '../../services/predictive/predictive_analyzer.dart';
import '../../theme/fluxforge_theme.dart';

/// Kompaktni confidence badge (32px high) — pinned tier color + percentage.
class PredictiveConfidenceBadge extends StatelessWidget {
  /// Predikcija — null skriva badge (returns SizedBox.shrink).
  final StageCandidate? candidate;

  /// Očekivani stage (target DragTarget-a). Ako je != `candidate.stage`,
  /// badge dobija "↪" prefix i muted color tier (Boki vidi mismatch).
  final String? stageHint;

  /// Opciono: prikazaj cache age badge ("3s ago") za debug.
  final bool showCacheAge;

  const PredictiveConfidenceBadge({
    super.key,
    required this.candidate,
    this.stageHint,
    this.showCacheAge = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    if (c == null) return const SizedBox.shrink();

    final tier = confidenceTierOf(c.confidence);
    if (tier == ConfidenceTier.unclassified) return const SizedBox.shrink();

    final (color, icon, label) = _tierStyle(tier);
    final mismatch = _isMismatch(c.stage, stageHint);
    // Mismatch desaturira accent — Boki vidi da audio NE match-uje stage.
    final accent = mismatch
        ? FluxForgeTheme.textTertiary
        : color;

    final pct = (c.confidence * 100).round();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.glassFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mismatch ? '↪' : icon,
            style: FluxForgeTheme.dockSans(
              size: 12,
              color: accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$pct%',
            style: FluxForgeTheme.dockMono(
              size: 11,
              color: accent,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _shortenStage(c.stage),
              overflow: TextOverflow.ellipsis,
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: mismatch
                    ? FluxForgeTheme.textTertiary
                    : FluxForgeTheme.textSecondary,
              ),
            ),
          ),
          if (mismatch) ...[
            const SizedBox(width: 4),
            Text(
              '≠ ${_shortenStage(stageHint!)}',
              style: FluxForgeTheme.dockSans(
                size: 9,
                color: FluxForgeTheme.accentRed.withValues(alpha: 0.85),
                weight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: FluxForgeTheme.dockSans(
                size: 9,
                color: accent.withValues(alpha: 0.7),
                weight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tier styling ──────────────────────────────────────────────────────
  (Color, String, String) _tierStyle(ConfidenceTier tier) {
    switch (tier) {
      case ConfidenceTier.high:
        return (FluxForgeTheme.accentGreen, '🎯', 'HIGH');
      case ConfidenceTier.mid:
        return (FluxForgeTheme.accentYellow, '👍', 'MID');
      case ConfidenceTier.low:
        return (FluxForgeTheme.accentOrange, '🤔', 'LOW');
      case ConfidenceTier.unclassified:
        // Branch ne dohvata jer build() već short-circuit-uje, ali Dart
        // exhaustiveness traži pokriće.
        return (FluxForgeTheme.textTertiary, '?', '?');
    }
  }

  bool _isMismatch(String predicted, String? hint) {
    if (hint == null || hint.isEmpty) return false;
    return predicted.toUpperCase() != hint.toUpperCase();
  }

  /// "REEL_STOP_3" → "reel_stop_3" malim za vizuelni mir; trim na 24 char.
  String _shortenStage(String stage) {
    final lower = stage.toLowerCase();
    return lower.length > 24 ? '${lower.substring(0, 23)}…' : lower;
  }
}
