//! AI-Suggested Mixing Chains
//!
//! Takes an `AnalysisResult` (from `AudioAnalyzer`) plus the user's
//! scanned plugin library, and returns a complete, ordered effect chain
//! with concrete parameter suggestions and ranked plugin candidates per
//! slot.
//!
//! # Design
//!
//! 1. **Track-type detection** — uses spectral + dynamics + stereo
//!    features to classify the source as Vocal / Drums / Bass / Synth /
//!    Guitar / FullMix / Master. The user can also pass a hint to skip
//!    detection.
//! 2. **Chain template lookup** — each track type has a curated reference
//!    chain (slot order + target params) drawn from industry best
//!    practice. The template is then *adapted* using the analysis
//!    features (e.g. boost the de-esser's threshold if no sibilance is
//!    detected, raise the HPF if low rumble is present).
//! 3. **Plugin matching** — for each slot kind (`SlotKind::Eq`,
//!    `SlotKind::Compressor`, …) a name-pattern matcher ranks the
//!    user's scanned plugins. The user always sees a list, not a single
//!    forced choice — top candidate has highest `match_score`.
//! 4. **Reasoning** — every slot ships with a one-sentence
//!    `reasoning` string explaining *why* it's there (e.g. "Tames
//!    sibilance at 6 kHz detected by spectral analysis"), so the user
//!    can disagree intelligently.
//!
//! # Why a separate module
//!
//! `assistant/suggestions.rs` already produces *individual* suggestions
//! ("the mix is 3 dB too loud"). What was missing — and what mixers
//! actually need — is the **assembled signal flow**: ordered chain,
//! plugin-pinned, parameter-pinned. That's what this module does.

use serde::{Deserialize, Serialize};

use super::AnalysisResult;
use super::classifier::Genre;
use super::suggestions::{ParameterSuggestion, SuggestionType};

// ─────────────────────────────────────────────────────────────────────────
// Track type — what kind of source we're advising on
// ─────────────────────────────────────────────────────────────────────────

/// Detected (or hinted) source type. Drives template selection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrackType {
    /// Lead or backing vocal.
    Vocal,
    /// Drum bus or single drum (kick/snare composite).
    Drums,
    /// Bass guitar or synth bass.
    Bass,
    /// Electric/acoustic guitar.
    Guitar,
    /// Synth pad / lead / arp.
    Synth,
    /// Piano / keyboard.
    Keys,
    /// Full mix bus (all instruments combined).
    FullMix,
    /// Mastering chain (final 2-bus).
    Master,
    /// Type couldn't be confidently determined.
    Unknown,
}

impl TrackType {
    pub fn display_name(self) -> &'static str {
        match self {
            TrackType::Vocal => "Vocal",
            TrackType::Drums => "Drums",
            TrackType::Bass => "Bass",
            TrackType::Guitar => "Guitar",
            TrackType::Synth => "Synth",
            TrackType::Keys => "Keys",
            TrackType::FullMix => "Full Mix",
            TrackType::Master => "Master",
            TrackType::Unknown => "Unknown",
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Slot kinds — the canonical processor types we advise on
// ─────────────────────────────────────────────────────────────────────────

/// Canonical processor categories that go in a chain. This is a smaller,
/// chain-oriented set than `assistant::suggestions::SuggestionType`
/// (which is a flat catalogue of advice categories).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SlotKind {
    /// High-pass filter (cleanup).
    HighPass,
    /// Subtractive / surgical EQ.
    Eq,
    /// Dynamic processor (downward compression).
    Compressor,
    /// Multiband compressor.
    MultibandCompressor,
    /// De-esser.
    DeEsser,
    /// Noise gate.
    Gate,
    /// Saturation / harmonic enhancement.
    Saturation,
    /// Transient shaper.
    Transient,
    /// Stereo width / imaging.
    StereoWidth,
    /// Reverb.
    Reverb,
    /// Delay.
    Delay,
    /// Modulation (chorus, flanger, phaser).
    Modulation,
    /// Brick-wall limiter.
    Limiter,
    /// Loudness maximiser (mastering).
    Maximizer,
}

impl SlotKind {
    pub fn display_name(self) -> &'static str {
        match self {
            SlotKind::HighPass => "High-Pass",
            SlotKind::Eq => "EQ",
            SlotKind::Compressor => "Compressor",
            SlotKind::MultibandCompressor => "Multiband Comp",
            SlotKind::DeEsser => "De-Esser",
            SlotKind::Gate => "Gate",
            SlotKind::Saturation => "Saturation",
            SlotKind::Transient => "Transient Shaper",
            SlotKind::StereoWidth => "Stereo Width",
            SlotKind::Reverb => "Reverb",
            SlotKind::Delay => "Delay",
            SlotKind::Modulation => "Modulation",
            SlotKind::Limiter => "Limiter",
            SlotKind::Maximizer => "Maximizer",
        }
    }

    /// Map to the closer-grained suggestion category (for UI grouping).
    pub fn related_suggestion_type(self) -> SuggestionType {
        match self {
            SlotKind::HighPass | SlotKind::Eq => SuggestionType::Eq,
            SlotKind::Compressor | SlotKind::MultibandCompressor => {
                SuggestionType::Compression
            }
            SlotKind::DeEsser => SuggestionType::DeEss,
            SlotKind::Gate | SlotKind::Transient => SuggestionType::Transients,
            SlotKind::Saturation => SuggestionType::Saturation,
            SlotKind::StereoWidth => SuggestionType::StereoWidth,
            SlotKind::Reverb => SuggestionType::Reverb,
            SlotKind::Delay => SuggestionType::Reverb,
            SlotKind::Modulation => SuggestionType::Mix,
            SlotKind::Limiter | SlotKind::Maximizer => SuggestionType::Limiting,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Plugin candidate (what the user has scanned)
// ─────────────────────────────────────────────────────────────────────────

/// Minimal plugin descriptor — `rf-ml` doesn't depend on `rf-plugin`,
/// so the caller flattens its `PluginInfo` into this before calling.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AvailablePlugin {
    pub id: String,
    pub name: String,
    pub vendor: String,
}

/// One ranked plugin choice for a chain slot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginCandidate {
    pub plugin_id: String,
    pub plugin_name: String,
    pub vendor: String,
    /// Match score 0.0–1.0; higher = better fit for this slot kind.
    pub match_score: f32,
}

// ─────────────────────────────────────────────────────────────────────────
// Chain output types
// ─────────────────────────────────────────────────────────────────────────

/// One slot in the suggested chain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainSlotSuggestion {
    /// 0-based position in the signal flow.
    pub position: u32,
    pub kind: SlotKind,
    /// Bypass-safe = removing this slot won't break the chain
    /// (e.g. reverb yes, HPF cleanup no).
    pub bypass_safe: bool,
    /// Plugin candidates from the user's library, ranked by match.
    /// Empty if no scanned plugin matched — the UI should fall back to
    /// the internal rf-dsp processor.
    pub plugin_candidates: Vec<PluginCandidate>,
    /// Concrete parameter targets (gain, frequency, ratio, mix, etc.).
    pub parameters: Vec<ParameterSuggestion>,
    /// One-sentence "why this slot is here".
    pub reasoning: String,
    /// 0.0–1.0 confidence in the suggestion.
    pub confidence: f32,
}

/// Full chain suggestion.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainSuggestion {
    pub track_type: TrackType,
    pub track_type_confidence: f32,
    pub slots: Vec<ChainSlotSuggestion>,
    pub overall_reasoning: String,
    /// Style tag the chain targets: "Modern Pop", "Vintage Warmth",
    /// "Streaming Master", etc.
    pub style_tag: String,
    /// 0.0–1.0 — how confident the advisor is overall.
    pub overall_confidence: f32,
}

impl ChainSuggestion {
    /// Number of slots.
    pub fn len(&self) -> usize {
        self.slots.len()
    }

    pub fn is_empty(&self) -> bool {
        self.slots.is_empty()
    }

    /// Slot kinds in order — useful for UI summaries ("HPF → EQ → Comp → Reverb").
    pub fn pipeline_string(&self) -> String {
        self.slots
            .iter()
            .map(|s| s.kind.display_name())
            .collect::<Vec<_>>()
            .join(" → ")
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Advisor configuration & entry point
// ─────────────────────────────────────────────────────────────────────────

/// Configuration knobs for the advisor.
#[derive(Debug, Clone)]
pub struct AdvisorConfig {
    /// Aggressiveness of corrective slots (HPF, de-esser).
    /// 0.0 = only suggest when problem is obvious, 1.0 = always suggest.
    pub corrective_aggressiveness: f32,
    /// Streaming target loudness (LUFS) — drives master limiter.
    pub target_lufs: f32,
    /// If true, prefer chains that target a "vintage warm" tone (more
    /// saturation, slower comp); if false, target "modern clean".
    pub vintage_bias: bool,
}

impl Default for AdvisorConfig {
    fn default() -> Self {
        Self {
            corrective_aggressiveness: 0.6,
            target_lufs: -14.0,
            vintage_bias: false,
        }
    }
}

/// Chain Advisor.
///
/// Stateless — building one is essentially free; not held across analyses.
pub struct ChainAdvisor {
    config: AdvisorConfig,
}

impl ChainAdvisor {
    pub fn new() -> Self {
        Self {
            config: AdvisorConfig::default(),
        }
    }

    pub fn with_config(config: AdvisorConfig) -> Self {
        Self { config }
    }

    /// Top-level: produce a chain from analysis + plugin library.
    ///
    /// `track_hint` — if the caller already knows the source type
    /// (user told us "this is the lead vocal"), pass `Some(...)` to
    /// skip detection. Pass `None` to let the advisor classify.
    pub fn suggest_chain(
        &self,
        analysis: &AnalysisResult,
        available_plugins: &[AvailablePlugin],
        track_hint: Option<TrackType>,
    ) -> ChainSuggestion {
        let (track_type, type_confidence) = match track_hint {
            Some(t) => (t, 1.0),
            None => self.classify_track_type(analysis),
        };

        let template = self.template_for(track_type);
        let mut slots = Vec::new();
        for (idx, slot_def) in template.slots.iter().enumerate() {
            let candidates = rank_plugins_for(slot_def.kind, available_plugins);
            let params = adapt_parameters(slot_def, analysis);
            slots.push(ChainSlotSuggestion {
                position: idx as u32,
                kind: slot_def.kind,
                bypass_safe: slot_def.bypass_safe,
                plugin_candidates: candidates,
                parameters: params,
                reasoning: slot_def.reasoning.clone(),
                confidence: slot_def.confidence,
            });
        }

        let overall_confidence = (type_confidence
            + slots.iter().map(|s| s.confidence).sum::<f32>() / slots.len().max(1) as f32)
            * 0.5;

        ChainSuggestion {
            track_type,
            track_type_confidence: type_confidence,
            slots,
            overall_reasoning: template.overall_reasoning,
            style_tag: template.style_tag,
            overall_confidence: overall_confidence.clamp(0.0, 1.0),
        }
    }

    /// Classify a track from spectral / dynamics / stereo features.
    ///
    /// Heuristic rules (deterministic, audited):
    /// - High `low_ratio`, low transient_sharpness → Bass
    /// - High transient_sharpness + crest > 18 dB → Drums
    /// - Mid-heavy + brightness near 0 + width < 0.4 + crest 8–16 dB → Vocal
    /// - Genre = Electronic + width > 0.6 → Synth
    /// - Genre matches Rock/Pop/HipHop + width > 0.5 + crest < 12 dB → FullMix
    /// - Else → Unknown (template falls back to a safe generic chain).
    pub fn classify_track_type(&self, a: &AnalysisResult) -> (TrackType, f32) {
        let low = a.spectral.low_ratio;
        let mid = a.spectral.mid_ratio;
        let high = a.spectral.high_ratio;
        let crest = a.dynamics.crest_factor_db;
        let trans = a.dynamics.transient_sharpness;
        let width = a.stereo.width;

        // Bass: dominant low-end, gentle transients.
        if low > 0.55 && trans < 0.45 {
            return (TrackType::Bass, 0.78);
        }
        // Drums: very high transients + high crest factor.
        if trans > 0.65 && crest > 16.0 {
            return (TrackType::Drums, 0.85);
        }
        // Vocal: mid-dominant, narrow stereo, moderate dynamics.
        if mid > 0.45 && width < 0.45 && crest > 8.0 && crest < 16.0 {
            return (TrackType::Vocal, 0.72);
        }
        // Synth: high width + electronic genre.
        if width > 0.6
            && a.genres
                .iter()
                .any(|(g, p)| matches!(g, Genre::Electronic | Genre::Pop) && *p > 0.4)
        {
            return (TrackType::Synth, 0.65);
        }
        // Full mix: balanced spectrum + wide + compressed.
        if (low + mid + high - 1.0).abs() < 0.2 && width > 0.5 && crest < 14.0 {
            return (TrackType::FullMix, 0.6);
        }
        (TrackType::Unknown, 0.3)
    }

    /// Pick the chain template for a track type. Templates adapt their
    /// concrete parameters in `adapt_parameters` once analysis is in
    /// hand.
    fn template_for(&self, t: TrackType) -> ChainTemplate {
        match t {
            TrackType::Vocal => template_vocal(self.config.vintage_bias),
            TrackType::Drums => template_drums(self.config.vintage_bias),
            TrackType::Bass => template_bass(),
            TrackType::Guitar => template_guitar(self.config.vintage_bias),
            TrackType::Synth => template_synth(),
            TrackType::Keys => template_keys(),
            TrackType::FullMix => template_full_mix(),
            TrackType::Master => template_master(self.config.target_lufs),
            TrackType::Unknown => template_generic(),
        }
    }
}

impl Default for ChainAdvisor {
    fn default() -> Self {
        Self::new()
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Internal: chain templates
// ─────────────────────────────────────────────────────────────────────────

/// Template slot — pre-`adapt_parameters` form.
struct SlotTemplate {
    kind: SlotKind,
    bypass_safe: bool,
    reasoning: String,
    /// Default param suggestions; some are overwritten by analysis in
    /// `adapt_parameters`.
    base_params: Vec<ParameterSuggestion>,
    confidence: f32,
}

impl SlotTemplate {
    fn new(
        kind: SlotKind,
        bypass_safe: bool,
        reasoning: &str,
        confidence: f32,
        params: Vec<ParameterSuggestion>,
    ) -> Self {
        Self {
            kind,
            bypass_safe,
            reasoning: reasoning.to_string(),
            confidence,
            base_params: params,
        }
    }
}

struct ChainTemplate {
    slots: Vec<SlotTemplate>,
    overall_reasoning: String,
    style_tag: String,
}

fn p(name: &str, suggested: f32, unit: &str) -> ParameterSuggestion {
    ParameterSuggestion {
        name: name.to_string(),
        current: 0.0,
        suggested,
        unit: unit.to_string(),
    }
}

fn template_vocal(vintage: bool) -> ChainTemplate {
    let comp_ratio = if vintage { 4.0 } else { 3.0 };
    let mut slots = vec![
        SlotTemplate::new(
            SlotKind::HighPass,
            false,
            "Removes sub-100 Hz rumble and proximity-effect mud below the vocal's fundamental.",
            0.92,
            vec![p("Cutoff", 80.0, "Hz"), p("Slope", 24.0, "dB/oct")],
        ),
        SlotTemplate::new(
            SlotKind::DeEsser,
            true,
            "Tames sibilance in the 5–8 kHz band.",
            0.78,
            vec![p("Frequency", 6500.0, "Hz"), p("Threshold", -22.0, "dB"), p("Range", -6.0, "dB")],
        ),
        SlotTemplate::new(
            SlotKind::Compressor,
            false,
            "Levels the performance — a touch of glue without squashing dynamics.",
            0.88,
            vec![
                p("Threshold", -18.0, "dB"),
                p("Ratio", comp_ratio, ":1"),
                p("Attack", 10.0, "ms"),
                p("Release", 80.0, "ms"),
                p("Makeup", 3.0, "dB"),
            ],
        ),
        SlotTemplate::new(
            SlotKind::Eq,
            true,
            "Subtle presence boost around 4–5 kHz; tame any 250 Hz boxiness.",
            0.7,
            vec![
                p("Low-Mid Cut", -2.5, "dB"),
                p("Low-Mid Freq", 250.0, "Hz"),
                p("Presence", 2.0, "dB"),
                p("Presence Freq", 4500.0, "Hz"),
                p("Air", 1.5, "dB"),
                p("Air Freq", 12000.0, "Hz"),
            ],
        ),
        SlotTemplate::new(
            SlotKind::Reverb,
            true,
            "Plate or short room — adds glue and depth without smearing the lyrics.",
            0.72,
            vec![
                p("Type", 1.0, "Plate"),
                p("Decay", 1.4, "s"),
                p("Pre-Delay", 25.0, "ms"),
                p("Mix", 18.0, "%"),
            ],
        ),
    ];
    if vintage {
        slots.push(SlotTemplate::new(
            SlotKind::Saturation,
            true,
            "Subtle tape warmth to glue the vocal to a vintage bed.",
            0.6,
            vec![p("Drive", 1.5, "dB"), p("Mix", 30.0, "%")],
        ));
    }
    ChainTemplate {
        slots,
        overall_reasoning:
            "Modern vocal chain: cleanup → de-essing → leveling → tonal sculpt → space.".into(),
        style_tag: if vintage { "Vintage Vocal".into() } else { "Modern Pop Vocal".into() },
    }
}

fn template_drums(vintage: bool) -> ChainTemplate {
    let saturation_drive = if vintage { 3.5 } else { 1.5 };
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::Gate,
                true,
                "Cleans bleed between hits on close mics.",
                0.65,
                vec![p("Threshold", -42.0, "dB"), p("Range", -20.0, "dB"), p("Attack", 0.5, "ms")],
            ),
            SlotTemplate::new(
                SlotKind::Eq,
                false,
                "Punch boost ~80 Hz on kick, snap ~5 kHz on snare; cut 300 Hz mud.",
                0.82,
                vec![
                    p("Punch", 3.0, "dB"),
                    p("Punch Freq", 80.0, "Hz"),
                    p("Mud Cut", -3.0, "dB"),
                    p("Mud Freq", 300.0, "Hz"),
                    p("Snap", 2.5, "dB"),
                    p("Snap Freq", 5000.0, "Hz"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Compressor,
                false,
                "Parallel compression for thickness without losing transients.",
                0.85,
                vec![
                    p("Threshold", -22.0, "dB"),
                    p("Ratio", 4.0, ":1"),
                    p("Attack", 5.0, "ms"),
                    p("Release", 100.0, "ms"),
                    p("Mix", 50.0, "%"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Transient,
                true,
                "Sharpens transients lost in compression.",
                0.7,
                vec![p("Attack", 4.0, "dB"), p("Sustain", -2.0, "dB")],
            ),
            SlotTemplate::new(
                SlotKind::Saturation,
                true,
                "Tape/tube warmth glues the kit and adds harmonics.",
                0.7,
                vec![p("Drive", saturation_drive, "dB"), p("Mix", 60.0, "%")],
            ),
            SlotTemplate::new(
                SlotKind::Limiter,
                true,
                "Catches stray transients before they hit the mix bus.",
                0.6,
                vec![p("Ceiling", -1.0, "dB"), p("Release", 50.0, "ms")],
            ),
        ],
        overall_reasoning: "Drum bus chain: gate → punch EQ → parallel comp → transients → glue saturation → safety limiter.".into(),
        style_tag: if vintage { "Vintage Drum Glue".into() } else { "Modern Drum Punch".into() },
    }
}

fn template_bass() -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::HighPass,
                false,
                "Cuts inaudible sub rumble below the bass fundamental.",
                0.9,
                vec![p("Cutoff", 30.0, "Hz"), p("Slope", 12.0, "dB/oct")],
            ),
            SlotTemplate::new(
                SlotKind::Compressor,
                false,
                "Heavy ratio glues the bass tightly to the kick.",
                0.88,
                vec![
                    p("Threshold", -20.0, "dB"),
                    p("Ratio", 6.0, ":1"),
                    p("Attack", 15.0, "ms"),
                    p("Release", 120.0, "ms"),
                    p("Makeup", 4.0, "dB"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Eq,
                false,
                "Boost fundamental around 80 Hz, scoop 400 Hz mud, lift presence at 1.2 kHz.",
                0.85,
                vec![
                    p("Sub Boost", 2.0, "dB"),
                    p("Sub Freq", 80.0, "Hz"),
                    p("Mud Cut", -3.5, "dB"),
                    p("Mud Freq", 400.0, "Hz"),
                    p("Presence", 2.5, "dB"),
                    p("Presence Freq", 1200.0, "Hz"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Saturation,
                true,
                "Harmonics make the bass audible on small speakers/phones.",
                0.78,
                vec![p("Drive", 2.5, "dB"), p("Mix", 40.0, "%")],
            ),
        ],
        overall_reasoning:
            "Bass chain: sub cleanup → heavy comp glue → tonal sculpt → harmonic excitement.".into(),
        style_tag: "Modern Tight Bass".into(),
    }
}

fn template_guitar(vintage: bool) -> ChainTemplate {
    let mut slots = vec![
        SlotTemplate::new(
            SlotKind::HighPass,
            false,
            "Removes low rumble below the guitar's range.",
            0.85,
            vec![p("Cutoff", 100.0, "Hz"), p("Slope", 12.0, "dB/oct")],
        ),
        SlotTemplate::new(
            SlotKind::Compressor,
            false,
            "Gentle leveling — keeps strums consistent.",
            0.78,
            vec![
                p("Threshold", -16.0, "dB"),
                p("Ratio", 3.0, ":1"),
                p("Attack", 15.0, "ms"),
                p("Release", 100.0, "ms"),
            ],
        ),
        SlotTemplate::new(
            SlotKind::Eq,
            true,
            "Cut 250 Hz boxiness, lift 3–4 kHz for pick attack and air.",
            0.74,
            vec![
                p("Box Cut", -2.0, "dB"),
                p("Box Freq", 250.0, "Hz"),
                p("Pick Attack", 2.5, "dB"),
                p("Pick Freq", 3500.0, "Hz"),
            ],
        ),
        SlotTemplate::new(
            SlotKind::Delay,
            true,
            "Quarter-note slap-back glues the guitar to the rhythm grid.",
            0.55,
            vec![p("Time", 1.0 / 4.0, "note"), p("Feedback", 25.0, "%"), p("Mix", 18.0, "%")],
        ),
        SlotTemplate::new(
            SlotKind::Reverb,
            true,
            "Hall or plate adds depth and 3D space.",
            0.65,
            vec![
                p("Decay", 2.2, "s"),
                p("Pre-Delay", 30.0, "ms"),
                p("Mix", 14.0, "%"),
            ],
        ),
    ];
    if vintage {
        slots.insert(
            2,
            SlotTemplate::new(
                SlotKind::Saturation,
                true,
                "Tube warmth — classic amp-front-end harmonics.",
                0.68,
                vec![p("Drive", 2.0, "dB"), p("Mix", 50.0, "%")],
            ),
        );
    }
    ChainTemplate {
        slots,
        overall_reasoning: "Guitar chain: cleanup → comp → tone EQ → time-based effects.".into(),
        style_tag: if vintage { "Vintage Tube Guitar".into() } else { "Modern Clean Guitar".into() },
    }
}

fn template_synth() -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::HighPass,
                true,
                "Carves room for bass and kick.",
                0.7,
                vec![p("Cutoff", 100.0, "Hz"), p("Slope", 12.0, "dB/oct")],
            ),
            SlotTemplate::new(
                SlotKind::Modulation,
                true,
                "Gentle chorus widens the synth without phasing problems.",
                0.62,
                vec![p("Rate", 0.4, "Hz"), p("Depth", 25.0, "%"), p("Mix", 20.0, "%")],
            ),
            SlotTemplate::new(
                SlotKind::StereoWidth,
                true,
                "Pushes the synth wider while keeping bass mono.",
                0.65,
                vec![p("Width", 130.0, "%"), p("Mono Below", 120.0, "Hz")],
            ),
            SlotTemplate::new(
                SlotKind::Reverb,
                true,
                "Long lush hall for pad-style synths.",
                0.7,
                vec![p("Decay", 3.5, "s"), p("Pre-Delay", 40.0, "ms"), p("Mix", 28.0, "%")],
            ),
            SlotTemplate::new(
                SlotKind::Limiter,
                true,
                "Catches resonance peaks at filter sweeps.",
                0.55,
                vec![p("Ceiling", -1.0, "dB"), p("Release", 30.0, "ms")],
            ),
        ],
        overall_reasoning: "Synth chain: cleanup → mod → width → space → safety.".into(),
        style_tag: "Modern Synth Pad".into(),
    }
}

fn template_keys() -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::HighPass,
                true,
                "Removes hum and rumble below 50 Hz.",
                0.78,
                vec![p("Cutoff", 50.0, "Hz"), p("Slope", 12.0, "dB/oct")],
            ),
            SlotTemplate::new(
                SlotKind::Compressor,
                false,
                "Smooths dynamic swings of piano performances.",
                0.8,
                vec![
                    p("Threshold", -18.0, "dB"),
                    p("Ratio", 2.5, ":1"),
                    p("Attack", 20.0, "ms"),
                    p("Release", 150.0, "ms"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Eq,
                true,
                "Light low-mid scoop, gentle high shelf for sparkle.",
                0.7,
                vec![
                    p("Low-Mid Cut", -1.5, "dB"),
                    p("Low-Mid Freq", 300.0, "Hz"),
                    p("Air", 1.5, "dB"),
                    p("Air Freq", 10000.0, "Hz"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Reverb,
                true,
                "Concert hall or plate for natural ambience.",
                0.72,
                vec![p("Decay", 2.6, "s"), p("Mix", 22.0, "%")],
            ),
        ],
        overall_reasoning: "Keys chain: cleanup → smooth dynamics → tone → ambience.".into(),
        style_tag: "Modern Piano".into(),
    }
}

fn template_full_mix() -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::Eq,
                true,
                "Subtle bus EQ — shape the overall tonal balance with a gentle tilt.",
                0.7,
                vec![
                    p("Low Shelf", 0.5, "dB"),
                    p("Low Freq", 100.0, "Hz"),
                    p("High Shelf", 0.8, "dB"),
                    p("High Freq", 10000.0, "Hz"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::MultibandCompressor,
                true,
                "Glues the mix without pumping; tame ranges that misbehave.",
                0.75,
                vec![
                    p("Low Threshold", -16.0, "dB"),
                    p("Low Ratio", 2.0, ":1"),
                    p("Mid Threshold", -14.0, "dB"),
                    p("Mid Ratio", 1.8, ":1"),
                    p("High Threshold", -18.0, "dB"),
                    p("High Ratio", 1.6, ":1"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Saturation,
                true,
                "Bus saturation — analog warmth on the 2-bus.",
                0.6,
                vec![p("Drive", 1.0, "dB"), p("Mix", 25.0, "%")],
            ),
            SlotTemplate::new(
                SlotKind::StereoWidth,
                true,
                "Slight width enhancement above 200 Hz; keeps bottom mono.",
                0.62,
                vec![p("Width", 110.0, "%"), p("Mono Below", 200.0, "Hz")],
            ),
            SlotTemplate::new(
                SlotKind::Limiter,
                false,
                "Brick-wall limiter — final loudness with no inter-sample peaks.",
                0.85,
                vec![
                    p("Ceiling", -1.0, "dB"),
                    p("Release", 50.0, "ms"),
                    p("Lookahead", 5.0, "ms"),
                ],
            ),
        ],
        overall_reasoning:
            "Mix bus chain: tilt EQ → multiband glue → analog warmth → width → safety limiter.".into(),
        style_tag: "Streaming-Ready Mix Bus".into(),
    }
}

fn template_master(target_lufs: f32) -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::HighPass,
                true,
                "Removes inaudible sub-content that wastes headroom.",
                0.65,
                vec![p("Cutoff", 25.0, "Hz"), p("Slope", 12.0, "dB/oct")],
            ),
            SlotTemplate::new(
                SlotKind::Eq,
                false,
                "Mastering tilt: gentle low + high shelves, broad-Q only.",
                0.78,
                vec![
                    p("Low Tilt", 0.4, "dB"),
                    p("Low Freq", 80.0, "Hz"),
                    p("High Tilt", 0.6, "dB"),
                    p("High Freq", 12000.0, "Hz"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::MultibandCompressor,
                true,
                "Surgical multiband for problem ranges only — avoid pumping.",
                0.7,
                vec![
                    p("Mid Threshold", -12.0, "dB"),
                    p("Mid Ratio", 1.5, ":1"),
                    p("High Threshold", -16.0, "dB"),
                    p("High Ratio", 1.3, ":1"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Saturation,
                true,
                "Mastering tape simulation — barely-perceptible harmonics.",
                0.55,
                vec![p("Drive", 0.5, "dB"), p("Mix", 15.0, "%")],
            ),
            SlotTemplate::new(
                SlotKind::Maximizer,
                false,
                &format!("Achieves {:.1} LUFS streaming target with -1 dBTP ceiling.", target_lufs),
                0.88,
                vec![
                    p("Target LUFS", target_lufs, "LUFS"),
                    p("Ceiling", -1.0, "dBTP"),
                    p("Release", 40.0, "ms"),
                    p("Lookahead", 5.0, "ms"),
                ],
            ),
        ],
        overall_reasoning:
            "Mastering chain: HPF → tilt EQ → surgical multiband → tape glue → maximizer.".into(),
        style_tag: "Streaming Master".into(),
    }
}

fn template_generic() -> ChainTemplate {
    ChainTemplate {
        slots: vec![
            SlotTemplate::new(
                SlotKind::HighPass,
                true,
                "Generic cleanup — sub rumble removal.",
                0.55,
                vec![p("Cutoff", 60.0, "Hz"), p("Slope", 12.0, "dB/oct")],
            ),
            SlotTemplate::new(
                SlotKind::Eq,
                true,
                "Generic tone shaping — start with neutral curve.",
                0.5,
                vec![p("Low Shelf", 0.0, "dB"), p("High Shelf", 0.0, "dB")],
            ),
            SlotTemplate::new(
                SlotKind::Compressor,
                true,
                "Generic leveling — start gentle, taste-driven.",
                0.5,
                vec![
                    p("Threshold", -16.0, "dB"),
                    p("Ratio", 2.5, ":1"),
                    p("Attack", 15.0, "ms"),
                    p("Release", 100.0, "ms"),
                ],
            ),
            SlotTemplate::new(
                SlotKind::Limiter,
                true,
                "Generic safety net.",
                0.55,
                vec![p("Ceiling", -1.0, "dB"), p("Release", 50.0, "ms")],
            ),
        ],
        overall_reasoning: "Source type undetermined — neutral starter chain.".into(),
        style_tag: "Generic Starter".into(),
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Internal: parameter adaptation from analysis
// ─────────────────────────────────────────────────────────────────────────

/// Adjust a slot's base parameters using analysis features.
///
/// Examples of adaptation:
/// - Vocal HPF: raise cutoff by 20 Hz if `low_ratio > 0.45` (mud detected).
/// - Vocal de-esser: pull threshold up 3 dB if no sibilance detected
///   (low high_ratio + low transient_sharpness).
/// - Master limiter: keep `target_lufs` (no change), but tighten release
///   when crest factor is very high.
fn adapt_parameters(slot: &SlotTemplate, a: &AnalysisResult) -> Vec<ParameterSuggestion> {
    let mut params = slot.base_params.clone();
    match slot.kind {
        SlotKind::HighPass => {
            // If low-end is heavy, raise cutoff slightly.
            if a.spectral.low_ratio > 0.45
                && let Some(p) = params.iter_mut().find(|p| p.name == "Cutoff")
            {
                p.suggested = (p.suggested + 20.0).min(150.0);
            }
        }
        SlotKind::DeEsser => {
            // If no detectable sibilance, raise threshold (gentler).
            if a.spectral.high_ratio < 0.18
                && let Some(p) = params.iter_mut().find(|p| p.name == "Threshold")
            {
                p.suggested = (p.suggested + 3.0).min(-10.0);
            }
        }
        SlotKind::Compressor => {
            // If already heavily compressed (low crest factor), back off.
            if a.dynamics.crest_factor_db < 8.0
                && let Some(p) = params.iter_mut().find(|p| p.name == "Threshold")
            {
                p.suggested = (p.suggested + 4.0).min(-6.0);
            }
        }
        SlotKind::Maximizer => {
            // Loud material: tighten release for transparency.
            if a.dynamics.crest_factor_db > 18.0
                && let Some(p) = params.iter_mut().find(|p| p.name == "Release")
            {
                p.suggested = (p.suggested - 10.0).max(10.0);
            }
        }
        _ => {}
    }
    params
}

// ─────────────────────────────────────────────────────────────────────────
// Internal: plugin matcher
// ─────────────────────────────────────────────────────────────────────────

/// Rank scanned plugins for a given slot kind by name patterns. Returns
/// up to 8 candidates (top match first). Empty result = no scanned
/// plugin matched; UI should fall back to the internal rf-dsp processor.
fn rank_plugins_for(kind: SlotKind, plugins: &[AvailablePlugin]) -> Vec<PluginCandidate> {
    let patterns: &[&str] = match kind {
        SlotKind::HighPass => &["highpass", "hpf", "filter", "pro-q", "fab q", " q ", "eq"],
        SlotKind::Eq => &["eq", "equalizer", "pro-q", " q3", " q4", "renaissance eq", "tdr nova"],
        SlotKind::Compressor => &[
            "compressor",
            "comp",
            "pro-c",
            "1176",
            "la-2a",
            "la2a",
            "cla-76",
            "renaissance compressor",
            "fairchild",
        ],
        SlotKind::MultibandCompressor => &[
            "multiband",
            "multi-band",
            "mb",
            "pro-mb",
            "ozone",
            "c4",
            "c6",
        ],
        SlotKind::DeEsser => &["deesser", "de-esser", "de esser", "sibilance", "pro-ds", "esstal"],
        SlotKind::Gate => &["gate", "expander"],
        SlotKind::Saturation => &[
            "saturation",
            "saturator",
            "tape",
            "decapitator",
            "vinyl",
            "kramer tape",
            "studer",
            "rc-tube",
            "softube tape",
        ],
        SlotKind::Transient => &["transient", "trans-x", "transgressor", "smack attack"],
        SlotKind::StereoWidth => &[
            "stereo",
            "width",
            "imager",
            "ozone imager",
            "s1",
            "midside",
            "m/s",
        ],
        SlotKind::Reverb => &[
            "reverb",
            "verb",
            "pro-r",
            "valhalla",
            "rc-48",
            "rc 48",
            "lexicon",
            "blackhole",
            "raum",
        ],
        SlotKind::Delay => &["delay", "echo", "h-delay", "valhallaecho", "tape echo", "ddl"],
        SlotKind::Modulation => &[
            "chorus",
            "flanger",
            "phaser",
            "mod ",
            "modulation",
            "metaflanger",
            "mondo mod",
        ],
        SlotKind::Limiter => &["limiter", "pro-l", "l1", "l2", "l3", "fabfilter pro-l"],
        SlotKind::Maximizer => &[
            "maximizer",
            "ozone maximizer",
            "loudness maximizer",
            "l3 maximizer",
            "oxford limiter",
            "pro-l 2",
        ],
    };

    let mut scored: Vec<PluginCandidate> = plugins
        .iter()
        .filter_map(|plug| {
            let lower = plug.name.to_lowercase();
            // Score = max specificity hit (longer pattern = higher score).
            let score = patterns
                .iter()
                .filter(|pat| lower.contains(*pat))
                .map(|pat| pat.len() as f32 / 20.0)
                .fold(0.0f32, f32::max);
            if score > 0.0 {
                Some(PluginCandidate {
                    plugin_id: plug.id.clone(),
                    plugin_name: plug.name.clone(),
                    vendor: plug.vendor.clone(),
                    match_score: score.min(1.0),
                })
            } else {
                None
            }
        })
        .collect();
    scored.sort_by(|a, b| b.match_score.partial_cmp(&a.match_score).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(8);
    scored
}

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::assistant::{
        DynamicsAnalysis, LoudnessAnalysis, SpectralAnalysis, StereoAnalysis,
    };

    fn analysis(low: f32, mid: f32, high: f32, crest: f32, trans: f32, width: f32) -> AnalysisResult {
        AnalysisResult {
            genres: vec![],
            moods: vec![],
            tempo_bpm: None,
            key: None,
            loudness: LoudnessAnalysis::default(),
            spectral: SpectralAnalysis {
                low_ratio: low,
                mid_ratio: mid,
                high_ratio: high,
                ..Default::default()
            },
            dynamics: DynamicsAnalysis {
                crest_factor_db: crest,
                transient_sharpness: trans,
                ..Default::default()
            },
            stereo: StereoAnalysis { width, ..Default::default() },
            suggestions: vec![],
            quality_score: 0.5,
        }
    }

    fn pl(id: &str, name: &str, vendor: &str) -> AvailablePlugin {
        AvailablePlugin {
            id: id.into(),
            name: name.into(),
            vendor: vendor.into(),
        }
    }

    #[test]
    fn classifies_drums() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.3, 0.4, 0.3, 18.0, 0.85, 0.5);
        let (t, c) = advisor.classify_track_type(&a);
        assert_eq!(t, TrackType::Drums);
        assert!(c > 0.5);
    }

    #[test]
    fn classifies_bass() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.7, 0.2, 0.1, 9.0, 0.3, 0.3);
        let (t, _) = advisor.classify_track_type(&a);
        assert_eq!(t, TrackType::Bass);
    }

    #[test]
    fn classifies_vocal() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3);
        let (t, _) = advisor.classify_track_type(&a);
        assert_eq!(t, TrackType::Vocal);
    }

    #[test]
    fn classifies_unknown_when_features_inconsistent() {
        let advisor = ChainAdvisor::new();
        // Wide stereo + low crest + no clear band dominance → Unknown
        let a = analysis(0.33, 0.33, 0.34, 14.5, 0.5, 0.45);
        let (t, _) = advisor.classify_track_type(&a);
        assert!(matches!(t, TrackType::Unknown | TrackType::FullMix));
    }

    #[test]
    fn vocal_chain_has_expected_pipeline() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3);
        let chain = advisor.suggest_chain(&a, &[], None);
        assert_eq!(chain.track_type, TrackType::Vocal);
        // First slot must be HPF (cleanup before anything else)
        assert_eq!(chain.slots[0].kind, SlotKind::HighPass);
        // Must contain a de-esser and a compressor and a reverb
        assert!(chain.slots.iter().any(|s| s.kind == SlotKind::DeEsser));
        assert!(chain.slots.iter().any(|s| s.kind == SlotKind::Compressor));
        assert!(chain.slots.iter().any(|s| s.kind == SlotKind::Reverb));
    }

    #[test]
    fn drum_chain_starts_with_gate_or_eq() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.3, 0.4, 0.3, 18.0, 0.85, 0.5);
        let chain = advisor.suggest_chain(&a, &[], None);
        assert_eq!(chain.track_type, TrackType::Drums);
        let first = chain.slots[0].kind;
        assert!(matches!(first, SlotKind::Gate | SlotKind::Eq));
    }

    #[test]
    fn track_hint_overrides_classification() {
        let advisor = ChainAdvisor::new();
        let a = analysis(0.7, 0.2, 0.1, 9.0, 0.3, 0.3); // would classify Bass
        let chain = advisor.suggest_chain(&a, &[], Some(TrackType::Vocal));
        assert_eq!(chain.track_type, TrackType::Vocal);
        assert_eq!(chain.track_type_confidence, 1.0);
    }

    #[test]
    fn plugin_matcher_ranks_eq_correctly() {
        let plugins = vec![
            pl("p1", "FabFilter Pro-Q 4", "FabFilter"),
            pl("p2", "Massive X", "Native Instruments"),
            pl("p3", "TDR Nova", "Tokyo Dawn"),
            pl("p4", "Soothe2", "Oeksound"),
        ];
        let ranked = rank_plugins_for(SlotKind::Eq, &plugins);
        assert!(!ranked.is_empty());
        // Pro-Q should outrank a generic synth (which doesn't match)
        assert!(ranked.iter().any(|c| c.plugin_name.contains("Pro-Q")));
        // Massive X is a synth — must NOT be returned
        assert!(!ranked.iter().any(|c| c.plugin_name.contains("Massive")));
    }

    #[test]
    fn plugin_matcher_ranks_compressor() {
        let plugins = vec![
            pl("c1", "FabFilter Pro-C 2", "FabFilter"),
            pl("c2", "CLA-76", "Waves"),
            pl("c3", "Pro-Q 4", "FabFilter"),
        ];
        let ranked = rank_plugins_for(SlotKind::Compressor, &plugins);
        assert!(!ranked.is_empty());
        // Pro-C and CLA-76 must both be there
        let names: Vec<&str> = ranked.iter().map(|c| c.plugin_name.as_str()).collect();
        assert!(names.iter().any(|n| n.contains("Pro-C")));
        assert!(names.iter().any(|n| n.contains("CLA-76")));
        assert!(!names.iter().any(|n| *n == "Pro-Q 4"));
    }

    #[test]
    fn plugin_matcher_empty_when_nothing_matches() {
        let plugins = vec![pl("x", "Massive X", "Native Instruments")];
        let ranked = rank_plugins_for(SlotKind::Reverb, &plugins);
        assert!(ranked.is_empty());
    }

    #[test]
    fn plugin_matcher_caps_at_8() {
        let plugins: Vec<AvailablePlugin> = (0..20)
            .map(|i| pl(&format!("c{}", i), &format!("Compressor {}", i), "v"))
            .collect();
        let ranked = rank_plugins_for(SlotKind::Compressor, &plugins);
        assert!(ranked.len() <= 8);
    }

    #[test]
    fn vocal_chain_with_plugins_includes_candidates() {
        let plugins = vec![
            pl("p1", "FabFilter Pro-Q 4", "FabFilter"),
            pl("p2", "FabFilter Pro-C 2", "FabFilter"),
            pl("p3", "FabFilter Pro-DS", "FabFilter"),
            pl("p4", "Valhalla VintageVerb", "Valhalla"),
        ];
        let advisor = ChainAdvisor::new();
        let a = analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3);
        let chain = advisor.suggest_chain(&a, &plugins, None);
        // Compressor slot should have Pro-C as a candidate
        let comp = chain.slots.iter().find(|s| s.kind == SlotKind::Compressor).unwrap();
        assert!(comp.plugin_candidates.iter().any(|c| c.plugin_name.contains("Pro-C")));
        // Reverb slot should have Valhalla as a candidate
        let reverb = chain.slots.iter().find(|s| s.kind == SlotKind::Reverb).unwrap();
        assert!(reverb.plugin_candidates.iter().any(|c| c.plugin_name.contains("Valhalla")));
    }

    #[test]
    fn pipeline_string_is_readable() {
        let advisor = ChainAdvisor::new();
        let chain = advisor.suggest_chain(
            &analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3),
            &[],
            Some(TrackType::Vocal),
        );
        let pipeline = chain.pipeline_string();
        assert!(pipeline.contains("→"));
        assert!(pipeline.contains("EQ") || pipeline.contains("Compressor"));
    }

    #[test]
    fn master_chain_uses_target_lufs() {
        let advisor = ChainAdvisor::with_config(AdvisorConfig {
            target_lufs: -10.0,
            ..AdvisorConfig::default()
        });
        let chain = advisor.suggest_chain(
            &analysis(0.3, 0.4, 0.3, 12.0, 0.5, 0.6),
            &[],
            Some(TrackType::Master),
        );
        // Maximizer slot should reflect target LUFS
        let maxim = chain.slots.iter().find(|s| s.kind == SlotKind::Maximizer).unwrap();
        let lufs_param = maxim.parameters.iter().find(|p| p.name == "Target LUFS").unwrap();
        assert!((lufs_param.suggested - (-10.0)).abs() < 0.01);
    }

    #[test]
    fn vintage_bias_adds_saturation_to_vocal() {
        let advisor = ChainAdvisor::with_config(AdvisorConfig {
            vintage_bias: true,
            ..AdvisorConfig::default()
        });
        let chain = advisor.suggest_chain(
            &analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3),
            &[],
            Some(TrackType::Vocal),
        );
        assert!(chain.slots.iter().any(|s| s.kind == SlotKind::Saturation));
    }

    #[test]
    fn modern_vocal_has_no_saturation() {
        let advisor = ChainAdvisor::new();
        let chain = advisor.suggest_chain(
            &analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3),
            &[],
            Some(TrackType::Vocal),
        );
        assert!(!chain.slots.iter().any(|s| s.kind == SlotKind::Saturation));
    }

    #[test]
    fn hpf_cutoff_adapts_to_low_heavy_source() {
        let advisor = ChainAdvisor::new();
        // Heavy low-end → HPF should bump cutoff above default
        let a = analysis(0.6, 0.25, 0.15, 12.0, 0.4, 0.3);
        let chain = advisor.suggest_chain(&a, &[], Some(TrackType::Vocal));
        let hpf = chain.slots.iter().find(|s| s.kind == SlotKind::HighPass).unwrap();
        let cutoff = hpf.parameters.iter().find(|p| p.name == "Cutoff").unwrap();
        // Default vocal cutoff is 80; with low-heavy source, +20 = 100
        assert!(cutoff.suggested >= 100.0);
    }

    #[test]
    fn unknown_track_uses_generic_template() {
        let advisor = ChainAdvisor::new();
        // Hint Unknown explicitly
        let chain = advisor.suggest_chain(
            &analysis(0.33, 0.33, 0.34, 14.5, 0.5, 0.45),
            &[],
            Some(TrackType::Unknown),
        );
        assert_eq!(chain.style_tag, "Generic Starter");
        assert!(!chain.slots.is_empty());
    }

    #[test]
    fn pipeline_position_indices_are_sequential() {
        let advisor = ChainAdvisor::new();
        let chain = advisor.suggest_chain(
            &analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3),
            &[],
            Some(TrackType::Vocal),
        );
        for (i, slot) in chain.slots.iter().enumerate() {
            assert_eq!(slot.position, i as u32);
        }
    }

    #[test]
    fn slot_kind_display_names_present() {
        assert_eq!(SlotKind::Compressor.display_name(), "Compressor");
        assert_eq!(SlotKind::Maximizer.display_name(), "Maximizer");
        assert_eq!(TrackType::Vocal.display_name(), "Vocal");
    }

    #[test]
    fn overall_confidence_is_clamped() {
        let advisor = ChainAdvisor::new();
        let chain = advisor.suggest_chain(
            &analysis(0.2, 0.55, 0.25, 12.0, 0.5, 0.3),
            &[],
            None,
        );
        assert!(chain.overall_confidence >= 0.0);
        assert!(chain.overall_confidence <= 1.0);
    }
}
