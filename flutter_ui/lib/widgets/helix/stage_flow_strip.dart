/// FLUX_MASTER_TODO 3.6.A — Stage Flow Strip za HELIX TIMELINE dock-tab.
///
/// Slot-native composition view: horizontalna traka sa chunk-om za svaki
/// stage iz `lastStages` (poslednji spin), boja po kategoriji, klik =
/// audition (REGISTRY → triggerStage).  Rešava problem "TIMELINE dok-tab
/// pokazuje DAW timeline koji nema smisla za event-driven slot machine".
///
/// Layout:
/// ```
/// ┌─ STAGE FLOW (last spin) ──────────────────────────────────── 4250 ms ┐
/// │ ▓▓▓ ░░░ ▒▒ ███ ▓▓ ░░░░░ ███ ▓▓                                       │
/// │ SPIN  REEL  REEL  REEL  REEL  REEL  WIN_  WIN_                       │
/// │ STA…  STOP  STOP  STOP  STOP  STOP  PRES  END                        │
/// └──────────────────────────────────────────────────────────────────────┘
/// ```
///
/// Empty state (no spin yet):
/// ```
/// │  No stages cached yet — press SPIN to populate the flow strip.       │
/// ```
///
/// Reactive hookup:
///   * Listenable: `SlotLabCoordinator` (notifies kad stageProvider menja)
///   * Source of truth: `coord.stageProvider.lastStages`
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
/// Designed to live inside the TIMELINE dock-tab toolbar row OR as a
/// separate banner above the existing DAW-timeline canvas.  Both
/// integrations are first-class — pass [height] to control vertical
/// footprint.
class StageFlowStrip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GetIt.instance<SlotLabCoordinator>(),
      builder: (context, _) {
        final coord = GetIt.instance<SlotLabCoordinator>();
        final stages = coord.stageProvider.lastStages;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF06060A).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: stages.isEmpty
              ? _buildEmptyState()
              : _buildPopulatedStrip(stages, context),
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
    BuildContext context,
  ) {
    // Total span — last stage timestamp + reasonable tail (so the last
    // chunk has visible width even when stages are sparse).
    final totalMs = stages.isEmpty
        ? 0.0
        : stages.last.timestampMs + 200; // 200ms tail for readability
    final totalMsLabel = totalMs.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row with title + total duration.
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
          ],
        ),
        const SizedBox(height: 3),
        // The actual strip — paints chunk per stage scaled to width.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return _StageFlowCanvas(
                stages: stages,
                totalMs: totalMs.toDouble(),
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                onTap: (stage) {
                  if (onStageTap != null) {
                    onStageTap!(stage);
                  } else {
                    // Default: audition through EventRegistry — same path
                    // the JUMP quick-action uses (see helix_screen.dart
                    // case 'timeline_jump_stage').
                    EventRegistry.instance
                        .triggerStage(stage.stageType.toUpperCase());
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StageFlowCanvas extends StatelessWidget {
  final List<SlotLabStageEvent> stages;
  final double totalMs;
  final double width;
  final double height;
  final void Function(SlotLabStageEvent stage) onTap;

  const _StageFlowCanvas({
    required this.stages,
    required this.totalMs,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (totalMs <= 0 || width <= 0) return const SizedBox.shrink();

    // Each chunk is the slice from this stage's timestamp until the
    // next stage's timestamp (last stage runs to the totalMs tail).
    final chunks = <_Chunk>[];
    for (int i = 0; i < stages.length; i++) {
      final start = stages[i].timestampMs;
      final end = (i + 1 < stages.length)
          ? stages[i + 1].timestampMs
          : totalMs;
      final chunkWidth = ((end - start) / totalMs * width)
          .clamp(0.0, width);
      chunks.add(_Chunk(
        stage: stages[i],
        widthPx: chunkWidth,
        startMs: start,
        endMs: end,
      ));
    }

    return Row(
      children: chunks.map((c) {
        return _ChunkTile(
          chunk: c,
          height: height,
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
  final VoidCallback onTap;

  const _ChunkTile({
    required this.chunk,
    required this.height,
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
    final color = _categoryColor(stageType);
    final showLabel = widget.chunk.widthPx >= 40; // below 40px label illegible

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message:
              '$stageType\n${widget.chunk.startMs.round()} → ${widget.chunk.endMs.round()} ms\n(${widget.chunk.durationMs.round()} ms)\nclick to audition',
          waitDuration: const Duration(milliseconds: 400),
          textStyle: FluxForgeTheme.dockMono(
            size: 10,
            color: Colors.white,
          ),
          child: Container(
            width: widget.chunk.widthPx,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: _hover ? 0.45 : 0.25),
              border: Border.all(
                color: color.withValues(alpha: _hover ? 0.9 : 0.55),
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
                              ? Colors.white
                              : color.withValues(alpha: 0.95),
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
    if (s.startsWith('REEL_STOP_')) {
      return 'R${s.substring('REEL_STOP_'.length)}';
    }
    if (s == 'REEL_SPIN_LOOP') return 'SPIN';
    if (s == 'REEL_STOP') return 'STOP';
    if (s.startsWith('WIN_PRESENT_')) {
      return 'W${s.substring('WIN_PRESENT_'.length)}';
    }
    if (s.startsWith('ANTICIPATION_TENSION_')) {
      return 'ANT${s.substring('ANTICIPATION_TENSION_'.length)}';
    }
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
    if (s.startsWith('SPIN_') || s.startsWith('REEL_')) {
      return const Color(0xFF4CAF50); // spin = green
    }
    if (s.startsWith('WIN_') || s.startsWith('ROLLUP_')) {
      return const Color(0xFFFFD700); // win = gold
    }
    if (s.startsWith('FS_') || s.startsWith('FREE_SPIN')) {
      return const Color(0xFF9C27B0); // feature = purple
    }
    if (s.startsWith('BONUS_')) return const Color(0xFFE91E63);
    if (s.startsWith('CASCADE_') || s.startsWith('TUMBLE_')) {
      return const Color(0xFF00BCD4);
    }
    if (s.startsWith('JACKPOT_')) return const Color(0xFFFF5722);
    if (s.startsWith('UI_') || s.startsWith('BUTTON_')) {
      return const Color(0xFF607D8B);
    }
    if (s.startsWith('MUSIC_') ||
        s.startsWith('AMBIENT_') ||
        s.startsWith('BIG_WIN') ||
        s == 'GAME_START') {
      return const Color(0xFF673AB7);
    }
    if (s.startsWith('SYMBOL_') ||
        s.startsWith('WILD_') ||
        s.startsWith('SCATTER_')) {
      return const Color(0xFF2196F3);
    }
    if (s.startsWith('ANTICIPATION_') || s.startsWith('NEAR_MISS')) {
      return const Color(0xFFF44336);
    }
    return const Color(0xFF9E9E9E);
  }
}
