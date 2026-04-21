/// NeuralBindOrb — futuristički, instant audio bind widget.
///
/// ## Koncept
/// Jedan drag-and-drop ili klik. Nema dialoga. Nema koraka. Nema čekanja.
///
/// ## UX Flow
///   1. Korisnik draga folder iz OS-a direktno na Orb  (desktop_drop)
///      OR klikne Orb → folder picker
///   2. AutoBindEngine.analyze() → < 300ms za 500 fajlova
///   3. Neural flash sheet se pojavi sa rezultatom (bottom sheet, 2s auto-dismiss)
///   4. Jedan tap → primeni  /  ESC → odbaci
///
/// ## Vizuelni sistem
///   - IDLE: pulsing ring + status arc (zelena/siva po match rate-u)
///   - DRAG HOVER: expanded glow, "DROP TO BIND" label
///   - ANALYZING: spinning arc, ikona se menja
///   - DONE: full green fill, check ikona, X/Y broj
///   - ERROR: red flash
library neural_bind_orb;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab_project_provider.dart';
import '../../services/auto_bind/auto_bind_engine.dart';
import '../../services/auto_bind/binding_result.dart';
import '../../services/native_file_picker.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';
import 'auto_bind_dialog_v2.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ORB STATE
// ─────────────────────────────────────────────────────────────────────────────

enum _OrbState { idle, dragHover, analyzing, done, error }

// ─────────────────────────────────────────────────────────────────────────────
// NEURAL BIND ORB
// ─────────────────────────────────────────────────────────────────────────────

/// Compact 28×28 orb widget — entry point za instant audio bind.
///
/// Plasiraj ga u toolbar, pored stage-listera, bilo gde.
/// Koristi [NeuralBindOrb.large] za 48×48 varijantu sa tekstom.
class NeuralBindOrb extends StatefulWidget {
  /// Callback posle uspešnog bind-a. Dobija analizu.
  /// Caller je odgovoran za `SlotLabScreen.triggerAutoBindReload(folderPath)`.
  final void Function(BindingAnalysis analysis, String folderPath)? onBindComplete;

  /// Callback za bus volumes (kad korisnik adjust-uje).
  final void Function(Map<int, double> busVolumes)? onBusVolumesChanged;

  /// Veličina orba u pikselima.
  final double size;

  /// Prikazuje tekst "Auto-Bind" pored orba.
  final bool showLabel;

  const NeuralBindOrb({
    super.key,
    this.onBindComplete,
    this.onBusVolumesChanged,
    this.size = 28,
    this.showLabel = false,
  });

  /// Veća varijanta sa labelom — za toolbar-e sa dosta prostora.
  const NeuralBindOrb.large({
    super.key,
    this.onBindComplete,
    this.onBusVolumesChanged,
  }) : size = 28, showLabel = true;

  @override
  State<NeuralBindOrb> createState() => _NeuralBindOrbState();
}

class _NeuralBindOrbState extends State<NeuralBindOrb>
    with TickerProviderStateMixin {

  // ── ANIMATION ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtl;
  late final AnimationController _spinCtl;
  late final AnimationController _flashCtl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _flashAnim;

  // ── STATE ──────────────────────────────────────────────────────────────────
  _OrbState _state = _OrbState.idle;
  BindingAnalysis? _lastAnalysis;
  String? _lastFolder;
  int _totalStages = 0;
  Timer? _autoDismiss;

  // ── LIFECYCLE ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtl, curve: Curves.easeInOut),
    );

    _spinCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();

    _flashCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtl, curve: Curves.easeOut),
    );

    _totalStages = StageConfigurationService.instance.getAllStages().length;
  }

  @override
  void dispose() {
    _pulseCtl.dispose();
    _spinCtl.dispose();
    _flashCtl.dispose();
    _autoDismiss?.cancel();
    super.dispose();
  }

  // ── DROP HANDLER ──────────────────────────────────────────────────────────

  void _onDropDone(DropDoneDetails details) {
    if (details.files.isEmpty) return;

    // Pronađi prvi direktorijum (ili uzmi parent od prvog fajla)
    String? folderPath;
    for (final xfile in details.files) {
      final path = xfile.path;
      if (Directory(path).existsSync()) {
        folderPath = path;
        break;
      }
    }
    // Fallback: parent directory prvog fajla
    folderPath ??= File(details.files.first.path).parent.path;

    _runInstantBind(folderPath);
  }

  // ── CLICK HANDLER ─────────────────────────────────────────────────────────

  Future<void> _onTap(BuildContext context) async {
    // Ako je done state → otvori full dialog za detalje
    if (_state == _OrbState.done && _lastAnalysis != null) {
      _showNeuralSheet(context);
      return;
    }

    // Inače → folder picker + instant bind
    final path = await NativeFilePicker.pickDirectory(
      title: 'Drop in sounds — Auto-Bind will handle the rest',
    );
    if (path == null || !mounted) return;
    _runInstantBind(path);
  }

  // ── INSTANT BIND ──────────────────────────────────────────────────────────

  void _runInstantBind(String folderPath) {
    if (_state == _OrbState.analyzing) return;
    setState(() => _state = _OrbState.analyzing);

    // Async: analyze + apply, sve u background
    Future.microtask(() {
      try {
        final analysis = AutoBindEngine.analyze(folderPath);
        if (!mounted) return;

        if (analysis.matchedCount == 0) {
          _setError();
          return;
        }

        // Apply transakcijsko
        final provider = GetIt.instance<SlotLabProjectProvider>();
        AutoBindEngine.apply(analysis, provider);

        // Trigger EventRegistry sync
        try {
          final coord = GetIt.instance<SlotLabCoordinator>();
          coord.syncAllEventsToRegistry();
        } catch (_) {}

        _lastAnalysis = analysis;
        _lastFolder = folderPath;

        if (mounted) {
          setState(() => _state = _OrbState.done);
          _flashCtl.forward(from: 0);
          // Callback za sync (caller poziva SlotLabScreen.triggerAutoBindReload)
          widget.onBindComplete?.call(analysis, folderPath);

          _autoDismiss?.cancel();
          // Posle 4s, vrati orb u idle ako sheet nije otvoren
          _autoDismiss = Timer(const Duration(seconds: 4), () {
            if (mounted && _state == _OrbState.done) {
              setState(() => _state = _OrbState.idle);
            }
          });
          // Odmah pokaži neural sheet
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showNeuralSheet(context);
          });
        }
      } catch (e) {
        if (mounted) _setError();
      }
    });
  }

  void _setError() {
    setState(() => _state = _OrbState.error);
    _flashCtl.forward(from: 0);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _state = _OrbState.idle);
    });
  }

  // ── NEURAL SHEET ──────────────────────────────────────────────────────────

  void _showNeuralSheet(BuildContext context) {
    if (_lastAnalysis == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NeuralBindSheet(
        analysis: _lastAnalysis!,
        folderPath: _lastFolder ?? '',
        onBusVolumesChanged: widget.onBusVolumesChanged,
        onOpenFull: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AutoBindDialogV2(),
          );
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _state = _OrbState.dragHover),
      onDragExited: (_) {
        if (_state == _OrbState.dragHover) setState(() => _state = _OrbState.idle);
      },
      onDragDone: _onDropDone,
      child: GestureDetector(
        onTap: () => _onTap(context),
        child: widget.showLabel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildOrb(),
                  const SizedBox(width: 6),
                  _buildLabel(),
                ],
              )
            : _buildOrb(),
      ),
    );
  }

  Widget _buildLabel() {
    final a = _lastAnalysis;
    final label = _state == _OrbState.analyzing
        ? 'Binding...'
        : _state == _OrbState.done && a != null
            ? '${a.uniqueStageCount}/${_totalStages}'
            : _state == _OrbState.dragHover
                ? 'Drop to Bind'
                : 'Auto-Bind';
    final color = _state == _OrbState.done
        ? FluxForgeTheme.accentGreen
        : _state == _OrbState.dragHover
            ? FluxForgeTheme.accentCyan
            : _state == _OrbState.error
                ? FluxForgeTheme.accentRed
                : FluxForgeTheme.accentGreen;

    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: color,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _buildOrb() {
    final s = widget.size;
    return SizedBox(
      width: _state == _OrbState.dragHover ? s * 1.3 : s,
      height: _state == _OrbState.dragHover ? s * 1.3 : s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _spinCtl, _flashAnim]),
        builder: (_, __) => CustomPaint(
          painter: _OrbPainter(
            state: _state,
            pulseValue: _pulseAnim.value,
            spinValue: _spinCtl.value,
            flashValue: _flashAnim.value,
            matchRate: _lastAnalysis?.matchRate ?? 0,
            boundStages: _lastAnalysis?.uniqueStageCount ?? 0,
            totalStages: _totalStages,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORB PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  final _OrbState state;
  final double pulseValue;
  final double spinValue;
  final double flashValue;
  final double matchRate;
  final int boundStages;
  final int totalStages;

  const _OrbPainter({
    required this.state,
    required this.pulseValue,
    required this.spinValue,
    required this.flashValue,
    required this.matchRate,
    required this.boundStages,
    required this.totalStages,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;

    switch (state) {
      case _OrbState.idle:
        _paintIdle(canvas, cx, cy, r);
      case _OrbState.dragHover:
        _paintDragHover(canvas, cx, cy, r);
      case _OrbState.analyzing:
        _paintAnalyzing(canvas, cx, cy, r);
      case _OrbState.done:
        _paintDone(canvas, cx, cy, r);
      case _OrbState.error:
        _paintError(canvas, cx, cy, r);
    }
  }

  void _paintIdle(Canvas canvas, double cx, double cy, double r) {
    // Outer glow ring (pulses)
    final glowPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.08 * pulseValue)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 1.15, glowPaint);

    // Background circle
    final bgPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, bgPaint);

    // Border ring
    final ringPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.25 + 0.2 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, ringPaint);

    // Progress arc (match rate if any)
    if (matchRate > 0) {
      final arcPaint = Paint()
        ..color = const Color(0xFF50FF98).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
        -math.pi / 2,
        2 * math.pi * matchRate,
        false,
        arcPaint,
      );
    }

    // Center icon (auto_fix_high approximation — small lightning bolt)
    _drawIconGlyph(canvas, cx, cy, r * 0.3, const Color(0xFF50FF98).withValues(alpha: 0.8 * pulseValue));
  }

  void _paintDragHover(Canvas canvas, double cx, double cy, double r) {
    // Expanded pulsing ring
    final glowPaint = Paint()
      ..color = const Color(0xFF50D8FF).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r, glowPaint);

    final ringPaint = Paint()
      ..color = const Color(0xFF50D8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r * 0.85, ringPaint);

    // Dashed inner ring
    _drawDashedCircle(canvas, cx, cy, r * 0.65, const Color(0xFF50D8FF).withValues(alpha: 0.5));

    _drawIconGlyph(canvas, cx, cy, r * 0.3, const Color(0xFF50D8FF));
  }

  void _paintAnalyzing(Canvas canvas, double cx, double cy, double r) {
    // Background
    final bgPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, bgPaint);

    // Spinning arc
    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF50FF98).withValues(alpha: 0.9),
        ],
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(spinValue * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), r * 0.78, arcPaint);

    _drawIconGlyph(canvas, cx, cy, r * 0.25, const Color(0xFF50FF98).withValues(alpha: 0.5));
  }

  void _paintDone(Canvas canvas, double cx, double cy, double r) {
    // Flash fill
    if (flashValue > 0) {
      final flashPaint = Paint()
        ..color = const Color(0xFF50FF98).withValues(alpha: flashValue * 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy), r, flashPaint);
    }

    // Solid green fill
    final fillPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, fillPaint);

    // Bright border
    final ringPaint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, ringPaint);

    // Full arc
    final arcPaint = Paint()
      ..color = const Color(0xFF50FF98)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, arcPaint);

    // Check mark
    _drawCheckmark(canvas, cx, cy, r * 0.3, const Color(0xFF50FF98));
  }

  void _paintError(Canvas canvas, double cx, double cy, double r) {
    final alpha = (flashValue * 0.4).clamp(0.0, 0.4);
    final bgPaint = Paint()
      ..color = const Color(0xFFFF5060).withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, bgPaint);

    final ringPaint = Paint()
      ..color = const Color(0xFFFF5060).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r * 0.78, ringPaint);

    _drawX(canvas, cx, cy, r * 0.25, const Color(0xFFFF5060));
  }

  void _drawIconGlyph(Canvas canvas, double cx, double cy, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Wand icon (diagonal + stars)
    final path = Path()
      ..moveTo(cx - r * 0.6, cy + r * 0.6)
      ..lineTo(cx + r * 0.3, cy - r * 0.3);
    canvas.drawPath(path, paint);

    // Sparkle dots
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + r * 0.55, cy - r * 0.55), r * 0.12, dotPaint);
    canvas.drawCircle(Offset(cx + r * 0.1, cy - r * 0.7), r * 0.08, dotPaint);
    canvas.drawCircle(Offset(cx + r * 0.7, cy - r * 0.1), r * 0.08, dotPaint);
  }

  void _drawCheckmark(Canvas canvas, double cx, double cy, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(cx - r * 0.8, cy)
      ..lineTo(cx - r * 0.15, cy + r * 0.7)
      ..lineTo(cx + r * 0.9, cy - r * 0.7);
    canvas.drawPath(path, paint);
  }

  void _drawX(Canvas canvas, double cx, double cy, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - r, cy - r), Offset(cx + r, cy + r), paint);
    canvas.drawLine(Offset(cx + r, cy - r), Offset(cx - r, cy + r), paint);
  }

  void _drawDashedCircle(Canvas canvas, double cx, double cy, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const dashCount = 12;
    const dashAngle = 2 * math.pi / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        i * dashAngle,
        dashAngle * 0.6,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.state != state ||
      old.pulseValue != pulseValue ||
      old.spinValue != spinValue ||
      old.flashValue != flashValue ||
      old.matchRate != matchRate;
}

// ─────────────────────────────────────────────────────────────────────────────
// NEURAL BIND SHEET
// ─────────────────────────────────────────────────────────────────────────────

/// Bottom sheet koji se pojavi posle instant bind-a.
/// Kompaktan, futuristički, auto-dismiss.
class NeuralBindSheet extends StatefulWidget {
  final BindingAnalysis analysis;
  final String folderPath;
  final void Function(Map<int, double>)? onBusVolumesChanged;
  final VoidCallback? onOpenFull;

  const NeuralBindSheet({
    super.key,
    required this.analysis,
    required this.folderPath,
    this.onBusVolumesChanged,
    this.onOpenFull,
  });

  @override
  State<NeuralBindSheet> createState() => _NeuralBindSheetState();
}

class _NeuralBindSheetState extends State<NeuralBindSheet>
    with SingleTickerProviderStateMixin {

  late final AnimationController _entryCtl;
  late final Animation<double> _entryAnim;

  // Stage nodovi — layout data
  late final List<_StageNode> _nodes;
  final _rand = math.Random(42);

  @override
  void initState() {
    super.initState();
    _entryCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _entryAnim = CurvedAnimation(parent: _entryCtl, curve: Curves.easeOutCubic);
    _entryCtl.forward();

    // Build node list from analysis
    _nodes = _buildNodes();
  }

  @override
  void dispose() {
    _entryCtl.dispose();
    super.dispose();
  }

  List<_StageNode> _buildNodes() {
    final nodes = <_StageNode>[];
    final boundStages = widget.analysis.stageGroups.keys.toSet();
    final allStages = StageConfigurationService.instance.getAllStages();

    // Sample ~40 representative stages for visual (not all 182)
    final sample = allStages.length > 48
        ? (List.of(allStages)..shuffle(math.Random(7))).take(48).toList()
        : allStages;

    for (int i = 0; i < sample.length; i++) {
      final stage = sample[i];
      final isBound = boundStages.contains(stage.name);
      // Distributed circular layout
      final angle = (i / sample.length) * 2 * math.pi;
      final radiusNorm = 0.3 + _rand.nextDouble() * 0.35;
      nodes.add(_StageNode(
        stage: stage.name,
        isBound: isBound,
        angle: angle,
        radiusNorm: radiusNorm,
        delay: i * 18,
      ));
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final screenH = MediaQuery.of(context).size.height;

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, (1 - _entryAnim.value) * 60),
        child: Opacity(opacity: _entryAnim.value, child: child),
      ),
      child: Container(
        height: screenH * 0.42,
        decoration: BoxDecoration(
          color: const Color(0xFF08080F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: const Color(0xFF50FF98).withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF50FF98).withValues(alpha: 0.06),
              blurRadius: 40,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Row(
                children: [
                  // Status orb mini
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF50FF98),
                      boxShadow: [BoxShadow(color: const Color(0xFF50FF98).withValues(alpha: 0.5), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${a.uniqueStageCount} STAGES BOUND',
                    style: const TextStyle(
                      color: Color(0xFF50FF98),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Match rate badge
                  _RateBadge(rate: a.matchRate),
                  const Spacer(),
                  // Unmatched warning
                  if (a.unmatchedCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${a.unmatchedCount} unmatched',
                        style: const TextStyle(color: Colors.orange, fontSize: 9, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Full dialog button
                  GestureDetector(
                    onTap: widget.onOpenFull,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: const Text('Details ↗', style: TextStyle(color: Colors.white38, fontSize: 9)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Neural viz + stage list
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Neural viz (60% width)
                  Expanded(
                    flex: 6,
                    child: _NeuralViz(nodes: _nodes, analysis: a),
                  ),
                  // Top matches list (40% width)
                  Expanded(
                    flex: 4,
                    child: _TopMatchesList(analysis: a),
                  ),
                ],
              ),
            ),
            // Bottom bar
            _BottomBar(
              analysis: a,
              folderPath: widget.folderPath,
              onBusVolumesChanged: widget.onBusVolumesChanged,
              onClose: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEURAL VIZ
// ─────────────────────────────────────────────────────────────────────────────

class _StageNode {
  final String stage;
  final bool isBound;
  final double angle;
  final double radiusNorm;
  final int delay; // animation stagger ms

  const _StageNode({
    required this.stage,
    required this.isBound,
    required this.angle,
    required this.radiusNorm,
    required this.delay,
  });
}

class _NeuralViz extends StatefulWidget {
  final List<_StageNode> nodes;
  final BindingAnalysis analysis;

  const _NeuralViz({required this.nodes, required this.analysis});

  @override
  State<_NeuralViz> createState() => _NeuralVizState();
}

class _NeuralVizState extends State<_NeuralViz> with TickerProviderStateMixin {
  late final AnimationController _waveCtl;
  final List<AnimationController> _nodeCtls = [];
  final List<Animation<double>> _nodeAnims = [];

  @override
  void initState() {
    super.initState();
    _waveCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat();

    // Staggered node reveal
    for (final node in widget.nodes) {
      if (!node.isBound) continue;
      final ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
      final anim = CurvedAnimation(parent: ctl, curve: Curves.easeOutBack);
      _nodeCtls.add(ctl);
      _nodeAnims.add(anim);
      Future.delayed(Duration(milliseconds: node.delay), () {
        if (mounted) ctl.forward();
      });
    }
  }

  @override
  void dispose() {
    _waveCtl.dispose();
    for (final c in _nodeCtls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _waveCtl,
      builder: (_, __) => CustomPaint(
        painter: _NeuralVizPainter(
          nodes: widget.nodes,
          waveValue: _waveCtl.value,
          nodeScales: _nodeAnims.map((a) => a.value).toList(),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _NeuralVizPainter extends CustomPainter {
  final List<_StageNode> nodes;
  final double waveValue;
  final List<double> nodeScales;

  const _NeuralVizPainter({
    required this.nodes,
    required this.waveValue,
    required this.nodeScales,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final maxR = math.min(size.width, size.height) * 0.44;

    // Background grid (subtle)
    _drawGrid(canvas, size);

    // Center orb (core)
    _drawCore(canvas, cx, cy, maxR * 0.08);

    // Draw connections first (behind nodes)
    int boundIdx = 0;
    for (final node in nodes) {
      if (!node.isBound) continue;
      final nx = cx + math.cos(node.angle) * maxR * node.radiusNorm;
      final ny = cy + math.sin(node.angle) * maxR * node.radiusNorm;
      final scale = boundIdx < nodeScales.length ? nodeScales[boundIdx] : 1.0;
      if (scale > 0) {
        _drawConnection(canvas, cx, cy, nx, ny, scale);
      }
      boundIdx++;
    }

    // Draw all nodes
    boundIdx = 0;
    for (final node in nodes) {
      final nx = cx + math.cos(node.angle) * maxR * node.radiusNorm;
      final ny = cy + math.sin(node.angle) * maxR * node.radiusNorm;

      if (node.isBound) {
        final scale = boundIdx < nodeScales.length ? nodeScales[boundIdx] : 1.0;
        _drawBoundNode(canvas, nx, ny, maxR * 0.055, scale, waveValue, boundIdx);
        boundIdx++;
      } else {
        _drawUnboundNode(canvas, nx, ny, maxR * 0.04);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 8; i++) {
      final x = size.width * i / 7;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 0; i < 6; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawCore(Canvas canvas, double cx, double cy, double r) {
    final waveR = r * (1.0 + 0.4 * math.sin(waveValue * 2 * math.pi));
    // Outer wave
    canvas.drawCircle(
      Offset(cx, cy), waveR * 3,
      Paint()..color = const Color(0xFF50FF98).withValues(alpha: 0.04)..style = PaintingStyle.fill,
    );
    // Core
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = const Color(0xFF50FF98).withValues(alpha: 0.9)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(cx, cy), r * 0.5,
      Paint()..color = Colors.white..style = PaintingStyle.fill,
    );
  }

  void _drawConnection(Canvas canvas, double x1, double y1, double x2, double y2, double scale) {
    if (scale <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFF50FF98).withValues(alpha: 0.12 * scale)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    // Lerp from center outward based on scale
    final ex = x1 + (x2 - x1) * scale;
    final ey = y1 + (y2 - y1) * scale;
    canvas.drawLine(Offset(x1, y1), Offset(ex, ey), paint);
  }

  void _drawBoundNode(Canvas canvas, double nx, double ny, double r, double scale, double wave, int idx) {
    if (scale <= 0) return;
    final sr = r * scale;
    // Wave pulse (staggered per node)
    final nodeWave = math.sin((wave + idx * 0.11) * 2 * math.pi);
    final waveR = sr * (1.0 + 0.25 * nodeWave.abs() * scale);

    canvas.drawCircle(
      Offset(nx, ny), waveR * 1.8,
      Paint()..color = const Color(0xFF50FF98).withValues(alpha: 0.05 * scale)..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(nx, ny), sr,
      Paint()
        ..color = const Color(0xFF50FF98).withValues(alpha: 0.85 * scale)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  void _drawUnboundNode(Canvas canvas, double nx, double ny, double r) {
    canvas.drawCircle(
      Offset(nx, ny), r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(nx, ny), r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_NeuralVizPainter old) =>
      old.waveValue != waveValue ||
      old.nodeScales.length != nodeScales.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP MATCHES LIST
// ─────────────────────────────────────────────────────────────────────────────

class _TopMatchesList extends StatelessWidget {
  final BindingAnalysis analysis;
  const _TopMatchesList({required this.analysis});

  @override
  Widget build(BuildContext context) {
    // Top 12 by score, sorted
    final top = (List.of(analysis.matched)
        ..sort((a, b) => b.score.compareTo(a.score)))
        .take(14).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      itemCount: top.length,
      itemExtent: 22,
      itemBuilder: (_, i) {
        final m = top[i];
        final methodColor = Color(m.methodColor);
        return Row(
          children: [
            // Confidence dot
            Container(
              width: 5, height: 5,
              margin: const EdgeInsets.only(right: 5, top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: methodColor.withValues(alpha: 0.8),
              ),
            ),
            // Stage name
            Expanded(
              child: Text(
                m.stage,
                style: const TextStyle(
                  color: Color(0xFF50FF98),
                  fontSize: 8,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Score
            Text(
              '${m.score}',
              style: TextStyle(
                color: methodColor.withValues(alpha: 0.6),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final BindingAnalysis analysis;
  final String folderPath;
  final void Function(Map<int, double>)? onBusVolumesChanged;
  final VoidCallback onClose;

  const _BottomBar({
    required this.analysis,
    required this.folderPath,
    required this.onBusVolumesChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final folder = folderPath.split('/').last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          // Folder indicator
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 10, color: Colors.white24),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    folder,
                    style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${analysis.totalFiles} files',
                  style: const TextStyle(color: Colors.white16, fontSize: 8),
                ),
              ],
            ),
          ),
          // Close button
          GestureDetector(
            onTap: onClose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Dismiss', style: TextStyle(color: Colors.white38, fontSize: 9)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RATE BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _RateBadge extends StatelessWidget {
  final double rate;
  const _RateBadge({required this.rate});

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100).round();
    final color = pct >= 90
        ? const Color(0xFF50FF98)
        : pct >= 70
            ? const Color(0xFF50D8FF)
            : pct >= 50
                ? Colors.orange
                : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
      ),
    );
  }
}
