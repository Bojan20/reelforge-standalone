// FLUX_MASTER_TODO 0.5 F.2 — AI Recommender MVP (rule-based heuristics).
//
// MVP varijanta — pure heuristic rule engine, no LLM. Radi 100% offline,
// daje preporuke za:
//   * math profile (RTP, volatility, hit frequency, max win cap)
//   * feature stack (free spins, cascade, hold-and-win, gamble, multipliers)
//   * audio palette (high-energy / atmospheric / classical / cinematic)
//   * compliance pre-flight (LDW guard, near-miss cap, celebration limits)
//
// Inputs:
//   * `MarketSegment` — koje tržište (UK retail / MGA crypto / NV high-roller …)
//   * `PlayerProfile` — casual / engaged / high-stakes
//   * Optional: `targetMaxWin` cap (constraint)
//
// Output: `GameConfigRecommendation` sa structured rationale-om za svaki polje.
// UI sloja: konsumira rationale i prikazuje **zašto** je recommender odlučio
// tako, ne samo "evo brojeva". Onboarding bez tutorijala.
//
// Roadmap: F.2 full (Faza 4) zameni heuristics sa local LLM (Llama 3 8B).
// MVP heuristics ostaju kao baseline za A/B comparison sa LLM kad stigne.

import 'package:flutter/foundation.dart';

/// Tržišni segment — utiče na compliance + volatility recommendation.
enum MarketSegment {
  /// UK retail (UKGC) — strict LDW, max win caps, no auto-spin.
  ukRetail,

  /// MGA online crypto — relaxed compliance, high volatility expected.
  mgaCrypto,

  /// Sweden (Spelinspektionen) — moderate, PaymentMethods restriction.
  swedenRegulated,

  /// Nevada (NV) high-roller — high volatility, high max-win, jackpot-heavy.
  nvHighRoller,

  /// New Jersey (NJ) — balanced, moderate volatility, social casino style.
  njBalanced,

  /// Generic / no jurisdiction (development only).
  generic,
}

extension MarketSegmentExtension on MarketSegment {
  String get label => switch (this) {
        MarketSegment.ukRetail => 'UK Retail (UKGC)',
        MarketSegment.mgaCrypto => 'MGA Online (Crypto)',
        MarketSegment.swedenRegulated => 'Sweden Regulated',
        MarketSegment.nvHighRoller => 'Nevada High-Roller',
        MarketSegment.njBalanced => 'New Jersey',
        MarketSegment.generic => 'Generic / Dev',
      };

  /// Per-jurisdiction max-win caps (multiple of bet) — 2026 industry guidance.
  double get maxWinCap => switch (this) {
        MarketSegment.ukRetail => 5000,
        MarketSegment.mgaCrypto => 50000,
        MarketSegment.swedenRegulated => 10000,
        MarketSegment.nvHighRoller => 25000,
        MarketSegment.njBalanced => 10000,
        MarketSegment.generic => 50000,
      };

  /// Min RTP po jurisdikciji — regulator floor.
  double get minRtp => switch (this) {
        MarketSegment.ukRetail => 0.92,
        MarketSegment.mgaCrypto => 0.94,
        MarketSegment.swedenRegulated => 0.92,
        MarketSegment.nvHighRoller => 0.92,
        MarketSegment.njBalanced => 0.93,
        MarketSegment.generic => 0.85,
      };

  /// Max RTP po jurisdikciji — operator ceiling (above ovog je gubitak).
  double get maxRtp => 0.97;
}

/// Player profile — utiče na hit frequency + audio energy.
enum PlayerProfile {
  /// Casual — frekventni mali wins, spori tempo, kompenzacija mala.
  casual,

  /// Engaged — moderate volatility, mix tempo, moderate big wins.
  engaged,

  /// High-stakes — visok volatility, retki ali ogromni wins, intense audio.
  highStakes,
}

extension PlayerProfileExtension on PlayerProfile {
  String get label => switch (this) {
        PlayerProfile.casual => 'Casual (frequent small wins)',
        PlayerProfile.engaged => 'Engaged (balanced)',
        PlayerProfile.highStakes => 'High-Stakes (rare big wins)',
      };
}

/// Audio palette stil — utiče na bus configuration + composition.
enum AudioPaletteStyle {
  /// High-energy electronic — EDM, modern hits, dancing.
  highEnergy,

  /// Atmospheric — ambient pads, slow build, mystery.
  atmospheric,

  /// Classical / orchestral — strings, brass, pomp & circumstance.
  classical,

  /// Cinematic — film-score style, large dynamic range.
  cinematic,
}

extension AudioPaletteStyleExtension on AudioPaletteStyle {
  String get label => switch (this) {
        AudioPaletteStyle.highEnergy => 'High-Energy (EDM)',
        AudioPaletteStyle.atmospheric => 'Atmospheric (Ambient)',
        AudioPaletteStyle.classical => 'Classical (Orchestral)',
        AudioPaletteStyle.cinematic => 'Cinematic (Film-Score)',
      };
}

/// Math profile — set numeričkih targets za game design.
class MathProfile {
  /// Return to Player [0..1].
  final double rtp;

  /// Volatility 1-10 (industry scale: 1=ultra-low, 10=ultra-high).
  final int volatility;

  /// Hit frequency [0..1] — fraction of spins that produce ANY win.
  final double hitFrequency;

  /// Max win cap (multiple of bet).
  final double maxWinMultiplier;

  /// Bonus frequency (1-in-N spins).
  final int bonusFrequencyOneIn;

  const MathProfile({
    required this.rtp,
    required this.volatility,
    required this.hitFrequency,
    required this.maxWinMultiplier,
    required this.bonusFrequencyOneIn,
  });

  Map<String, dynamic> toJson() => {
        'rtp': rtp,
        'volatility': volatility,
        'hit_frequency': hitFrequency,
        'max_win_multiplier': maxWinMultiplier,
        'bonus_frequency_one_in': bonusFrequencyOneIn,
      };
}

/// Feature stack — koje feature-e uključiti.
class FeatureStack {
  final bool freeSpins;
  final bool cascade;
  final bool holdAndWin;
  final bool gamble;
  final bool wildMultiplier;
  final bool expandingWilds;

  const FeatureStack({
    this.freeSpins = false,
    this.cascade = false,
    this.holdAndWin = false,
    this.gamble = false,
    this.wildMultiplier = false,
    this.expandingWilds = false,
  });

  Map<String, dynamic> toJson() => {
        'free_spins': freeSpins,
        'cascade': cascade,
        'hold_and_win': holdAndWin,
        'gamble': gamble,
        'wild_multiplier': wildMultiplier,
        'expanding_wilds': expandingWilds,
      };

  int get featureCount {
    int n = 0;
    if (freeSpins) n++;
    if (cascade) n++;
    if (holdAndWin) n++;
    if (gamble) n++;
    if (wildMultiplier) n++;
    if (expandingWilds) n++;
    return n;
  }
}

/// Compliance flags — pre-flight upozorenja vezano za izabrani segment.
class ComplianceFlags {
  /// Mora imati LDW guard (Loss Disguised as Win) ako se win < bet
  /// celebriraju kao "win" sa fanfare.
  final bool requiresLdwGuard;

  /// Near-miss quota cap (ratio od total spinova).
  final double nearMissQuotaCap;

  /// Celebration duration cap (ms) — UKGC strict.
  final int celebrationDurationCapMs;

  /// Auto-spin allowed?
  final bool autoSpinAllowed;

  const ComplianceFlags({
    required this.requiresLdwGuard,
    required this.nearMissQuotaCap,
    required this.celebrationDurationCapMs,
    required this.autoSpinAllowed,
  });

  Map<String, dynamic> toJson() => {
        'requires_ldw_guard': requiresLdwGuard,
        'near_miss_quota_cap': nearMissQuotaCap,
        'celebration_duration_cap_ms': celebrationDurationCapMs,
        'auto_spin_allowed': autoSpinAllowed,
      };
}

/// Recommendation rationale — par (key → human-readable razlog).
class RecommendationRationale {
  final String field;
  final dynamic value;
  final String reason;
  final String source; // koji rule pravilo je prouzrokovalo ovo

  const RecommendationRationale({
    required this.field,
    required this.value,
    required this.reason,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'field': field,
        'value': value,
        'reason': reason,
        'source_rule': source,
      };
}

/// Complete game config recommendation.
class GameConfigRecommendation {
  final MarketSegment market;
  final PlayerProfile player;
  final MathProfile math;
  final FeatureStack features;
  final AudioPaletteStyle audioPalette;
  final ComplianceFlags compliance;
  final List<RecommendationRationale> rationale;

  const GameConfigRecommendation({
    required this.market,
    required this.player,
    required this.math,
    required this.features,
    required this.audioPalette,
    required this.compliance,
    required this.rationale,
  });

  Map<String, dynamic> toJson() => {
        'market': market.name,
        'player': player.name,
        'math': math.toJson(),
        'features': features.toJson(),
        'audio_palette': audioPalette.name,
        'compliance': compliance.toJson(),
        'rationale': rationale.map((r) => r.toJson()).toList(),
      };
}

/// Singleton heuristic recommender. No LLM, no async, no I/O — pure compute.
class GameConfigRecommender extends ChangeNotifier {
  static final GameConfigRecommender instance = GameConfigRecommender._();
  GameConfigRecommender._();

  GameConfigRecommendation? _last;
  GameConfigRecommendation? get last => _last;

  /// Generiše recommendation za dati input. Idempotent — isti input daje isti output.
  GameConfigRecommendation recommend({
    required MarketSegment market,
    required PlayerProfile player,
    double? targetMaxWin,
  }) {
    final rationale = <RecommendationRationale>[];

    // ── RTP ────────────────────────────────────────────────────────────
    final rtp = _recommendRtp(market, player, rationale);

    // ── Volatility ─────────────────────────────────────────────────────
    final volatility = _recommendVolatility(market, player, rationale);

    // ── Hit frequency (inverse of volatility) ──────────────────────────
    final hitFreq = _recommendHitFrequency(volatility, rationale);

    // ── Max win cap ────────────────────────────────────────────────────
    final maxWin = _recommendMaxWin(market, targetMaxWin, rationale);

    // ── Bonus frequency ────────────────────────────────────────────────
    final bonusFreq = _recommendBonusFrequency(volatility, rationale);

    // ── Feature stack ──────────────────────────────────────────────────
    final features = _recommendFeatures(market, player, rationale);

    // ── Audio palette ──────────────────────────────────────────────────
    final audio = _recommendAudio(market, player, rationale);

    // ── Compliance ─────────────────────────────────────────────────────
    final compliance = _recommendCompliance(market, rationale);

    final report = GameConfigRecommendation(
      market: market,
      player: player,
      math: MathProfile(
        rtp: rtp,
        volatility: volatility,
        hitFrequency: hitFreq,
        maxWinMultiplier: maxWin,
        bonusFrequencyOneIn: bonusFreq,
      ),
      features: features,
      audioPalette: audio,
      compliance: compliance,
      rationale: rationale,
    );
    _last = report;
    notifyListeners();
    return report;
  }

  // ── Rule implementations ────────────────────────────────────────────

  double _recommendRtp(
    MarketSegment market,
    PlayerProfile player,
    List<RecommendationRationale> log,
  ) {
    double rtp;
    String reason;
    String source;

    switch (player) {
      case PlayerProfile.casual:
        // Casual — ka višim RTP-ima, više češćih malih wins.
        rtp = market.minRtp + (market.maxRtp - market.minRtp) * 0.7;
        reason = 'Casual igrači reaguju pozitivno na češće male wins; RTP '
            'pomeren ka jurisdikcijskom plafonu (max ${market.maxRtp}).';
        source = 'rule_casual_rtp_high';
        break;
      case PlayerProfile.engaged:
        rtp = market.minRtp + (market.maxRtp - market.minRtp) * 0.5;
        reason = 'Engaged igrač = balanced — sredina RTP raspona '
            '(${market.minRtp}-${market.maxRtp}).';
        source = 'rule_engaged_rtp_mid';
        break;
      case PlayerProfile.highStakes:
        rtp = market.minRtp + (market.maxRtp - market.minRtp) * 0.85;
        reason = 'High-stakes treba visok RTP da kompenzuje varijancu retkih '
            'big wins (psihološki: igrač oseća "fair").';
        source = 'rule_highstakes_rtp_high';
        break;
    }

    rtp = rtp.clamp(market.minRtp, market.maxRtp);
    log.add(RecommendationRationale(
      field: 'rtp',
      value: double.parse(rtp.toStringAsFixed(4)),
      reason: reason,
      source: source,
    ));
    return double.parse(rtp.toStringAsFixed(4));
  }

  int _recommendVolatility(
    MarketSegment market,
    PlayerProfile player,
    List<RecommendationRationale> log,
  ) {
    int v;
    String reason;
    String source;

    switch (player) {
      case PlayerProfile.casual:
        v = 3; // ultra-low volatility
        reason = 'Casual = low volatility (1-3). Mali ali česti wins, '
            'predvidljiv gameplay.';
        source = 'rule_casual_volatility_low';
        break;
      case PlayerProfile.engaged:
        v = 6; // moderate
        reason = 'Engaged = medium volatility (5-7). Mix predviđenih i '
            'iznenadnih win momenata.';
        source = 'rule_engaged_volatility_mid';
        break;
      case PlayerProfile.highStakes:
        v = 9; // high
        reason = 'High-stakes = high volatility (8-10). Retki ali masivni '
            'wins, intense session.';
        source = 'rule_highstakes_volatility_high';
        break;
    }

    // MGA crypto market dozvoljava + 1 volatility tier (loosely regulated).
    if (market == MarketSegment.mgaCrypto && v < 10) {
      v += 1;
      log.add(RecommendationRationale(
        field: 'volatility_market_adjustment',
        value: '+1 (MGA crypto)',
        reason: 'MGA online crypto market dozvoljava agresivniju volatility — '
            'igrači očekuju veću varijancu od retail jurisdikcija.',
        source: 'rule_mga_volatility_bonus',
      ));
    }
    // UK retail clamping na max 7 (UKGC frowns na ekstremnu volatility).
    if (market == MarketSegment.ukRetail && v > 7) {
      v = 7;
      log.add(RecommendationRationale(
        field: 'volatility_market_clamp',
        value: 'capped at 7',
        reason: 'UKGC nikad nije izričito zabranio visoku volatility ali '
            'enforcement guidance favorizuje moderaciju.',
        source: 'rule_ukgc_volatility_cap',
      ));
    }

    log.add(RecommendationRationale(
      field: 'volatility',
      value: v,
      reason: reason,
      source: source,
    ));
    return v;
  }

  double _recommendHitFrequency(
    int volatility,
    List<RecommendationRationale> log,
  ) {
    // Industry inverse: low volatility = high hit freq, high vol = low freq.
    // Ova formula je kalibrisana na ~30 referentnih slot-ova.
    final hf = (0.45 - (volatility - 1) * 0.025).clamp(0.15, 0.45);
    log.add(RecommendationRationale(
      field: 'hit_frequency',
      value: double.parse(hf.toStringAsFixed(3)),
      reason: 'Inverzno korelirano sa volatility ($volatility) — viša '
          'volatility znači retkije wins ali veće. Kalibrisano na ~30 '
          'referentnih slot-ova.',
      source: 'rule_inverse_volatility_hit_freq',
    ));
    return double.parse(hf.toStringAsFixed(3));
  }

  double _recommendMaxWin(
    MarketSegment market,
    double? userTarget,
    List<RecommendationRationale> log,
  ) {
    final cap = market.maxWinCap;
    double recommendation;
    String reason;
    String source;

    if (userTarget != null) {
      if (userTarget > cap) {
        recommendation = cap;
        reason = 'User target ($userTarget×) prelazi jurisdikcijski cap '
            '(${cap}×) — clamped na cap.';
        source = 'rule_max_win_user_target_clamped';
      } else {
        recommendation = userTarget;
        reason = 'User target prihvaćen (ispod jurisdikcijskog cap-a $cap×).';
        source = 'rule_max_win_user_target_accepted';
      }
    } else {
      recommendation = cap;
      reason = 'Bez user target-a — koristi se jurisdikcijski default '
          '(${market.label}).';
      source = 'rule_max_win_jurisdiction_default';
    }

    log.add(RecommendationRationale(
      field: 'max_win_multiplier',
      value: recommendation,
      reason: reason,
      source: source,
    ));
    return recommendation;
  }

  int _recommendBonusFrequency(
    int volatility,
    List<RecommendationRationale> log,
  ) {
    // Industry-typical: 1-in-100 (low vol) … 1-in-300 (high vol).
    final freq = (80 + volatility * 22).clamp(80, 300);
    log.add(RecommendationRationale(
      field: 'bonus_frequency_one_in',
      value: freq,
      reason: 'Skalirano sa volatility — 1-in-$freq spinova. Niža frekvencija '
          'kod više volatility čuva big-win retkost.',
      source: 'rule_bonus_freq_scale_volatility',
    ));
    return freq;
  }

  FeatureStack _recommendFeatures(
    MarketSegment market,
    PlayerProfile player,
    List<RecommendationRationale> log,
  ) {
    // Bazna preporuka — free spins UVEK (industry default 95%+ slot-ova).
    var fs = const FeatureStack(freeSpins: true);
    log.add(const RecommendationRationale(
      field: 'feature.free_spins',
      value: true,
      reason: 'Industry default — 95%+ slot-ova ima Free Spins; igrač očekuje.',
      source: 'rule_features_fs_default',
    ));

    // Cascade — popular kod casual + engaged, manje kod high-stakes (brzina).
    if (player != PlayerProfile.highStakes) {
      fs = FeatureStack(
        freeSpins: fs.freeSpins,
        cascade: true,
      );
      log.add(const RecommendationRationale(
        field: 'feature.cascade',
        value: true,
        reason: 'Cascade pojačava engagement kod casual + engaged playera; '
            'high-stakes preferira brzi single-spin pace.',
        source: 'rule_features_cascade_casual_engaged',
      ));
    }

    // Hold & Win — high-stakes + njBalanced market preferira.
    if (player == PlayerProfile.highStakes ||
        market == MarketSegment.njBalanced) {
      fs = FeatureStack(
        freeSpins: fs.freeSpins,
        cascade: fs.cascade,
        holdAndWin: true,
      );
      log.add(const RecommendationRationale(
        field: 'feature.hold_and_win',
        value: true,
        reason: 'High-stakes player + NJ market — Hold & Win daje "agency" '
            'osećaj kontrole.',
        source: 'rule_features_hnw_highstakes_nj',
      ));
    }

    // Gamble — UKGC zabranjuje "double or nothing" funkcijuje koje
    // produžavaju session bez nove uloge → SKIP za UK.
    if (market != MarketSegment.ukRetail) {
      fs = FeatureStack(
        freeSpins: fs.freeSpins,
        cascade: fs.cascade,
        holdAndWin: fs.holdAndWin,
        gamble: true,
      );
      log.add(const RecommendationRationale(
        field: 'feature.gamble',
        value: true,
        reason: 'Gamble (double-or-nothing) prihvaćen u svim jurisdikcijama '
            'osim UKGC (zabrana session-extension features).',
        source: 'rule_features_gamble_non_uk',
      ));
    }

    // Wild multiplier — high-stakes + high volatility.
    if (player == PlayerProfile.highStakes) {
      fs = FeatureStack(
        freeSpins: fs.freeSpins,
        cascade: fs.cascade,
        holdAndWin: fs.holdAndWin,
        gamble: fs.gamble,
        wildMultiplier: true,
        expandingWilds: true,
      );
      log.add(const RecommendationRationale(
        field: 'feature.wild_multiplier',
        value: true,
        reason: 'High-stakes — wild multipliers + expanding wilds maksimizuju '
            'big-win potential.',
        source: 'rule_features_wild_multiplier_highstakes',
      ));
    }

    return fs;
  }

  AudioPaletteStyle _recommendAudio(
    MarketSegment market,
    PlayerProfile player,
    List<RecommendationRationale> log,
  ) {
    AudioPaletteStyle style;
    String reason;
    String source;

    switch (player) {
      case PlayerProfile.casual:
        style = AudioPaletteStyle.atmospheric;
        reason = 'Casual = ambient pads, smiren tempo, ne preopterećuje '
            'tokom dugih session-a.';
        source = 'rule_audio_casual_atmospheric';
        break;
      case PlayerProfile.engaged:
        style = AudioPaletteStyle.cinematic;
        reason = 'Engaged = filmska dramaturgija, dynamic range podržava '
            'oscilacije win/loss tension.';
        source = 'rule_audio_engaged_cinematic';
        break;
      case PlayerProfile.highStakes:
        style = AudioPaletteStyle.highEnergy;
        reason = 'High-stakes = EDM/high-energy, intense session, kratki '
            'attention spans, brzi tempo.';
        source = 'rule_audio_highstakes_high_energy';
        break;
    }

    // NV high-roller market preferira classical/orchestral (Las Vegas heritage).
    if (market == MarketSegment.nvHighRoller) {
      style = AudioPaletteStyle.classical;
      reason = 'Nevada high-roller heritage — orchestral palette evocira '
          'classic Vegas casino floor estetiku.';
      source = 'rule_audio_nv_classical_override';
    }

    log.add(RecommendationRationale(
      field: 'audio_palette',
      value: style.label,
      reason: reason,
      source: source,
    ));
    return style;
  }

  ComplianceFlags _recommendCompliance(
    MarketSegment market,
    List<RecommendationRationale> log,
  ) {
    final ldw = market != MarketSegment.generic;
    final nearMissCap = switch (market) {
      MarketSegment.ukRetail => 0.02, // UKGC strict 2%
      MarketSegment.swedenRegulated => 0.025,
      MarketSegment.njBalanced => 0.03,
      MarketSegment.mgaCrypto => 0.05,
      MarketSegment.nvHighRoller => 0.05,
      MarketSegment.generic => 0.10,
    };
    final celebMs = switch (market) {
      MarketSegment.ukRetail => 1500, // UKGC strict
      MarketSegment.swedenRegulated => 2000,
      MarketSegment.njBalanced => 2500,
      MarketSegment.mgaCrypto => 4000,
      MarketSegment.nvHighRoller => 5000,
      MarketSegment.generic => 5000,
    };
    final autoSpin = market != MarketSegment.ukRetail;

    log.add(RecommendationRationale(
      field: 'compliance.requires_ldw_guard',
      value: ldw,
      reason: ldw
          ? 'LDW guard je MANDATORY u svim regulisanim jurisdikcijama — '
              'wins manji od ulога ne smeju biti celebrirani sa fanfare.'
          : 'Generic / dev mode — LDW guard preporučljiv ali ne obavezan.',
      source: 'rule_compliance_ldw',
    ));
    log.add(RecommendationRationale(
      field: 'compliance.near_miss_quota_cap',
      value: nearMissCap,
      reason: 'Per-jurisdiction near-miss quota — UKGC najstrožji '
          '(2%), MGA crypto najlibralniji (5%).',
      source: 'rule_compliance_near_miss',
    ));
    log.add(RecommendationRationale(
      field: 'compliance.celebration_duration_cap_ms',
      value: celebMs,
      reason: 'Win celebration trajanje — UKGC ${celebMs}ms cap je strogo '
          'enforce-an (ne smeju duge fanfare za male wins).',
      source: 'rule_compliance_celebration_duration',
    ));
    log.add(RecommendationRationale(
      field: 'compliance.auto_spin_allowed',
      value: autoSpin,
      reason: autoSpin
          ? 'Auto-spin dozvoljen u ovoj jurisdikciji.'
          : 'UKGC zabranjuje auto-spin (od 2021) — mora manual click.',
      source: 'rule_compliance_auto_spin',
    ));

    return ComplianceFlags(
      requiresLdwGuard: ldw,
      nearMissQuotaCap: nearMissCap,
      celebrationDurationCapMs: celebMs,
      autoSpinAllowed: autoSpin,
    );
  }
}
