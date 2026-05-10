/// FLUX_MASTER_TODO 3.6.E — Session Recorder UI panel.
///
/// Pojavi se u TIMELINE dock-tab-u kao kompaktni footer ispod Stage
/// Flow Strip-a.  Pruža:
///
///   - **[Record N]** dugme — pokreće `SessionRecorder.recordSession(N)`
///     gde N user bira (default 50).  Tokom snimanja prikazuje
///     progress bar i spin counter.
///   - **Latest session card** — pošto se snimanje završi, header
///     karakteristika: count, hit rate, session RTP, anticipation
///     density, Best Win badge sa replay handle-om.
///   - **Replay button** na Best Win cell-u — re-fire stages iz
///     `SessionSpinSnapshot` kroz `SessionRecorder.replaySnapshot(...)`
///     (ide kroz isti REPLAY path kao TIMELINE quick-action).
///
/// Compact, sve u jednom 64px row-u.  Future iteration (3.6.F) dodaje
/// "Export Marketing Clip" dugme koji bundlu Best Win u MP4+WAV+JSON.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../services/marketing_clip_exporter.dart';
import '../../services/session_recorder.dart';
import '../../src/rust/native_ffi.dart' show NativeFFI;
import '../../theme/fluxforge_theme.dart';

/// Compact panel for the TIMELINE dock-tab footer.
class SessionRecorderPanel extends StatelessWidget {
  final int defaultSpinCount;
  const SessionRecorderPanel({super.key, this.defaultSpinCount = 50});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionRecorder.instance,
      builder: (context, _) {
        final rec = SessionRecorder.instance;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              _RecordControl(
                rec: rec,
                defaultSpinCount: defaultSpinCount,
              ),
              const SizedBox(width: 12),
              Expanded(child: _LatestSessionRow(rec: rec)),
            ],
          ),
        );
      },
    );
  }
}

class _RecordControl extends StatefulWidget {
  final SessionRecorder rec;
  final int defaultSpinCount;
  const _RecordControl({required this.rec, required this.defaultSpinCount});

  @override
  State<_RecordControl> createState() => _RecordControlState();
}

class _RecordControlState extends State<_RecordControl> {
  late int _spinCount = widget.defaultSpinCount;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    if (rec.isRecording) {
      return _ProgressView(
        current: rec.progressCurrent,
        total: rec.progressTotal,
        onCancel: rec.cancel,
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _SpinCountStepper(
        value: _spinCount,
        onChanged: (v) => setState(() => _spinCount = v),
      ),
      const SizedBox(width: 6),
      _RecordButton(onTap: () => rec.recordSession(spinCount: _spinCount)),
    ]);
  }
}

class _SpinCountStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _SpinCountStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Cycle through 10, 25, 50, 100, 250 — covers quick QA, smoke, and
    // marketing-clip-grade sample sizes without committing to a slider.
    const cycle = [10, 25, 50, 100, 250];
    return GestureDetector(
      onTap: () {
        final idx = cycle.indexOf(value);
        final next = cycle[(idx + 1) % cycle.length];
        onChanged(next);
      },
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A12).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.repeat_rounded, size: 12, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 4),
          Text('$value spins', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            fontWeight: FontWeight.w700,
            color: FluxForgeTheme.accentCyan, letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentRed.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: FluxForgeTheme.accentRed.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.fiber_manual_record_rounded, size: 12,
              color: FluxForgeTheme.accentRed),
          const SizedBox(width: 4),
          const Text('REC', style: TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            fontWeight: FontWeight.w800,
            color: FluxForgeTheme.accentRed, letterSpacing: 0.4)),
        ]),
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onCancel;
  const _ProgressView({
    required this.current,
    required this.total,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : current / total;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: FluxForgeTheme.accentRed.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Animated dot — Material's pulse via Tween isn't worth here;
          // the int counter changing is enough live feedback.
          const Icon(Icons.fiber_manual_record_rounded,
              size: 11, color: FluxForgeTheme.accentRed),
          const SizedBox(width: 4),
          Text('REC $current/$total', style: const TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700,
            color: FluxForgeTheme.accentRed, letterSpacing: 0.3)),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 4,
                backgroundColor: const Color(0xFF1A1A22),
                valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentRed),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onCancel,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 0.8,
            ),
          ),
          child: const Text('CANCEL', style: TextStyle(
            fontFamily: 'monospace', fontSize: 9,
            fontWeight: FontWeight.w700,
            color: FluxForgeTheme.textSecondary, letterSpacing: 0.4)),
        ),
      ),
    ]);
  }
}

class _LatestSessionRow extends StatelessWidget {
  final SessionRecorder rec;
  const _LatestSessionRow({required this.rec});

  @override
  Widget build(BuildContext context) {
    final session = rec.latest;
    if (session == null) {
      return Text(
        'No session recorded — REC button kicks off ${50}-spin batch.',
        style: TextStyle(
          fontFamily: 'monospace', fontSize: 9,
          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
        ),
      );
    }
    final hitRatePct = (session.hitRate * 100).toStringAsFixed(0);
    final rtpPct = session.sessionRtp.toStringAsFixed(1);
    final antiPct = (session.anticipationDensity * 100).toStringAsFixed(0);
    final best = session.bestWin;

    return Row(children: [
      _SessionStat(label: 'spins', value: '${session.spinCount}', color: FluxForgeTheme.accentCyan),
      const SizedBox(width: 8),
      _SessionStat(label: 'hit', value: '$hitRatePct%', color: FluxForgeTheme.accentGreen),
      const SizedBox(width: 8),
      _SessionStat(label: 'RTP', value: '$rtpPct%',
          color: session.sessionRtp >= 95 && session.sessionRtp <= 100
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.accentYellow),
      const SizedBox(width: 8),
      _SessionStat(label: 'anti', value: '$antiPct%', color: FluxForgeTheme.accentOrange),
      const SizedBox(width: 12),
      if (best != null)
        Tooltip(
          message: 'Best Win — score ${best.highlightScore.toStringAsFixed(1)}\n'
              '${best.result.winTierName} · '
              '${best.result.totalWin.toStringAsFixed(2)} on '
              '${best.result.bet.toStringAsFixed(2)} '
              '(×${best.result.winRatio.toStringAsFixed(1)})\n\n'
              'Tap to replay through TIMELINE.',
          waitDuration: const Duration(milliseconds: 350),
          textStyle: const TextStyle(
            fontFamily: 'monospace', fontSize: 10,
            color: Colors.white, height: 1.4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentYellow.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: GestureDetector(
            onTap: () => rec.replaySnapshot(best),
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentYellow.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: FluxForgeTheme.accentYellow.withValues(alpha: 0.55),
                  width: 0.8,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.emoji_events_rounded, size: 12,
                    color: FluxForgeTheme.accentYellow),
                const SizedBox(width: 4),
                Text(best.result.winTierName, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: FluxForgeTheme.accentYellow, letterSpacing: 0.3)),
                const SizedBox(width: 4),
                const Icon(Icons.replay_rounded, size: 11,
                    color: FluxForgeTheme.accentYellow),
              ]),
            ),
          ),
        ),
      // FLUX_MASTER_TODO 0.5 E.1 (Sprint 10) — Marketing Clip Export.
      // Pored "best win" replay badge dodaje se 📦 Export Clip dugme.
      // Stateful child da prikazuje progress + result inline.
      if (best != null) ...[
        const SizedBox(width: 6),
        _ExportClipButton(snapshot: best),
      ],
    ]);
  }
}

/// FLUX_MASTER_TODO 0.5 E.1 — Stateful clip export button.
/// Vizuelna stanja: idle (📦 Export) → exporting (spinner) → success
/// (✓ + folder path tooltip) ili error (⚠ + error tooltip).
class _ExportClipButton extends StatefulWidget {
  final SessionSpinSnapshot snapshot;
  const _ExportClipButton({required this.snapshot});

  @override
  State<_ExportClipButton> createState() => _ExportClipButtonState();
}

class _ExportClipButtonState extends State<_ExportClipButton> {
  bool _exporting = false;
  String? _resultMsg;
  bool _wasSuccess = false;

  Future<void> _onTap() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _resultMsg = null;
    });
    final result = await MarketingClipExporter.instance.exportClip(
      snapshot: widget.snapshot,
      ffi: GetIt.instance<NativeFFI>(),
    );
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _wasSuccess = result.isSuccess;
      _resultMsg = result.isSuccess
          ? '✓ ${result.clip!.folderPath.split('/').last}'
          : '⚠ ${result.error}';
    });
    if (result.isSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: FluxForgeTheme.bgElevated,
          content: Text(
            '📦 Clip exported → ${result.clip!.folderPath}',
            style: const TextStyle(color: FluxForgeTheme.brandGold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _wasSuccess && _resultMsg != null
        ? FluxForgeTheme.accentGreen
        : !_wasSuccess && _resultMsg != null
            ? FluxForgeTheme.accentRed
            : FluxForgeTheme.brandGold;
    return Tooltip(
      message: _resultMsg ??
          'Export 60s WAV + JSON metadata clip bundle for marketing.\n'
              'Output → ~/Library/Application Support/FluxForge Studio/clips/',
      waitDuration: const Duration(milliseconds: 350),
      child: GestureDetector(
        onTap: _exporting ? null : _onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: color.withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_exporting)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(
                _wasSuccess && _resultMsg != null
                    ? Icons.check_rounded
                    : !_wasSuccess && _resultMsg != null
                        ? Icons.warning_amber_rounded
                        : Icons.movie_creation_outlined,
                size: 12,
                color: color,
              ),
            const SizedBox(width: 4),
            Text(
              _exporting ? 'EXPORTING' : 'CLIP',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SessionStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(text: TextSpan(children: [
      TextSpan(text: '$label ', style: TextStyle(
        fontFamily: 'monospace', fontSize: 8,
        color: color.withValues(alpha: 0.5),
        letterSpacing: 0.4)),
      TextSpan(text: value, style: TextStyle(
        fontFamily: 'monospace', fontSize: 10,
        fontWeight: FontWeight.w800,
        color: color)),
    ]));
  }
}
