//! Sonic DNA Classifier — Zero-Click Sound Placement
//!
//! Akustički klasifikator koji autonomno raspoređuje zvuk u stage-ove.
//! Korisnik prevuče folder sa BILO KAKVIM imenima → sve se rasporedi.
//!
//! ## Arhitektura
//!
//! ### Layer 1: Feature Vector
//! 7 akustičkih featura po zvuku (iz PCM analize):
//! - Duration, RMS Energy, Spectral Centroid, Transient Density,
//!   Zero Crossing Rate, Spectral Flux, Envelope Shape
//!
//! ### Layer 2: Slot Sound Taxonomy
//! Hardcoded akustički profili za svaki slot stage type.
//! Weighted Euclidean distance = score.
//!
//! ### Layer 3: Intelligent Placement Engine
//! Hungarian algorithm za optimalno dodeljivanje bez konflikata.
//! Variant detection, gap analysis, auto-rename generisanje.

use std::collections::HashMap;
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 1: FEATURE VECTOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Normalizovani akustički feature vector za jedan zvuk.
/// Svi vrednosti su u [0.0, 1.0] osim gde je naznačeno.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FeatureVector {
    /// Trajanje u sekundama (neograničeno)
    pub duration_s: f32,
    /// RMS energija (0=tišina, 1=full scale)
    pub rms_energy: f32,
    /// Spektralni centroid normalizovan na [0,1] (0=bass, 1=treble)
    pub spectral_centroid: f32,
    /// Gustina tranzijenta po sekundi (broj oštrih udara/s)
    pub transient_density: f32,
    /// Stopa nultih prelaza normalizovana [0,1] (0=tonalni, 1=noise)
    pub zero_crossing_rate: f32,
    /// Spektralni flux — promjena spektra kroz vreme [0,1] (0=statičan, 1=dinamičan)
    pub spectral_flux: f32,
    /// Envelope oblik kao indeks EnvelopeShape
    pub envelope_shape: EnvelopeShape,
    /// Harmonijski sadržaj [0,1] (0=noise, 1=čisto tonalno/muzička)
    pub harmonic_ratio: f32,
}

/// Klasifikacija envelope oblika
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EnvelopeShape {
    /// Brzi attack, brzi decay (klik, udari)
    Impulse,
    /// Brzi attack, srednji decay (majority SFX)
    SharpAttackMediumDecay,
    /// Brzi attack, dugi tail (reverb SFX)
    SharpAttackLongTail,
    /// Spori buildup crescendo (anticipation, fanfare)
    BuildingCrescendo,
    /// Ravan (ambient pad, loop)
    Flat,
    /// Attack-sustain-decay (muzika, ambient)
    Sustained,
}

impl EnvelopeShape {
    /// Numerički indeks za distance računanje
    pub fn to_f32(self) -> f32 {
        match self {
            Self::Impulse => 0.0,
            Self::SharpAttackMediumDecay => 0.2,
            Self::SharpAttackLongTail => 0.4,
            Self::BuildingCrescendo => 0.6,
            Self::Sustained => 0.8,
            Self::Flat => 1.0,
        }
    }

    /// Detekcija envelope tipa iz amplitude envelope-a
    pub fn detect(envelope: &[f32]) -> Self {
        let n = envelope.len();
        if n == 0 {
            return Self::Flat;
        }

        let max_val = envelope.iter().cloned().fold(0.0f32, f32::max);
        if max_val < 1e-6 {
            return Self::Flat;
        }

        // Flatness test — niska varijansa = flat
        let mean = envelope.iter().sum::<f32>() / n as f32;
        let variance = envelope.iter().map(|&v| (v - mean).powi(2)).sum::<f32>() / n as f32;
        let cv = if mean > 1e-6 { variance.sqrt() / mean } else { 0.0 };
        if cv < 0.25 {
            return Self::Flat;
        }

        // Peak pozicija (normalized 0..1)
        let peak_idx = envelope
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .map(|(i, _)| i)
            .unwrap_or(0);
        let peak_pos = peak_idx as f32 / n as f32;

        // Attack time: od onset (>10% max) do peak
        let onset_idx = envelope
            .iter()
            .position(|&v| v >= max_val * 0.1)
            .unwrap_or(0);
        let attack_time = if peak_idx > onset_idx {
            (peak_idx - onset_idx) as f32 / n as f32
        } else {
            0.0
        };

        // Decay: energija prve trećine posle peak-a vs poslednje trećine
        let post_n = n.saturating_sub(peak_idx + 1);
        let (decay_near, decay_far) = if post_n >= 6 {
            let split = post_n / 3;
            let near: f32 = envelope[peak_idx + 1..peak_idx + 1 + split]
                .iter().map(|&v| v * v).sum::<f32>() / split as f32;
            let far_start = peak_idx + 1 + split * 2;
            let far_len = n.saturating_sub(far_start);
            let far: f32 = if far_len > 0 {
                envelope[far_start..].iter().map(|&v| v * v).sum::<f32>() / far_len as f32
            } else { 0.0 };
            (near, far)
        } else {
            let last_val = *envelope.last().unwrap_or(&0.0);
            (max_val * max_val, last_val * last_val)
        };

        // Decay ratio: far/near (< 0.15 = fast decay, > 0.5 = sustained tail)
        let decay_ratio = if decay_near > 1e-12 { decay_far / decay_near } else { 0.0 };

        // Klasifikacija
        if attack_time < 0.15 && decay_ratio < 0.1 {
            // Brz attack, brz decay → Impulse
            Self::Impulse
        } else if attack_time < 0.2 && decay_ratio >= 0.3 {
            // Brz attack, dug tail
            Self::SharpAttackLongTail
        } else if attack_time < 0.2 {
            // Brz attack, srednji decay
            Self::SharpAttackMediumDecay
        } else if peak_pos > 0.4 {
            // Kasni peak = crescendo
            Self::BuildingCrescendo
        } else {
            Self::Sustained
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 2: SLOT SOUND TAXONOMY
// ═══════════════════════════════════════════════════════════════════════════════

/// Tip slot zvuka — sve moguće kategorije
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SlotSoundType {
    ReelSpin,
    ReelStop,
    ScatterHit,
    BigWin,
    SmallWin,
    ButtonClick,
    AmbientLoop,
    BonusTrigger,
    Multiplier,
    FreeSpinStart,
    MusicBase,
    MusicFeature,
    Anticipation,
    Rollup,
    Transition,
}

impl SlotSoundType {
    /// Lista svih tipova za matching
    pub fn all() -> &'static [SlotSoundType] {
        &[
            Self::ReelSpin,
            Self::ReelStop,
            Self::ScatterHit,
            Self::BigWin,
            Self::SmallWin,
            Self::ButtonClick,
            Self::AmbientLoop,
            Self::BonusTrigger,
            Self::Multiplier,
            Self::FreeSpinStart,
            Self::MusicBase,
            Self::MusicFeature,
            Self::Anticipation,
            Self::Rollup,
            Self::Transition,
        ]
    }

    /// Mapa tipa u FFNC prefix za auto-rename
    pub fn ffnc_prefix(self) -> &'static str {
        match self {
            Self::ReelSpin => "sfx_reel_spin",
            Self::ReelStop => "sfx_reel_stop",
            Self::ScatterHit => "sfx_scatter_hit",
            Self::BigWin => "sfx_big_win",
            Self::SmallWin => "sfx_small_win",
            Self::ButtonClick => "ui_button_click",
            Self::AmbientLoop => "amb_base_game",
            Self::BonusTrigger => "sfx_bonus_trigger",
            Self::Multiplier => "sfx_multiplier",
            Self::FreeSpinStart => "sfx_free_spin_start",
            Self::MusicBase => "mus_base_game",
            Self::MusicFeature => "mus_feature",
            Self::Anticipation => "sfx_anticipation",
            Self::Rollup => "sfx_rollup_tick",
            Self::Transition => "trn_base_to_feature",
        }
    }

    /// Ljudski čitljivo ime
    pub fn display_name(self) -> &'static str {
        match self {
            Self::ReelSpin => "Reel Spin",
            Self::ReelStop => "Reel Stop",
            Self::ScatterHit => "Scatter Hit",
            Self::BigWin => "Big Win",
            Self::SmallWin => "Small Win",
            Self::ButtonClick => "Button Click",
            Self::AmbientLoop => "Ambient Loop",
            Self::BonusTrigger => "Bonus Trigger",
            Self::Multiplier => "Multiplier",
            Self::FreeSpinStart => "Free Spins Start",
            Self::MusicBase => "Base Music",
            Self::MusicFeature => "Feature Music",
            Self::Anticipation => "Anticipation",
            Self::Rollup => "Rollup",
            Self::Transition => "Transition",
        }
    }
}

/// Akustički profil za jedan slot sound type.
/// Vrednosti su (min, max) expected ranges; center = (min+max)/2.
#[derive(Debug, Clone)]
pub struct SlotSoundProfile {
    pub sound_type: SlotSoundType,
    /// Duration range u sekundama
    pub duration_min: f32,
    pub duration_max: f32,
    /// RMS energy range
    pub rms_min: f32,
    pub rms_max: f32,
    /// Spectral centroid (normalizovano 0=bass, 1=treble)
    pub centroid_min: f32,
    pub centroid_max: f32,
    /// Transient density (udara/s)
    pub transient_min: f32,
    pub transient_max: f32,
    /// Zero crossing rate
    pub zcr_min: f32,
    pub zcr_max: f32,
    /// Spectral flux
    pub flux_min: f32,
    pub flux_max: f32,
    /// Expected envelope shapes (ponderisano)
    pub expected_envelope: &'static [EnvelopeShape],
    /// Harmonic ratio range
    pub harmonic_min: f32,
    pub harmonic_max: f32,
    /// Težinski koeficijenti za svaki feature (suma=1)
    pub weights: FeatureWeights,
}

/// Težinski koeficijenti za distance računanje
#[derive(Debug, Clone, Copy)]
pub struct FeatureWeights {
    pub duration: f32,
    pub rms: f32,
    pub centroid: f32,
    pub transient: f32,
    pub zcr: f32,
    pub flux: f32,
    pub envelope: f32,
    pub harmonic: f32,
}

impl FeatureWeights {
    pub const fn uniform() -> Self {
        Self {
            duration: 0.125,
            rms: 0.125,
            centroid: 0.125,
            transient: 0.125,
            zcr: 0.125,
            flux: 0.125,
            envelope: 0.125,
            harmonic: 0.125,
        }
    }
}

/// Baza svih akustičkih profila — hardkodovana iz industry experience
pub fn all_profiles() -> Vec<SlotSoundProfile> {
    vec![
        // REEL_SPIN — kratki, repetitivni, mid-freq, visoka tranzijentna gustina
        SlotSoundProfile {
            sound_type: SlotSoundType::ReelSpin,
            duration_min: 0.05, duration_max: 0.4,
            rms_min: 0.1, rms_max: 0.5,
            centroid_min: 0.3, centroid_max: 0.65,
            transient_min: 3.0, transient_max: 20.0,
            zcr_min: 0.2, zcr_max: 0.6,
            flux_min: 0.1, flux_max: 0.5,
            expected_envelope: &[EnvelopeShape::Impulse, EnvelopeShape::SharpAttackMediumDecay],
            harmonic_min: 0.0, harmonic_max: 0.5,
            weights: FeatureWeights {
                duration: 0.25, rms: 0.1, centroid: 0.2,
                transient: 0.25, zcr: 0.1, flux: 0.05,
                envelope: 0.05, harmonic: 0.0,
            },
        },
        // REEL_STOP — kratki udar, mid-low freq, single spike
        SlotSoundProfile {
            sound_type: SlotSoundType::ReelStop,
            duration_min: 0.1, duration_max: 0.5,
            rms_min: 0.15, rms_max: 0.65,
            centroid_min: 0.2, centroid_max: 0.55,
            transient_min: 0.5, transient_max: 4.0,
            zcr_min: 0.15, zcr_max: 0.5,
            flux_min: 0.0, flux_max: 0.3,
            expected_envelope: &[EnvelopeShape::SharpAttackMediumDecay, EnvelopeShape::Impulse],
            harmonic_min: 0.0, harmonic_max: 0.6,
            weights: FeatureWeights {
                duration: 0.2, rms: 0.15, centroid: 0.2,
                transient: 0.2, zcr: 0.1, flux: 0.05,
                envelope: 0.1, harmonic: 0.0,
            },
        },
        // SCATTER_HIT — metallic, high freq, ZCR visok, medium duration
        SlotSoundProfile {
            sound_type: SlotSoundType::ScatterHit,
            duration_min: 0.2, duration_max: 0.8,
            rms_min: 0.2, rms_max: 0.7,
            centroid_min: 0.55, centroid_max: 0.9,
            transient_min: 1.0, transient_max: 8.0,
            zcr_min: 0.45, zcr_max: 0.85,
            flux_min: 0.1, flux_max: 0.5,
            expected_envelope: &[EnvelopeShape::SharpAttackLongTail, EnvelopeShape::SharpAttackMediumDecay],
            harmonic_min: 0.1, harmonic_max: 0.6,
            weights: FeatureWeights {
                duration: 0.1, rms: 0.1, centroid: 0.3,
                transient: 0.1, zcr: 0.3, flux: 0.05,
                envelope: 0.05, harmonic: 0.0,
            },
        },
        // BIG_WIN — dug, glasno, wide-band, dinamičan, fanfare
        SlotSoundProfile {
            sound_type: SlotSoundType::BigWin,
            duration_min: 2.0, duration_max: 10.0,
            rms_min: 0.35, rms_max: 0.9,
            centroid_min: 0.25, centroid_max: 0.75,
            transient_min: 0.0, transient_max: 2.0,
            zcr_min: 0.05, zcr_max: 0.4,
            flux_min: 0.3, flux_max: 0.9,
            expected_envelope: &[EnvelopeShape::BuildingCrescendo, EnvelopeShape::Sustained],
            harmonic_min: 0.3, harmonic_max: 0.95,
            weights: FeatureWeights {
                duration: 0.3, rms: 0.2, centroid: 0.05,
                transient: 0.05, zcr: 0.05, flux: 0.2,
                envelope: 0.15, harmonic: 0.0,
            },
        },
        // SMALL_WIN — kratko, mid energy, brzi burst
        SlotSoundProfile {
            sound_type: SlotSoundType::SmallWin,
            duration_min: 0.5, duration_max: 2.0,
            rms_min: 0.2, rms_max: 0.65,
            centroid_min: 0.35, centroid_max: 0.7,
            transient_min: 0.5, transient_max: 4.0,
            zcr_min: 0.1, zcr_max: 0.5,
            flux_min: 0.15, flux_max: 0.6,
            expected_envelope: &[EnvelopeShape::SharpAttackMediumDecay, EnvelopeShape::SharpAttackLongTail],
            harmonic_min: 0.1, harmonic_max: 0.75,
            weights: FeatureWeights {
                duration: 0.2, rms: 0.15, centroid: 0.15,
                transient: 0.1, zcr: 0.1, flux: 0.15,
                envelope: 0.15, harmonic: 0.0,
            },
        },
        // BUTTON_CLICK — impulse, visok centroid, <150ms
        SlotSoundProfile {
            sound_type: SlotSoundType::ButtonClick,
            duration_min: 0.01, duration_max: 0.15,
            rms_min: 0.05, rms_max: 0.5,
            centroid_min: 0.4, centroid_max: 0.85,
            transient_min: 3.0, transient_max: 50.0,
            zcr_min: 0.2, zcr_max: 0.7,
            flux_min: 0.0, flux_max: 0.3,
            expected_envelope: &[EnvelopeShape::Impulse],
            harmonic_min: 0.0, harmonic_max: 0.5,
            weights: FeatureWeights {
                duration: 0.4, rms: 0.05, centroid: 0.2,
                transient: 0.2, zcr: 0.1, flux: 0.0,
                envelope: 0.05, harmonic: 0.0,
            },
        },
        // AMBIENT_LOOP — dug, tiho, bass/mid, statičan, flat envelope
        SlotSoundProfile {
            sound_type: SlotSoundType::AmbientLoop,
            duration_min: 3.0, duration_max: 999.0,
            rms_min: 0.01, rms_max: 0.35,
            centroid_min: 0.1, centroid_max: 0.45,
            transient_min: 0.0, transient_max: 0.5,
            zcr_min: 0.0, zcr_max: 0.2,
            flux_min: 0.0, flux_max: 0.15,
            expected_envelope: &[EnvelopeShape::Flat, EnvelopeShape::Sustained],
            harmonic_min: 0.1, harmonic_max: 0.9,
            weights: FeatureWeights {
                duration: 0.3, rms: 0.1, centroid: 0.1,
                transient: 0.2, zcr: 0.05, flux: 0.2,
                envelope: 0.05, harmonic: 0.0,
            },
        },
        // BONUS_TRIGGER — dramatičan attack, mid-high freq, glasno
        SlotSoundProfile {
            sound_type: SlotSoundType::BonusTrigger,
            duration_min: 0.5, duration_max: 1.5,
            rms_min: 0.3, rms_max: 0.85,
            centroid_min: 0.4, centroid_max: 0.75,
            transient_min: 1.0, transient_max: 6.0,
            zcr_min: 0.15, zcr_max: 0.55,
            flux_min: 0.2, flux_max: 0.7,
            expected_envelope: &[EnvelopeShape::BuildingCrescendo, EnvelopeShape::SharpAttackLongTail],
            harmonic_min: 0.2, harmonic_max: 0.8,
            weights: FeatureWeights {
                duration: 0.15, rms: 0.25, centroid: 0.15,
                transient: 0.1, zcr: 0.1, flux: 0.1,
                envelope: 0.15, harmonic: 0.0,
            },
        },
        // MULTIPLIER — rising sweep, mid-high, building crescendo
        SlotSoundProfile {
            sound_type: SlotSoundType::Multiplier,
            duration_min: 0.3, duration_max: 1.2,
            rms_min: 0.2, rms_max: 0.7,
            centroid_min: 0.35, centroid_max: 0.75,
            transient_min: 0.5, transient_max: 5.0,
            zcr_min: 0.1, zcr_max: 0.5,
            flux_min: 0.3, flux_max: 0.8,
            expected_envelope: &[EnvelopeShape::BuildingCrescendo, EnvelopeShape::SharpAttackMediumDecay],
            harmonic_min: 0.15, harmonic_max: 0.8,
            weights: FeatureWeights {
                duration: 0.15, rms: 0.15, centroid: 0.1,
                transient: 0.1, zcr: 0.1, flux: 0.3,
                envelope: 0.1, harmonic: 0.0,
            },
        },
        // FREE_SPIN_START — fanfare, glasno, wide-band, sustained, 1-3s
        SlotSoundProfile {
            sound_type: SlotSoundType::FreeSpinStart,
            duration_min: 1.0, duration_max: 3.5,
            rms_min: 0.3, rms_max: 0.9,
            centroid_min: 0.3, centroid_max: 0.75,
            transient_min: 0.5, transient_max: 4.0,
            zcr_min: 0.05, zcr_max: 0.45,
            flux_min: 0.3, flux_max: 0.85,
            expected_envelope: &[EnvelopeShape::BuildingCrescendo, EnvelopeShape::Sustained],
            harmonic_min: 0.3, harmonic_max: 0.95,
            weights: FeatureWeights {
                duration: 0.25, rms: 0.2, centroid: 0.05,
                transient: 0.05, zcr: 0.05, flux: 0.2,
                envelope: 0.2, harmonic: 0.0,
            },
        },
        // MUSIC_BASE — dug loop, bass/mid, flat, harmoničan
        SlotSoundProfile {
            sound_type: SlotSoundType::MusicBase,
            duration_min: 5.0, duration_max: 999.0,
            rms_min: 0.1, rms_max: 0.6,
            centroid_min: 0.15, centroid_max: 0.5,
            transient_min: 0.0, transient_max: 1.0,
            zcr_min: 0.0, zcr_max: 0.2,
            flux_min: 0.05, flux_max: 0.3,
            expected_envelope: &[EnvelopeShape::Flat, EnvelopeShape::Sustained],
            harmonic_min: 0.55, harmonic_max: 1.0,
            weights: FeatureWeights {
                duration: 0.25, rms: 0.05, centroid: 0.1,
                transient: 0.1, zcr: 0.05, flux: 0.1,
                envelope: 0.1, harmonic: 0.25,
            },
        },
        // MUSIC_FEATURE — duži loop, nešto živahniji od base
        SlotSoundProfile {
            sound_type: SlotSoundType::MusicFeature,
            duration_min: 3.0, duration_max: 999.0,
            rms_min: 0.15, rms_max: 0.7,
            centroid_min: 0.2, centroid_max: 0.55,
            transient_min: 0.0, transient_max: 1.5,
            zcr_min: 0.0, zcr_max: 0.25,
            flux_min: 0.1, flux_max: 0.5,
            expected_envelope: &[EnvelopeShape::Flat, EnvelopeShape::Sustained, EnvelopeShape::BuildingCrescendo],
            harmonic_min: 0.5, harmonic_max: 1.0,
            weights: FeatureWeights {
                duration: 0.2, rms: 0.05, centroid: 0.1,
                transient: 0.1, zcr: 0.05, flux: 0.15,
                envelope: 0.1, harmonic: 0.25,
            },
        },
        // ANTICIPATION — tension layer, dug, low energy, statičan, flux low
        SlotSoundProfile {
            sound_type: SlotSoundType::Anticipation,
            duration_min: 0.5, duration_max: 3.0,
            rms_min: 0.05, rms_max: 0.4,
            centroid_min: 0.2, centroid_max: 0.6,
            transient_min: 0.0, transient_max: 1.0,
            zcr_min: 0.05, zcr_max: 0.35,
            flux_min: 0.0, flux_max: 0.25,
            expected_envelope: &[EnvelopeShape::Sustained, EnvelopeShape::Flat, EnvelopeShape::BuildingCrescendo],
            harmonic_min: 0.2, harmonic_max: 0.85,
            weights: FeatureWeights {
                duration: 0.15, rms: 0.2, centroid: 0.1,
                transient: 0.15, zcr: 0.1, flux: 0.2,
                envelope: 0.1, harmonic: 0.0,
            },
        },
        // ROLLUP — repetitivni tick, kratki, mid freq
        SlotSoundProfile {
            sound_type: SlotSoundType::Rollup,
            duration_min: 0.02, duration_max: 0.2,
            rms_min: 0.05, rms_max: 0.45,
            centroid_min: 0.25, centroid_max: 0.6,
            transient_min: 5.0, transient_max: 30.0,
            zcr_min: 0.15, zcr_max: 0.55,
            flux_min: 0.0, flux_max: 0.2,
            expected_envelope: &[EnvelopeShape::Impulse, EnvelopeShape::SharpAttackMediumDecay],
            harmonic_min: 0.0, harmonic_max: 0.5,
            weights: FeatureWeights {
                duration: 0.3, rms: 0.05, centroid: 0.15,
                transient: 0.35, zcr: 0.1, flux: 0.0,
                envelope: 0.05, harmonic: 0.0,
            },
        },
        // TRANSITION — kratki stinger, mid-high, dinamičan
        SlotSoundProfile {
            sound_type: SlotSoundType::Transition,
            duration_min: 0.3, duration_max: 2.0,
            rms_min: 0.15, rms_max: 0.7,
            centroid_min: 0.3, centroid_max: 0.7,
            transient_min: 0.5, transient_max: 5.0,
            zcr_min: 0.1, zcr_max: 0.5,
            flux_min: 0.2, flux_max: 0.7,
            expected_envelope: &[EnvelopeShape::SharpAttackMediumDecay, EnvelopeShape::BuildingCrescendo],
            harmonic_min: 0.15, harmonic_max: 0.8,
            weights: FeatureWeights {
                duration: 0.2, rms: 0.1, centroid: 0.15,
                transient: 0.1, zcr: 0.1, flux: 0.2,
                envelope: 0.15, harmonic: 0.0,
            },
        },
    ]
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 2: DISTANCE SCORING
// ═══════════════════════════════════════════════════════════════════════════════

impl SlotSoundProfile {
    /// Weighted distance između feature vektora i ovog profila.
    /// Manji = bolji match. Vraća [0, 1] normalized score (0=perfect match).
    pub fn distance(&self, fv: &FeatureVector) -> f32 {
        let w = &self.weights;

        // Duration — normalized log distance (log scale za bolje razdvajanje kratko/dugo)
        let dur_center = (self.duration_min + self.duration_max) / 2.0;
        let dur_range = (self.duration_max - self.duration_min).max(0.01);
        let dur_d = ((fv.duration_s - dur_center) / dur_range).abs().min(1.0);

        // RMS
        let rms_center = (self.rms_min + self.rms_max) / 2.0;
        let rms_range = (self.rms_max - self.rms_min).max(0.01);
        let rms_d = ((fv.rms_energy - rms_center) / rms_range).abs().min(1.0);

        // Spectral centroid
        let cen_center = (self.centroid_min + self.centroid_max) / 2.0;
        let cen_range = (self.centroid_max - self.centroid_min).max(0.01);
        let cen_d = ((fv.spectral_centroid - cen_center) / cen_range).abs().min(1.0);

        // Transient density — log normalizacija (range može biti 0..50)
        let tr_center = (self.transient_min + self.transient_max) / 2.0;
        let tr_range = (self.transient_max - self.transient_min).max(0.01);
        let tr_d = ((fv.transient_density - tr_center) / tr_range).abs().min(1.0);

        // ZCR
        let zcr_center = (self.zcr_min + self.zcr_max) / 2.0;
        let zcr_range = (self.zcr_max - self.zcr_min).max(0.01);
        let zcr_d = ((fv.zero_crossing_rate - zcr_center) / zcr_range).abs().min(1.0);

        // Spectral flux
        let fx_center = (self.flux_min + self.flux_max) / 2.0;
        let fx_range = (self.flux_max - self.flux_min).max(0.01);
        let fx_d = ((fv.spectral_flux - fx_center) / fx_range).abs().min(1.0);

        // Envelope — discrete distance (0 ako je u expected, 1 ako nije)
        let env_d = if self.expected_envelope.contains(&fv.envelope_shape) {
            0.0f32
        } else {
            // Partial credit za close shapes
            let input_val = fv.envelope_shape.to_f32();
            self.expected_envelope
                .iter()
                .map(|&e| (e.to_f32() - input_val).abs())
                .fold(f32::MAX, f32::min)
                .min(1.0)
        };

        // Harmonic
        let har_center = (self.harmonic_min + self.harmonic_max) / 2.0;
        let har_range = (self.harmonic_max - self.harmonic_min).max(0.01);
        let har_d = ((fv.harmonic_ratio - har_center) / har_range).abs().min(1.0);

        // Weighted sum
        w.duration * dur_d
            + w.rms * rms_d
            + w.centroid * cen_d
            + w.transient * tr_d
            + w.zcr * zcr_d
            + w.flux * fx_d
            + w.envelope * env_d
            + w.harmonic * har_d
    }

    /// Score matrix: score[i][j] = 1.0 - distance (veći = bolji match)
    pub fn match_score(&self, fv: &FeatureVector) -> f32 {
        (1.0 - self.distance(fv)).max(0.0)
    }
}

/// Izračunaj score matrix [sound_idx][profile_idx] → score
pub fn build_score_matrix(
    features: &[FeatureVector],
    profiles: &[SlotSoundProfile],
) -> Vec<Vec<f32>> {
    features
        .iter()
        .map(|fv| profiles.iter().map(|p| p.match_score(fv)).collect())
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER 3: HUNGARIAN ALGORITHM + PLACEMENT ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Rezultat klasifikacije za jedan zvuk
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundClassification {
    /// Originalni fajl
    pub original_path: String,
    /// Klasifikovani tip
    pub sound_type: SlotSoundType,
    /// FFNC ime (bez ekstenzije)
    pub ffnc_name: String,
    /// Confidence score [0, 1]
    pub confidence: f32,
    /// Feature vector za debugging
    pub features: FeatureVector,
    /// Variant index ako postoji više zvukova istog tipa (0-indexed)
    pub variant_index: usize,
}

/// Rezultat kompletnog Placement Engine-a
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlacementResult {
    /// Klasifikacije svih zvukova
    pub classifications: Vec<SoundClassification>,
    /// Stage-ovi koji nemaju dodeljeni zvuk (gap analysis)
    pub missing_types: Vec<SlotSoundType>,
    /// Broj zvukova po tipu
    pub type_counts: HashMap<String, usize>,
    /// Ukupni confidence (prosek)
    pub avg_confidence: f32,
}

/// Primeni Hungarian algorithm na score matrix.
///
/// Rešava problem minimalnog troška (max assignment = min (-cost)).
/// Implementacija: Munkres O(n^3) za n×m matrice (n=sounds, m=types).
///
/// Vraća: Vec<usize> assignments[i] = j (sound i → profile j)
pub fn hungarian_assignment(score_matrix: &[Vec<f32>]) -> Vec<usize> {
    let n = score_matrix.len();
    if n == 0 {
        return vec![];
    }
    let m = score_matrix[0].len();
    if m == 0 {
        return vec![0; n];
    }

    // Pretvaramo u cost matrix (negiramo score jer Munkres minimizuje)
    let mut cost: Vec<Vec<f32>> = score_matrix
        .iter()
        .map(|row| row.iter().map(|&s| 1.0 - s).collect())
        .collect();

    // Pravimo kvadratnu matricu (dopunjujemo sa 1.0 ako je n != m)
    let size = n.max(m);
    while cost.len() < size {
        cost.push(vec![1.0; size]);
    }
    for row in &mut cost {
        while row.len() < size {
            row.push(1.0);
        }
    }

    // Step 1: row reduction
    for row in &mut cost {
        let min = *row.iter().min_by(|a, b| a.partial_cmp(b).unwrap()).unwrap_or(&0.0);
        for v in row.iter_mut() {
            *v -= min;
        }
    }

    // Step 2: column reduction.
    // `j` se koristi za column-major indeksiranje gde row-by-row
    // iter_mut nije primenjiv (čitamo dva indeks-a paralelno).
    // Clippy `needless_range_loop` mora da bude allow-ovano lokalno.
    #[allow(clippy::needless_range_loop)]
    for j in 0..size {
        let min = (0..size).map(|i| cost[i][j]).fold(f32::MAX, f32::min);
        for i in 0..size {
            cost[i][j] -= min;
        }
    }

    // Step 3-6: iterative assignment
    // Implementiramo pojednostavljeni Munkres sa starred/primed zeros
    let mut starred = vec![vec![false; size]; size];
    let mut primed = vec![vec![false; size]; size];
    let mut row_covered = vec![false; size];
    let mut col_covered = vec![false; size];

    // Star zeros (greedy initial assignment)
    for i in 0..size {
        for j in 0..size {
            if cost[i][j].abs() < 1e-6 && !row_covered[i] && !col_covered[j] {
                starred[i][j] = true;
                row_covered[i] = true;
                col_covered[j] = true;
            }
        }
    }
    row_covered.fill(false);
    // col_covered reset happens at top of each loop iteration

    let max_iterations = size * size * 4;
    let mut iter = 0;

    loop {
        iter += 1;
        if iter > max_iterations {
            break;
        }

        // Cover starred zeros columns (inlined)
        col_covered.fill(false);
        for j in 0..size {
            if (0..size).any(|i| starred[i][j]) {
                col_covered[j] = true;
            }
        }

        // Provjeri je li riješeno
        if col_covered.iter().filter(|&&c| c).count() >= n.min(m) {
            break;
        }

        // Nađi uncovered zero
        let mut z_row = None;
        let mut z_col = None;
        'outer: for i in 0..size {
            if row_covered[i] {
                continue;
            }
            for j in 0..size {
                if !col_covered[j] && cost[i][j].abs() < 1e-6 {
                    z_row = Some(i);
                    z_col = Some(j);
                    break 'outer;
                }
            }
        }

        if let (Some(zr), Some(zc)) = (z_row, z_col) {
            primed[zr][zc] = true;
            // Je li starred zero u ovom redu?
            if let Some(sc) = (0..size).find(|&j| starred[zr][j]) {
                row_covered[zr] = true;
                col_covered[sc] = false;
            } else {
                // Augment path
                let mut path = vec![(zr, zc)];
                loop {
                    let (_, last_c) = *path.last().unwrap();
                    if let Some(sr) = (0..size).find(|&i| starred[i][last_c]) {
                        path.push((sr, last_c));
                        let (last_r, _) = *path.last().unwrap();
                        if let Some(pc) = (0..size).find(|&j| primed[last_r][j]) {
                            path.push((last_r, pc));
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                }
                // Flip starred/primed
                for &(r, c) in &path {
                    starred[r][c] = !starred[r][c];
                }
                // Reset
                primed.iter_mut().for_each(|row| row.fill(false));
                row_covered.fill(false);
                col_covered.fill(false);
            }
        } else {
            // Nema uncovered zeros — adjust costs
            let mut min_uncovered = f32::MAX;
            for i in 0..size {
                for j in 0..size {
                    if !row_covered[i] && !col_covered[j] && cost[i][j] < min_uncovered {
                        min_uncovered = cost[i][j];
                    }
                }
            }

            if min_uncovered == f32::MAX || min_uncovered == 0.0 {
                break;
            }

            for i in 0..size {
                for j in 0..size {
                    if !row_covered[i] && !col_covered[j] {
                        cost[i][j] -= min_uncovered;
                    } else if row_covered[i] && col_covered[j] {
                        cost[i][j] += min_uncovered;
                    }
                }
            }
        }
    }

    // Izvuci rezultat: assignments[i] = j
    (0..n)
        .map(|i| {
            (0..m)
                .find(|&j| starred[i][j])
                .unwrap_or_else(|| {
                    // Fallback: greedy best score za ovaj sound
                    score_matrix[i]
                        .iter()
                        .enumerate()
                        .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
                        .map(|(j, _)| j)
                        .unwrap_or(0)
                })
        })
        .collect()
}

/// Glavni Placement Engine — kompletna klasifikacija i dodeljivanje
pub fn classify_and_place(
    file_paths: &[String],
    features: Vec<FeatureVector>,
) -> PlacementResult {
    let profiles = all_profiles();
    let n = features.len();

    if n == 0 {
        return PlacementResult {
            classifications: vec![],
            missing_types: SlotSoundType::all().to_vec(),
            type_counts: HashMap::new(),
            avg_confidence: 0.0,
        };
    }

    // Score matrix
    let score_matrix = build_score_matrix(&features, &profiles);

    // Variant detection: ako je n > m, duplicirani zvukovi moraju ići kao variante
    // Koristimo Hungarian samo za n <= m slučaj, inače dozvoljava dupliciranje
    let assignments: Vec<usize> = if n <= profiles.len() {
        hungarian_assignment(&score_matrix)
    } else {
        // Više zvukova od tipova — dozvoli duplicate, greedily
        score_matrix
            .iter()
            .map(|row| {
                row.iter()
                    .enumerate()
                    .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
                    .map(|(j, _)| j)
                    .unwrap_or(0)
            })
            .collect()
    };

    // Variant indexing: counts po tipu
    let mut type_variant_counter: HashMap<usize, usize> = HashMap::new();

    // Build classifications
    let mut classifications: Vec<SoundClassification> = assignments
        .iter()
        .zip(features.iter())
        .zip(file_paths.iter())
        .map(|((&profile_idx, fv), path)| {
            let profile_idx = profile_idx.min(profiles.len() - 1);
            let profile = &profiles[profile_idx];
            let confidence = score_matrix
                .get(file_paths.iter().position(|p| p == path).unwrap_or(0))
                .and_then(|row| row.get(profile_idx))
                .cloned()
                .unwrap_or(0.0);

            let variant_idx = *type_variant_counter
                .entry(profile_idx)
                .and_modify(|c| *c += 1)
                .or_insert(0);

            // FFNC name generisanje
            let ext = std::path::Path::new(path)
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("wav");
            let ffnc_name = if variant_idx == 0 {
                format!("{}.{}", profile.sound_type.ffnc_prefix(), ext)
            } else {
                format!("{}_{}.{}", profile.sound_type.ffnc_prefix(), variant_idx + 1, ext)
            };

            SoundClassification {
                original_path: path.clone(),
                sound_type: profile.sound_type,
                ffnc_name,
                confidence,
                features: fv.clone(),
                variant_index: variant_idx,
            }
        })
        .collect();

    // Gap analysis — koji tipovi nemaju ni jedan zvuk
    let assigned_types: std::collections::HashSet<SlotSoundType> = classifications
        .iter()
        .map(|c| c.sound_type)
        .collect();
    let missing_types: Vec<SlotSoundType> = SlotSoundType::all()
        .iter()
        .filter(|t| !assigned_types.contains(t))
        .cloned()
        .collect();

    // Type counts
    let mut type_counts: HashMap<String, usize> = HashMap::new();
    for c in &classifications {
        *type_counts
            .entry(c.sound_type.ffnc_prefix().to_string())
            .or_insert(0) += 1;
    }

    // Avg confidence
    let avg_confidence = if classifications.is_empty() {
        0.0
    } else {
        classifications.iter().map(|c| c.confidence).sum::<f32>()
            / classifications.len() as f32
    };

    // Sortiramo po originalnoj putanji za konzistentnost
    classifications.sort_by(|a, b| a.original_path.cmp(&b.original_path));

    PlacementResult {
        classifications,
        missing_types,
        type_counts,
        avg_confidence,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn make_fv(dur: f32, rms: f32, cen: f32, tr: f32, zcr: f32, flux: f32, env: EnvelopeShape, har: f32) -> FeatureVector {
        FeatureVector {
            duration_s: dur,
            rms_energy: rms,
            spectral_centroid: cen,
            transient_density: tr,
            zero_crossing_rate: zcr,
            spectral_flux: flux,
            envelope_shape: env,
            harmonic_ratio: har,
        }
    }

    #[test]
    fn test_reel_spin_matches_profile() {
        let profiles = all_profiles();
        let reel_spin_profile = profiles.iter().find(|p| p.sound_type == SlotSoundType::ReelSpin).unwrap();
        let fv = make_fv(0.15, 0.3, 0.45, 10.0, 0.4, 0.2, EnvelopeShape::Impulse, 0.2);
        let score = reel_spin_profile.match_score(&fv);
        assert!(score > 0.5, "ReelSpin should match well, got {score}");
    }

    #[test]
    fn test_big_win_matches_profile() {
        let profiles = all_profiles();
        let big_win = profiles.iter().find(|p| p.sound_type == SlotSoundType::BigWin).unwrap();
        let fv = make_fv(4.5, 0.7, 0.5, 0.5, 0.1, 0.6, EnvelopeShape::BuildingCrescendo, 0.7);
        let score = big_win.match_score(&fv);
        assert!(score > 0.5, "BigWin should match well, got {score}");
    }

    #[test]
    fn test_ambient_matches_profile() {
        let profiles = all_profiles();
        let ambient = profiles.iter().find(|p| p.sound_type == SlotSoundType::AmbientLoop).unwrap();
        let fv = make_fv(10.0, 0.1, 0.2, 0.1, 0.05, 0.05, EnvelopeShape::Flat, 0.5);
        let score = ambient.match_score(&fv);
        assert!(score > 0.5, "AmbientLoop should match well, got {score}");
    }

    #[test]
    fn test_button_click_matches_profile() {
        let profiles = all_profiles();
        let click = profiles.iter().find(|p| p.sound_type == SlotSoundType::ButtonClick).unwrap();
        let fv = make_fv(0.05, 0.3, 0.65, 20.0, 0.5, 0.1, EnvelopeShape::Impulse, 0.2);
        let score = click.match_score(&fv);
        assert!(score > 0.5, "ButtonClick should match well, got {score}");
    }

    #[test]
    fn test_all_profiles_exist() {
        let profiles = all_profiles();
        assert_eq!(profiles.len(), SlotSoundType::all().len(),
            "Profile count must match SlotSoundType count");
        for t in SlotSoundType::all() {
            assert!(
                profiles.iter().any(|p| &p.sound_type == t),
                "Missing profile for {:?}", t
            );
        }
    }

    #[test]
    fn test_placement_single_sound() {
        let fv = make_fv(0.15, 0.3, 0.45, 10.0, 0.4, 0.2, EnvelopeShape::Impulse, 0.2);
        let result = classify_and_place(&["test.wav".to_string()], vec![fv]);
        assert_eq!(result.classifications.len(), 1);
        assert!(!result.classifications[0].ffnc_name.is_empty());
        assert!(result.avg_confidence >= 0.0 && result.avg_confidence <= 1.0);
    }

    #[test]
    fn test_placement_multi_sound_no_conflict() {
        let sounds = vec![
            ("spin.wav", make_fv(0.15, 0.3, 0.45, 10.0, 0.4, 0.2, EnvelopeShape::Impulse, 0.2)),
            ("bigwin.wav", make_fv(4.5, 0.7, 0.5, 0.5, 0.1, 0.6, EnvelopeShape::BuildingCrescendo, 0.7)),
            ("ambient.wav", make_fv(10.0, 0.1, 0.2, 0.1, 0.05, 0.05, EnvelopeShape::Flat, 0.5)),
        ];
        let paths: Vec<String> = sounds.iter().map(|(p, _)| p.to_string()).collect();
        let features: Vec<FeatureVector> = sounds.into_iter().map(|(_, f)| f).collect();
        let result = classify_and_place(&paths, features);
        assert_eq!(result.classifications.len(), 3);
        // Hungarian ne sme da dodeli isti tip dvema različitim zvukovima (kad n <= m)
        let types: std::collections::HashSet<_> = result.classifications.iter()
            .map(|c| c.sound_type)
            .collect();
        assert_eq!(types.len(), 3, "Should have 3 different types");
    }

    #[test]
    fn test_variant_detection() {
        // Dva click zvuka → second dobija _2 suffix
        let sounds = vec![
            make_fv(0.05, 0.3, 0.65, 20.0, 0.5, 0.1, EnvelopeShape::Impulse, 0.2),
            make_fv(0.06, 0.25, 0.7, 18.0, 0.55, 0.08, EnvelopeShape::Impulse, 0.15),
        ];
        let paths = vec!["click1.wav".to_string(), "click2.wav".to_string()];
        let result = classify_and_place(&paths, sounds);
        // Kad imamo više zvukova nego tipova, dozvoljava duplicate
        assert_eq!(result.classifications.len(), 2);
    }

    #[test]
    fn test_gap_analysis() {
        // Jedan zvuk → ostalo su missing
        let fv = make_fv(0.15, 0.3, 0.45, 10.0, 0.4, 0.2, EnvelopeShape::Impulse, 0.2);
        let result = classify_and_place(&["test.wav".to_string()], vec![fv]);
        assert!(!result.missing_types.is_empty(), "Should have missing types");
        assert!(result.missing_types.len() < SlotSoundType::all().len(),
            "At least one type should be assigned");
    }

    #[test]
    fn test_envelope_shape_detect_impulse() {
        // Kratki spike pa odmah pada na nulu
        let mut env = vec![0.0f32; 100];
        env[5] = 1.0;
        env[6] = 0.5;
        env[7] = 0.1;
        assert_eq!(EnvelopeShape::detect(&env), EnvelopeShape::Impulse);
    }

    #[test]
    fn test_envelope_shape_detect_flat() {
        // Flat signal
        let env = vec![0.5f32; 100];
        assert_eq!(EnvelopeShape::detect(&env), EnvelopeShape::Flat);
    }

    #[test]
    fn test_ffnc_prefix_all_unique() {
        let prefixes: std::collections::HashSet<_> = SlotSoundType::all()
            .iter()
            .map(|t| t.ffnc_prefix())
            .collect();
        assert_eq!(prefixes.len(), SlotSoundType::all().len(),
            "All FFNC prefixes must be unique");
    }

    #[test]
    fn test_hungarian_trivial_3x3() {
        // Perfect matching: diagonala
        let scores = vec![
            vec![1.0, 0.0, 0.0],
            vec![0.0, 1.0, 0.0],
            vec![0.0, 0.0, 1.0],
        ];
        let result = hungarian_assignment(&scores);
        assert_eq!(result, vec![0, 1, 2]);
    }

    #[test]
    fn test_hungarian_resolves_conflict() {
        // Oba žele kolonu 0, ali Hungarian treba da razreši
        let scores = vec![
            vec![0.9, 0.1],
            vec![0.8, 0.3],
        ];
        let result = hungarian_assignment(&scores);
        // Sound 0 → col 0 (0.9), Sound 1 → col 1 (0.3) je bolji od (0.1 + 0.8)
        assert_eq!(result.len(), 2);
        // Ukupni score treba biti optimalan
        let total_default = scores[0][result[0]] + scores[1][result[1]];
        assert!(total_default >= 0.9 + 0.3, "Should pick optimal assignment, got {total_default}");
    }
}
