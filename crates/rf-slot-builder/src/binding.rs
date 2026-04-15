//! Parameter binding — connects nodes to the math model and audio engine.
//!
//! Bindings are resolved at runtime by the executor:
//! - `MathBinding` → reads from the live math model / spin result
//! - `AudioBinding` → translated to HELIX Bus events on node enter/exit

use serde::{Deserialize, Serialize};

// ─── Math binding ─────────────────────────────────────────────────────────────

/// Reference to a parameter in the math model (PAR file / rf-ingest output).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathParamRef {
    /// Parameter namespace (e.g. "base", "feature.free_spins", "jackpot.grand")
    pub namespace: String,
    /// Parameter key within namespace (e.g. "rtp", "scatter_pays", "win_multiplier")
    pub key: String,
    /// Default value if parameter not found in math model
    pub default: Option<serde_json::Value>,
}

impl MathParamRef {
    pub fn new(namespace: impl Into<String>, key: impl Into<String>) -> Self {
        Self {
            namespace: namespace.into(),
            key: key.into(),
            default: None,
        }
    }

    pub fn with_default(mut self, val: impl Into<serde_json::Value>) -> Self {
        self.default = Some(val.into());
        self
    }

    pub fn qualified_name(&self) -> String {
        format!("{}.{}", self.namespace, self.key)
    }
}

/// How the math model drives a node's behavior.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct MathBinding {
    /// RTP target for this stage (from PAR model)
    pub rtp_ref: Option<MathParamRef>,
    /// Win multiplier reference (e.g. free spins multiplier)
    pub multiplier_ref: Option<MathParamRef>,
    /// Volatility index reference (1=low, 10=high)
    pub volatility_ref: Option<MathParamRef>,
    /// Hit frequency reference (0.0-1.0)
    pub hit_freq_ref: Option<MathParamRef>,
    /// Feature trigger probability reference
    pub trigger_prob_ref: Option<MathParamRef>,
    /// Max payout cap for this stage
    pub max_payout_ref: Option<MathParamRef>,
    /// Custom parameter bindings (key → MathParamRef)
    pub custom: std::collections::HashMap<String, MathParamRef>,
}

impl MathBinding {
    pub fn with_rtp(mut self, ns: &str, key: &str) -> Self {
        self.rtp_ref = Some(MathParamRef::new(ns, key));
        self
    }

    pub fn with_multiplier(mut self, ns: &str, key: &str) -> Self {
        self.multiplier_ref = Some(MathParamRef::new(ns, key));
        self
    }

    pub fn with_trigger_prob(mut self, ns: &str, key: &str) -> Self {
        self.trigger_prob_ref = Some(MathParamRef::new(ns, key));
        self
    }
}

// ─── Audio binding ────────────────────────────────────────────────────────────

/// Reference to a HELIX audio event or asset.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEventRef {
    /// Event name in the HELIX asset pack (e.g. "reel_spin_loop", "bigwin_ultra")
    pub event_name: String,
    /// Gain override (None = use HELIX default)
    pub gain_db: Option<f32>,
    /// Fade-in duration (ms)
    pub fade_in_ms: u32,
    /// Fade-out duration (ms)
    pub fade_out_ms: u32,
    /// Layer / bus to route to (None = default)
    pub bus: Option<String>,
    /// RTPC parameter overrides for this event
    pub rtpc_overrides: std::collections::HashMap<String, f32>,
}

impl AudioEventRef {
    pub fn new(event_name: impl Into<String>) -> Self {
        Self {
            event_name: event_name.into(),
            gain_db: None,
            fade_in_ms: 0,
            fade_out_ms: 0,
            bus: None,
            rtpc_overrides: Default::default(),
        }
    }

    pub fn with_gain(mut self, db: f32) -> Self {
        self.gain_db = Some(db);
        self
    }

    pub fn with_fade(mut self, in_ms: u32, out_ms: u32) -> Self {
        self.fade_in_ms = in_ms;
        self.fade_out_ms = out_ms;
        self
    }

    pub fn with_rtpc(mut self, key: impl Into<String>, value: f32) -> Self {
        self.rtpc_overrides.insert(key.into(), value);
        self
    }
}

/// Timing mode for when to fire audio on node entry
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AudioFireMode {
    /// Fire immediately on node entry
    #[default]
    Immediate,
    /// Fire after `delay_ms` milliseconds
    Delayed { delay_ms: u32 },
    /// Fire when a specific RTPC threshold is crossed
    OnRtpc { param: String, threshold: f32 },
    /// Fire at a specific beat position (synchronized to BPM)
    OnBeat { beat: f32 },
}

/// Complete audio binding for a node.
/// Defines what sounds play when entering, looping, and exiting this game phase.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AudioBinding {
    /// Events fired on node ENTRY
    pub on_enter: Vec<AudioEventRef>,

    /// Looping events while IN this node (stopped on exit)
    pub on_loop: Vec<AudioEventRef>,

    /// Events fired on node EXIT
    pub on_exit: Vec<AudioEventRef>,

    /// Events fired on a specific transition (keyed by transition UUID string)
    pub on_transition: std::collections::HashMap<String, Vec<AudioEventRef>>,

    /// Fire mode for entry events
    pub fire_mode: AudioFireMode,

    /// Duck music while this node is active (0.0 = full duck, 1.0 = no duck)
    pub music_duck_factor: Option<f32>,

    /// RTPC parameters to set on entry (key → value)
    pub rtpc_set: std::collections::HashMap<String, f32>,

    /// RTPC parameters to clear (reset to default) on exit
    pub rtpc_clear: Vec<String>,

    /// Whether this node participates in the Audio DNA brand identity
    pub audio_dna_active: bool,

    /// Override Audio DNA profile for this node (None = use blueprint default)
    pub audio_dna_profile: Option<String>,
}

impl AudioBinding {
    pub fn enter(mut self, event: AudioEventRef) -> Self {
        self.on_enter.push(event);
        self
    }

    pub fn looping(mut self, event: AudioEventRef) -> Self {
        self.on_loop.push(event);
        self
    }

    pub fn exit(mut self, event: AudioEventRef) -> Self {
        self.on_exit.push(event);
        self
    }

    pub fn duck_music(mut self, factor: f32) -> Self {
        self.music_duck_factor = Some(factor.clamp(0.0, 1.0));
        self
    }

    pub fn with_rtpc(mut self, key: impl Into<String>, value: f32) -> Self {
        self.rtpc_set.insert(key.into(), value);
        self
    }

    pub fn with_dna(mut self) -> Self {
        self.audio_dna_active = true;
        self
    }
}
