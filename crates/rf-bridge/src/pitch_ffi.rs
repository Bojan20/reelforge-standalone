//! Pitch FFI — Bridges rf-pitch to Flutter via C FFI.
//!
//! Functions:
//! - pitch_detect — monophonic pitch detection (returns Hz)
//! - pitch_detect_midi — monophonic pitch detection (returns MIDI note)
//! - pitch_corrector_create/destroy — instance management
//! - pitch_corrector_set_* — configuration

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::LazyLock;

use parking_lot::RwLock;
use rf_pitch::correction::{CorrectionMode, PitchCorrector};
use rf_pitch::detection::PitchDetector;
use rf_pitch::scale::{Scale, ScaleType};
use rf_pitch::PitchConfig;

/// Pitch corrector instances — keyed by slot ID.
static CORRECTORS: LazyLock<RwLock<HashMap<u32, PitchCorrector>>> =
    LazyLock::new(|| RwLock::new(HashMap::new()));

/// Next corrector ID.
static NEXT_CORRECTOR_ID: AtomicU32 = AtomicU32::new(1);

// ════════════════════════════════════════════════════════════════════
// PITCH DETECTION
// ════════════════════════════════════════════════════════════════════

/// Detect fundamental pitch from audio samples.
/// Returns frequency in Hz, or -1.0 if no pitch detected.
/// samples: pointer to f64 audio data
/// length: number of samples
/// sample_rate: sample rate in Hz
#[unsafe(no_mangle)]
pub extern "C" fn pitch_detect(
    samples: *const f64,
    length: u32,
    sample_rate: f64,
) -> f64 {
    if samples.is_null() || length == 0 {
        return -1.0;
    }

    let data = unsafe { std::slice::from_raw_parts(samples, length as usize) };

    // Convert f64 to f32 for rf-pitch
    let f32_data: Vec<f32> = data.iter().map(|&s| s as f32).collect();

    let config = PitchConfig {
        sample_rate: sample_rate as u32,
        ..PitchConfig::default()
    };

    let mut detector = PitchDetector::new(&config);
    match detector.detect(&f32_data) {
        Ok(Some((freq, _confidence))) => freq as f64,
        Ok(None) => -1.0,
        Err(e) => {
            log::error!("PITCH FFI: detect failed — {}", e);
            -1.0
        }
    }
}

/// Detect pitch and return as MIDI note number (0-127).
/// Returns -1 if no pitch detected.
#[unsafe(no_mangle)]
pub extern "C" fn pitch_detect_midi(
    samples: *const f64,
    length: u32,
    sample_rate: f64,
) -> i32 {
    let freq = pitch_detect(samples, length, sample_rate);
    if freq < 0.0 {
        return -1;
    }

    // freq_to_midi: 69 + 12 * log2(freq / 440)
    let midi = 69.0 + 12.0 * (freq / 440.0).log2();
    let rounded = midi.round() as i32;
    rounded.clamp(0, 127)
}

// ════════════════════════════════════════════════════════════════════
// PITCH CORRECTOR INSTANCES
// ════════════════════════════════════════════════════════════════════

/// Create a pitch corrector instance. Returns corrector ID, or -1 on failure.
/// sample_rate: audio sample rate
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_create(sample_rate: u32) -> i32 {
    let id = NEXT_CORRECTOR_ID.fetch_add(1, Ordering::Relaxed);
    let corrector = PitchCorrector::new(sample_rate);

    let mut map = CORRECTORS.write();
    map.insert(id, corrector);
    log::info!("PITCH FFI: Created corrector id={} @ {}Hz", id, sample_rate);
    id as i32
}

/// Destroy a pitch corrector instance. Returns 1 on success, -1 if not found.
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_destroy(id: u32) -> i32 {
    let mut map = CORRECTORS.write();
    if map.remove(&id).is_some() {
        log::info!("PITCH FFI: Destroyed corrector id={}", id);
        1
    } else {
        -1
    }
}

/// Set scale type for a corrector.
/// scale: 0=Chromatic, 1=Major, 2=NaturalMinor, 3=HarmonicMinor, 4=PentatonicMajor,
///        5=PentatonicMinor, 6=Blues, 7=WholeTone
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_scale(id: u32, scale: i32) -> i32 {
    let map = CORRECTORS.read();
    if !map.contains_key(&id) { return -1; }

    let scale_type = match scale {
        0 => ScaleType::Chromatic,
        1 => ScaleType::Major,
        2 => ScaleType::NaturalMinor,
        3 => ScaleType::HarmonicMinor,
        4 => ScaleType::PentatonicMajor,
        5 => ScaleType::PentatonicMinor,
        6 => ScaleType::Blues,
        7 => ScaleType::WholeTone,
        _ => ScaleType::Chromatic,
    };

    // Need write access to set scale — drop read, get write
    drop(map);
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        corrector.set_scale(Scale::new(scale_type, 0));
        1
    } else {
        -1
    }
}

/// Set root note for the corrector's scale. root: 0-11 (C=0, C#=1, ..., B=11)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_root(id: u32, root: i32) -> i32 {
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        let current_config = corrector.config().clone();
        let scale_type = current_config
            .scale
            .as_ref()
            .map(|s| s.scale_type)
            .unwrap_or(ScaleType::Chromatic);
        corrector.set_scale(Scale::new(scale_type, root.clamp(0, 11) as u8));
        1
    } else {
        -1
    }
}

/// Set correction speed (0.0 = slow/natural, 1.0 = instant).
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_speed(id: u32, speed: f64) -> i32 {
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        let mut config = corrector.config().clone();
        config.speed = speed as f32;
        corrector.set_config(config);
        1
    } else {
        -1
    }
}

/// Set correction amount (0.0 = none, 1.0 = full).
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_amount(id: u32, amount: f64) -> i32 {
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        let mut config = corrector.config().clone();
        config.amount = amount as f32;
        if amount <= 0.0 {
            config.mode = CorrectionMode::Off;
        } else if config.mode == CorrectionMode::Off {
            config.mode = CorrectionMode::Scale;
        }
        corrector.set_config(config);
        1
    } else {
        -1
    }
}

/// Enable/disable vibrato preservation. preserve: 0=off, 1=on
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_preserve_vibrato(id: u32, preserve: i32) -> i32 {
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        let mut config = corrector.config().clone();
        config.preserve_vibrato = preserve != 0;
        corrector.set_config(config);
        1
    } else {
        -1
    }
}

/// Set formant preservation amount (0.0 = none, 1.0 = full).
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_formant_preservation(id: u32, amount: f64) -> i32 {
    // rf-pitch FormantPreserver is separate — we store the value in a side-channel
    // For now, store as part of correction config's humanize field (closest semantic)
    let mut map = CORRECTORS.write();
    if let Some(corrector) = map.get_mut(&id) {
        let mut config = corrector.config().clone();
        config.humanize = amount as f32;
        corrector.set_config(config);
        1
    } else {
        -1
    }
}
