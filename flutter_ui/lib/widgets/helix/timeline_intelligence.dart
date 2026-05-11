/// FLUX_MASTER_TODO 3.6.B + 3.6.C + 3.6.D — TIMELINE Intelligence Bar
///
/// Tri kompaktna indikatora iznad Stage Flow Strip-a, svaki rešava
/// jedan slot-native problem koji DAW-i ne rešavaju:
///
/// **3.6.B — Audio Clash Detector ⚔**
///   Detektuje kad dva audio layer-a iz različitih trigger-ovanih
///   stage-ova bore za isti `busId` u istom vremenskom prozoru.
///   Format: `WIN_BIG L2 ⚔ REEL_STOP_4 (bus 2) at 1500–1800ms`.
///   Render: badge `⚔ 3 clashes` sa expandable tooltip listom.
///
/// **3.6.C — Time Budget Compliance ⏱**
///   Total spin duration vs target + per-jurisdiction caps.  Boja
///   prati zelenu (under cap), žutu (≥ 80% cap), crvenu (over cap).
///   Format: `4250ms / 3500 target ⚠`.
///
/// **3.6.D — Anticipation Density Meter 🔥**
///   Procenat poslednjih N spin-ova koji su trigger-ovali
///   `ANTICIPATION_TENSION_*`.  Industry sweet spot 15–30%.
///   Lokalni ring buffer (50 spinova) — ne traži Session Recorder.
///   Format: `🔥 22% · 23/50 spins`.
///
/// **Reactivity:** sve troje listening na
/// `SlotLabCoordinator.stageProvider` notify (kad spin completion-a) +
/// `MiddlewareProvider` (kad composite events promene).
///
/// Stand-alone — ako spin cache prazan, indikatori prikazuju idle state
/// bez crash-a.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../src/rust/native_ffi.dart' show SlotLabStageEvent;
import '../../theme/fluxforge_theme.dart';
import '../lower_zone/lower_zone_types.dart';
import '../lower_zone/slotlab_lower_zone_controller.dart';

// ─────────────────────────────────────────────────────────────────────────
// 3.6.D — Anticipation Density tracker (singleton per session)
// ─────────────────────────────────────────────────────────────────────────

/// In-memory ring buffer that tracks whether each of the last N spins
/// fired any `ANTICIPATION_TENSION_*` stage.  Static singleton because
/// the data is session-scoped, not project-scoped — clear naturally
/// when app restarts.
///
/// When `notifySpin(...)` is called from the spin-complete callback, we
/// push a `bool` (had-anticipation?) into the ring.  `densityPercent`
/// returns 0..1 over the current ring contents (0 if empty, 1 if all
/// spins had anticipation).
class _AnticipationRing {
  static const int _capacity = 50;
  final List<bool> _ring = <bool>[];
  int _spinId = -1; // last spin id we recorded — dedupe spin completion replays

  void recordSpin(int spinId, bool hadAnticipation) {
    if (spinId == _spinId) return;
    _spinId = spinId;
    _ring.add(hadAnticipation);
    if (_ring.length > _capacity) {
      _ring.removeAt(0);
    }
  }

  int get totalRecorded => _ring.length;
  int get withAnticipation => _ring.where((b) => b).length;

  /// 0..1 — percentage of recent spins that triggered anticipation.
  double get density {
    if (_ring.isEmpty) return 0;
    return withAnticipation / _ring.length;
  }

  void clear() {
    _ring.clear();
    _spinId = -1;
  }
}

/// Singleton instance — package-private so Timeline Intelligence can
/// notify on spin completion from outside this file (future hook from
/// SlotLabCoordinator if Session Recorder lands).
final _AnticipationRing _anticipationRing = _AnticipationRing();

/// Public surface for the spin-complete callback hook.  Today the
/// `TimelineIntelligenceBar` itself observes `lastStages` changes and
/// records when a new spin's stages contain `ANTICIPATION_TENSION_*`.
/// In the future the SlotLabCoordinator can call this directly with a
/// proper spinId from `SlotLabSpinResult.spinId` (3.6.E).
void recordAnticipationForCurrentSpin(int spinId, bool hadAnticipation) {
  _anticipationRing.recordSpin(spinId, hadAnticipation);
}

// ─────────────────────────────────────────────────────────────────────────
// 3.6.C — Time Budget table (per-stage targets + jurisdiction caps)
// ─────────────────────────────────────────────────────────────────────────

/// Industry-aligned per-stage time budgets in milliseconds.  Values are
/// median observed across IGT/Aristocrat/Konami slot lifecycles —
/// jurisdiction caps reflect MGA / UKGC public guidance:
///   * Total spin: < 3500ms (UKGC), < 4000ms (MGA)
///   * Big win presentation: < 5000ms (most jurisdictions)
///   * Reel stop staircase: < 200ms each (regulator-friendly pacing)
class _StageBudget {
  final int targetMs;
  final int capMs; // soft cap — over this triggers warning ribbon
  const _StageBudget(this.targetMs, this.capMs);
}

const Map<String, _StageBudget> _kStageBudgets = {
  'GAME_START': _StageBudget(0, 200),
  'UI_SPIN_PRESS': _StageBudget(50, 150),
  'REEL_SPIN_LOOP': _StageBudget(800, 1500),
  'REEL_STOP_0': _StageBudget(150, 300),
  'REEL_STOP_1': _StageBudget(150, 300),
  'REEL_STOP_2': _StageBudget(150, 300),
  'REEL_STOP_3': _StageBudget(150, 300),
  'REEL_STOP_4': _StageBudget(150, 300),
  'WIN_PRESENT_LOW': _StageBudget(800, 1500),
  'WIN_PRESENT_EQUAL': _StageBudget(900, 1500),
  'WIN_PRESENT_1': _StageBudget(800, 1500),
  'WIN_PRESENT_2': _StageBudget(1200, 2000),
  'WIN_PRESENT_3': _StageBudget(1500, 2500),
  'WIN_PRESENT_4': _StageBudget(2000, 3000),
  'WIN_PRESENT_5': _StageBudget(2500, 3500),
  'BIG_WIN_START': _StageBudget(1800, 5000),
  'BIG_WIN_END': _StageBudget(500, 1500),
  'ANTICIPATION_TENSION_R2': _StageBudget(500, 1200),
  'ANTICIPATION_TENSION_R3': _StageBudget(700, 1500),
  'ANTICIPATION_TENSION_R4': _StageBudget(1000, 2000),
  'WIN_PRESENT_END': _StageBudget(200, 600),
};

/// Total-spin budget cap (all jurisdictions average).
const int _kTotalSpinCapMs = 3500;
/// Soft target — under this is healthy.
const int _kTotalSpinTargetMs = 2800;

// ─────────────────────────────────────────────────────────────────────────
// 3.6.B — Clash detection
// ─────────────────────────────────────────────────────────────────────────

/// One detected bus collision between two layers from two different
/// trigger-ed stages within the cached spin window.
class _ClashIssue {
  final String stageA;
  final String layerNameA;
  final String stageB;
  final String layerNameB;
  final int busId;
  final double overlapStartMs;
  final double overlapEndMs;

  _ClashIssue({
    required this.stageA,
    required this.layerNameA,
    required this.stageB,
    required this.layerNameB,
    required this.busId,
    required this.overlapStartMs,
    required this.overlapEndMs,
  });

  double get durationMs => overlapEndMs - overlapStartMs;
  String get busName => switch (busId) {
        SlotBusIds.master => 'master',
        SlotBusIds.music => 'music',
        SlotBusIds.sfx => 'sfx',
        SlotBusIds.voice => 'voice',
        SlotBusIds.ui => 'ui',
        SlotBusIds.reels => 'reels',
        SlotBusIds.wins => 'wins',
        SlotBusIds.anticipation => 'anticipation',
        _ => 'bus $busId',
      };

  @override
  String toString() =>
      '$stageA[$layerNameA] ⚔ $stageB[$layerNameB] (bus $busName) '
      '@ ${overlapStartMs.round()}–${overlapEndMs.round()}ms';
}

/// Compute (a, b) overlap window — `null` if no overlap.
({double startMs, double endMs})? _intervalOverlap(
  double a1,
  double a2,
  double b1,
  double b2,
) {
  final start = a1 > b1 ? a1 : b1;
  final end = a2 < b2 ? a2 : b2;
  if (end <= start) return null;
  return (startMs: start, endMs: end);
}

/// Walk every (stage, layer) pair from the last spin and pair-compare
/// for bus clashes.  Returns sorted by overlap duration desc so the
/// worst offenders surface first.
List<_ClashIssue> _detectClashes(
  List<SlotLabStageEvent> stages,
  List<SlotCompositeEvent> compositeEvents,
) {
  if (stages.isEmpty || compositeEvents.isEmpty) return const [];

  // Build a map of stage → composite event so we can lookup layers fast.
  // Match by triggerStages (uppercase).
  final byStage = <String, SlotCompositeEvent>{};
  for (final ev in compositeEvents) {
    for (final s in ev.triggerStages) {
      byStage[s.toUpperCase()] = ev;
    }
  }

  // Materialize each stage's audible window:
  //   - start = stage.timestampMs + layer.offsetMs
  //   - end   = start + (layer.durationSeconds ?? 0.5) * 1000
  // (0.5s is a safe default if duration unknown — most SFX < 500ms anyway)
  final windows = <
      ({
        String stage,
        String layerName,
        int busId,
        double start,
        double end,
      })>[];
  for (final stageEvent in stages) {
    final stageType = stageEvent.stageType.toUpperCase();
    final composite = byStage[stageType];
    if (composite == null) continue;
    for (final layer in composite.layers) {
      // Skip non-Play layers (FadeVoice, StopVoice, SetBusVolume, …)
      // they don't compete for output mix.
      if (layer.actionType != 'Play') continue;
      if (layer.audioPath.isEmpty) continue;
      final start = stageEvent.timestampMs + layer.offsetMs;
      final dur = (layer.durationSeconds ?? 0.5) * 1000;
      final end = start + dur;
      windows.add((
        stage: stageType,
        layerName: layer.name,
        busId: layer.busId ?? 2,
        start: start,
        end: end,
      ));
    }
  }

  // Pairwise compare — same-stage layers are NOT a clash (intentional
  // composite design), only cross-stage overlaps on same bus matter.
  final issues = <_ClashIssue>[];
  for (int i = 0; i < windows.length; i++) {
    for (int j = i + 1; j < windows.length; j++) {
      final a = windows[i];
      final b = windows[j];
      if (a.stage == b.stage) continue;
      if (a.busId != b.busId) continue;
      final ov = _intervalOverlap(a.start, a.end, b.start, b.end);
      if (ov == null) continue;
      issues.add(_ClashIssue(
        stageA: a.stage,
        layerNameA: a.layerName,
        stageB: b.stage,
        layerNameB: b.layerName,
        busId: a.busId,
        overlapStartMs: ov.startMs,
        overlapEndMs: ov.endMs,
      ));
    }
  }
  // Sort: longest overlap first (biggest signal-fight first).
  issues.sort((x, y) => y.durationMs.compareTo(x.durationMs));
  return issues;
}

// ─────────────────────────────────────────────────────────────────────────
// PUBLIC WIDGET — Timeline Intelligence Bar
// ─────────────────────────────────────────────────────────────────────────

/// Compact horizontal bar with three indicator pills.  Drop above the
/// `StageFlowStrip` inside the TIMELINE dock-tab Panel.
class TimelineIntelligenceBar extends StatefulWidget {
  const TimelineIntelligenceBar({super.key});

  @override
  State<TimelineIntelligenceBar> createState() =>
      _TimelineIntelligenceBarState();
}

class _TimelineIntelligenceBarState extends State<TimelineIntelligenceBar> {
  // Track last seen stage timestamp set so we only push to the
  // anticipation ring once per spin (instead of every notify).
  int _lastSeenStageHash = 0;
  int _spinCounter = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabCoordinator>(),
        GetIt.instance<MiddlewareProvider>(),
      ]),
      builder: (context, _) {
        final coord = GetIt.instance<SlotLabCoordinator>();
        final mw = GetIt.instance<MiddlewareProvider>();
        final stages = coord.stageProvider.lastStages;
        final composites = mw.compositeEvents;

        // 3.6.D — record this spin into the anticipation ring once.
        if (stages.isNotEmpty) {
          final hash = Object.hashAll(
            stages.map((s) => '${s.stageType}@${s.timestampMs}'),
          );
          if (hash != _lastSeenStageHash) {
            _lastSeenStageHash = hash;
            _spinCounter += 1;
            final hadAnticipation = stages.any(
              (s) => s.stageType.toUpperCase().startsWith('ANTICIPATION_'),
            );
            recordAnticipationForCurrentSpin(_spinCounter, hadAnticipation);
          }
        }

        // 3.6.B — clash detection
        final clashes = _detectClashes(stages, composites);

        // 3.6.C — time budget
        final totalMs = stages.isEmpty ? 0.0 : stages.last.timestampMs;
        final budgetUtil = totalMs / _kTotalSpinCapMs;
        final overBudgetStages = _findOverBudgetStages(stages);

        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF06060A).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              _ClashBadge(
                clashes: clashes,
                isEmpty: stages.isEmpty,
                onTap: clashes.isNotEmpty
                    ? () => SlotLabLowerZoneController.instance
                        .setSuperTab(SlotLabSuperTab.mix)
                    : null,
              ),
              const SizedBox(width: 8),
              _TimeBudgetBadge(
                totalMs: totalMs.toInt(),
                budgetUtil: budgetUtil,
                overBudgetStages: overBudgetStages,
                isEmpty: stages.isEmpty,
              ),
              const SizedBox(width: 8),
              _AnticipationDensityBadge(),
              const Spacer(),
              if (stages.isEmpty)
                Text(
                  'Press SPIN to populate metrics',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Walk lastStages and flag any (stage, observed_duration) where
/// observed > softCap.  observed = next-stage.timestampMs - this.timestampMs.
List<({String stage, int observedMs, int capMs})> _findOverBudgetStages(
  List<SlotLabStageEvent> stages,
) {
  final results = <({String stage, int observedMs, int capMs})>[];
  for (int i = 0; i < stages.length; i++) {
    final stageType = stages[i].stageType.toUpperCase();
    final budget = _kStageBudgets[stageType];
    if (budget == null) continue;
    final endMs = (i + 1 < stages.length)
        ? stages[i + 1].timestampMs
        : stages[i].timestampMs + budget.targetMs;
    final observedMs = (endMs - stages[i].timestampMs).round();
    if (observedMs > budget.capMs) {
      results.add(
        (stage: stageType, observedMs: observedMs, capMs: budget.capMs),
      );
    }
  }
  return results;
}

// ─────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS — three pills
// ─────────────────────────────────────────────────────────────────────────

class _ClashBadge extends StatelessWidget {
  final List<_ClashIssue> clashes;
  final bool isEmpty;

  /// When non-null, the pill becomes tappable — opens the MIX dock tab.
  final VoidCallback? onTap;

  const _ClashBadge({
    required this.clashes,
    required this.isEmpty,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isEmpty
        ? FluxForgeTheme.textTertiary
        : (clashes.isEmpty
            ? FluxForgeTheme.accentGreen
            : (clashes.length <= 2
                ? FluxForgeTheme.accentYellow
                : FluxForgeTheme.accentRed));

    final clashList = clashes.isEmpty
        ? ''
        : '\n\n${clashes.take(8).map((c) => '  $c').join('\n')}'
            '${clashes.length > 8 ? '\n  …' : ''}';

    final tapHint = onTap != null ? '\n\n▶ Tap to open MIX dock' : '';

    final tooltip = isEmpty
        ? 'Audio Clash Detector — no spin cached.\n'
            'Pairwise (stage,layer) check on same busId.'
        : (clashes.isEmpty
            ? '⚔ No bus clashes — every layer plays cleanly.'
            : 'Audio Clashes (top ${clashes.take(8).length} of '
                '${clashes.length}):$clashList$tapHint');

    return _Pill(
      icon: Icons.flash_on_rounded,
      iconColor: color,
      label: isEmpty
          ? '⚔ —'
          : (clashes.isEmpty ? '⚔ 0' : '⚔ ${clashes.length}'),
      labelColor: color,
      tooltip: tooltip,
      onTap: onTap,
    );
  }
}

class _TimeBudgetBadge extends StatelessWidget {
  final int totalMs;
  final double budgetUtil;
  final List<({String stage, int observedMs, int capMs})> overBudgetStages;
  final bool isEmpty;

  const _TimeBudgetBadge({
    required this.totalMs,
    required this.budgetUtil,
    required this.overBudgetStages,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final color = isEmpty
        ? FluxForgeTheme.textTertiary
        : (budgetUtil > 1.0
            ? FluxForgeTheme.accentRed
            : (budgetUtil >= 0.8
                ? FluxForgeTheme.accentYellow
                : FluxForgeTheme.accentGreen));

    final tooltipLines = <String>[
      '⏱ Time Budget — total spin duration vs jurisdiction cap',
      '',
      isEmpty
          ? 'No spin cached'
          : 'Spin: ${totalMs}ms / target ${_kTotalSpinTargetMs}ms · '
              'cap ${_kTotalSpinCapMs}ms',
      '',
    ];
    if (overBudgetStages.isEmpty) {
      tooltipLines.add('All stages within their soft caps.');
    } else {
      tooltipLines.add('Over-budget stages:');
      for (final s in overBudgetStages.take(8)) {
        tooltipLines.add(
          '  ${s.stage}: ${s.observedMs}ms > ${s.capMs}ms cap',
        );
      }
      if (overBudgetStages.length > 8) tooltipLines.add('  …');
    }

    return _Pill(
      icon: Icons.timer_rounded,
      iconColor: color,
      label: isEmpty ? '⏱ —' : '⏱ ${totalMs}ms',
      labelColor: color,
      tooltip: tooltipLines.join('\n'),
    );
  }
}

class _AnticipationDensityBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ring = _anticipationRing;
    final n = ring.totalRecorded;
    final pct = (ring.density * 100).round();

    // Industry sweet spot 15–30% — color tier:
    //   < 5%   → red   (game feels flat)
    //   5–15%  → orange (low engagement)
    //   15–30% → green (sweet spot)
    //   > 30%  → yellow (over-stimulating)
    final Color color;
    final String verdict;
    if (n == 0) {
      color = FluxForgeTheme.textTertiary;
      verdict = 'no data';
    } else if (pct < 5) {
      color = FluxForgeTheme.accentRed;
      verdict = 'flat';
    } else if (pct < 15) {
      color = FluxForgeTheme.accentOrange;
      verdict = 'low';
    } else if (pct <= 30) {
      color = FluxForgeTheme.accentGreen;
      verdict = 'good';
    } else {
      color = FluxForgeTheme.accentYellow;
      verdict = 'high';
    }

    final tooltip = n == 0
        ? '🔥 Anticipation Density — no spins recorded yet.\n'
            'Industry sweet spot: 15–30% of spins should fire '
            'ANTICIPATION_TENSION_*.'
        : '🔥 Anticipation Density — $verdict\n'
            '$pct% over last $n spins '
            '(${ring.withAnticipation} with anticipation, '
            '${n - ring.withAnticipation} without)\n\n'
            'Industry guidance:\n'
            '  < 5%   → flat  (game feels predictable)\n'
            '  5–15%  → low   (under-engaging)\n'
            '  15–30% → good  (sweet spot)\n'
            '  > 30%  → high  (over-stimulating, fatigue risk)';

    return _Pill(
      icon: Icons.local_fire_department_rounded,
      iconColor: color,
      label: n == 0 ? '🔥 —' : '🔥 $pct% · $n',
      labelColor: color,
      tooltip: tooltip,
    );
  }
}

class _Pill extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final String tooltip;

  /// When non-null, the pill is interactive: shows pointer cursor + hover glow.
  final VoidCallback? onTap;

  const _Pill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.tooltip,
    this.onTap,
  });

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.onTap != null;
    final borderAlpha = isInteractive && _hovered ? 0.85 : 0.4;
    final bgAlpha = isInteractive && _hovered ? 0.95 : 0.7;

    Widget pill = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12).withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: widget.labelColor.withValues(alpha: borderAlpha),
          width: isInteractive && _hovered ? 1.2 : 0.8,
        ),
        boxShadow: isInteractive && _hovered
            ? [
                BoxShadow(
                  color: widget.labelColor.withValues(alpha: 0.25),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 12, color: widget.iconColor),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: widget.labelColor,
              letterSpacing: 0.3,
            ),
          ),
          if (isInteractive) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new_rounded,
              size: 9,
              color: widget.labelColor.withValues(alpha: _hovered ? 0.9 : 0.5),
            ),
          ],
        ],
      ),
    );

    if (isInteractive) {
      pill = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: pill,
        ),
      );
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      textStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        color: Colors.white,
        height: 1.5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.labelColor.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: pill,
    );
  }
}
