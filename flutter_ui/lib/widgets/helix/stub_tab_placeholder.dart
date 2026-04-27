/// StubTabPlaceholder — SPRINT 1 SPEC-07.
///
/// Replaces empty Container() / "Coming soon" text in HELIX dock tabs that
/// are reserved for future phases. Shows the user *why* the tab is empty,
/// what's coming, and when.
///
/// Used for SFX, BT, DNA, AI, CLOUD, A/B dock tabs that are placeholders
/// for Phase 4–7 features.
library;

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class StubTabPlaceholder extends StatelessWidget {
  /// Tab name in CAPS — e.g. "SFX", "AI", "CLOUD".
  final String tabName;

  /// One- or two-sentence description of what the tab will become.
  final String description;

  /// Phase / quarter estimate string — e.g. "Phase 5 · Q3 2026".
  final String estimatedPhase;

  /// Up to 4 planned feature bullets.
  final List<String> plannedFeatures;

  /// Icon shown in the gold gradient circle at the top.
  final IconData icon;

  const StubTabPlaceholder({
    super.key,
    required this.tabName,
    required this.description,
    required this.estimatedPhase,
    required this.plannedFeatures,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon in gold gradient circle
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        FluxForgeTheme.brandGoldDark,
                        FluxForgeTheme.brandGold,
                        FluxForgeTheme.brandGoldBright,
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: FluxForgeTheme.brandGold.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 30, color: FluxForgeTheme.bgVoid),
                ),
              ),
              const SizedBox(height: 20),

              // Tab name
              Center(
                child: Text(
                  tabName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: FluxForgeTheme.brandGold,
                    letterSpacing: 4.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Description (1-2 sentences)
              Center(
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: FluxForgeTheme.textSecondary,
                    height: 1.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Estimated phase chip
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.brandGoldDark.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: FluxForgeTheme.brandGold.withValues(alpha: 0.35),
                      width: 0.6,
                    ),
                  ),
                  child: Text(
                    estimatedPhase,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: FluxForgeTheme.brandGoldBright,
                      letterSpacing: 1.6,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Subtle divider
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      FluxForgeTheme.brandGold.withValues(alpha: 0.32),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Planned features list
              ...plannedFeatures.take(4).map((feat) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                        color: FluxForgeTheme.brandGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feat,
                        style: const TextStyle(
                          fontSize: 11,
                          color: FluxForgeTheme.textPrimary,
                          height: 1.4,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 22),

              // "Coming in" badge
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 13,
                      color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'COMING IN $estimatedPhase',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.85),
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Curated stub-tab specs — single source of truth for HELIX dock placeholders.
class HelixStubTabs {
  static const sfx = StubTabPlaceholder(
    tabName: 'SFX',
    description: 'Procedural SFX pipeline — generate sfx_reel_stop, sfx_coin, '
        'sfx_bonus from physical parameters (mass, velocity, material).',
    estimatedPhase: 'PHASE 5 · Q3 2026',
    icon: Icons.graphic_eq_rounded,
    plannedFeatures: [
      'Foley sandbox with physical simulator (ball drop, water splash, glass)',
      'Stage-aware SFX template library (per win tier, per feature)',
      'One-click variation generator (10 alternates per asset)',
      'AudioSeal watermark on every generated sample',
    ],
  );

  static const bt = StubTabPlaceholder(
    tabName: 'BT',
    description: 'Behavior Tree visual editor — drag-drop logic for slot '
        'mechanics without writing code.',
    estimatedPhase: 'PHASE 4 · Q3 2026',
    icon: Icons.account_tree_rounded,
    plannedFeatures: [
      'Visual node editor for stage transitions and gates',
      'Live simulation with random / forced outcomes',
      'Compliance-safe templates (UKGC / MGA pre-validated)',
      'Export to runtime BT format for embedded cabinets',
    ],
  );

  static const dna = StubTabPlaceholder(
    tabName: 'DNA',
    description: 'Slot Sound DNA analysis — spectral fingerprint, automatic '
        'stage classification, cross-project style matching.',
    estimatedPhase: 'PHASE 4 · Q4 2026',
    icon: Icons.fingerprint_rounded,
    plannedFeatures: [
      'Per-asset spectral fingerprint (Sonic DNA Layer 2/3)',
      'Auto-classify drag-and-dropped audio to stage with confidence score',
      'Style fingerprint export (.style file) for marketplace',
      'Cross-project "this sounds like Wrath of Olympus" detection',
    ],
  );

  static const ai = StubTabPlaceholder(
    tabName: 'AI',
    description: 'Corti Copilot v1 — voice authoring, gap detection, mix '
        'suggestions, error prevention. Local LLM, zero cloud dependency.',
    estimatedPhase: 'PHASE 4 · Q1 2027',
    icon: Icons.psychology_alt_rounded,
    plannedFeatures: [
      'Voice commands: "solo voice bus", "audition next win tier", "export MGA manifest"',
      'Generative mix suggestions with reversible Action diff',
      'Gap detection ("12 files match FREE_SPIN_START, top 3 confidence")',
      'Predictive automation from manual gesture history',
    ],
  );

  static const cloud = StubTabPlaceholder(
    tabName: 'CLOUD',
    description: 'Multi-studio sync — real-time collaborative authoring via '
        'CRDT, cloud asset library, presence indicators.',
    estimatedPhase: 'PHASE 7 · Q2 2027',
    icon: Icons.cloud_sync_rounded,
    plannedFeatures: [
      'Yjs / Automerge 2.0 CRDT shared sessions',
      'WebRTC transport for live edits + voice chat (LiveKit)',
      'Roles + permissions (composer / sound designer / QA read-only)',
      'Comment threads anchored to timeline regions',
    ],
  );

  static const ab = StubTabPlaceholder(
    tabName: 'A/B',
    description: 'Live A/B testing — 2 mix variants in production, automatic '
        'winner selection from player retention metrics.',
    estimatedPhase: 'PHASE 5 · Q1 2027',
    icon: Icons.compare_arrows_rounded,
    plannedFeatures: [
      'Side-by-side mix variant authoring with shared timeline',
      'Anonymous opt-in player retention telemetry per variant',
      'Statistical significance gating (Bayesian, configurable confidence)',
      'Automatic promote-winner workflow',
    ],
  );
}
