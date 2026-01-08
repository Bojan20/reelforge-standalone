//! FFI Bridge for Flutter/Dart Integration
//!
//! C-compatible FFI functions for:
//! - Track management (create, delete, reorder)
//! - Clip operations (add, move, resize, split, delete)
//! - Waveform peak data retrieval
//! - Audio file import
//! - Loop region control
//! - Crossfade management
//! - Marker management

use parking_lot::RwLock;
use std::ffi::{CStr, CString, c_char};
use std::path::Path;
use std::ptr;
use std::sync::Arc;

use crate::audio_import::{AudioImporter, ImportedAudio};
use crate::playback::PlaybackEngine;
use crate::track_manager::{
    Clip, ClipId, CrossfadeCurve, CrossfadeId, MarkerId, OutputBus, TrackId, TrackManager,
};
use crate::waveform::{NUM_LOD_LEVELS, SAMPLES_PER_PEAK, StereoWaveformPeaks, WaveformCache};
use rf_state::UndoManager;

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref TRACK_MANAGER: Arc<TrackManager> = Arc::new(TrackManager::new());
    static ref WAVEFORM_CACHE: WaveformCache = WaveformCache::new();
    static ref IMPORTED_AUDIO: RwLock<std::collections::HashMap<ClipId, Arc<ImportedAudio>>> =
        RwLock::new(std::collections::HashMap::new());
    static ref PLAYBACK_ENGINE: PlaybackEngine = PlaybackEngine::new(Arc::clone(&TRACK_MANAGER), 48000);
    static ref UNDO_MANAGER: RwLock<UndoManager> = RwLock::new(UndoManager::new(500));
    /// Project dirty state tracking
    static ref PROJECT_STATE: ProjectState = ProjectState::new();
    /// Click track / metronome
    static ref CLICK_TRACK: RwLock<crate::click::ClickTrack> = RwLock::new(crate::click::ClickTrack::new(48000));
}

/// Project dirty state for FFI
pub struct ProjectState {
    is_dirty: std::sync::atomic::AtomicBool,
    last_saved_undo_count: std::sync::atomic::AtomicUsize,
    file_path: RwLock<Option<String>>,
}

impl ProjectState {
    fn new() -> Self {
        Self {
            is_dirty: std::sync::atomic::AtomicBool::new(false),
            last_saved_undo_count: std::sync::atomic::AtomicUsize::new(0),
            file_path: RwLock::new(None),
        }
    }

    fn is_modified(&self) -> bool {
        use std::sync::atomic::Ordering;
        self.is_dirty.load(Ordering::Relaxed)
            || UNDO_MANAGER.read().undo_count()
                != self.last_saved_undo_count.load(Ordering::Relaxed)
    }

    fn mark_dirty(&self) {
        self.is_dirty
            .store(true, std::sync::atomic::Ordering::Relaxed);
    }

    fn mark_clean(&self) {
        use std::sync::atomic::Ordering;
        self.is_dirty.store(false, Ordering::Relaxed);
        self.last_saved_undo_count
            .store(UNDO_MANAGER.read().undo_count(), Ordering::Relaxed);
    }

    fn set_file_path(&self, path: Option<String>) {
        *self.file_path.write() = path;
    }

    fn file_path(&self) -> Option<String> {
        self.file_path.read().clone()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/// Convert C string to Rust string
unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

/// Convert Rust string to C string (caller must free)
fn string_to_cstr(s: &str) -> *mut c_char {
    CString::new(s)
        .map(|cs| cs.into_raw())
        .unwrap_or(ptr::null_mut())
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Create a new track
///
/// Returns track ID (u64) or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_create_track(name: *const c_char, color: u32, bus_id: u32) -> u64 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Track".to_string());
    let output_bus = OutputBus::from(bus_id);

    let track_id = TRACK_MANAGER.create_track(&name, color, output_bus);
    track_id.0
}

/// Delete a track
///
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_delete_track(track_id: u64) -> i32 {
    TRACK_MANAGER.delete_track(TrackId(track_id));
    1
}

/// Get track name (caller must free result with engine_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_name(track_id: u64) -> *mut c_char {
    if let Some(track) = TRACK_MANAGER.get_track(TrackId(track_id)) {
        string_to_cstr(&track.name)
    } else {
        ptr::null_mut()
    }
}

/// Set track name
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_name(track_id: u64, name: *const c_char) -> i32 {
    let name = match unsafe { cstr_to_string(name) } {
        Some(n) => n,
        None => return 0,
    };

    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.name = name;
    });
    1
}

/// Set track color
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_color(track_id: u64, color: u32) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.color = color;
    });
    1
}

/// Set track mute state
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_mute(track_id: u64, muted: i32) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.muted = muted != 0;
    });
    1
}

/// Set track solo state
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_solo(track_id: u64, solo: i32) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.soloed = solo != 0;
    });
    1
}

/// Set track armed state
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_armed(track_id: u64, armed: i32) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.armed = armed != 0;
    });
    1
}

/// Set track volume (0.0 - 2.0, 1.0 = unity)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_volume(track_id: u64, volume: f64) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.volume = volume.clamp(0.0, 2.0);
    });
    1
}

/// Set track pan (-1.0 to 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_pan(track_id: u64, pan: f64) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.pan = pan.clamp(-1.0, 1.0);
    });
    1
}

/// Set track output bus (0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience, 5=Aux)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_bus(track_id: u64, bus_id: u32) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.output_bus = OutputBus::from(bus_id);
    });
    1
}

/// Reorder tracks
#[unsafe(no_mangle)]
pub extern "C" fn engine_reorder_tracks(track_ids: *const u64, count: usize) -> i32 {
    if track_ids.is_null() || count == 0 {
        return 0;
    }

    let ids: Vec<TrackId> = unsafe {
        std::slice::from_raw_parts(track_ids, count)
            .iter()
            .map(|&id| TrackId(id))
            .collect()
    };

    TRACK_MANAGER.reorder_tracks(ids);
    1
}

/// Get track count
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_count() -> usize {
    TRACK_MANAGER.track_count()
}

/// Get track peak level (0.0 - 1.0+) by track ID
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_peak(track_id: u64) -> f64 {
    PLAYBACK_ENGINE.get_track_peak(track_id)
}

/// Get all track peaks at once (more efficient for UI)
/// Writes pairs of (track_id, peak) to out buffer
/// Returns number of tracks written
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_all_track_peaks(
    out_ids: *mut u64,
    out_peaks: *mut f64,
    max_count: usize,
) -> usize {
    if out_ids.is_null() || out_peaks.is_null() {
        return 0;
    }

    let peaks = PLAYBACK_ENGINE.get_all_track_peaks();
    let count = peaks.len().min(max_count);

    unsafe {
        for (i, (track_id, peak)) in peaks.iter().take(count).enumerate() {
            *out_ids.add(i) = *track_id;
            *out_peaks.add(i) = *peak;
        }
    }

    count
}

/// Get track IDs (caller provides buffer)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_ids(out_ids: *mut u64, max_count: usize) -> usize {
    if out_ids.is_null() {
        return 0;
    }

    let tracks = TRACK_MANAGER.get_all_tracks();
    let count = tracks.len().min(max_count);

    unsafe {
        for (i, track) in tracks.iter().take(count).enumerate() {
            *out_ids.add(i) = track.id.0;
        }
    }

    count
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO IMPORT FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Import audio file and add clip to track
///
/// Returns clip ID or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_import_audio(path: *const c_char, track_id: u64, start_time: f64) -> u64 {
    let path_str = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => {
            eprintln!("[FFI Import] ERROR: Invalid path pointer");
            return 0;
        }
    };

    eprintln!(
        "[FFI Import] Importing: {} to track {} at {:.2}s",
        path_str, track_id, start_time
    );

    // Import audio file
    let imported = match AudioImporter::import(Path::new(&path_str)) {
        Ok(audio) => {
            eprintln!(
                "[FFI Import] SUCCESS: {} samples, {} Hz, {} ch, {:.2}s",
                audio.samples.len(),
                audio.sample_rate,
                audio.channels,
                audio.duration_secs
            );
            Arc::new(audio)
        }
        Err(e) => {
            eprintln!(
                "[FFI Import] ERROR: Failed to import '{}': {:?}",
                path_str, e
            );
            return 0;
        }
    };

    let duration = imported.duration_secs;
    let name = imported.name.clone();

    // Create clip
    let clip_id = TRACK_MANAGER.create_clip(
        TrackId(track_id),
        &name,
        &path_str,
        start_time,
        duration,
        duration,
    );

    // Generate waveform peaks and cache
    let peaks = if imported.channels == 2 {
        StereoWaveformPeaks::from_interleaved(&imported.samples, imported.sample_rate)
    } else {
        StereoWaveformPeaks::from_mono(&imported.samples, imported.sample_rate)
    };

    // Store in caches
    let key = format!("clip_{}", clip_id.0);
    WAVEFORM_CACHE.get_or_compute(&key, || peaks);
    IMPORTED_AUDIO
        .write()
        .insert(clip_id, Arc::clone(&imported));

    // Also add to PlaybackEngine cache for real-time playback
    // (uses source_file path as key, matching how clips reference audio)
    log::info!(
        "[Import] Caching audio for path: '{}' (clip_id: {}, duration: {:.2}s, samples: {})",
        path_str,
        clip_id.0,
        duration,
        imported.samples.len()
    );
    PLAYBACK_ENGINE
        .cache
        .files
        .write()
        .insert(path_str.clone(), imported);

    // Debug: verify cache contents
    let cache_size = PLAYBACK_ENGINE.cache.files.read().len();
    log::info!("[Import] Cache now has {} entries", cache_size);

    clip_id.0
}

/// Get import error message (caller must free with engine_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_last_import_error() -> *mut c_char {
    // TODO: Implement error tracking
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP MANAGEMENT FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Add a clip to a track
#[unsafe(no_mangle)]
pub extern "C" fn engine_add_clip(
    track_id: u64,
    name: *const c_char,
    start_time: f64,
    duration: f64,
    source_offset: f64,
    source_duration: f64,
) -> u64 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Clip".to_string());

    let mut clip = Clip::new(TrackId(track_id), &name, "", start_time, duration);
    clip.source_offset = source_offset;
    clip.source_duration = source_duration;

    let clip_id = TRACK_MANAGER.add_clip(clip);
    clip_id.0
}

/// Move a clip to a new position (possibly on a different track)
#[unsafe(no_mangle)]
pub extern "C" fn engine_move_clip(clip_id: u64, target_track_id: u64, start_time: f64) -> i32 {
    TRACK_MANAGER.move_clip(ClipId(clip_id), TrackId(target_track_id), start_time);
    1
}

/// Resize a clip
#[unsafe(no_mangle)]
pub extern "C" fn engine_resize_clip(
    clip_id: u64,
    start_time: f64,
    duration: f64,
    source_offset: f64,
) -> i32 {
    TRACK_MANAGER.resize_clip(ClipId(clip_id), start_time, duration, source_offset);
    1
}

/// Split a clip at a given time
///
/// Returns the new clip ID (right part) or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_split_clip(clip_id: u64, at_time: f64) -> u64 {
    match TRACK_MANAGER.split_clip(ClipId(clip_id), at_time) {
        Some((_, new_id)) => new_id.0,
        None => 0,
    }
}

/// Duplicate a clip
///
/// Returns new clip ID or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_duplicate_clip(clip_id: u64) -> u64 {
    match TRACK_MANAGER.duplicate_clip(ClipId(clip_id)) {
        Some(new_id) => new_id.0,
        None => 0,
    }
}

/// Delete a clip
#[unsafe(no_mangle)]
pub extern "C" fn engine_delete_clip(clip_id: u64) -> i32 {
    TRACK_MANAGER.delete_clip(ClipId(clip_id));
    // Also remove from audio cache
    IMPORTED_AUDIO.write().remove(&ClipId(clip_id));
    1
}

/// Get clip info
///
/// Fills provided pointers with clip data
/// Returns 1 on success, 0 if clip not found
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_clip_info(
    clip_id: u64,
    out_track_id: *mut u64,
    out_start_time: *mut f64,
    out_duration: *mut f64,
    out_source_offset: *mut f64,
    out_gain: *mut f64,
    out_muted: *mut i32,
) -> i32 {
    if let Some(clip) = TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        unsafe {
            if !out_track_id.is_null() {
                *out_track_id = clip.track_id.0;
            }
            if !out_start_time.is_null() {
                *out_start_time = clip.start_time;
            }
            if !out_duration.is_null() {
                *out_duration = clip.duration;
            }
            if !out_source_offset.is_null() {
                *out_source_offset = clip.source_offset;
            }
            if !out_gain.is_null() {
                *out_gain = clip.gain;
            }
            if !out_muted.is_null() {
                *out_muted = if clip.muted { 1 } else { 0 };
            }
        }
        1
    } else {
        0
    }
}

/// Get clip duration (in seconds)
/// Returns -1.0 if clip not found
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_clip_duration(clip_id: u64) -> f64 {
    TRACK_MANAGER
        .get_clip(ClipId(clip_id))
        .map(|c| c.duration)
        .unwrap_or(-1.0)
}

/// Get clip source duration (original file duration in seconds)
/// Returns -1.0 if clip not found
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_clip_source_duration(clip_id: u64) -> f64 {
    TRACK_MANAGER
        .get_clip(ClipId(clip_id))
        .map(|c| c.source_duration)
        .unwrap_or(-1.0)
}

/// Get audio file duration (in seconds) by reading the file
/// Returns -1.0 on error
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_audio_file_duration(path: *const c_char) -> f64 {
    let path_str = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => return -1.0,
    };

    // Try to get from cache first
    if let Some(audio) = IMPORTED_AUDIO
        .read()
        .values()
        .find(|a| a.source_path == path_str)
    {
        return audio.sample_count as f64 / audio.sample_rate as f64;
    }

    // Load and get duration
    use std::path::Path;
    match crate::AudioImporter::import(Path::new(&path_str)) {
        Ok(audio) => audio.sample_count as f64 / audio.sample_rate as f64,
        Err(_) => -1.0,
    }
}

/// Set clip gain
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_clip_gain(clip_id: u64, gain: f64) -> i32 {
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.gain = gain.clamp(0.0, 4.0); // Allow up to +12dB
    });
    1
}

/// Set clip mute state
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_clip_muted(clip_id: u64, muted: i32) -> i32 {
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.muted = muted != 0;
    });
    1
}

/// Get clips for a track (caller provides buffer)
///
/// Returns actual number of clips
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_track_clips(
    track_id: u64,
    out_clip_ids: *mut u64,
    max_count: usize,
) -> usize {
    if out_clip_ids.is_null() {
        return 0;
    }

    let clips = TRACK_MANAGER.get_clips_for_track(TrackId(track_id));
    let count = clips.len().min(max_count);

    unsafe {
        for (i, clip) in clips.iter().take(count).enumerate() {
            *out_clip_ids.add(i) = clip.id.0;
        }
    }

    count
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Get waveform peaks for a clip at specified LOD level
///
/// Returns number of peaks written, or 0 on failure
/// Each peak is 2 floats (min, max), so buffer should be peaks * 2 floats
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_waveform_peaks(
    clip_id: u64,
    lod_level: u32,
    out_peaks: *mut f32,
    max_peaks: usize,
) -> usize {
    if out_peaks.is_null() || max_peaks == 0 {
        return 0;
    }

    let key = format!("clip_{}", clip_id);

    // Try to get from cache
    if let Some(peaks) = WAVEFORM_CACHE.cache.read().get(&key) {
        let level = (lod_level as usize).min(NUM_LOD_LEVELS - 1);
        let flat = peaks.left.to_flat_array(level);
        let count = (flat.len() / 2).min(max_peaks);

        unsafe {
            std::ptr::copy_nonoverlapping(flat.as_ptr(), out_peaks, count * 2);
        }

        return count;
    }

    0
}

/// Get waveform peaks for a time range
///
/// Returns number of peaks written
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_waveform_peaks_in_range(
    clip_id: u64,
    start_time: f64,
    end_time: f64,
    pixels_per_second: f64,
    out_peaks: *mut f32,
    max_peaks: usize,
) -> usize {
    if out_peaks.is_null() || max_peaks == 0 {
        return 0;
    }

    let key = format!("clip_{}", clip_id);

    if let Some(stereo_peaks) = WAVEFORM_CACHE.cache.read().get(&key) {
        let peaks = stereo_peaks
            .left
            .get_peaks_in_range(start_time, end_time, pixels_per_second);
        let count = peaks.len().min(max_peaks);

        unsafe {
            for (i, peak) in peaks.iter().take(count).enumerate() {
                *out_peaks.add(i * 2) = peak.min;
                *out_peaks.add(i * 2 + 1) = peak.max;
            }
        }

        return count;
    }

    0
}

/// Get number of LOD levels available
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_waveform_lod_levels() -> usize {
    NUM_LOD_LEVELS
}

/// Get samples per peak for a given LOD level
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_samples_per_peak(lod_level: u32) -> usize {
    let level = (lod_level as usize).min(NUM_LOD_LEVELS - 1);
    SAMPLES_PER_PEAK[level]
}

// ═══════════════════════════════════════════════════════════════════════════
// CROSSFADE FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Create a crossfade between two clips
///
/// curve: 0=Linear, 1=EqualPower, 2=SCurve
/// Returns crossfade ID or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_create_crossfade(
    clip_a_id: u64,
    clip_b_id: u64,
    duration: f64,
    curve: u32,
) -> u64 {
    let curve = match curve {
        0 => CrossfadeCurve::Linear,
        1 => CrossfadeCurve::EqualPower,
        2 => CrossfadeCurve::SCurve,
        _ => CrossfadeCurve::EqualPower,
    };

    match TRACK_MANAGER.create_crossfade(ClipId(clip_a_id), ClipId(clip_b_id), duration, curve) {
        Some(id) => id.0,
        None => 0,
    }
}

/// Update crossfade
#[unsafe(no_mangle)]
pub extern "C" fn engine_update_crossfade(crossfade_id: u64, duration: f64, curve: u32) -> i32 {
    let curve = match curve {
        0 => CrossfadeCurve::Linear,
        1 => CrossfadeCurve::EqualPower,
        2 => CrossfadeCurve::SCurve,
        _ => CrossfadeCurve::EqualPower,
    };

    TRACK_MANAGER.update_crossfade(CrossfadeId(crossfade_id), duration, curve);
    1
}

/// Delete a crossfade
#[unsafe(no_mangle)]
pub extern "C" fn engine_delete_crossfade(crossfade_id: u64) -> i32 {
    TRACK_MANAGER.delete_crossfade(CrossfadeId(crossfade_id));
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// LOOP REGION FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Set loop region
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_loop_region(start: f64, end: f64) {
    TRACK_MANAGER.set_loop_region(start, end);
}

/// Enable/disable loop
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_loop_enabled(enabled: i32) {
    TRACK_MANAGER.set_loop_enabled(enabled != 0);
}

/// Get loop region
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_loop_region(
    out_start: *mut f64,
    out_end: *mut f64,
    out_enabled: *mut i32,
) {
    let region = TRACK_MANAGER.get_loop_region();

    unsafe {
        if !out_start.is_null() {
            *out_start = region.start;
        }
        if !out_end.is_null() {
            *out_end = region.end;
        }
        if !out_enabled.is_null() {
            *out_enabled = if region.enabled { 1 } else { 0 };
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARKER FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Add a marker
///
/// Returns marker ID
#[unsafe(no_mangle)]
pub extern "C" fn engine_add_marker(name: *const c_char, time: f64, color: u32) -> u64 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Marker".to_string());
    let marker_id = TRACK_MANAGER.add_marker(time, &name, color);
    marker_id.0
}

/// Delete a marker
#[unsafe(no_mangle)]
pub extern "C" fn engine_delete_marker(marker_id: u64) -> i32 {
    TRACK_MANAGER.delete_marker(MarkerId(marker_id));
    1
}

/// Get marker count
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_marker_count() -> usize {
    TRACK_MANAGER.get_markers().len()
}

// ═══════════════════════════════════════════════════════════════════════════
// SNAP & GRID FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Snap time to grid
#[unsafe(no_mangle)]
pub extern "C" fn engine_snap_to_grid(time: f64, grid_size: f64) -> f64 {
    if grid_size <= 0.0 {
        return time;
    }
    (time / grid_size).round() * grid_size
}

/// Snap time to nearest event (clip boundary)
///
/// Returns snapped time, or original if no nearby event
#[unsafe(no_mangle)]
pub extern "C" fn engine_snap_to_event(time: f64, threshold: f64) -> f64 {
    let clips = TRACK_MANAGER.get_all_clips();

    let mut nearest_time = time;
    let mut nearest_distance = threshold;

    // Check all clip boundaries
    for clip in &clips {
        let start_dist = (clip.start_time - time).abs();
        let end_dist = (clip.end_time() - time).abs();

        if start_dist < nearest_distance {
            nearest_distance = start_dist;
            nearest_time = clip.start_time;
        }
        if end_dist < nearest_distance {
            nearest_distance = end_dist;
            nearest_time = clip.end_time();
        }
    }

    nearest_time
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSPORT / PLAYBACK FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Start playback
#[unsafe(no_mangle)]
pub extern "C" fn engine_play() {
    PLAYBACK_ENGINE.play();
}

/// Pause playback
#[unsafe(no_mangle)]
pub extern "C" fn engine_pause() {
    PLAYBACK_ENGINE.pause();
}

/// Stop playback and reset position
#[unsafe(no_mangle)]
pub extern "C" fn engine_stop() {
    PLAYBACK_ENGINE.stop();
}

/// Seek to position in seconds
#[unsafe(no_mangle)]
pub extern "C" fn engine_seek(seconds: f64) {
    PLAYBACK_ENGINE.seek(seconds);
}

/// Seek to position in samples
#[unsafe(no_mangle)]
pub extern "C" fn engine_seek_samples(samples: u64) {
    PLAYBACK_ENGINE.seek_samples(samples);
}

/// Get current playback position in seconds
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_position() -> f64 {
    PLAYBACK_ENGINE.current_time()
}

/// Get current playback position in samples
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_position_samples() -> u64 {
    PLAYBACK_ENGINE.position.samples()
}

/// Get playback state (0=Stopped, 1=Playing, 2=Paused)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_playback_state() -> u8 {
    PLAYBACK_ENGINE.state() as u8
}

/// Check if currently playing
#[unsafe(no_mangle)]
pub extern "C" fn engine_is_playing() -> i32 {
    if PLAYBACK_ENGINE.is_playing() { 1 } else { 0 }
}

/// Set master volume (0.0 to 1.5)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_master_volume(volume: f64) {
    PLAYBACK_ENGINE.set_master_volume(volume);
}

/// Get master volume
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_master_volume() -> f64 {
    PLAYBACK_ENGINE.master_volume()
}

/// Preload all audio files for playback
#[unsafe(no_mangle)]
pub extern "C" fn engine_preload_all() {
    PLAYBACK_ENGINE.preload_all();
}

/// Preload audio files in time range
#[unsafe(no_mangle)]
pub extern "C" fn engine_preload_range(start_time: f64, end_time: f64) {
    PLAYBACK_ENGINE.preload_range(start_time, end_time);
}

/// Process audio block - main audio callback
///
/// This should be called from the audio thread callback.
/// output_l and output_r should be arrays of `frames` f64 values.
#[unsafe(no_mangle)]
pub extern "C" fn engine_process_audio(output_l: *mut f64, output_r: *mut f64, frames: usize) {
    if output_l.is_null() || output_r.is_null() || frames == 0 {
        return;
    }

    let out_l = unsafe { std::slice::from_raw_parts_mut(output_l, frames) };
    let out_r = unsafe { std::slice::from_raw_parts_mut(output_r, frames) };

    PLAYBACK_ENGINE.process(out_l, out_r);
}

/// Get sample rate
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_sample_rate() -> u32 {
    PLAYBACK_ENGINE.position.sample_rate()
}

/// Set transport loop from loop region
#[unsafe(no_mangle)]
pub extern "C" fn engine_sync_loop_from_region() {
    let region = TRACK_MANAGER.get_loop_region();
    PLAYBACK_ENGINE
        .position
        .set_loop(region.start, region.end, region.enabled);
}

// ═══════════════════════════════════════════════════════════════════════════
// BUS CONTROL FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Set bus volume (bus_idx: 0=UI, 1=Reels, 2=FX, 3=VO, 4=Music, 5=Ambient)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_bus_volume(bus_idx: i32, volume: f64) {
    if bus_idx >= 0 && bus_idx < 6 {
        PLAYBACK_ENGINE.set_bus_volume(bus_idx as usize, volume);
    }
}

/// Set bus pan (-1.0 to 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_bus_pan(bus_idx: i32, pan: f64) {
    if bus_idx >= 0 && bus_idx < 6 {
        PLAYBACK_ENGINE.set_bus_pan(bus_idx as usize, pan);
    }
}

/// Set bus mute
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_bus_mute(bus_idx: i32, muted: i32) {
    if bus_idx >= 0 && bus_idx < 6 {
        PLAYBACK_ENGINE.set_bus_mute(bus_idx as usize, muted != 0);
    }
}

/// Set bus solo
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_bus_solo(bus_idx: i32, soloed: i32) {
    if bus_idx >= 0 && bus_idx < 6 {
        PLAYBACK_ENGINE.set_bus_solo(bus_idx as usize, soloed != 0);
    }
}

/// Get bus volume
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_bus_volume(bus_idx: i32) -> f64 {
    if bus_idx >= 0 && bus_idx < 6 {
        PLAYBACK_ENGINE
            .get_bus_state(bus_idx as usize)
            .map(|s| s.volume)
            .unwrap_or(1.0)
    } else {
        1.0
    }
}

/// Get bus mute state
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_bus_mute(bus_idx: i32) -> i32 {
    if bus_idx >= 0 && bus_idx < 6 {
        if PLAYBACK_ENGINE
            .get_bus_state(bus_idx as usize)
            .map(|s| s.muted)
            .unwrap_or(false)
        {
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Get bus solo state
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_bus_solo(bus_idx: i32) -> i32 {
    if bus_idx >= 0 && bus_idx < 6 {
        if PLAYBACK_ENGINE
            .get_bus_state(bus_idx as usize)
            .map(|s| s.soloed)
            .unwrap_or(false)
        {
            1
        } else {
            0
        }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Get peak meters (fills left and right peak values)
/// Returns linear amplitude (0.0 to 1.0+)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_peak_meters(out_left: *mut f64, out_right: *mut f64) {
    let (peak_l, peak_r) = PLAYBACK_ENGINE.get_peaks();
    if !out_left.is_null() {
        unsafe {
            *out_left = peak_l;
        }
    }
    if !out_right.is_null() {
        unsafe {
            *out_right = peak_r;
        }
    }
}

/// Get RMS meters
/// Returns linear amplitude (0.0 to 1.0+)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_rms_meters(out_left: *mut f64, out_right: *mut f64) {
    let (rms_l, rms_r) = PLAYBACK_ENGINE.get_rms();
    if !out_left.is_null() {
        unsafe {
            *out_left = rms_l;
        }
    }
    if !out_right.is_null() {
        unsafe {
            *out_right = rms_r;
        }
    }
}

/// Get LUFS meters (momentary, short-term, integrated)
/// Returns values in LUFS per ITU-R BS.1770-4 (typically -70 to 0)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_lufs_meters(
    out_momentary: *mut f64,
    out_short: *mut f64,
    out_integrated: *mut f64,
) {
    let (momentary, short, integrated) = PLAYBACK_ENGINE.get_lufs();

    if !out_momentary.is_null() {
        unsafe {
            *out_momentary = momentary;
        }
    }
    if !out_short.is_null() {
        unsafe {
            *out_short = short;
        }
    }
    if !out_integrated.is_null() {
        unsafe {
            *out_integrated = integrated;
        }
    }
}

/// Get true peak meters (left, right)
/// Returns values in dBTP per ITU-R BS.1770-4 (4x oversampled)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_true_peak_meters(out_left: *mut f64, out_right: *mut f64) {
    let (db_l, db_r) = PLAYBACK_ENGINE.get_true_peak();

    if !out_left.is_null() {
        unsafe {
            *out_left = db_l;
        }
    }
    if !out_right.is_null() {
        unsafe {
            *out_right = db_r;
        }
    }
}

/// Get master stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
#[unsafe(no_mangle)]
pub extern "C" fn metering_get_master_correlation() -> f32 {
    PLAYBACK_ENGINE.get_correlation() as f32
}

/// Get master stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
#[unsafe(no_mangle)]
pub extern "C" fn metering_get_master_balance() -> f32 {
    PLAYBACK_ENGINE.get_balance() as f32
}

/// Get master dynamic range (peak - RMS in dB)
#[unsafe(no_mangle)]
pub extern "C" fn metering_get_master_dynamic_range() -> f32 {
    // Calculate from existing peak and RMS values
    let (peak_l, peak_r) = PLAYBACK_ENGINE.get_peaks();
    let (rms_l, rms_r) = PLAYBACK_ENGINE.get_rms();

    let peak_db = |p: f64| {
        if p <= 0.000001 {
            -60.0
        } else {
            20.0 * p.log10()
        }
    };
    let rms_db = |r: f64| {
        if r <= 0.000001 {
            -60.0
        } else {
            20.0 * r.log10()
        }
    };

    let peak_max = peak_db(peak_l).max(peak_db(peak_r));
    let rms_avg = (rms_db(rms_l) + rms_db(rms_r)) / 2.0;

    (peak_max - rms_avg).clamp(0.0, 40.0) as f32
}

/// Get master spectrum data (256 bins, normalized 0-1, log-scaled 20Hz-20kHz)
/// Writes data to out_data buffer, returns number of bins written
#[unsafe(no_mangle)]
pub extern "C" fn metering_get_master_spectrum(out_data: *mut f32, max_count: usize) -> usize {
    if out_data.is_null() {
        return 0;
    }

    let spectrum = PLAYBACK_ENGINE.get_spectrum_data();
    let count = spectrum.len().min(max_count);

    unsafe {
        for (i, &value) in spectrum.iter().take(count).enumerate() {
            *out_data.add(i) = value;
        }
    }

    count
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP FX FFI
// ═══════════════════════════════════════════════════════════════════════════

use crate::track_manager::{ClipFxSlotId, ClipFxType};

/// Convert int to ClipFxType
fn fx_type_from_int(value: u8) -> ClipFxType {
    match value {
        0 => ClipFxType::Gain { db: 0.0, pan: 0.0 },
        1 => ClipFxType::Compressor {
            ratio: 4.0,
            threshold_db: -18.0,
            attack_ms: 10.0,
            release_ms: 100.0,
        },
        2 => ClipFxType::Limiter { ceiling_db: -0.3 },
        3 => ClipFxType::Gate {
            threshold_db: -40.0,
            attack_ms: 1.0,
            release_ms: 50.0,
        },
        4 => ClipFxType::Saturation {
            drive: 0.5,
            mix: 1.0,
        },
        5 => ClipFxType::PitchShift {
            semitones: 0.0,
            cents: 0.0,
        },
        6 => ClipFxType::TimeStretch { ratio: 1.0 },
        7 => ClipFxType::ProEq { bands: 8 },
        8 => ClipFxType::UltraEq,
        9 => ClipFxType::Pultec,
        10 => ClipFxType::Api550,
        11 => ClipFxType::Neve1073,
        12 => ClipFxType::MorphEq,
        13 => ClipFxType::RoomCorrection,
        14 => ClipFxType::External {
            plugin_id: String::new(),
            state: None,
        },
        _ => ClipFxType::Gain { db: 0.0, pan: 0.0 },
    }
}

/// Add FX slot to clip - returns slot ID or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_add(clip_id: u64, fx_type: u8) -> u64 {
    let fx = fx_type_from_int(fx_type);
    TRACK_MANAGER
        .add_clip_fx(ClipId(clip_id), fx)
        .map(|id| id.0)
        .unwrap_or(0)
}

/// Remove FX slot from clip
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_remove(clip_id: u64, slot_id: u64) -> i32 {
    if TRACK_MANAGER.remove_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id)) {
        1
    } else {
        0
    }
}

/// Move FX slot to new position
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_move(clip_id: u64, slot_id: u64, new_index: u64) -> i32 {
    if TRACK_MANAGER.move_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), new_index as usize) {
        1
    } else {
        0
    }
}

/// Set FX slot bypass
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_bypass(clip_id: u64, slot_id: u64, bypass: i32) -> i32 {
    if TRACK_MANAGER.set_clip_fx_bypass(ClipId(clip_id), ClipFxSlotId(slot_id), bypass != 0) {
        1
    } else {
        0
    }
}

/// Set entire FX chain bypass
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_chain_bypass(clip_id: u64, bypass: i32) -> i32 {
    if TRACK_MANAGER.set_clip_fx_chain_bypass(ClipId(clip_id), bypass != 0) {
        1
    } else {
        0
    }
}

/// Set FX slot wet/dry mix
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_wet_dry(clip_id: u64, slot_id: u64, wet_dry: f64) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.wet_dry = wet_dry.clamp(0.0, 1.0);
    }) {
        1
    } else {
        0
    }
}

/// Set clip FX chain input gain
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_input_gain(clip_id: u64, gain_db: f64) -> i32 {
    if TRACK_MANAGER.set_clip_fx_input_gain(ClipId(clip_id), gain_db) {
        1
    } else {
        0
    }
}

/// Set clip FX chain output gain
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_output_gain(clip_id: u64, gain_db: f64) -> i32 {
    if TRACK_MANAGER.set_clip_fx_output_gain(ClipId(clip_id), gain_db) {
        1
    } else {
        0
    }
}

/// Set Gain FX parameters
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_gain_params(clip_id: u64, slot_id: u64, db: f64, pan: f64) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.fx_type = ClipFxType::Gain {
            db,
            pan: pan.clamp(-1.0, 1.0),
        };
    }) {
        1
    } else {
        0
    }
}

/// Set Compressor FX parameters
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_compressor_params(
    clip_id: u64,
    slot_id: u64,
    ratio: f64,
    threshold_db: f64,
    attack_ms: f64,
    release_ms: f64,
) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.fx_type = ClipFxType::Compressor {
            ratio: ratio.clamp(1.0, 100.0),
            threshold_db: threshold_db.clamp(-60.0, 0.0),
            attack_ms: attack_ms.clamp(0.01, 500.0),
            release_ms: release_ms.clamp(1.0, 5000.0),
        };
    }) {
        1
    } else {
        0
    }
}

/// Set Limiter FX parameters
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_limiter_params(clip_id: u64, slot_id: u64, ceiling_db: f64) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.fx_type = ClipFxType::Limiter {
            ceiling_db: ceiling_db.clamp(-30.0, 0.0),
        };
    }) {
        1
    } else {
        0
    }
}

/// Set Gate FX parameters
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_gate_params(
    clip_id: u64,
    slot_id: u64,
    threshold_db: f64,
    attack_ms: f64,
    release_ms: f64,
) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.fx_type = ClipFxType::Gate {
            threshold_db: threshold_db.clamp(-80.0, 0.0),
            attack_ms: attack_ms.clamp(0.01, 100.0),
            release_ms: release_ms.clamp(1.0, 2000.0),
        };
    }) {
        1
    } else {
        0
    }
}

/// Set Saturation FX parameters
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_set_saturation_params(
    clip_id: u64,
    slot_id: u64,
    drive: f64,
    mix: f64,
) -> i32 {
    if TRACK_MANAGER.update_clip_fx(ClipId(clip_id), ClipFxSlotId(slot_id), |slot| {
        slot.fx_type = ClipFxType::Saturation {
            drive: drive.clamp(0.0, 1.0),
            mix: mix.clamp(0.0, 1.0),
        };
    }) {
        1
    } else {
        0
    }
}

/// Copy FX chain from one clip to another
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_copy(source_clip_id: u64, target_clip_id: u64) -> i32 {
    if TRACK_MANAGER.copy_clip_fx(ClipId(source_clip_id), ClipId(target_clip_id)) {
        1
    } else {
        0
    }
}

/// Clear all FX from clip
#[unsafe(no_mangle)]
pub extern "C" fn clip_fx_clear(clip_id: u64) -> i32 {
    if TRACK_MANAGER.clear_clip_fx(ClipId(clip_id)) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLICK TRACK / METRONOME FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Enable/disable click track
#[unsafe(no_mangle)]
pub extern "C" fn click_set_enabled(enabled: i32) {
    CLICK_TRACK.read().set_enabled(enabled != 0);
}

/// Check if click track is enabled
#[unsafe(no_mangle)]
pub extern "C" fn click_is_enabled() -> i32 {
    if CLICK_TRACK.read().is_enabled() {
        1
    } else {
        0
    }
}

/// Set click volume (0.0 - 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn click_set_volume(volume: f64) {
    CLICK_TRACK.write().set_volume(volume as f32);
}

/// Set click pattern
/// 0 = Quarter, 1 = Eighth, 2 = Sixteenth, 3 = Triplet, 4 = DownbeatOnly
#[unsafe(no_mangle)]
pub extern "C" fn click_set_pattern(pattern: u8) {
    use crate::click::ClickPattern;
    let p = match pattern {
        0 => ClickPattern::Quarter,
        1 => ClickPattern::Eighth,
        2 => ClickPattern::Sixteenth,
        3 => ClickPattern::Triplet,
        4 => ClickPattern::DownbeatOnly,
        _ => ClickPattern::Quarter,
    };
    CLICK_TRACK.write().set_pattern(p);
}

/// Set count-in mode
/// 0 = Off, 1 = OneBar, 2 = TwoBars, 3 = FourBeats
#[unsafe(no_mangle)]
pub extern "C" fn click_set_count_in(mode: u8) {
    use crate::click::CountInMode;
    let m = match mode {
        0 => CountInMode::Off,
        1 => CountInMode::OneBar,
        2 => CountInMode::TwoBars,
        3 => CountInMode::FourBeats,
        _ => CountInMode::Off,
    };
    CLICK_TRACK.write().set_count_in(m);
}

/// Set click pan (-1.0 left, 0.0 center, 1.0 right)
#[unsafe(no_mangle)]
pub extern "C" fn click_set_pan(pan: f64) {
    CLICK_TRACK.write().set_pan(pan as f32);
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND/RETURN FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SEND_BANKS: parking_lot::RwLock<std::collections::HashMap<u64, crate::send_return::SendBank>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref RETURN_MANAGER: parking_lot::RwLock<crate::send_return::ReturnBusManager> =
        parking_lot::RwLock::new(crate::send_return::ReturnBusManager::new(4, 512, 48000.0));
}

/// Set send level for a track
/// track_id: Track identifier
/// send_index: Send slot (0-7)
/// level: Linear gain (0.0 - 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn send_set_level(track_id: u64, send_index: u32, level: f64) {
    let banks = SEND_BANKS.read();
    if let Some(bank) = banks.get(&track_id) {
        if let Some(send) = bank.get(send_index as usize) {
            send.set_level(level);
        }
    }
}

/// Set send level in dB
#[unsafe(no_mangle)]
pub extern "C" fn send_set_level_db(track_id: u64, send_index: u32, db: f64) {
    let banks = SEND_BANKS.read();
    if let Some(bank) = banks.get(&track_id) {
        if let Some(send) = bank.get(send_index as usize) {
            send.set_level_db(db);
        }
    }
}

/// Set send destination (return bus index)
#[unsafe(no_mangle)]
pub extern "C" fn send_set_destination(track_id: u64, send_index: u32, destination: u32) {
    let mut banks = SEND_BANKS.write();
    if let Some(bank) = banks.get_mut(&track_id) {
        if let Some(send) = bank.get_mut(send_index as usize) {
            send.set_destination(destination as usize);
        }
    }
}

/// Set send pan (-1.0 left, 0.0 center, 1.0 right)
#[unsafe(no_mangle)]
pub extern "C" fn send_set_pan(track_id: u64, send_index: u32, pan: f64) {
    let banks = SEND_BANKS.read();
    if let Some(bank) = banks.get(&track_id) {
        if let Some(send) = bank.get(send_index as usize) {
            send.set_pan(pan);
        }
    }
}

/// Enable/disable send
#[unsafe(no_mangle)]
pub extern "C" fn send_set_enabled(track_id: u64, send_index: u32, enabled: i32) {
    let banks = SEND_BANKS.read();
    if let Some(bank) = banks.get(&track_id) {
        if let Some(send) = bank.get(send_index as usize) {
            send.set_enabled(enabled != 0);
        }
    }
}

/// Mute/unmute send
#[unsafe(no_mangle)]
pub extern "C" fn send_set_muted(track_id: u64, send_index: u32, muted: i32) {
    let banks = SEND_BANKS.read();
    if let Some(bank) = banks.get(&track_id) {
        if let Some(send) = bank.get(send_index as usize) {
            send.set_muted(muted != 0);
        }
    }
}

/// Set send tap point
/// 0 = PreFader, 1 = PostFader, 2 = PostPan
#[unsafe(no_mangle)]
pub extern "C" fn send_set_tap_point(track_id: u64, send_index: u32, tap_point: u8) {
    use crate::send_return::SendTapPoint;
    let tap = match tap_point {
        0 => SendTapPoint::PreFader,
        1 => SendTapPoint::PostFader,
        2 => SendTapPoint::PostPan,
        _ => SendTapPoint::PostFader,
    };
    let mut banks = SEND_BANKS.write();
    if let Some(bank) = banks.get_mut(&track_id) {
        if let Some(send) = bank.get_mut(send_index as usize) {
            send.set_tap_point(tap);
        }
    }
}

/// Create send bank for a track (call when track is created)
#[unsafe(no_mangle)]
pub extern "C" fn send_create_bank(track_id: u64) {
    let mut banks = SEND_BANKS.write();
    if !banks.contains_key(&track_id) {
        banks.insert(track_id, crate::send_return::SendBank::new(48000.0));
    }
}

/// Remove send bank (call when track is deleted)
#[unsafe(no_mangle)]
pub extern "C" fn send_remove_bank(track_id: u64) {
    let mut banks = SEND_BANKS.write();
    banks.remove(&track_id);
}

// ═══════════════════════════════════════════════════════════════════════════
// RETURN BUS FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Set return bus level
#[unsafe(no_mangle)]
pub extern "C" fn return_set_level(return_index: u32, level: f64) {
    let manager = RETURN_MANAGER.read();
    if let Some(bus) = manager.get(return_index as usize) {
        bus.set_level(level);
    }
}

/// Set return bus level in dB
#[unsafe(no_mangle)]
pub extern "C" fn return_set_level_db(return_index: u32, db: f64) {
    let manager = RETURN_MANAGER.read();
    if let Some(bus) = manager.get(return_index as usize) {
        bus.set_level_db(db);
    }
}

/// Set return bus pan
#[unsafe(no_mangle)]
pub extern "C" fn return_set_pan(return_index: u32, pan: f64) {
    let manager = RETURN_MANAGER.read();
    if let Some(bus) = manager.get(return_index as usize) {
        bus.set_pan(pan);
    }
}

/// Mute/unmute return bus
#[unsafe(no_mangle)]
pub extern "C" fn return_set_muted(return_index: u32, muted: i32) {
    let manager = RETURN_MANAGER.read();
    if let Some(bus) = manager.get(return_index as usize) {
        bus.set_muted(muted != 0);
    }
}

/// Solo/unsolo return bus
#[unsafe(no_mangle)]
pub extern "C" fn return_set_solo(return_index: u32, solo: i32) {
    let manager = RETURN_MANAGER.read();
    if let Some(bus) = manager.get(return_index as usize) {
        bus.set_solo(solo != 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SIDECHAIN ROUTING FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SIDECHAIN_ROUTER: parking_lot::RwLock<crate::sidechain::SidechainRouter> =
        parking_lot::RwLock::new(crate::sidechain::SidechainRouter::new(512));
    static ref SIDECHAIN_INPUTS: parking_lot::RwLock<std::collections::HashMap<u32, crate::sidechain::SidechainInput>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Add a sidechain route
/// Returns route ID (non-zero) or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_add_route(
    source_id: u32,
    dest_processor_id: u32,
    pre_fader: i32,
) -> u32 {
    let mut router = SIDECHAIN_ROUTER.write();
    router.add_route(source_id, dest_processor_id, pre_fader != 0)
}

/// Remove a sidechain route
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_remove_route(route_id: u32) -> i32 {
    let mut router = SIDECHAIN_ROUTER.write();
    if router.remove_route(route_id) { 1 } else { 0 }
}

/// Create sidechain input for a processor
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_create_input(processor_id: u32) {
    let mut inputs = SIDECHAIN_INPUTS.write();
    if !inputs.contains_key(&processor_id) {
        inputs.insert(
            processor_id,
            crate::sidechain::SidechainInput::new(48000.0, 512),
        );
    }
}

/// Remove sidechain input
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_remove_input(processor_id: u32) {
    let mut inputs = SIDECHAIN_INPUTS.write();
    inputs.remove(&processor_id);
}

/// Set sidechain source type
/// source_type: 0=Internal, 1=External, 2=Mid, 3=Side
/// external_id: Source track ID (only used when source_type=1)
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_source(processor_id: u32, source_type: u8, external_id: u32) {
    use crate::sidechain::SidechainSource;
    let source = match source_type {
        0 => SidechainSource::Internal,
        1 => SidechainSource::External(external_id),
        2 => SidechainSource::Mid,
        3 => SidechainSource::Side,
        _ => SidechainSource::Internal,
    };
    let mut inputs = SIDECHAIN_INPUTS.write();
    if let Some(input) = inputs.get_mut(&processor_id) {
        input.set_source(source);
    }
}

/// Set sidechain filter mode
/// mode: 0=Off, 1=HighPass, 2=LowPass, 3=BandPass
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_filter_mode(processor_id: u32, mode: u8) {
    use crate::sidechain::SidechainFilterMode;
    let filter_mode = match mode {
        0 => SidechainFilterMode::Off,
        1 => SidechainFilterMode::HighPass,
        2 => SidechainFilterMode::LowPass,
        3 => SidechainFilterMode::BandPass,
        _ => SidechainFilterMode::Off,
    };
    let mut inputs = SIDECHAIN_INPUTS.write();
    if let Some(input) = inputs.get_mut(&processor_id) {
        input.set_filter_mode(filter_mode);
    }
}

/// Set sidechain filter frequency (20-20000 Hz)
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_filter_freq(processor_id: u32, freq: f64) {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        input.set_filter_freq(freq);
    }
}

/// Set sidechain filter Q (0.1-10.0)
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_filter_q(processor_id: u32, q: f64) {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        input.set_filter_q(q);
    }
}

/// Set sidechain mix (0.0=internal, 1.0=external)
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_mix(processor_id: u32, mix: f64) {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        input.set_mix(mix);
    }
}

/// Set sidechain gain in dB
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_gain_db(processor_id: u32, db: f64) {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        input.set_gain_db(db);
    }
}

/// Enable/disable sidechain monitor
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_set_monitor(processor_id: u32, monitor: i32) {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        input.set_monitor(monitor != 0);
    }
}

/// Check if sidechain is monitoring
#[unsafe(no_mangle)]
pub extern "C" fn sidechain_is_monitoring(processor_id: u32) -> i32 {
    let inputs = SIDECHAIN_INPUTS.read();
    if let Some(input) = inputs.get(&processor_id) {
        if input.is_monitoring() { 1 } else { 0 }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref AUTOMATION_ENGINE: crate::automation::AutomationEngine =
        crate::automation::AutomationEngine::new(48000.0);
}

/// Set global automation mode
/// mode: 0=Read, 1=Touch, 2=Latch, 3=Write, 4=Trim, 5=Off
#[unsafe(no_mangle)]
pub extern "C" fn automation_set_mode(mode: u8) {
    use crate::automation::AutomationMode;
    let m = match mode {
        0 => AutomationMode::Read,
        1 => AutomationMode::Touch,
        2 => AutomationMode::Latch,
        3 => AutomationMode::Write,
        4 => AutomationMode::Trim,
        5 => AutomationMode::Off,
        _ => AutomationMode::Read,
    };
    AUTOMATION_ENGINE.set_mode(m);
}

/// Get current automation mode
#[unsafe(no_mangle)]
pub extern "C" fn automation_get_mode() -> u8 {
    use crate::automation::AutomationMode;
    match AUTOMATION_ENGINE.mode() {
        AutomationMode::Read => 0,
        AutomationMode::Touch => 1,
        AutomationMode::Latch => 2,
        AutomationMode::Write => 3,
        AutomationMode::Trim => 4,
        AutomationMode::Off => 5,
    }
}

/// Enable/disable automation recording
#[unsafe(no_mangle)]
pub extern "C" fn automation_set_recording(enabled: i32) {
    AUTOMATION_ENGINE.set_recording(enabled != 0);
}

/// Check if automation recording is enabled
#[unsafe(no_mangle)]
pub extern "C" fn automation_is_recording() -> i32 {
    if AUTOMATION_ENGINE.is_recording() {
        1
    } else {
        0
    }
}

/// Touch parameter (start recording for touch/latch modes)
#[unsafe(no_mangle)]
pub extern "C" fn automation_touch_param(track_id: u64, param_name: *const c_char, value: f64) {
    use crate::automation::{ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name,
        slot: None,
    };
    AUTOMATION_ENGINE.touch_param(param_id, value);
}

/// Release parameter (stop touch recording)
#[unsafe(no_mangle)]
pub extern "C" fn automation_release_param(track_id: u64, param_name: *const c_char) {
    use crate::automation::{ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name,
        slot: None,
    };
    AUTOMATION_ENGINE.release_param(&param_id);
}

/// Record parameter change
#[unsafe(no_mangle)]
pub extern "C" fn automation_record_change(track_id: u64, param_name: *const c_char, value: f64) {
    use crate::automation::{ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name,
        slot: None,
    };
    AUTOMATION_ENGINE.record_change(param_id, value);
}

/// Add automation point directly
#[unsafe(no_mangle)]
pub extern "C" fn automation_add_point(
    track_id: u64,
    param_name: *const c_char,
    time_samples: u64,
    value: f64,
    curve_type: u8,
) {
    use crate::automation::{AutomationPoint, CurveType, ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name.clone(),
        slot: None,
    };

    // Ensure lane exists
    AUTOMATION_ENGINE.get_or_create_lane(param_id.clone(), &name);

    let curve = match curve_type {
        0 => CurveType::Linear,
        1 => CurveType::Bezier,
        2 => CurveType::Exponential,
        3 => CurveType::Logarithmic,
        4 => CurveType::Step,
        5 => CurveType::SCurve,
        _ => CurveType::Linear,
    };

    let point = AutomationPoint::new(time_samples, value).with_curve(curve);
    AUTOMATION_ENGINE.add_point(&param_id, point);
}

/// Get automation value at position
#[unsafe(no_mangle)]
pub extern "C" fn automation_get_value(
    track_id: u64,
    param_name: *const c_char,
    time_samples: u64,
) -> f64 {
    use crate::automation::{ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name,
        slot: None,
    };

    if let Some(lane) = AUTOMATION_ENGINE.lane(&param_id) {
        lane.value_at(time_samples)
    } else {
        0.5 // Default value
    }
}

/// Clear automation lane
#[unsafe(no_mangle)]
pub extern "C" fn automation_clear_lane(track_id: u64, param_name: *const c_char) {
    use crate::automation::{ParamId, TargetType};
    let name = if param_name.is_null() {
        "volume".to_string()
    } else {
        unsafe { std::ffi::CStr::from_ptr(param_name) }
            .to_string_lossy()
            .into_owned()
    };
    let param_id = ParamId {
        target_id: track_id,
        target_type: TargetType::Track,
        param_name: name,
        slot: None,
    };

    AUTOMATION_ENGINE.with_lane(&param_id, |lane| lane.clear());
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT EFFECTS FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref INSERT_CHAINS: parking_lot::RwLock<std::collections::HashMap<u64, crate::insert_chain::InsertChain>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create insert chain for a track
#[unsafe(no_mangle)]
pub extern "C" fn insert_create_chain(track_id: u64) {
    let mut chains = INSERT_CHAINS.write();
    if !chains.contains_key(&track_id) {
        chains.insert(track_id, crate::insert_chain::InsertChain::new(48000.0));
    }
}

/// Remove insert chain
#[unsafe(no_mangle)]
pub extern "C" fn insert_remove_chain(track_id: u64) {
    let mut chains = INSERT_CHAINS.write();
    chains.remove(&track_id);
}

/// Set insert slot bypass
#[unsafe(no_mangle)]
pub extern "C" fn insert_set_bypass(track_id: u64, slot: u32, bypass: i32) {
    let chains = INSERT_CHAINS.read();
    if let Some(chain) = chains.get(&track_id) {
        if let Some(slot_ref) = chain.slot(slot as usize) {
            slot_ref.set_bypass(bypass != 0);
        }
    }
}

/// Set insert slot wet/dry mix
#[unsafe(no_mangle)]
pub extern "C" fn insert_set_mix(track_id: u64, slot: u32, mix: f64) {
    let chains = INSERT_CHAINS.read();
    if let Some(chain) = chains.get(&track_id) {
        if let Some(slot_ref) = chain.slot(slot as usize) {
            slot_ref.set_mix(mix);
        }
    }
}

/// Bypass all inserts on track
#[unsafe(no_mangle)]
pub extern "C" fn insert_bypass_all(track_id: u64, bypass: i32) {
    let chains = INSERT_CHAINS.read();
    if let Some(chain) = chains.get(&track_id) {
        chain.bypass_all(bypass != 0);
    }
}

/// Get total latency of insert chain (samples)
#[unsafe(no_mangle)]
pub extern "C" fn insert_get_total_latency(track_id: u64) -> u32 {
    let chains = INSERT_CHAINS.read();
    if let Some(chain) = chains.get(&track_id) {
        chain.total_latency() as u32
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSIENT DETECTION FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Detect transients in audio buffer
/// Returns number of transients detected
#[unsafe(no_mangle)]
pub extern "C" fn transient_detect(
    samples: *const f64,
    length: u32,
    sample_rate: f64,
    sensitivity: f64,
    algorithm: u8,
    out_positions: *mut u64,
    out_max_count: u32,
) -> u32 {
    use rf_dsp::transient::{DetectionAlgorithm, TransientDetector};

    if samples.is_null() || out_positions.is_null() || length == 0 {
        return 0;
    }

    let algo = match algorithm {
        0 => DetectionAlgorithm::HighEmphasis,
        1 => DetectionAlgorithm::LowEmphasis,
        2 => DetectionAlgorithm::Enhanced,
        3 => DetectionAlgorithm::SpectralFlux,
        4 => DetectionAlgorithm::ComplexDomain,
        _ => DetectionAlgorithm::Enhanced,
    };

    let mut detector = TransientDetector::new(sample_rate);
    detector.set_algorithm(algo);
    detector.set_sensitivity(sensitivity);

    let input = unsafe { std::slice::from_raw_parts(samples, length as usize) };
    let transients = detector.analyze(input);

    let count = transients.len().min(out_max_count as usize);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out_positions, count) };

    for (i, t) in transients.iter().take(count).enumerate() {
        out_slice[i] = t.position;
    }

    count as u32
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH DETECTION FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Detect pitch at position
/// Returns frequency in Hz (0.0 if no pitch detected)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_detect(samples: *const f64, length: u32, sample_rate: f64) -> f64 {
    use rf_dsp::pitch::PitchDetector;

    if samples.is_null() || length == 0 {
        return 0.0;
    }

    let mut detector = PitchDetector::new(sample_rate);
    let input = unsafe { std::slice::from_raw_parts(samples, length as usize) };

    if let Some((pitch, _confidence)) = detector.detect_frame(input) {
        pitch.to_frequency()
    } else {
        0.0
    }
}

/// Detect pitch and return MIDI note number
/// Returns -1 if no pitch detected
#[unsafe(no_mangle)]
pub extern "C" fn pitch_detect_midi(samples: *const f64, length: u32, sample_rate: f64) -> i32 {
    use rf_dsp::pitch::PitchDetector;

    if samples.is_null() || length == 0 {
        return -1;
    }

    let mut detector = PitchDetector::new(sample_rate);
    let input = unsafe { std::slice::from_raw_parts(samples, length as usize) };

    if let Some((pitch, _confidence)) = detector.detect_frame(input) {
        pitch.midi_note as i32
    } else {
        -1
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Free a string allocated by engine functions
#[unsafe(no_mangle)]
pub extern "C" fn engine_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Clear all data (reset to empty state)
#[unsafe(no_mangle)]
pub extern "C" fn engine_clear_all() {
    PLAYBACK_ENGINE.stop();
    PLAYBACK_ENGINE.cache().clear();
    TRACK_MANAGER.clear();
    WAVEFORM_CACHE.clear();
    IMPORTED_AUDIO.write().clear();
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO STREAM FFI (cpal device control)
// ═══════════════════════════════════════════════════════════════════════════

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;

static AUDIO_STREAM_RUNNING: AtomicBool = AtomicBool::new(false);

lazy_static::lazy_static! {
    static ref AUDIO_THREAD_HANDLE: parking_lot::Mutex<Option<(thread::JoinHandle<()>, mpsc::Sender<()>)>> =
        parking_lot::Mutex::new(None);
}

/// Start the audio output stream (cpal device)
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_start_playback() -> i32 {
    if AUDIO_STREAM_RUNNING.load(Ordering::Acquire) {
        return 1; // Already running
    }

    // Create channel for shutdown signal
    let (shutdown_tx, shutdown_rx) = mpsc::channel::<()>();

    // Spawn audio thread (cpal::Stream must stay on one thread)
    let handle = thread::spawn(move || {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

        let host = cpal::default_host();
        let device = match host.default_output_device() {
            Some(d) => d,
            None => {
                log::error!("No audio output device found");
                return;
            }
        };

        let config = match device.default_output_config() {
            Ok(c) => c,
            Err(e) => {
                log::error!("Failed to get audio config: {}", e);
                return;
            }
        };

        let channels = config.channels() as usize;

        log::info!(
            "Starting audio stream: {} Hz, {} channels",
            config.sample_rate().0,
            channels
        );

        // Pre-allocate processing buffers
        let mut output_l = vec![0.0f64; 4096];
        let mut output_r = vec![0.0f64; 4096];

        let stream = match device.build_output_stream(
            &config.into(),
            move |data: &mut [f32], _| {
                let frames = data.len() / channels;

                // Ensure buffers are large enough
                if output_l.len() < frames {
                    output_l.resize(frames, 0.0);
                    output_r.resize(frames, 0.0);
                }

                // Process audio from engine
                PLAYBACK_ENGINE.process(&mut output_l[..frames], &mut output_r[..frames]);

                // Convert to f32 output
                for i in 0..frames {
                    let idx = i * channels;
                    if channels >= 2 {
                        data[idx] = output_l[i] as f32;
                        data[idx + 1] = output_r[i] as f32;
                    } else if channels == 1 {
                        data[idx] = ((output_l[i] + output_r[i]) * 0.5) as f32;
                    }
                }
            },
            |err| log::error!("Audio stream error: {}", err),
            None,
        ) {
            Ok(s) => s,
            Err(e) => {
                log::error!("Failed to build audio stream: {}", e);
                return;
            }
        };

        if let Err(e) = stream.play() {
            log::error!("Failed to start audio stream: {}", e);
            return;
        }

        log::info!("Audio stream started successfully");
        AUDIO_STREAM_RUNNING.store(true, Ordering::Release);

        // Wait for shutdown signal
        let _ = shutdown_rx.recv();

        // Stream automatically stopped when dropped
        log::info!("Audio stream thread exiting");
    });

    // Store handle
    *AUDIO_THREAD_HANDLE.lock() = Some((handle, shutdown_tx));

    // Wait a bit for thread to start
    std::thread::sleep(std::time::Duration::from_millis(50));

    if AUDIO_STREAM_RUNNING.load(Ordering::Acquire) {
        1
    } else {
        0
    }
}

/// Stop the audio output stream
#[unsafe(no_mangle)]
pub extern "C" fn engine_stop_playback() {
    if !AUDIO_STREAM_RUNNING.load(Ordering::Acquire) {
        return;
    }

    AUDIO_STREAM_RUNNING.store(false, Ordering::Release);
    PLAYBACK_ENGINE.pause();

    // Send shutdown signal and wait for thread
    if let Some((handle, shutdown_tx)) = AUDIO_THREAD_HANDLE.lock().take() {
        let _ = shutdown_tx.send(());
        let _ = handle.join();
    }

    log::info!("Audio stream stopped");
}

/// Check if audio stream is running
#[unsafe(no_mangle)]
pub extern "C" fn engine_is_playback_running() -> i32 {
    if AUDIO_STREAM_RUNNING.load(Ordering::Relaxed) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNDO/REDO FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Undo last action
/// Returns 1 if action was undone, 0 if nothing to undo
#[unsafe(no_mangle)]
pub extern "C" fn engine_undo() -> i32 {
    let mut manager = UNDO_MANAGER.write();
    if manager.undo() {
        log::debug!("Undo successful");
        1
    } else {
        log::debug!("Nothing to undo");
        0
    }
}

/// Redo last undone action
/// Returns 1 if action was redone, 0 if nothing to redo
#[unsafe(no_mangle)]
pub extern "C" fn engine_redo() -> i32 {
    let mut manager = UNDO_MANAGER.write();
    if manager.redo() {
        log::debug!("Redo successful");
        1
    } else {
        log::debug!("Nothing to redo");
        0
    }
}

/// Check if undo is available
#[unsafe(no_mangle)]
pub extern "C" fn engine_can_undo() -> i32 {
    let manager = UNDO_MANAGER.read();
    if manager.can_undo() { 1 } else { 0 }
}

/// Check if redo is available
#[unsafe(no_mangle)]
pub extern "C" fn engine_can_redo() -> i32 {
    let manager = UNDO_MANAGER.read();
    if manager.can_redo() { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROJECT SAVE/LOAD FFI (DEPRECATED - use rf-bridge/api.rs for Flutter)
// ═══════════════════════════════════════════════════════════════════════════

/// Save project to path (legacy C FFI - use rf-bridge for Flutter)
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::save_project for Flutter")]
pub extern "C" fn engine_save_project(path: *const c_char) -> i32 {
    let path_str = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => return 0,
    };

    log::info!("Saving project to: {}", path_str);
    // C FFI stub - Flutter uses rf-bridge::api::save_project
    1
}

/// Load project from path (legacy C FFI - use rf-bridge for Flutter)
/// Returns 1 on success, 0 on failure
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::load_project for Flutter")]
pub extern "C" fn engine_load_project(path: *const c_char) -> i32 {
    let path_str = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => return 0,
    };

    log::info!("Loading project from: {}", path_str);
    // C FFI stub - Flutter uses rf-bridge::api::load_project
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// PROJECT DIRTY STATE FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Check if project has unsaved changes
/// Returns 1 if modified, 0 if clean
#[unsafe(no_mangle)]
pub extern "C" fn engine_project_is_modified() -> i32 {
    if PROJECT_STATE.is_modified() { 1 } else { 0 }
}

/// Mark project as dirty (has unsaved changes)
#[unsafe(no_mangle)]
pub extern "C" fn engine_project_mark_dirty() {
    PROJECT_STATE.mark_dirty();
}

/// Mark project as clean (just saved)
#[unsafe(no_mangle)]
pub extern "C" fn engine_project_mark_clean() {
    PROJECT_STATE.mark_clean();
}

/// Set project file path (empty string = None)
#[unsafe(no_mangle)]
pub extern "C" fn engine_project_set_file_path(path: *const c_char) {
    let path_opt = unsafe { cstr_to_string(path) }.filter(|s| !s.is_empty());
    PROJECT_STATE.set_file_path(path_opt);
}

/// Get project file path (returns null if no path set)
/// Caller must NOT free the returned string (static lifetime)
#[unsafe(no_mangle)]
pub extern "C" fn engine_project_get_file_path() -> *const c_char {
    use std::ffi::CString;
    use std::sync::OnceLock;

    static LAST_PATH: OnceLock<parking_lot::Mutex<Option<CString>>> = OnceLock::new();
    let mutex = LAST_PATH.get_or_init(|| parking_lot::Mutex::new(None));

    match PROJECT_STATE.file_path() {
        Some(path) => {
            let c_str = CString::new(path).unwrap_or_default();
            let ptr = c_str.as_ptr();
            *mutex.lock() = Some(c_str);
            ptr
        }
        None => std::ptr::null(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Get memory usage in MB
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_memory_usage() -> f32 {
    // Approximate memory usage from caches
    let audio_cache_bytes = PLAYBACK_ENGINE.cache().memory_usage();
    let waveform_cache_bytes = WAVEFORM_CACHE.memory_usage();
    let imported_audio_bytes: usize = IMPORTED_AUDIO
        .read()
        .values()
        .map(|a| a.samples.len() * std::mem::size_of::<f32>())
        .sum();

    let total_bytes = audio_cache_bytes + waveform_cache_bytes + imported_audio_bytes;
    (total_bytes as f32) / (1024.0 * 1024.0)
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    /// Per-track EQ processors
    static ref EQ_PROCESSORS: parking_lot::RwLock<std::collections::HashMap<u32, crate::dsp_wrappers::ProEqWrapper>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Get or create EQ processor for track
fn get_or_create_eq(
    track_id: u32,
) -> parking_lot::RwLockWriteGuard<
    'static,
    std::collections::HashMap<u32, crate::dsp_wrappers::ProEqWrapper>,
> {
    let mut eqs = EQ_PROCESSORS.write();
    if !eqs.contains_key(&track_id) {
        eqs.insert(track_id, crate::dsp_wrappers::ProEqWrapper::new(48000.0));
    }
    eqs
}

/// Set EQ band enabled
#[unsafe(no_mangle)]
pub extern "C" fn eq_set_band_enabled(track_id: u32, band_index: u8, enabled: i32) -> i32 {
    let mut eqs = get_or_create_eq(track_id);
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_enabled(band_index as usize, enabled != 0);
        log::debug!(
            "EQ track {} band {} enabled: {}",
            track_id,
            band_index,
            enabled != 0
        );
        1
    } else {
        0
    }
}

/// Set EQ band frequency
#[unsafe(no_mangle)]
pub extern "C" fn eq_set_band_frequency(track_id: u32, band_index: u8, frequency: f64) -> i32 {
    let mut eqs = get_or_create_eq(track_id);
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_frequency(band_index as usize, frequency);
        log::debug!(
            "EQ track {} band {} freq: {} Hz",
            track_id,
            band_index,
            frequency
        );
        1
    } else {
        0
    }
}

/// Set EQ band gain
#[unsafe(no_mangle)]
pub extern "C" fn eq_set_band_gain(track_id: u32, band_index: u8, gain: f64) -> i32 {
    let mut eqs = get_or_create_eq(track_id);
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_gain(band_index as usize, gain);
        log::debug!(
            "EQ track {} band {} gain: {} dB",
            track_id,
            band_index,
            gain
        );
        1
    } else {
        0
    }
}

/// Set EQ band Q
#[unsafe(no_mangle)]
pub extern "C" fn eq_set_band_q(track_id: u32, band_index: u8, q: f64) -> i32 {
    let mut eqs = get_or_create_eq(track_id);
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_q(band_index as usize, q);
        log::debug!("EQ track {} band {} Q: {}", track_id, band_index, q);
        1
    } else {
        0
    }
}

/// Set EQ bypass
#[unsafe(no_mangle)]
pub extern "C" fn eq_set_bypass(track_id: u32, bypass: i32) -> i32 {
    let mut eqs = get_or_create_eq(track_id);
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_bypass(bypass != 0);
        log::debug!("EQ track {} bypass: {}", track_id, bypass != 0);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER BUS FFI (with expected names from Flutter)
// ═══════════════════════════════════════════════════════════════════════════

/// Set bus volume (dB)
#[unsafe(no_mangle)]
pub extern "C" fn mixer_set_bus_volume(bus_id: u32, volume_db: f64) -> i32 {
    // Convert dB to linear
    let linear = if volume_db <= -60.0 {
        0.0
    } else {
        10.0_f64.powf(volume_db / 20.0)
    };
    PLAYBACK_ENGINE.set_bus_volume(bus_id as usize, linear);
    1
}

/// Set bus mute
#[unsafe(no_mangle)]
pub extern "C" fn mixer_set_bus_mute(bus_id: u32, muted: i32) -> i32 {
    PLAYBACK_ENGINE.set_bus_mute(bus_id as usize, muted != 0);
    1
}

/// Set bus solo
#[unsafe(no_mangle)]
pub extern "C" fn mixer_set_bus_solo(bus_id: u32, solo: i32) -> i32 {
    PLAYBACK_ENGINE.set_bus_solo(bus_id as usize, solo != 0);
    1
}

/// Set bus pan
#[unsafe(no_mangle)]
pub extern "C" fn mixer_set_bus_pan(bus_id: u32, pan: f64) -> i32 {
    PLAYBACK_ENGINE.set_bus_pan(bus_id as usize, pan);
    1
}

/// Set master volume (dB)
#[unsafe(no_mangle)]
pub extern "C" fn mixer_set_master_volume(volume_db: f64) -> i32 {
    let linear = if volume_db <= -60.0 {
        0.0
    } else {
        10.0_f64.powf(volume_db / 20.0)
    };
    PLAYBACK_ENGINE.set_master_volume(linear);
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PROCESSING FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Normalize clip to target dB
#[unsafe(no_mangle)]
pub extern "C" fn clip_normalize(clip_id: u64, target_db: f64) -> i32 {
    log::debug!("Normalize clip {} to {} dB", clip_id, target_db);

    // Get clip info
    let clip = match TRACK_MANAGER.get_clip(ClipId(clip_id)) {
        Some(c) => c,
        None => {
            log::error!("Clip {} not found for normalization", clip_id);
            return 0;
        }
    };

    // Load or get cached audio
    let audio = IMPORTED_AUDIO
        .read()
        .get(&ClipId(clip_id))
        .cloned()
        .or_else(|| {
            // Try to load from source file
            match AudioImporter::import(std::path::Path::new(&clip.source_file)) {
                Ok(audio) => {
                    let arc = Arc::new(audio);
                    IMPORTED_AUDIO
                        .write()
                        .insert(ClipId(clip_id), Arc::clone(&arc));
                    Some(arc)
                }
                Err(e) => {
                    log::error!("Failed to load audio for normalization: {}", e);
                    None
                }
            }
        });

    let audio = match audio {
        Some(a) => a,
        None => return 0,
    };

    // Find peak level within clip region
    let sample_rate = audio.sample_rate as f64;
    let source_offset_samples = (clip.source_offset * sample_rate) as usize;
    let duration_samples = (clip.source_duration * sample_rate) as usize;
    let end_sample = (source_offset_samples + duration_samples).min(audio.sample_count);

    let mut peak: f32 = 0.0;
    let channels = audio.channels as usize;

    for frame in source_offset_samples..end_sample {
        for ch in 0..channels {
            let sample_idx = frame * channels + ch;
            if sample_idx < audio.samples.len() {
                let sample = audio.samples[sample_idx].abs();
                if sample > peak {
                    peak = sample;
                }
            }
        }
    }

    if peak < 1e-6 {
        log::warn!(
            "Clip {} has near-zero peak level, skipping normalization",
            clip_id
        );
        return 1;
    }

    // Calculate gain needed to reach target
    let peak_db = 20.0 * (peak as f64).log10();
    let gain_db = target_db - peak_db;
    let gain_linear = 10.0_f64.powf(gain_db / 20.0);

    log::info!(
        "Normalizing clip {}: peak={:.2} dB, applying {:.2} dB gain",
        clip_id,
        peak_db,
        gain_db
    );

    // Apply gain to clip
    TRACK_MANAGER.update_clip(ClipId(clip_id), |c| {
        c.gain *= gain_linear;
        c.gain = c.gain.clamp(0.001, 10.0); // Limit to reasonable range
    });

    1
}

/// Reverse clip audio
/// This sets a flag on the clip to play audio in reverse
#[unsafe(no_mangle)]
pub extern "C" fn clip_reverse(clip_id: u64) -> i32 {
    log::debug!("Reverse clip {}", clip_id);

    // Check if clip exists
    let clip = TRACK_MANAGER.get_clip(ClipId(clip_id));
    if clip.is_none() {
        log::error!("Clip {} not found for reverse", clip_id);
        return 0;
    }

    // Toggle reversed state
    TRACK_MANAGER.update_clip(ClipId(clip_id), |c| {
        c.reversed = !c.reversed;
        log::info!("Clip {} reversed: {}", clip_id, c.reversed);
    });

    1
}

/// Apply fade in to clip
#[unsafe(no_mangle)]
pub extern "C" fn clip_fade_in(clip_id: u64, duration_sec: f64, curve_type: u8) -> i32 {
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.fade_in = duration_sec;
    });
    log::debug!(
        "Fade in clip {} for {} sec, curve {}",
        clip_id,
        duration_sec,
        curve_type
    );
    1
}

/// Apply fade out to clip
#[unsafe(no_mangle)]
pub extern "C" fn clip_fade_out(clip_id: u64, duration_sec: f64, curve_type: u8) -> i32 {
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.fade_out = duration_sec;
    });
    log::debug!(
        "Fade out clip {} for {} sec, curve {}",
        clip_id,
        duration_sec,
        curve_type
    );
    1
}

/// Apply gain to clip (dB)
#[unsafe(no_mangle)]
pub extern "C" fn clip_apply_gain(clip_id: u64, gain_db: f64) -> i32 {
    let linear = 10.0_f64.powf(gain_db / 20.0);
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.gain *= linear;
        clip.gain = clip.gain.clamp(0.0, 4.0);
    });
    log::debug!("Apply {} dB gain to clip {}", gain_db, clip_id);
    1
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT FFI (additional)
// ═══════════════════════════════════════════════════════════════════════════

/// Rename track
#[unsafe(no_mangle)]
pub extern "C" fn track_rename(track_id: u64, name: *const c_char) -> i32 {
    engine_set_track_name(track_id, name)
}

/// Duplicate track
/// Returns new track ID or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn track_duplicate(track_id: u64) -> u64 {
    let original = match TRACK_MANAGER.get_track(TrackId(track_id)) {
        Some(t) => t,
        None => return 0,
    };

    let new_name = format!("{} (copy)", original.name);
    let new_id = TRACK_MANAGER.create_track(&new_name, original.color, original.output_bus);

    // Copy track settings
    TRACK_MANAGER.update_track(new_id, |track| {
        track.volume = original.volume;
        track.pan = original.pan;
        track.muted = original.muted;
    });

    // Copy all clips from original track
    let clips = TRACK_MANAGER.get_clips_for_track(TrackId(track_id));
    for clip in clips {
        let mut new_clip = Clip::new(
            new_id,
            &format!("{} (copy)", clip.name),
            &clip.source_file,
            clip.start_time,
            clip.duration,
        );
        new_clip.source_offset = clip.source_offset;
        new_clip.source_duration = clip.source_duration;
        new_clip.fade_in = clip.fade_in;
        new_clip.fade_out = clip.fade_out;
        new_clip.gain = clip.gain;
        TRACK_MANAGER.add_clip(new_clip);
    }

    log::debug!("Duplicated track {} -> {}", track_id, new_id.0);
    new_id.0
}

/// Set track color
#[unsafe(no_mangle)]
pub extern "C" fn track_set_color(track_id: u64, color: u32) -> i32 {
    engine_set_track_color(track_id, color)
}

// ═══════════════════════════════════════════════════════════════════════════
// DYNAMIC ROUTING FFI
// ═══════════════════════════════════════════════════════════════════════════

use crate::routing::{ChannelId, ChannelKind, OutputDestination, RoutingGraph};

lazy_static::lazy_static! {
    static ref ROUTING_GRAPH: RwLock<RoutingGraph> = RwLock::new(RoutingGraph::new(256));
}

/// Create a new bus channel
/// Returns channel ID
#[unsafe(no_mangle)]
pub extern "C" fn routing_create_bus(name: *const c_char) -> u32 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Bus".to_string());
    ROUTING_GRAPH.write().create_bus(&name).0
}

/// Create a new aux channel (for sends/effects)
/// Returns channel ID
#[unsafe(no_mangle)]
pub extern "C" fn routing_create_aux(name: *const c_char) -> u32 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Aux".to_string());
    ROUTING_GRAPH.write().create_aux(&name).0
}

/// Create a new audio track channel
/// Returns channel ID
#[unsafe(no_mangle)]
pub extern "C" fn routing_create_audio(name: *const c_char) -> u32 {
    let name = unsafe { cstr_to_string(name) };
    ROUTING_GRAPH
        .write()
        .create_channel(ChannelKind::Audio, name.as_deref())
        .0
}

/// Delete a channel
/// Returns 1 on success, 0 if channel not found or is master
#[unsafe(no_mangle)]
pub extern "C" fn routing_delete_channel(channel_id: u32) -> i32 {
    if ROUTING_GRAPH.write().delete_channel(ChannelId(channel_id)) {
        1
    } else {
        0
    }
}

/// Set channel output to master
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_output_master(channel_id: u32) -> i32 {
    match ROUTING_GRAPH
        .write()
        .set_output(ChannelId(channel_id), OutputDestination::Master)
    {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

/// Set channel output to another channel (bus/aux)
/// Returns 1 on success, 0 on error (cycle, not found, etc)
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_output_channel(from_id: u32, to_id: u32) -> i32 {
    match ROUTING_GRAPH.write().set_output(
        ChannelId(from_id),
        OutputDestination::Channel(ChannelId(to_id)),
    ) {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

/// Add send from channel to aux/bus
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn routing_add_send(from_id: u32, to_id: u32, pre_fader: i32) -> i32 {
    match ROUTING_GRAPH
        .write()
        .add_send(ChannelId(from_id), ChannelId(to_id), pre_fader != 0)
    {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

/// Remove send by index
#[unsafe(no_mangle)]
pub extern "C" fn routing_remove_send(channel_id: u32, send_index: usize) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.write().get_mut(ChannelId(channel_id)) {
        channel.remove_send(send_index);
        1
    } else {
        0
    }
}

/// Set channel fader level in dB
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_fader(channel_id: u32, db: f64) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.write().get_mut(ChannelId(channel_id)) {
        channel.set_fader(db);
        1
    } else {
        0
    }
}

/// Get channel fader level in dB
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_fader(channel_id: u32) -> f64 {
    ROUTING_GRAPH
        .read()
        .get(ChannelId(channel_id))
        .map(|c| c.fader_db())
        .unwrap_or(0.0)
}

/// Set channel pan (-1.0 to 1.0)
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_pan(channel_id: u32, pan: f64) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.write().get_mut(ChannelId(channel_id)) {
        channel.set_pan(pan);
        1
    } else {
        0
    }
}

/// Set channel mute
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_mute(channel_id: u32, muted: i32) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.read().get(ChannelId(channel_id)) {
        channel.set_mute(muted != 0);
        1
    } else {
        0
    }
}

/// Set channel solo
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_solo(channel_id: u32, soloed: i32) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.read().get(ChannelId(channel_id)) {
        channel.set_solo(soloed != 0);
        1
    } else {
        0
    }
}

/// Get channel count (excluding master)
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_channel_count() -> usize {
    ROUTING_GRAPH.read().channel_count()
}

/// Get all channel IDs (fills buffer)
/// Returns actual count written
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_all_channels(out_ids: *mut u32, max_count: usize) -> usize {
    if out_ids.is_null() {
        return 0;
    }

    let graph = ROUTING_GRAPH.read();
    let ids = graph.all_channel_ids();
    let count = ids.len().min(max_count);

    unsafe {
        for (i, id) in ids.iter().take(count).enumerate() {
            *out_ids.add(i) = id.0;
        }
    }
    count
}

/// Get channel kind (0=Audio, 1=Bus, 2=Aux, 3=VCA, 4=Master)
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_channel_kind(channel_id: u32) -> u8 {
    ROUTING_GRAPH
        .read()
        .get(ChannelId(channel_id))
        .map(|c| match c.kind {
            ChannelKind::Audio => 0,
            ChannelKind::Bus => 1,
            ChannelKind::Aux => 2,
            ChannelKind::Vca => 3,
            ChannelKind::Master => 4,
        })
        .unwrap_or(255)
}

/// Set channel name
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_name(channel_id: u32, name: *const c_char) -> i32 {
    let name = match unsafe { cstr_to_string(name) } {
        Some(n) => n,
        None => return 0,
    };

    if let Some(channel) = ROUTING_GRAPH.write().get_mut(ChannelId(channel_id)) {
        channel.name = name;
        1
    } else {
        0
    }
}

/// Set channel color
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_color(channel_id: u32, color: u32) -> i32 {
    if let Some(channel) = ROUTING_GRAPH.write().get_mut(ChannelId(channel_id)) {
        channel.color = color;
        1
    } else {
        0
    }
}

/// Process routing graph (updates topological sort if needed)
#[unsafe(no_mangle)]
pub extern "C" fn routing_process() {
    ROUTING_GRAPH.write().process();
}

/// Get master channel output (fills stereo buffers)
/// Returns number of samples written
#[unsafe(no_mangle)]
pub extern "C" fn routing_get_output(
    out_left: *mut f64,
    out_right: *mut f64,
    max_samples: usize,
) -> usize {
    if out_left.is_null() || out_right.is_null() {
        return 0;
    }

    let graph = ROUTING_GRAPH.read();
    let (left, right) = graph.get_output();
    let count = left.len().min(right.len()).min(max_samples);

    unsafe {
        std::ptr::copy_nonoverlapping(left.as_ptr(), out_left, count);
        std::ptr::copy_nonoverlapping(right.as_ptr(), out_right, count);
    }
    count
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA FADER FFI
// ═══════════════════════════════════════════════════════════════════════════

use crate::groups::{GroupManager, LinkMode, LinkParameter};

lazy_static::lazy_static! {
    static ref GROUP_MANAGER: RwLock<GroupManager> = RwLock::new(GroupManager::new());
}

/// Create a new VCA fader
/// Returns VCA ID
#[unsafe(no_mangle)]
pub extern "C" fn vca_create(name: *const c_char) -> u64 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "VCA".to_string());
    GROUP_MANAGER.write().create_vca(&name)
}

/// Delete a VCA fader
#[unsafe(no_mangle)]
pub extern "C" fn vca_delete(vca_id: u64) -> i32 {
    GROUP_MANAGER.write().delete_vca(vca_id);
    1
}

/// Add track to VCA
#[unsafe(no_mangle)]
pub extern "C" fn vca_add_track(vca_id: u64, track_id: u64) -> i32 {
    GROUP_MANAGER.write().add_to_vca(vca_id, track_id);
    1
}

/// Remove track from VCA
#[unsafe(no_mangle)]
pub extern "C" fn vca_remove_track(vca_id: u64, track_id: u64) -> i32 {
    GROUP_MANAGER.write().remove_from_vca(vca_id, track_id);
    1
}

/// Set VCA level (dB)
#[unsafe(no_mangle)]
pub extern "C" fn vca_set_level(vca_id: u64, level_db: f64) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(vca) = mgr.vcas.get_mut(&vca_id) {
        vca.set_level(level_db);
        1
    } else {
        0
    }
}

/// Get VCA level (dB)
#[unsafe(no_mangle)]
pub extern "C" fn vca_get_level(vca_id: u64) -> f64 {
    GROUP_MANAGER
        .read()
        .vcas
        .get(&vca_id)
        .map(|v| v.level_db)
        .unwrap_or(0.0)
}

/// Set VCA mute
#[unsafe(no_mangle)]
pub extern "C" fn vca_set_mute(vca_id: u64, muted: i32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(vca) = mgr.vcas.get_mut(&vca_id) {
        vca.muted = muted != 0;
        1
    } else {
        0
    }
}

/// Set VCA solo
#[unsafe(no_mangle)]
pub extern "C" fn vca_set_solo(vca_id: u64, soloed: i32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(vca) = mgr.vcas.get_mut(&vca_id) {
        vca.soloed = soloed != 0;
        1
    } else {
        0
    }
}

/// Get VCA contribution for track (total dB from all VCAs)
#[unsafe(no_mangle)]
pub extern "C" fn vca_get_track_contribution(track_id: u64) -> f64 {
    GROUP_MANAGER.read().get_vca_contribution(track_id)
}

/// Check if track is muted by any VCA
#[unsafe(no_mangle)]
pub extern "C" fn vca_is_track_muted(track_id: u64) -> i32 {
    if GROUP_MANAGER.read().is_vca_muted(track_id) {
        1
    } else {
        0
    }
}

/// Set VCA color
#[unsafe(no_mangle)]
pub extern "C" fn vca_set_color(vca_id: u64, color: u32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(vca) = mgr.vcas.get_mut(&vca_id) {
        vca.color = color;
        1
    } else {
        0
    }
}

/// Set VCA trim for specific track
#[unsafe(no_mangle)]
pub extern "C" fn vca_set_trim(vca_id: u64, track_id: u64, trim_db: f64) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(vca) = mgr.vcas.get_mut(&vca_id) {
        vca.set_trim(track_id, trim_db);
        1
    } else {
        0
    }
}

/// Get VCA member count
#[unsafe(no_mangle)]
pub extern "C" fn vca_get_member_count(vca_id: u64) -> usize {
    GROUP_MANAGER
        .read()
        .vcas
        .get(&vca_id)
        .map(|v| v.members.len())
        .unwrap_or(0)
}

/// Get VCA member track IDs (fills buffer)
/// Returns actual count written
#[unsafe(no_mangle)]
pub extern "C" fn vca_get_members(vca_id: u64, out_track_ids: *mut u64, max_count: usize) -> usize {
    if out_track_ids.is_null() {
        return 0;
    }

    let mgr = GROUP_MANAGER.read();
    if let Some(vca) = mgr.vcas.get(&vca_id) {
        let members: Vec<u64> = vca.members.iter().copied().collect();
        let count = members.len().min(max_count);
        unsafe {
            for (i, &id) in members.iter().take(count).enumerate() {
                *out_track_ids.add(i) = id;
            }
        }
        count
    } else {
        0
    }
}

/// Get all VCA IDs (fills buffer)
/// Returns actual count written
#[unsafe(no_mangle)]
pub extern "C" fn vca_get_all(out_vca_ids: *mut u64, max_count: usize) -> usize {
    if out_vca_ids.is_null() {
        return 0;
    }

    let mgr = GROUP_MANAGER.read();
    let ids: Vec<u64> = mgr.vcas.keys().copied().collect();
    let count = ids.len().min(max_count);
    unsafe {
        for (i, &id) in ids.iter().take(count).enumerate() {
            *out_vca_ids.add(i) = id;
        }
    }
    count
}

// ═══════════════════════════════════════════════════════════════════════════
// GROUP LINKING FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Create a new group
/// Returns Group ID
#[unsafe(no_mangle)]
pub extern "C" fn group_create(name: *const c_char) -> u64 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Group".to_string());
    GROUP_MANAGER.write().create_group(&name)
}

/// Delete a group
#[unsafe(no_mangle)]
pub extern "C" fn group_delete(group_id: u64) -> i32 {
    GROUP_MANAGER.write().delete_group(group_id);
    1
}

/// Add track to group
#[unsafe(no_mangle)]
pub extern "C" fn group_add_track(group_id: u64, track_id: u64) -> i32 {
    GROUP_MANAGER.write().add_to_group(group_id, track_id);
    1
}

/// Remove track from group
#[unsafe(no_mangle)]
pub extern "C" fn group_remove_track(group_id: u64, track_id: u64) -> i32 {
    GROUP_MANAGER.write().remove_from_group(group_id, track_id);
    1
}

/// Set group active state
#[unsafe(no_mangle)]
pub extern "C" fn group_set_active(group_id: u64, active: i32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(group) = mgr.groups.get_mut(&group_id) {
        group.active = active != 0;
        1
    } else {
        0
    }
}

/// Set group link mode (0=Absolute, 1=Relative)
#[unsafe(no_mangle)]
pub extern "C" fn group_set_link_mode(group_id: u64, mode: u8) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(group) = mgr.groups.get_mut(&group_id) {
        group.link_mode = if mode == 0 {
            LinkMode::Absolute
        } else {
            LinkMode::Relative
        };
        1
    } else {
        0
    }
}

/// Toggle link parameter for group
/// param: 0=Volume, 1=Pan, 2=Mute, 3=Solo, 4=RecordArm, 5=Monitor, 6=InsertBypass, 7=SendLevel, 8=AutomationMode
#[unsafe(no_mangle)]
pub extern "C" fn group_toggle_link(group_id: u64, param: u8) -> i32 {
    let link_param = match param {
        0 => LinkParameter::Volume,
        1 => LinkParameter::Pan,
        2 => LinkParameter::Mute,
        3 => LinkParameter::Solo,
        4 => LinkParameter::RecordArm,
        5 => LinkParameter::Monitor,
        6 => LinkParameter::InsertBypass,
        7 => LinkParameter::SendLevel,
        8 => LinkParameter::AutomationMode,
        _ => return 0,
    };

    let mut mgr = GROUP_MANAGER.write();
    if let Some(group) = mgr.groups.get_mut(&group_id) {
        group.toggle_link(link_param);
        1
    } else {
        0
    }
}

/// Check if parameter is linked in group
#[unsafe(no_mangle)]
pub extern "C" fn group_is_param_linked(group_id: u64, param: u8) -> i32 {
    let link_param = match param {
        0 => LinkParameter::Volume,
        1 => LinkParameter::Pan,
        2 => LinkParameter::Mute,
        3 => LinkParameter::Solo,
        4 => LinkParameter::RecordArm,
        5 => LinkParameter::Monitor,
        6 => LinkParameter::InsertBypass,
        7 => LinkParameter::SendLevel,
        8 => LinkParameter::AutomationMode,
        _ => return 0,
    };

    GROUP_MANAGER
        .read()
        .groups
        .get(&group_id)
        .map(|g| if g.is_linked(link_param) { 1 } else { 0 })
        .unwrap_or(0)
}

/// Get linked tracks for a parameter change
/// Returns count of linked tracks
#[unsafe(no_mangle)]
pub extern "C" fn group_get_linked_tracks(
    source_track: u64,
    param: u8,
    out_track_ids: *mut u64,
    max_count: usize,
) -> usize {
    if out_track_ids.is_null() {
        return 0;
    }

    let link_param = match param {
        0 => LinkParameter::Volume,
        1 => LinkParameter::Pan,
        2 => LinkParameter::Mute,
        3 => LinkParameter::Solo,
        _ => return 0,
    };

    let mgr = GROUP_MANAGER.read();
    let linked = mgr.get_linked_tracks(source_track, link_param);
    let count = linked.len().min(max_count);

    unsafe {
        for (i, &id) in linked.iter().take(count).enumerate() {
            *out_track_ids.add(i) = id;
        }
    }
    count
}

/// Set group color
#[unsafe(no_mangle)]
pub extern "C" fn group_set_color(group_id: u64, color: u32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(group) = mgr.groups.get_mut(&group_id) {
        group.color = color;
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FOLDER TRACK FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Create a folder track
#[unsafe(no_mangle)]
pub extern "C" fn folder_create(folder_id: u64, name: *const c_char) -> i32 {
    let name = unsafe { cstr_to_string(name) }.unwrap_or_else(|| "Folder".to_string());
    GROUP_MANAGER.write().create_folder(folder_id, &name);
    1
}

/// Delete a folder track
#[unsafe(no_mangle)]
pub extern "C" fn folder_delete(folder_id: u64) -> i32 {
    GROUP_MANAGER.write().delete_folder(folder_id);
    1
}

/// Add child track to folder
#[unsafe(no_mangle)]
pub extern "C" fn folder_add_child(folder_id: u64, track_id: u64) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(folder) = mgr.folders.get_mut(&folder_id) {
        folder.add_child(track_id);
        1
    } else {
        0
    }
}

/// Remove child track from folder
#[unsafe(no_mangle)]
pub extern "C" fn folder_remove_child(folder_id: u64, track_id: u64) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(folder) = mgr.folders.get_mut(&folder_id) {
        folder.remove_child(track_id);
        1
    } else {
        0
    }
}

/// Toggle folder expanded state
#[unsafe(no_mangle)]
pub extern "C" fn folder_toggle(folder_id: u64) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(folder) = mgr.folders.get_mut(&folder_id) {
        folder.toggle();
        1
    } else {
        0
    }
}

/// Check if folder is expanded
#[unsafe(no_mangle)]
pub extern "C" fn folder_is_expanded(folder_id: u64) -> i32 {
    GROUP_MANAGER
        .read()
        .folders
        .get(&folder_id)
        .map(|f| if f.expanded { 1 } else { 0 })
        .unwrap_or(0)
}

/// Get folder children (fills buffer)
/// Returns actual count written
#[unsafe(no_mangle)]
pub extern "C" fn folder_get_children(
    folder_id: u64,
    out_track_ids: *mut u64,
    max_count: usize,
) -> usize {
    if out_track_ids.is_null() {
        return 0;
    }

    let mgr = GROUP_MANAGER.read();
    if let Some(folder) = mgr.folders.get(&folder_id) {
        let count = folder.children.len().min(max_count);
        unsafe {
            for (i, &id) in folder.children.iter().take(count).enumerate() {
                *out_track_ids.add(i) = id;
            }
        }
        count
    } else {
        0
    }
}

/// Get parent folder for track (returns folder ID or 0 if none)
#[unsafe(no_mangle)]
pub extern "C" fn folder_get_parent(track_id: u64) -> u64 {
    GROUP_MANAGER
        .read()
        .parent_folder(track_id)
        .map(|f| f.id)
        .unwrap_or(0)
}

/// Set folder color
#[unsafe(no_mangle)]
pub extern "C" fn folder_set_color(folder_id: u64, color: u32) -> i32 {
    let mut mgr = GROUP_MANAGER.write();
    if let Some(folder) = mgr.folders.get_mut(&folder_id) {
        folder.color = color;
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ELASTIC PRO (TIME STRETCHING)
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref ELASTIC_PROCESSORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::ElasticPro>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create time stretch processor for clip
#[unsafe(no_mangle)]
pub extern "C" fn elastic_create(clip_id: u32, sample_rate: f64) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    procs.insert(clip_id, rf_dsp::ElasticPro::new(sample_rate));
    1
}

/// Remove time stretch processor
#[unsafe(no_mangle)]
pub extern "C" fn elastic_remove(clip_id: u32) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if procs.remove(&clip_id).is_some() {
        1
    } else {
        0
    }
}

/// Set stretch ratio (0.1 to 10.0)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_ratio(clip_id: u32, ratio: f64) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        proc.set_stretch_ratio(ratio);
        1
    } else {
        0
    }
}

/// Set pitch shift in semitones (-24 to +24)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_pitch(clip_id: u32, semitones: f64) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        proc.set_pitch_shift(semitones);
        1
    } else {
        0
    }
}

/// Set quality preset (0=Preview, 1=Standard, 2=High, 3=Ultra)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_quality(clip_id: u32, quality: u8) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let q = match quality {
            0 => rf_dsp::StretchQuality::Preview,
            1 => rf_dsp::StretchQuality::Standard,
            2 => rf_dsp::StretchQuality::High,
            _ => rf_dsp::StretchQuality::Ultra,
        };
        proc.set_quality(q);
        1
    } else {
        0
    }
}

/// Set algorithm mode (0=Auto, 1=Polyphonic, 2=Monophonic, 3=Rhythmic, 4=Speech, 5=Creative)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_mode(clip_id: u32, mode: u8) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let m = match mode {
            0 => rf_dsp::StretchMode::Auto,
            1 => rf_dsp::StretchMode::Polyphonic,
            2 => rf_dsp::StretchMode::Monophonic,
            3 => rf_dsp::StretchMode::Rhythmic,
            4 => rf_dsp::StretchMode::Speech,
            _ => rf_dsp::StretchMode::Creative,
        };
        proc.set_mode(m);
        1
    } else {
        0
    }
}

/// Enable/disable STN decomposition
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_stn_enabled(clip_id: u32, enabled: i32) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let mut config = proc.config().clone();
        config.use_stn = enabled != 0;
        proc.set_config(config);
        1
    } else {
        0
    }
}

/// Enable/disable transient preservation
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_preserve_transients(clip_id: u32, enabled: i32) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let mut config = proc.config().clone();
        config.preserve_transients = enabled != 0;
        proc.set_config(config);
        1
    } else {
        0
    }
}

/// Enable/disable formant preservation
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_preserve_formants(clip_id: u32, enabled: i32) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let mut config = proc.config().clone();
        config.preserve_formants = enabled != 0;
        proc.set_config(config);
        1
    } else {
        0
    }
}

/// Set tonal threshold (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_tonal_threshold(clip_id: u32, threshold: f64) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let mut config = proc.config().clone();
        config.tonal_threshold = threshold.clamp(0.0, 1.0);
        proc.set_config(config);
        1
    } else {
        0
    }
}

/// Set transient threshold (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_set_transient_threshold(clip_id: u32, threshold: f64) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        let mut config = proc.config().clone();
        config.transient_threshold = threshold.clamp(0.0, 1.0);
        proc.set_config(config);
        1
    } else {
        0
    }
}

/// Process audio with time stretching
/// Returns number of output samples written
#[unsafe(no_mangle)]
pub extern "C" fn elastic_process(
    clip_id: u32,
    input: *const f64,
    input_len: u32,
    output: *mut f64,
    output_max_len: u32,
) -> u32 {
    if input.is_null() || output.is_null() || input_len == 0 {
        return 0;
    }

    let mut procs = ELASTIC_PROCESSORS.write();
    let proc = match procs.get_mut(&clip_id) {
        Some(p) => p,
        None => return 0,
    };

    let input_slice = unsafe { std::slice::from_raw_parts(input, input_len as usize) };
    let result = proc.process(input_slice);

    let copy_len = result.len().min(output_max_len as usize);
    let output_slice = unsafe { std::slice::from_raw_parts_mut(output, copy_len) };
    output_slice.copy_from_slice(&result[..copy_len]);

    copy_len as u32
}

/// Process stereo audio with time stretching
/// Returns number of output samples written (per channel)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_process_stereo(
    clip_id: u32,
    input_l: *const f64,
    input_r: *const f64,
    input_len: u32,
    output_l: *mut f64,
    output_r: *mut f64,
    output_max_len: u32,
) -> u32 {
    if input_l.is_null()
        || input_r.is_null()
        || output_l.is_null()
        || output_r.is_null()
        || input_len == 0
    {
        return 0;
    }

    let mut procs = ELASTIC_PROCESSORS.write();
    let proc = match procs.get_mut(&clip_id) {
        Some(p) => p,
        None => return 0,
    };

    let left_in = unsafe { std::slice::from_raw_parts(input_l, input_len as usize) };
    let right_in = unsafe { std::slice::from_raw_parts(input_r, input_len as usize) };

    let (left_out, right_out) = proc.process_stereo(left_in, right_in);

    let copy_len = left_out
        .len()
        .min(right_out.len())
        .min(output_max_len as usize);

    let left_slice = unsafe { std::slice::from_raw_parts_mut(output_l, copy_len) };
    let right_slice = unsafe { std::slice::from_raw_parts_mut(output_r, copy_len) };

    left_slice.copy_from_slice(&left_out[..copy_len]);
    right_slice.copy_from_slice(&right_out[..copy_len]);

    copy_len as u32
}

/// Get expected output length for given input length
#[unsafe(no_mangle)]
pub extern "C" fn elastic_get_output_length(clip_id: u32, input_len: u32) -> u32 {
    let procs = ELASTIC_PROCESSORS.read();
    if let Some(proc) = procs.get(&clip_id) {
        proc.output_length(input_len as usize) as u32
    } else {
        input_len
    }
}

/// Get current stretch ratio
#[unsafe(no_mangle)]
pub extern "C" fn elastic_get_ratio(clip_id: u32) -> f64 {
    let procs = ELASTIC_PROCESSORS.read();
    if let Some(proc) = procs.get(&clip_id) {
        proc.config().stretch_ratio
    } else {
        1.0
    }
}

/// Get current pitch shift
#[unsafe(no_mangle)]
pub extern "C" fn elastic_get_pitch(clip_id: u32) -> f64 {
    let procs = ELASTIC_PROCESSORS.read();
    if let Some(proc) = procs.get(&clip_id) {
        proc.config().pitch_shift
    } else {
        0.0
    }
}

/// Reset elastic processor state
#[unsafe(no_mangle)]
pub extern "C" fn elastic_reset(clip_id: u32) -> i32 {
    let mut procs = ELASTIC_PROCESSORS.write();
    if let Some(proc) = procs.get_mut(&clip_id) {
        proc.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PIANO ROLL FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref PIANO_ROLL_STATES: parking_lot::RwLock<std::collections::HashMap<u32, rf_core::PianoRollState>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create/get piano roll state for clip
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_create(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if !states.contains_key(&clip_id) {
        states.insert(clip_id, rf_core::PianoRollState::new(clip_id));
    }
    1
}

/// Remove piano roll state
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_remove(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    states.remove(&clip_id);
    1
}

/// Add note to piano roll
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_add_note(
    clip_id: u32,
    note: u8,
    start_tick: u64,
    duration: u64,
    velocity: u16,
) -> u64 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.add_note(note, start_tick, duration, velocity)
    } else {
        0
    }
}

/// Remove note by ID
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_remove_note(clip_id: u32, note_id: u64) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        if state.remove_note(note_id).is_some() {
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Select note
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_select(clip_id: u32, note_id: u64, add_to_selection: i32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.select(note_id, add_to_selection != 0);
        1
    } else {
        0
    }
}

/// Deselect all
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_deselect_all(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.deselect_all();
        1
    } else {
        0
    }
}

/// Select all
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_select_all(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.select_all();
        1
    } else {
        0
    }
}

/// Select rectangle
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_select_rect(
    clip_id: u32,
    tick_start: u64,
    tick_end: u64,
    note_low: u8,
    note_high: u8,
    add: i32,
) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.select_rect(tick_start, tick_end, note_low, note_high, add != 0);
        1
    } else {
        0
    }
}

/// Move selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_move_selected(clip_id: u32, delta_tick: i64, delta_note: i8) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.move_selected(delta_tick, delta_note);
        1
    } else {
        0
    }
}

/// Resize selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_resize_selected(
    clip_id: u32,
    delta_duration: i64,
    from_start: i32,
) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.resize_selected(delta_duration, from_start != 0);
        1
    } else {
        0
    }
}

/// Set velocity for selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_velocity(clip_id: u32, velocity: u16) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.set_selected_velocity(velocity);
        1
    } else {
        0
    }
}

/// Quantize selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_quantize(clip_id: u32, strength: f64) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.quantize_selected(strength);
        1
    } else {
        0
    }
}

/// Transpose selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_transpose(clip_id: u32, semitones: i8) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.transpose_selected(semitones);
        1
    } else {
        0
    }
}

/// Copy selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_copy(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.copy();
        1
    } else {
        0
    }
}

/// Cut selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_cut(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.cut();
        1
    } else {
        0
    }
}

/// Paste notes at position
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_paste(clip_id: u32, tick: u64) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.paste(tick);
        1
    } else {
        0
    }
}

/// Duplicate selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_duplicate(clip_id: u32, offset_ticks: u64) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.duplicate(offset_ticks);
        1
    } else {
        0
    }
}

/// Delete selected notes
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_delete_selected(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.remove_selected();
        1
    } else {
        0
    }
}

/// Undo
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_undo(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        if state.undo() { 1 } else { 0 }
    } else {
        0
    }
}

/// Redo
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_redo(clip_id: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        if state.redo() { 1 } else { 0 }
    } else {
        0
    }
}

/// Set grid division (0-7)
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_grid(clip_id: u32, grid_index: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.grid = match grid_index {
            0 => rf_core::GridDivision::Bar,
            1 => rf_core::GridDivision::Half,
            2 => rf_core::GridDivision::Quarter,
            3 => rf_core::GridDivision::Eighth,
            4 => rf_core::GridDivision::Sixteenth,
            5 => rf_core::GridDivision::ThirtySecond,
            6 => rf_core::GridDivision::EighthTriplet,
            7 => rf_core::GridDivision::SixteenthTriplet,
            _ => rf_core::GridDivision::Sixteenth,
        };
        1
    } else {
        0
    }
}

/// Set snap enabled
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_snap(clip_id: u32, enabled: i32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.snap_enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Set tool (0=Select, 1=Draw, 2=Erase, 3=Velocity, 4=Slice, 5=Glue, 6=Mute)
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_tool(clip_id: u32, tool_index: u32) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.tool = match tool_index {
            0 => rf_core::PianoRollTool::Select,
            1 => rf_core::PianoRollTool::Draw,
            2 => rf_core::PianoRollTool::Erase,
            3 => rf_core::PianoRollTool::Velocity,
            4 => rf_core::PianoRollTool::Slice,
            5 => rf_core::PianoRollTool::Glue,
            6 => rf_core::PianoRollTool::Mute,
            _ => rf_core::PianoRollTool::Select,
        };
        1
    } else {
        0
    }
}

/// Set clip length in ticks
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_length(clip_id: u32, length_ticks: u64) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.clip_length = length_ticks;
        1
    } else {
        0
    }
}

/// Get note count
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_get_note_count(clip_id: u32) -> u32 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        state.note_count() as u32
    } else {
        0
    }
}

/// Get selection count
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_get_selection_count(clip_id: u32) -> u32 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        state.selection_count() as u32
    } else {
        0
    }
}

/// Get note at index (returns data via out params)
/// Returns 1 if note exists, 0 otherwise
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_get_note(
    clip_id: u32,
    index: u32,
    out_id: *mut u64,
    out_note: *mut u8,
    out_start_tick: *mut u64,
    out_duration: *mut u64,
    out_velocity: *mut u16,
    out_selected: *mut i32,
    out_muted: *mut i32,
) -> i32 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        if let Some(note) = state.notes.get(index as usize) {
            unsafe {
                if !out_id.is_null() {
                    *out_id = note.id;
                }
                if !out_note.is_null() {
                    *out_note = note.note.note;
                }
                if !out_start_tick.is_null() {
                    *out_start_tick = note.note.start_tick;
                }
                if !out_duration.is_null() {
                    *out_duration = note.note.duration_ticks;
                }
                if !out_velocity.is_null() {
                    *out_velocity = note.note.velocity;
                }
                if !out_selected.is_null() {
                    *out_selected = if note.selected { 1 } else { 0 };
                }
                if !out_muted.is_null() {
                    *out_muted = if note.muted { 1 } else { 0 };
                }
            }
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Get note ID at position
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_note_at(clip_id: u32, tick: u64, note: u8) -> u64 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        state.note_id_at(tick, note).unwrap_or(0)
    } else {
        0
    }
}

/// Set view zoom
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_zoom(
    clip_id: u32,
    pixels_per_beat: f64,
    pixels_per_note: f64,
) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.view.pixels_per_beat = pixels_per_beat.clamp(20.0, 500.0);
        state.view.pixels_per_note = pixels_per_note.clamp(6.0, 40.0);
        1
    } else {
        0
    }
}

/// Set scroll position
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_set_scroll(clip_id: u32, scroll_tick: u64, scroll_note: u8) -> i32 {
    let mut states = PIANO_ROLL_STATES.write();
    if let Some(state) = states.get_mut(&clip_id) {
        state.view.scroll_x_tick = scroll_tick;
        state.view.scroll_y_note = scroll_note;
        1
    } else {
        0
    }
}

/// Can undo?
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_can_undo(clip_id: u32) -> i32 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        if state.can_undo() { 1 } else { 0 }
    } else {
        0
    }
}

/// Can redo?
#[unsafe(no_mangle)]
pub extern "C" fn piano_roll_can_redo(clip_id: u32) -> i32 {
    let states = PIANO_ROLL_STATES.read();
    if let Some(state) = states.get(&clip_id) {
        if state.can_redo() { 1 } else { 0 }
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// REVERB FFI - Convolution & Algorithmic
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref CONVOLUTION_REVERBS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::reverb::ConvolutionReverb>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref ALGORITHMIC_REVERBS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::reverb::AlgorithmicReverb>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// --- Convolution Reverb ---

/// Create convolution reverb for track
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut reverbs = CONVOLUTION_REVERBS.write();
    reverbs.insert(
        track_id,
        rf_dsp::reverb::ConvolutionReverb::new(sample_rate),
    );
    1
}

/// Remove convolution reverb
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_remove(track_id: u32) -> i32 {
    CONVOLUTION_REVERBS.write().remove(&track_id);
    1
}

/// Load impulse response from raw samples
/// ir_samples: interleaved stereo or mono samples
/// channel_count: 1 for mono, 2 for stereo
/// length: number of samples per channel
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_load_ir(
    track_id: u32,
    ir_samples: *const f64,
    channel_count: u32,
    length: u32,
) -> i32 {
    if ir_samples.is_null() || length == 0 {
        return 0;
    }

    let mut reverbs = CONVOLUTION_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        let samples =
            unsafe { std::slice::from_raw_parts(ir_samples, (length * channel_count) as usize) };

        if channel_count == 1 {
            reverb.load_ir_mono(samples);
        } else {
            // Deinterleave stereo
            let mut left = Vec::with_capacity(length as usize);
            let mut right = Vec::with_capacity(length as usize);
            for i in 0..length as usize {
                left.push(samples[i * 2]);
                right.push(samples[i * 2 + 1]);
            }
            reverb.load_ir(&left, &right);
        }
        1
    } else {
        0
    }
}

/// Set convolution reverb dry/wet mix (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut reverbs = CONVOLUTION_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Set convolution reverb predelay in ms
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_set_predelay(track_id: u32, predelay_ms: f64) -> i32 {
    let mut reverbs = CONVOLUTION_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_predelay(predelay_ms);
        1
    } else {
        0
    }
}

/// Reset convolution reverb state
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut reverbs = CONVOLUTION_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.reset();
        1
    } else {
        0
    }
}

/// Process stereo samples through convolution reverb
/// Returns 1 on success, 0 if reverb doesn't exist
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_process(
    track_id: u32,
    left: *mut f64,
    right: *mut f64,
    num_samples: u32,
) -> i32 {
    use rf_dsp::StereoProcessor;
    if left.is_null() || right.is_null() {
        return 0;
    }

    let mut reverbs = CONVOLUTION_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        let left_buf = unsafe { std::slice::from_raw_parts_mut(left, num_samples as usize) };
        let right_buf = unsafe { std::slice::from_raw_parts_mut(right, num_samples as usize) };
        reverb.process_block(left_buf, right_buf);
        1
    } else {
        0
    }
}

/// Get convolution reverb latency in samples
#[unsafe(no_mangle)]
pub extern "C" fn convolution_reverb_get_latency(track_id: u32) -> u32 {
    use rf_dsp::Processor;
    let reverbs = CONVOLUTION_REVERBS.read();
    if let Some(reverb) = reverbs.get(&track_id) {
        reverb.latency() as u32
    } else {
        0
    }
}

// --- Algorithmic Reverb ---

/// Create algorithmic reverb for track
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    reverbs.insert(
        track_id,
        rf_dsp::reverb::AlgorithmicReverb::new(sample_rate),
    );
    1
}

/// Remove algorithmic reverb
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_remove(track_id: u32) -> i32 {
    ALGORITHMIC_REVERBS.write().remove(&track_id);
    1
}

/// Set reverb type (0=Room, 1=Hall, 2=Plate, 3=Chamber, 4=Spring)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_type(track_id: u32, reverb_type: u32) -> i32 {
    use rf_dsp::reverb::ReverbType;
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        let rt = match reverb_type {
            0 => ReverbType::Room,
            1 => ReverbType::Hall,
            2 => ReverbType::Plate,
            3 => ReverbType::Chamber,
            4 => ReverbType::Spring,
            _ => ReverbType::Room,
        };
        reverb.set_type(rt);
        1
    } else {
        0
    }
}

/// Set room size (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_room_size(track_id: u32, size: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_room_size(size);
        1
    } else {
        0
    }
}

/// Set damping (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_damping(track_id: u32, damping: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_damping(damping);
        1
    } else {
        0
    }
}

/// Set stereo width (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_width(track_id: u32, width: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_width(width);
        1
    } else {
        0
    }
}

/// Set dry/wet mix (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Set predelay in ms (0-200ms)
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_set_predelay(track_id: u32, predelay_ms: f64) -> i32 {
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.set_predelay(predelay_ms);
        1
    } else {
        0
    }
}

/// Reset algorithmic reverb state
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        reverb.reset();
        1
    } else {
        0
    }
}

/// Process stereo samples through algorithmic reverb
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_process(
    track_id: u32,
    left: *mut f64,
    right: *mut f64,
    num_samples: u32,
) -> i32 {
    use rf_dsp::StereoProcessor;
    if left.is_null() || right.is_null() {
        return 0;
    }

    let mut reverbs = ALGORITHMIC_REVERBS.write();
    if let Some(reverb) = reverbs.get_mut(&track_id) {
        let left_buf = unsafe { std::slice::from_raw_parts_mut(left, num_samples as usize) };
        let right_buf = unsafe { std::slice::from_raw_parts_mut(right, num_samples as usize) };
        reverb.process_block(left_buf, right_buf);
        1
    } else {
        0
    }
}

/// Get algorithmic reverb latency in samples
#[unsafe(no_mangle)]
pub extern "C" fn algorithmic_reverb_get_latency(track_id: u32) -> u32 {
    use rf_dsp::Processor;
    let reverbs = ALGORITHMIC_REVERBS.read();
    if let Some(reverb) = reverbs.get(&track_id) {
        reverb.latency() as u32
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DELAY FFI - Simple, PingPong, MultiTap, Modulated
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SIMPLE_DELAYS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::delay::Delay>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref PING_PONG_DELAYS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::delay::PingPongDelay>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref MULTI_TAP_DELAYS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::delay::MultiTapDelay>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref MODULATED_DELAYS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::delay::ModulatedDelay>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// --- Simple Delay ---

/// Create simple delay for track
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_create(track_id: u32, sample_rate: f64, max_delay_ms: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    delays.insert(
        track_id,
        rf_dsp::delay::Delay::new(sample_rate, max_delay_ms),
    );
    1
}

/// Remove simple delay
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_remove(track_id: u32) -> i32 {
    SIMPLE_DELAYS.write().remove(&track_id);
    1
}

/// Set delay time in ms
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_time(track_id: u32, delay_ms: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_delay_ms(delay_ms);
        1
    } else {
        0
    }
}

/// Set feedback (0.0-0.99)
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_feedback(track_id: u32, feedback: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_feedback(feedback);
        1
    } else {
        0
    }
}

/// Set dry/wet mix (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Set highpass filter frequency
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_highpass(track_id: u32, freq: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_highpass(freq);
        1
    } else {
        0
    }
}

/// Set lowpass filter frequency
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_lowpass(track_id: u32, freq: f64) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_lowpass(freq);
        1
    } else {
        0
    }
}

/// Set filter enabled
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_set_filter_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_filter_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Reset simple delay
#[unsafe(no_mangle)]
pub extern "C" fn simple_delay_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut delays = SIMPLE_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.reset();
        1
    } else {
        0
    }
}

// --- Ping-Pong Delay ---

/// Create ping-pong delay
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_create(
    track_id: u32,
    sample_rate: f64,
    max_delay_ms: f64,
) -> i32 {
    let mut delays = PING_PONG_DELAYS.write();
    delays.insert(
        track_id,
        rf_dsp::delay::PingPongDelay::new(sample_rate, max_delay_ms),
    );
    1
}

/// Remove ping-pong delay
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_remove(track_id: u32) -> i32 {
    PING_PONG_DELAYS.write().remove(&track_id);
    1
}

/// Set ping-pong delay time
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_set_time(track_id: u32, delay_ms: f64) -> i32 {
    let mut delays = PING_PONG_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_delay_ms(delay_ms);
        1
    } else {
        0
    }
}

/// Set ping-pong feedback
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_set_feedback(track_id: u32, feedback: f64) -> i32 {
    let mut delays = PING_PONG_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_feedback(feedback);
        1
    } else {
        0
    }
}

/// Set ping-pong dry/wet
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut delays = PING_PONG_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Set ping-pong amount (0.0 = stereo, 1.0 = full ping-pong)
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_set_ping_pong(track_id: u32, amount: f64) -> i32 {
    let mut delays = PING_PONG_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_ping_pong(amount);
        1
    } else {
        0
    }
}

/// Reset ping-pong delay
#[unsafe(no_mangle)]
pub extern "C" fn ping_pong_delay_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut delays = PING_PONG_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.reset();
        1
    } else {
        0
    }
}

// --- Multi-Tap Delay ---

/// Create multi-tap delay
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_create(
    track_id: u32,
    sample_rate: f64,
    max_delay_ms: f64,
    num_taps: u32,
) -> i32 {
    let mut delays = MULTI_TAP_DELAYS.write();
    delays.insert(
        track_id,
        rf_dsp::delay::MultiTapDelay::new(sample_rate, max_delay_ms, num_taps as usize),
    );
    1
}

/// Remove multi-tap delay
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_remove(track_id: u32) -> i32 {
    MULTI_TAP_DELAYS.write().remove(&track_id);
    1
}

/// Set a specific tap
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_set_tap(
    track_id: u32,
    tap_index: u32,
    delay_ms: f64,
    level: f64,
    pan: f64,
) -> i32 {
    let mut delays = MULTI_TAP_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_tap(tap_index as usize, delay_ms, level, pan);
        1
    } else {
        0
    }
}

/// Set multi-tap feedback
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_set_feedback(track_id: u32, feedback: f64) -> i32 {
    let mut delays = MULTI_TAP_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_feedback(feedback);
        1
    } else {
        0
    }
}

/// Set multi-tap dry/wet
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut delays = MULTI_TAP_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Reset multi-tap delay
#[unsafe(no_mangle)]
pub extern "C" fn multi_tap_delay_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut delays = MULTI_TAP_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.reset();
        1
    } else {
        0
    }
}

// --- Modulated Delay (Chorus/Flanger) ---

/// Create modulated delay
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    delays.insert(track_id, rf_dsp::delay::ModulatedDelay::new(sample_rate));
    1
}

/// Create chorus preset
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_create_chorus(track_id: u32, sample_rate: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    delays.insert(track_id, rf_dsp::delay::ModulatedDelay::chorus(sample_rate));
    1
}

/// Create flanger preset
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_create_flanger(track_id: u32, sample_rate: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    delays.insert(
        track_id,
        rf_dsp::delay::ModulatedDelay::flanger(sample_rate),
    );
    1
}

/// Remove modulated delay
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_remove(track_id: u32) -> i32 {
    MODULATED_DELAYS.write().remove(&track_id);
    1
}

/// Set base delay time in ms
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_set_time(track_id: u32, delay_ms: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_delay_ms(delay_ms);
        1
    } else {
        0
    }
}

/// Set modulation depth in ms
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_set_mod_depth(track_id: u32, depth_ms: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_mod_depth_ms(depth_ms);
        1
    } else {
        0
    }
}

/// Set modulation rate in Hz
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_set_mod_rate(track_id: u32, rate_hz: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_mod_rate(rate_hz);
        1
    } else {
        0
    }
}

/// Set feedback (-0.99 to 0.99)
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_set_feedback(track_id: u32, feedback: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_feedback(feedback);
        1
    } else {
        0
    }
}

/// Set dry/wet mix
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_set_dry_wet(track_id: u32, mix: f64) -> i32 {
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.set_dry_wet(mix);
        1
    } else {
        0
    }
}

/// Reset modulated delay
#[unsafe(no_mangle)]
pub extern "C" fn modulated_delay_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut delays = MODULATED_DELAYS.write();
    if let Some(delay) = delays.get_mut(&track_id) {
        delay.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DYNAMICS FFI - Compressor, Limiter, Gate, Expander
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref COMPRESSORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::dynamics::StereoCompressor>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref LIMITERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::dynamics::TruePeakLimiter>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref GATES: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::dynamics::Gate>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref EXPANDERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::dynamics::Expander>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// --- Stereo Compressor ---

/// Create stereo compressor for track
#[unsafe(no_mangle)]
pub extern "C" fn compressor_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    comps.insert(
        track_id,
        rf_dsp::dynamics::StereoCompressor::new(sample_rate),
    );
    1
}

/// Remove compressor
#[unsafe(no_mangle)]
pub extern "C" fn compressor_remove(track_id: u32) -> i32 {
    COMPRESSORS.write().remove(&track_id);
    1
}

/// Set compressor type (0=VCA, 1=Opto, 2=FET)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_type(track_id: u32, comp_type: u32) -> i32 {
    use rf_dsp::dynamics::CompressorType;
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        let ct = match comp_type {
            0 => CompressorType::Vca,
            1 => CompressorType::Opto,
            2 => CompressorType::Fet,
            _ => CompressorType::Vca,
        };
        comp.set_both(|c| c.set_type(ct));
        1
    } else {
        0
    }
}

/// Set threshold in dB (-60 to 0)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_threshold(db));
        1
    } else {
        0
    }
}

/// Set ratio (1:1 to 100:1)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_ratio(track_id: u32, ratio: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_ratio(ratio));
        1
    } else {
        0
    }
}

/// Set knee width in dB (0-24)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_knee(track_id: u32, db: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_knee(db));
        1
    } else {
        0
    }
}

/// Set attack time in ms
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_attack(track_id: u32, ms: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_attack(ms));
        1
    } else {
        0
    }
}

/// Set release time in ms
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_release(track_id: u32, ms: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_release(ms));
        1
    } else {
        0
    }
}

/// Set makeup gain in dB
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_makeup(track_id: u32, db: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_makeup(db));
        1
    } else {
        0
    }
}

/// Set parallel mix (0.0 = full dry, 1.0 = full compressed)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_mix(track_id: u32, mix: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_both(|c| c.set_mix(mix));
        1
    } else {
        0
    }
}

/// Set stereo link (0.0 = independent, 1.0 = fully linked)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_set_link(track_id: u32, link: f64) -> i32 {
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_link(link);
        1
    } else {
        0
    }
}

/// Get gain reduction in dB (returns average of L/R)
#[unsafe(no_mangle)]
pub extern "C" fn compressor_get_gain_reduction(track_id: u32) -> f64 {
    let comps = COMPRESSORS.read();
    if let Some(comp) = comps.get(&track_id) {
        let (l, r) = comp.gain_reduction_db();
        (l + r) / 2.0
    } else {
        0.0
    }
}

/// Reset compressor
#[unsafe(no_mangle)]
pub extern "C" fn compressor_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut comps = COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.reset();
        1
    } else {
        0
    }
}

// --- True Peak Limiter ---

/// Create true peak limiter for track
#[unsafe(no_mangle)]
pub extern "C" fn limiter_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut limiters = LIMITERS.write();
    limiters.insert(
        track_id,
        rf_dsp::dynamics::TruePeakLimiter::new(sample_rate),
    );
    1
}

/// Remove limiter
#[unsafe(no_mangle)]
pub extern "C" fn limiter_remove(track_id: u32) -> i32 {
    LIMITERS.write().remove(&track_id);
    1
}

/// Set threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn limiter_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut limiters = LIMITERS.write();
    if let Some(limiter) = limiters.get_mut(&track_id) {
        limiter.set_threshold(db);
        1
    } else {
        0
    }
}

/// Set ceiling in dB
#[unsafe(no_mangle)]
pub extern "C" fn limiter_set_ceiling(track_id: u32, db: f64) -> i32 {
    let mut limiters = LIMITERS.write();
    if let Some(limiter) = limiters.get_mut(&track_id) {
        limiter.set_ceiling(db);
        1
    } else {
        0
    }
}

/// Set release time in ms
#[unsafe(no_mangle)]
pub extern "C" fn limiter_set_release(track_id: u32, ms: f64) -> i32 {
    let mut limiters = LIMITERS.write();
    if let Some(limiter) = limiters.get_mut(&track_id) {
        limiter.set_release(ms);
        1
    } else {
        0
    }
}

/// Get true peak level in dBTP
#[unsafe(no_mangle)]
pub extern "C" fn limiter_get_true_peak(track_id: u32) -> f64 {
    let limiters = LIMITERS.read();
    if let Some(limiter) = limiters.get(&track_id) {
        limiter.true_peak_db()
    } else {
        -120.0
    }
}

/// Get gain reduction in dB
#[unsafe(no_mangle)]
pub extern "C" fn limiter_get_gain_reduction(track_id: u32) -> f64 {
    let limiters = LIMITERS.read();
    if let Some(limiter) = limiters.get(&track_id) {
        limiter.gain_reduction_db()
    } else {
        0.0
    }
}

/// Reset limiter
#[unsafe(no_mangle)]
pub extern "C" fn limiter_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut limiters = LIMITERS.write();
    if let Some(limiter) = limiters.get_mut(&track_id) {
        limiter.reset();
        1
    } else {
        0
    }
}

// --- Noise Gate ---

/// Create noise gate for track
#[unsafe(no_mangle)]
pub extern "C" fn gate_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut gates = GATES.write();
    gates.insert(track_id, rf_dsp::dynamics::Gate::new(sample_rate));
    1
}

/// Remove gate
#[unsafe(no_mangle)]
pub extern "C" fn gate_remove(track_id: u32) -> i32 {
    GATES.write().remove(&track_id);
    1
}

/// Set gate threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn gate_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_threshold(db);
        1
    } else {
        0
    }
}

/// Set gate range in dB
#[unsafe(no_mangle)]
pub extern "C" fn gate_set_range(track_id: u32, db: f64) -> i32 {
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_range(db);
        1
    } else {
        0
    }
}

/// Set gate attack in ms
#[unsafe(no_mangle)]
pub extern "C" fn gate_set_attack(track_id: u32, ms: f64) -> i32 {
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_attack(ms);
        1
    } else {
        0
    }
}

/// Set gate hold in ms
#[unsafe(no_mangle)]
pub extern "C" fn gate_set_hold(track_id: u32, ms: f64) -> i32 {
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_hold(ms);
        1
    } else {
        0
    }
}

/// Set gate release in ms
#[unsafe(no_mangle)]
pub extern "C" fn gate_set_release(track_id: u32, ms: f64) -> i32 {
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_release(ms);
        1
    } else {
        0
    }
}

/// Reset gate
#[unsafe(no_mangle)]
pub extern "C" fn gate_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut gates = GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.reset();
        1
    } else {
        0
    }
}

// --- Expander ---

/// Create expander for track
#[unsafe(no_mangle)]
pub extern "C" fn expander_create(track_id: u32, sample_rate: f64) -> i32 {
    let mut expanders = EXPANDERS.write();
    expanders.insert(track_id, rf_dsp::dynamics::Expander::new(sample_rate));
    1
}

/// Remove expander
#[unsafe(no_mangle)]
pub extern "C" fn expander_remove(track_id: u32) -> i32 {
    EXPANDERS.write().remove(&track_id);
    1
}

/// Set expander threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn expander_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut expanders = EXPANDERS.write();
    if let Some(exp) = expanders.get_mut(&track_id) {
        exp.set_threshold(db);
        1
    } else {
        0
    }
}

/// Set expander ratio
#[unsafe(no_mangle)]
pub extern "C" fn expander_set_ratio(track_id: u32, ratio: f64) -> i32 {
    let mut expanders = EXPANDERS.write();
    if let Some(exp) = expanders.get_mut(&track_id) {
        exp.set_ratio(ratio);
        1
    } else {
        0
    }
}

/// Set expander knee in dB
#[unsafe(no_mangle)]
pub extern "C" fn expander_set_knee(track_id: u32, db: f64) -> i32 {
    let mut expanders = EXPANDERS.write();
    if let Some(exp) = expanders.get_mut(&track_id) {
        exp.set_knee(db);
        1
    } else {
        0
    }
}

/// Set expander attack/release times
#[unsafe(no_mangle)]
pub extern "C" fn expander_set_times(track_id: u32, attack_ms: f64, release_ms: f64) -> i32 {
    let mut expanders = EXPANDERS.write();
    if let Some(exp) = expanders.get_mut(&track_id) {
        exp.set_times(attack_ms, release_ms);
        1
    } else {
        0
    }
}

/// Reset expander
#[unsafe(no_mangle)]
pub extern "C" fn expander_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut expanders = EXPANDERS.write();
    if let Some(exp) = expanders.get_mut(&track_id) {
        exp.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPATIAL PROCESSING FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref STEREO_IMAGERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spatial::StereoImager>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref STEREO_PANNERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spatial::StereoPanner>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref STEREO_WIDTHS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spatial::StereoWidth>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref MS_PROCESSORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spatial::MsProcessor>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// === STEREO IMAGER (Full processor) ===

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_create(track_id: u32, sample_rate: f64) -> i32 {
    let imager = rf_dsp::spatial::StereoImager::new(sample_rate);
    let mut imagers = STEREO_IMAGERS.write();
    imagers.insert(track_id, imager);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_remove(track_id: u32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if imagers.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_width(track_id: u32, width: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.width.set_width(width);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_pan(track_id: u32, pan: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.panner.set_pan(pan);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_pan_law(track_id: u32, law: u32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        let pan_law = match law {
            0 => rf_dsp::spatial::PanLaw::Linear,
            1 => rf_dsp::spatial::PanLaw::ConstantPower,
            2 => rf_dsp::spatial::PanLaw::Compromise,
            3 => rf_dsp::spatial::PanLaw::NoCenterAttenuation,
            _ => rf_dsp::spatial::PanLaw::ConstantPower,
        };
        imager.panner.set_pan_law(pan_law);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_balance(track_id: u32, balance: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.balance.set_balance(balance);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_mid_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.ms.set_mid_gain_db(gain_db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_side_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.ms.set_side_gain_db(gain_db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_set_rotation(track_id: u32, degrees: f64) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.rotation.set_angle_degrees(degrees);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_enable_width(track_id: u32, enabled: i32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.enable_width(enabled != 0);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_enable_panner(track_id: u32, enabled: i32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.enable_panner(enabled != 0);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_enable_balance(track_id: u32, enabled: i32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.enable_balance(enabled != 0);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_enable_ms(track_id: u32, enabled: i32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.enable_ms(enabled != 0);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_enable_rotation(track_id: u32, enabled: i32) -> i32 {
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.enable_rotation(enabled != 0);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_get_correlation(track_id: u32) -> f64 {
    let imagers = STEREO_IMAGERS.read();
    if let Some(imager) = imagers.get(&track_id) {
        imager.correlation.correlation()
    } else {
        0.0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn stereo_imager_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut imagers = STEREO_IMAGERS.write();
    if let Some(imager) = imagers.get_mut(&track_id) {
        imager.reset();
        1
    } else {
        0
    }
}

// === STANDALONE PANNER ===

#[unsafe(no_mangle)]
pub extern "C" fn panner_create(track_id: u32) -> i32 {
    let panner = rf_dsp::spatial::StereoPanner::new();
    let mut panners = STEREO_PANNERS.write();
    panners.insert(track_id, panner);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn panner_remove(track_id: u32) -> i32 {
    let mut panners = STEREO_PANNERS.write();
    if panners.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn panner_set_pan(track_id: u32, pan: f64) -> i32 {
    let mut panners = STEREO_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_pan(pan);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn panner_set_law(track_id: u32, law: u32) -> i32 {
    let mut panners = STEREO_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        let pan_law = match law {
            0 => rf_dsp::spatial::PanLaw::Linear,
            1 => rf_dsp::spatial::PanLaw::ConstantPower,
            2 => rf_dsp::spatial::PanLaw::Compromise,
            3 => rf_dsp::spatial::PanLaw::NoCenterAttenuation,
            _ => rf_dsp::spatial::PanLaw::ConstantPower,
        };
        panner.set_pan_law(pan_law);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn panner_get_pan(track_id: u32) -> f64 {
    let panners = STEREO_PANNERS.read();
    if let Some(panner) = panners.get(&track_id) {
        panner.pan()
    } else {
        0.0
    }
}

// === STANDALONE WIDTH ===

#[unsafe(no_mangle)]
pub extern "C" fn width_create(track_id: u32) -> i32 {
    let width = rf_dsp::spatial::StereoWidth::new();
    let mut widths = STEREO_WIDTHS.write();
    widths.insert(track_id, width);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn width_remove(track_id: u32) -> i32 {
    let mut widths = STEREO_WIDTHS.write();
    if widths.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn width_set_width(track_id: u32, width: f64) -> i32 {
    let mut widths = STEREO_WIDTHS.write();
    if let Some(w) = widths.get_mut(&track_id) {
        w.set_width(width);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn width_get_width(track_id: u32) -> f64 {
    let widths = STEREO_WIDTHS.read();
    if let Some(w) = widths.get(&track_id) {
        w.width()
    } else {
        1.0
    }
}

// === M/S PROCESSOR ===

#[unsafe(no_mangle)]
pub extern "C" fn ms_processor_create(track_id: u32) -> i32 {
    let ms = rf_dsp::spatial::MsProcessor::new();
    let mut processors = MS_PROCESSORS.write();
    processors.insert(track_id, ms);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn ms_processor_remove(track_id: u32) -> i32 {
    let mut processors = MS_PROCESSORS.write();
    if processors.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ms_processor_set_mid_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut processors = MS_PROCESSORS.write();
    if let Some(ms) = processors.get_mut(&track_id) {
        ms.set_mid_gain_db(gain_db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ms_processor_set_side_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut processors = MS_PROCESSORS.write();
    if let Some(ms) = processors.get_mut(&track_id) {
        ms.set_side_gain_db(gain_db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ms_processor_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut processors = MS_PROCESSORS.write();
    if let Some(ms) = processors.get_mut(&track_id) {
        ms.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MULTIBAND DYNAMICS FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref MULTIBAND_COMPRESSORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::multiband::MultibandCompressor>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref MULTIBAND_LIMITERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::multiband::MultibandLimiter>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// === MULTIBAND COMPRESSOR ===

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_create(track_id: u32, sample_rate: f64, num_bands: u32) -> i32 {
    let num_bands = (num_bands as usize).clamp(2, 6);
    let comp = rf_dsp::multiband::MultibandCompressor::new(sample_rate, num_bands);
    let mut comps = MULTIBAND_COMPRESSORS.write();
    comps.insert(track_id, comp);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_remove(track_id: u32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if comps.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_num_bands(track_id: u32, num_bands: u32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_num_bands(num_bands as usize);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_crossover(track_id: u32, index: u32, freq: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_crossover(index as usize, freq);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_crossover_type(track_id: u32, crossover_type: u32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        let ct = match crossover_type {
            0 => rf_dsp::multiband::CrossoverType::Butterworth12,
            1 => rf_dsp::multiband::CrossoverType::LinkwitzRiley24,
            2 => rf_dsp::multiband::CrossoverType::LinkwitzRiley48,
            _ => rf_dsp::multiband::CrossoverType::LinkwitzRiley24,
        };
        comp.set_crossover_type(ct);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_threshold(track_id: u32, band: u32, db: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.threshold_db = db.clamp(-60.0, 0.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_ratio(track_id: u32, band: u32, ratio: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.ratio = ratio.clamp(1.0, 100.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_attack(track_id: u32, band: u32, ms: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.attack_ms = ms.clamp(0.01, 500.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_release(track_id: u32, band: u32, ms: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.release_ms = ms.clamp(1.0, 5000.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_knee(track_id: u32, band: u32, db: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.knee_db = db.clamp(0.0, 24.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_makeup(track_id: u32, band: u32, db: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.makeup_db = db.clamp(-24.0, 24.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_solo(track_id: u32, band: u32, solo: i32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.solo = solo != 0;
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_mute(track_id: u32, band: u32, mute: i32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.mute = mute != 0;
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_band_bypass(track_id: u32, band: u32, bypass: i32) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        if let Some(b) = comp.band_mut(band as usize) {
            b.bypass = bypass != 0;
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_set_output_gain(track_id: u32, db: f64) -> i32 {
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_output_gain(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_get_band_gr(track_id: u32, band: u32) -> f64 {
    let comps = MULTIBAND_COMPRESSORS.read();
    if let Some(comp) = comps.get(&track_id) {
        let grs = comp.get_gain_reduction();
        if let Some((gr_l, gr_r)) = grs.get(band as usize) {
            (*gr_l + *gr_r) / 2.0
        } else {
            0.0
        }
    } else {
        0.0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_comp_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut comps = MULTIBAND_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.reset();
        1
    } else {
        0
    }
}

// === MULTIBAND LIMITER ===

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_create(track_id: u32, sample_rate: f64, num_bands: u32) -> i32 {
    let num_bands = (num_bands as usize).clamp(2, 6);
    let lim = rf_dsp::multiband::MultibandLimiter::new(sample_rate, num_bands);
    let mut lims = MULTIBAND_LIMITERS.write();
    lims.insert(track_id, lim);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_remove(track_id: u32) -> i32 {
    let mut lims = MULTIBAND_LIMITERS.write();
    if lims.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_set_ceiling(track_id: u32, db: f64) -> i32 {
    let mut lims = MULTIBAND_LIMITERS.write();
    if let Some(lim) = lims.get_mut(&track_id) {
        lim.set_ceiling(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_set_band_ceiling(track_id: u32, band: u32, db: f64) -> i32 {
    let mut lims = MULTIBAND_LIMITERS.write();
    if let Some(lim) = lims.get_mut(&track_id) {
        lim.set_band_ceiling(band as usize, db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_set_band_solo(track_id: u32, band: u32, solo: i32) -> i32 {
    let mut lims = MULTIBAND_LIMITERS.write();
    if let Some(lim) = lims.get_mut(&track_id) {
        if let Some(b) = lim.band_mut(band as usize) {
            b.solo = solo != 0;
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_set_band_mute(track_id: u32, band: u32, mute: i32) -> i32 {
    let mut lims = MULTIBAND_LIMITERS.write();
    if let Some(lim) = lims.get_mut(&track_id) {
        if let Some(b) = lim.band_mut(band as usize) {
            b.mute = mute != 0;
            1
        } else {
            0
        }
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_lim_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut lims = MULTIBAND_LIMITERS.write();
    if let Some(lim) = lims.get_mut(&track_id) {
        lim.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSIENT SHAPER FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref TRANSIENT_SHAPERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::transient::TransientShaper>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref MULTIBAND_TRANSIENT_SHAPERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::transient::MultibandTransientShaper>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// === TRANSIENT SHAPER ===

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_create(track_id: u32, sample_rate: f64) -> i32 {
    let shaper = rf_dsp::transient::TransientShaper::new(sample_rate);
    let mut shapers = TRANSIENT_SHAPERS.write();
    shapers.insert(track_id, shaper);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_remove(track_id: u32) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if shapers.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_attack(track_id: u32, percent: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_attack(percent);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_sustain(track_id: u32, percent: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_sustain(percent);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_attack_speed(track_id: u32, ms: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_attack_speed(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_sustain_speed(track_id: u32, ms: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_sustain_speed(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_output_gain(track_id: u32, db: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_output_gain(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_set_mix(track_id: u32, mix: f64) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_mix(mix);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_get_attack_envelope(track_id: u32) -> f64 {
    let shapers = TRANSIENT_SHAPERS.read();
    if let Some(shaper) = shapers.get(&track_id) {
        shaper.attack_envelope()
    } else {
        0.0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_get_sustain_envelope(track_id: u32) -> f64 {
    let shapers = TRANSIENT_SHAPERS.read();
    if let Some(shaper) = shapers.get(&track_id) {
        shaper.sustain_envelope()
    } else {
        0.0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn transient_shaper_reset(track_id: u32) -> i32 {
    let mut shapers = TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.reset();
        1
    } else {
        0
    }
}

// === MULTIBAND TRANSIENT SHAPER ===

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_create(track_id: u32, sample_rate: f64) -> i32 {
    let shaper = rf_dsp::transient::MultibandTransientShaper::new(sample_rate);
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    shapers.insert(track_id, shaper);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_remove(track_id: u32) -> i32 {
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    if shapers.remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_set_crossovers(track_id: u32, low: f64, high: f64) -> i32 {
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.set_crossovers(low, high);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_set_band_attack(
    track_id: u32,
    band: u32,
    percent: f64,
) -> i32 {
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        let band_shaper = match band {
            0 => shaper.low_band(),
            1 => shaper.mid_band(),
            2 => shaper.high_band(),
            _ => return 0,
        };
        band_shaper.set_attack(percent);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_set_band_sustain(
    track_id: u32,
    band: u32,
    percent: f64,
) -> i32 {
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        let band_shaper = match band {
            0 => shaper.low_band(),
            1 => shaper.mid_band(),
            2 => shaper.high_band(),
            _ => return 0,
        };
        band_shaper.set_sustain(percent);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn multiband_transient_reset(track_id: u32) -> i32 {
    let mut shapers = MULTIBAND_TRANSIENT_SHAPERS.write();
    if let Some(shaper) = shapers.get_mut(&track_id) {
        shaper.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRO EQ FFI - 64-Band Professional Parametric EQ
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref PRO_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_pro::ProEq>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create a new Pro EQ instance for a track
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_pro::ProEq::new(sample_rate);
    PRO_EQS.write().insert(track_id, eq);
    1
}

/// Destroy a Pro EQ instance
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_destroy(track_id: u32) -> i32 {
    if PRO_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Enable or disable a band
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_enabled(track_id: u32, band_index: u32, enabled: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.enable_band(band_index as usize, enabled != 0);
        1
    } else {
        0
    }
}

/// Set band frequency
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_frequency(track_id: u32, band_index: u32, freq: f64) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_frequency(band_index as usize, freq);
        1
    } else {
        0
    }
}

/// Set band gain
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_gain(track_id: u32, band_index: u32, gain_db: f64) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_gain(band_index as usize, gain_db);
        1
    } else {
        0
    }
}

/// Set band Q
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_q(track_id: u32, band_index: u32, q: f64) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_q(band_index as usize, q);
        1
    } else {
        0
    }
}

/// Set band filter shape
/// shape: 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=Bandpass, 7=TiltShelf, 8=Allpass, 9=Brickwall
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_shape(track_id: u32, band_index: u32, shape: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let filter_shape = match shape {
            0 => rf_dsp::eq_pro::FilterShape::Bell,
            1 => rf_dsp::eq_pro::FilterShape::LowShelf,
            2 => rf_dsp::eq_pro::FilterShape::HighShelf,
            3 => rf_dsp::eq_pro::FilterShape::LowCut,
            4 => rf_dsp::eq_pro::FilterShape::HighCut,
            5 => rf_dsp::eq_pro::FilterShape::Notch,
            6 => rf_dsp::eq_pro::FilterShape::Bandpass,
            7 => rf_dsp::eq_pro::FilterShape::TiltShelf,
            8 => rf_dsp::eq_pro::FilterShape::Allpass,
            9 => rf_dsp::eq_pro::FilterShape::Brickwall,
            _ => return 0,
        };
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.shape = filter_shape;
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Set all band parameters at once
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band(
    track_id: u32,
    band_index: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    shape: i32,
) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let filter_shape = match shape {
            0 => rf_dsp::eq_pro::FilterShape::Bell,
            1 => rf_dsp::eq_pro::FilterShape::LowShelf,
            2 => rf_dsp::eq_pro::FilterShape::HighShelf,
            3 => rf_dsp::eq_pro::FilterShape::LowCut,
            4 => rf_dsp::eq_pro::FilterShape::HighCut,
            5 => rf_dsp::eq_pro::FilterShape::Notch,
            6 => rf_dsp::eq_pro::FilterShape::Bandpass,
            7 => rf_dsp::eq_pro::FilterShape::TiltShelf,
            8 => rf_dsp::eq_pro::FilterShape::Allpass,
            9 => rf_dsp::eq_pro::FilterShape::Brickwall,
            _ => return 0,
        };
        eq.set_band(band_index as usize, freq, gain_db, q, filter_shape);
        1
    } else {
        0
    }
}

/// Set band stereo placement
/// placement: 0=Stereo, 1=Left, 2=Right, 3=Mid, 4=Side
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_placement(track_id: u32, band_index: u32, placement: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let stereo_placement = match placement {
            0 => rf_dsp::eq_pro::StereoPlacement::Stereo,
            1 => rf_dsp::eq_pro::StereoPlacement::Left,
            2 => rf_dsp::eq_pro::StereoPlacement::Right,
            3 => rf_dsp::eq_pro::StereoPlacement::Mid,
            4 => rf_dsp::eq_pro::StereoPlacement::Side,
            _ => return 0,
        };
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.placement = stereo_placement;
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Set band slope (for low/high cut filters)
/// slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB, 4=36dB, 5=48dB, 6=72dB, 7=96dB, 8=Brickwall
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_slope(track_id: u32, band_index: u32, slope: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let filter_slope = match slope {
            0 => rf_dsp::eq_pro::Slope::Db6,
            1 => rf_dsp::eq_pro::Slope::Db12,
            2 => rf_dsp::eq_pro::Slope::Db18,
            3 => rf_dsp::eq_pro::Slope::Db24,
            4 => rf_dsp::eq_pro::Slope::Db36,
            5 => rf_dsp::eq_pro::Slope::Db48,
            6 => rf_dsp::eq_pro::Slope::Db72,
            7 => rf_dsp::eq_pro::Slope::Db96,
            8 => rf_dsp::eq_pro::Slope::Brickwall,
            _ => return 0,
        };
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.slope = filter_slope;
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Configure dynamic EQ for a band
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_band_dynamic(
    track_id: u32,
    band_index: u32,
    enabled: i32,
    threshold_db: f64,
    ratio: f64,
    attack_ms: f64,
    release_ms: f64,
) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.dynamic.enabled = enabled != 0;
            band.dynamic.threshold_db = threshold_db;
            band.dynamic.ratio = ratio;
            band.dynamic.attack_ms = attack_ms;
            band.dynamic.release_ms = release_ms;
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Set output gain
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_output_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.output_gain_db = gain_db;
        1
    } else {
        0
    }
}

/// Set analyzer mode
/// mode: 0=Off, 1=PreEq, 2=PostEq, 3=Sidechain, 4=Delta
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_analyzer_mode(track_id: u32, mode: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.analyzer_mode = match mode {
            0 => rf_dsp::eq_pro::AnalyzerMode::Off,
            1 => rf_dsp::eq_pro::AnalyzerMode::PreEq,
            2 => rf_dsp::eq_pro::AnalyzerMode::PostEq,
            3 => rf_dsp::eq_pro::AnalyzerMode::Sidechain,
            4 => rf_dsp::eq_pro::AnalyzerMode::Delta,
            _ => return 0,
        };
        1
    } else {
        0
    }
}

/// Enable auto gain (LUFS matching)
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_auto_gain(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.auto_gain.enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Enable EQ match mode
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_set_match_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.match_enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Store current state as A
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_store_state_a(track_id: u32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.store_state_a();
        1
    } else {
        0
    }
}

/// Store current state as B
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_store_state_b(track_id: u32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.store_state_b();
        1
    } else {
        0
    }
}

/// Recall state A
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_recall_state_a(track_id: u32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.recall_state_a();
        1
    } else {
        0
    }
}

/// Recall state B
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_recall_state_b(track_id: u32) -> i32 {
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.recall_state_b();
        1
    } else {
        0
    }
}

/// Get spectrum data for display (256 float values, log-scaled 20Hz-20kHz)
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_get_spectrum(track_id: u32, out_data: *mut f32, out_len: u32) -> i32 {
    if out_data.is_null() || out_len < 256 {
        return 0;
    }

    let eqs = PRO_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        let spectrum = eq.get_spectrum_data();
        let len = spectrum.len().min(out_len as usize);
        unsafe {
            std::ptr::copy_nonoverlapping(spectrum.as_ptr(), out_data, len);
        }
        len as i32
    } else {
        0
    }
}

/// Get frequency response curve for display
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_get_frequency_response(
    track_id: u32,
    num_points: u32,
    out_freq: *mut f64,
    out_db: *mut f64,
) -> i32 {
    if out_freq.is_null() || out_db.is_null() || num_points == 0 {
        return 0;
    }

    let eqs = PRO_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        let curve = eq.frequency_response_curve(num_points as usize);
        for (i, (freq, db)) in curve.iter().enumerate() {
            unsafe {
                *out_freq.add(i) = *freq;
                *out_db.add(i) = *db;
            }
        }
        curve.len() as i32
    } else {
        0
    }
}

/// Get enabled band count
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_get_enabled_band_count(track_id: u32) -> i32 {
    let eqs = PRO_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.enabled_band_count() as i32
    } else {
        0
    }
}

/// Process stereo audio block
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_process(
    track_id: u32,
    left: *mut f64,
    right: *mut f64,
    num_samples: u32,
) -> i32 {
    if left.is_null() || right.is_null() || num_samples == 0 {
        return 0;
    }

    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let left_slice = unsafe { std::slice::from_raw_parts_mut(left, num_samples as usize) };
        let right_slice = unsafe { std::slice::from_raw_parts_mut(right, num_samples as usize) };
        eq.process_block(left_slice, right_slice);
        1
    } else {
        0
    }
}

/// Reset EQ state
#[unsafe(no_mangle)]
pub extern "C" fn pro_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = PRO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANALOG EQ FFI - Pultec, API 550, Neve 1073
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref PULTEC_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_analog::StereoPultec>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref API550_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_analog::StereoApi550>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref NEVE1073_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_analog::StereoNeve1073>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// ─────────────────────────────────────────────────────────────────────────────
// PULTEC EQP-1A
// ─────────────────────────────────────────────────────────────────────────────

/// Create Pultec EQ instance
#[unsafe(no_mangle)]
pub extern "C" fn pultec_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_analog::StereoPultec::new(sample_rate);
    PULTEC_EQS.write().insert(track_id, eq);
    1
}

/// Destroy Pultec EQ instance
#[unsafe(no_mangle)]
pub extern "C" fn pultec_destroy(track_id: u32) -> i32 {
    if PULTEC_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set Pultec low boost (0-10)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_low_boost(track_id: u32, amount: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_low_boost(amount);
        eq.right.set_low_boost(amount);
        1
    } else {
        0
    }
}

/// Set Pultec low atten (0-10)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_low_atten(track_id: u32, amount: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_low_atten(amount);
        eq.right.set_low_atten(amount);
        1
    } else {
        0
    }
}

/// Set Pultec low freq (0=20Hz, 1=30Hz, 2=60Hz, 3=100Hz)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_low_freq(track_id: u32, freq_index: i32) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::PultecLowFreq::Hz20,
            1 => rf_dsp::eq_analog::PultecLowFreq::Hz30,
            2 => rf_dsp::eq_analog::PultecLowFreq::Hz60,
            _ => rf_dsp::eq_analog::PultecLowFreq::Hz100,
        };
        eq.left.set_low_freq(freq);
        eq.right.set_low_freq(freq);
        1
    } else {
        0
    }
}

/// Set Pultec high boost (0-10)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_high_boost(track_id: u32, amount: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_high_boost(amount);
        eq.right.set_high_boost(amount);
        1
    } else {
        0
    }
}

/// Set Pultec high bandwidth (0=sharp, 1=broad)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_high_bandwidth(track_id: u32, bandwidth: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_high_bandwidth(bandwidth);
        eq.right.set_high_bandwidth(bandwidth);
        1
    } else {
        0
    }
}

/// Set Pultec high boost freq (0=3k, 1=4k, 2=5k, 3=8k, 4=10k, 5=12k, 6=16k)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_high_boost_freq(track_id: u32, freq_index: i32) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::PultecHighBoostFreq::K3,
            1 => rf_dsp::eq_analog::PultecHighBoostFreq::K4,
            2 => rf_dsp::eq_analog::PultecHighBoostFreq::K5,
            3 => rf_dsp::eq_analog::PultecHighBoostFreq::K8,
            4 => rf_dsp::eq_analog::PultecHighBoostFreq::K10,
            5 => rf_dsp::eq_analog::PultecHighBoostFreq::K12,
            _ => rf_dsp::eq_analog::PultecHighBoostFreq::K16,
        };
        eq.left.set_high_boost_freq(freq);
        eq.right.set_high_boost_freq(freq);
        1
    } else {
        0
    }
}

/// Set Pultec high atten (0-10)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_high_atten(track_id: u32, amount: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_high_atten(amount);
        eq.right.set_high_atten(amount);
        1
    } else {
        0
    }
}

/// Set Pultec high atten freq (0=5k, 1=10k, 2=20k)
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_high_atten_freq(track_id: u32, freq_index: i32) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::PultecHighAttenFreq::K5,
            1 => rf_dsp::eq_analog::PultecHighAttenFreq::K10,
            _ => rf_dsp::eq_analog::PultecHighAttenFreq::K20,
        };
        eq.left.set_high_atten_freq(freq);
        eq.right.set_high_atten_freq(freq);
        1
    } else {
        0
    }
}

/// Set Pultec drive
#[unsafe(no_mangle)]
pub extern "C" fn pultec_set_drive(track_id: u32, drive: f64) -> i32 {
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.left.set_drive(drive);
        eq.right.set_drive(drive);
        1
    } else {
        0
    }
}

/// Reset Pultec
#[unsafe(no_mangle)]
pub extern "C" fn pultec_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = PULTEC_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// API 550
// ─────────────────────────────────────────────────────────────────────────────

/// Create API 550 instance
#[unsafe(no_mangle)]
pub extern "C" fn api550_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_analog::StereoApi550::new(sample_rate);
    API550_EQS.write().insert(track_id, eq);
    1
}

/// Destroy API 550 instance
#[unsafe(no_mangle)]
pub extern "C" fn api550_destroy(track_id: u32) -> i32 {
    if API550_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set API 550 low band
#[unsafe(no_mangle)]
pub extern "C" fn api550_set_low(track_id: u32, gain_db: f64, freq_index: i32) -> i32 {
    let mut eqs = API550_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Api550LowFreq::Hz50,
            1 => rf_dsp::eq_analog::Api550LowFreq::Hz100,
            2 => rf_dsp::eq_analog::Api550LowFreq::Hz200,
            3 => rf_dsp::eq_analog::Api550LowFreq::Hz300,
            _ => rf_dsp::eq_analog::Api550LowFreq::Hz400,
        };
        eq.left.set_low(gain_db, freq);
        eq.right.set_low(gain_db, freq);
        1
    } else {
        0
    }
}

/// Set API 550 mid band
#[unsafe(no_mangle)]
pub extern "C" fn api550_set_mid(track_id: u32, gain_db: f64, freq_index: i32) -> i32 {
    let mut eqs = API550_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Api550MidFreq::Hz200,
            1 => rf_dsp::eq_analog::Api550MidFreq::Hz400,
            2 => rf_dsp::eq_analog::Api550MidFreq::Hz800,
            3 => rf_dsp::eq_analog::Api550MidFreq::K1_5,
            _ => rf_dsp::eq_analog::Api550MidFreq::K3,
        };
        eq.left.set_mid(gain_db, freq);
        eq.right.set_mid(gain_db, freq);
        1
    } else {
        0
    }
}

/// Set API 550 high band
#[unsafe(no_mangle)]
pub extern "C" fn api550_set_high(track_id: u32, gain_db: f64, freq_index: i32) -> i32 {
    let mut eqs = API550_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Api550HighFreq::K2_5,
            1 => rf_dsp::eq_analog::Api550HighFreq::K5,
            2 => rf_dsp::eq_analog::Api550HighFreq::K7_5,
            3 => rf_dsp::eq_analog::Api550HighFreq::K10,
            _ => rf_dsp::eq_analog::Api550HighFreq::K12_5,
        };
        eq.left.set_high(gain_db, freq);
        eq.right.set_high(gain_db, freq);
        1
    } else {
        0
    }
}

/// Reset API 550
#[unsafe(no_mangle)]
pub extern "C" fn api550_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = API550_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEVE 1073
// ─────────────────────────────────────────────────────────────────────────────

/// Create Neve 1073 instance
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_analog::StereoNeve1073::new(sample_rate);
    NEVE1073_EQS.write().insert(track_id, eq);
    1
}

/// Destroy Neve 1073 instance
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_destroy(track_id: u32) -> i32 {
    if NEVE1073_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set Neve 1073 high-pass
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_set_hp(track_id: u32, enabled: i32, freq_index: i32) -> i32 {
    let mut eqs = NEVE1073_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Neve1073HpFreq::Hz50,
            1 => rf_dsp::eq_analog::Neve1073HpFreq::Hz80,
            2 => rf_dsp::eq_analog::Neve1073HpFreq::Hz160,
            _ => rf_dsp::eq_analog::Neve1073HpFreq::Hz300,
        };
        eq.left.set_hp(enabled != 0, freq);
        eq.right.set_hp(enabled != 0, freq);
        1
    } else {
        0
    }
}

/// Set Neve 1073 low shelf
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_set_low(track_id: u32, gain_db: f64, freq_index: i32) -> i32 {
    let mut eqs = NEVE1073_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Neve1073LowFreq::Hz35,
            1 => rf_dsp::eq_analog::Neve1073LowFreq::Hz60,
            2 => rf_dsp::eq_analog::Neve1073LowFreq::Hz110,
            _ => rf_dsp::eq_analog::Neve1073LowFreq::Hz220,
        };
        eq.left.set_low(gain_db, freq);
        eq.right.set_low(gain_db, freq);
        1
    } else {
        0
    }
}

/// Set Neve 1073 high shelf
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_set_high(track_id: u32, gain_db: f64, freq_index: i32) -> i32 {
    let mut eqs = NEVE1073_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let freq = match freq_index {
            0 => rf_dsp::eq_analog::Neve1073HighFreq::K12,
            1 => rf_dsp::eq_analog::Neve1073HighFreq::K10,
            2 => rf_dsp::eq_analog::Neve1073HighFreq::K7_5,
            _ => rf_dsp::eq_analog::Neve1073HighFreq::K5,
        };
        eq.left.set_high(gain_db, freq);
        eq.right.set_high(gain_db, freq);
        1
    } else {
        0
    }
}

/// Reset Neve 1073
#[unsafe(no_mangle)]
pub extern "C" fn neve1073_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = NEVE1073_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH CORRECTION FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref PITCH_CORRECTORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::pitch::PitchCorrector>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create pitch corrector instance
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_create(track_id: u32) -> i32 {
    let corrector = rf_dsp::pitch::PitchCorrector::default();
    PITCH_CORRECTORS.write().insert(track_id, corrector);
    1
}

/// Destroy pitch corrector instance
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_destroy(track_id: u32) -> i32 {
    if PITCH_CORRECTORS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set pitch correction scale
/// scale: 0=Chromatic, 1=Major, 2=Minor, 3=HarmonicMinor, 4=PentatonicMajor,
///        5=PentatonicMinor, 6=Blues, 7=Dorian, 8=Custom
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_scale(track_id: u32, scale: i32) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.scale = match scale {
            0 => rf_dsp::pitch::Scale::Chromatic,
            1 => rf_dsp::pitch::Scale::Major,
            2 => rf_dsp::pitch::Scale::Minor,
            3 => rf_dsp::pitch::Scale::HarmonicMinor,
            4 => rf_dsp::pitch::Scale::PentatonicMajor,
            5 => rf_dsp::pitch::Scale::PentatonicMinor,
            6 => rf_dsp::pitch::Scale::Blues,
            7 => rf_dsp::pitch::Scale::Dorian,
            _ => rf_dsp::pitch::Scale::Custom,
        };
        1
    } else {
        0
    }
}

/// Set pitch correction root note (0=C, 1=C#, ..., 11=B)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_root(track_id: u32, root: i32) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.root = (root as u8).clamp(0, 11);
        1
    } else {
        0
    }
}

/// Set pitch correction speed (0.0=slow/natural, 1.0=instant/robotic)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_speed(track_id: u32, speed: f64) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.speed = speed.clamp(0.0, 1.0);
        1
    } else {
        0
    }
}

/// Set pitch correction amount (0.0=off, 1.0=full correction)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_amount(track_id: u32, amount: f64) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.amount = amount.clamp(0.0, 1.0);
        1
    } else {
        0
    }
}

/// Set preserve vibrato option
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_preserve_vibrato(track_id: u32, preserve: i32) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.preserve_vibrato = preserve != 0;
        1
    } else {
        0
    }
}

/// Set formant preservation amount (0.0=none, 1.0=full)
#[unsafe(no_mangle)]
pub extern "C" fn pitch_corrector_set_formant_preservation(track_id: u32, amount: f64) -> i32 {
    let mut correctors = PITCH_CORRECTORS.write();
    if let Some(corrector) = correctors.get_mut(&track_id) {
        corrector.formant_preservation = amount.clamp(0.0, 1.0);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECTRAL PROCESSING FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SPECTRAL_GATES: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spectral::SpectralGate>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref SPECTRAL_FREEZES: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spectral::SpectralFreeze>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref SPECTRAL_COMPRESSORS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spectral::SpectralCompressor>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref DE_CLICKS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::spectral::DeClick>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

// ─────────────────────────────────────────────────────────────────────────────
// SPECTRAL GATE (Noise Reduction)
// ─────────────────────────────────────────────────────────────────────────────

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_create(track_id: u32, sample_rate: f64) -> i32 {
    let gate = rf_dsp::spectral::SpectralGate::new(sample_rate);
    SPECTRAL_GATES.write().insert(track_id, gate);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_destroy(track_id: u32) -> i32 {
    if SPECTRAL_GATES.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_threshold(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_set_reduction(track_id: u32, db: f64) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_reduction(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_set_attack(track_id: u32, ms: f64) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_attack(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_set_release(track_id: u32, ms: f64) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.set_release(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_learn_noise_start(track_id: u32) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.learn_noise_start();
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_learn_noise_stop(track_id: u32) -> i32 {
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.learn_noise_stop();
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_gate_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut gates = SPECTRAL_GATES.write();
    if let Some(gate) = gates.get_mut(&track_id) {
        gate.reset();
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPECTRAL FREEZE
// ─────────────────────────────────────────────────────────────────────────────

#[unsafe(no_mangle)]
pub extern "C" fn spectral_freeze_create(track_id: u32, sample_rate: f64) -> i32 {
    let freeze = rf_dsp::spectral::SpectralFreeze::new(sample_rate);
    SPECTRAL_FREEZES.write().insert(track_id, freeze);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_freeze_destroy(track_id: u32) -> i32 {
    if SPECTRAL_FREEZES.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_freeze_toggle(track_id: u32) -> i32 {
    let mut freezes = SPECTRAL_FREEZES.write();
    if let Some(freeze) = freezes.get_mut(&track_id) {
        freeze.toggle_freeze();
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_freeze_set_mix(track_id: u32, mix: f64) -> i32 {
    let mut freezes = SPECTRAL_FREEZES.write();
    if let Some(freeze) = freezes.get_mut(&track_id) {
        freeze.set_mix(mix);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_freeze_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut freezes = SPECTRAL_FREEZES.write();
    if let Some(freeze) = freezes.get_mut(&track_id) {
        freeze.reset();
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPECTRAL COMPRESSOR
// ─────────────────────────────────────────────────────────────────────────────

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_create(track_id: u32, sample_rate: f64) -> i32 {
    let comp = rf_dsp::spectral::SpectralCompressor::new(sample_rate);
    SPECTRAL_COMPRESSORS.write().insert(track_id, comp);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_destroy(track_id: u32) -> i32 {
    if SPECTRAL_COMPRESSORS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut comps = SPECTRAL_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_threshold(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_set_ratio(track_id: u32, ratio: f64) -> i32 {
    let mut comps = SPECTRAL_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_ratio(ratio);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_set_attack(track_id: u32, ms: f64) -> i32 {
    let mut comps = SPECTRAL_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_attack(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_set_release(track_id: u32, ms: f64) -> i32 {
    let mut comps = SPECTRAL_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.set_release(ms);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn spectral_compressor_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut comps = SPECTRAL_COMPRESSORS.write();
    if let Some(comp) = comps.get_mut(&track_id) {
        comp.reset();
        1
    } else {
        0
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DE-CLICK
// ─────────────────────────────────────────────────────────────────────────────

#[unsafe(no_mangle)]
pub extern "C" fn declick_create(track_id: u32, sample_rate: f64) -> i32 {
    let declick = rf_dsp::spectral::DeClick::new(sample_rate);
    DE_CLICKS.write().insert(track_id, declick);
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn declick_destroy(track_id: u32) -> i32 {
    if DE_CLICKS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn declick_set_threshold(track_id: u32, db: f64) -> i32 {
    let mut declicks = DE_CLICKS.write();
    if let Some(declick) = declicks.get_mut(&track_id) {
        declick.set_threshold(db);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn declick_set_interp_length(track_id: u32, samples: u32) -> i32 {
    let mut declicks = DE_CLICKS.write();
    if let Some(declick) = declicks.get_mut(&track_id) {
        declick.set_interp_length(samples as usize);
        1
    } else {
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn declick_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut declicks = DE_CLICKS.write();
    if let Some(declick) = declicks.get_mut(&track_id) {
        declick.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ULTRA EQ - Beyond Pro-Q 4
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref ULTRA_EQS: RwLock<std::collections::HashMap<u32, rf_dsp::eq_ultra::UltraEq>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create UltraEq instance
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_ultra::UltraEq::new(sample_rate);
    ULTRA_EQS.write().insert(track_id, eq);
    1
}

/// Destroy UltraEq instance
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_destroy(track_id: u32) -> i32 {
    if ULTRA_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Enable/disable band
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_enable_band(track_id: u32, band_index: u32, enabled: i32) -> i32 {
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.enable_band(band_index as usize, enabled != 0);
        1
    } else {
        0
    }
}

/// Set band parameters
/// filter_type: 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_band(
    track_id: u32,
    band_index: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    filter_type: u32,
) -> i32 {
    use rf_dsp::eq_ultra::UltraFilterType;
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let ft = match filter_type {
            0 => UltraFilterType::Bell,
            1 => UltraFilterType::LowShelf,
            2 => UltraFilterType::HighShelf,
            3 => UltraFilterType::LowCut,
            4 => UltraFilterType::HighCut,
            _ => UltraFilterType::Bell,
        };
        eq.set_band(band_index as usize, freq, gain_db, q, ft);
        1
    } else {
        0
    }
}

/// Set oversampling mode: 0=Off, 1=2x, 2=4x, 3=8x, 4=Adaptive
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_oversample(track_id: u32, mode: u32) -> i32 {
    use rf_dsp::eq_ultra::OversampleMode;
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        let m = match mode {
            0 => OversampleMode::Off,
            1 => OversampleMode::X2,
            2 => OversampleMode::X4,
            3 => OversampleMode::X8,
            4 => OversampleMode::Adaptive,
            _ => OversampleMode::Off,
        };
        eq.set_oversample(m);
        1
    } else {
        0
    }
}

/// Set loudness compensation (ISO 226)
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_loudness_compensation(
    track_id: u32,
    enabled: i32,
    target_phon: f64,
) -> i32 {
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_loudness_compensation(enabled != 0, target_phon);
        1
    } else {
        0
    }
}

/// Set output gain
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_output_gain(track_id: u32, gain_db: f64) -> i32 {
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.output_gain_db = gain_db;
        1
    } else {
        0
    }
}

/// Get stereo correlation
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_get_correlation(track_id: u32) -> f64 {
    let eqs = ULTRA_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.correlation.get_correlation()
    } else {
        1.0
    }
}

/// Set band saturation (per-band analog warmth)
/// sat_type: 0=Tube, 1=Tape, 2=Transistor, 3=Soft
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_band_saturation(
    track_id: u32,
    band_index: u32,
    drive: f64,
    mix: f64,
    sat_type: u32,
) -> i32 {
    use rf_dsp::eq_ultra::SaturationType;
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.saturator.drive = drive.clamp(0.0, 1.0);
            band.saturator.mix = mix.clamp(0.0, 1.0);
            band.saturator.sat_type = match sat_type {
                0 => SaturationType::Tube,
                1 => SaturationType::Tape,
                2 => SaturationType::Transistor,
                3 => SaturationType::Soft,
                _ => SaturationType::Tube,
            };
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Set band transient-aware mode
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_set_band_transient_aware(
    track_id: u32,
    band_index: u32,
    enabled: i32,
    q_reduction: f64,
) -> i32 {
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        if let Some(band) = eq.band_mut(band_index as usize) {
            band.transient_aware = enabled != 0;
            band.transient_q_reduction = q_reduction.clamp(0.0, 1.0);
            1
        } else {
            0
        }
    } else {
        0
    }
}

/// Reset UltraEq
#[unsafe(no_mangle)]
pub extern "C" fn ultra_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = ULTRA_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ELASTIC PRO - Ultimate Time Stretching
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref ELASTIC_PROS: RwLock<std::collections::HashMap<u32, rf_dsp::elastic_pro::ElasticPro>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create ElasticPro instance
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_create(track_id: u32, sample_rate: f64) -> i32 {
    let elastic = rf_dsp::elastic_pro::ElasticPro::new(sample_rate);
    ELASTIC_PROS.write().insert(track_id, elastic);
    1
}

/// Destroy ElasticPro instance
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_destroy(track_id: u32) -> i32 {
    if ELASTIC_PROS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set stretch ratio (0.1 to 10.0, 1.0 = no change)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_ratio(track_id: u32, ratio: f64) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        elastic.set_stretch_ratio(ratio);
        1
    } else {
        0
    }
}

/// Set pitch shift in semitones (-24 to +24)
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_pitch(track_id: u32, semitones: f64) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        elastic.set_pitch_shift(semitones);
        1
    } else {
        0
    }
}

/// Set quality: 0=Preview, 1=Standard, 2=High, 3=Ultra
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_quality(track_id: u32, quality: u32) -> i32 {
    use rf_dsp::elastic_pro::StretchQuality;
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let q = match quality {
            0 => StretchQuality::Preview,
            1 => StretchQuality::Standard,
            2 => StretchQuality::High,
            3 => StretchQuality::Ultra,
            _ => StretchQuality::Standard,
        };
        elastic.set_quality(q);
        1
    } else {
        0
    }
}

/// Set mode: 0=Auto, 1=Polyphonic, 2=Monophonic, 3=Rhythmic, 4=Speech, 5=Creative
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_mode(track_id: u32, mode: u32) -> i32 {
    use rf_dsp::elastic_pro::StretchMode;
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let m = match mode {
            0 => StretchMode::Auto,
            1 => StretchMode::Polyphonic,
            2 => StretchMode::Monophonic,
            3 => StretchMode::Rhythmic,
            4 => StretchMode::Speech,
            5 => StretchMode::Creative,
            _ => StretchMode::Auto,
        };
        elastic.set_mode(m);
        1
    } else {
        0
    }
}

/// Enable/disable transient preservation
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_preserve_transients(track_id: u32, enabled: i32) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let mut config = elastic.config().clone();
        config.preserve_transients = enabled != 0;
        elastic.set_config(config);
        1
    } else {
        0
    }
}

/// Enable/disable formant preservation
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_preserve_formants(track_id: u32, enabled: i32) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let mut config = elastic.config().clone();
        config.preserve_formants = enabled != 0;
        elastic.set_config(config);
        1
    } else {
        0
    }
}

/// Enable/disable STN decomposition
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_use_stn(track_id: u32, enabled: i32) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let mut config = elastic.config().clone();
        config.use_stn = enabled != 0;
        elastic.set_config(config);
        1
    } else {
        0
    }
}

/// Set STN thresholds
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_set_stn_thresholds(track_id: u32, tonal: f64, transient: f64) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        let mut config = elastic.config().clone();
        config.tonal_threshold = tonal.clamp(0.0, 1.0);
        config.transient_threshold = transient.clamp(0.0, 1.0);
        elastic.set_config(config);
        1
    } else {
        0
    }
}

/// Reset ElasticPro
#[unsafe(no_mangle)]
pub extern "C" fn elastic_pro_reset(track_id: u32) -> i32 {
    let mut elastics = ELASTIC_PROS.write();
    if let Some(elastic) = elastics.get_mut(&track_id) {
        elastic.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MORPHING EQ - Preset Interpolation
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref MORPH_EQS: RwLock<std::collections::HashMap<u32, rf_dsp::eq_morph::MorphingEq>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create MorphingEq instance
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_morph::MorphingEq::new(sample_rate);
    MORPH_EQS.write().insert(track_id, eq);
    1
}

/// Destroy MorphingEq instance
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_destroy(track_id: u32) -> i32 {
    if MORPH_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set morph position (0.0 = Preset A, 1.0 = Preset B)
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_set_position(track_id: u32, position: f64) -> i32 {
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_morph(position);
        1
    } else {
        0
    }
}

/// Morph to preset A
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_to_a(track_id: u32) -> i32 {
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.morph_to_a();
        1
    } else {
        0
    }
}

/// Morph to preset B
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_to_b(track_id: u32) -> i32 {
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.morph_to_b();
        1
    } else {
        0
    }
}

/// Toggle A/B instantly
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_toggle_ab(track_id: u32) -> i32 {
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.toggle_ab();
        1
    } else {
        0
    }
}

/// Set morph speed (time in seconds)
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_set_speed(track_id: u32, speed_seconds: f64) -> i32 {
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        // Convert to per-sample rate (assuming 48kHz)
        eq.morph_speed = 1.0 / (speed_seconds * 48000.0).max(1.0);
        1
    } else {
        0
    }
}

/// Get current morph position
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_get_position(track_id: u32) -> f64 {
    let eqs = MORPH_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.morph_position
    } else {
        0.0
    }
}

/// Reset MorphingEq
#[unsafe(no_mangle)]
pub extern "C" fn morph_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = MORPH_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROOM CORRECTION EQ
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref ROOM_EQS: RwLock<std::collections::HashMap<u32, rf_dsp::eq_room::RoomCorrectionEq>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create RoomCorrectionEq instance
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_room::RoomCorrectionEq::new(sample_rate);
    ROOM_EQS.write().insert(track_id, eq);
    1
}

/// Destroy RoomCorrectionEq instance
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_destroy(track_id: u32) -> i32 {
    if ROOM_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set target curve: 0=Flat, 1=Harman, 2=B&K, 3=BBC, 4=X-Curve, 5=Custom
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_set_target_curve(track_id: u32, curve: u32) -> i32 {
    use rf_dsp::eq_room::TargetCurve;
    let mut eqs = ROOM_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.target = match curve {
            0 => TargetCurve::Flat,
            1 => TargetCurve::Harman,
            2 => TargetCurve::BAndK,
            3 => TargetCurve::BBC,
            4 => TargetCurve::XCurve,
            5 => TargetCurve::Custom,
            _ => TargetCurve::Flat,
        };
        1
    } else {
        0
    }
}

/// Set max correction amount (dB, e.g. 12.0)
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_set_max_correction(track_id: u32, max_db: f64) -> i32 {
    let mut eqs = ROOM_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.max_correction = max_db.clamp(0.0, 24.0);
        1
    } else {
        0
    }
}

/// Enable/disable cut-only mode (safer, no boosts)
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_set_cut_only(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = ROOM_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.cut_only = enabled != 0;
        1
    } else {
        0
    }
}

/// Enable/disable room correction
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_set_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = ROOM_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Get number of detected room modes
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_get_room_mode_count(track_id: u32) -> u32 {
    let eqs = ROOM_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.measurement.room_modes.len() as u32
    } else {
        0
    }
}

/// Reset RoomCorrectionEq
#[unsafe(no_mangle)]
pub extern "C" fn room_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = ROOM_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVELET ANALYSIS - Multi-resolution Analysis
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref WAVELETS: RwLock<std::collections::HashMap<u32, rf_dsp::wavelet::DWT>> =
        RwLock::new(std::collections::HashMap::new());
    static ref CQTS: RwLock<std::collections::HashMap<u32, rf_dsp::wavelet::CQT>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create DWT (Discrete Wavelet Transform) instance
/// wavelet_type: 0=Haar, 1=db2, 2=db4, 3=db6, 4=db8, 5=sym4, 6=sym8, 7=coif1, 8=coif2
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_dwt_create(track_id: u32, wavelet_type: u32) -> i32 {
    use rf_dsp::wavelet::WaveletType;
    let wt = match wavelet_type {
        0 => WaveletType::Haar,
        1 => WaveletType::Daubechies(2),
        2 => WaveletType::Daubechies(4),
        3 => WaveletType::Daubechies(6),
        4 => WaveletType::Daubechies(8),
        5 => WaveletType::Symlet(4),
        6 => WaveletType::Symlet(8),
        7 => WaveletType::Coiflet(1),
        8 => WaveletType::Coiflet(2),
        _ => WaveletType::Daubechies(4),
    };
    let dwt = rf_dsp::wavelet::DWT::new(wt);
    WAVELETS.write().insert(track_id, dwt);
    1
}

/// Destroy DWT instance
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_dwt_destroy(track_id: u32) -> i32 {
    if WAVELETS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set maximum decomposition level
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_dwt_set_max_level(track_id: u32, level: u32) -> i32 {
    let mut wavelets = WAVELETS.write();
    if let Some(dwt) = wavelets.get_mut(&track_id) {
        dwt.set_max_level(level as usize);
        1
    } else {
        0
    }
}

/// Create CQT (Constant-Q Transform) instance
/// min_freq/max_freq in Hz, bins_per_octave typically 12 or 24
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_cqt_create(
    track_id: u32,
    sample_rate: f64,
    min_freq: f64,
    max_freq: f64,
    bins_per_octave: u32,
) -> i32 {
    let cqt = rf_dsp::wavelet::CQT::new(sample_rate, min_freq, max_freq, bins_per_octave as usize);
    CQTS.write().insert(track_id, cqt);
    1
}

/// Create CQT with musical settings (C1 to C8, 12 bins/octave)
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_cqt_create_musical(track_id: u32, sample_rate: f64) -> i32 {
    let cqt = rf_dsp::wavelet::CQT::musical(sample_rate);
    CQTS.write().insert(track_id, cqt);
    1
}

/// Destroy CQT instance
#[unsafe(no_mangle)]
pub extern "C" fn wavelet_cqt_destroy(track_id: u32) -> i32 {
    if CQTS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MINIMUM PHASE EQ FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref MIN_PHASE_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_minimum_phase::MinPhaseEq>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create minimum phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_minimum_phase::MinPhaseEq::new(sample_rate);
    MIN_PHASE_EQS.write().insert(track_id, eq);
    1
}

/// Remove minimum phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_remove(track_id: u32) -> i32 {
    if MIN_PHASE_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Add band to minimum phase EQ
/// filter_type: 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch
/// Returns band index
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_add_band(
    track_id: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    filter_type: u32,
) -> i32 {
    let ft = match filter_type {
        0 => rf_dsp::eq_minimum_phase::MinPhaseFilterType::Bell,
        1 => rf_dsp::eq_minimum_phase::MinPhaseFilterType::LowShelf,
        2 => rf_dsp::eq_minimum_phase::MinPhaseFilterType::HighShelf,
        3 => rf_dsp::eq_minimum_phase::MinPhaseFilterType::LowCut,
        4 => rf_dsp::eq_minimum_phase::MinPhaseFilterType::HighCut,
        _ => rf_dsp::eq_minimum_phase::MinPhaseFilterType::Notch,
    };
    let mut eqs = MIN_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.add_band(freq, gain_db, q, ft) as i32
    } else {
        -1
    }
}

/// Set band parameters
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_set_band(
    track_id: u32,
    band_index: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
) -> i32 {
    let mut eqs = MIN_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band(band_index as usize, freq, gain_db, q);
        1
    } else {
        0
    }
}

/// Enable/disable band
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_set_band_enabled(
    track_id: u32,
    band_index: u32,
    enabled: i32,
) -> i32 {
    let mut eqs = MIN_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_enabled(band_index as usize, enabled != 0);
        1
    } else {
        0
    }
}

/// Remove band
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_remove_band(track_id: u32, band_index: u32) -> i32 {
    let mut eqs = MIN_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.remove_band(band_index as usize);
        1
    } else {
        0
    }
}

/// Get magnitude at frequency in dB
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_get_magnitude_at(track_id: u32, freq: f64) -> f64 {
    let eqs = MIN_PHASE_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        let mag = eq.magnitude_at(freq);
        20.0 * mag.log10()
    } else {
        0.0
    }
}

/// Get group delay at frequency in ms
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_get_group_delay_at(track_id: u32, freq: f64) -> f64 {
    let eqs = MIN_PHASE_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.group_delay_at(freq) * 1000.0
    } else {
        0.0
    }
}

/// Get number of bands
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_get_num_bands(track_id: u32) -> u32 {
    let eqs = MIN_PHASE_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.num_bands() as u32
    } else {
        0
    }
}

/// Reset minimum phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn min_phase_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = MIN_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO EQ FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref STEREO_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_stereo::StereoEq>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref BASS_MONOS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::eq_stereo::BassMono>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create stereo EQ
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::eq_stereo::StereoEq::new(sample_rate);
    STEREO_EQS.write().insert(track_id, eq);
    1
}

/// Remove stereo EQ
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_remove(track_id: u32) -> i32 {
    if STEREO_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Add band to stereo EQ
/// mode: 0=Stereo, 1=Left, 2=Right, 3=Mid, 4=Side
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_add_band(
    track_id: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    mode: u32,
) -> i32 {
    let stereo_mode = match mode {
        0 => rf_dsp::eq_stereo::StereoMode::Stereo,
        1 => rf_dsp::eq_stereo::StereoMode::Left,
        2 => rf_dsp::eq_stereo::StereoMode::Right,
        3 => rf_dsp::eq_stereo::StereoMode::Mid,
        _ => rf_dsp::eq_stereo::StereoMode::Side,
    };
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.add_band(freq, gain_db, q, stereo_mode) as i32
    } else {
        -1
    }
}

/// Set band parameters
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_band(
    track_id: u32,
    band_index: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band(band_index as usize, freq, gain_db, q);
        1
    } else {
        0
    }
}

/// Set band mode
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_band_mode(track_id: u32, band_index: u32, mode: u32) -> i32 {
    let stereo_mode = match mode {
        0 => rf_dsp::eq_stereo::StereoMode::Stereo,
        1 => rf_dsp::eq_stereo::StereoMode::Left,
        2 => rf_dsp::eq_stereo::StereoMode::Right,
        3 => rf_dsp::eq_stereo::StereoMode::Mid,
        _ => rf_dsp::eq_stereo::StereoMode::Side,
    };
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_band_mode(band_index as usize, stereo_mode);
        1
    } else {
        0
    }
}

/// Add width band (stereo width per frequency)
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_add_width_band(
    track_id: u32,
    freq: f64,
    bandwidth: f64,
    width: f64,
) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.add_width_band(freq, bandwidth, width) as i32
    } else {
        -1
    }
}

/// Set width band parameters
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_width_band(
    track_id: u32,
    band_index: u32,
    freq: f64,
    bandwidth: f64,
    width: f64,
) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_width_band(band_index as usize, freq, bandwidth, width);
        1
    } else {
        0
    }
}

/// Enable/disable bass mono
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_bass_mono_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.bass_mono_enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Set bass mono crossover frequency
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_bass_mono_freq(track_id: u32, freq: f64) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.bass_mono.set_crossover(freq);
        1
    } else {
        0
    }
}

/// Enable/disable global M/S mode
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_set_global_ms(track_id: u32, enabled: i32) -> i32 {
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.global_ms_mode = enabled != 0;
        1
    } else {
        0
    }
}

/// Reset stereo EQ
#[unsafe(no_mangle)]
pub extern "C" fn stereo_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = STEREO_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

/// Create standalone bass mono processor
#[unsafe(no_mangle)]
pub extern "C" fn bass_mono_create(track_id: u32, sample_rate: f64) -> i32 {
    let bm = rf_dsp::eq_stereo::BassMono::new(sample_rate);
    BASS_MONOS.write().insert(track_id, bm);
    1
}

/// Remove bass mono processor
#[unsafe(no_mangle)]
pub extern "C" fn bass_mono_remove(track_id: u32) -> i32 {
    if BASS_MONOS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set bass mono crossover
#[unsafe(no_mangle)]
pub extern "C" fn bass_mono_set_crossover(track_id: u32, freq: f64) -> i32 {
    let mut bms = BASS_MONOS.write();
    if let Some(bm) = bms.get_mut(&track_id) {
        bm.set_crossover(freq);
        1
    } else {
        0
    }
}

/// Set bass mono blend (0=stereo, 1=full mono)
#[unsafe(no_mangle)]
pub extern "C" fn bass_mono_set_blend(track_id: u32, blend: f64) -> i32 {
    let mut bms = BASS_MONOS.write();
    if let Some(bm) = bms.get_mut(&track_id) {
        bm.blend = blend.clamp(0.0, 1.0);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LINEAR PHASE EQ FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref LINEAR_PHASE_EQS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::linear_phase::LinearPhaseEQ>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create linear phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_create(track_id: u32, sample_rate: f64) -> i32 {
    let eq = rf_dsp::linear_phase::LinearPhaseEQ::new(sample_rate);
    LINEAR_PHASE_EQS.write().insert(track_id, eq);
    1
}

/// Remove linear phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_remove(track_id: u32) -> i32 {
    if LINEAR_PHASE_EQS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Add band to linear phase EQ
/// filter_type: 0=Bell, 1=LowShelf, 2=HighShelf, 3=LowCut, 4=HighCut, 5=Notch, 6=BandPass, 7=Tilt
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_add_band(
    track_id: u32,
    filter_type: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    slope: f64,
) -> i32 {
    let ft = match filter_type {
        0 => rf_dsp::linear_phase::LinearPhaseFilterType::Bell,
        1 => rf_dsp::linear_phase::LinearPhaseFilterType::LowShelf,
        2 => rf_dsp::linear_phase::LinearPhaseFilterType::HighShelf,
        3 => rf_dsp::linear_phase::LinearPhaseFilterType::LowCut,
        4 => rf_dsp::linear_phase::LinearPhaseFilterType::HighCut,
        5 => rf_dsp::linear_phase::LinearPhaseFilterType::Notch,
        6 => rf_dsp::linear_phase::LinearPhaseFilterType::BandPass,
        _ => rf_dsp::linear_phase::LinearPhaseFilterType::Tilt,
    };
    let band = rf_dsp::linear_phase::LinearPhaseBand {
        filter_type: ft,
        frequency: freq,
        gain: gain_db,
        q,
        slope,
        enabled: true,
    };
    let mut eqs = LINEAR_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.add_band(band) as i32
    } else {
        -1
    }
}

/// Update band parameters
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_update_band(
    track_id: u32,
    band_index: u32,
    filter_type: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
    slope: f64,
    enabled: i32,
) -> i32 {
    let ft = match filter_type {
        0 => rf_dsp::linear_phase::LinearPhaseFilterType::Bell,
        1 => rf_dsp::linear_phase::LinearPhaseFilterType::LowShelf,
        2 => rf_dsp::linear_phase::LinearPhaseFilterType::HighShelf,
        3 => rf_dsp::linear_phase::LinearPhaseFilterType::LowCut,
        4 => rf_dsp::linear_phase::LinearPhaseFilterType::HighCut,
        5 => rf_dsp::linear_phase::LinearPhaseFilterType::Notch,
        6 => rf_dsp::linear_phase::LinearPhaseFilterType::BandPass,
        _ => rf_dsp::linear_phase::LinearPhaseFilterType::Tilt,
    };
    let band = rf_dsp::linear_phase::LinearPhaseBand {
        filter_type: ft,
        frequency: freq,
        gain: gain_db,
        q,
        slope,
        enabled: enabled != 0,
    };
    let mut eqs = LINEAR_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.update_band(band_index as usize, band);
        1
    } else {
        0
    }
}

/// Remove band
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_remove_band(track_id: u32, band_index: u32) -> i32 {
    let mut eqs = LINEAR_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.remove_band(band_index as usize);
        1
    } else {
        0
    }
}

/// Get band count
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_get_band_count(track_id: u32) -> u32 {
    let eqs = LINEAR_PHASE_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.band_count() as u32
    } else {
        0
    }
}

/// Set bypass
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_set_bypass(track_id: u32, bypass: i32) -> i32 {
    let mut eqs = LINEAR_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.set_bypass(bypass != 0);
        1
    } else {
        0
    }
}

/// Get latency in samples
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_get_latency(track_id: u32) -> u32 {
    use rf_dsp::Processor;
    let eqs = LINEAR_PHASE_EQS.read();
    if let Some(eq) = eqs.get(&track_id) {
        eq.latency() as u32
    } else {
        0
    }
}

/// Reset linear phase EQ
#[unsafe(no_mangle)]
pub extern "C" fn linear_phase_eq_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut eqs = LINEAR_PHASE_EQS.write();
    if let Some(eq) = eqs.get_mut(&track_id) {
        eq.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref CHANNEL_STRIPS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::channel::ChannelStrip>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create channel strip
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_create(track_id: u32, sample_rate: f64) -> i32 {
    let strip = rf_dsp::channel::ChannelStrip::new(sample_rate);
    CHANNEL_STRIPS.write().insert(track_id, strip);
    1
}

/// Remove channel strip
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_remove(track_id: u32) -> i32 {
    if CHANNEL_STRIPS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set input gain in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_input_gain(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_input_gain_db(db);
        1
    } else {
        0
    }
}

/// Set output gain in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_output_gain(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_output_gain_db(db);
        1
    } else {
        0
    }
}

/// Enable/disable HPF
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_hpf_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_hpf_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set HPF frequency
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_hpf_freq(track_id: u32, freq: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_hpf_freq(freq);
        1
    } else {
        0
    }
}

/// Enable/disable gate
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_gate_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_gate_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set gate threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_gate_threshold(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_gate_threshold(db);
        1
    } else {
        0
    }
}

/// Enable/disable compressor
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set compressor threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_threshold(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_threshold(db);
        1
    } else {
        0
    }
}

/// Set compressor ratio
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_ratio(track_id: u32, ratio: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_ratio(ratio);
        1
    } else {
        0
    }
}

/// Set compressor attack in ms
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_attack(track_id: u32, ms: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_attack(ms);
        1
    } else {
        0
    }
}

/// Set compressor release in ms
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_release(track_id: u32, ms: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_release(ms);
        1
    } else {
        0
    }
}

/// Set compressor makeup gain in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_makeup(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_makeup(db);
        1
    } else {
        0
    }
}

/// Set compressor link (0=independent, 1=linked)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_comp_link(track_id: u32, link: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_comp_link(link);
        1
    } else {
        0
    }
}

/// Enable/disable EQ
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_eq_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_eq_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set EQ low shelf (freq, gain_db)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_eq_low(track_id: u32, freq: f64, gain_db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_eq_low(freq, gain_db);
        1
    } else {
        0
    }
}

/// Set EQ low-mid parametric (freq, gain_db, q)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_eq_low_mid(
    track_id: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_eq_low_mid(freq, gain_db, q);
        1
    } else {
        0
    }
}

/// Set EQ high-mid parametric (freq, gain_db, q)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_eq_high_mid(
    track_id: u32,
    freq: f64,
    gain_db: f64,
    q: f64,
) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_eq_high_mid(freq, gain_db, q);
        1
    } else {
        0
    }
}

/// Set EQ high shelf (freq, gain_db)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_eq_high(track_id: u32, freq: f64, gain_db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_eq_high(freq, gain_db);
        1
    } else {
        0
    }
}

/// Enable/disable limiter
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_limiter_enabled(track_id: u32, enabled: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_limiter_enabled(enabled != 0);
        1
    } else {
        0
    }
}

/// Set limiter threshold in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_limiter_threshold(track_id: u32, db: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_limiter_threshold(db);
        1
    } else {
        0
    }
}

/// Set pan (-1=left, 0=center, 1=right)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_pan(track_id: u32, pan: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_pan(pan);
        1
    } else {
        0
    }
}

/// Set width (0=mono, 1=normal, 2=wide)
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_width(track_id: u32, width: f64) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_width(width);
        1
    } else {
        0
    }
}

/// Set mute
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_mute(track_id: u32, mute: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_mute(mute != 0);
        1
    } else {
        0
    }
}

/// Set solo
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_solo(track_id: u32, solo: i32) -> i32 {
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_solo(solo != 0);
        1
    } else {
        0
    }
}

/// Set processing order
/// 0=GateCompEq, 1=GateEqComp, 2=EqGateComp, 3=EqCompGate
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_set_processing_order(track_id: u32, order: u32) -> i32 {
    let po = match order {
        0 => rf_dsp::channel::ProcessingOrder::GateCompEq,
        1 => rf_dsp::channel::ProcessingOrder::GateEqComp,
        2 => rf_dsp::channel::ProcessingOrder::EqGateComp,
        _ => rf_dsp::channel::ProcessingOrder::EqCompGate,
    };
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.set_processing_order(po);
        1
    } else {
        0
    }
}

/// Get input peak levels in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_get_input_peak(
    track_id: u32,
    out_l: *mut f64,
    out_r: *mut f64,
) -> i32 {
    let strips = CHANNEL_STRIPS.read();
    if let Some(strip) = strips.get(&track_id) {
        let (l, r) = strip.input_peak_db();
        if !out_l.is_null() {
            unsafe {
                *out_l = l;
            }
        }
        if !out_r.is_null() {
            unsafe {
                *out_r = r;
            }
        }
        1
    } else {
        0
    }
}

/// Get output peak levels in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_get_output_peak(
    track_id: u32,
    out_l: *mut f64,
    out_r: *mut f64,
) -> i32 {
    let strips = CHANNEL_STRIPS.read();
    if let Some(strip) = strips.get(&track_id) {
        let (l, r) = strip.output_peak_db();
        if !out_l.is_null() {
            unsafe {
                *out_l = l;
            }
        }
        if !out_r.is_null() {
            unsafe {
                *out_r = r;
            }
        }
        1
    } else {
        0
    }
}

/// Get compressor gain reduction in dB
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_get_gain_reduction(track_id: u32) -> f64 {
    let strips = CHANNEL_STRIPS.read();
    if let Some(strip) = strips.get(&track_id) {
        strip.gain_reduction_db()
    } else {
        0.0
    }
}

/// Reset channel strip
#[unsafe(no_mangle)]
pub extern "C" fn channel_strip_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut strips = CHANNEL_STRIPS.write();
    if let Some(strip) = strips.get_mut(&track_id) {
        strip.reset();
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SURROUND PANNER FFI
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SURROUND_PANNERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::surround::SurroundPanner>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
    static ref AMBISONICS_ENCODERS: parking_lot::RwLock<std::collections::HashMap<u32, rf_dsp::surround::AmbisonicsEncoder>> =
        parking_lot::RwLock::new(std::collections::HashMap::new());
}

/// Create surround panner
/// layout: 0=Stereo, 1=5.1, 2=7.1, 3=7.1.4 Atmos, 4=9.1.6 Atmos
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_create(track_id: u32, layout: u32) -> i32 {
    let channel_layout = match layout {
        0 => rf_dsp::surround::ChannelLayout::Stereo,
        1 => rf_dsp::surround::ChannelLayout::Surround51,
        2 => rf_dsp::surround::ChannelLayout::Surround71,
        3 => rf_dsp::surround::ChannelLayout::Surround714,
        4 => rf_dsp::surround::ChannelLayout::Surround916,
        _ => rf_dsp::surround::ChannelLayout::Surround51,
    };
    let panner = rf_dsp::surround::SurroundPanner::new(channel_layout);
    SURROUND_PANNERS.write().insert(track_id, panner);
    1
}

/// Remove surround panner
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_remove(track_id: u32) -> i32 {
    if SURROUND_PANNERS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set position XYZ (-1 to 1)
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_set_position(track_id: u32, x: f64, y: f64, z: f64) -> i32 {
    let mut panners = SURROUND_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_position(rf_dsp::surround::Position3D::new(x, y, z));
        1
    } else {
        0
    }
}

/// Set position from azimuth/elevation in degrees
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_set_position_spherical(
    track_id: u32,
    azimuth: f64,
    elevation: f64,
) -> i32 {
    let mut panners = SURROUND_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_position_spherical(azimuth, elevation);
        1
    } else {
        0
    }
}

/// Set spread (0=point, 1=omnidirectional)
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_set_spread(track_id: u32, spread: f64) -> i32 {
    let mut panners = SURROUND_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_spread(spread);
        1
    } else {
        0
    }
}

/// Set LFE level (0-1)
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_set_lfe_level(track_id: u32, level: f64) -> i32 {
    let mut panners = SURROUND_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_lfe_level(level);
        1
    } else {
        0
    }
}

/// Set distance (0-2, affects attenuation)
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_set_distance(track_id: u32, distance: f64) -> i32 {
    let mut panners = SURROUND_PANNERS.write();
    if let Some(panner) = panners.get_mut(&track_id) {
        panner.set_distance(distance);
        1
    } else {
        0
    }
}

/// Get speaker gains
/// out_gains must have enough space for all speakers in the layout
/// Returns number of speakers
#[unsafe(no_mangle)]
pub extern "C" fn surround_panner_get_gains(
    track_id: u32,
    out_gains: *mut f64,
    max_count: usize,
) -> usize {
    let panners = SURROUND_PANNERS.read();
    if let Some(panner) = panners.get(&track_id) {
        let gains = panner.gains();
        let count = gains.len().min(max_count);
        if !out_gains.is_null() {
            for (i, &gain) in gains.iter().take(count).enumerate() {
                unsafe {
                    *out_gains.add(i) = gain;
                }
            }
        }
        count
    } else {
        0
    }
}

/// Create ambisonics encoder
#[unsafe(no_mangle)]
pub extern "C" fn ambisonics_encoder_create(track_id: u32) -> i32 {
    let encoder = rf_dsp::surround::AmbisonicsEncoder::new();
    AMBISONICS_ENCODERS.write().insert(track_id, encoder);
    1
}

/// Remove ambisonics encoder
#[unsafe(no_mangle)]
pub extern "C" fn ambisonics_encoder_remove(track_id: u32) -> i32 {
    if AMBISONICS_ENCODERS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set ambisonics position in degrees
#[unsafe(no_mangle)]
pub extern "C" fn ambisonics_encoder_set_position(
    track_id: u32,
    azimuth: f64,
    elevation: f64,
) -> i32 {
    let mut encoders = AMBISONICS_ENCODERS.write();
    if let Some(enc) = encoders.get_mut(&track_id) {
        enc.set_position(azimuth, elevation);
        1
    } else {
        0
    }
}

/// Set ambisonics gain
#[unsafe(no_mangle)]
pub extern "C" fn ambisonics_encoder_set_gain(track_id: u32, gain: f64) -> i32 {
    let mut encoders = AMBISONICS_ENCODERS.write();
    if let Some(enc) = encoders.get_mut(&track_id) {
        enc.set_gain(gain);
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_track_creation_ffi() {
        engine_clear_all();

        let name = CString::new("Test Track").unwrap();
        let track_id = engine_create_track(name.as_ptr(), 0xFF0000, 0);

        assert_ne!(track_id, 0);
        assert_eq!(engine_get_track_count(), 1);
    }

    #[test]
    fn test_clip_operations_ffi() {
        engine_clear_all();

        let track_name = CString::new("Track 1").unwrap();
        let track_id = engine_create_track(track_name.as_ptr(), 0xFF0000, 0);

        let clip_name = CString::new("Clip 1").unwrap();
        let clip_id = engine_add_clip(track_id, clip_name.as_ptr(), 0.0, 5.0, 0.0, 5.0);

        assert_ne!(clip_id, 0);

        // Move clip
        assert_eq!(engine_move_clip(clip_id, track_id, 2.0), 1);

        // Split clip
        let new_clip_id = engine_split_clip(clip_id, 3.5);
        assert_ne!(new_clip_id, 0);
    }

    #[test]
    fn test_loop_region_ffi() {
        engine_clear_all();

        engine_set_loop_region(1.0, 5.0);
        engine_set_loop_enabled(1);

        let mut start: f64 = 0.0;
        let mut end: f64 = 0.0;
        let mut enabled: i32 = 0;

        engine_get_loop_region(&mut start, &mut end, &mut enabled);

        assert_eq!(start, 1.0);
        assert_eq!(end, 5.0);
        assert_eq!(enabled, 1);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SATURATION PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    static ref SATURATORS: RwLock<std::collections::HashMap<u32, rf_dsp::saturation::StereoSaturator>> =
        RwLock::new(std::collections::HashMap::new());
}

/// Create saturation processor for track
#[unsafe(no_mangle)]
pub extern "C" fn saturation_create(track_id: u32, sample_rate: f64) -> i32 {
    let saturator = rf_dsp::saturation::StereoSaturator::new(sample_rate);
    SATURATORS.write().insert(track_id, saturator);
    1
}

/// Destroy saturation processor
#[unsafe(no_mangle)]
pub extern "C" fn saturation_destroy(track_id: u32) -> i32 {
    if SATURATORS.write().remove(&track_id).is_some() {
        1
    } else {
        0
    }
}

/// Set saturation type
/// 0 = Tape, 1 = Tube, 2 = Transistor, 3 = SoftClip, 4 = HardClip, 5 = Foldback
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_type(track_id: u32, sat_type: u8) -> i32 {
    use rf_dsp::saturation::SaturationType;
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        let t = match sat_type {
            0 => SaturationType::Tape,
            1 => SaturationType::Tube,
            2 => SaturationType::Transistor,
            3 => SaturationType::SoftClip,
            4 => SaturationType::HardClip,
            5 => SaturationType::Foldback,
            _ => SaturationType::Tape,
        };
        sat.set_both(|s| s.set_type(t));
        1
    } else {
        0
    }
}

/// Set drive amount (0.0-1.0, maps to 0-40dB internally)
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_drive(track_id: u32, drive: f64) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        let drive_db = drive.clamp(0.0, 1.0) * 40.0;
        sat.set_both(|s| s.set_drive_db(drive_db));
        1
    } else {
        0
    }
}

/// Set drive in dB directly (-20 to +40)
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_drive_db(track_id: u32, drive_db: f64) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.set_both(|s| s.set_drive_db(drive_db));
        1
    } else {
        0
    }
}

/// Set dry/wet mix (0.0 = dry, 1.0 = wet)
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_mix(track_id: u32, mix: f64) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.set_both(|s| s.set_mix(mix));
        1
    } else {
        0
    }
}

/// Set output level in dB (-24 to +12)
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_output_db(track_id: u32, output_db: f64) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.set_both(|s| s.set_output_db(output_db));
        1
    } else {
        0
    }
}

/// Set tape bias (0.0-1.0, only affects Tape mode)
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_tape_bias(track_id: u32, bias: f64) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.set_both(|s| s.set_tape_bias(bias));
        1
    } else {
        0
    }
}

/// Reset saturation processor state
#[unsafe(no_mangle)]
pub extern "C" fn saturation_reset(track_id: u32) -> i32 {
    use rf_dsp::Processor;
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.reset();
        1
    } else {
        0
    }
}

/// Set stereo link mode
#[unsafe(no_mangle)]
pub extern "C" fn saturation_set_link(track_id: u32, linked: i32) -> i32 {
    let mut sats = SATURATORS.write();
    if let Some(sat) = sats.get_mut(&track_id) {
        sat.set_link(linked != 0);
        1
    } else {
        0
    }
}

/// Check if saturation processor exists
#[unsafe(no_mangle)]
pub extern "C" fn saturation_exists(track_id: u32) -> i32 {
    if SATURATORS.read().contains_key(&track_id) {
        1
    } else {
        0
    }
}
