/// CopilotExplainer — H.4 / 2B.3.7 "Context menu Explain this"
///
/// Rule-based param explanation service for slot audio parameters.
/// Pre-populated with ~60 industry-standard slot audio params covering:
/// voice/budget, timing/duration, win tiers, game math, compliance, and
/// audio engineering parameters.
///
/// No LLM/cloud required — deterministic, offline, zero latency.
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Rich explanation for a single slot audio parameter.
@immutable
class ParamExplanation {
  /// Unique param ID, e.g. "voice_budget"
  final String id;

  /// Human-readable title, e.g. "Voice Budget"
  final String title;

  /// 2–3 sentence description of what this param is and why it matters.
  final String description;

  /// Industry typical values / ranges.
  final String typicalValues;

  /// Unit string: "voices", "dB", "ms", "%", etc. May be null.
  final String? unit;

  /// Compliance note (UKGC / MGA / SE) if applicable. May be null.
  final String? complianceNote;

  /// Related rf-copilot rule ID, e.g. "R-VB-1". May be null.
  final String? relatedRuleId;

  /// 1–3 actionable tips for audio designers.
  final List<String> tips;

  const ParamExplanation({
    required this.id,
    required this.title,
    required this.description,
    required this.typicalValues,
    this.unit,
    this.complianceNote,
    this.relatedRuleId,
    this.tips = const [],
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// GetIt singleton. Call [explain] or [explainFuzzy] to retrieve explanations.
class CopilotExplainer extends ChangeNotifier {
  CopilotExplainer() {
    _buildRegistry();
  }

  final Map<String, ParamExplanation> _registry = {};

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Exact lookup by param ID. Returns null if not found.
  ParamExplanation? explain(String paramId) => _registry[paramId];

  /// Fuzzy lookup: normalises [hint] to snake_case and tries exact match first,
  /// then falls back to substring matching across all registered IDs.
  ParamExplanation? explainFuzzy(String hint) {
    final normalized = hint.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

    // 1) exact match after normalisation
    if (_registry.containsKey(normalized)) return _registry[normalized];

    // 2) substring: hint appears inside registered ID
    for (final entry in _registry.entries) {
      if (entry.key.contains(normalized)) return entry.value;
    }

    // 3) substring: any word of normalised hint appears inside registered ID
    final words = normalized.split('_').where((w) => w.length > 2).toList();
    for (final word in words) {
      for (final entry in _registry.entries) {
        if (entry.key.contains(word)) return entry.value;
      }
    }

    return null;
  }

  /// Register a custom explanation at runtime (extensibility hook).
  void registerCustom(String id, ParamExplanation p) {
    _registry[id] = p;
    notifyListeners();
  }

  // ─── Registry Builder ────────────────────────────────────────────────────────

  void _buildRegistry() {
    final entries = <ParamExplanation>[
      // ── Voice / Budget ──────────────────────────────────────────────────────

      const ParamExplanation(
        id: 'voice_budget',
        title: 'Voice Budget',
        description:
            'The maximum number of audio voices (channels) that can play '
            'simultaneously on this slot title. Each active sound occupies one '
            'voice; exceeding the budget triggers voice stealing. Setting the '
            'budget too low causes audible cutouts; too high wastes CPU cycles '
            'on the gaming cabinet.',
        typicalValues: '24–64 voices for most slot titles; 48 is industry standard',
        unit: 'voices',
        complianceNote: null,
        relatedRuleId: 'R-VB-1',
        tips: [
          'Profile peak usage during free-spins bonus — that is usually the highest-voice moment.',
          'Reserve at least 4 voices for ambient loops so they are never stolen.',
          'Use priority weights (audio_weight) to control which sounds are culled first.',
        ],
      ),

      const ParamExplanation(
        id: 'estimated_peak_voices',
        title: 'Estimated Peak Voices',
        description:
            'The highest voice count recorded (or predicted via simulation) '
            'during a representative playback session. Used by the AI Co-Pilot '
            'to verify that voice_budget is not exceeded under worst-case '
            'conditions such as a max-win celebration with ambient music.',
        typicalValues: 'Should stay at or below voice_budget (typically ≤ 64)',
        unit: 'voices',
        relatedRuleId: 'R-VB-1',
        tips: [
          'Run the Simulation Engine on the jackpot stage to get reliable peak estimates.',
          'If peak exceeds budget, tighten voice_count on lower-priority events first.',
        ],
      ),

      const ParamExplanation(
        id: 'voice_count',
        title: 'Voice Count',
        description:
            'The number of voices allocated for a specific audio event. '
            'For layered events (e.g. a win celebration with stinger + ambient '
            'swell + VO) each layer uses one voice. Controlling per-event '
            'counts is the primary tool for staying within voice_budget.',
        typicalValues: '1–4 for most events; 6–8 for complex flagship wins',
        unit: 'voices',
        relatedRuleId: 'R-VB-1',
        tips: [
          'Prefer 1–2 voices for near-miss and reel-stop events.',
          'Jackpot and feature-trigger events can justify 4–8 layers.',
        ],
      ),

      const ParamExplanation(
        id: 'audio_weight',
        title: 'Audio Priority Weight',
        description:
            'A normalised priority value (0.0 = lowest, 1.0 = highest) used '
            'by the voice stealing algorithm when the voice budget is '
            'exhausted. Higher-weight voices remain playing; lower-weight '
            'voices are culled first. Critical sounds (win stingers, VO) '
            'should always be 1.0; ambient beds should be 0.2–0.4.',
        typicalValues: '0.0–1.0; win/VO: 1.0; ambient: 0.2–0.4; UI: 0.6–0.8',
        unit: 'weight (0–1)',
        relatedRuleId: 'R-PO-1',
        tips: [
          'Set near_miss_audio weight below win_celebration to prevent confusion.',
          'Ambient loops should be the first candidates for stealing — keep them at 0.2.',
          'Never set audio_weight to 0 for compliance-critical sounds (LDW guard).',
        ],
      ),

      // ── Timing / Duration ───────────────────────────────────────────────────

      const ParamExplanation(
        id: 'duration_ms',
        title: 'Duration (ms)',
        description:
            'The total playback duration of an audio event in milliseconds. '
            'Precise timing is critical in slot audio because it must '
            'synchronise with visual animations — reel stops, win reveals, and '
            'feature transitions all have frame-accurate sync requirements.',
        typicalValues: 'Varies by event type; see spin_start_duration, reel_stop_duration, etc.',
        unit: 'ms',
        tips: [
          'Match duration to the corresponding animation length exported from the game engine.',
          'Add 50–100 ms of tail silence to avoid abrupt cutoffs on shorter clips.',
        ],
      ),

      const ParamExplanation(
        id: 'spin_start_duration',
        title: 'Spin Start Duration',
        description:
            'Duration of the audio event triggered when the player presses the '
            'spin button. This is a high-frequency event that fires every spin '
            'and must feel responsive. Too long and it overlaps with reel-spin '
            'audio; too short and it sounds weak.',
        typicalValues: '150–250 ms (industry benchmark)',
        unit: 'ms',
        relatedRuleId: 'R-TB-1',
        tips: [
          'Keep under 250 ms for snappy feel — aim for 180 ms as a baseline.',
          'Layer a transient "click" at the very start to reinforce button feedback.',
        ],
      ),

      const ParamExplanation(
        id: 'reel_stop_duration',
        title: 'Reel Stop Duration',
        description:
            'Duration of the sound played as each reel comes to rest. In a '
            'five-reel sequential stop, the last two stops often use the '
            'anticipation variant which is longer. Reel-stop sounds must align '
            'with the physical bounce animation of the reels.',
        typicalValues: '200–400 ms per reel stop; anticipation variants 600–1200 ms',
        unit: 'ms',
        relatedRuleId: 'R-TB-1',
        tips: [
          'Use a slightly longer duration on reels 4–5 to build tension.',
          'Keep the transient sharp (< 50 ms attack) so the stop feels physical.',
        ],
      ),

      const ParamExplanation(
        id: 'anticipation_duration',
        title: 'Anticipation Duration',
        description:
            'Duration of the tension-building audio event that plays before '
            'the final reels stop when a potential big win is detected. This '
            'is one of the most emotionally potent events in a slot and '
            'directly impacts the perceived excitement of the game.',
        typicalValues: '1500–4000 ms; 2000–2500 ms is the industry sweet spot',
        unit: 'ms',
        tips: [
          'Use a rising filter sweep or ascending note progression for maximum tension.',
          'Crossfade back to ambient at the end if no win occurs — avoid abrupt silence.',
        ],
      ),

      const ParamExplanation(
        id: 'win_celebration_duration',
        title: 'Win Celebration Duration',
        description:
            'Total duration of the win celebration audio sequence. Must be '
            'proportional to win size — small wins use short clips while '
            'flagship wins use extended orchestral builds. Oversized '
            'celebrations on small wins violate celebration_proportionality '
            'compliance rules.',
        typicalValues: 'Subtle: 400–800 ms | Standard: 800–2000 ms | Prominent: 2000–6000 ms | Flagship: 8000–30000 ms',
        unit: 'ms',
        complianceNote: 'MGA/UKGC: Audio intensity must be proportional to win value. Using a long celebration for a small win can be flagged as misleading.',
        tips: [
          'Map win tier thresholds to duration ranges in WinTierConfig — never hardcode.',
          'Loop the middle section of flagship wins rather than creating a single 30-second file.',
        ],
      ),

      const ParamExplanation(
        id: 'ambient_loop_duration',
        title: 'Ambient Loop Duration',
        description:
            'The duration of the ambient background music loop. Loops that '
            'are too short become perceptible and annoying to players during '
            'extended sessions. Regulatory bodies also monitor for repetitive '
            'audio patterns that may induce trance-like states.',
        typicalValues: '30 seconds minimum; 60–120 seconds recommended',
        unit: 'ms',
        complianceNote: 'SE (Spelinspektionen): Repetitive audio patterns in ambient loops are a responsible gaming concern. Minimum 30 s loop length is an industry best practice.',
        relatedRuleId: 'R-TB-2',
        tips: [
          'Use at least a 60-second loop to avoid obvious repetition.',
          'Add subtle variation at the 30-second mark (e.g., a different percussion fill).',
        ],
      ),

      const ParamExplanation(
        id: 'feature_trigger_duration',
        title: 'Feature Trigger Duration',
        description:
            'Duration of the audio event that fires when the free spins or '
            'bonus game is activated. This is a peak excitement moment and '
            'should feel substantial and rewarding while transitioning cleanly '
            'into the feature ambient music.',
        typicalValues: '3000–8000 ms; 4000–5000 ms is common',
        unit: 'ms',
        tips: [
          'End with a 500–800 ms crossfade into the free-spins ambient bed.',
          'Ensure the stinger does not overlap with the first reel spin of the feature.',
        ],
      ),

      const ParamExplanation(
        id: 'jackpot_duration_grand',
        title: 'Grand Jackpot Duration',
        description:
            'Total duration of the Grand Jackpot celebration sequence. Grand '
            'jackpots are the rarest and highest-value wins and deserve the '
            'most elaborate audio treatment, often including a coin counter '
            'sequence, orchestral build, and VO stinger.',
        typicalValues: '25000–40000 ms (25–40 seconds)',
        unit: 'ms',
        tips: [
          'Structure as: intro (2s) → coin counter loop (10–20s) → climax stinger (3s) → outro (5s).',
          'Ensure the loop point in the coin counter section is seamless.',
        ],
      ),

      const ParamExplanation(
        id: 'jackpot_duration_mini',
        title: 'Mini Jackpot Duration',
        description:
            'Duration of the Mini Jackpot celebration. Mini jackpots are '
            'frequent enough that overly long celebrations would interrupt '
            'gameplay flow, but still deserve more than a standard win sound.',
        typicalValues: '2000–4000 ms',
        unit: 'ms',
        tips: [
          'Keep under 4 seconds to avoid disrupting play rhythm.',
          'Use a distinct but shorter version of the major jackpot motif.',
        ],
      ),

      // ── Win Tiers ───────────────────────────────────────────────────────────

      const ParamExplanation(
        id: 'win_tier',
        title: 'Win Tier',
        description:
            'The classification of a win into one of four standardised '
            'tiers: Subtle, Standard, Prominent, and Flagship. Each tier '
            'maps to a defined bet-multiple range and drives the audio '
            'duration, intensity, and celebration style. The tier system '
            'ensures audio is always proportional to win value.',
        typicalValues: 'subtle | standard | prominent | flagship',
        complianceNote: 'MGA/UKGC: All audio responses must map to a verifiable win tier hierarchy. Ad-hoc celebration sizing without a tier system is a compliance risk.',
        tips: [
          'Define tier thresholds in WinTierConfig — never hardcode bet multiples.',
          'Verify that tier boundaries do not overlap (a win cannot be in two tiers).',
        ],
      ),

      const ParamExplanation(
        id: 'win_duration_ratio',
        title: 'Win Duration Ratio',
        description:
            'The ratio of the longest win celebration duration to the '
            'shortest. A high ratio (e.g. 40×) gives a large dynamic '
            'range between small and large wins. The ratio must remain '
            'perceptible to players but should not make minor wins feel '
            'trivial.',
        typicalValues: '10:1 minimum; 40:1 is industry standard',
        unit: 'ratio',
        complianceNote: 'R-WT-2: The ratio between the largest and smallest win durations must be at least 10:1 to ensure proportionality.',
        relatedRuleId: 'R-WT-2',
        tips: [
          'Flagship (30s) ÷ Subtle (0.6s) = 50× ratio — a good target.',
          'Use the Simulation Engine to auto-check this ratio across all projects.',
        ],
      ),

      const ParamExplanation(
        id: 'tier_subtle',
        title: 'Tier: Subtle',
        description:
            'The lowest win tier, for wins less than 2× the total bet. '
            'Audio should be brief and understated — a light chime or coin '
            'clink. It must NOT use the same audio as higher tiers and must '
            'NOT use win audio if the win ≤ bet (LDW rule).',
        typicalValues: 'Wins < 2× bet; duration < 800 ms',
        unit: 'ms',
        complianceNote: 'UKGC/MGA: Wins equal to or less than the total bet must NOT trigger any win sound (Loss Disguised as Win rule).',
        tips: [
          'Keep this tier\'s audio clearly distinct from near_miss_audio.',
          'If win == bet, use silence or a neutral non-celebratory sound.',
        ],
      ),

      const ParamExplanation(
        id: 'tier_standard',
        title: 'Tier: Standard',
        description:
            'Mid-range wins from 2× to 10× the bet. The most common win '
            'tier in normal base-game play. Audio should feel rewarding '
            'without overshadowing the gameplay loop. Coin cascade effects '
            'are common here.',
        typicalValues: 'Wins 2–10× bet; duration 800–2000 ms',
        unit: 'ms',
        tips: [
          'Use a short melody fragment that shares motifs with higher tiers for brand consistency.',
          'Add a coin cascade layer proportional to the win amount within the tier.',
        ],
      ),

      const ParamExplanation(
        id: 'tier_prominent',
        title: 'Tier: Prominent',
        description:
            'High-value wins from 10× to 50× the bet. These are exciting '
            'events that slow the pace of play. Audio should be '
            'multi-layered, building from a stinger into a short melodic '
            'phrase. Coin counters are expected.',
        typicalValues: 'Wins 10–50× bet; duration 2000–6000 ms',
        unit: 'ms',
        tips: [
          'Include a coin counter loop that matches the payline total on screen.',
          'Transition cleanly back to base-game ambient when the sequence ends.',
        ],
      ),

      const ParamExplanation(
        id: 'tier_flagship',
        title: 'Tier: Flagship',
        description:
            'The highest win tier for wins exceeding 50× the bet. These '
            'are rare, high-emotion events that deserve the full production '
            'treatment: orchestral build, VO stinger, coin cascade, and '
            'extended loop. The cabinet may also trigger lighting effects '
            'synced to this audio.',
        typicalValues: 'Wins > 50× bet; duration 8000–30000 ms',
        unit: 'ms',
        complianceNote: 'MGA: Extended celebrations (>10s) must not be misleading about win value relative to bet.',
        tips: [
          'Structure as a three-phase sequence: build → peak → outro.',
          'Sync the coin counter animation tick to audio beats for emotional impact.',
        ],
      ),

      // ── Game Math ───────────────────────────────────────────────────────────

      const ParamExplanation(
        id: 'rtp_target',
        title: 'RTP Target',
        description:
            'Return to Player percentage — the theoretical long-run '
            'percentage of wagered money returned to players as winnings. '
            'RTP is the primary regulatory compliance metric for slots and '
            'directly affects the game\'s approval by gaming commissions.',
        typicalValues: '94–97.5% for most certified slots',
        unit: '%',
        complianceNote: 'UKGC minimum: 92% RTP. MGA minimum: 85% RTP. SE (Spelinspektionen): 92%+ typical. RTPs must be certified and published.',
        relatedRuleId: 'R-RG-1',
        tips: [
          'Always verify RTP with the certified math model — audio does not affect RTP but must be tested alongside it.',
          'Use the Math-Audio Bridge to flag audio events that misrepresent win frequency.',
        ],
      ),

      const ParamExplanation(
        id: 'volatility',
        title: 'Volatility',
        description:
            'Describes the risk/reward profile of the slot — how often '
            'wins occur and how large they tend to be. Low volatility means '
            'frequent small wins; high/extreme volatility means rare but '
            'large wins. Volatility directly informs how the audio should '
            'be paced and what tier events should dominate.',
        typicalValues: 'low | medium | high | extreme',
        tips: [
          'High volatility slots should have more dramatic anticipation audio — long dry spells need tension relief.',
          'Low volatility slots benefit from frequent short celebrations to maintain engagement.',
        ],
      ),

      const ParamExplanation(
        id: 'hit_frequency',
        title: 'Hit Frequency',
        description:
            'The percentage of spins that produce any win (including tiny '
            'wins). Directly correlated with how often win_celebration audio '
            'fires. A 30% hit frequency means roughly 1 in 3 spins triggers '
            'some form of win sound.',
        typicalValues: '20–45% for most certified slots',
        unit: '%',
        tips: [
          'High hit frequency (>40%) requires lightweight win sounds — avoid CPU-heavy layers.',
          'Low hit frequency (<20%) justifies longer anticipation windows.',
        ],
      ),

      const ParamExplanation(
        id: 'max_win_multiplier',
        title: 'Max Win Multiplier',
        description:
            'The highest possible win multiplier achievable in the game, '
            'expressed as a multiple of the total bet. This defines the '
            'ceiling for the flagship win tier. Jackpot events are typically '
            'at or near this ceiling.',
        typicalValues: '500× – 50000× depending on title',
        unit: '×',
        tips: [
          'Ensure the jackpot audio sequence duration matches the emotional weight of the max multiplier.',
          'Extreme max-wins (>10000×) may warrant unique one-shot audio not used elsewhere.',
        ],
      ),

      const ParamExplanation(
        id: 'reels',
        title: 'Reel Count',
        description:
            'The number of vertical reel columns in the slot layout. '
            'Reel count directly determines how many reel_stop events fire '
            'per spin and therefore the maximum simultaneous voice demand '
            'during the stop sequence.',
        typicalValues: '5 reels (standard); 3 or 6+ for special formats',
        unit: 'reels',
        tips: [
          'With 5 reels, budget for 5 simultaneous reel_stop voices in the worst case.',
          'Anticipation fires on reels 4 and 5 — plan the voice overlap carefully.',
        ],
      ),

      const ParamExplanation(
        id: 'rows',
        title: 'Row Count',
        description:
            'The number of horizontal rows visible in the reel window. '
            'Together with reel count, defines the total symbol grid size '
            'which affects the probability of win combinations and thus '
            'the frequency of each win tier\'s audio.',
        typicalValues: '3 rows (standard); some titles use 4 or 5',
        unit: 'rows',
        tips: [
          'A 5×3 grid (15 symbols) is the most common layout — use as your baseline reference.',
        ],
      ),

      // ── Compliance ──────────────────────────────────────────────────────────

      const ParamExplanation(
        id: 'near_miss_audio',
        title: 'Near Miss Audio',
        description:
            'The audio event that plays when reels stop in a near-miss '
            'configuration (e.g. two jackpot symbols with the third just '
            'above or below the payline). Near-miss audio is strictly '
            'regulated — it must be clearly distinct from win audio to '
            'avoid misleading players.',
        typicalValues: 'Distinct non-celebratory sound; typically a slight deflation tone',
        complianceNote: 'MGA Directive 2020/04: Near-miss audio MUST differ perceptibly from win audio (R-RG-2). Using a partial win sound as near-miss audio is a compliance violation.',
        relatedRuleId: 'R-RG-2',
        tips: [
          'Use a descending or "deflating" audio motif — the opposite of the win stinger.',
          'Test with audio frequency analysis to confirm spectral difference from win sounds.',
          'Never reuse any fragment of the win_celebration audio for near-miss.',
        ],
      ),

      const ParamExplanation(
        id: 'ldw_audio',
        title: 'LDW Audio (Loss Disguised as Win)',
        description:
            'Governs the audio response when the total win equals or is '
            'less than the total bet placed. Playing a win celebration '
            'sound in this scenario is called a "Loss Disguised as Win" '
            'and is prohibited in regulated markets. The audio must be '
            'neutral or silent.',
        typicalValues: 'Silence or neutral tick — no celebratory audio',
        complianceNote: 'UKGC: Win sound prohibited when win ≤ bet. MGA: Same rule. SE: Same rule. Violation can result in license suspension.',
        relatedRuleId: 'R-RG-3',
        tips: [
          'Implement an LDW guard in the event trigger layer — check win_amount vs bet_amount before firing any audio.',
          'Route LDW outcomes to a dedicated "neutral result" audio event, not silence (to avoid confusion with errors).',
          'Test edge cases: win exactly equals bet, win = bet - 0.01.',
        ],
      ),

      const ParamExplanation(
        id: 'celebration_proportionality',
        title: 'Celebration Proportionality',
        description:
            'The principle that audio intensity, duration, and elaborateness '
            'must be directly proportional to the win\'s value relative to '
            'the bet. A small win using a grand jackpot celebration is a '
            'compliance violation. The win tier system enforces this.',
        typicalValues: 'Audio intensity and duration must scale monotonically with win tier',
        complianceNote: 'UKGC/MGA/SE: Disproportionate celebration of wins is classified as misleading commercial communication under gambling regulations.',
        relatedRuleId: 'R-WT-1',
        tips: [
          'Use the AI Co-Pilot win tier calibration check to verify proportionality automatically.',
          'Ensure the win_duration_ratio is at least 10:1 across all tiers.',
        ],
      ),

      const ParamExplanation(
        id: 'responsible_gaming_rtp_floor',
        title: 'RTP Floor (Responsible Gaming)',
        description:
            'The minimum certified RTP that a slot must advertise and '
            'maintain to receive a gaming license in the target jurisdiction. '
            'Below this floor, the game cannot be legally offered to players.',
        typicalValues: 'UKGC: 92% | MGA: 85% | SE: 86% (typical)',
        unit: '%',
        complianceNote: 'Licensing requirement: Slots must meet jurisdiction-specific RTP floors to obtain and maintain a gaming operator license.',
        relatedRuleId: 'R-RG-1',
        tips: [
          'Always validate against the most restrictive jurisdiction in your target markets.',
          'Audio does not affect RTP mathematically but must not misrepresent win frequency.',
        ],
      ),

      const ParamExplanation(
        id: 'autoplay_audio',
        title: 'Autoplay Audio',
        description:
            'Audio behaviour during autoplay sessions where the game '
            'spins automatically without player interaction. Some '
            'jurisdictions require that players can mute or reduce audio '
            'during autoplay as a responsible gaming measure.',
        typicalValues: 'Full audio by default; mute option required in SE',
        complianceNote: 'SE (Spelinspektionen): Operators MUST allow players to enable silent autoplay. Mandatory audio during autoplay is a compliance violation in Sweden.',
        tips: [
          'Add a "Silent Autoplay" toggle in the game settings — do not rely on device mute.',
          'Reduce win celebration volume during autoplay (not eliminate) to decrease arousal.',
        ],
      ),

      // ── Audio Engineering ───────────────────────────────────────────────────

      const ParamExplanation(
        id: 'can_loop',
        title: 'Can Loop',
        description:
            'Boolean flag indicating whether this audio event is designed '
            'to loop continuously until explicitly stopped. Looping events '
            'must have seamless loop points and often use crossfading to '
            'hide the transition.',
        typicalValues: 'true for ambient beds, reel_spin; false for one-shot events',
        relatedRuleId: 'R-LC-1',
        tips: [
          'Always specify a crossfade duration (spin_loop_crossfade) for looping events.',
          'Test loop points at various playback positions — not just from the start.',
        ],
      ),

      const ParamExplanation(
        id: 'trigger_probability',
        title: 'Trigger Probability',
        description:
            'The statistical likelihood (0.0–1.0) that this audio event '
            'fires on a given spin or game event. Used by the Simulation '
            'Engine to model CPU/voice usage over many spins and ensure '
            'the voice budget holds under real play conditions.',
        typicalValues: '0.0–1.0; spin_start always 1.0; near_miss typically 0.03–0.08',
        unit: 'probability (0–1)',
        tips: [
          'Set accurate probabilities — the simulation is only as good as its inputs.',
          'Jackpot trigger probability should match the math model\'s jackpot hit frequency.',
        ],
      ),

      const ParamExplanation(
        id: 'rtp_contribution',
        title: 'RTP Contribution',
        description:
            'An informational field indicating which RTP-contributing '
            'events (wins) this audio event is associated with. While '
            'audio itself does not change mathematical RTP, it must '
            'correctly represent the win outcomes without distortion.',
        typicalValues: 'Reference to win tier or jackpot type; informational only',
        tips: [
          'Use this field to link audio events to their corresponding math model outcomes for compliance tracing.',
        ],
      ),

      const ParamExplanation(
        id: 'is_required',
        title: 'Is Required',
        description:
            'Whether this audio event is mandatory for regulatory '
            'compliance. Required events cannot be deleted from a project '
            'and trigger critical errors in the compliance validator. '
            'Examples: ldw_audio handling, base-game ambient.',
        typicalValues: 'true for compliance-critical events; false for optional events',
        tips: [
          'Check the is_required flag before deleting any event from the SlotLab stage graph.',
          'Required events should appear in the compliance manifest export.',
        ],
      ),

      const ParamExplanation(
        id: 'spin_loop_crossfade',
        title: 'Spin Loop Crossfade',
        description:
            'The duration of the crossfade at the loop point of the '
            'reel-spin audio. A smooth crossfade prevents the mechanical '
            '"click" that occurs when a looping audio file wraps from its '
            'end back to its beginning.',
        typicalValues: '50–200 ms; 80–120 ms is ideal for most spin sounds',
        unit: 'ms',
        relatedRuleId: 'R-LC-1',
        tips: [
          'Use 100 ms as a starting point and adjust based on the spectral content of the loop.',
          'Ensure the crossfade region does not contain sharp transients.',
        ],
      ),

      const ParamExplanation(
        id: 'lufs_target',
        title: 'LUFS Target',
        description:
            'The integrated loudness target for this audio asset or the '
            'overall mix, measured in LUFS (Loudness Units Full Scale). '
            'Consistent loudness across all events prevents jarring level '
            'jumps during gameplay.',
        typicalValues: '-16 LUFS ±1 dB (slot audio industry standard)',
        unit: 'LUFS',
        tips: [
          'Normalise all assets to -16 LUFS integrated before importing into SlotLab.',
          'Check peak levels too — keep true peak below -1 dBTP to prevent inter-sample clipping.',
        ],
      ),

      const ParamExplanation(
        id: 'dynamic_range_db',
        title: 'Dynamic Range (dB)',
        description:
            'The maximum loudness jump allowed between consecutive audio '
            'events in the game flow. Large jumps are jarring and can '
            'startle players. The recommended ceiling of 6 dB ensures '
            'smooth loudness transitions throughout the session.',
        typicalValues: '≤ 6 dB jump recommended between events',
        unit: 'dB',
        tips: [
          'Use the AI Co-Pilot loudness check to scan for events that exceed the 6 dB jump limit.',
          'Automate a ducking curve on ambient tracks during win celebrations to manage dynamic range.',
        ],
      ),

      // ── Events ──────────────────────────────────────────────────────────────

      const ParamExplanation(
        id: 'event_category',
        title: 'Event Category',
        description:
            'High-level classification of an audio event into one of the '
            'standard slot audio categories. Used for filtering, compliance '
            'checking, and the Simulation Engine\'s voice budget analysis.',
        typicalValues: 'BaseGame | Win | NearMiss | Feature | Jackpot | Special',
        tips: [
          'Always assign the correct category — the LDW guard and near-miss compliance checks filter by category.',
          'Events in the Win category are subject to the celebration_proportionality rule.',
        ],
      ),

      const ParamExplanation(
        id: 'spin_start',
        title: 'Spin Start Event',
        description:
            'The audio event triggered the moment the player activates '
            'a spin. It is the highest-frequency event in the game and '
            'fires on every single spin. It must be short, crisp, and '
            'responsive to maintain the game\'s feel.',
        typicalValues: 'Duration: 150–250 ms; Trigger probability: 1.0',
        unit: null,
        tips: [
          'Use a single-layer transient — no complex layering needed here.',
          'Vary the pitch or timbre slightly on each trigger to avoid monotony during long sessions.',
        ],
      ),

      const ParamExplanation(
        id: 'reel_spin',
        title: 'Reel Spin Loop',
        description:
            'The continuous looping audio that plays while the reels are '
            'spinning. This is typically a mechanical whirring or whooshing '
            'sound. It must loop seamlessly and duck appropriately when '
            'win audio begins.',
        typicalValues: 'Looping; typically 1–2 seconds per loop cycle',
        unit: null,
        relatedRuleId: 'R-LC-1',
        tips: [
          'Ensure can_loop is true and spin_loop_crossfade is set.',
          'Duck this track by 6–12 dB during win_celebration for clarity.',
        ],
      ),

      const ParamExplanation(
        id: 'reel_stop',
        title: 'Reel Stop Event',
        description:
            'The audio event fired each time an individual reel stops. '
            'In a 5-reel slot, five stop events fire sequentially with '
            'a short delay between each. The stop sound must synchronise '
            'with the visual snap/bounce animation of the reel.',
        typicalValues: 'Duration: 200–400 ms; sequential across 5 reels',
        unit: null,
        tips: [
          'Use different pitch variants per reel-stop index to avoid a machine-gun effect.',
          'Reel 5 stop often transitions into anticipation — handle the crossfade carefully.',
        ],
      ),

      const ParamExplanation(
        id: 'anticipation',
        title: 'Anticipation Event',
        description:
            'The tension-building audio that plays as reels 4–5 are about '
            'to stop when a potential high-value win is detected. It is '
            'one of the most emotionally impactful events in the entire '
            'slot audio timeline.',
        typicalValues: 'Duration: 1500–4000 ms; triggered on ~5–15% of spins',
        unit: null,
        tips: [
          'Layer a rising drone, a rhythmic tension loop, and a subtle high-frequency shimmer.',
          'Crossfade cleanly into either win_celebration or near_miss_audio depending on outcome.',
        ],
      ),

      const ParamExplanation(
        id: 'win_celebration',
        title: 'Win Celebration Event',
        description:
            'The primary win audio event that fires after the outcome is '
            'determined and symbols lock in. Duration and intensity must '
            'map to the win tier. This is the most compliance-sensitive '
            'audio event in the game.',
        typicalValues: 'Duration: 400 ms (subtle) to 30000 ms (flagship); maps to win tier',
        unit: null,
        complianceNote: 'MGA/UKGC: Must not fire when win ≤ bet (LDW rule). Intensity must be proportional to win value (celebration_proportionality).',
        tips: [
          'Always route win amount through the LDW guard before triggering this event.',
          'Use the WinTierConfig to select the correct tier variant automatically.',
        ],
      ),

      const ParamExplanation(
        id: 'feature_trigger',
        title: 'Feature Trigger Event',
        description:
            'The audio event that plays when the free spins bonus or '
            'special feature is activated. It is a peak excitement moment '
            'and transitions the game from base-game audio to feature audio.',
        typicalValues: 'Duration: 3000–8000 ms; triggers per feature hit frequency',
        unit: null,
        tips: [
          'End with a crossfade into free_spins_ambient.',
          'Ensure the feature trigger stinger does not voice-steal from critical UI sounds.',
        ],
      ),

      const ParamExplanation(
        id: 'free_spins_ambient',
        title: 'Free Spins Ambient',
        description:
            'The background music that loops throughout the free spins '
            'bonus feature. It should be thematically distinct from the '
            'base game ambient to signal the changed game state, and must '
            'meet the same loop length requirements.',
        typicalValues: 'Looping; minimum 30 seconds per loop; distinct from base-game ambient',
        unit: null,
        relatedRuleId: 'R-TB-2',
        tips: [
          'Use higher energy music than base-game — free spins should feel elevated.',
          'Budget for this to play underneath win_celebration events — ensure ducking is set up.',
        ],
      ),

      // ── Quality Score (AI Co-Pilot) ─────────────────────────────────────────

      const ParamExplanation(
        id: 'quality_score',
        title: 'Quality Score',
        description:
            'The AI Co-Pilot\'s composite score (0–100) reflecting the '
            'overall audio design quality of the current slot project. '
            'It aggregates sub-scores across voice budget, event coverage, '
            'win tier calibration, compliance, and timing benchmarks.',
        typicalValues: '≥ 80 for production-ready; ≥ 90 for premium release',
        unit: 'score (0–100)',
        tips: [
          'Address CRITICAL suggestions first — they have the highest score impact.',
          'A score of 100 does not guarantee regulatory approval — always run COMPLY separately.',
        ],
      ),
    ];

    for (final e in entries) {
      _registry[e.id] = e;
    }
  }

  /// Number of params currently in the registry (including custom ones).
  int get registrySize => _registry.length;
}
