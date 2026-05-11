/// FLUX_MASTER_TODO 3.6.A + 3.6.H — Stage Flow Strip + Per-Spin Profile Compare.
///
/// Slot-native composition view: horizontalna traka sa chunk-om za svaki
/// stage iz `lastStages` (poslednji spin), boja po kategoriji, klik =
/// audition (REGISTRY → triggerStage).  Rešava problem "TIMELINE dok-tab
/// pokazuje DAW timeline koji nema smisla za event-driven slot machine".
///
/// 3.6.H — Per-Spin Profile Compare (dual-track mode):
///   ⊞ REF dugme snima tekuće lastStages kao frozen reference u
///   SlotLabCoordinator.saveAsReference().  Kad referenca postoji, pojavljuje
///   se ⇌ toggle — pritisnuti → dual-track: gornji red = LIVE (tekući spin),
///   donji red = REF (frozen, dimmed), oba skalirana na isti totalMs.
///   Vizuelno odmah vidiš gde se LIVE razlikuje od REF-a (drugačiji raspored
///   REEL_STOP-ova, anticipation window, win presentation timing).
///
/// Layout:
/// ```
/// ┌─ STAGE FLOW · 8 events ────────────── 4250 ms  ⊞ REF  ⇌ ┐
/// │ LIVE  ▓▓▓ ░░░ ▒▒ ███ ▓▓ ░░░░░ ███ ▓▓                    │
/// │ REF   ░░░░░░ ▓▓▓ ▒▒▒ ██ ░░ ███ ▓▓▓                       │
/// └──────────────────────────────────────────────────────────┘
/// ```
///
/// Reactive hookup:
///   * Listenable: `SlotLabCoordinator` (notifies kad stageProvider menja)
///   * Source of truth: `coord.stageProvider.lastStages`
///   * Reference store: `coord.referenceStages` / `coord.saveAsReference()`
///   * Audition handler: `EventRegistry.triggerStage(stageType.toUpperCase())`
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../services/event_registry.dart';
import '../../src/rust/native_ffi.dart' show SlotLabStageEvent;
import '../../theme/fluxforge_theme.dart';

/// Compact horizontal strip rendering the cached `lastStages` sequence.
///
/// Supports single-track (default) and dual-track compare mode (3.6.H).
/// In compare mode, shows two rows: LIVE (current spin) and REF (frozen
/// reference saved by the user via "⊞ REF").
class StageFlowStrip extends StatefulWidget {
  /// Height of the strip in logical pixels.  Default 56 fits inside a
  /// HELIX dock-tab row above the existing ruler.
  final double height;

  /// Optional callback fired when user taps a stage chunk.  When null,
  /// the widget falls back to `EventRegistry.triggerStage(...)` which
  /// re-fires the stage through the audio engine (audition mode).
  final void Function(SlotLabStageEvent stage)? onStageTap;

  const StageFlowStrip({
    super.key,
    this.height = 56,
    this.onStageTap,
  });

  @override
  State<StageFlowStrip> createState() => _StageFlowStripState();
}

class _StageFlowStripState extends State<StageFlowStrip> {
  /// Compare mode: show dual-track LIVE + REF overlay.
  bool _compareMode = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<SlotLabCoordinator>(),
      builder: (context, _) {
        final coord = GetIt.instance<SlotLabCoordinator>();
        final stages = coord.stageProvider.lastStages;
        final ref = coord.referenceStages;

        // Auto-exit compare mode when reference is cleared externally.
        if (ref == null && _compareMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _compareMode = false);
          });
        }

        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgVoid.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: stages.isEmpty
              ? _buildEmptyState()
              : _buildPopulatedStrip(stages, ref, context, coord),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.timeline_rounded,
            size: 14,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Text(
          'No stages cached yet — press SPIN to populate the flow strip.',
          style: FluxForgeTheme.dockSans(
            size: 10,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildPopulatedStrip(
    List<SlotLabStageEvent> stages,
    List<SlotLabStageEvent>? ref,
    BuildContext context,
    SlotLabCoordinator coord,
  ) {
    // Total span — use the broader window when in compare mode so both
    // tracks share the same time axis and are visually comparable.
    final liveMs = stages.isEmpty ? 0.0 : stages.last.timestampMs + 200;
    final refMs = (ref?.isEmpty ?? true) ? 0.0 : ref!.last.timestampMs + 200;
    final totalMs = _compareMode && ref != null
        ? (liveMs > refMs ? liveMs : refMs)
        : liveMs;

    final totalMsLabel = totalMs.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header row ─────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'STAGE FLOW',
              style: FluxForgeTheme.dockSans(
                size: 9,
                weight: FontWeight.w800,
                letterSpacing: 1.0,
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· ${stages.length} events',
              style: FluxForgeTheme.dockMono(
                size: 8,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const Spacer(),
            Text(
              '$totalMsLabel ms',
              style: FluxForgeTheme.dockMono(
                size: 9,
                color: FluxForgeTheme.textSecondary,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // ⊞ REF — save current spin as reference
            _HeaderButton(
              label: ref != null ? '✕ REF' : '⊞ REF',
              tooltip: ref != null
                  ? 'Clear reference snapshot'
                  : 'Save current spin as reference for compare',
              color: ref != null
                  ? FluxForgeTheme.accentRed.withValues(alpha: 0.8)
                  : FluxForgeTheme.accentCyan.withValues(alpha: 0.8),
              active: ref != null,
              onTap: () {
                if (ref != null) {
                  coord.clearReference();
                  setState(() => _compareMode = false);
                } else {
                  coord.saveAsReference();
                }
              },
            ),
            // ⇌ compare toggle — only when reference exists
            if (ref != null) ...[
              const SizedBox(width: 4),
              _HeaderButton(
                label: '⇌',
                tooltip: _compareMode
                    ? 'Exit compare mode'
                    : 'Compare LIVE vs REF overlay',
                color: _compareMode
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.9)
                    : FluxForgeTheme.textSecondary.withValues(alpha: 0.6),
                active: _compareMode,
                onTap: () => setState(() => _compareMode = !_compareMode),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        // ── Canvas area ────────────────────────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              if (_compareMode && ref != null) {
                // Dual-track mode: split vertically, 1px gap between rows.
                // ref is flow-narrowed to non-null inside this branch.
                final rowH = (h - 1) / 2;
                return Column(
                  children: [
                    // LIVE track (top)
                    SizedBox(
                      height: rowH,
                      child: Row(
                        children: [
                          _TrackLabel('LIVE', FluxForgeTheme.accentOrange),
                          Expanded(
                            child: _StageFlowCanvas(
                              stages: stages,
                              totalMs: totalMs,
                              width: w - _kTrackLabelWidth,
                              height: rowH,
                              dimmed: false,
                              onTap: (stage) => _handleTap(stage),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.4)),
                    // REF track (bottom) — dimmed + blue-shifted
                    SizedBox(
                      height: rowH,
                      child: Row(
                        children: [
                          _TrackLabel('REF', FluxForgeTheme.accentCyan),
                          Expanded(
                            child: _StageFlowCanvas(
                              stages: ref,
                              totalMs: totalMs,
                              width: w - _kTrackLabelWidth,
                              height: rowH,
                              dimmed: true,
                              onTap: (stage) => _handleTap(stage),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Single-track mode (default)
              return _StageFlowCanvas(
                stages: stages,
                totalMs: totalMs,
                width: w,
                height: h,
                dimmed: false,
                onTap: (stage) => _handleTap(stage),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTap(SlotLabStageEvent stage) {
    if (widget.onStageTap != null) {
      widget.onStageTap!(stage);
    } else {
      EventRegistry.instance.triggerStage(stage.stageType.toUpperCase());
    }
  }
}

/// Width reserved for LIVE/REF track labels in compare mode.
const double _kTrackLabelWidth = 30.0;

/// Tiny side label for dual-track rows ("LIVE" / "REF").
class _TrackLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _TrackLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kTrackLabelWidth,
      child: Center(
        child: Text(
          label,
          style: FluxForgeTheme.dockMono(
            size: 7,
            weight: FontWeight.w700,
            color: color.withValues(alpha: 0.75),
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Compact header action button (⊞ REF, ⇌).
class _HeaderButton extends StatefulWidget {
  final String label;
  final String tooltip;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.label,
    required this.tooltip,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      textStyle: FluxForgeTheme.dockMono(size: 10, color: Colors.white),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: widget.active
                  ? widget.color.withValues(alpha: _hover ? 0.22 : 0.12)
                  : (_hover
                      ? widget.color.withValues(alpha: 0.1)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: widget.color.withValues(
                    alpha: widget.active ? (_hover ? 0.75 : 0.5) : (_hover ? 0.45 : 0.25)),
                width: 0.8,
              ),
              boxShadow: _hover
                  ? [BoxShadow(color: widget.color.withValues(alpha: 0.2), blurRadius: 4)]
                  : null,
            ),
            child: Text(
              widget.label,
              style: FluxForgeTheme.dockMono(
                size: 8,
                weight: FontWeight.w700,
                color: widget.color.withValues(alpha: _hover ? 1.0 : 0.85),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CANVAS + CHUNK RENDERING
// ────────────────────────────────────────────────────────────────────────────

class _StageFlowCanvas extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final double totalMs;
  final double width;
  final double height;

  /// When true: chunks are rendered at 40% opacity (REF track in compare mode).
  final bool dimmed;
  final void Function(SlotLabStageEvent stage) onTap;

  const _StageFlowCanvas({
    required this.stages,
    required this.totalMs,
    required this.width,
    required this.height,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (totalMs <= 0 || width <= 0) return const SizedBox.shrink();

    final chunks = <_Chunk>[];
    for (int i = 0; i < stages.length; i++) {
      final start = stages[i].timestampMs;
      final end = (i + 1 < stages.length) ? stages[i + 1].timestampMs : totalMs;
      final chunkWidth = ((end - start) / totalMs * width).clamp(0.0, width);
      chunks.add(_Chunk(stage: stages[i], widthPx: chunkWidth, startMs: start, endMs: end));
    }

    return Row(
      children: chunks.map((c) {
        return _ChunkTile(
          chunk: c,
          height: height,
          dimmed: dimmed,
          onTap: () => onTap(c.stage),
        );
      }).toList(),
    );
  }
}

class _Chunk {
  final SlotLabStageEvent stage;
  final double widthPx;
  final double startMs;
  final double endMs;

  _Chunk({
    required this.stage,
    required this.widthPx,
    required this.startMs,
    required this.endMs,
  });

  double get durationMs => endMs - startMs;
}

class _ChunkTile extends StatefulWidget {
  final _Chunk chunk;
  final double height;
  final bool dimmed;
  final VoidCallback onTap;

  const _ChunkTile({
    required this.chunk,
    required this.height,
    required this.dimmed,
    required this.onTap,
  });

  @override
  State<_ChunkTile> createState() => _ChunkTileState();
}

class _ChunkTileState extends State<_ChunkTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final stageType = widget.chunk.stage.stageType;
    final baseColor = _categoryColor(stageType);
    // In dimmed (REF) mode: desaturate by blending toward textTertiary and
    // reduce opacity so LIVE track reads as dominant.
    final color = widget.dimmed
        ? Color.lerp(baseColor, FluxForgeTheme.textTertiary, 0.35)!
        : baseColor;
    final alphaBase = widget.dimmed ? 0.55 : 1.0;
    final showLabel = widget.chunk.widthPx >= 40;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message:
              '$stageType\n${widget.chunk.startMs.round()} → ${widget.chunk.endMs.round()} ms'
              '\n(${widget.chunk.durationMs.round()} ms)'
              '${widget.dimmed ? '\n[REF snapshot]' : '\nclick to audition'}',
          waitDuration: const Duration(milliseconds: 400),
          textStyle: FluxForgeTheme.dockMono(size: 10, color: Colors.white),
          child: Container(
            width: widget.chunk.widthPx,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: (_hover ? 0.55 : 0.3) * alphaBase),
              border: Border.all(
                color: color.withValues(alpha: (_hover ? 0.95 : 0.6) * alphaBase),
                width: _hover ? 1.0 : 0.6,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: showLabel
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _shortLabel(stageType),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluxForgeTheme.dockMono(
                          size: 8,
                          weight: FontWeight.w700,
                          color: _hover
                              ? Colors.white.withValues(alpha: alphaBase)
                              : color.withValues(alpha: 0.95 * alphaBase),
                        ).copyWith(letterSpacing: 0.3),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// Shorten REEL_STOP_0 → "R0", WIN_PRESENT_END → "WIN END" so chunks
  /// remain readable at small widths.
  static String _shortLabel(String stageType) {
    final s = stageType.toUpperCase();
    if (s.startsWith('REEL_STOP_')) return 'R${s.substring('REEL_STOP_'.length)}';
    if (s == 'REEL_SPIN_LOOP') return 'SPIN';
    if (s == 'REEL_STOP') return 'STOP';
    if (s.startsWith('WIN_PRESENT_')) return 'W${s.substring('WIN_PRESENT_'.length)}';
    if (s.startsWith('ANTICIPATION_TENSION_')) return 'ANT${s.substring('ANTICIPATION_TENSION_'.length)}';
    if (s.startsWith('SCATTER_LAND')) return 'SCAT';
    if (s.startsWith('WILD_LAND')) return 'WILD';
    if (s.startsWith('BIG_WIN')) return 'BIG';
    if (s.startsWith('FREE_SPIN')) return 'FS';
    if (s.startsWith('UI_')) return s.substring(3);
    return s.split('_').first;
  }

  /// Color per stage category — mirrors `_getCategoryForStage` from
  /// SlotLabScreen so timeline chunks read consistently with the spine.
  static Color _categoryColor(String stage) {
    final s = stage.toUpperCase();
    if (s.startsWith('SPIN_') || s.startsWith('REEL_')) return const Color(0xFF4CAF50);
    if (s.startsWith('WIN_') || s.startsWith('ROLLUP_')) return const Color(0xFFFFD700);
    if (s.startsWith('FS_') || s.startsWith('FREE_SPIN')) return const Color(0xFF9C27B0);
    if (s.startsWith('BONUS_')) return const Color(0xFFE91E63);
    if (s.startsWith('CASCADE_') || s.startsWith('TUMBLE_')) return const Color(0xFF00BCD4);
    if (s.startsWith('JACKPOT_')) return const Color(0xFFFF5722);
    if (s.startsWith('UI_') || s.startsWith('BUTTON_')) return const Color(0xFF607D8B);
    if (s.startsWith('MUSIC_') ||
        s.startsWith('AMBIENT_') ||
        s.startsWith('BIG_WIN') ||
        s == 'GAME_START') return const Color(0xFF673AB7);
    if (s.startsWith('SYMBOL_') || s.startsWith('WILD_') || s.startsWith('SCATTER_')) {
      return const Color(0xFF2196F3);
    }
    if (s.startsWith('ANTICIPATION_') || s.startsWith('NEAR_MISS')) return const Color(0xFFF44336);
    return const Color(0xFF9E9E9E);
  }
}
