//! Jurisdiction profiles — regulatory thresholds per territory.
//!
//! Each jurisdiction defines maximum acceptable values for RGAI metrics.
//! These are based on published guidance documents and enforcement patterns.

use serde::{Deserialize, Serialize};

/// Supported jurisdictions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Jurisdiction {
    /// UK Gambling Commission — strictest globally
    Ukgc,
    /// Malta Gaming Authority
    Mga,
    /// Ontario iGaming (AGCO)
    Ontario,
    /// Sweden Spelinspektionen
    Sweden,
    /// Denmark Spillemyndigheden
    Denmark,
    /// Netherlands Kansspelautoriteit
    Netherlands,
    /// Australia ACMA (National Consumer Protection Framework)
    Australia,
    /// Custom jurisdiction with user-defined thresholds
    Custom,
}

impl Jurisdiction {
    /// All built-in jurisdictions (excludes Custom).
    pub fn all_builtin() -> &'static [Jurisdiction] {
        &[
            Self::Ukgc,
            Self::Mga,
            Self::Ontario,
            Self::Sweden,
            Self::Denmark,
            Self::Netherlands,
            Self::Australia,
        ]
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::Ukgc => "UKGC (United Kingdom)",
            Self::Mga => "MGA (Malta)",
            Self::Ontario => "AGCO (Ontario)",
            Self::Sweden => "Spelinspektionen (Sweden)",
            Self::Denmark => "Spillemyndigheden (Denmark)",
            Self::Netherlands => "KSA (Netherlands)",
            Self::Australia => "ACMA (Australia)",
            Self::Custom => "Custom",
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::Ukgc => "UKGC",
            Self::Mga => "MGA",
            Self::Ontario => "AGCO",
            Self::Sweden => "SE",
            Self::Denmark => "DK",
            Self::Netherlands => "NL",
            Self::Australia => "AU",
            Self::Custom => "CUSTOM",
        }
    }

    /// Get the default profile for this jurisdiction.
    pub fn profile(&self) -> JurisdictionProfile {
        match self {
            Self::Ukgc => JurisdictionProfile::ukgc(),
            Self::Mga => JurisdictionProfile::mga(),
            Self::Ontario => JurisdictionProfile::ontario(),
            Self::Sweden => JurisdictionProfile::sweden(),
            Self::Denmark => JurisdictionProfile::denmark(),
            Self::Netherlands => JurisdictionProfile::netherlands(),
            Self::Australia => JurisdictionProfile::australia(),
            Self::Custom => JurisdictionProfile::permissive(),
        }
    }
}

/// Threshold profile for a jurisdiction.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct JurisdictionProfile {
    pub jurisdiction: Jurisdiction,
    /// Maximum arousal coefficient before flagging.
    pub max_arousal: f64,
    /// Maximum near-miss deception index.
    pub max_near_miss_deception: f64,
    /// Maximum loss-disguise score.
    pub max_loss_disguise: f64,
    /// Maximum temporal distortion factor.
    pub max_temporal_distortion: f64,
    /// Whether this jurisdiction mandates LDW suppression.
    pub ldw_suppression_required: bool,
    /// Whether near-miss audio enhancement is prohibited.
    pub near_miss_enhancement_prohibited: bool,
    /// Maximum win celebration duration in seconds.
    pub max_celebration_duration_secs: f64,
    /// Whether cooling-off ambient audio is required after extended play.
    pub cooling_off_audio_required: bool,
    /// Session duration (minutes) after which cooling-off activates.
    pub cooling_off_trigger_minutes: u32,
    /// Whether audio must include session-time reminders.
    pub session_time_reminder_required: bool,
    /// Interval (minutes) for session-time audio reminders.
    pub session_time_reminder_interval_minutes: u32,
}

impl JurisdictionProfile {
    // ═══ UKGC: Strictest in the world ═══
    pub fn ukgc() -> Self {
        Self {
            jurisdiction: Jurisdiction::Ukgc,
            max_arousal: 0.60,
            max_near_miss_deception: 0.30,
            max_loss_disguise: 0.20, // UKGC hates LDW — essentially zero tolerance
            max_temporal_distortion: 0.50,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: true,
            max_celebration_duration_secs: 5.0,
            cooling_off_audio_required: true,
            cooling_off_trigger_minutes: 60,
            session_time_reminder_required: true,
            session_time_reminder_interval_minutes: 60,
        }
    }

    // ═══ MGA Malta: Moderate strictness ═══
    pub fn mga() -> Self {
        Self {
            jurisdiction: Jurisdiction::Mga,
            max_arousal: 0.70,
            max_near_miss_deception: 0.50,
            max_loss_disguise: 0.40,
            max_temporal_distortion: 0.60,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: false,
            max_celebration_duration_secs: 8.0,
            cooling_off_audio_required: false,
            cooling_off_trigger_minutes: 0,
            session_time_reminder_required: false,
            session_time_reminder_interval_minutes: 0,
        }
    }

    // ═══ Ontario AGCO: Moderate-strict ═══
    pub fn ontario() -> Self {
        Self {
            jurisdiction: Jurisdiction::Ontario,
            max_arousal: 0.65,
            max_near_miss_deception: 0.40,
            max_loss_disguise: 0.30,
            max_temporal_distortion: 0.55,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: true,
            max_celebration_duration_secs: 6.0,
            cooling_off_audio_required: true,
            cooling_off_trigger_minutes: 90,
            session_time_reminder_required: true,
            session_time_reminder_interval_minutes: 60,
        }
    }

    // ═══ Sweden Spelinspektionen: Very strict ═══
    pub fn sweden() -> Self {
        Self {
            jurisdiction: Jurisdiction::Sweden,
            max_arousal: 0.55,
            max_near_miss_deception: 0.35,
            max_loss_disguise: 0.25,
            max_temporal_distortion: 0.45,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: true,
            max_celebration_duration_secs: 4.0,
            cooling_off_audio_required: true,
            cooling_off_trigger_minutes: 60,
            session_time_reminder_required: true,
            session_time_reminder_interval_minutes: 30,
        }
    }

    // ═══ Denmark Spillemyndigheden: Moderate ═══
    pub fn denmark() -> Self {
        Self {
            jurisdiction: Jurisdiction::Denmark,
            max_arousal: 0.65,
            max_near_miss_deception: 0.45,
            max_loss_disguise: 0.35,
            max_temporal_distortion: 0.55,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: false,
            max_celebration_duration_secs: 7.0,
            cooling_off_audio_required: false,
            cooling_off_trigger_minutes: 0,
            session_time_reminder_required: true,
            session_time_reminder_interval_minutes: 60,
        }
    }

    // ═══ Netherlands KSA: Moderate-strict ═══
    pub fn netherlands() -> Self {
        Self {
            jurisdiction: Jurisdiction::Netherlands,
            max_arousal: 0.60,
            max_near_miss_deception: 0.35,
            max_loss_disguise: 0.25,
            max_temporal_distortion: 0.50,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: true,
            max_celebration_duration_secs: 5.0,
            cooling_off_audio_required: true,
            cooling_off_trigger_minutes: 60,
            session_time_reminder_required: true,
            session_time_reminder_interval_minutes: 30,
        }
    }

    // ═══ Australia ACMA: Moderate ═══
    pub fn australia() -> Self {
        Self {
            jurisdiction: Jurisdiction::Australia,
            max_arousal: 0.70,
            max_near_miss_deception: 0.45,
            max_loss_disguise: 0.35,
            max_temporal_distortion: 0.60,
            ldw_suppression_required: true,
            near_miss_enhancement_prohibited: false,
            max_celebration_duration_secs: 8.0,
            cooling_off_audio_required: false,
            cooling_off_trigger_minutes: 0,
            session_time_reminder_required: false,
            session_time_reminder_interval_minutes: 0,
        }
    }

    /// A permissive profile — for custom/unlisted jurisdictions or testing.
    pub fn permissive() -> Self {
        Self {
            jurisdiction: Jurisdiction::Custom,
            max_arousal: 1.0,
            max_near_miss_deception: 1.0,
            max_loss_disguise: 1.0,
            max_temporal_distortion: 1.0,
            ldw_suppression_required: false,
            near_miss_enhancement_prohibited: false,
            max_celebration_duration_secs: 30.0,
            cooling_off_audio_required: false,
            cooling_off_trigger_minutes: 0,
            session_time_reminder_required: false,
            session_time_reminder_interval_minutes: 0,
        }
    }

    /// The strictest threshold across multiple jurisdictions.
    pub fn strictest(jurisdictions: &[Jurisdiction]) -> Self {
        let profiles: Vec<JurisdictionProfile> =
            jurisdictions.iter().map(|j| j.profile()).collect();

        if profiles.is_empty() {
            return Self::permissive();
        }

        Self {
            jurisdiction: Jurisdiction::Custom,
            max_arousal: profiles.iter().map(|p| p.max_arousal).fold(f64::MAX, f64::min),
            max_near_miss_deception: profiles
                .iter()
                .map(|p| p.max_near_miss_deception)
                .fold(f64::MAX, f64::min),
            max_loss_disguise: profiles
                .iter()
                .map(|p| p.max_loss_disguise)
                .fold(f64::MAX, f64::min),
            max_temporal_distortion: profiles
                .iter()
                .map(|p| p.max_temporal_distortion)
                .fold(f64::MAX, f64::min),
            ldw_suppression_required: profiles.iter().any(|p| p.ldw_suppression_required),
            near_miss_enhancement_prohibited: profiles
                .iter()
                .any(|p| p.near_miss_enhancement_prohibited),
            max_celebration_duration_secs: profiles
                .iter()
                .map(|p| p.max_celebration_duration_secs)
                .fold(f64::MAX, f64::min),
            cooling_off_audio_required: profiles.iter().any(|p| p.cooling_off_audio_required),
            cooling_off_trigger_minutes: profiles
                .iter()
                .filter(|p| p.cooling_off_trigger_minutes > 0)
                .map(|p| p.cooling_off_trigger_minutes)
                .min()
                .unwrap_or(0),
            session_time_reminder_required: profiles
                .iter()
                .any(|p| p.session_time_reminder_required),
            session_time_reminder_interval_minutes: profiles
                .iter()
                .filter(|p| p.session_time_reminder_interval_minutes > 0)
                .map(|p| p.session_time_reminder_interval_minutes)
                .min()
                .unwrap_or(0),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_builtin_jurisdictions_have_profiles() {
        for j in Jurisdiction::all_builtin() {
            let p = j.profile();
            assert!(p.max_arousal > 0.0);
            assert!(p.max_arousal <= 1.0);
            assert!(p.max_near_miss_deception > 0.0);
            assert!(p.max_loss_disguise > 0.0);
        }
    }

    #[test]
    fn ukgc_is_strictest_on_ldw() {
        let ukgc = JurisdictionProfile::ukgc();
        for j in Jurisdiction::all_builtin() {
            let p = j.profile();
            assert!(
                ukgc.max_loss_disguise <= p.max_loss_disguise,
                "UKGC should be strictest on LDW, but {} is stricter",
                j.code()
            );
        }
    }

    #[test]
    fn sweden_requires_session_reminders_every_30min() {
        let se = JurisdictionProfile::sweden();
        assert!(se.session_time_reminder_required);
        assert_eq!(se.session_time_reminder_interval_minutes, 30);
    }

    #[test]
    fn strictest_picks_minimum_thresholds() {
        let merged = JurisdictionProfile::strictest(&[
            Jurisdiction::Ukgc,
            Jurisdiction::Sweden,
            Jurisdiction::Netherlands,
        ]);
        // Sweden has lowest arousal (0.55)
        assert!((merged.max_arousal - 0.55).abs() < 1e-10);
        // UKGC has lowest LDW (0.20)
        assert!((merged.max_loss_disguise - 0.20).abs() < 1e-10);
        // Sweden has shortest celebration (4.0s)
        assert!((merged.max_celebration_duration_secs - 4.0).abs() < 1e-10);
    }

    #[test]
    fn permissive_allows_everything() {
        let p = JurisdictionProfile::permissive();
        assert_eq!(p.max_arousal, 1.0);
        assert!(!p.ldw_suppression_required);
        assert!(!p.near_miss_enhancement_prohibited);
    }

    #[test]
    fn jurisdiction_codes_unique() {
        let codes: Vec<&str> = Jurisdiction::all_builtin().iter().map(|j| j.code()).collect();
        let mut deduped = codes.clone();
        deduped.sort();
        deduped.dedup();
        assert_eq!(codes.len(), deduped.len());
    }

    #[test]
    fn strictest_empty_returns_permissive() {
        let p = JurisdictionProfile::strictest(&[]);
        assert_eq!(p.max_arousal, 1.0);
    }

    #[test]
    fn cooling_off_trigger_picks_minimum_nonzero() {
        let merged = JurisdictionProfile::strictest(&[
            Jurisdiction::Ukgc,     // 60 min
            Jurisdiction::Ontario,  // 90 min
            Jurisdiction::Mga,      // 0 (disabled)
        ]);
        assert_eq!(merged.cooling_off_trigger_minutes, 60);
    }
}
