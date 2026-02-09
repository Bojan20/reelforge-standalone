//! rf-video: Video Playback for FluxForge Studio
//!
//! Professional video playback for post-production:
#![allow(dead_code)]
#![allow(dropping_copy_types)]
//! - FFmpeg-based decoding (H.264, H.265, ProRes, DNxHD)
//! - Frame-accurate seeking
//! - Audio/video sync with sample-accurate timecode
//! - Thumbnail generation
//! - EDL/AAF import

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use crossbeam_channel::Sender;
use parking_lot::Mutex;
use thiserror::Error;

use rf_core::SampleRate;

pub mod decoder;
pub mod frame_cache;
pub mod thumbnail;
pub mod timecode;

pub use decoder::{PixelFormat, VideoDecoder, VideoFrame};
pub use frame_cache::{CacheConfig, FrameCache};
pub use thumbnail::{ThumbnailGenerator, ThumbnailStrip};
pub use timecode::{FrameRate, Timecode, TimecodeFormat};

// ============ Error Types ============

#[derive(Error, Debug)]
pub enum VideoError {
    #[error("Failed to open video file: {0}")]
    OpenFailed(String),

    #[error("Failed to decode frame: {0}")]
    DecodeFailed(String),

    #[error("Seek failed: {0}")]
    SeekFailed(String),

    #[error("Invalid timecode: {0}")]
    InvalidTimecode(String),

    #[error("Unsupported codec: {0}")]
    UnsupportedCodec(String),

    #[error("FFmpeg error: {0}")]
    FfmpegError(String),

    #[error("No video stream found")]
    NoVideoStream,

    #[error("No audio stream found")]
    NoAudioStream,

    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type VideoResult<T> = Result<T, VideoError>;

// ============ Video Info ============

/// Video file metadata
#[derive(Debug, Clone)]
pub struct VideoInfo {
    /// File path
    pub path: PathBuf,
    /// Duration in frames
    pub duration_frames: u64,
    /// Duration in seconds
    pub duration_secs: f64,
    /// Frame rate
    pub frame_rate: FrameRate,
    /// Width in pixels
    pub width: u32,
    /// Height in pixels
    pub height: u32,
    /// Pixel format
    pub pixel_format: PixelFormat,
    /// Video codec name
    pub codec: String,
    /// Bit rate (bits per second)
    pub bitrate: u64,
    /// Has audio track
    pub has_audio: bool,
    /// Audio sample rate
    pub audio_sample_rate: Option<u32>,
    /// Audio channels
    pub audio_channels: Option<u8>,
    /// Start timecode (if embedded)
    pub start_timecode: Option<Timecode>,
}

// ============ Video Track ============

/// Video track for timeline integration
#[derive(Debug, Clone)]
pub struct VideoTrack {
    /// Unique ID
    pub id: u64,
    /// Track name
    pub name: String,
    /// Video clips on this track
    pub clips: Vec<VideoClip>,
    /// Track visible
    pub visible: bool,
    /// Track locked
    pub locked: bool,
}

/// Video clip on timeline
#[derive(Debug, Clone)]
pub struct VideoClip {
    /// Unique ID
    pub id: u64,
    /// Source video info
    pub source: VideoInfo,
    /// Start position on timeline (samples)
    pub timeline_start: u64,
    /// End position on timeline (samples)
    pub timeline_end: u64,
    /// Source in point (frames)
    pub source_in: u64,
    /// Source out point (frames)
    pub source_out: u64,
    /// Clip name
    pub name: String,
    /// Opacity (0.0 - 1.0)
    pub opacity: f64,
}

impl VideoClip {
    /// Get the frame number for a given timeline position (samples)
    pub fn frame_at_position(&self, position_samples: u64, sample_rate: SampleRate) -> Option<u64> {
        if position_samples < self.timeline_start || position_samples >= self.timeline_end {
            return None;
        }

        let clip_offset_samples = position_samples - self.timeline_start;
        let clip_offset_secs = clip_offset_samples as f64 / sample_rate.as_f64();
        let frame_offset = (clip_offset_secs * self.source.frame_rate.as_f64()) as u64;

        Some(self.source_in + frame_offset)
    }
}

// ============ Video Player ============

/// State of video playback
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Stopped,
    Playing,
    Paused,
    Seeking,
    Buffering,
}

/// Video player with frame caching and A/V sync
pub struct VideoPlayer {
    /// Current video info
    info: Option<VideoInfo>,
    /// Decoder instance
    decoder: Option<Arc<Mutex<VideoDecoder>>>,
    /// Frame cache
    cache: FrameCache,
    /// Current frame
    current_frame: u64,
    /// Playback state
    state: PlaybackState,
    /// Master sample rate (for A/V sync)
    sample_rate: SampleRate,
    /// Preload thread sender
    preload_tx: Option<Sender<PreloadCommand>>,
}

enum PreloadCommand {
    LoadRange { start: u64, end: u64 },
    Stop,
}

impl VideoPlayer {
    pub fn new(sample_rate: SampleRate) -> Self {
        Self {
            info: None,
            decoder: None,
            cache: FrameCache::new(CacheConfig::default()),
            current_frame: 0,
            state: PlaybackState::Stopped,
            sample_rate,
            preload_tx: None,
        }
    }

    /// Open a video file
    pub fn open(&mut self, path: impl AsRef<Path>) -> VideoResult<VideoInfo> {
        let decoder = VideoDecoder::open(path.as_ref())?;
        let info = decoder.info().clone();

        self.info = Some(info.clone());
        self.decoder = Some(Arc::new(Mutex::new(decoder)));
        self.current_frame = 0;
        self.state = PlaybackState::Stopped;

        // Clear cache for new video
        self.cache.clear();

        Ok(info)
    }

    /// Close current video
    pub fn close(&mut self) {
        if let Some(tx) = self.preload_tx.take() {
            let _ = tx.send(PreloadCommand::Stop);
        }
        self.info = None;
        self.decoder = None;
        self.cache.clear();
        self.current_frame = 0;
        self.state = PlaybackState::Stopped;
    }

    /// Get current video info
    pub fn info(&self) -> Option<&VideoInfo> {
        self.info.as_ref()
    }

    /// Seek to frame
    pub fn seek_to_frame(&mut self, frame: u64) -> VideoResult<()> {
        if let Some(ref decoder) = self.decoder {
            let mut dec = decoder.lock();
            dec.seek_to_frame(frame)?;
            self.current_frame = frame;
        }
        Ok(())
    }

    /// Seek to timecode
    pub fn seek_to_timecode(&mut self, tc: &Timecode) -> VideoResult<()> {
        if let Some(ref info) = self.info {
            let frame = tc.to_frame_number(&info.frame_rate);
            self.seek_to_frame(frame)
        } else {
            Err(VideoError::SeekFailed("No video loaded".into()))
        }
    }

    /// Seek to sample position (for A/V sync)
    pub fn seek_to_sample(&mut self, sample: u64) -> VideoResult<()> {
        if let Some(ref info) = self.info {
            let time_secs = sample as f64 / self.sample_rate.as_f64();
            let frame = (time_secs * info.frame_rate.as_f64()) as u64;
            self.seek_to_frame(frame)
        } else {
            Err(VideoError::SeekFailed("No video loaded".into()))
        }
    }

    /// Get frame for current position
    pub fn get_current_frame(&mut self) -> VideoResult<Option<VideoFrame>> {
        // Try cache first
        if let Some(frame) = self.cache.get(self.current_frame) {
            return Ok(Some(frame));
        }

        // Decode if not cached
        if let Some(ref decoder) = self.decoder {
            let mut dec = decoder.lock();
            let frame = dec.decode_frame(self.current_frame)?;
            if let Some(ref f) = frame {
                self.cache.insert(self.current_frame, f.clone());
            }
            return Ok(frame);
        }

        Ok(None)
    }

    /// Get frame at specific frame number
    pub fn get_frame(&mut self, frame: u64) -> VideoResult<Option<VideoFrame>> {
        // Try cache first
        if let Some(f) = self.cache.get(frame) {
            return Ok(Some(f));
        }

        // Decode if not cached
        if let Some(ref decoder) = self.decoder {
            let mut dec = decoder.lock();
            let f = dec.decode_frame(frame)?;
            if let Some(ref decoded) = f {
                self.cache.insert(frame, decoded.clone());
            }
            return Ok(f);
        }

        Ok(None)
    }

    /// Advance to next frame
    pub fn next_frame(&mut self) -> VideoResult<()> {
        if let Some(ref info) = self.info
            && self.current_frame < info.duration_frames.saturating_sub(1)
        {
            self.current_frame += 1;
        }
        Ok(())
    }

    /// Go to previous frame
    pub fn prev_frame(&mut self) -> VideoResult<()> {
        if self.current_frame > 0 {
            self.current_frame -= 1;
        }
        Ok(())
    }

    /// Get current frame number
    pub fn current_frame(&self) -> u64 {
        self.current_frame
    }

    /// Get current timecode
    pub fn current_timecode(&self) -> Option<Timecode> {
        self.info
            .as_ref()
            .map(|info| Timecode::from_frame_number(self.current_frame, &info.frame_rate))
    }

    /// Get playback state
    pub fn state(&self) -> PlaybackState {
        self.state
    }

    /// Start playback
    pub fn play(&mut self) {
        self.state = PlaybackState::Playing;
    }

    /// Pause playback
    pub fn pause(&mut self) {
        self.state = PlaybackState::Paused;
    }

    /// Stop playback
    pub fn stop(&mut self) {
        self.state = PlaybackState::Stopped;
        self.current_frame = 0;
    }

    /// Update for playback (call from UI frame loop)
    /// Returns true if frame changed
    pub fn update(&mut self, _delta_time: Duration) -> bool {
        if self.state != PlaybackState::Playing {
            return false;
        }

        if let Some(ref info) = self.info {
            if self.current_frame < info.duration_frames.saturating_sub(1) {
                self.current_frame += 1;
                return true;
            } else {
                self.state = PlaybackState::Stopped;
            }
        }

        false
    }

    /// Preload frames in range for smooth playback
    pub fn preload_range(&mut self, start_frame: u64, end_frame: u64) {
        if let Some(ref decoder) = self.decoder {
            let decoder = Arc::clone(decoder);
            let cache = self.cache.clone();

            std::thread::spawn(move || {
                for frame in start_frame..=end_frame {
                    if cache.contains(frame) {
                        continue;
                    }

                    let mut dec = decoder.lock();
                    if let Ok(Some(f)) = dec.decode_frame(frame) {
                        cache.insert(frame, f);
                    }
                }
            });
        }
    }
}

// ============ Video Engine ============

/// Video engine for managing multiple video tracks
pub struct VideoEngine {
    /// Video tracks
    tracks: Vec<VideoTrack>,
    /// Active players (one per source)
    players: HashMap<u64, VideoPlayer>,
    /// Sample rate for A/V sync
    sample_rate: SampleRate,
    /// Current playhead position (samples)
    playhead: u64,
    /// Thumbnail generator
    thumbnails: ThumbnailGenerator,
}

impl VideoEngine {
    pub fn new(sample_rate: SampleRate) -> Self {
        Self {
            tracks: Vec::new(),
            players: HashMap::new(),
            sample_rate,
            playhead: 0,
            thumbnails: ThumbnailGenerator::new(),
        }
    }

    /// Add a video track
    pub fn add_track(&mut self, name: impl Into<String>) -> u64 {
        let id = self.tracks.len() as u64;
        self.tracks.push(VideoTrack {
            id,
            name: name.into(),
            clips: Vec::new(),
            visible: true,
            locked: false,
        });
        id
    }

    /// Import video to track
    pub fn import_video(
        &mut self,
        track_id: u64,
        path: impl AsRef<Path>,
        timeline_start: u64,
    ) -> VideoResult<u64> {
        // Create player for this source
        let mut player = VideoPlayer::new(self.sample_rate);
        let info = player.open(&path)?;

        let clip_id = self.players.len() as u64;

        // Calculate clip length in samples
        let clip_duration_secs = info.duration_secs;
        let clip_duration_samples = (clip_duration_secs * self.sample_rate.as_f64()) as u64;

        let clip = VideoClip {
            id: clip_id,
            source: info.clone(),
            timeline_start,
            timeline_end: timeline_start + clip_duration_samples,
            source_in: 0,
            source_out: info.duration_frames,
            name: path
                .as_ref()
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "Video".into()),
            opacity: 1.0,
        };

        // Add clip to track
        if let Some(track) = self.tracks.iter_mut().find(|t| t.id == track_id) {
            track.clips.push(clip);
        }

        self.players.insert(clip_id, player);

        Ok(clip_id)
    }

    /// Get frame at current playhead
    pub fn get_frame_at_playhead(&mut self) -> VideoResult<Option<VideoFrame>> {
        // Find topmost visible clip at playhead
        for track in self.tracks.iter().rev() {
            if !track.visible {
                continue;
            }

            for clip in &track.clips {
                if let Some(frame) = clip.frame_at_position(self.playhead, self.sample_rate)
                    && let Some(player) = self.players.get_mut(&clip.id)
                {
                    return player.get_frame(frame);
                }
            }
        }

        Ok(None)
    }

    /// Update playhead position
    pub fn set_playhead(&mut self, samples: u64) {
        self.playhead = samples;
    }

    /// Get playhead
    pub fn playhead(&self) -> u64 {
        self.playhead
    }

    /// Get all tracks
    pub fn tracks(&self) -> &[VideoTrack] {
        &self.tracks
    }

    /// Set sample rate (must match audio engine)
    pub fn set_sample_rate(&mut self, sr: SampleRate) {
        self.sample_rate = sr;
    }

    /// Get playhead in samples
    pub fn playhead_samples(&self) -> u64 {
        self.playhead
    }

    /// Seek to sample position
    pub fn seek_to_sample(&mut self, sample: u64) {
        self.playhead = sample;
        // Update all active players
        for player in self.players.values_mut() {
            let _ = player.seek_to_sample(sample);
        }
    }

    /// Get frames skipped (sync metric)
    pub fn frames_skipped(&self) -> u32 {
        // TODO: Track actual skipped frames during playback
        0
    }

    /// Get decode latency in ms (sync metric)
    pub fn decode_latency_ms(&self) -> f32 {
        // TODO: Track actual decode latency
        0.0
    }

    /// Generate thumbnails for clip
    pub fn generate_thumbnails(
        &mut self,
        clip_id: u64,
        width: u32,
        interval_frames: u64,
    ) -> VideoResult<ThumbnailStrip> {
        if let Some(player) = self.players.get_mut(&clip_id)
            && let Some(info) = player.info()
        {
            return self
                .thumbnails
                .generate_strip(&info.path, width, interval_frames);
        }
        Err(VideoError::OpenFailed("Clip not found".into()))
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_timecode_parsing() {
        let tc = Timecode::parse("01:02:03:04", TimecodeFormat::NonDropFrame).unwrap();
        assert_eq!(tc.hours, 1);
        assert_eq!(tc.minutes, 2);
        assert_eq!(tc.seconds, 3);
        assert_eq!(tc.frames, 4);
    }

    #[test]
    fn test_frame_rate() {
        let fr = FrameRate::Fps24;
        assert!((fr.as_f64() - 24.0).abs() < 0.001);

        let fr = FrameRate::Fps23_976;
        assert!((fr.as_f64() - 23.976).abs() < 0.001);
    }
}
