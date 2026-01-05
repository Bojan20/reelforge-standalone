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

use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::ptr;
use std::sync::Arc;
use parking_lot::RwLock;

use crate::track_manager::{
    TrackManager, TrackId, ClipId, CrossfadeId, MarkerId,
    OutputBus, CrossfadeCurve, Clip,
};
use crate::audio_import::{AudioImporter, ImportedAudio};
use crate::waveform::{StereoWaveformPeaks, WaveformCache, NUM_LOD_LEVELS, SAMPLES_PER_PEAK};
use crate::playback::{PlaybackEngine, PlaybackState, AudioCache};
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
            || UNDO_MANAGER.read().undo_count() != self.last_saved_undo_count.load(Ordering::Relaxed)
    }

    fn mark_dirty(&self) {
        self.is_dirty.store(true, std::sync::atomic::Ordering::Relaxed);
    }

    fn mark_clean(&self) {
        use std::sync::atomic::Ordering;
        self.is_dirty.store(false, Ordering::Relaxed);
        self.last_saved_undo_count.store(
            UNDO_MANAGER.read().undo_count(),
            Ordering::Relaxed
        );
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
    CString::new(s).map(|cs| cs.into_raw()).unwrap_or(ptr::null_mut())
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT FFI
// ═══════════════════════════════════════════════════════════════════════════

/// Create a new track
///
/// Returns track ID (u64) or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn engine_create_track(
    name: *const c_char,
    color: u32,
    bus_id: u32,
) -> u64 {
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

/// Set track volume (0.0 - 1.5)
#[unsafe(no_mangle)]
pub extern "C" fn engine_set_track_volume(track_id: u64, volume: f64) -> i32 {
    TRACK_MANAGER.update_track(TrackId(track_id), |track| {
        track.volume = volume.clamp(0.0, 1.5);
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
pub extern "C" fn engine_import_audio(
    path: *const c_char,
    track_id: u64,
    start_time: f64,
) -> u64 {
    let path_str = match unsafe { cstr_to_string(path) } {
        Some(p) => p,
        None => return 0,
    };

    // Import audio file
    let imported = match AudioImporter::import(Path::new(&path_str)) {
        Ok(audio) => Arc::new(audio),
        Err(_) => return 0,
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
    IMPORTED_AUDIO.write().insert(clip_id, imported);

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
pub extern "C" fn engine_move_clip(
    clip_id: u64,
    target_track_id: u64,
    start_time: f64,
) -> i32 {
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
    TRACK_MANAGER.get_clip(ClipId(clip_id))
        .map(|c| c.duration)
        .unwrap_or(-1.0)
}

/// Get clip source duration (original file duration in seconds)
/// Returns -1.0 if clip not found
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_clip_source_duration(clip_id: u64) -> f64 {
    TRACK_MANAGER.get_clip(ClipId(clip_id))
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
    if let Some(audio) = IMPORTED_AUDIO.read().values().find(|a| a.source_path == path_str) {
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
        let peaks = stereo_peaks.left.get_peaks_in_range(start_time, end_time, pixels_per_second);
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
pub extern "C" fn engine_get_loop_region(out_start: *mut f64, out_end: *mut f64, out_enabled: *mut i32) {
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
pub extern "C" fn engine_add_marker(
    name: *const c_char,
    time: f64,
    color: u32,
) -> u64 {
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
pub extern "C" fn engine_process_audio(
    output_l: *mut f64,
    output_r: *mut f64,
    frames: usize,
) {
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
    PLAYBACK_ENGINE.position.set_loop(region.start, region.end, region.enabled);
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
        PLAYBACK_ENGINE.get_bus_state(bus_idx as usize)
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
        if PLAYBACK_ENGINE.get_bus_state(bus_idx as usize).map(|s| s.muted).unwrap_or(false) {
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
        if PLAYBACK_ENGINE.get_bus_state(bus_idx as usize).map(|s| s.soloed).unwrap_or(false) {
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
        unsafe { *out_left = peak_l; }
    }
    if !out_right.is_null() {
        unsafe { *out_right = peak_r; }
    }
}

/// Get RMS meters
/// Returns linear amplitude (0.0 to 1.0+)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_rms_meters(out_left: *mut f64, out_right: *mut f64) {
    let (rms_l, rms_r) = PLAYBACK_ENGINE.get_rms();
    if !out_left.is_null() {
        unsafe { *out_left = rms_l; }
    }
    if !out_right.is_null() {
        unsafe { *out_right = rms_r; }
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
        unsafe { *out_momentary = momentary; }
    }
    if !out_short.is_null() {
        unsafe { *out_short = short; }
    }
    if !out_integrated.is_null() {
        unsafe { *out_integrated = integrated; }
    }
}

/// Get true peak meters (left, right)
/// Returns values in dBTP per ITU-R BS.1770-4 (4x oversampled)
#[unsafe(no_mangle)]
pub extern "C" fn engine_get_true_peak_meters(out_left: *mut f64, out_right: *mut f64) {
    let (db_l, db_r) = PLAYBACK_ENGINE.get_true_peak();

    if !out_left.is_null() {
        unsafe { *out_left = db_l; }
    }
    if !out_right.is_null() {
        unsafe { *out_right = db_r; }
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
use std::thread;
use std::sync::mpsc;

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

        log::info!("Starting audio stream: {} Hz, {} channels",
                   config.sample_rate().0, channels);

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

    if AUDIO_STREAM_RUNNING.load(Ordering::Acquire) { 1 } else { 0 }
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
    if AUDIO_STREAM_RUNNING.load(Ordering::Relaxed) { 1 } else { 0 }
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
    let path_opt = unsafe { cstr_to_string(path) }
        .filter(|s| !s.is_empty());
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
    let imported_audio_bytes: usize = IMPORTED_AUDIO.read()
        .values()
        .map(|a| a.samples.len() * std::mem::size_of::<f32>())
        .sum();

    let total_bytes = audio_cache_bytes + waveform_cache_bytes + imported_audio_bytes;
    (total_bytes as f32) / (1024.0 * 1024.0)
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ FFI (DEPRECATED - use rf-bridge/api.rs for Flutter)
// ═══════════════════════════════════════════════════════════════════════════
//
// NOTE: These C FFI functions are legacy stubs. For Flutter integration,
// use the rf-bridge crate which has full implementation with lock-free
// command queue (DspCommand) for real-time safe parameter updates.
//
// The actual DSP processing happens in rf-bridge/playback.rs via DspStorage.

/// Set EQ band enabled (legacy C FFI - use rf-bridge for Flutter)
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::eq_set_band_enabled for Flutter")]
pub extern "C" fn eq_set_band_enabled(track_id: u32, band_index: u8, enabled: i32) -> i32 {
    log::debug!("EQ track {} band {} enabled: {}", track_id, band_index, enabled != 0);
    // C FFI stub - Flutter uses rf-bridge command queue
    1
}

/// Set EQ band frequency (legacy C FFI - use rf-bridge for Flutter)
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::eq_set_band_frequency for Flutter")]
pub extern "C" fn eq_set_band_frequency(track_id: u32, band_index: u8, frequency: f64) -> i32 {
    log::debug!("EQ track {} band {} freq: {} Hz", track_id, band_index, frequency);
    // C FFI stub - Flutter uses rf-bridge command queue
    1
}

/// Set EQ band gain (legacy C FFI - use rf-bridge for Flutter)
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::eq_set_band_gain for Flutter")]
pub extern "C" fn eq_set_band_gain(track_id: u32, band_index: u8, gain: f64) -> i32 {
    log::debug!("EQ track {} band {} gain: {} dB", track_id, band_index, gain);
    // C FFI stub - Flutter uses rf-bridge command queue
    1
}

/// Set EQ band Q (legacy C FFI - use rf-bridge for Flutter)
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::eq_set_band_q for Flutter")]
pub extern "C" fn eq_set_band_q(track_id: u32, band_index: u8, q: f64) -> i32 {
    log::debug!("EQ track {} band {} Q: {}", track_id, band_index, q);
    // C FFI stub - Flutter uses rf-bridge command queue
    1
}

/// Set EQ bypass (legacy C FFI - use rf-bridge for Flutter)
#[unsafe(no_mangle)]
#[deprecated(note = "Use rf-bridge::api::eq_set_bypass for Flutter")]
pub extern "C" fn eq_set_bypass(track_id: u32, bypass: i32) -> i32 {
    log::debug!("EQ track {} bypass: {}", track_id, bypass != 0);
    // C FFI stub - Flutter uses rf-bridge command queue
    1
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
    let audio = IMPORTED_AUDIO.read()
        .get(&ClipId(clip_id))
        .cloned()
        .or_else(|| {
            // Try to load from source file
            match AudioImporter::import(std::path::Path::new(&clip.source_file)) {
                Ok(audio) => {
                    let arc = Arc::new(audio);
                    IMPORTED_AUDIO.write().insert(ClipId(clip_id), Arc::clone(&arc));
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
        log::warn!("Clip {} has near-zero peak level, skipping normalization", clip_id);
        return 1;
    }

    // Calculate gain needed to reach target
    let peak_db = 20.0 * (peak as f64).log10();
    let gain_db = target_db - peak_db;
    let gain_linear = 10.0_f64.powf(gain_db / 20.0);

    log::info!(
        "Normalizing clip {}: peak={:.2} dB, applying {:.2} dB gain",
        clip_id, peak_db, gain_db
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
    log::debug!("Fade in clip {} for {} sec, curve {}", clip_id, duration_sec, curve_type);
    1
}

/// Apply fade out to clip
#[unsafe(no_mangle)]
pub extern "C" fn clip_fade_out(clip_id: u64, duration_sec: f64, curve_type: u8) -> i32 {
    TRACK_MANAGER.update_clip(ClipId(clip_id), |clip| {
        clip.fade_out = duration_sec;
    });
    log::debug!("Fade out clip {} for {} sec, curve {}", clip_id, duration_sec, curve_type);
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

use crate::routing::{RoutingGraph, ChannelKind, OutputDestination, ChannelId};

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
    ROUTING_GRAPH.write().create_channel(ChannelKind::Audio, name.as_deref()).0
}

/// Delete a channel
/// Returns 1 on success, 0 if channel not found or is master
#[unsafe(no_mangle)]
pub extern "C" fn routing_delete_channel(channel_id: u32) -> i32 {
    if ROUTING_GRAPH.write().delete_channel(ChannelId(channel_id)) { 1 } else { 0 }
}

/// Set channel output to master
#[unsafe(no_mangle)]
pub extern "C" fn routing_set_output_master(channel_id: u32) -> i32 {
    match ROUTING_GRAPH.write().set_output(ChannelId(channel_id), OutputDestination::Master) {
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
        OutputDestination::Channel(ChannelId(to_id))
    ) {
        Ok(_) => 1,
        Err(_) => 0,
    }
}

/// Add send from channel to aux/bus
/// Returns 1 on success, 0 on error
#[unsafe(no_mangle)]
pub extern "C" fn routing_add_send(from_id: u32, to_id: u32, pre_fader: i32) -> i32 {
    match ROUTING_GRAPH.write().add_send(
        ChannelId(from_id),
        ChannelId(to_id),
        pre_fader != 0
    ) {
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
    ROUTING_GRAPH.read()
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
    ROUTING_GRAPH.read()
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
pub extern "C" fn routing_get_output(out_left: *mut f64, out_right: *mut f64, max_samples: usize) -> usize {
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

use crate::groups::{GroupManager, VcaFader, Group, FolderTrack, LinkParameter, LinkMode};

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
    GROUP_MANAGER.read()
        .vcas.get(&vca_id)
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
    if GROUP_MANAGER.read().is_vca_muted(track_id) { 1 } else { 0 }
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
    GROUP_MANAGER.read()
        .vcas.get(&vca_id)
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
        group.link_mode = if mode == 0 { LinkMode::Absolute } else { LinkMode::Relative };
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

    GROUP_MANAGER.read()
        .groups.get(&group_id)
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
    GROUP_MANAGER.read()
        .folders.get(&folder_id)
        .map(|f| if f.expanded { 1 } else { 0 })
        .unwrap_or(0)
}

/// Get folder children (fills buffer)
/// Returns actual count written
#[unsafe(no_mangle)]
pub extern "C" fn folder_get_children(folder_id: u64, out_track_ids: *mut u64, max_count: usize) -> usize {
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
    GROUP_MANAGER.read()
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
