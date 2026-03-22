//! Destructive clip audio operations
//!
//! These modify actual audio sample data in-place (destructive editing).
//! Non-destructive parameters (Clip.gain, Clip.fade_in/out) remain separate.
//!
//! All operations:
//! 1. Get mutable access to ImportedAudio via Arc::make_mut (CoW)
//! 2. Process samples in-place
//! 3. Invalidate waveform cache
//! 4. Return success/failure

use std::sync::Arc;
use crate::track_manager::ClipId;
use crate::ffi::{IMPORTED_AUDIO, TRACK_MANAGER, WAVEFORM_CACHE};

/// Fade curve types
#[derive(Debug, Clone, Copy)]
pub enum FadeCurve {
    /// Linear ramp
    Linear,
    /// Equal power (sine curve) — default for crossfades
    EqualPower,
    /// S-curve (smooth start and end)
    SCurve,
    /// Logarithmic (fast attack)
    Logarithmic,
    /// Exponential (slow attack)
    Exponential,
}

impl FadeCurve {
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => Self::Linear,
            1 => Self::EqualPower,
            2 => Self::SCurve,
            3 => Self::Logarithmic,
            4 => Self::Exponential,
            _ => Self::Linear,
        }
    }

    /// Calculate gain at position t (0.0 = start, 1.0 = end)
    /// For fade-in: t goes 0→1 (silence→full)
    /// For fade-out: caller should use 1.0 - t
    pub fn gain_at(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        match self {
            Self::Linear => t,
            Self::EqualPower => (t * std::f32::consts::FRAC_PI_2).sin(),
            Self::SCurve => {
                // Hermite S-curve: 3t² - 2t³
                t * t * (3.0 - 2.0 * t)
            }
            Self::Logarithmic => {
                // Fast attack: log-like curve, continuous at t=0
                // Formula: (ln(1 + k*t) / ln(1 + k)) where k controls curvature
                let k: f32 = 50.0;
                ((1.0 + k * t).ln() / (1.0 + k).ln()).clamp(0.0, 1.0)
            }
            Self::Exponential => {
                // Slow attack: (e^(k*t) - 1) / (e^k - 1) — true exponential
                let k: f32 = 4.0;
                ((k * t).exp() - 1.0) / (k.exp() - 1.0)
            }
        }
    }
}

/// Invalidate waveform cache for a clip's source file
fn invalidate_waveform(clip_id: u64) {
    if let Some(clip) = TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        WAVEFORM_CACHE.cache.write().remove(&clip.source_file);
    }
    // Also remove by clip ID key pattern
    let key = format!("clip_{}", clip_id);
    WAVEFORM_CACHE.cache.write().remove(&key);
}

// ═══════════════════════════════════════════════════════════════════════════
// NORMALIZE (destructive)
// ═══════════════════════════════════════════════════════════════════════════

/// Normalize clip audio samples to target peak dB.
/// Modifies actual sample data — irreversible without undo.
pub fn normalize_destructive(clip_id: u64, target_db: f64) -> bool {
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("clip_normalize_destructive: clip {} not found", clip_id);
            return false;
        }
    };

    let mut map = IMPORTED_AUDIO.write();
    let audio_arc = match map.get_mut(&ClipId(clip_id)) {
        Some(a) => a,
        None => {
            log::error!("clip_normalize_destructive: no audio for clip {}", clip_id);
            return false;
        }
    };

    let audio = Arc::make_mut(audio_arc);
    let channels = audio.channels as usize;
    if channels == 0 {
        log::error!("clip_normalize_destructive: clip {} has 0 channels", clip_id);
        return false;
    }
    let sample_rate = audio.sample_rate as f64;

    // Calculate sample range from clip region
    let start_frame = (clip.source_offset.max(0.0) * sample_rate) as usize;
    let end_frame = ((clip.source_offset + clip.source_duration) * sample_rate) as usize;
    let end_frame = end_frame.min(audio.sample_count);

    // Find true peak (sample-accurate)
    let mut peak: f32 = 0.0;
    for frame in start_frame..end_frame {
        for ch in 0..channels {
            let idx = frame * channels + ch;
            if idx < audio.samples.len() {
                let abs = audio.samples[idx].abs();
                if abs > peak {
                    peak = abs;
                }
            }
        }
    }

    if peak < 1e-7 {
        log::warn!("clip_normalize_destructive: clip {} is silent, skipping", clip_id);
        return true; // Success but nothing to do
    }

    // Calculate and apply gain
    let target_linear = 10.0_f64.powf(target_db / 20.0) as f32;
    let gain = target_linear / peak;

    // Apply to ALL samples in the clip region (not just display range)
    for frame in start_frame..end_frame {
        for ch in 0..channels {
            let idx = frame * channels + ch;
            if idx < audio.samples.len() {
                audio.samples[idx] *= gain;
            }
        }
    }

    // Update duration_secs if needed (shouldn't change for normalize)
    drop(map);

    invalidate_waveform(clip_id);

    log::info!(
        "clip_normalize_destructive: clip {} peak={:.2}dB → target={:.1}dB, gain={:.4}x",
        clip_id,
        20.0 * (peak as f64).log10(),
        target_db,
        gain
    );
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERSE (destructive)
// ═══════════════════════════════════════════════════════════════════════════

/// Reverse clip audio samples in-place.
/// Swaps frames from start↔end preserving channel interleaving.
pub fn reverse_destructive(clip_id: u64) -> bool {
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("clip_reverse_destructive: clip {} not found", clip_id);
            return false;
        }
    };

    let mut map = IMPORTED_AUDIO.write();
    let audio_arc = match map.get_mut(&ClipId(clip_id)) {
        Some(a) => a,
        None => {
            log::error!("clip_reverse_destructive: no audio for clip {}", clip_id);
            return false;
        }
    };

    let audio = Arc::make_mut(audio_arc);
    let channels = audio.channels as usize;
    if channels == 0 {
        log::error!("clip_reverse_destructive: clip {} has 0 channels", clip_id);
        return false;
    }
    let sample_rate = audio.sample_rate as f64;

    let start_frame = (clip.source_offset.max(0.0) * sample_rate) as usize;
    let end_frame = ((clip.source_offset + clip.source_duration) * sample_rate) as usize;
    let end_frame = end_frame.min(audio.sample_count);

    if end_frame <= start_frame + 1 {
        return true; // Nothing to reverse
    }

    // Reverse frames in-place (swap frame i with frame (end-1-i))
    let num_frames = end_frame - start_frame;
    for i in 0..num_frames / 2 {
        let frame_a = start_frame + i;
        let frame_b = end_frame - 1 - i;
        for ch in 0..channels {
            let idx_a = frame_a * channels + ch;
            let idx_b = frame_b * channels + ch;
            if idx_a < audio.samples.len() && idx_b < audio.samples.len() {
                audio.samples.swap(idx_a, idx_b);
            }
        }
    }

    drop(map);

    // Toggle reversed flag on clip metadata
    TRACK_MANAGER.update_clip(ClipId(clip_id), |c| {
        c.reversed = !c.reversed;
    });

    invalidate_waveform(clip_id);

    log::info!(
        "clip_reverse_destructive: clip {} reversed ({} frames, {} channels)",
        clip_id, num_frames, channels
    );
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// FADE IN (destructive)
// ═══════════════════════════════════════════════════════════════════════════

/// Apply fade-in to clip audio samples (destructive).
/// Multiplies samples at the start of the clip by the fade curve.
pub fn fade_in_destructive(clip_id: u64, duration_sec: f64, curve_type: u8) -> bool {
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("clip_fade_in_destructive: clip {} not found", clip_id);
            return false;
        }
    };

    let mut map = IMPORTED_AUDIO.write();
    let audio_arc = match map.get_mut(&ClipId(clip_id)) {
        Some(a) => a,
        None => {
            log::error!("clip_fade_in_destructive: no audio for clip {}", clip_id);
            return false;
        }
    };

    let audio = Arc::make_mut(audio_arc);
    let channels = audio.channels as usize;
    if channels == 0 {
        log::error!("clip_fade_in_destructive: clip {} has 0 channels", clip_id);
        return false;
    }
    let sample_rate = audio.sample_rate as f64;
    let curve = FadeCurve::from_u8(curve_type);

    let start_frame = (clip.source_offset.max(0.0) * sample_rate) as usize;
    let fade_frames = (duration_sec * sample_rate) as usize;
    let end_frame = ((clip.source_offset + clip.source_duration) * sample_rate) as usize;
    let end_frame = end_frame.min(audio.sample_count);
    let fade_end = (start_frame + fade_frames).min(end_frame);

    for frame in start_frame..fade_end {
        let t = (frame - start_frame) as f32 / fade_frames.max(1) as f32;
        let gain = curve.gain_at(t);
        for ch in 0..channels {
            let idx = frame * channels + ch;
            if idx < audio.samples.len() {
                audio.samples[idx] *= gain;
            }
        }
    }

    drop(map);

    // Clear non-destructive fade metadata — fade is now baked into samples
    // Setting to 0 prevents playback engine from applying fade a second time
    TRACK_MANAGER.update_clip(ClipId(clip_id), |c| {
        c.fade_in = 0.0;
    });

    invalidate_waveform(clip_id);

    log::info!(
        "clip_fade_in_destructive: clip {} fade={:.3}s curve={:?} (baked, metadata cleared)",
        clip_id, duration_sec, curve
    );
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// FADE OUT (destructive)
// ═══════════════════════════════════════════════════════════════════════════

/// Apply fade-out to clip audio samples (destructive).
/// Multiplies samples at the end of the clip by the inverse fade curve.
pub fn fade_out_destructive(clip_id: u64, duration_sec: f64, curve_type: u8) -> bool {
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("clip_fade_out_destructive: clip {} not found", clip_id);
            return false;
        }
    };

    let mut map = IMPORTED_AUDIO.write();
    let audio_arc = match map.get_mut(&ClipId(clip_id)) {
        Some(a) => a,
        None => {
            log::error!("clip_fade_out_destructive: no audio for clip {}", clip_id);
            return false;
        }
    };

    let audio = Arc::make_mut(audio_arc);
    let channels = audio.channels as usize;
    if channels == 0 {
        log::error!("clip_fade_out_destructive: clip {} has 0 channels", clip_id);
        return false;
    }
    let sample_rate = audio.sample_rate as f64;
    let curve = FadeCurve::from_u8(curve_type);

    let start_frame = (clip.source_offset.max(0.0) * sample_rate) as usize;
    let end_frame = ((clip.source_offset + clip.source_duration) * sample_rate) as usize;
    let end_frame = end_frame.min(audio.sample_count);
    let fade_frames = (duration_sec * sample_rate) as usize;
    // Clamp fade_start to clip start — never fade before clip region
    let fade_start = end_frame.saturating_sub(fade_frames).max(start_frame);

    for frame in fade_start..end_frame {
        // t goes from 1.0 (full volume) to 0.0 (silence)
        let t = (end_frame - frame) as f32 / fade_frames.max(1) as f32;
        let gain = curve.gain_at(t);
        for ch in 0..channels {
            let idx = frame * channels + ch;
            if idx < audio.samples.len() {
                audio.samples[idx] *= gain;
            }
        }
    }

    drop(map);

    // Clear non-destructive fade metadata — fade is now baked into samples
    TRACK_MANAGER.update_clip(ClipId(clip_id), |c| {
        c.fade_out = 0.0;
    });

    invalidate_waveform(clip_id);

    log::info!(
        "clip_fade_out_destructive: clip {} fade={:.3}s curve={:?} (baked, metadata cleared)",
        clip_id, duration_sec, curve
    );
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// APPLY GAIN (destructive)
// ═══════════════════════════════════════════════════════════════════════════

/// Apply gain to clip audio samples (destructive — bakes into samples).
/// After this, the samples are permanently scaled.
pub fn apply_gain_destructive(clip_id: u64, gain_db: f64) -> bool {
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("clip_apply_gain_destructive: clip {} not found", clip_id);
            return false;
        }
    };

    let mut map = IMPORTED_AUDIO.write();
    let audio_arc = match map.get_mut(&ClipId(clip_id)) {
        Some(a) => a,
        None => {
            log::error!("clip_apply_gain_destructive: no audio for clip {}", clip_id);
            return false;
        }
    };

    let audio = Arc::make_mut(audio_arc);
    let channels = audio.channels as usize;
    if channels == 0 {
        log::error!("clip_apply_gain_destructive: clip {} has 0 channels", clip_id);
        return false;
    }
    let sample_rate = audio.sample_rate as f64;
    let gain = 10.0_f64.powf(gain_db / 20.0) as f32;

    let start_frame = (clip.source_offset.max(0.0) * sample_rate) as usize;
    let end_frame = ((clip.source_offset + clip.source_duration) * sample_rate) as usize;
    let end_frame = end_frame.min(audio.sample_count);

    // Apply gain with tanh soft clipping (continuous, no discontinuity)
    for frame in start_frame..end_frame {
        for ch in 0..channels {
            let idx = frame * channels + ch;
            if idx < audio.samples.len() {
                let scaled = audio.samples[idx] * gain;
                // tanh soft clip: linear below threshold, smooth saturation above
                // tanh(x) ≈ x for small x, approaches ±1 for large x
                audio.samples[idx] = scaled.tanh();
            }
        }
    }

    drop(map);

    invalidate_waveform(clip_id);

    log::info!(
        "clip_apply_gain_destructive: clip {} gain={:.2}dB ({:.4}x)",
        clip_id, gain_db, gain
    );
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fade_curve_linear() {
        let curve = FadeCurve::Linear;
        assert_eq!(curve.gain_at(0.0), 0.0);
        assert_eq!(curve.gain_at(0.5), 0.5);
        assert_eq!(curve.gain_at(1.0), 1.0);
    }

    #[test]
    fn test_fade_curve_equal_power() {
        let curve = FadeCurve::EqualPower;
        assert!(curve.gain_at(0.0).abs() < 1e-6);
        assert!((curve.gain_at(1.0) - 1.0).abs() < 1e-6);
        // At 0.5: sin(π/4) ≈ 0.707
        assert!((curve.gain_at(0.5) - 0.707).abs() < 0.01);
    }

    #[test]
    fn test_fade_curve_scurve() {
        let curve = FadeCurve::SCurve;
        assert_eq!(curve.gain_at(0.0), 0.0);
        assert_eq!(curve.gain_at(1.0), 1.0);
        assert_eq!(curve.gain_at(0.5), 0.5); // S-curve passes through midpoint
    }

    #[test]
    fn test_fade_curve_clamp() {
        let curve = FadeCurve::Linear;
        assert_eq!(curve.gain_at(-0.5), 0.0);
        assert_eq!(curve.gain_at(1.5), 1.0);
    }

    #[test]
    fn test_fade_curve_from_u8() {
        assert!(matches!(FadeCurve::from_u8(0), FadeCurve::Linear));
        assert!(matches!(FadeCurve::from_u8(1), FadeCurve::EqualPower));
        assert!(matches!(FadeCurve::from_u8(2), FadeCurve::SCurve));
        assert!(matches!(FadeCurve::from_u8(3), FadeCurve::Logarithmic));
        assert!(matches!(FadeCurve::from_u8(4), FadeCurve::Exponential));
        assert!(matches!(FadeCurve::from_u8(255), FadeCurve::Linear)); // fallback
    }

    #[test]
    fn test_fade_curve_logarithmic() {
        let curve = FadeCurve::Logarithmic;
        // Boundaries: 0 at start, 1 at end
        assert!(curve.gain_at(0.0).abs() < 1e-6);
        assert!((curve.gain_at(1.0) - 1.0).abs() < 1e-3);
        // Monotonically increasing
        let mut prev = 0.0;
        for i in 1..=100 {
            let t = i as f32 / 100.0;
            let g = curve.gain_at(t);
            assert!(g >= prev, "Log curve not monotonic at t={}: {} < {}", t, g, prev);
            prev = g;
        }
        // Fast attack: at t=0.1, should already be > 0.3
        assert!(curve.gain_at(0.1) > 0.3, "Log curve should have fast attack");
    }

    #[test]
    fn test_fade_curve_exponential() {
        let curve = FadeCurve::Exponential;
        // Boundaries
        assert!(curve.gain_at(0.0).abs() < 1e-6);
        assert!((curve.gain_at(1.0) - 1.0).abs() < 1e-3);
        // Slow attack: at t=0.5, should be < 0.3
        assert!(curve.gain_at(0.5) < 0.3, "Exp curve should have slow attack");
        // Monotonically increasing
        let mut prev = 0.0;
        for i in 1..=100 {
            let t = i as f32 / 100.0;
            let g = curve.gain_at(t);
            assert!(g >= prev, "Exp curve not monotonic at t={}: {} < {}", t, g, prev);
            prev = g;
        }
    }

    #[test]
    fn test_tanh_soft_clip_continuity() {
        // tanh(1.0) ≈ 0.7616 — no discontinuity
        let at_one: f32 = 1.0_f32.tanh();
        assert!((at_one - 0.7616).abs() < 0.001);
        // tanh(0.5) ≈ 0.4621 — linear region
        let at_half: f32 = 0.5_f32.tanh();
        assert!((at_half - 0.4621).abs() < 0.001);
        // tanh(3.0) ≈ 0.9951 — saturation
        let at_three: f32 = 3.0_f32.tanh();
        assert!(at_three > 0.99);
        // Symmetric
        assert!(((-1.0_f32).tanh() + at_one).abs() < 1e-6);
    }

    #[test]
    fn test_all_curves_zero_to_one() {
        // Every curve must be 0 at t=0 and 1 at t=1
        for curve_type in 0..=4u8 {
            let curve = FadeCurve::from_u8(curve_type);
            let at_zero = curve.gain_at(0.0);
            let at_one = curve.gain_at(1.0);
            assert!(
                at_zero.abs() < 0.01,
                "Curve {:?} at t=0: {} (expected ~0)", curve, at_zero
            );
            assert!(
                (at_one - 1.0).abs() < 0.01,
                "Curve {:?} at t=1: {} (expected ~1)", curve, at_one
            );
        }
    }
}
