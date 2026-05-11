/// FLUX_MASTER_TODO 3.6.G — Stress Test Panel
///
/// Compact, expandable panel in the TIMELINE dock-tab that runs
/// large-batch spin simulations via the rf-ab-sim Rust backend and
/// displays results inline.
///
/// Features:
///   - Spin count presets: 10 K / 100 K / 1 M
///   - Voice budget selector (16 / 32 / 48 / 64)
///   - Background simulation via BatchSimService (poll 200 ms)
///   - Progress bar with spin counter
///   - Results: RTP (actual vs target delta), voice budget utilization,
///     event frequency heatmap (top-8 by count), warnings list
///   - Cancel at any time
///
/// Uses the current project's GameModel from SlotLabCoordinator.
/// Falls back to a minimal 5×3 default if no project is loaded.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../services/batch_sim_service.dart';
import '../../theme/fluxforge_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panel widget
// ─────────────────────────────────────────────────────────────────────────────

/// Compact stress-test panel for the Helix timeline dock.
class StressTestPanel extends StatefulWidget {
  const StressTestPanel({super.key});

  @override
  State<StressTestPanel> createState() => _StressTestPanelState();
}

class _StressTestPanelState extends State<StressTestPanel> {
  // Config state
  int _spinCount = 100000;
  int _voiceBudget = 48;

  // Expand/collapse result body
  bool _expanded = false;

  BatchSimService? _svc;

  @override
  void initState() {
    super.initState();
    try {
      _svc = GetIt.instance<BatchSimService>();
      _svc?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _svc?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  // ── Simulation control ────────────────────────────────────────────────────

  void _runOrCancel() {
    final svc = _svc;
    if (svc == null) return;
    if (svc.isRunning) {
      svc.cancelSimulation();
      return;
    }
    final config = _buildConfigJson();
    svc.startSimulation(config);
    setState(() => _expanded = true);
  }

  String _buildConfigJson() {
    // Prefer the live game model from project; fall back to a minimal default.
    final coordinator = GetIt.instance<SlotLabCoordinator>();
    final model = coordinator.currentGameModel;
    final modelJson = model != null ? jsonEncode(model) : _kDefaultGameModelJson;

    return BatchSimConfigBuilder()
        .spinCount(_spinCount)
        .voiceBudget(_voiceBudget)
        .build(modelJson);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc = _svc;
    if (svc == null) return const SizedBox.shrink();

    final isRunning = svc.isRunning;
    final result = svc.lastResult;
    final progress = (svc.currentTask?.progress ?? 0.0).clamp(0.0, 1.0);

    final hasContent = isRunning || result != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF06060A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          _buildHeader(isRunning, result != null, hasContent),

          // ── Progress bar ──────────────────────────────────────────────────
          if (isRunning)
            _buildProgressBar(progress, svc.currentTask?.spinCount ?? _spinCount),

          // ── Result body (expandable) ──────────────────────────────────────
          if (_expanded && result != null) _buildResultBody(result),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isRunning, bool hasResult, bool hasContent) {
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Icon + label
            Icon(
              Icons.speed_rounded,
              size: 11,
              color: isRunning
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              'STRESS TEST',
              style: FluxForgeTheme.dockMono(
                size: 9,
                weight: FontWeight.w700,
                color: isRunning
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),

            // Spin count presets
            if (!isRunning) ...[
              _spinPreset('10K', 10000),
              const SizedBox(width: 3),
              _spinPreset('100K', 100000),
              const SizedBox(width: 3),
              _spinPreset('1M', 1000000),
              const SizedBox(width: 6),
              // Voice budget
              _voicePreset('32', 32),
              const SizedBox(width: 3),
              _voicePreset('48', 48),
              const SizedBox(width: 3),
              _voicePreset('64', 64),
            ] else ...[
              Text(
                '${_formatSpinCount(_spinCount)} spins',
                style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary),
              ),
            ],

            const Spacer(),

            // Expand toggle (only when results exist)
            if (hasResult)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            const SizedBox(width: 4),

            // Run / Cancel button
            _RunButton(isRunning: isRunning, onTap: _runOrCancel),
          ],
        ),
      ),
    );
  }

  Widget _spinPreset(String label, int count) {
    final isActive = _spinCount == count;
    return GestureDetector(
      onTap: () => setState(() => _spinCount = count),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.15)
              : FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle,
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: FluxForgeTheme.dockMono(
            size: 8,
            weight: isActive ? FontWeight.w700 : FontWeight.normal,
            color: isActive ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _voicePreset(String label, int budget) {
    final isActive = _voiceBudget == budget;
    return GestureDetector(
      onTap: () => setState(() => _voiceBudget = budget),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentCyan.withValues(alpha: 0.12)
              : FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4)
                : FluxForgeTheme.borderSubtle,
            width: 0.6,
          ),
        ),
        child: Text(
          '♪$label',
          style: FluxForgeTheme.dockMono(
            size: 8,
            weight: isActive ? FontWeight.w700 : FontWeight.normal,
            color: isActive ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(double progress, int totalSpins) {
    final done = (progress * totalSpins).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: FluxForgeTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation<Color>(FluxForgeTheme.accentGreen),
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 2),
          Text(
            '${_formatSpinCount(done)} / ${_formatSpinCount(totalSpins)} spins  '
            '(${(progress * 100).toStringAsFixed(1)}%)',
            style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBody(BatchSimResult result) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Overview row ─────────────────────────────────────────────────
          Row(
            children: [
              _ResultChip(
                icon: Icons.percent_rounded,
                label: 'RTP',
                value: '${(result.actualRtp * 100).toStringAsFixed(2)}%',
                subValue: _rtpDeltaLabel(result),
                color: _rtpColor(result),
              ),
              const SizedBox(width: 8),
              _ResultChip(
                icon: Icons.graphic_eq_rounded,
                label: 'VOICES',
                value:
                    '${result.voiceBudget.peakVoices}/${result.voiceBudget.voiceBudget}',
                subValue:
                    '${(result.voiceBudget.utilizationPct * 100).toStringAsFixed(0)}%',
                color: result.voiceBudget.isOverBudget
                    ? FluxForgeTheme.accentRed
                    : (result.voiceBudget.utilizationPct > 0.85
                        ? FluxForgeTheme.accentYellow
                        : FluxForgeTheme.accentGreen),
              ),
              const SizedBox(width: 8),
              _ResultChip(
                icon: Icons.hourglass_empty_rounded,
                label: 'DRY',
                value: '${result.drySpellAnalysis.maxDrySpins}',
                subValue: 'max streak',
                color: result.drySpellAnalysis.maxDrySpins > 100
                    ? FluxForgeTheme.accentYellow
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              _ResultChip(
                icon: Icons.timer_outlined,
                label: 'TIME',
                value: _formatMs(result.simDurationMs),
                subValue: '${_formatSpinCount(result.spinCount)} spins',
                color: FluxForgeTheme.textTertiary,
              ),
            ],
          ),

          // ── Event heatmap ─────────────────────────────────────────────────
          if (result.eventFrequencyMap.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SectionHeader(label: 'EVENT HEATMAP'),
            const SizedBox(height: 3),
            _EventHeatmap(frequencies: result.eventFrequencyMap),
          ],

          // ── Warnings ──────────────────────────────────────────────────────
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SectionHeader(label: 'WARNINGS'),
            const SizedBox(height: 3),
            for (final w in result.warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 10,
                        color: FluxForgeTheme.accentYellow.withValues(alpha: 0.8)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        w,
                        style: FluxForgeTheme.dockMono(
                          size: 9,
                          color: FluxForgeTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _rtpColor(BatchSimResult r) {
    if (r.targetRtp <= 0) return FluxForgeTheme.textSecondary;
    final delta = r.rtpDelta.abs();
    if (delta > 0.01) return FluxForgeTheme.accentRed;
    if (delta > 0.005) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentGreen;
  }

  String _rtpDeltaLabel(BatchSimResult r) {
    if (r.targetRtp <= 0) return 'no target';
    final sign = r.rtpDelta >= 0 ? '+' : '';
    return 'Δ$sign${(r.rtpDelta * 100).toStringAsFixed(2)}%';
  }

  static String _formatSpinCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return '$n';
  }

  static String _formatMs(int ms) {
    if (ms >= 60000) return '${(ms / 60000).toStringAsFixed(1)}min';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms}ms';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RunButton extends StatefulWidget {
  final bool isRunning;
  final VoidCallback onTap;

  const _RunButton({required this.isRunning, required this.onTap});

  @override
  State<_RunButton> createState() => _RunButtonState();
}

class _RunButtonState extends State<_RunButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isRunning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: _hovered ? 0.22 : 0.14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: _hovered ? 0.7 : 0.45),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 11,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                widget.isRunning ? 'STOP' : 'RUN',
                style: FluxForgeTheme.dockMono(
                  size: 9,
                  weight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subValue;
  final Color color;

  const _ResultChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.subValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 9, color: color.withValues(alpha: 0.7)),
              const SizedBox(width: 3),
              Text(
                label,
                style: FluxForgeTheme.dockMono(
                  size: 7,
                  color: color.withValues(alpha: 0.6),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: FluxForgeTheme.dockMono(size: 11, weight: FontWeight.w700, color: color),
          ),
          Text(
            subValue,
            style: FluxForgeTheme.dockMono(size: 8, color: color.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: FluxForgeTheme.dockMono(
        size: 8,
        weight: FontWeight.w700,
        color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _EventHeatmap extends StatelessWidget {
  final Map<String, EventFrequency> frequencies;
  const _EventHeatmap({required this.frequencies});

  @override
  Widget build(BuildContext context) {
    // Sort by count descending, take top 8
    final sorted = frequencies.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));
    final top = sorted.take(8).toList();
    final maxCount = top.isEmpty ? 1.0 : top.first.value.count.toDouble();

    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: top.map((entry) {
        final frac = entry.value.count / maxCount;
        final color = _heatColor(frac);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Heat bar (small)
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: frac * 0.7 + 0.1),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.key,
                    style: FluxForgeTheme.dockMono(
                      size: 8, weight: FontWeight.w600, color: color,
                    ),
                  ),
                  Text(
                    '${entry.value.avgPer1000Spins.toStringAsFixed(1)}/1K',
                    style: FluxForgeTheme.dockMono(
                      size: 7, color: color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Heat color: cool (blue) → warm (yellow) → hot (red)
  Color _heatColor(double frac) {
    if (frac > 0.8) return FluxForgeTheme.accentRed;
    if (frac > 0.6) return FluxForgeTheme.accentOrange;
    if (frac > 0.4) return FluxForgeTheme.accentYellow;
    if (frac > 0.2) return FluxForgeTheme.accentGreen;
    return FluxForgeTheme.accentCyan;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal default game model JSON (5×3, no features, default win tiers)
// Used when no project is loaded.
// ─────────────────────────────────────────────────────────────────────────────

const String _kDefaultGameModelJson = r'''
{
  "info": {
    "name": "Stress Test Default",
    "id": "stress_test_default",
    "rtp_target": 96.0,
    "volatility": "medium",
    "hit_frequency": 0.3
  },
  "grid": {
    "reels": 5,
    "rows": 3
  },
  "win_mechanism": "paylines",
  "features": [],
  "win_tiers": {
    "tiers": [
      {"id": "WIN_1", "name": "WIN 1", "min_multiplier": 0.2, "max_multiplier": 1.0},
      {"id": "WIN_2", "name": "WIN 2", "min_multiplier": 1.0, "max_multiplier": 5.0},
      {"id": "WIN_3", "name": "WIN 3", "min_multiplier": 5.0, "max_multiplier": 20.0},
      {"id": "WIN_4", "name": "WIN 4", "min_multiplier": 20.0, "max_multiplier": 100.0},
      {"id": "WIN_5", "name": "WIN 5", "min_multiplier": 100.0, "max_multiplier": 500.0}
    ]
  },
  "mode": "audio_driven"
}
''';
