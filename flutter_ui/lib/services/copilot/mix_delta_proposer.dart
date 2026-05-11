/// FAZA 4.2.1 — Generative Mix Delta Proposer
///
/// Heuristički rule engine koji prevodi natural-language "intent phrase"
/// u konkretne **mix delta** predloge (parameter changes) za jedan ili
/// više stage layer-a. Bez LLM-a — koristi keyword matching + numeric
/// extraction + emotional mapping.
///
/// **Primer:**
///   Input: "make rollup 15% more euphoric"
///   Output: 3 deltas — volume +1.5dB, brightness +15%, tempo +7%
///
/// **Emotional dimensions:**
///   - euphoric → +volume, +brightness, +tempo, +reverb dwell
///   - tense / dark → -brightness, +low-pass, -tempo, +distortion
///   - calm / serene → -volume, +reverb dwell, -tempo, -dynamics
///   - aggressive / intense → +volume, +saturation, +tempo, +high-mid
///   - euphoric / triumphant → +volume, +brightness, +stereo width
///
/// **Future:**
///   - LLM-driven proposal (4.1.2 Phi-4 lokalno) → fluent intent
///   - Multi-turn refinement ("less reverb, more punch")
library;

/// One concrete parameter change proposal.
class MixDelta {
  /// Target stage (npr. `WIN_ROLLUP_3`) ili `*` za sve match-ujuće.
  final String stage;

  /// Parametar (`volume_db`, `pan`, `brightness_pct`, `tempo_pct`,
  /// `reverb_dwell_ms`, `low_pass_hz`, `stereo_width_pct`, …).
  final String parameter;

  /// Delta (signed; jedinica zavisi od parametra).
  final double delta;

  /// Rationale za UI tooltip — kratak "why this change".
  final String rationale;

  const MixDelta({
    required this.stage,
    required this.parameter,
    required this.delta,
    required this.rationale,
  });

  Map<String, dynamic> toJson() => {
        'stage': stage,
        'parameter': parameter,
        'delta': delta,
        'rationale': rationale,
      };
}

/// Result wrapper sa eksplicitnim error handling-om.
class MixProposalResult {
  final List<MixDelta>? deltas;
  final String intent;
  final String? error;

  const MixProposalResult.success({
    required List<MixDelta> this.deltas,
    required this.intent,
  }) : error = null;

  const MixProposalResult.failure({
    required this.intent,
    required String this.error,
  }) : deltas = null;

  bool get isSuccess => deltas != null;
}

/// Emotional axis. Sve mappings centralizovani ovde.
enum Emotion {
  euphoric,
  tense,
  calm,
  aggressive,
  triumphant,
  dark,
  bright,
  punchy,
  smooth,
  none,
}

class MixDeltaProposer {
  MixDeltaProposer._();
  static final MixDeltaProposer instance = MixDeltaProposer._();

  /// Glavni entry — parse intent phrase + generiši delta list.
  ///
  /// `intent` — npr. "make rollup 15% more euphoric"
  /// `stagePattern` — kanonski stage name; ako null, izvuci iz intent-a
  /// (npr. "rollup" → `WIN_ROLLUP_*`).
  MixProposalResult propose(String intent, {String? stagePattern}) {
    final lower = intent.toLowerCase().trim();
    if (lower.isEmpty) {
      return const MixProposalResult.failure(
        intent: '',
        error: 'Empty intent phrase.',
      );
    }

    final stage = stagePattern ?? _extractStage(lower);
    if (stage == null) {
      return MixProposalResult.failure(
        intent: intent,
        error: 'Cannot identify target stage. Specify "rollup", "win", '
            '"reel", "anticipation", "spin", "bonus", "jackpot", or '
            'pass `stagePattern` explicitly.',
      );
    }

    final emotion = _extractEmotion(lower);
    if (emotion == Emotion.none) {
      return MixProposalResult.failure(
        intent: intent,
        error: 'Cannot identify emotional intent. Use one of: euphoric, '
            'tense, calm, aggressive, triumphant, dark, bright, punchy, smooth.',
      );
    }

    final intensity = _extractIntensity(lower); // [-1.0, 1.0]
    final deltas = _emotionToDeltas(emotion, stage, intensity);

    if (deltas.isEmpty) {
      return MixProposalResult.failure(
        intent: intent,
        error: 'No deltas produced — unmapped emotion: ${emotion.name}',
      );
    }
    return MixProposalResult.success(deltas: deltas, intent: intent);
  }

  // ── Stage extraction ─────────────────────────────────────────────────
  String? _extractStage(String lower) {
    // Order matters — match longest specific phrase first.
    const map = {
      'rollup': 'WIN_ROLLUP_*',
      'big win': 'WIN_BIG_*',
      'mega win': 'WIN_MEGA_*',
      'massive win': 'WIN_MASSIVE_*',
      'win presentation': 'WIN_*',
      'anticipation': 'ANTICIPATION_*',
      'reel stop': 'REEL_STOP_*',
      'reel spin': 'REEL_SPIN_*',
      'reel': 'REEL_*',
      'bonus trigger': 'BONUS_TRIGGER_*',
      'bonus': 'BONUS_*',
      'free spin trigger': 'FREE_SPIN_TRIGGER_*',
      'free spin': 'FREE_SPIN_*',
      'free spins': 'FREE_SPIN_*',
      'jackpot': 'JACKPOT_*',
      'cascade': 'CASCADE_*',
      'spin press': 'UI_SPIN_PRESS',
      'spin': 'REEL_SPIN_*',
      'idle': 'IDLE_*',
      'music': 'MUSIC_*',
      'ambient': 'AMBIENT_*',
      'win': 'WIN_*',
    };
    for (final entry in map.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // ── Emotion extraction ───────────────────────────────────────────────
  Emotion _extractEmotion(String lower) {
    final wordMap = <String, Emotion>{
      'euphoric': Emotion.euphoric,
      'euphoria': Emotion.euphoric,
      'happy': Emotion.euphoric,
      'joyful': Emotion.euphoric,
      'triumph': Emotion.triumphant,
      'triumphant': Emotion.triumphant,
      'victorious': Emotion.triumphant,
      'tense': Emotion.tense,
      'tension': Emotion.tense,
      'suspense': Emotion.tense,
      'suspenseful': Emotion.tense,
      'calm': Emotion.calm,
      'serene': Emotion.calm,
      'peaceful': Emotion.calm,
      'quiet': Emotion.calm,
      'aggressive': Emotion.aggressive,
      'intense': Emotion.aggressive,
      'powerful': Emotion.aggressive,
      'dark': Emotion.dark,
      'sinister': Emotion.dark,
      'moody': Emotion.dark,
      'bright': Emotion.bright,
      'sparkling': Emotion.bright,
      'shiny': Emotion.bright,
      'punchy': Emotion.punchy,
      'snappy': Emotion.punchy,
      'crisp': Emotion.punchy,
      'smooth': Emotion.smooth,
      'soft': Emotion.smooth,
      'silky': Emotion.smooth,
    };
    for (final entry in wordMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return Emotion.none;
  }

  // ── Intensity extraction (percent + multiplier hints) ────────────────
  /// Returns [-1.0, 1.0]. Default 0.15 (small bump).
  ///
  /// Algoritam (deterministic):
  /// 1. Eksplicitan procenat "N%" pobedi sve (uključujući negativan).
  /// 2. Intensifier ("much/very/extremely/way") → magnitude 0.30; inače 0.15.
  /// 3. Direction ("less/reduce/lower/decrease") → negativan znak; default poz.
  double _extractIntensity(String lower) {
    // 1. Eksplicitan procenat.
    final pctMatch = RegExp(r'(\-?\d+(?:\.\d+)?)\s*%').firstMatch(lower);
    if (pctMatch != null) {
      final pct = double.tryParse(pctMatch.group(1) ?? '');
      if (pct != null) return (pct / 100.0).clamp(-1.0, 1.0);
    }

    // 2. Magnitude — "much/very/extremely/way" pojačava.
    final hasIntensifier = RegExp(
      r'\b(much|very|extremely|way)\b',
    ).hasMatch(lower);
    final magnitude = hasIntensifier ? 0.30 : 0.15;

    // 3. Direction — "less" prebacuje znak.
    final isNegative = RegExp(
      r'\b(less|reduce|lower|decrease|reduce)\b',
    ).hasMatch(lower);

    return isNegative ? -magnitude : magnitude;
  }

  // ── Emotion → concrete deltas ────────────────────────────────────────
  List<MixDelta> _emotionToDeltas(
    Emotion emotion,
    String stage,
    double intensity,
  ) {
    // Intensity ∈ [-1, 1] — pozitivno znači "more X", negativno "less X".
    // Volumes su izraženi u dB (delta), pct su u procentima (0–100 jedinice).
    final i = intensity; // shorthand

    switch (emotion) {
      case Emotion.euphoric:
        return [
          MixDelta(
            stage: stage,
            parameter: 'volume_db',
            delta: 2.0 * i,
            rationale: 'Euphoric → louder gain creates uplift sensation',
          ),
          MixDelta(
            stage: stage,
            parameter: 'brightness_pct',
            delta: 15.0 * i,
            rationale: 'Euphoric → boost high-mid energy (1–4 kHz)',
          ),
          MixDelta(
            stage: stage,
            parameter: 'tempo_pct',
            delta: 7.0 * i,
            rationale: 'Euphoric → slight tempo lift reinforces excitement',
          ),
        ];
      case Emotion.triumphant:
        return [
          MixDelta(
            stage: stage,
            parameter: 'volume_db',
            delta: 3.0 * i,
            rationale: 'Triumphant → big presence',
          ),
          MixDelta(
            stage: stage,
            parameter: 'stereo_width_pct',
            delta: 20.0 * i,
            rationale: 'Triumphant → wide stereo image',
          ),
          MixDelta(
            stage: stage,
            parameter: 'reverb_dwell_ms',
            delta: 200.0 * i,
            rationale: 'Triumphant → longer reverb tail = grandeur',
          ),
        ];
      case Emotion.tense:
        return [
          MixDelta(
            stage: stage,
            parameter: 'brightness_pct',
            delta: -10.0 * i,
            rationale: 'Tense → roll off high-end',
          ),
          MixDelta(
            stage: stage,
            parameter: 'low_pass_hz',
            delta: -1500.0 * i,
            rationale: 'Tense → lower cutoff narrows spectrum (claustrophobic)',
          ),
          MixDelta(
            stage: stage,
            parameter: 'tempo_pct',
            delta: -5.0 * i,
            rationale: 'Tense → slow tempo builds suspense',
          ),
        ];
      case Emotion.calm:
        return [
          MixDelta(
            stage: stage,
            parameter: 'volume_db',
            delta: -2.0 * i,
            rationale: 'Calm → quieter presence',
          ),
          MixDelta(
            stage: stage,
            parameter: 'reverb_dwell_ms',
            delta: 300.0 * i,
            rationale: 'Calm → long reverb dwell = serene space',
          ),
          MixDelta(
            stage: stage,
            parameter: 'tempo_pct',
            delta: -5.0 * i,
            rationale: 'Calm → slower tempo',
          ),
        ];
      case Emotion.aggressive:
        return [
          MixDelta(
            stage: stage,
            parameter: 'volume_db',
            delta: 3.0 * i,
            rationale: 'Aggressive → loud presence',
          ),
          MixDelta(
            stage: stage,
            parameter: 'saturation_pct',
            delta: 25.0 * i,
            rationale: 'Aggressive → harmonic saturation = grit',
          ),
          MixDelta(
            stage: stage,
            parameter: 'tempo_pct',
            delta: 8.0 * i,
            rationale: 'Aggressive → faster tempo = drive',
          ),
        ];
      case Emotion.dark:
        return [
          MixDelta(
            stage: stage,
            parameter: 'brightness_pct',
            delta: -20.0 * i,
            rationale: 'Dark → cut highs, emphasize low-mid',
          ),
          MixDelta(
            stage: stage,
            parameter: 'low_pass_hz',
            delta: -2500.0 * i,
            rationale: 'Dark → low-pass below 6kHz',
          ),
        ];
      case Emotion.bright:
        return [
          MixDelta(
            stage: stage,
            parameter: 'brightness_pct',
            delta: 20.0 * i,
            rationale: 'Bright → emphasize high-frequency content',
          ),
          MixDelta(
            stage: stage,
            parameter: 'volume_db',
            delta: 1.0 * i,
            rationale: 'Bright → slight volume lift',
          ),
        ];
      case Emotion.punchy:
        return [
          MixDelta(
            stage: stage,
            parameter: 'transient_pct',
            delta: 30.0 * i,
            rationale: 'Punchy → boost transient response',
          ),
          MixDelta(
            stage: stage,
            parameter: 'reverb_dwell_ms',
            delta: -150.0 * i,
            rationale: 'Punchy → less reverb = tighter',
          ),
        ];
      case Emotion.smooth:
        return [
          MixDelta(
            stage: stage,
            parameter: 'transient_pct',
            delta: -20.0 * i,
            rationale: 'Smooth → soften transients',
          ),
          MixDelta(
            stage: stage,
            parameter: 'reverb_dwell_ms',
            delta: 250.0 * i,
            rationale: 'Smooth → longer reverb glue',
          ),
        ];
      case Emotion.none:
        return const [];
    }
  }
}
