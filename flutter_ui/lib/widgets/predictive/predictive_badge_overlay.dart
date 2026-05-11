/// FAZA 4.4.2 — Predictive Drag Overlay
///
/// `PredictiveBadgeOverlay` — reusable widget koji se postavlja kao Stack
/// child iznad bilo kog `DragTarget` builder-a. Prima current candidate
/// data path(s) iz DragTarget callback-a, analizira fajl preko
/// `PredictiveAnalyzer`, i prikazuje `PredictiveConfidenceBadge`.
///
/// Korišćenje (npr. unutar composite event DragTarget):
///
/// ```dart
/// DragTarget<String>(
///   onAcceptWithDetails: (d) => assignAudio(d.data),
///   builder: (ctx, candidateData, _) {
///     return Stack(children: [
///       _buildEventRow(),
///       if (candidateData.isNotEmpty)
///         Positioned(
///           top: 4, right: 4,
///           child: PredictiveBadgeOverlay(
///             candidatePath: candidateData.first,
///             stageHint: event.stageName,
///           ),
///         ),
///     ]);
///   },
/// )
/// ```
///
/// Throttle: cache hit < 1µs (LRU), miss ~5-50ms (FFI). Async future ne
/// blokira drag gesture frame.
///
/// Auto-cleanup: kada `candidatePath` postane null/empty (drag leave),
/// widget se sakriva i otpušta stari Future. `_mounted` guard sprečava
/// setState posle dispose-a.
library;

import 'package:flutter/widgets.dart';

import '../../providers/slot_lab/spectral_dna_classifier.dart';
import '../../services/predictive/predictive_analyzer.dart';
import 'predictive_confidence_badge.dart';

class PredictiveBadgeOverlay extends StatefulWidget {
  /// Trenutni path koji se vuče (iz `DragTarget.builder` candidateData).
  /// null/empty → badge sakriven.
  final String? candidatePath;

  /// Očekivani stage target. Koristi se za match/mismatch styling.
  final String? stageHint;

  /// Opciono: cap široki badge ako parent nije ograničen.
  final double maxWidth;

  const PredictiveBadgeOverlay({
    super.key,
    required this.candidatePath,
    this.stageHint,
    this.maxWidth = 220.0,
  });

  @override
  State<PredictiveBadgeOverlay> createState() => _PredictiveBadgeOverlayState();
}

class _PredictiveBadgeOverlayState extends State<PredictiveBadgeOverlay> {
  StageCandidate? _candidate;
  String? _analyzedPath; // path koji je dao trenutni _candidate

  @override
  void initState() {
    super.initState();
    _maybeAnalyze();
  }

  @override
  void didUpdateWidget(covariant PredictiveBadgeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidatePath != widget.candidatePath ||
        oldWidget.stageHint != widget.stageHint) {
      _maybeAnalyze();
    }
  }

  void _maybeAnalyze() {
    final path = widget.candidatePath;
    if (path == null || path.isEmpty) {
      // Drag leave — clear stale prediction.
      if (_candidate != null) {
        setState(() {
          _candidate = null;
          _analyzedPath = null;
        });
      }
      return;
    }

    // Nemamo update ako je već trenutni path analiziran sa istim hint-om.
    if (_analyzedPath == path && _candidate != null) return;

    // Pokreni async — analyzer ima cache + inflight dedup.
    final analyzer = PredictiveAnalyzer.instance;
    final hint = widget.stageHint;
    analyzer.predictFor(path, stageHint: hint).then((candidate) {
      if (!mounted) return;
      // Race guard: ako se path promenio u međuvremenu, ignoriši stari rezultat.
      if (widget.candidatePath != path) return;
      setState(() {
        _candidate = candidate;
        _analyzedPath = path;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _candidate;
    if (c == null || widget.candidatePath == null) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: PredictiveConfidenceBadge(
        candidate: c,
        stageHint: widget.stageHint,
      ),
    );
  }
}
