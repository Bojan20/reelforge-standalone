//! Telemetry stream FFI — unified real-time meter snapshot.
//!
//! The engine already exposes per-track peaks, master peak/RMS/LUFS,
//! advanced meters (true peak 8x, PSR, crest factor, psychoacoustic),
//! and spectrum data — but as 8+ separate `flutter_rust_bridge`
//! functions. The UI then has to poll each one at 60 Hz, build an
//! aggregated frame, and reason about freshness.
//!
//! This module wraps it into one C-extern call:
//!
//! - `telemetry_snapshot_json(track_ids_csv) -> *mut c_char`
//!   Single JSON snapshot of master + selected tracks + advanced
//!   meters + spectrum. Designed to be polled at 60 Hz from any
//!   client (Flutter, web, dashboard, headless).
//!
//! Plus the peak-hold layer the engine doesn't track:
//!
//! - `telemetry_set_peak_hold_ms(ms)` / `telemetry_set_peak_decay_db_per_sec(d)`
//!   Configure the hold/decay used in the per-track and master peak
//!   fields. Hold = how long after a peak before it starts decaying;
//!   decay = how fast it falls (dB/s). UI meters look professional
//!   only when these two move together.
//!
//! - `telemetry_reset_holds` — clear all peak-hold state.
//!
//! # Snapshot shape
//!
//! ```json
//! {
//!   "seq": 12345,                       // monotonic counter, increments per snapshot
//!   "timestamp_ms": 1735689600000,
//!   "master": {
//!     "peak_l": -3.2, "peak_r": -3.0,
//!     "peak_l_hold": -1.1, "peak_r_hold": -0.9,
//!     "rms_l": -18.4, "rms_r": -18.1,
//!     "lufs_m": -14.2, "lufs_s": -14.5, "lufs_i": -14.3,
//!     "true_peak": -0.8,
//!     "correlation": 0.92, "balance": 0.02,
//!     "dynamic_range": 12.4
//!   },
//!   "tracks": [
//!     { "id": 1, "peak_l": -6.1, "peak_r": -6.0,
//!       "peak_l_hold": -3.5, "peak_r_hold": -3.4,
//!       "rms_l": -22.1, "rms_r": -22.0,
//!       "correlation": 0.95, "lufs_m": -18.0, "lufs_s": -18.2, "lufs_i": -18.1 }
//!   ],
//!   "spectrum": [0.12, 0.08, ...],     // 256 bins, 20 Hz–20 kHz log-scaled, 0..1
//!   "cpu_usage": 18.5,                  // %
//!   "buffer_underruns": 0
//! }
//! ```
//!
//! All level fields are in dB (peak/RMS) or LUFS, never linear.
//! `track_ids_csv` filters which tracks appear; pass an empty string
//! to include none, or `"*"` to include all live tracks.

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;
use std::time::Instant;

use parking_lot::RwLock;
use serde::Serialize;

use crate::ENGINE;

// ─── Peak-hold + decay state ──────────────────────────────────────────────

/// Peak-hold tracker per channel — holds the last sustained peak for
/// `hold_ms`, then decays at `decay_db_per_sec`. The dB conversion is
/// done at write time to keep the read path branch-free.
#[derive(Debug, Clone, Copy)]
struct HoldChannel {
    /// Held value in dB.
    held_db: f32,
    /// When the current hold was set (Instant epoch).
    set_at: Instant,
}

impl Default for HoldChannel {
    fn default() -> Self {
        Self {
            held_db: -120.0,
            set_at: Instant::now(),
        }
    }
}

impl HoldChannel {
    /// Update the hold with a new peak value (in dB) and a wall clock
    /// reference. If the new value beats the current decayed value,
    /// the hold restarts.
    fn update(&mut self, new_db: f32, now: Instant, hold_ms: u64, decay_db_per_sec: f32) {
        let elapsed_ms = now.duration_since(self.set_at).as_millis() as u64;
        let current_decayed = if elapsed_ms <= hold_ms {
            self.held_db
        } else {
            let decay_secs = (elapsed_ms - hold_ms) as f32 * 0.001;
            (self.held_db - decay_db_per_sec * decay_secs).max(-120.0)
        };
        if new_db >= current_decayed {
            self.held_db = new_db;
            self.set_at = now;
        } else {
            self.held_db = current_decayed;
        }
    }

    fn current_db(&self) -> f32 {
        self.held_db
    }
}

#[derive(Debug, Default, Clone, Copy)]
struct StereoHold {
    l: HoldChannel,
    r: HoldChannel,
}

/// Holds peak-hold state for master + each tracked id.
struct HoldState {
    master: StereoHold,
    tracks: HashMap<u64, StereoHold>,
    hold_ms: u64,
    decay_db_per_sec: f32,
    seq: AtomicU64,
}

impl HoldState {
    fn new() -> Self {
        Self {
            master: StereoHold::default(),
            tracks: HashMap::new(),
            hold_ms: 1500,           // sane default for VU/PPM-style meters
            decay_db_per_sec: 20.0,  // dB/s
            seq: AtomicU64::new(0),
        }
    }
}

static HOLD_STATE: OnceLock<RwLock<HoldState>> = OnceLock::new();

fn hold_state() -> &'static RwLock<HoldState> {
    HOLD_STATE.get_or_init(|| RwLock::new(HoldState::new()))
}

// ─── Snapshot wire types ──────────────────────────────────────────────────

#[derive(Debug, Serialize)]
struct MasterMeters {
    peak_l: f32,
    peak_r: f32,
    peak_l_hold: f32,
    peak_r_hold: f32,
    rms_l: f32,
    rms_r: f32,
    lufs_m: f32,
    lufs_s: f32,
    lufs_i: f32,
    true_peak: f32,
    correlation: f32,
    balance: f32,
    dynamic_range: f32,
}

#[derive(Debug, Serialize)]
struct TrackMeterOut {
    id: u64,
    peak_l: f32,
    peak_r: f32,
    peak_l_hold: f32,
    peak_r_hold: f32,
    rms_l: f32,
    rms_r: f32,
    correlation: f32,
    lufs_m: f32,
    lufs_s: f32,
    lufs_i: f32,
}

#[derive(Debug, Serialize)]
struct Snapshot {
    seq: u64,
    timestamp_ms: u128,
    master: MasterMeters,
    tracks: Vec<TrackMeterOut>,
    spectrum: Vec<f32>,
    cpu_usage: f32,
    buffer_underruns: u32,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

// ─── Helpers ──────────────────────────────────────────────────────────────

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json)
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

fn error_response(msg: &str) -> *mut c_char {
    let resp = ErrorResponse { error: msg.into() };
    json_to_c(serde_json::to_string(&resp).unwrap_or_default())
}

/// Convert linear amplitude to dB. Floor at -120 dB so silence doesn't
/// produce -inf in JSON.
#[inline]
fn linear_to_db(x: f32) -> f32 {
    if x <= 1e-6 {
        -120.0
    } else {
        20.0 * x.log10()
    }
}

/// Parse `track_ids_csv` into a request.
///
/// - `""` → no tracks
/// - `"*"` → all tracks the engine knows about
/// - `"1,2,3"` → those track ids only
/// - bad input → error to caller
fn parse_track_ids(csv: &str) -> Result<TrackFilter, String> {
    let trimmed = csv.trim();
    if trimmed.is_empty() {
        return Ok(TrackFilter::None);
    }
    if trimmed == "*" {
        return Ok(TrackFilter::All);
    }
    let mut ids = Vec::new();
    for part in trimmed.split(',') {
        let p = part.trim();
        if p.is_empty() {
            continue;
        }
        let id: u64 = p
            .parse()
            .map_err(|_| format!("invalid track id '{}'", p))?;
        ids.push(id);
    }
    Ok(TrackFilter::Some(ids))
}

#[derive(Debug)]
enum TrackFilter {
    None,
    All,
    Some(Vec<u64>),
}

// ─── Snapshot builder ─────────────────────────────────────────────────────

fn build_snapshot(filter: TrackFilter) -> Result<Snapshot, String> {
    let engine_guard = ENGINE.read();
    let engine = engine_guard
        .as_ref()
        .ok_or_else(|| "ENGINE not initialised".to_string())?;
    let pb = engine.playback_engine();

    let mut state = hold_state().write();
    let now = Instant::now();
    let hold_ms = state.hold_ms;
    let decay = state.decay_db_per_sec;

    // ── Master ─────────────────────────────────────────────────────────
    let m = &engine.metering;
    let master_peak_l_db = linear_to_db(m.master_peak_l);
    let master_peak_r_db = linear_to_db(m.master_peak_r);
    state
        .master
        .l
        .update(master_peak_l_db, now, hold_ms, decay);
    state
        .master
        .r
        .update(master_peak_r_db, now, hold_ms, decay);
    let master = MasterMeters {
        peak_l: master_peak_l_db,
        peak_r: master_peak_r_db,
        peak_l_hold: state.master.l.current_db(),
        peak_r_hold: state.master.r.current_db(),
        rms_l: linear_to_db(m.master_rms_l),
        rms_r: linear_to_db(m.master_rms_r),
        lufs_m: m.master_lufs_m,
        lufs_s: m.master_lufs_s,
        lufs_i: m.master_lufs_i,
        true_peak: linear_to_db(m.master_true_peak),
        correlation: m.correlation,
        balance: m.stereo_balance,
        dynamic_range: m.dynamic_range,
    };

    // ── Tracks (filter-driven) ────────────────────────────────────────
    let mut tracks: Vec<TrackMeterOut> = Vec::new();
    let id_meter_pairs: Vec<(u64, rf_engine::TrackMeter)> = match filter {
        TrackFilter::None => Vec::new(),
        TrackFilter::All => pb
            .get_all_track_meters()
            .into_iter()
            .map(|(id, meter)| (id, meter))
            .collect(),
        TrackFilter::Some(ref ids) => pb.get_track_meters_for_ids(ids),
    };
    for (id, meter) in id_meter_pairs {
        let peak_l_db = linear_to_db(meter.peak_l as f32);
        let peak_r_db = linear_to_db(meter.peak_r as f32);
        let entry = state.tracks.entry(id).or_default();
        entry.l.update(peak_l_db, now, hold_ms, decay);
        entry.r.update(peak_r_db, now, hold_ms, decay);
        let hold_l = entry.l.current_db();
        let hold_r = entry.r.current_db();
        tracks.push(TrackMeterOut {
            id,
            peak_l: peak_l_db,
            peak_r: peak_r_db,
            peak_l_hold: hold_l,
            peak_r_hold: hold_r,
            rms_l: linear_to_db(meter.rms_l as f32),
            rms_r: linear_to_db(meter.rms_r as f32),
            correlation: meter.correlation as f32,
            lufs_m: meter.lufs_momentary as f32,
            lufs_s: meter.lufs_short as f32,
            lufs_i: meter.lufs_integrated as f32,
        });
    }

    // ── Spectrum (256 bins) ───────────────────────────────────────────
    let spectrum = pb.get_spectrum_data();

    let seq = state.seq.fetch_add(1, Ordering::Relaxed);

    Ok(Snapshot {
        seq,
        timestamp_ms: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0),
        master,
        tracks,
        spectrum,
        cpu_usage: m.cpu_usage,
        buffer_underruns: m.buffer_underruns,
    })
}

// ─── Public C FFI ─────────────────────────────────────────────────────────

/// Snapshot of all meters. Pass a CSV of track ids to include, or `"*"`
/// for every live track, or empty string for master+spectrum only.
///
/// Returns JSON. Caller must free via `telemetry_free_string`.
///
/// # Safety
/// `track_ids_csv` must be a NUL-terminated UTF-8 string.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_snapshot_json(track_ids_csv: *const c_char) -> *mut c_char {
    let csv = if track_ids_csv.is_null() {
        ""
    } else {
        match unsafe { CStr::from_ptr(track_ids_csv) }.to_str() {
            Ok(s) => s,
            Err(_) => return error_response("track_ids_csv not utf-8"),
        }
    };
    let filter = match parse_track_ids(csv) {
        Ok(f) => f,
        Err(e) => return error_response(&e),
    };
    match build_snapshot(filter) {
        Ok(snap) => match serde_json::to_string(&snap) {
            Ok(j) => json_to_c(j),
            Err(e) => error_response(&format!("serialize error: {}", e)),
        },
        Err(e) => error_response(&e),
    }
}

/// Set peak-hold time in milliseconds (default 1500 ms).
/// Clamped to `[0, 60000]`.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_set_peak_hold_ms(ms: u64) {
    let mut state = hold_state().write();
    state.hold_ms = ms.min(60_000);
}

/// Set peak decay rate in dB/sec (default 20 dB/s, professional VU).
/// Clamped to `[0.0, 200.0]`.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_set_peak_decay_db_per_sec(decay: f32) {
    let mut state = hold_state().write();
    state.decay_db_per_sec = decay.clamp(0.0, 200.0);
}

/// Reset all peak-hold values to silence (-120 dB). Useful when stopping
/// playback or starting a new session.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_reset_holds() {
    let mut state = hold_state().write();
    state.master = StereoHold::default();
    state.tracks.clear();
}

/// Get the current snapshot sequence counter without taking a full
/// snapshot. UI can poll this cheaply to know whether anything has
/// changed since the last full call.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_current_seq() -> u64 {
    hold_state().read().seq.load(Ordering::Relaxed)
}

/// Free a string allocated by this module's FFI functions.
///
/// # Safety
/// `ptr` must come from `telemetry_snapshot_json`.
#[unsafe(no_mangle)]
pub extern "C" fn telemetry_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn cstr_to_string(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null());
        let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
        telemetry_free_string(ptr);
        s
    }

    #[test]
    fn linear_to_db_silence_returns_floor() {
        assert!(linear_to_db(0.0) <= -119.0);
        assert!(linear_to_db(1e-9) <= -119.0);
    }

    #[test]
    fn linear_to_db_unity_is_zero() {
        let v = linear_to_db(1.0);
        assert!(v.abs() < 1e-3, "got {}", v);
    }

    #[test]
    fn linear_to_db_half_is_minus_six() {
        // 0.5 linear = ~ -6.02 dB
        let v = linear_to_db(0.5);
        assert!((v - (-6.0205)).abs() < 0.01, "got {}", v);
    }

    #[test]
    fn parse_track_ids_empty() {
        let f = parse_track_ids("").unwrap();
        assert!(matches!(f, TrackFilter::None));
    }

    #[test]
    fn parse_track_ids_all() {
        let f = parse_track_ids("*").unwrap();
        assert!(matches!(f, TrackFilter::All));
    }

    #[test]
    fn parse_track_ids_csv() {
        let f = parse_track_ids("1,2,5").unwrap();
        match f {
            TrackFilter::Some(v) => assert_eq!(v, vec![1, 2, 5]),
            _ => panic!("expected Some"),
        }
    }

    #[test]
    fn parse_track_ids_with_whitespace() {
        let f = parse_track_ids(" 1 , 2 , 5 ").unwrap();
        match f {
            TrackFilter::Some(v) => assert_eq!(v, vec![1, 2, 5]),
            _ => panic!("expected Some"),
        }
    }

    #[test]
    fn parse_track_ids_invalid_returns_error() {
        let r = parse_track_ids("1,abc,3");
        assert!(r.is_err());
    }

    #[test]
    fn parse_track_ids_skips_empty_segments() {
        // Trailing comma must not break it
        let f = parse_track_ids("1,2,").unwrap();
        match f {
            TrackFilter::Some(v) => assert_eq!(v, vec![1, 2]),
            _ => panic!("expected Some"),
        }
    }

    #[test]
    fn hold_channel_holds_then_decays() {
        let mut h = HoldChannel::default();
        let t0 = Instant::now();
        h.update(-3.0, t0, 100, 20.0);
        assert!((h.current_db() - (-3.0)).abs() < 1e-3);

        // During hold window, value stays
        let t_in_hold = t0 + std::time::Duration::from_millis(50);
        h.update(-30.0, t_in_hold, 100, 20.0);
        assert!((h.current_db() - (-3.0)).abs() < 1e-3);

        // After hold window, decays
        let t_after_hold = t0 + std::time::Duration::from_millis(600);
        h.update(-30.0, t_after_hold, 100, 20.0);
        // 0.5 s of decay at 20 dB/s = 10 dB drop
        let expected = -3.0 - 10.0;
        assert!(
            (h.current_db() - expected).abs() < 0.5,
            "got {}, expected ~{}",
            h.current_db(),
            expected
        );
    }

    #[test]
    fn hold_channel_resets_on_higher_peak() {
        let mut h = HoldChannel::default();
        let t0 = Instant::now();
        h.update(-10.0, t0, 100, 20.0);
        // Higher peak resets hold
        let t1 = t0 + std::time::Duration::from_millis(200);
        h.update(-2.0, t1, 100, 20.0);
        assert!((h.current_db() - (-2.0)).abs() < 1e-3);
    }

    #[test]
    fn hold_floor_at_minus_120() {
        let mut h = HoldChannel::default();
        let t0 = Instant::now();
        h.update(-30.0, t0, 0, 1000.0); // huge decay
        let t_far = t0 + std::time::Duration::from_secs(5);
        h.update(-100.0, t_far, 0, 1000.0);
        assert!(h.current_db() >= -120.0 - 1e-3);
    }

    #[test]
    fn snapshot_with_no_engine_returns_error() {
        let csv = CString::new("").unwrap();
        let raw = telemetry_snapshot_json(csv.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""), "got {}", out);
        assert!(out.contains("ENGINE"), "got {}", out);
    }

    #[test]
    fn snapshot_invalid_csv_returns_error() {
        let csv = CString::new("not,a,number").unwrap();
        let raw = telemetry_snapshot_json(csv.as_ptr());
        let out = cstr_to_string(raw);
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn snapshot_null_csv_treated_as_empty() {
        // Null pointer means "no track filter" — should not crash.
        let raw = telemetry_snapshot_json(std::ptr::null());
        let out = cstr_to_string(raw);
        // ENGINE not initialised in test — error, but no crash
        assert!(out.contains("\"error\""));
    }

    #[test]
    fn set_peak_hold_clamps() {
        telemetry_set_peak_hold_ms(999_999);
        let hold_ms = hold_state().read().hold_ms;
        assert!(hold_ms <= 60_000);
    }

    #[test]
    fn set_decay_clamps() {
        telemetry_set_peak_decay_db_per_sec(9999.0);
        let v = hold_state().read().decay_db_per_sec;
        assert!(v <= 200.0);

        telemetry_set_peak_decay_db_per_sec(-50.0);
        let v = hold_state().read().decay_db_per_sec;
        assert!(v >= 0.0);
    }

    #[test]
    fn reset_holds_clears_state() {
        // Seed master with a peak
        {
            let mut s = hold_state().write();
            s.master.l.held_db = -3.0;
            s.master.r.held_db = -3.0;
            s.tracks.insert(42, StereoHold {
                l: HoldChannel { held_db: -1.0, set_at: Instant::now() },
                r: HoldChannel { held_db: -1.0, set_at: Instant::now() },
            });
        }
        telemetry_reset_holds();
        let (master_l, tracks_empty) = {
            let s = hold_state().read();
            (s.master.l.held_db, s.tracks.is_empty())
        };
        assert!(master_l <= -119.0);
        assert!(tracks_empty);
    }

    #[test]
    fn current_seq_is_monotonic() {
        // Each snapshot bumps seq by 1, but in test environment
        // (no engine), build_snapshot fails before incrementing.
        // We test the read path here.
        let a = telemetry_current_seq();
        // No-op; should equal itself if engine not initialised
        let b = telemetry_current_seq();
        assert_eq!(a, b);
    }

    #[test]
    fn free_string_is_null_safe() {
        telemetry_free_string(std::ptr::null_mut());
    }
}
