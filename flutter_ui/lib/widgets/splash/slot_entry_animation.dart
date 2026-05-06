/// FLUX_MASTER_TODO 3.1.2 — Splash → Slot kinematska entry animacija
///
/// Trigger: korisnik završi splash (Enter key ili `onComplete`), umesto
/// instant cut na SlotLabScreen ide ova 1.6s sekvenca:
///
///   0.0–0.4s   golden radial bloom — zvezda u centru se širi
///   0.4–1.0s   5 reels padaju odozgo sa staggered timing-om i bounce
///   1.0–1.4s   simboli "settle" pulsiraju, zlatni rim svetli
///   1.4–1.6s   ceo overlay fade-out → SlotLabScreen otkriven
///
/// **Bez disk/audio asset zavisnosti** — kompletno proceduralno
/// (CustomPaint + emoji symbols). Ako se kasnije doda audio,
/// `enableAudio` flag prosledjuje audio cue na svaki phase boundary.
///
/// Pattern: Single overlay, prelazi se preko SlotLabScreen-a, na
/// `onComplete` se dismiss-uje. Caller routes-uje normalno.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/fluxforge_theme.dart';

/// Kinematska entry animacija koja vodi iz splash-a u slot lab.
///
/// Duration: 1.6s ukupno. Dropdown widget — postavi preko SlotLabScreen-a
/// kao Stack child sa `Positioned.fill`, na `onComplete` ukloni.
class SlotEntryAnimation extends StatefulWidget {
  /// 5 reels × 3 rows je default (industry standard 5x3 grid). Druge
  /// dimenzije rade ali nisu testirane vizuelno.
  final int reelCount;
  final int rowCount;

  /// Pozvan kad se animacija završi (overlay treba ukloniti).
  final VoidCallback onComplete;

  /// Optional fade-out boja na kraju (default: transparent — pretpostavlja
  /// da SlotLab ima svoju background koji preuzme).
  final Color exitTintColor;

  const SlotEntryAnimation({
    super.key,
    required this.onComplete,
    this.reelCount = 5,
    this.rowCount = 3,
    this.exitTintColor = Colors.transparent,
  });

  @override
  State<SlotEntryAnimation> createState() => _SlotEntryAnimationState();
}

class _SlotEntryAnimationState extends State<SlotEntryAnimation>
    with SingleTickerProviderStateMixin {
  /// Master timeline — sve faze čitaju iz njega da vreme bude consistent.
  late final AnimationController _master;

  /// Phase 1: golden bloom (0.0–0.25 of total).
  late final Animation<double> _bloomScale;
  late final Animation<double> _bloomOpacity;

  /// Phase 2: reels drop (0.25–0.625 of total).
  late final Animation<double> _reelsProgress;

  /// Phase 3: settle pulse (0.625–0.875 of total).
  late final Animation<double> _settlePulse;

  /// Phase 4: fade out (0.875–1.0 of total).
  late final Animation<double> _exitFade;

  bool _completedFired = false;

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Phase intervals — fractions of master duration. Each phase je
    // odvojen `Interval` curve tako da neopadajući redosled je očuvan
    // čak i kad master controller pauzira mid-flight.
    _bloomScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.00, 0.25, curve: Curves.easeOutCubic),
      ),
    );
    _bloomOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.55), weight: 40),
    ]).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.00, 0.55, curve: Curves.easeInOut),
      ),
    );
    _reelsProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        // Lagano produžen interval — bounce treba prostor za "naseljenje".
        curve: const Interval(0.25, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _settlePulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.625, 0.875, curve: Curves.easeInOut),
      ),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _master,
        curve: const Interval(0.875, 1.0, curve: Curves.easeIn),
      ),
    );

    _master.addStatusListener(_onStatus);
    _master.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completedFired) {
      _completedFired = true;
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _master.removeStatusListener(_onStatus);
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IgnorePointer — overlay je čisto vizuelan, ne sme da blokira
    // klikove na SlotLabScreen-u koji se otkriva ispod.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _master,
        builder: (context, _) => CustomPaint(
          painter: _SlotEntryPainter(
            bloomScale: _bloomScale.value,
            bloomOpacity: _bloomOpacity.value,
            reelsProgress: _reelsProgress.value,
            settlePulse: _settlePulse.value,
            exitFade: _exitFade.value,
            reelCount: widget.reelCount,
            rowCount: widget.rowCount,
            exitTint: widget.exitTintColor,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// All-in-one painter — single render pass kroz sve 4 faze. Single painter
/// umesto stacked widget-a radi performanse: 60fps na 5x3 grid sa multi-
/// layer glow zahteva minimum allocations po frame-u.
class _SlotEntryPainter extends CustomPainter {
  final double bloomScale;
  final double bloomOpacity;
  final double reelsProgress;
  final double settlePulse;
  final double exitFade;
  final int reelCount;
  final int rowCount;
  final Color exitTint;

  _SlotEntryPainter({
    required this.bloomScale,
    required this.bloomOpacity,
    required this.reelsProgress,
    required this.settlePulse,
    required this.exitFade,
    required this.reelCount,
    required this.rowCount,
    required this.exitTint,
  });

  // Symbol set — proceduralni glyphs (no disk asset). Mix premium suit
  // simbola + 7/BAR cliché slot symbols.
  static const _symbols = ['7', '♠', '♥', '♦', '♣', 'BAR', '★', '◆'];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // ── Phase 0: BACKGROUND VEIL ─────────────────────────────────────
    // Crni veo koji blocks-uje SlotLab content ispod, fadeuje na kraju.
    final veilOpacity = exitFade;
    if (veilOpacity > 0.001) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF06080D).withValues(alpha: veilOpacity),
      );
    }

    // ── Phase 1: GOLDEN BLOOM ────────────────────────────────────────
    if (bloomOpacity > 0.001) {
      final bloomR = 280.0 * bloomScale;
      final shader = RadialGradient(
        colors: [
          FluxForgeTheme.brandGoldBright.withValues(alpha: bloomOpacity * 0.95),
          FluxForgeTheme.brandGold.withValues(alpha: bloomOpacity * 0.7),
          FluxForgeTheme.brandBurgundy.withValues(alpha: bloomOpacity * 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: bloomR));
      canvas.drawCircle(
        Offset(cx, cy),
        bloomR,
        Paint()..shader = shader,
      );
    }

    // ── Phase 2+3: REELS ─────────────────────────────────────────────
    if (reelsProgress > 0.001) {
      _paintReels(canvas, size);
    }
  }

  void _paintReels(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cell geometry — fit 5x3 grid u centralnih 60% širine ekrana.
    final gridW = w * 0.55;
    final gridH = h * 0.45;
    final cellW = gridW / reelCount;
    final cellH = gridH / rowCount;
    final cell = math.min(cellW, cellH);
    final actualGridW = cell * reelCount;
    final actualGridH = cell * rowCount;
    final originX = (w - actualGridW) / 2;
    final originY = (h - actualGridH) / 2;

    for (int r = 0; r < reelCount; r++) {
      // Stagger — svaki reel kreće malo kasnije od prethodnog. Ukupan
      // stagger budget = 30% reels phase tako da svi padnu pre nego što
      // settle počne.
      final reelStagger = (r / reelCount) * 0.3;
      final reelLocal = ((reelsProgress - reelStagger) / (1.0 - reelStagger))
          .clamp(0.0, 1.0);

      // Drop offset — počinju ispod gornjeg ruba ekrana, dolaze u poziciju.
      final dropFrom = -h * 0.6;
      final dropY = dropFrom * (1.0 - _easeOutBounce(reelLocal));

      for (int row = 0; row < rowCount; row++) {
        final cellX = originX + r * cell;
        final cellY = originY + row * cell + dropY;
        final symIdx = (r * 3 + row) % _symbols.length;
        _paintCell(
          canvas,
          Rect.fromLTWH(cellX, cellY, cell, cell),
          _symbols[symIdx],
          reelLocal,
        );
      }
    }
  }

  void _paintCell(Canvas canvas, Rect cell, String symbol, double reelLocal) {
    final radius = cell.width * 0.12;
    final rect = RRect.fromRectAndRadius(cell.deflate(2), Radius.circular(radius));

    // Cell BG — gradient sa burgundy → black da simboli plivaju iznad.
    final bgShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF1A1015),
        const Color(0xFF080606),
      ],
    ).createShader(cell);
    canvas.drawRRect(rect, Paint()..shader = bgShader);

    // Settle pulse — zlatni rim koji puls-uje na kraju animacije.
    final pulseAlpha = (settlePulse * (0.7 + 0.3 * math.sin(settlePulse * math.pi)))
        .clamp(0.0, 1.0);
    if (pulseAlpha > 0.01) {
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = FluxForgeTheme.brandGold.withValues(alpha: pulseAlpha),
      );
    }

    // Symbol text — zlatni glow + bright core. Skala se širi sa pulse-om
    // (0.95 → 1.05) tako da simboli "dišu" pre fade-a.
    final scale = 0.95 + 0.10 * settlePulse;
    final fontSize = cell.width * 0.42 * scale;

    // Drop opacity — simboli postaju vidljivi tek kad reel-local > 0.4
    // (sprečava da vidiš simbol DOK reel pada — vizuelno čistije).
    final symOpacity = ((reelLocal - 0.4) / 0.6).clamp(0.0, 1.0);

    final textPainter = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: FluxForgeTheme.brandGoldBright.withValues(alpha: symOpacity),
          shadows: [
            Shadow(
              color: FluxForgeTheme.brandGold
                  .withValues(alpha: symOpacity * (0.6 + 0.4 * settlePulse)),
              blurRadius: 12 * (0.5 + settlePulse),
            ),
            Shadow(
              color: FluxForgeTheme.brandBurgundy
                  .withValues(alpha: symOpacity * 0.4),
              blurRadius: 18,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: cell.width);
    textPainter.paint(
      canvas,
      Offset(
        cell.center.dx - textPainter.width / 2,
        cell.center.dy - textPainter.height / 2,
      ),
    );
  }

  /// Easing kriva — bounce na kraju. Replikira Material `Curves.bounceOut`
  /// algoritam ali kao raw fn (Curves su widget-side, painter side ide
  /// raw da ne kreira CurvedAnimation overhead per frame).
  double _easeOutBounce(double t) {
    const n1 = 7.5625;
    const d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) {
      t -= 1.5 / d1;
      return n1 * t * t + 0.75;
    }
    if (t < 2.5 / d1) {
      t -= 2.25 / d1;
      return n1 * t * t + 0.9375;
    }
    t -= 2.625 / d1;
    return n1 * t * t + 0.984375;
  }

  @override
  bool shouldRepaint(covariant _SlotEntryPainter old) =>
      old.bloomScale != bloomScale ||
      old.bloomOpacity != bloomOpacity ||
      old.reelsProgress != reelsProgress ||
      old.settlePulse != settlePulse ||
      old.exitFade != exitFade;
}
