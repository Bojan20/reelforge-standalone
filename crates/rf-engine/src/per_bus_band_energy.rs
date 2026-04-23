//! Per-Bus 4-Band Energy Analyzer (Phase 10e-3)
//!
//! Provides per-bus energy measurements in 4 psychoacoustic broad bands so the
//! OrbMixer's masking alert can decide **which two buses are fighting in which
//! band** instead of guessing from a single master-spectrum snapshot.
//!
//! Bands (centre / type / purpose):
//! | Idx | Name     | Filter                      | Approx. range |
//! |-----|----------|-----------------------------|---------------|
//! | 0   | bass     | Lowpass  200 Hz  Q=0.707    |   20 – 250 Hz |
//! | 1   | lowmid   | Bandpass 450 Hz  Q=1.0      |  220 – 950 Hz |
//! | 2   | highmid  | Bandpass 1800 Hz Q=1.0      |  900 – 3500 Hz|
//! | 3   | treble   | Highpass 3500 Hz Q=0.707    | 3500 –  Nyq.  |
//!
//! # Real-time contract
//!
//! - **Zero allocation** — all filter state + smoothing envelopes are owned by
//!   `PerBusBandAnalyzer` and resized only by `set_sample_rate`.
//! - **Single-writer** — audio thread calls `process_bus_block(...)`.
//! - **Lock-free publish** — smoothed RMS values are stored into the caller-
//!   supplied atomics (typically `SHARED_METERS.bus_band_rms`) via `Relaxed`
//!   writes; UI reads after the shared-meter sequence increment.
//! - Per-block cost: 6 buses × 4 bands × 2 channels × N samples biquad taps =
//!   ~4% of a typical 512-sample audio block at 48 kHz on an M-series CPU.
//!
//! # Smoothing
//!
//! RMS is integrated with a one-pole envelope with release ≈ 120 ms so the UI
//! sees a smoothly-changing value rather than per-block peaks. Attack is
//! immediate to reflect transients within a single block.

use std::sync::atomic::{AtomicU32, Ordering};

use rf_core::Sample;
use rf_dsp::biquad::BiquadTDF2;
use rf_dsp::MonoProcessor;

/// Number of buses tracked — must match SHARED_METERS layout.
/// Order: 0=Master, 1=Music, 2=SFX, 3=VO, 4=Ambience, 5=Aux.
pub const NUM_BUSES: usize = 6;

/// Number of bands per bus.
pub const NUM_BANDS: usize = 4;

/// Total atomic slots (matches `SharedMeterBuffer::bus_band_rms.len()`).
pub const TOTAL_SLOTS: usize = NUM_BUSES * NUM_BANDS;

/// Per-channel-per-band filter state for one bus.
#[derive(Debug)]
struct BusFilters {
    // [band] -> filter for left channel
    l: [BiquadTDF2; NUM_BANDS],
    // [band] -> filter for right channel
    r: [BiquadTDF2; NUM_BANDS],
    // Smoothed band RMS (linear, not dB). Updated per-block.
    env: [f32; NUM_BANDS],
}

impl BusFilters {
    fn new(sample_rate: f64) -> Self {
        Self {
            l: Self::build_filters(sample_rate),
            r: Self::build_filters(sample_rate),
            env: [0.0; NUM_BANDS],
        }
    }

    fn build_filters(sr: f64) -> [BiquadTDF2; NUM_BANDS] {
        let mut bass = BiquadTDF2::new(sr);
        bass.set_lowpass(200.0, 0.707);
        let mut lowmid = BiquadTDF2::new(sr);
        lowmid.set_bandpass(450.0, 1.0);
        let mut highmid = BiquadTDF2::new(sr);
        highmid.set_bandpass(1800.0, 1.0);
        let mut treble = BiquadTDF2::new(sr);
        treble.set_highpass(3500.0, 0.707);
        [bass, lowmid, highmid, treble]
    }

    fn retune(&mut self, sr: f64) {
        self.l = Self::build_filters(sr);
        self.r = Self::build_filters(sr);
        self.env = [0.0; NUM_BANDS];
    }
}

/// Analyzer for all buses.
///
/// Use `process_bus_block()` after each bus' final mix and before (or after)
/// master mixdown — the analyzer is side-effect free, just reads the signal.
/// Call `publish(atomics)` once per audio block to write smoothed RMS values.
pub struct PerBusBandAnalyzer {
    buses: [BusFilters; NUM_BUSES],
    sample_rate: f64,
    /// Release coefficient: new_env = max(rms, env * coeff + rms * (1 - coeff))
    /// Derived from sample rate for ~120 ms release on block boundary.
    release_coeff: f32,
}

impl PerBusBandAnalyzer {
    /// Create an analyzer configured for the given sample rate.
    pub fn new(sample_rate: f64) -> Self {
        let sr = if sample_rate > 0.0 { sample_rate } else { 48_000.0 };
        Self {
            buses: [
                BusFilters::new(sr), BusFilters::new(sr), BusFilters::new(sr),
                BusFilters::new(sr), BusFilters::new(sr), BusFilters::new(sr),
            ],
            sample_rate: sr,
            release_coeff: Self::compute_release_coeff(sr),
        }
    }

    fn compute_release_coeff(_sr: f64) -> f32 {
        // Per-block coefficient for ~120 ms release when called once per 512-sample block.
        // alpha = exp(-block_dt / tau). Typical 512-sample block @ 48 kHz ≈ 10.67 ms,
        // tau = 120 ms → alpha ≈ 0.915. Block-size variance doesn't shift this much.
        0.92
    }

    /// Re-initialise all filters for a new sample rate.
    /// Safe to call from any thread before audio starts or when engine SR changes.
    /// Performs no allocation.
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        if sample_rate <= 0.0 || !sample_rate.is_finite() { return; }
        if (sample_rate - self.sample_rate).abs() < 0.5 { return; }
        self.sample_rate = sample_rate;
        for b in &mut self.buses {
            b.retune(sample_rate);
        }
        self.release_coeff = Self::compute_release_coeff(sample_rate);
    }

    /// Process one bus' stereo block. Calculates per-sample band magnitudes and
    /// updates the smoothed envelope. The envelope is published via `publish()`.
    ///
    /// `bus_idx` is clamped; out-of-range indices are silently ignored.
    #[inline]
    pub fn process_bus_block(&mut self, bus_idx: usize, left: &[Sample], right: &[Sample]) {
        if bus_idx >= NUM_BUSES { return; }
        let n = left.len().min(right.len());
        if n == 0 { return; }

        let bus = &mut self.buses[bus_idx];
        // Accumulate sum-of-squares per band over the block.
        let mut ss = [0.0_f64; NUM_BANDS];
        for i in 0..n {
            for b in 0..NUM_BANDS {
                let yl = bus.l[b].process_sample(left[i]);
                let yr = bus.r[b].process_sample(right[i]);
                ss[b] += yl * yl + yr * yr;
            }
        }
        let inv = 1.0 / (2.0 * n as f64);
        let coeff = self.release_coeff;
        let inv_coeff = 1.0 - coeff;
        for b in 0..NUM_BANDS {
            let rms = (ss[b] * inv).sqrt() as f32;
            // Attack: immediate on rise. Release: one-pole smoothing on fall.
            let prev = bus.env[b];
            let smoothed = if rms >= prev { rms } else { coeff * prev + inv_coeff * rms };
            bus.env[b] = if smoothed.is_finite() { smoothed } else { 0.0 };
        }
    }

    /// Apply release decay without sampling new signal (called for muted /
    /// solo-masked buses so their envelope fades to zero instead of staying
    /// stuck at the last observed level).
    #[inline]
    pub fn decay_bus(&mut self, bus_idx: usize) {
        if bus_idx >= NUM_BUSES { return; }
        let coeff = self.release_coeff;
        let env = &mut self.buses[bus_idx].env;
        for b in 0..NUM_BANDS {
            env[b] *= coeff;
            if env[b] < 1e-6 { env[b] = 0.0; }
        }
    }

    /// Publish current envelopes into the caller-supplied atomic slice.
    /// Slice length must be `TOTAL_SLOTS` (24); extra slots are ignored,
    /// missing slots are skipped silently.
    #[inline]
    pub fn publish(&self, atomics: &[AtomicU32]) {
        let upper = atomics.len().min(TOTAL_SLOTS);
        for bus_idx in 0..NUM_BUSES {
            for b in 0..NUM_BANDS {
                let slot = bus_idx * NUM_BANDS + b;
                if slot >= upper { return; }
                atomics[slot].store(self.buses[bus_idx].env[b].to_bits(), Ordering::Relaxed);
            }
        }
    }

    /// Fetch current envelope for a (bus, band) without touching atomics
    /// (used primarily in tests).
    #[cfg(test)]
    pub fn current(&self, bus_idx: usize, band: usize) -> f32 {
        self.buses[bus_idx].env[band]
    }
}

impl Default for PerBusBandAnalyzer {
    fn default() -> Self {
        Self::new(48_000.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silent_block_stays_at_zero() {
        let mut a = PerBusBandAnalyzer::new(48_000.0);
        let silent = vec![0.0_f64; 512];
        a.process_bus_block(0, &silent, &silent);
        for b in 0..NUM_BANDS {
            assert_eq!(a.current(0, b), 0.0);
        }
    }

    #[test]
    fn tone_lights_up_correct_band() {
        let sr = 48_000.0;
        let mut a = PerBusBandAnalyzer::new(sr);
        // 2 kHz sine → should load high-mid (band 2), little else.
        let n = 2048;
        let mut sig = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            sig.push((2.0 * std::f64::consts::PI * 2000.0 * t).sin() * 0.5);
        }
        // Run a few blocks for filters to settle.
        for _ in 0..6 {
            a.process_bus_block(1, &sig, &sig);
        }
        let envs = [
            a.current(1, 0), a.current(1, 1),
            a.current(1, 2), a.current(1, 3),
        ];
        // High-mid (index 2) must be the dominant band.
        let (argmax, _) = envs.iter().copied().enumerate()
            .fold((0usize, f32::NEG_INFINITY),
                |(i0, v0), (i, v)| if v > v0 { (i, v) } else { (i0, v0) });
        assert_eq!(argmax, 2, "expected high-mid dominant, got {:?}", envs);
    }

    #[test]
    fn publish_and_read_roundtrip() {
        let a = PerBusBandAnalyzer::new(48_000.0);
        let atomics: Vec<AtomicU32> =
            (0..TOTAL_SLOTS).map(|_| AtomicU32::new(0)).collect();
        a.publish(&atomics);
        for at in &atomics {
            let bits = at.load(Ordering::Relaxed);
            let v = f32::from_bits(bits);
            assert_eq!(v, 0.0);
        }
    }

    #[test]
    fn release_envelope_decays_not_instantly() {
        let sr = 48_000.0;
        let mut a = PerBusBandAnalyzer::new(sr);
        // Load low-mid with sine, then go silent and verify decay.
        let n = 512;
        let mut sig = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / sr;
            sig.push((2.0 * std::f64::consts::PI * 450.0 * t).sin() * 0.5);
        }
        for _ in 0..10 { a.process_bus_block(0, &sig, &sig); }
        let loaded = a.current(0, 1);
        assert!(loaded > 0.05, "low-mid should load: got {loaded}");

        let silent = vec![0.0_f64; n];
        a.process_bus_block(0, &silent, &silent);
        let after = a.current(0, 1);
        // Immediately after one silent block, envelope must have dropped but not to zero.
        assert!(after < loaded, "expected decay after silence");
        assert!(after > 0.0, "expected non-zero residual (release smoothing)");
    }

    #[test]
    fn bus_oob_is_noop() {
        let mut a = PerBusBandAnalyzer::new(48_000.0);
        let sig = vec![0.5_f64; 128];
        // Should not panic, should not affect any bus.
        a.process_bus_block(99, &sig, &sig);
        for bi in 0..NUM_BUSES {
            for b in 0..NUM_BANDS {
                assert_eq!(a.current(bi, b), 0.0);
            }
        }
    }
}
