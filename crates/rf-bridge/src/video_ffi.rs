//! Video FFI — Bridges rf-video (VideoEngine) to Flutter via C FFI.
//!
//! 12 functions matching native_ffi.dart typedefs:
//! - videoAddTrack, videoImport, videoSetPlayhead, videoGetPlayhead
//! - videoGetFrame, videoFreeFrame, videoGetInfoJson
//! - videoGenerateThumbnails, videoGetTrackCount, videoClearAll
//! - videoFormatTimecode, videoParseTimecode

use std::ffi::{c_char, CStr, CString};
use std::sync::OnceLock;

use parking_lot::RwLock;
use rf_core::SampleRate;
use rf_video::{FrameRate, Timecode, TimecodeFormat, VideoEngine};

/// Global video engine singleton — initialized lazily on first use.
/// Uses sample rate from the audio engine (default 48000 until set).
static VIDEO_ENGINE: OnceLock<RwLock<VideoEngine>> = OnceLock::new();

fn video_engine() -> &'static RwLock<VideoEngine> {
    VIDEO_ENGINE.get_or_init(|| {
        log::info!("VIDEO FFI: VideoEngine initialized (48000 Hz default)");
        RwLock::new(VideoEngine::new(SampleRate::Hz48000))
    })
}

// ════════════════════════════════════════════════════════════════════
// TRACK MANAGEMENT
// ════════════════════════════════════════════════════════════════════

/// Create a new video track. Returns track ID, or 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn video_add_track(name: *const c_char) -> u64 {
    if name.is_null() {
        log::error!("VIDEO FFI: video_add_track — null name pointer");
        return 0;
    }

    let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            log::error!("VIDEO FFI: video_add_track — invalid UTF-8 name");
            return 0;
        }
    };

    let mut engine = video_engine().write();
    let track_id = engine.add_track(name_str);
    log::info!("VIDEO FFI: Added track '{}' → id={}", name_str, track_id);
    track_id
}

/// Get the number of video tracks.
#[unsafe(no_mangle)]
pub extern "C" fn video_get_track_count() -> u32 {
    let engine = video_engine().read();
    engine.tracks().len() as u32
}

/// Clear all video tracks and clips.
#[unsafe(no_mangle)]
pub extern "C" fn video_clear_all() {
    // Re-initialize the engine to clear all state
    let mut engine = video_engine().write();
    let sr = engine.sample_rate();
    *engine = VideoEngine::new(sr);
    log::info!("VIDEO FFI: Cleared all video state");
}

// ════════════════════════════════════════════════════════════════════
// IMPORT & CLIPS
// ════════════════════════════════════════════════════════════════════

/// Import a video file onto a track. Returns clip ID, or 0 on failure.
#[unsafe(no_mangle)]
pub extern "C" fn video_import(
    track_id: u64,
    path: *const c_char,
    timeline_start_samples: u64,
) -> u64 {
    if path.is_null() {
        log::error!("VIDEO FFI: video_import — null path pointer");
        return 0;
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            log::error!("VIDEO FFI: video_import — invalid UTF-8 path");
            return 0;
        }
    };

    let mut engine = video_engine().write();
    match engine.import_video(track_id, path_str, timeline_start_samples) {
        Ok(clip_id) => {
            log::info!(
                "VIDEO FFI: Imported '{}' → track={}, clip={}, start={}",
                path_str, track_id, clip_id, timeline_start_samples
            );
            clip_id
        }
        Err(e) => {
            log::error!("VIDEO FFI: Import failed — {}", e);
            0
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// PLAYHEAD
// ════════════════════════════════════════════════════════════════════

/// Set playhead position (in samples).
#[unsafe(no_mangle)]
pub extern "C" fn video_set_playhead(samples: u64) {
    let mut engine = video_engine().write();
    engine.set_playhead(samples);
}

/// Get current playhead position (in samples).
#[unsafe(no_mangle)]
pub extern "C" fn video_get_playhead() -> u64 {
    let engine = video_engine().read();
    engine.playhead()
}

// ════════════════════════════════════════════════════════════════════
// FRAME ACCESS
// ════════════════════════════════════════════════════════════════════

/// Get a video frame as RGBA pixel data.
/// Returns pointer to RGBA buffer (caller MUST call video_free_frame to release).
/// Output params: width, height, data_size are written via pointers.
/// Returns null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn video_get_frame(
    _clip_id: u64,
    _frame_samples: u64,
    out_width: *mut u32,
    out_height: *mut u32,
    out_data_size: *mut u64,
) -> *mut u8 {
    if out_width.is_null() || out_height.is_null() || out_data_size.is_null() {
        log::error!("VIDEO FFI: video_get_frame — null output pointer");
        return std::ptr::null_mut();
    }

    let mut engine = video_engine().write();
    match engine.get_frame_at_playhead() {
        Ok(Some(frame)) => {
            let rgba = frame.to_rgba();
            let width = frame.width;
            let height = frame.height;
            let size = rgba.len() as u64;

            // Allocate on heap, hand ownership to caller
            let boxed = rgba.into_boxed_slice();
            let ptr = Box::into_raw(boxed) as *mut u8;

            unsafe {
                *out_width = width;
                *out_height = height;
                *out_data_size = size;
            }

            ptr
        }
        Ok(None) => {
            // No frame available at playhead — return placeholder
            unsafe {
                *out_width = 0;
                *out_height = 0;
                *out_data_size = 0;
            }
            std::ptr::null_mut()
        }
        Err(e) => {
            log::error!("VIDEO FFI: get_frame failed — {}", e);
            unsafe {
                *out_width = 0;
                *out_height = 0;
                *out_data_size = 0;
            }
            std::ptr::null_mut()
        }
    }
}

/// Free a frame buffer previously returned by video_get_frame.
/// MUST be called with the exact pointer and size returned.
#[unsafe(no_mangle)]
pub extern "C" fn video_free_frame(data: *mut u8, size: u64) {
    if data.is_null() || size == 0 {
        return;
    }
    // Reconstruct the Box<[u8]> and drop it
    unsafe {
        let slice = std::slice::from_raw_parts_mut(data, size as usize);
        let _ = Box::from_raw(slice as *mut [u8]);
    }
}

// ════════════════════════════════════════════════════════════════════
// VIDEO INFO
// ════════════════════════════════════════════════════════════════════

/// Get video clip info as JSON string.
/// Returns heap-allocated C string (caller must free with standard CString logic).
/// Returns null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn video_get_info_json(clip_id: u64) -> *mut c_char {
    let engine = video_engine().read();

    // Find the clip across all tracks
    for track in engine.tracks() {
        for clip in &track.clips {
            if clip.id == clip_id {
                let info = &clip.source;
                let json = format!(
                    r#"{{"duration_frames":{},"frame_rate":{},"width":{},"height":{}}}"#,
                    info.duration_frames,
                    info.frame_rate.as_f64(),
                    info.width,
                    info.height,
                );
                return match CString::new(json) {
                    Ok(cs) => cs.into_raw(),
                    Err(_) => std::ptr::null_mut(),
                };
            }
        }
    }

    log::warn!("VIDEO FFI: video_get_info_json — clip {} not found", clip_id);
    std::ptr::null_mut()
}

// ════════════════════════════════════════════════════════════════════
// THUMBNAILS
// ════════════════════════════════════════════════════════════════════

/// Generate thumbnails for a clip. Returns count of thumbnails generated.
#[unsafe(no_mangle)]
pub extern "C" fn video_generate_thumbnails(
    clip_id: u64,
    width: u32,
    interval_frames: u64,
) -> u32 {
    let mut engine = video_engine().write();
    match engine.generate_thumbnails(clip_id, width, interval_frames) {
        Ok(strip) => {
            let count = strip.thumbnails.len() as u32;
            log::info!(
                "VIDEO FFI: Generated {} thumbnails for clip {} ({}px, interval={})",
                count, clip_id, width, interval_frames
            );
            count
        }
        Err(e) => {
            log::error!("VIDEO FFI: Thumbnail generation failed — {}", e);
            0
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// TIMECODE
// ════════════════════════════════════════════════════════════════════

/// Format seconds as timecode string (HH:MM:SS:FF).
/// Returns heap-allocated C string. Caller must free.
#[unsafe(no_mangle)]
pub extern "C" fn video_format_timecode(
    seconds: f64,
    frame_rate: f64,
    drop_frame: i32,
) -> *mut c_char {
    let fr = frame_rate_from_f64(frame_rate);
    let total_frames = (seconds * fr.as_f64()).round() as u64;

    let _format = if drop_frame != 0 {
        TimecodeFormat::DropFrame
    } else {
        TimecodeFormat::NonDropFrame
    };

    let tc = Timecode::from_frame_number(total_frames, &fr);
    let tc_str = format!("{}", tc);

    match CString::new(tc_str) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Parse a timecode string to seconds. Returns -1.0 on error.
#[unsafe(no_mangle)]
pub extern "C" fn video_parse_timecode(
    tc_str: *const c_char,
    frame_rate: f64,
) -> f64 {
    if tc_str.is_null() {
        return -1.0;
    }

    let s = match unsafe { CStr::from_ptr(tc_str) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1.0,
    };

    let fr = frame_rate_from_f64(frame_rate);

    // Detect drop frame by semicolon presence
    let format = if s.contains(';') {
        TimecodeFormat::DropFrame
    } else {
        TimecodeFormat::NonDropFrame
    };

    match Timecode::parse(s, format) {
        Ok(tc) => tc.to_seconds(&fr),
        Err(e) => {
            log::error!("VIDEO FFI: parse_timecode '{}' failed — {}", s, e);
            -1.0
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════

/// Convert an f64 frame rate to the nearest standard FrameRate variant.
fn frame_rate_from_f64(fps: f64) -> FrameRate {
    if (fps - 23.976).abs() < 0.1 {
        FrameRate::Fps23_976
    } else if (fps - 24.0).abs() < 0.1 {
        FrameRate::Fps24
    } else if (fps - 25.0).abs() < 0.1 {
        FrameRate::Fps25
    } else if (fps - 29.97).abs() < 0.1 {
        FrameRate::Fps29_97
    } else if (fps - 30.0).abs() < 0.1 {
        FrameRate::Fps30
    } else if (fps - 50.0).abs() < 0.1 {
        FrameRate::Fps50
    } else if (fps - 59.94).abs() < 0.1 {
        FrameRate::Fps59_94
    } else if (fps - 60.0).abs() < 0.1 {
        FrameRate::Fps60
    } else {
        FrameRate::Custom(fps)
    }
}
