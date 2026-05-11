/// FAZA 4.2.5 — Arrangement Suggester (Copilot Phase 2)
///
/// Heuristički rule engine koji prevodi natural-language "arrangement intent"
/// u **ordered list of stage steps** sa preporučenim trajanjima i envelope
/// oblicima. Komplement MixDeltaProposer-u (4.2.1) — gde Mix Delta menja
/// parametre **jednog** stage-a, ArrangementSuggester predlaže **sekvencu**
/// stage-ova preko vremena.
///
/// **Primer:**
///   Input: "tense buildup to big win"
///   Output:
///     1. ANTICIPATION_LOW   (2500 ms, build envelope)
///     2. ANTICIPATION_HIGH  (1500 ms, peak envelope)
///     3. REEL_STOP_FINAL    ( 400 ms, transient envelope)
///     4. WIN_BIG_TIER       ( 800 ms, release envelope)
///     5. WIN_ROLLUP         (3500 ms, sustained envelope)
///
/// **Intent grammar:**
///   - shape:    "tense buildup" / "euphoric climax" / "calm intro" /
///               "punchy hit" / "aggressive sequence" / "smooth transition" /
///               "bright payoff" / "dark setup" / "triumphant finale"
///   - target:   "to big win" / "to bonus" / "to free spins" / "to jackpot"
///   - modifier: "short" / "long" / "quick" / "extended"
///
/// **Design constraints:**
///   - Deterministic — istog intent-a vraća isti output (no RNG).
///   - Stateless — singleton, ali bez mutable state-a.
///   - No LLM dependency — pure keyword + ordered rule matching.
///   - Output je **kandidat** koji UI prikazuje korisniku za approve/reject;
///     ne primenjuje se direktno (drugačije od MixDelta kojeg user može
///     direktno aplicirati).
library;

/// Envelope shape descriptor — kako amplituda / energija evoluiše tokom
/// stage step-a. Ne renderuje se direktno — koristi se kao tag za audio
/// engine da bira odgovarajući automation curve.
enum EnvelopeShape {
  /// Slow rise iz tihog ka glasnom (anticipation, buildup).
  build,

  /// Konstantan visoki nivo (peak, climax).
  peak,

  /// Brzi kratki udar (transient, hit).
  transient,

  /// Glasno-pa-meko padanje (release, decay).
  release,

  /// Dugačka konstantna jačina (sustained, rollup).
  sustained,

  /// Postupno tiše (fade, outro).
  fade,
}

/// Jedan korak u predloženom arrangement-u.
class StageStep {
  /// Kanonski stage ID — npr. `ANTICIPATION_LOW`, `WIN_ROLLUP`.
  final String stageId;

  /// Preporučeno trajanje u milisekundama.
  final int durationMs;

  /// Envelope shape tag (build, peak, transient, release, sustained, fade).
  final EnvelopeShape envelope;

  /// Rationale za UI tooltip — kratak "why this step".
  final String rationale;

  const StageStep({
    required this.stageId,
    required this.durationMs,
    required this.envelope,
    required this.rationale,
  });

  Map<String, dynamic> toJson() => {
        'stage_id': stageId,
        'duration_ms': durationMs,
        'envelope': envelope.name,
        'rationale': rationale,
      };
}

/// Result wrapper sa eksplicitnim error handling-om (isti pattern kao
/// MixProposalResult).
class ArrangementProposalResult {
  final List<StageStep>? steps;
  final String intent;
  final String? error;

  /// Ukupno trajanje preporučenog arrangement-a (ms). 0 za failure.
  int get totalMs => (steps ?? const [])
      .fold<int>(0, (acc, step) => acc + step.durationMs);

  const ArrangementProposalResult.success({
    required List<StageStep> this.steps,
    required this.intent,
  }) : error = null;

  const ArrangementProposalResult.failure({
    required this.intent,
    required String this.error,
  }) : steps = null;

  bool get isSuccess => steps != null;
}

/// Arrangement shape — opisuje karakter sekvence kroz vreme.
/// Različito od `Emotion` (MixDelta) koji opisuje **stalni** karakter
/// **jednog** stage-a.
enum ArrangementShape {
  /// Tenzija raste, pa eksplodira u win.
  tenseBuildup,

  /// Trenutna euforija — kratki visoki nivo, dugi rollup.
  euphoricClimax,

  /// Tih, miran ulaz; spor build.
  calmIntro,

  /// Snažan, kratak hit bez puno fanfare.
  punchyHit,

  /// Glasno, brzo, neprekidno — aggressive sequence.
  aggressiveSequence,

  /// Crossfade-style prelazi sa puno reverb-a.
  smoothTransition,

  /// Sjajan, šljaštav payoff — bright, full-spectrum.
  brightPayoff,

  /// Mračan, niski energetski setup pre eskalacije.
  darkSetup,

  /// Veliki ceremonialni kraj — triumphant finale.
  triumphantFinale,

  /// Ne mogu da odredim — failure flag.
  none,
}

/// Cilj sekvence — kojom stage-event "tačkom" se završava.
enum ArrangementTarget {
  bigWin,
  megaWin,
  jackpot,
  bonus,
  freeSpins,
  cascade,
  generic,
}

class ArrangementSuggester {
  ArrangementSuggester._();
  static final ArrangementSuggester instance = ArrangementSuggester._();

  /// Glavni entry. `intent` — natural-language arrangement intent.
  /// `targetOverride` — eksplicitni target (preskoči parsing iz teksta).
  ArrangementProposalResult propose(
    String intent, {
    ArrangementTarget? targetOverride,
  }) {
    final lower = intent.toLowerCase().trim();
    if (lower.isEmpty) {
      return const ArrangementProposalResult.failure(
        intent: '',
        error: 'Empty intent phrase.',
      );
    }

    final shape = _extractShape(lower);
    if (shape == ArrangementShape.none) {
      return ArrangementProposalResult.failure(
        intent: intent,
        error: 'Cannot identify arrangement shape. Use one of: tense buildup, '
            'euphoric climax, calm intro, punchy hit, aggressive sequence, '
            'smooth transition, bright payoff, dark setup, triumphant finale.',
      );
    }

    final target = targetOverride ?? _extractTarget(lower);
    final scale = _extractScale(lower); // 0.5..2.0

    final steps = _shapeToSteps(shape, target, scale);
    if (steps.isEmpty) {
      return ArrangementProposalResult.failure(
        intent: intent,
        error: 'No steps produced — unmapped shape: ${shape.name}',
      );
    }
    return ArrangementProposalResult.success(steps: steps, intent: intent);
  }

  // ── Shape extraction ───────────────────────────────────────────────────
  ArrangementShape _extractShape(String lower) {
    // Order matters — match longest specific phrase first.
    const map = <String, ArrangementShape>{
      'tense buildup': ArrangementShape.tenseBuildup,
      'tense build-up': ArrangementShape.tenseBuildup,
      'suspenseful buildup': ArrangementShape.tenseBuildup,
      'tension': ArrangementShape.tenseBuildup,
      'euphoric climax': ArrangementShape.euphoricClimax,
      'euphoric peak': ArrangementShape.euphoricClimax,
      'climax': ArrangementShape.euphoricClimax,
      'calm intro': ArrangementShape.calmIntro,
      'gentle intro': ArrangementShape.calmIntro,
      'soft intro': ArrangementShape.calmIntro,
      'punchy hit': ArrangementShape.punchyHit,
      'snappy hit': ArrangementShape.punchyHit,
      'quick hit': ArrangementShape.punchyHit,
      'aggressive sequence': ArrangementShape.aggressiveSequence,
      'intense sequence': ArrangementShape.aggressiveSequence,
      'powerful sequence': ArrangementShape.aggressiveSequence,
      'smooth transition': ArrangementShape.smoothTransition,
      'silky transition': ArrangementShape.smoothTransition,
      'crossfade': ArrangementShape.smoothTransition,
      'bright payoff': ArrangementShape.brightPayoff,
      'sparkling payoff': ArrangementShape.brightPayoff,
      'shiny finale': ArrangementShape.brightPayoff,
      'dark setup': ArrangementShape.darkSetup,
      'moody setup': ArrangementShape.darkSetup,
      'sinister setup': ArrangementShape.darkSetup,
      'triumphant finale': ArrangementShape.triumphantFinale,
      'victorious finale': ArrangementShape.triumphantFinale,
      'grand finale': ArrangementShape.triumphantFinale,
    };
    for (final entry in map.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return ArrangementShape.none;
  }

  // ── Target extraction ──────────────────────────────────────────────────
  ArrangementTarget _extractTarget(String lower) {
    // "to X" / "into X" / trailing X.
    const map = <String, ArrangementTarget>{
      'big win': ArrangementTarget.bigWin,
      'mega win': ArrangementTarget.megaWin,
      'jackpot': ArrangementTarget.jackpot,
      'bonus': ArrangementTarget.bonus,
      'free spins': ArrangementTarget.freeSpins,
      'free spin': ArrangementTarget.freeSpins,
      'cascade': ArrangementTarget.cascade,
    };
    for (final entry in map.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return ArrangementTarget.generic;
  }

  // ── Scale extraction (modifier hints) ──────────────────────────────────
  /// Returns scale factor for `durationMs`. Default 1.0.
  ///
  /// Algoritam (deterministic):
  /// - "short / quick / fast / brief" → 0.5
  /// - "long / extended / slow / drawn out" → 1.75
  /// - inače 1.0
  double _extractScale(String lower) {
    final isShort = RegExp(
      r'\b(short|quick|fast|brief|tight)\b',
    ).hasMatch(lower);
    if (isShort) return 0.5;
    final isLong = RegExp(
      r'\b(long|extended|slow|drawn\s*out|epic)\b',
    ).hasMatch(lower);
    if (isLong) return 1.75;
    return 1.0;
  }

  // ── Shape → ordered step list ──────────────────────────────────────────
  List<StageStep> _shapeToSteps(
    ArrangementShape shape,
    ArrangementTarget target,
    double scale,
  ) {
    int ms(int base) => (base * scale).round();
    final winStage = _winStageFor(target);
    final triggerStage = _triggerStageFor(target);

    switch (shape) {
      case ArrangementShape.tenseBuildup:
        return [
          StageStep(
            stageId: 'ANTICIPATION_LOW',
            durationMs: ms(2500),
            envelope: EnvelopeShape.build,
            rationale: 'Low anticipation seeds tension via slow rise',
          ),
          StageStep(
            stageId: 'ANTICIPATION_HIGH',
            durationMs: ms(1500),
            envelope: EnvelopeShape.peak,
            rationale: 'High anticipation crests tension before release',
          ),
          StageStep(
            stageId: 'REEL_STOP_FINAL',
            durationMs: ms(400),
            envelope: EnvelopeShape.transient,
            rationale: 'Sharp transient cues outcome moment',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(800),
            envelope: EnvelopeShape.release,
            rationale: 'Win tier hit releases accumulated tension',
          ),
          StageStep(
            stageId: 'WIN_ROLLUP',
            durationMs: ms(3500),
            envelope: EnvelopeShape.sustained,
            rationale: 'Sustained rollup celebrates payoff',
          ),
        ];
      case ArrangementShape.euphoricClimax:
        return [
          StageStep(
            stageId: triggerStage,
            durationMs: ms(600),
            envelope: EnvelopeShape.transient,
            rationale: 'Trigger event opens the climax',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(1200),
            envelope: EnvelopeShape.peak,
            rationale: 'Peak energy — euphoric tier hit',
          ),
          StageStep(
            stageId: 'WIN_ROLLUP',
            durationMs: ms(4500),
            envelope: EnvelopeShape.sustained,
            rationale: 'Long rollup sustains euphoria',
          ),
          StageStep(
            stageId: 'WIN_END',
            durationMs: ms(800),
            envelope: EnvelopeShape.fade,
            rationale: 'Graceful fade closes the celebration',
          ),
        ];
      case ArrangementShape.calmIntro:
        return [
          StageStep(
            stageId: 'AMBIENT_INTRO',
            durationMs: ms(4000),
            envelope: EnvelopeShape.build,
            rationale: 'Soft ambient bed establishes calm baseline',
          ),
          StageStep(
            stageId: 'IDLE_LOOP',
            durationMs: ms(6000),
            envelope: EnvelopeShape.sustained,
            rationale: 'Sustained idle loop holds the mood',
          ),
          StageStep(
            stageId: 'UI_SPIN_PRESS',
            durationMs: ms(300),
            envelope: EnvelopeShape.transient,
            rationale: 'Subtle interaction cue without breaking calm',
          ),
        ];
      case ArrangementShape.punchyHit:
        return [
          StageStep(
            stageId: 'REEL_STOP_FINAL',
            durationMs: ms(150),
            envelope: EnvelopeShape.transient,
            rationale: 'Tight transient — no preamble',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(500),
            envelope: EnvelopeShape.transient,
            rationale: 'Quick punch on win tier',
          ),
          StageStep(
            stageId: 'WIN_END',
            durationMs: ms(300),
            envelope: EnvelopeShape.fade,
            rationale: 'Fast decay keeps it punchy',
          ),
        ];
      case ArrangementShape.aggressiveSequence:
        return [
          StageStep(
            stageId: 'REEL_SPIN',
            durationMs: ms(1200),
            envelope: EnvelopeShape.peak,
            rationale: 'Loud sustained spin energy',
          ),
          StageStep(
            stageId: 'REEL_STOP_FINAL',
            durationMs: ms(300),
            envelope: EnvelopeShape.transient,
            rationale: 'Sharp stop hit',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(900),
            envelope: EnvelopeShape.peak,
            rationale: 'Aggressive win presence',
          ),
          StageStep(
            stageId: 'WIN_ROLLUP',
            durationMs: ms(2500),
            envelope: EnvelopeShape.sustained,
            rationale: 'Driving rollup keeps energy up',
          ),
        ];
      case ArrangementShape.smoothTransition:
        return [
          StageStep(
            stageId: 'AMBIENT_OUTRO',
            durationMs: ms(2000),
            envelope: EnvelopeShape.fade,
            rationale: 'Fade outgoing layer',
          ),
          StageStep(
            stageId: 'AMBIENT_INTRO',
            durationMs: ms(2500),
            envelope: EnvelopeShape.build,
            rationale: 'Crossfade incoming layer',
          ),
          StageStep(
            stageId: 'IDLE_LOOP',
            durationMs: ms(4000),
            envelope: EnvelopeShape.sustained,
            rationale: 'Settle into new state',
          ),
        ];
      case ArrangementShape.brightPayoff:
        return [
          StageStep(
            stageId: triggerStage,
            durationMs: ms(400),
            envelope: EnvelopeShape.transient,
            rationale: 'Sparkling trigger cue',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(1000),
            envelope: EnvelopeShape.peak,
            rationale: 'Full-spectrum bright win',
          ),
          StageStep(
            stageId: 'WIN_ROLLUP',
            durationMs: ms(3000),
            envelope: EnvelopeShape.sustained,
            rationale: 'Shimmering rollup with high-end emphasis',
          ),
        ];
      case ArrangementShape.darkSetup:
        return [
          StageStep(
            stageId: 'AMBIENT_INTRO',
            durationMs: ms(3500),
            envelope: EnvelopeShape.build,
            rationale: 'Low-frequency ambient bed sets mood',
          ),
          StageStep(
            stageId: 'ANTICIPATION_LOW',
            durationMs: ms(2000),
            envelope: EnvelopeShape.build,
            rationale: 'Dark anticipation undertones',
          ),
          StageStep(
            stageId: 'REEL_SPIN',
            durationMs: ms(1500),
            envelope: EnvelopeShape.sustained,
            rationale: 'Sinister spin tone',
          ),
        ];
      case ArrangementShape.triumphantFinale:
        return [
          StageStep(
            stageId: triggerStage,
            durationMs: ms(800),
            envelope: EnvelopeShape.transient,
            rationale: 'Ceremonial trigger',
          ),
          StageStep(
            stageId: winStage,
            durationMs: ms(1500),
            envelope: EnvelopeShape.peak,
            rationale: 'Big win hit at climax',
          ),
          StageStep(
            stageId: 'WIN_ROLLUP',
            durationMs: ms(5000),
            envelope: EnvelopeShape.sustained,
            rationale: 'Long ceremonial rollup with wide stereo + reverb',
          ),
          StageStep(
            stageId: 'WIN_END',
            durationMs: ms(1500),
            envelope: EnvelopeShape.fade,
            rationale: 'Grand fade with reverb tail',
          ),
        ];
      case ArrangementShape.none:
        return const [];
    }
  }

  String _winStageFor(ArrangementTarget t) {
    switch (t) {
      case ArrangementTarget.bigWin:
        return 'WIN_BIG_TIER';
      case ArrangementTarget.megaWin:
        return 'WIN_MEGA_TIER';
      case ArrangementTarget.jackpot:
        return 'WIN_JACKPOT';
      case ArrangementTarget.bonus:
        return 'BONUS_WIN';
      case ArrangementTarget.freeSpins:
        return 'FREE_SPIN_WIN';
      case ArrangementTarget.cascade:
        return 'CASCADE_WIN';
      case ArrangementTarget.generic:
        return 'WIN_GENERIC';
    }
  }

  String _triggerStageFor(ArrangementTarget t) {
    switch (t) {
      case ArrangementTarget.bigWin:
        return 'WIN_TRIGGER';
      case ArrangementTarget.megaWin:
        return 'WIN_TRIGGER';
      case ArrangementTarget.jackpot:
        return 'JACKPOT_TRIGGER';
      case ArrangementTarget.bonus:
        return 'BONUS_TRIGGER';
      case ArrangementTarget.freeSpins:
        return 'FREE_SPIN_TRIGGER';
      case ArrangementTarget.cascade:
        return 'CASCADE_TRIGGER';
      case ArrangementTarget.generic:
        return 'GENERIC_TRIGGER';
    }
  }
}
