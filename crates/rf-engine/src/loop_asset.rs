//! LoopAsset — Authoritative data model for Wwise-grade looping.
//!
//! Single Source of Truth for all loop behavior. A LoopAsset describes
//! an audio source with embedded cues, loop regions, and transition policies.
//! All positions are in samples (u64), never milliseconds.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;

// ─── Constants ─────────────────────────────────────────────

/// Maximum cues per asset (security guard)
pub const MAX_CUES_PER_ASSET: usize = 256;

/// Maximum regions per asset (security guard)
pub const MAX_REGIONS_PER_ASSET: usize = 16;

// ─── Core Enums ────────────────────────────────────────────

/// Type of audio source reference.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourceType {
    /// Direct file reference (WAV, FLAC, etc.)
    File,
    /// Sprite slice (Howler / HTML5 Audio)
    Sprite,
}

/// Cue type for fast dispatch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CueType {
    /// Mandatory: logical start of segment body
    Entry,
    /// Mandatory: logical end of segment body
    Exit,
    /// User-defined sync point between Entry and Exit
    Custom,
    /// Stinger sync point
    Sync,
    /// Event trigger point
    Event,
}

/// Loop wrapping mode at the seam.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoopMode {
    /// Hard wrap: position jumps from out to in (micro-fade only)
    Hard,
    /// Crossfade wrap: dual-voice overlap at seam
    Crossfade,
}

/// Intro embedding policy — how the intro relates to the loop body.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WrapPolicy {
    /// Play [Entry..LoopIn] once, then loop [LoopIn..LoopOut]
    PlayOnceThenLoop,
    /// Loop [LoopIn..LoopOut] including content before LoopIn
    IncludeInLoop,
    /// Start directly at LoopIn, skip intro
    SkipIntro,
    /// Play [Entry..LoopIn] once, then stop (stinger/one-shot)
    IntroOnly,
}

/// Crossfade curve shape.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoopCrossfadeCurve {
    /// Equal-power (sin/cos) — default, mathematically optimal
    EqualPower,
    /// Linear (simple ramp)
    Linear,
    /// S-curve (Hermite)
    SCurve,
    /// Logarithmic
    Logarithmic,
    /// Exponential
    Exponential,
    /// Cosine half (fade in only)
    CosineHalf,
    /// Square root
    SquareRoot,
    /// Sine (asymmetric)
    Sine,
    /// Fast attack
    FastAttack,
    /// Slow attack
    SlowAttack,
}

impl Default for LoopCrossfadeCurve {
    fn default() -> Self {
        Self::EqualPower
    }
}

/// Quantization type for snapping loop points.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum QuantizeType {
    Bars,
    Beats,
    Grid,
}

/// Snap rule for quantization.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SnapRule {
    Nearest,
    Floor,
    Ceil,
}

/// Sync mode for transitions and region switches.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SyncMode {
    /// Switch at the next quantized bar boundary
    NextBar,
    /// Switch at the next quantized beat boundary
    NextBeat,
    /// Switch at the next custom cue
    NextCue,
    /// Switch immediately with crossfade
    Immediate,
    /// Switch at the Exit Cue of current region
    ExitCue,
    /// Switch when reaching LoopOut (natural wrap point)
    OnWrap,
    /// Sync to destination Entry Cue
    EntryCue,
    /// Start destination at same relative position
    SameTime,
}

// ─── Data Structures ───────────────────────────────────────

/// Reference to an audio source.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundRef {
    /// Source type: File or Sprite
    pub source_type: SourceType,
    /// Asset ID in the sound bank / sprite atlas
    pub sound_id: String,
    /// Sprite slice ID (only for Sprite type)
    pub sprite_id: Option<String>,
}

/// Timeline metadata from audio file analysis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineInfo {
    /// Native sample rate
    pub sample_rate: u32,
    /// Channel count
    pub channels: u16,
    /// Total length in samples
    pub length_samples: u64,
    /// BPM (optional, for bar/beat quantization)
    pub bpm: Option<f64>,
    /// Beats per bar (optional)
    pub beats_per_bar: Option<u32>,
}

/// A named cue point on an asset's timeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cue {
    /// Cue name. "Entry" and "Exit" are reserved.
    pub name: String,
    /// Position in samples from file start
    pub at_samples: u64,
    /// Cue type for fast dispatch
    pub cue_type: CueType,
}

/// Quantization configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Quantize {
    pub quantize_type: QuantizeType,
    /// Grid unit size in samples
    pub grid_samples: u64,
    /// Snap rule
    pub snap: SnapRule,
}

/// Pre-entry / post-exit zone behavior.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZonePolicy {
    /// Whether to play this zone during transitions
    pub enabled: bool,
    /// Fade duration (ms) at zone boundary
    pub fade_ms: f32,
    /// Fade curve
    pub fade_curve: LoopCrossfadeCurve,
}

impl Default for ZonePolicy {
    fn default() -> Self {
        Self {
            enabled: false,
            fade_ms: 100.0,
            fade_curve: LoopCrossfadeCurve::EqualPower,
        }
    }
}

/// A named loop region within an asset.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvancedLoopRegion {
    /// Region name (e.g., "LoopA", "LoopB")
    pub name: String,
    /// Loop-in point (samples)
    pub in_samples: u64,
    /// Loop-out point (samples)
    pub out_samples: u64,
    /// Loop mode (Hard or Crossfade)
    pub mode: LoopMode,
    /// Intro handling policy
    pub wrap_policy: WrapPolicy,
    /// Micro-fade at seam (ms), default 5ms
    pub seam_fade_ms: f32,
    /// Crossfade duration for dual-voice mode (ms)
    pub crossfade_ms: f32,
    /// Crossfade curve shape
    pub crossfade_curve: LoopCrossfadeCurve,
    /// Quantization rule (applied at authoring time)
    pub quantize: Option<Quantize>,
    /// Maximum loop count (None = infinite)
    pub max_loops: Option<u32>,
    /// Per-iteration gain factor (e.g., 0.85 = -1.4dB per loop, None = 1.0)
    pub iteration_gain_factor: Option<f32>,
    /// Random start offset range in samples (0 = disabled)
    pub random_start_range: u64,
}

impl Default for AdvancedLoopRegion {
    fn default() -> Self {
        Self {
            name: "LoopA".into(),
            in_samples: 0,
            out_samples: 0,
            mode: LoopMode::Hard,
            wrap_policy: WrapPolicy::PlayOnceThenLoop,
            seam_fade_ms: 5.0,
            crossfade_ms: 50.0,
            crossfade_curve: LoopCrossfadeCurve::EqualPower,
            quantize: None,
            max_loops: None,
            iteration_gain_factor: None,
            random_start_range: 0,
        }
    }
}

impl AdvancedLoopRegion {
    /// Region length in samples.
    #[inline]
    pub fn length_samples(&self) -> u64 {
        self.out_samples.saturating_sub(self.in_samples)
    }
}

/// A complete audio source with embedded loop metadata.
/// This is the Single Source of Truth for all loop behavior.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoopAsset {
    /// Unique identifier (e.g., "bgm_base_main")
    pub id: String,
    /// Reference to the audio source
    pub sound_ref: SoundRef,
    /// Timeline metadata
    pub timeline: TimelineInfo,
    /// All cues (Entry + Exit + Custom)
    pub cues: Vec<Cue>,
    /// Loop regions (at least one for a looping asset)
    pub regions: Vec<AdvancedLoopRegion>,
    /// Pre-entry zone behavior
    pub pre_entry: ZonePolicy,
    /// Post-exit zone behavior
    pub post_exit: ZonePolicy,
}

impl LoopAsset {
    /// Get the Entry Cue position (defaults to 0 if missing).
    pub fn entry_samples(&self) -> u64 {
        self.cues
            .iter()
            .find(|c| c.cue_type == CueType::Entry)
            .map(|c| c.at_samples)
            .unwrap_or(0)
    }

    /// Get the Exit Cue position (defaults to file length if missing).
    pub fn exit_samples(&self) -> u64 {
        self.cues
            .iter()
            .find(|c| c.cue_type == CueType::Exit)
            .map(|c| c.at_samples)
            .unwrap_or(self.timeline.length_samples)
    }

    /// Look up a region by name.
    pub fn region_by_name(&self, name: &str) -> Option<&AdvancedLoopRegion> {
        self.regions.iter().find(|r| r.name == name)
    }

    /// All custom cues (not Entry/Exit).
    pub fn custom_cues(&self) -> impl Iterator<Item = &Cue> {
        self.cues
            .iter()
            .filter(|c| c.cue_type != CueType::Entry && c.cue_type != CueType::Exit)
    }
}

// ─── Validation ────────────────────────────────────────────

/// Validation error types.
#[derive(Debug, Clone)]
pub enum ValidationError {
    V01MissingEntryCue,
    V02MissingExitCue,
    V03EntryNotBeforeExit { entry: u64, exit: u64 },
    V04CueOutOfBounds { name: String, at: u64 },
    V05RegionInNotBeforeOut { name: String },
    V06RegionOutOfBounds { name: String },
    V07SkipIntroButLoopInBeforeEntry { name: String },
    V08SeamFadeTooLong { name: String, fade_ms: f32, region_ms: f64 },
    V09SeamFadeExcessive { name: String, fade_ms: f32 },
    V10QuantizeGridZero { name: String },
    V11DuplicateRegionName { name: String },
    V12DuplicateCueName { name: String },
    V13CustomCueOutsideBody { name: String },
    V14NoRegions,
    V15CrossfadeTooLong { name: String, crossfade_ms: f32, region_ms: f64 },
    V16IterationGainInvalid { name: String, factor: f32 },
    V17TooManyCues { count: usize },
    V18TooManyRegions { count: usize },
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::V01MissingEntryCue => write!(f, "V-01: Missing Entry cue"),
            Self::V02MissingExitCue => write!(f, "V-02: Missing Exit cue"),
            Self::V03EntryNotBeforeExit { entry, exit } => {
                write!(f, "V-03: Entry ({entry}) not before Exit ({exit})")
            }
            Self::V04CueOutOfBounds { name, at } => {
                write!(f, "V-04: Cue '{name}' at {at} is out of bounds")
            }
            Self::V05RegionInNotBeforeOut { name } => {
                write!(f, "V-05: Region '{name}' in >= out")
            }
            Self::V06RegionOutOfBounds { name } => {
                write!(f, "V-06: Region '{name}' out > file length")
            }
            Self::V07SkipIntroButLoopInBeforeEntry { name } => {
                write!(f, "V-07: Region '{name}' skip-intro but LoopIn < Entry")
            }
            Self::V08SeamFadeTooLong { name, fade_ms, region_ms } => {
                write!(f, "V-08: Region '{name}' seam fade {fade_ms}ms > half region {region_ms}ms")
            }
            Self::V09SeamFadeExcessive { name, fade_ms } => {
                write!(f, "V-09: Region '{name}' seam fade {fade_ms}ms > 100ms (needs explicit override)")
            }
            Self::V10QuantizeGridZero { name } => {
                write!(f, "V-10: Region '{name}' quantize grid = 0")
            }
            Self::V11DuplicateRegionName { name } => {
                write!(f, "V-11: Duplicate region name '{name}'")
            }
            Self::V12DuplicateCueName { name } => {
                write!(f, "V-12: Duplicate cue name '{name}'")
            }
            Self::V13CustomCueOutsideBody { name } => {
                write!(f, "V-13: Custom cue '{name}' outside [Entry, Exit]")
            }
            Self::V14NoRegions => write!(f, "V-14: No regions defined"),
            Self::V15CrossfadeTooLong { name, crossfade_ms, region_ms } => {
                write!(f, "V-15: Region '{name}' crossfade {crossfade_ms}ms > half region {region_ms}ms")
            }
            Self::V16IterationGainInvalid { name, factor } => {
                write!(f, "V-16: Region '{name}' iteration_gain_factor {factor} must be in (0.0, 2.0]")
            }
            Self::V17TooManyCues { count } => {
                write!(f, "V-17: Too many cues ({count} > {MAX_CUES_PER_ASSET})")
            }
            Self::V18TooManyRegions { count } => {
                write!(f, "V-18: Too many regions ({count} > {MAX_REGIONS_PER_ASSET})")
            }
        }
    }
}

/// Validate a LoopAsset. Returns Ok(()) or a list of all errors.
pub fn validate_loop_asset(asset: &LoopAsset) -> Result<(), Vec<ValidationError>> {
    let mut errors = Vec::new();

    // V-17/18: Security limits
    if asset.cues.len() > MAX_CUES_PER_ASSET {
        errors.push(ValidationError::V17TooManyCues { count: asset.cues.len() });
    }
    if asset.regions.len() > MAX_REGIONS_PER_ASSET {
        errors.push(ValidationError::V18TooManyRegions { count: asset.regions.len() });
    }

    // V-01: Entry cue must exist
    if !asset.cues.iter().any(|c| c.cue_type == CueType::Entry) {
        errors.push(ValidationError::V01MissingEntryCue);
    }

    // V-02: Exit cue must exist
    if !asset.cues.iter().any(|c| c.cue_type == CueType::Exit) {
        errors.push(ValidationError::V02MissingExitCue);
    }

    // V-03: Entry < Exit
    let entry = asset.entry_samples();
    let exit = asset.exit_samples();
    if entry >= exit {
        errors.push(ValidationError::V03EntryNotBeforeExit { entry, exit });
    }

    // V-04: All cues in [0, length)
    for cue in &asset.cues {
        if cue.at_samples >= asset.timeline.length_samples {
            errors.push(ValidationError::V04CueOutOfBounds {
                name: cue.name.clone(),
                at: cue.at_samples,
            });
        }
    }

    // Region validations
    for region in &asset.regions {
        // V-05: in < out
        if region.in_samples >= region.out_samples {
            errors.push(ValidationError::V05RegionInNotBeforeOut {
                name: region.name.clone(),
            });
        }

        // V-06: out <= file length
        if region.out_samples > asset.timeline.length_samples {
            errors.push(ValidationError::V06RegionOutOfBounds {
                name: region.name.clone(),
            });
        }

        // V-07: SkipIntro consistency
        if region.in_samples < entry && region.wrap_policy == WrapPolicy::SkipIntro {
            errors.push(ValidationError::V07SkipIntroButLoopInBeforeEntry {
                name: region.name.clone(),
            });
        }

        // V-08: SeamFade sanity (fade <= half region)
        let region_samples = region.out_samples.saturating_sub(region.in_samples);
        let fade_samples =
            (region.seam_fade_ms * asset.timeline.sample_rate as f32 / 1000.0) as u64;
        if fade_samples * 2 > region_samples {
            let region_ms =
                region_samples as f64 / asset.timeline.sample_rate as f64 * 1000.0;
            errors.push(ValidationError::V08SeamFadeTooLong {
                name: region.name.clone(),
                fade_ms: region.seam_fade_ms,
                region_ms,
            });
        }

        // V-09: SeamFade > 100ms needs explicit override
        if region.seam_fade_ms > 100.0 {
            errors.push(ValidationError::V09SeamFadeExcessive {
                name: region.name.clone(),
                fade_ms: region.seam_fade_ms,
            });
        }

        // V-10: Quantize grid non-zero
        if let Some(ref q) = region.quantize {
            if q.grid_samples == 0 {
                errors.push(ValidationError::V10QuantizeGridZero {
                    name: region.name.clone(),
                });
            }
        }

        // V-15: Crossfade <= half region
        let region_ms =
            region_samples as f64 / asset.timeline.sample_rate as f64 * 1000.0;
        if (region.crossfade_ms as f64) > region_ms / 2.0 {
            errors.push(ValidationError::V15CrossfadeTooLong {
                name: region.name.clone(),
                crossfade_ms: region.crossfade_ms,
                region_ms,
            });
        }

        // V-16: iteration_gain_factor must be in (0.0, 2.0]
        if let Some(factor) = region.iteration_gain_factor {
            if factor <= 0.0 || factor > 2.0 {
                errors.push(ValidationError::V16IterationGainInvalid {
                    name: region.name.clone(),
                    factor,
                });
            }
        }
    }

    // V-11: Unique region names
    let mut seen_regions = HashSet::new();
    for region in &asset.regions {
        if !seen_regions.insert(&region.name) {
            errors.push(ValidationError::V11DuplicateRegionName {
                name: region.name.clone(),
            });
        }
    }

    // V-12: Unique cue names
    let mut seen_cues = HashSet::new();
    for cue in &asset.cues {
        if !seen_cues.insert(&cue.name) {
            errors.push(ValidationError::V12DuplicateCueName {
                name: cue.name.clone(),
            });
        }
    }

    // V-13: Custom cues must be between Entry and Exit
    for cue in &asset.cues {
        if cue.cue_type == CueType::Custom || cue.cue_type == CueType::Sync || cue.cue_type == CueType::Event {
            if cue.at_samples < entry || cue.at_samples > exit {
                errors.push(ValidationError::V13CustomCueOutsideBody {
                    name: cue.name.clone(),
                });
            }
        }
    }

    // V-14: At least one region for looping assets
    if asset.regions.is_empty() {
        errors.push(ValidationError::V14NoRegions);
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

// ─── Test Helpers ──────────────────────────────────────────

/// Creates a minimal valid LoopAsset for testing.
pub fn test_loop_asset(
    id: &str,
    sample_rate: u32,
    length_samples: u64,
    loop_in: u64,
    loop_out: u64,
) -> LoopAsset {
    LoopAsset {
        id: id.to_string(),
        sound_ref: SoundRef {
            source_type: SourceType::File,
            sound_id: format!("{id}_sound"),
            sprite_id: None,
        },
        timeline: TimelineInfo {
            sample_rate,
            channels: 2,
            length_samples,
            bpm: Some(120.0),
            beats_per_bar: Some(4),
        },
        cues: vec![
            Cue {
                name: "Entry".into(),
                at_samples: 0,
                cue_type: CueType::Entry,
            },
            Cue {
                name: "Exit".into(),
                at_samples: length_samples.saturating_sub(1),
                cue_type: CueType::Exit,
            },
        ],
        regions: vec![AdvancedLoopRegion {
            name: "LoopA".into(),
            in_samples: loop_in,
            out_samples: loop_out,
            mode: LoopMode::Hard,
            wrap_policy: WrapPolicy::PlayOnceThenLoop,
            seam_fade_ms: 5.0,
            crossfade_ms: 50.0,
            crossfade_curve: LoopCrossfadeCurve::EqualPower,
            quantize: None,
            max_loops: None,
            iteration_gain_factor: None,
            random_start_range: 0,
        }],
        pre_entry: ZonePolicy::default(),
        post_exit: ZonePolicy::default(),
    }
}
