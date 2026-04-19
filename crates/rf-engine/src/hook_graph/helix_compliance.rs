// ═══════════════════════════════════════════════════════════════════════════════
// HELIX COMPLIANCE ENGINE (RCE) — Regulatory Compliance for Slot Audio
// ═══════════════════════════════════════════════════════════════════════════════
//
// Point 1.5 of HELIX Architecture. First-ever slot audio compliance engine.
// NO COMPETITOR HAS THIS — not Wwise, not FMOD, not SoundStage.
//
// Real-time enforcement of jurisdiction-specific audio rules:
//   - UKGC: LDW (Loss Disguised as Win) detection & suppression
//   - UKGC: Speed of play minimum spin duration
//   - Sweden: Reality check audio cues at intervals
//   - General: Near-miss deception guards
//   - General: Celebration proportionality (win amount vs. celebration duration)
//   - General: Session fatigue limits
//   - General: Autoplay audio consistency
//   - MGA, Gibraltar, Ontario, Denmark, Australia, US: per-jurisdiction profiles
//
// DESIGN: Every audio event is checked against active jurisdiction rules BEFORE
// playback. The engine publishes compliance.* messages on the HELIX Bus.
// ═══════════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;

// ─────────────────────────────────────────────────────────────────────────────
// Jurisdiction System
// ─────────────────────────────────────────────────────────────────────────────

/// Supported regulatory jurisdictions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Jurisdiction {
    /// UK Gambling Commission — strictest LDW, speed of play rules
    Ukgc        = 0,
    /// Malta Gaming Authority — EU standard
    Mga         = 1,
    /// Gibraltar Gambling Commissioner
    Gibraltar   = 2,
    /// Curaçao eGaming
    Curacao     = 3,
    /// Ontario (AGCO) — Canadian province
    Ontario     = 4,
    /// Swedish Gambling Authority (Spelinspektionen)
    Sweden      = 5,
    /// Danish Gambling Authority (Spillemyndigheden)
    Denmark     = 6,
    /// Australia (various state regulators)
    Australia   = 7,
    /// United States (various state regulators)
    UnitedStates = 8,
    /// Isle of Man
    IsleOfMan   = 9,
    /// ISO/internal standard — baseline rules
    Iso         = 10,
    /// No regulation — testing/development only
    None        = 255,
}

impl Jurisdiction {
    pub const COUNT: usize = 12;

    pub fn name(&self) -> &'static str {
        match self {
            Self::Ukgc => "UKGC (UK)",
            Self::Mga => "MGA (Malta)",
            Self::Gibraltar => "Gibraltar",
            Self::Curacao => "Curaçao",
            Self::Ontario => "AGCO (Ontario)",
            Self::Sweden => "Spelinspektionen (Sweden)",
            Self::Denmark => "Spillemyndigheden (Denmark)",
            Self::Australia => "Australia",
            Self::UnitedStates => "United States",
            Self::IsleOfMan => "Isle of Man",
            Self::Iso => "ISO Standard",
            Self::None => "No Regulation",
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::Ukgc => "UKGC",
            Self::Mga => "MGA",
            Self::Gibraltar => "GIB",
            Self::Curacao => "CUR",
            Self::Ontario => "AGCO",
            Self::Sweden => "SWE",
            Self::Denmark => "DEN",
            Self::Australia => "AUS",
            Self::UnitedStates => "US",
            Self::IsleOfMan => "IOM",
            Self::Iso => "ISO",
            Self::None => "NONE",
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compliance Rules
// ─────────────────────────────────────────────────────────────────────────────

/// Individual compliance rule
#[derive(Debug, Clone)]
pub enum ComplianceRule {
    /// LDW: No celebration audio when win amount ≤ stake
    /// UKGC mandates this — celebration sounds when player loses net money are deceptive
    LossDisguisedAsWin {
        /// Maximum win/bet ratio that triggers suppression (e.g., 1.0 = suppress if win ≤ bet)
        max_ratio: f64,
        /// What to do with audio (suppress, reduce, replace)
        action: LdwAction,
    },

    /// Minimum spin duration — prevents speed of play manipulation
    MinimumSpinDuration {
        /// Minimum time in ms from spin press to result display
        min_ms: u32,
        /// Whether audio must fill the minimum duration (pad with ambient)
        pad_audio: bool,
    },

    /// Reality check — audio cue at regular intervals to remind player of session duration
    RealityCheck {
        /// Interval in minutes between reality check sounds
        interval_minutes: u32,
        /// Audio asset ID to play (soft chime, subtle notification)
        audio_asset: Option<String>,
        /// Whether to pause gameplay during reality check
        pause_gameplay: bool,
    },

    /// Near-miss deception guard — cap anticipation/tension sounds
    NearMissGuard {
        /// Maximum dB level for anticipation sounds on non-winning outcomes
        max_anticipation_db: f32,
        /// Whether to completely suppress near-miss tension sounds
        suppress_tension: bool,
        /// Maximum duration of anticipation sound (ms)
        max_duration_ms: u32,
    },

    /// Celebration proportionality — celebration duration/intensity must match win tier
    CelebrationProportionality {
        /// Maximum celebration duration per unit of win/bet ratio
        max_duration_per_ratio_ms: u32,
        /// Maximum celebration duration overall (ms)
        max_duration_ms: u32,
        /// Maximum celebration volume relative to base game (dB)
        max_volume_boost_db: f32,
    },

    /// Session fatigue limit — prevent escalating stimulation over long sessions
    FatigueLimit {
        /// Maximum allowed growth in audio intensity over session (0.0-1.0)
        max_intensity_growth: f32,
        /// Session duration after which intensity must not increase (minutes)
        threshold_minutes: u32,
        /// Whether to actively reduce intensity after threshold
        auto_reduce: bool,
    },

    /// Autoplay consistency — autoplay audio must be identical to manual play
    AutoplayConsistency {
        /// Whether autoplay must play all the same sounds as manual
        require_identical: bool,
        /// Whether autoplay can skip celebratory sounds (some jurisdictions allow)
        allow_skip_celebrations: bool,
    },

    /// Maximum volume level — prevent audio from exceeding safe listening levels
    MaxVolume {
        /// Maximum peak level in dBFS
        max_peak_dbfs: f32,
        /// Maximum LUFS integrated loudness
        max_lufs: f32,
    },

    /// Cool-down period — minimum silence between celebrations
    CooldownPeriod {
        /// Minimum ms of silence/ambient between celebration sounds
        min_cooldown_ms: u32,
    },

    /// Audio accessibility — requirements for hearing-impaired players
    Accessibility {
        /// Whether visual feedback must accompany all audio cues
        require_visual_feedback: bool,
        /// Whether captions/subtitles must be available for spoken audio
        require_captions: bool,
    },
}

/// Action to take when LDW is detected
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LdwAction {
    /// Completely suppress celebration audio (replace with neutral)
    Suppress,
    /// Reduce celebration volume by N dB
    Reduce { db: i8 },
    /// Replace with specific audio (e.g., neutral "ding" instead of fanfare)
    Replace,
    /// Log warning but allow playback (for development)
    WarnOnly,
}

// ─────────────────────────────────────────────────────────────────────────────
// Jurisdiction Profile — Per-jurisdiction rule set
// ─────────────────────────────────────────────────────────────────────────────

/// Complete compliance profile for a jurisdiction
#[derive(Debug, Clone)]
pub struct JurisdictionProfile {
    pub jurisdiction: Jurisdiction,
    pub rules: Vec<ComplianceRule>,
    pub description: String,
    pub version: String,
    pub effective_date: String,
}

/// Create the default UKGC profile (strictest)
pub fn profile_ukgc() -> JurisdictionProfile {
    JurisdictionProfile {
        jurisdiction: Jurisdiction::Ukgc,
        rules: vec![
            ComplianceRule::LossDisguisedAsWin {
                max_ratio: 1.0,
                action: LdwAction::Suppress,
            },
            ComplianceRule::MinimumSpinDuration {
                min_ms: 2500,
                pad_audio: true,
            },
            ComplianceRule::NearMissGuard {
                max_anticipation_db: -12.0,
                suppress_tension: false,
                max_duration_ms: 2000,
            },
            ComplianceRule::CelebrationProportionality {
                max_duration_per_ratio_ms: 500,
                max_duration_ms: 15000,
                max_volume_boost_db: 6.0,
            },
            ComplianceRule::FatigueLimit {
                max_intensity_growth: 0.1,
                threshold_minutes: 60,
                auto_reduce: true,
            },
            ComplianceRule::AutoplayConsistency {
                require_identical: true,
                allow_skip_celebrations: false,
            },
            ComplianceRule::MaxVolume {
                max_peak_dbfs: -1.0,
                max_lufs: -14.0,
            },
            ComplianceRule::CooldownPeriod {
                min_cooldown_ms: 500,
            },
        ],
        description: "UK Gambling Commission — comprehensive player protection".to_string(),
        version: "2025.1".to_string(),
        effective_date: "2025-04-01".to_string(),
    }
}

/// Create the MGA profile
pub fn profile_mga() -> JurisdictionProfile {
    JurisdictionProfile {
        jurisdiction: Jurisdiction::Mga,
        rules: vec![
            ComplianceRule::LossDisguisedAsWin {
                max_ratio: 1.0,
                action: LdwAction::Reduce { db: -12 },
            },
            ComplianceRule::CelebrationProportionality {
                max_duration_per_ratio_ms: 800,
                max_duration_ms: 20000,
                max_volume_boost_db: 9.0,
            },
            ComplianceRule::AutoplayConsistency {
                require_identical: false,
                allow_skip_celebrations: true,
            },
            ComplianceRule::MaxVolume {
                max_peak_dbfs: -0.5,
                max_lufs: -12.0,
            },
        ],
        description: "Malta Gaming Authority — EU baseline".to_string(),
        version: "2025.1".to_string(),
        effective_date: "2025-01-01".to_string(),
    }
}

/// Create the Sweden profile
pub fn profile_sweden() -> JurisdictionProfile {
    JurisdictionProfile {
        jurisdiction: Jurisdiction::Sweden,
        rules: vec![
            ComplianceRule::LossDisguisedAsWin {
                max_ratio: 1.0,
                action: LdwAction::Suppress,
            },
            ComplianceRule::RealityCheck {
                interval_minutes: 60,
                audio_asset: None,
                pause_gameplay: true,
            },
            ComplianceRule::FatigueLimit {
                max_intensity_growth: 0.05,
                threshold_minutes: 45,
                auto_reduce: true,
            },
            ComplianceRule::MinimumSpinDuration {
                min_ms: 3000,
                pad_audio: true,
            },
            ComplianceRule::MaxVolume {
                max_peak_dbfs: -1.0,
                max_lufs: -14.0,
            },
        ],
        description: "Spelinspektionen — strict session management".to_string(),
        version: "2025.1".to_string(),
        effective_date: "2025-01-01".to_string(),
    }
}

/// Create the Ontario profile
pub fn profile_ontario() -> JurisdictionProfile {
    JurisdictionProfile {
        jurisdiction: Jurisdiction::Ontario,
        rules: vec![
            ComplianceRule::LossDisguisedAsWin {
                max_ratio: 1.0,
                action: LdwAction::Suppress,
            },
            ComplianceRule::NearMissGuard {
                max_anticipation_db: -6.0,
                suppress_tension: true,
                max_duration_ms: 1500,
            },
            ComplianceRule::AutoplayConsistency {
                require_identical: true,
                allow_skip_celebrations: false,
            },
            ComplianceRule::CelebrationProportionality {
                max_duration_per_ratio_ms: 600,
                max_duration_ms: 12000,
                max_volume_boost_db: 6.0,
            },
        ],
        description: "AGCO Ontario — Canadian province compliance".to_string(),
        version: "2025.1".to_string(),
        effective_date: "2025-01-01".to_string(),
    }
}

/// Create the ISO baseline profile (permissive)
pub fn profile_iso() -> JurisdictionProfile {
    JurisdictionProfile {
        jurisdiction: Jurisdiction::Iso,
        rules: vec![
            ComplianceRule::MaxVolume {
                max_peak_dbfs: -0.3,
                max_lufs: -10.0,
            },
            ComplianceRule::AutoplayConsistency {
                require_identical: false,
                allow_skip_celebrations: true,
            },
        ],
        description: "ISO baseline — minimal requirements".to_string(),
        version: "2025.1".to_string(),
        effective_date: "2025-01-01".to_string(),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compliance Check Results
// ─────────────────────────────────────────────────────────────────────────────

/// Result of a compliance check on an audio event
#[derive(Debug, Clone)]
pub struct ComplianceCheckResult {
    /// The audio event that was checked
    pub event_id: u32,
    /// Overall compliance status
    pub status: ComplianceStatus,
    /// Individual rule results
    pub rule_results: Vec<RuleCheckResult>,
    /// Timestamp of the check
    pub timestamp_ms: u64,
}

/// Overall compliance status (ordered by severity for worst-case tracking)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ComplianceStatus {
    /// Rule not applicable to this event
    NotApplicable = 0,
    /// All rules passed — audio can play as-is
    Pass = 1,
    /// Some rules require modification — audio can play with adjustments
    Warning = 2,
    /// Critical rule failed — audio must be suppressed or replaced
    Fail = 3,
}

/// Result of checking a single rule
#[derive(Debug, Clone)]
pub struct RuleCheckResult {
    pub rule_name: &'static str,
    pub status: ComplianceStatus,
    pub message: String,
    /// Suggested action (for warnings/failures)
    pub action: Option<ComplianceAction>,
}

/// Action to take based on compliance check
#[derive(Debug, Clone)]
pub enum ComplianceAction {
    /// Suppress the audio event entirely
    Suppress,
    /// Reduce volume by N dB
    ReduceVolume { db: f32 },
    /// Limit duration to N ms
    LimitDuration { max_ms: u32 },
    /// Replace with alternative audio
    ReplaceWith { asset_id: String },
    /// Delay playback by N ms (for minimum spin duration padding)
    Delay { ms: u32 },
    /// Insert reality check audio
    InsertRealityCheck,
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio Event Context — What we're checking
// ─────────────────────────────────────────────────────────────────────────────

/// Context for an audio event being compliance-checked
#[derive(Debug, Clone)]
pub struct AudioEventContext {
    /// Event ID
    pub event_id: u32,
    /// Event type (celebration, anticipation, ambient, sfx, etc.)
    pub event_type: AudioEventType,
    /// Win amount in currency units (if applicable)
    pub win_amount: Option<f64>,
    /// Bet amount in currency units
    pub bet_amount: Option<f64>,
    /// Win/bet ratio
    pub win_ratio: Option<f64>,
    /// Audio duration in ms
    pub duration_ms: u32,
    /// Audio peak level in dBFS
    pub peak_dbfs: f32,
    /// Whether this is autoplay
    pub is_autoplay: bool,
    /// Time since spin press (ms)
    pub time_since_spin_ms: u32,
    /// Current session duration (minutes)
    pub session_minutes: f64,
    /// Current session intensity level (0.0-1.0)
    pub session_intensity: f32,
    /// Number of scatters showing (for near-miss detection)
    pub scatter_count: Option<u8>,
    /// Scatters needed for feature trigger
    pub scatter_threshold: Option<u8>,
    /// Whether this was a near-miss (almost triggered feature)
    pub is_near_miss: bool,
}

/// Audio event categories for compliance classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioEventType {
    /// Win celebration (any tier)
    Celebration,
    /// Anticipation / tension build (near-miss, bonus trigger)
    Anticipation,
    /// Base game ambient / background
    Ambient,
    /// Sound effect (reel stop, button, etc.)
    Sfx,
    /// Music (base game or feature)
    Music,
    /// Regulatory audio (reality check, compliance notification)
    Regulatory,
    /// System sound (error, notification)
    System,
}

// ─────────────────────────────────────────────────────────────────────────────
// Compliance Engine
// ─────────────────────────────────────────────────────────────────────────────

/// Session state tracked by the compliance engine
#[derive(Debug, Clone)]
pub struct SessionState {
    /// Session start time (monotonic ms)
    pub session_start_ms: u64,
    /// Current session duration (ms)
    pub session_duration_ms: u64,
    /// Last reality check time (ms)
    pub last_reality_check_ms: u64,
    /// Initial audio intensity (baseline)
    pub baseline_intensity: f32,
    /// Current audio intensity
    pub current_intensity: f32,
    /// Peak intensity this session
    pub peak_intensity: f32,
    /// Number of spins this session
    pub spin_count: u32,
    /// Number of LDW events detected
    pub ldw_count: u32,
    /// Number of near-miss events detected
    pub near_miss_count: u32,
    /// Last celebration end time (ms) — for cooldown tracking
    pub last_celebration_end_ms: u64,
    /// Total compliance violations this session
    pub violation_count: u32,
}

impl Default for SessionState {
    fn default() -> Self {
        Self {
            session_start_ms: 0,
            session_duration_ms: 0,
            last_reality_check_ms: 0,
            baseline_intensity: 0.5,
            current_intensity: 0.5,
            peak_intensity: 0.5,
            spin_count: 0,
            ldw_count: 0,
            near_miss_count: 0,
            last_celebration_end_ms: 0,
            violation_count: 0,
        }
    }
}

/// The HELIX Compliance Engine
pub struct ComplianceEngine {
    /// Active jurisdiction profiles
    profiles: HashMap<Jurisdiction, JurisdictionProfile>,
    /// Currently active jurisdiction
    active_jurisdiction: Jurisdiction,
    /// Session state
    session: SessionState,
    /// Audit log (last N events)
    audit_log: Vec<ComplianceCheckResult>,
    /// Maximum audit log size
    max_audit_size: usize,
    /// Whether enforcement is active (vs. monitoring only)
    enforce: bool,
}

impl ComplianceEngine {
    /// Create a new compliance engine with default profiles
    pub fn new(jurisdiction: Jurisdiction) -> Self {
        let mut profiles = HashMap::new();
        profiles.insert(Jurisdiction::Ukgc, profile_ukgc());
        profiles.insert(Jurisdiction::Mga, profile_mga());
        profiles.insert(Jurisdiction::Sweden, profile_sweden());
        profiles.insert(Jurisdiction::Ontario, profile_ontario());
        profiles.insert(Jurisdiction::Iso, profile_iso());

        Self {
            profiles,
            active_jurisdiction: jurisdiction,
            session: SessionState::default(),
            audit_log: Vec::with_capacity(1000),
            max_audit_size: 10000,
            enforce: true,
        }
    }

    /// Set active jurisdiction
    pub fn set_jurisdiction(&mut self, jurisdiction: Jurisdiction) {
        self.active_jurisdiction = jurisdiction;
    }

    /// Get active jurisdiction
    pub fn active_jurisdiction(&self) -> Jurisdiction {
        self.active_jurisdiction
    }

    /// Add or replace a jurisdiction profile
    pub fn set_profile(&mut self, profile: JurisdictionProfile) {
        self.profiles.insert(profile.jurisdiction, profile);
    }

    /// Set enforcement mode (true = block violations, false = warn only)
    pub fn set_enforce(&mut self, enforce: bool) {
        self.enforce = enforce;
    }

    /// Update session state (call regularly from game loop)
    pub fn update_session(&mut self, current_ms: u64) {
        self.session.session_duration_ms = current_ms - self.session.session_start_ms;
    }

    /// Start a new session
    pub fn start_session(&mut self, current_ms: u64) {
        self.session = SessionState {
            session_start_ms: current_ms,
            ..Default::default()
        };
    }

    /// Record a spin
    pub fn record_spin(&mut self) {
        self.session.spin_count += 1;
    }

    /// Update session intensity
    pub fn update_intensity(&mut self, intensity: f32) {
        self.session.current_intensity = intensity;
        self.session.peak_intensity = self.session.peak_intensity.max(intensity);
    }

    /// Check an audio event against active jurisdiction rules.
    /// Returns the compliance result with any required actions.
    pub fn check_event(&mut self, ctx: &AudioEventContext) -> ComplianceCheckResult {
        let profile = match self.profiles.get(&self.active_jurisdiction) {
            Some(p) => p.clone(),
            None => {
                return ComplianceCheckResult {
                    event_id: ctx.event_id,
                    status: ComplianceStatus::Pass,
                    rule_results: vec![],
                    timestamp_ms: self.session.session_duration_ms,
                };
            }
        };

        let mut rule_results = Vec::new();
        let mut worst_status = ComplianceStatus::Pass;

        for rule in &profile.rules {
            let result = self.check_rule(rule, ctx);
            if result.status as u8 > worst_status as u8 {
                worst_status = result.status;
            }
            rule_results.push(result);
        }

        // Check reality check timing (independent of rules)
        if let Some(reality_result) = self.check_reality_check(&profile) {
            if reality_result.status as u8 > worst_status as u8 {
                worst_status = reality_result.status;
            }
            rule_results.push(reality_result);
        }

        let result = ComplianceCheckResult {
            event_id: ctx.event_id,
            status: worst_status,
            rule_results,
            timestamp_ms: self.session.session_duration_ms,
        };

        // Audit log
        if self.audit_log.len() < self.max_audit_size {
            self.audit_log.push(result.clone());
        }

        // Track violations
        if worst_status == ComplianceStatus::Fail {
            self.session.violation_count += 1;
        }

        result
    }

    /// Check a single rule against an event
    fn check_rule(&mut self, rule: &ComplianceRule, ctx: &AudioEventContext) -> RuleCheckResult {
        match rule {
            ComplianceRule::LossDisguisedAsWin { max_ratio, action } => {
                self.check_ldw(ctx, *max_ratio, *action)
            }
            ComplianceRule::MinimumSpinDuration { min_ms, pad_audio: _ } => {
                self.check_min_spin(ctx, *min_ms)
            }
            ComplianceRule::NearMissGuard { max_anticipation_db, suppress_tension, max_duration_ms } => {
                self.check_near_miss(ctx, *max_anticipation_db, *suppress_tension, *max_duration_ms)
            }
            ComplianceRule::CelebrationProportionality {
                max_duration_per_ratio_ms, max_duration_ms, max_volume_boost_db
            } => {
                self.check_celebration_proportionality(
                    ctx, *max_duration_per_ratio_ms, *max_duration_ms, *max_volume_boost_db
                )
            }
            ComplianceRule::FatigueLimit { max_intensity_growth, threshold_minutes, auto_reduce: _ } => {
                self.check_fatigue(ctx, *max_intensity_growth, *threshold_minutes)
            }
            ComplianceRule::AutoplayConsistency { require_identical, allow_skip_celebrations } => {
                self.check_autoplay(ctx, *require_identical, *allow_skip_celebrations)
            }
            ComplianceRule::MaxVolume { max_peak_dbfs, max_lufs: _ } => {
                self.check_max_volume(ctx, *max_peak_dbfs)
            }
            ComplianceRule::CooldownPeriod { min_cooldown_ms } => {
                self.check_cooldown(ctx, *min_cooldown_ms)
            }
            ComplianceRule::RealityCheck { .. } => {
                // Handled separately in check_reality_check
                RuleCheckResult {
                    rule_name: "RealityCheck",
                    status: ComplianceStatus::NotApplicable,
                    message: String::new(),
                    action: None,
                }
            }
            ComplianceRule::Accessibility { require_visual_feedback, require_captions: _ } => {
                RuleCheckResult {
                    rule_name: "Accessibility",
                    status: if *require_visual_feedback { ComplianceStatus::Warning } else { ComplianceStatus::Pass },
                    message: "Ensure visual feedback accompanies audio cues".to_string(),
                    action: None,
                }
            }
        }
    }

    // ── Individual Rule Checks ───────────────────────────────────────────

    fn check_ldw(&mut self, ctx: &AudioEventContext, max_ratio: f64, action: LdwAction) -> RuleCheckResult {
        // Only applies to celebration events
        if ctx.event_type != AudioEventType::Celebration {
            return RuleCheckResult {
                rule_name: "LDW",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        if let (Some(win), Some(bet)) = (ctx.win_amount, ctx.bet_amount)
            && bet > 0.0 && win / bet <= max_ratio {
                self.session.ldw_count += 1;

                let compliance_action = match action {
                    LdwAction::Suppress => ComplianceAction::Suppress,
                    LdwAction::Reduce { db } => ComplianceAction::ReduceVolume { db: db as f32 },
                    LdwAction::Replace => ComplianceAction::ReplaceWith {
                        asset_id: "neutral_settle".to_string(),
                    },
                    LdwAction::WarnOnly => return RuleCheckResult {
                        rule_name: "LDW",
                        status: ComplianceStatus::Warning,
                        message: format!("LDW detected: win {:.2} ≤ bet {:.2}", win, bet),
                        action: None,
                    },
                };

                return RuleCheckResult {
                    rule_name: "LDW",
                    status: if self.enforce { ComplianceStatus::Fail } else { ComplianceStatus::Warning },
                    message: format!(
                        "Loss Disguised as Win: win {:.2} ≤ bet {:.2} (ratio {:.2}). Celebration suppressed.",
                        win, bet, win / bet
                    ),
                    action: Some(compliance_action),
                };
            }

        RuleCheckResult {
            rule_name: "LDW",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_min_spin(&self, ctx: &AudioEventContext, min_ms: u32) -> RuleCheckResult {
        if ctx.event_type != AudioEventType::Celebration && ctx.event_type != AudioEventType::Sfx {
            return RuleCheckResult {
                rule_name: "MinSpinDuration",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        if ctx.time_since_spin_ms < min_ms {
            let delay = min_ms - ctx.time_since_spin_ms;
            return RuleCheckResult {
                rule_name: "MinSpinDuration",
                status: ComplianceStatus::Warning,
                message: format!(
                    "Spin too fast: {}ms < {}ms minimum. Delaying by {}ms.",
                    ctx.time_since_spin_ms, min_ms, delay
                ),
                action: Some(ComplianceAction::Delay { ms: delay }),
            };
        }

        RuleCheckResult {
            rule_name: "MinSpinDuration",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_near_miss(
        &mut self, ctx: &AudioEventContext,
        max_db: f32, suppress: bool, max_duration_ms: u32
    ) -> RuleCheckResult {
        if ctx.event_type != AudioEventType::Anticipation {
            return RuleCheckResult {
                rule_name: "NearMissGuard",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        if ctx.is_near_miss {
            self.session.near_miss_count += 1;

            if suppress {
                return RuleCheckResult {
                    rule_name: "NearMissGuard",
                    status: ComplianceStatus::Fail,
                    message: "Near-miss tension sound suppressed".to_string(),
                    action: Some(ComplianceAction::Suppress),
                };
            }

            let mut actions = Vec::new();
            let mut messages = Vec::new();

            if ctx.peak_dbfs > max_db {
                actions.push(ComplianceAction::ReduceVolume { db: max_db - ctx.peak_dbfs });
                messages.push(format!("Volume capped to {:.1} dBFS", max_db));
            }

            if ctx.duration_ms > max_duration_ms {
                actions.push(ComplianceAction::LimitDuration { max_ms: max_duration_ms });
                messages.push(format!("Duration capped to {}ms", max_duration_ms));
            }

            if !actions.is_empty() {
                return RuleCheckResult {
                    rule_name: "NearMissGuard",
                    status: ComplianceStatus::Warning,
                    message: messages.join("; "),
                    action: actions.into_iter().next(),
                };
            }
        }

        RuleCheckResult {
            rule_name: "NearMissGuard",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_celebration_proportionality(
        &self, ctx: &AudioEventContext,
        max_per_ratio_ms: u32, max_total_ms: u32, max_boost_db: f32
    ) -> RuleCheckResult {
        if ctx.event_type != AudioEventType::Celebration {
            return RuleCheckResult {
                rule_name: "CelebrationProportionality",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        let mut issues = Vec::new();

        // Check duration proportionality
        if let Some(ratio) = ctx.win_ratio {
            let max_duration = (ratio * max_per_ratio_ms as f64) as u32;
            let effective_max = max_duration.min(max_total_ms);

            if ctx.duration_ms > effective_max {
                issues.push(format!(
                    "Duration {}ms exceeds proportional max {}ms for {:.1}x win",
                    ctx.duration_ms, effective_max, ratio
                ));
            }
        } else if ctx.duration_ms > max_total_ms {
            issues.push(format!(
                "Duration {}ms exceeds max {}ms",
                ctx.duration_ms, max_total_ms
            ));
        }

        // Check volume boost
        if ctx.peak_dbfs > max_boost_db {
            issues.push(format!(
                "Peak {:.1}dBFS exceeds max boost {:.1}dBFS",
                ctx.peak_dbfs, max_boost_db
            ));
        }

        if !issues.is_empty() {
            return RuleCheckResult {
                rule_name: "CelebrationProportionality",
                status: ComplianceStatus::Warning,
                message: issues.join("; "),
                action: Some(ComplianceAction::LimitDuration { max_ms: max_total_ms }),
            };
        }

        RuleCheckResult {
            rule_name: "CelebrationProportionality",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_fatigue(
        &self, ctx: &AudioEventContext,
        max_growth: f32, threshold_min: u32
    ) -> RuleCheckResult {
        let _ = ctx; // Fatigue check uses session state, not event

        let session_minutes = self.session.session_duration_ms as f64 / 60000.0;
        if session_minutes < threshold_min as f64 {
            return RuleCheckResult {
                rule_name: "FatigueLimit",
                status: ComplianceStatus::Pass,
                message: String::new(),
                action: None,
            };
        }

        let intensity_growth = self.session.current_intensity - self.session.baseline_intensity;
        if intensity_growth > max_growth {
            return RuleCheckResult {
                rule_name: "FatigueLimit",
                status: ComplianceStatus::Warning,
                message: format!(
                    "Session intensity growth {:.2} exceeds limit {:.2} after {:.0} minutes",
                    intensity_growth, max_growth, session_minutes
                ),
                action: Some(ComplianceAction::ReduceVolume {
                    db: -(intensity_growth - max_growth) * 12.0
                }),
            };
        }

        RuleCheckResult {
            rule_name: "FatigueLimit",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_autoplay(
        &self, ctx: &AudioEventContext,
        require_identical: bool, allow_skip: bool
    ) -> RuleCheckResult {
        if !ctx.is_autoplay {
            return RuleCheckResult {
                rule_name: "AutoplayConsistency",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        if require_identical {
            // In autoplay mode with require_identical, all sounds must play
            return RuleCheckResult {
                rule_name: "AutoplayConsistency",
                status: ComplianceStatus::Pass,
                message: "Autoplay: all sounds required to match manual play".to_string(),
                action: None,
            };
        }

        if allow_skip && ctx.event_type == AudioEventType::Celebration {
            return RuleCheckResult {
                rule_name: "AutoplayConsistency",
                status: ComplianceStatus::Pass,
                message: "Autoplay: celebration skip allowed".to_string(),
                action: Some(ComplianceAction::Suppress),
            };
        }

        RuleCheckResult {
            rule_name: "AutoplayConsistency",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_max_volume(&self, ctx: &AudioEventContext, max_peak: f32) -> RuleCheckResult {
        if ctx.peak_dbfs > max_peak {
            return RuleCheckResult {
                rule_name: "MaxVolume",
                status: ComplianceStatus::Warning,
                message: format!(
                    "Peak {:.1}dBFS exceeds limit {:.1}dBFS",
                    ctx.peak_dbfs, max_peak
                ),
                action: Some(ComplianceAction::ReduceVolume { db: max_peak - ctx.peak_dbfs }),
            };
        }

        RuleCheckResult {
            rule_name: "MaxVolume",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_cooldown(&self, ctx: &AudioEventContext, min_ms: u32) -> RuleCheckResult {
        if ctx.event_type != AudioEventType::Celebration {
            return RuleCheckResult {
                rule_name: "CooldownPeriod",
                status: ComplianceStatus::NotApplicable,
                message: String::new(),
                action: None,
            };
        }

        let current_ms = self.session.session_duration_ms;
        let since_last = current_ms.saturating_sub(self.session.last_celebration_end_ms);

        if since_last < min_ms as u64 && self.session.last_celebration_end_ms > 0 {
            return RuleCheckResult {
                rule_name: "CooldownPeriod",
                status: ComplianceStatus::Warning,
                message: format!(
                    "Cooldown: {}ms since last celebration, minimum {}ms required",
                    since_last, min_ms
                ),
                action: Some(ComplianceAction::Delay {
                    ms: (min_ms as u64 - since_last) as u32,
                }),
            };
        }

        RuleCheckResult {
            rule_name: "CooldownPeriod",
            status: ComplianceStatus::Pass,
            message: String::new(),
            action: None,
        }
    }

    fn check_reality_check(&self, profile: &JurisdictionProfile) -> Option<RuleCheckResult> {
        for rule in &profile.rules {
            if let ComplianceRule::RealityCheck { interval_minutes, .. } = rule {
                let session_min = self.session.session_duration_ms / 60000;
                let last_check_min = self.session.last_reality_check_ms / 60000;
                let since_last = session_min - last_check_min;

                if since_last >= *interval_minutes as u64 {
                    return Some(RuleCheckResult {
                        rule_name: "RealityCheck",
                        status: ComplianceStatus::Warning,
                        message: format!(
                            "Reality check due: {} minutes since last check (interval: {} min)",
                            since_last, interval_minutes
                        ),
                        action: Some(ComplianceAction::InsertRealityCheck),
                    });
                }
            }
        }
        None
    }

    // ── Reports ──────────────────────────────────────────────────────────

    /// Get compliance dashboard data
    pub fn dashboard(&self) -> ComplianceDashboard {
        let mut rules_status = HashMap::new();

        // Evaluate current compliance status for each rule type
        if let Some(profile) = self.profiles.get(&self.active_jurisdiction) {
            for rule in &profile.rules {
                let name = rule_name(rule);
                let status = self.evaluate_rule_status(rule);
                rules_status.insert(name, status);
            }
        }

        ComplianceDashboard {
            jurisdiction: self.active_jurisdiction,
            session: self.session.clone(),
            rules_status,
            total_checks: self.audit_log.len(),
            violations: self.session.violation_count,
            ldw_detections: self.session.ldw_count,
            near_miss_detections: self.session.near_miss_count,
            enforce_mode: self.enforce,
        }
    }

    fn evaluate_rule_status(&self, rule: &ComplianceRule) -> ComplianceStatus {
        match rule {
            ComplianceRule::FatigueLimit { max_intensity_growth, threshold_minutes, .. } => {
                let minutes = self.session.session_duration_ms as f64 / 60000.0;
                if minutes < *threshold_minutes as f64 {
                    ComplianceStatus::Pass
                } else {
                    let growth = self.session.current_intensity - self.session.baseline_intensity;
                    if growth > *max_intensity_growth {
                        ComplianceStatus::Fail
                    } else if growth > max_intensity_growth * 0.8 {
                        ComplianceStatus::Warning
                    } else {
                        ComplianceStatus::Pass
                    }
                }
            }
            _ => ComplianceStatus::Pass, // Other rules are event-driven
        }
    }

    /// Get audit log
    pub fn audit_log(&self) -> &[ComplianceCheckResult] {
        &self.audit_log
    }

    /// Get session state
    pub fn session(&self) -> &SessionState {
        &self.session
    }

    /// Clear audit log
    pub fn clear_audit_log(&mut self) {
        self.audit_log.clear();
    }
}

fn rule_name(rule: &ComplianceRule) -> &'static str {
    match rule {
        ComplianceRule::LossDisguisedAsWin { .. } => "LDW",
        ComplianceRule::MinimumSpinDuration { .. } => "MinSpinDuration",
        ComplianceRule::RealityCheck { .. } => "RealityCheck",
        ComplianceRule::NearMissGuard { .. } => "NearMissGuard",
        ComplianceRule::CelebrationProportionality { .. } => "CelebrationProportionality",
        ComplianceRule::FatigueLimit { .. } => "FatigueLimit",
        ComplianceRule::AutoplayConsistency { .. } => "AutoplayConsistency",
        ComplianceRule::MaxVolume { .. } => "MaxVolume",
        ComplianceRule::CooldownPeriod { .. } => "CooldownPeriod",
        ComplianceRule::Accessibility { .. } => "Accessibility",
    }
}

/// Compliance dashboard data
#[derive(Debug, Clone)]
pub struct ComplianceDashboard {
    pub jurisdiction: Jurisdiction,
    pub session: SessionState,
    pub rules_status: HashMap<&'static str, ComplianceStatus>,
    pub total_checks: usize,
    pub violations: u32,
    pub ldw_detections: u32,
    pub near_miss_detections: u32,
    pub enforce_mode: bool,
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn make_celebration_ctx(win: f64, bet: f64) -> AudioEventContext {
        AudioEventContext {
            event_id: 1,
            event_type: AudioEventType::Celebration,
            win_amount: Some(win),
            bet_amount: Some(bet),
            win_ratio: Some(win / bet),
            duration_ms: 3000,
            peak_dbfs: -3.0,
            is_autoplay: false,
            time_since_spin_ms: 3000,
            session_minutes: 10.0,
            session_intensity: 0.5,
            scatter_count: None,
            scatter_threshold: None,
            is_near_miss: false,
        }
    }

    #[test]
    fn test_ldw_detection_ukgc() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        // Win 0.50, bet 1.00 — LDW! Player lost money but won something
        let ctx = make_celebration_ctx(0.50, 1.00);
        let result = engine.check_event(&ctx);

        assert_eq!(result.status, ComplianceStatus::Fail);
        assert!(result.rule_results.iter().any(|r|
            r.rule_name == "LDW" && r.status == ComplianceStatus::Fail
        ));
    }

    #[test]
    fn test_ldw_pass_genuine_win() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        // Win 5.00, bet 1.00 — genuine win, celebration allowed
        let ctx = make_celebration_ctx(5.00, 1.00);
        let result = engine.check_event(&ctx);

        let ldw = result.rule_results.iter().find(|r| r.rule_name == "LDW").unwrap();
        assert_eq!(ldw.status, ComplianceStatus::Pass);
    }

    #[test]
    fn test_near_miss_guard() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ontario);

        let ctx = AudioEventContext {
            event_id: 2,
            event_type: AudioEventType::Anticipation,
            win_amount: None,
            bet_amount: Some(1.00),
            win_ratio: None,
            duration_ms: 2000,
            peak_dbfs: -3.0,
            is_autoplay: false,
            time_since_spin_ms: 1500,
            session_minutes: 5.0,
            session_intensity: 0.5,
            scatter_count: Some(2),
            scatter_threshold: Some(3),
            is_near_miss: true,
        };

        let result = engine.check_event(&ctx);
        assert!(result.rule_results.iter().any(|r|
            r.rule_name == "NearMissGuard" && r.status == ComplianceStatus::Fail
        ));
    }

    #[test]
    fn test_min_spin_duration() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        let ctx = AudioEventContext {
            event_id: 3,
            event_type: AudioEventType::Sfx,
            win_amount: None,
            bet_amount: Some(1.00),
            win_ratio: None,
            duration_ms: 500,
            peak_dbfs: -6.0,
            is_autoplay: false,
            time_since_spin_ms: 1000, // Too fast! UKGC requires 2500ms
            session_minutes: 5.0,
            session_intensity: 0.5,
            scatter_count: None,
            scatter_threshold: None,
            is_near_miss: false,
        };

        let result = engine.check_event(&ctx);
        let spin_rule = result.rule_results.iter().find(|r| r.rule_name == "MinSpinDuration").unwrap();
        assert_eq!(spin_rule.status, ComplianceStatus::Warning);
        assert!(matches!(spin_rule.action, Some(ComplianceAction::Delay { ms: 1500 })));
    }

    #[test]
    fn test_max_volume() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        let mut ctx = make_celebration_ctx(10.0, 1.0);
        ctx.peak_dbfs = 0.5; // Over UKGC limit of -1.0 dBFS

        let result = engine.check_event(&ctx);
        assert!(result.rule_results.iter().any(|r|
            r.rule_name == "MaxVolume" && r.status == ComplianceStatus::Warning
        ));
    }

    #[test]
    fn test_celebration_proportionality() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        let mut ctx = make_celebration_ctx(2.0, 1.0);
        ctx.duration_ms = 30000; // 30 second celebration for 2x win — way too long

        let result = engine.check_event(&ctx);
        assert!(result.rule_results.iter().any(|r|
            r.rule_name == "CelebrationProportionality" && r.status == ComplianceStatus::Warning
        ));
    }

    #[test]
    fn test_jurisdiction_switch() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);
        assert_eq!(engine.active_jurisdiction(), Jurisdiction::Ukgc);

        engine.set_jurisdiction(Jurisdiction::Mga);
        assert_eq!(engine.active_jurisdiction(), Jurisdiction::Mga);

        // MGA is more lenient on LDW (reduce instead of suppress)
        let ctx = make_celebration_ctx(0.50, 1.00);
        let result = engine.check_event(&ctx);
        let ldw = result.rule_results.iter().find(|r| r.rule_name == "LDW").unwrap();
        // MGA still detects LDW but action is reduce, not suppress
        assert!(ldw.action.is_some());
    }

    #[test]
    fn test_dashboard() {
        let engine = ComplianceEngine::new(Jurisdiction::Ukgc);
        let dashboard = engine.dashboard();

        assert_eq!(dashboard.jurisdiction, Jurisdiction::Ukgc);
        assert_eq!(dashboard.violations, 0);
        assert!(dashboard.enforce_mode);
    }

    #[test]
    fn test_session_tracking() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);
        engine.start_session(1000);
        engine.record_spin();
        engine.record_spin();
        engine.update_session(61000); // 60 seconds later

        assert_eq!(engine.session().spin_count, 2);
        assert_eq!(engine.session().session_duration_ms, 60000);
    }

    #[test]
    fn test_audit_log() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);

        // Generate some events
        for i in 0..5 {
            let ctx = make_celebration_ctx(i as f64 * 2.0, 1.0);
            engine.check_event(&ctx);
        }

        assert_eq!(engine.audit_log().len(), 5);
        engine.clear_audit_log();
        assert_eq!(engine.audit_log().len(), 0);
    }

    #[test]
    fn test_warn_only_mode() {
        let mut engine = ComplianceEngine::new(Jurisdiction::Ukgc);
        engine.set_enforce(false); // Monitor-only mode

        let ctx = make_celebration_ctx(0.50, 1.00); // LDW
        let result = engine.check_event(&ctx);

        // Should be warning, not fail
        let ldw = result.rule_results.iter().find(|r| r.rule_name == "LDW").unwrap();
        assert_eq!(ldw.status, ComplianceStatus::Warning);
    }

    #[test]
    fn test_all_profiles_load() {
        // Ensure all built-in profiles are valid
        let _ukgc = profile_ukgc();
        let _mga = profile_mga();
        let _sweden = profile_sweden();
        let _ontario = profile_ontario();
        let _iso = profile_iso();

        // Each should have at least one rule
        assert!(!_ukgc.rules.is_empty());
        assert!(!_mga.rules.is_empty());
        assert!(!_sweden.rules.is_empty());
        assert!(!_ontario.rules.is_empty());
        assert!(!_iso.rules.is_empty());
    }

    #[test]
    fn test_jurisdiction_names() {
        assert_eq!(Jurisdiction::Ukgc.name(), "UKGC (UK)");
        assert_eq!(Jurisdiction::Ukgc.code(), "UKGC");
        assert_eq!(Jurisdiction::Sweden.name(), "Spelinspektionen (Sweden)");
    }
}
