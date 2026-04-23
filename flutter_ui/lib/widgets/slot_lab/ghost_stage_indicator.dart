/// PHASE 10 — Ghost Stage Indicator
///
/// Compact overall-coverage chip that doubles as an expandable gap explorer.
///
/// Closed (collapsed):
///   ┌──────────────────────────────────────────────────────┐
///   │  🫥  142/182 bound  78%  ▰▰▰▰▱  40 gaps   ▸          │
///   └──────────────────────────────────────────────────────┘
///
/// Open (expanded):
///   ┌──────────────────────────────────────────────────────┐
///   │  🫥  142/182 bound  78%  ▰▰▰▰▱  40 gaps   ▾          │
///   ├──────────────────────────────────────────────────────┤
///   │  Spin     ▰▰▰▰▰  18/18                                │
///   │  Win      ▰▰▰▱▱  12/25  — 13 missing  ▸              │
///   │  Feature  ▰▰▱▱▱   6/22  — 16 missing  ▸              │
///   │  ...                                                 │
///   └──────────────────────────────────────────────────────┘
///
/// Each category slice expands to show its missing stage names.
///
/// Drop into any screen that holds a stage→audio assignment map.

library;

import 'package:flutter/material.dart';

import '../../services/audio_gap_analysis_service.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

class GhostStageIndicator extends StatefulWidget {
  /// The current stage → audio-asset assignment map.
  final Map<String, String> audioAssignments;

  /// Optional: override the full stage list (test injection).
  final List<StageDefinition>? stageSource;

  /// Optional: called when user taps a missing stage name, so the caller
  /// can scroll to it in the Assign tab or open a quick-bind dialog.
  final void Function(String stageName)? onMissingStageTap;

  /// Whether the indicator starts expanded.
  final bool initiallyExpanded;

  /// Compact mode — smaller vertical padding for inline toolbars.
  final bool compact;

  const GhostStageIndicator({
    super.key,
    required this.audioAssignments,
    this.stageSource,
    this.onMissingStageTap,
    this.initiallyExpanded = false,
    this.compact = false,
  });

  @override
  State<GhostStageIndicator> createState() => _GhostStageIndicatorState();
}

class _GhostStageIndicatorState extends State<GhostStageIndicator>
    with TickerProviderStateMixin {
  bool _expanded = false;
  final Set<StageCategory> _openCategories = {};

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final report = AudioGapAnalysisService.instance.analyze(
      widget.audioAssignments,
      stageSource: widget.stageSource,
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _coverageColor(report.coverage).withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(report),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _buildBody(report)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ─── Header row ──────────────────────────────────────────────────────────
  Widget _buildHeader(AudioGapReport report) {
    final color = _coverageColor(report.coverage);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 10 : 12,
            vertical:   widget.compact ? 6 : 10,
          ),
          child: Row(
            children: [
              // Ghost glyph — fades to dim as coverage approaches 100%.
              Text(
                report.isFull ? '✨' : '🫥',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 8),
              // "142 / 182 bound"
              Text(
                '${report.boundStages} / ${report.totalStages} bound',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(width: 8),
              // Percentage
              Text(
                '${(report.coverage * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(width: 10),
              // Progress bar
              Expanded(child: _progressBar(report.coverage, color)),
              const SizedBox(width: 10),
              // Missing count pill (only if > 0)
              if (report.missingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentRed.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: FluxForgeTheme.accentRed.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${report.missingCount} gap${report.missingCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: FluxForgeTheme.accentRed,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // Chevron
              AnimatedRotation(
                duration: const Duration(milliseconds: 180),
                turns: _expanded ? 0.25 : 0.0,
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressBar(double coverage, Color color) {
    return Stack(
      children: [
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: coverage.clamp(0.0, 1.0),
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Body (per-category rows) ────────────────────────────────────────────
  Widget _buildBody(AudioGapReport report) {
    if (report.categorySlices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No stages defined',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontFamily: 'SpaceGrotesk',
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(
          color: Colors.white.withValues(alpha: 0.06), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final slice in report.categorySlices)
            _buildCategoryRow(slice),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(AudioGapCategorySlice slice) {
    final open = _openCategories.contains(slice.category);
    final color = Color(slice.category.color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: slice.missingCount == 0
                ? null
                : () => setState(() {
                      if (open) {
                        _openCategories.remove(slice.category);
                      } else {
                        _openCategories.add(slice.category);
                      }
                    }),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 62,
                    child: Text(
                      slice.category.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  // Per-category progress bar
                  Expanded(child: _progressBar(slice.coverage, color)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${slice.bound}/${slice.total}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 74,
                    child: Text(
                      slice.missingCount == 0
                          ? '—'
                          : '${slice.missingCount} missing',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: slice.missingCount == 0
                            ? Colors.white.withValues(alpha: 0.25)
                            : FluxForgeTheme.accentRed.withValues(alpha: 0.75),
                        fontSize: 9.5,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (slice.missingCount > 0)
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 160),
                      turns: open ? 0.25 : 0.0,
                      child: Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open && slice.missing.isNotEmpty
              ? _buildMissingList(slice.missing, color)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildMissingList(List<String> missing, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 2, 4, 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: [
          for (final stage in missing)
            _buildMissingChip(stage, color),
        ],
      ),
    );
  }

  Widget _buildMissingChip(String stage, Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onMissingStageTap == null
            ? null
            : () => widget.onMissingStageTap!(stage),
        borderRadius: BorderRadius.circular(3),
        child: Tooltip(
          message: widget.onMissingStageTap == null
              ? stage
              : 'Tap to open assign for $stage',
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              stage,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 8.5,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Coverage colour: red < 50%, orange < 80%, green ≥ 80%.
  Color _coverageColor(double coverage) {
    if (coverage < 0.5)  return FluxForgeTheme.accentRed;
    if (coverage < 0.8)  return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentGreen;
  }
}
