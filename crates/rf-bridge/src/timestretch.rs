//! TimeStretch Bridge API
//!
//! Flutter-Rust bridge for ULTIMATIVNI time stretching:
//! - NSGT + RTPGHI for pristine quality
//! - STN separation for content-aware processing
//! - LPC formant preservation
//! - Real-time flex marker visualization
//! - Clip-based stretch regions

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use rf_dsp::timestretch::{
    Algorithm, FlexMarker, FlexMarkerType, Quality, StretchRegion, TimeStretchConfig,
    TransientMode, UltimateTimeStretch,
};
use std::collections::HashMap;
use std::sync::Arc;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Global time stretch processor pool (one per clip)
static STRETCH_PROCESSORS: Lazy<RwLock<HashMap<u64, Arc<RwLock<UltimateTimeStretch>>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Global stretch region cache for visualization
static STRETCH_REGIONS: Lazy<RwLock<HashMap<u64, Vec<StretchRegionDto>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Global flex marker cache
static FLEX_MARKERS: Lazy<RwLock<HashMap<u64, Vec<FlexMarkerDto>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// DTOs FOR FLUTTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Algorithm selection for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub enum TimeStretchAlgorithm {
    /// Auto-select based on content analysis
    Auto,
    /// Phase vocoder (NSGT + RTPGHI, highest quality polyphonic)
    PhaseVocoder,
    /// WSOLA (fast, good for transients)
    Wsola,
    /// PSOLA (monophonic speech/vocals)
    Psola,
    /// WORLD vocoder (highest quality monophonic)
    World,
    /// Granular synthesis (creative/extreme stretch)
    Granular,
    /// Hybrid STN separation + per-component processing
    Hybrid,
}

impl From<TimeStretchAlgorithm> for Algorithm {
    fn from(alg: TimeStretchAlgorithm) -> Self {
        match alg {
            TimeStretchAlgorithm::Auto => Algorithm::Auto,
            TimeStretchAlgorithm::PhaseVocoder => Algorithm::PhaseVocoder,
            TimeStretchAlgorithm::Wsola => Algorithm::Wsola,
            TimeStretchAlgorithm::Psola => Algorithm::Psola,
            TimeStretchAlgorithm::World => Algorithm::World,
            TimeStretchAlgorithm::Granular => Algorithm::Granular,
            TimeStretchAlgorithm::Hybrid => Algorithm::Hybrid,
        }
    }
}

impl From<Algorithm> for TimeStretchAlgorithm {
    fn from(alg: Algorithm) -> Self {
        match alg {
            Algorithm::Auto => TimeStretchAlgorithm::Auto,
            Algorithm::PhaseVocoder => TimeStretchAlgorithm::PhaseVocoder,
            Algorithm::Wsola => TimeStretchAlgorithm::Wsola,
            Algorithm::Psola => TimeStretchAlgorithm::Psola,
            Algorithm::World => TimeStretchAlgorithm::World,
            Algorithm::Granular => TimeStretchAlgorithm::Granular,
            Algorithm::Hybrid => TimeStretchAlgorithm::Hybrid,
        }
    }
}

/// Quality preset for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub enum TimeStretchQuality {
    /// Real-time capable
    Realtime,
    /// High quality (default)
    High,
    /// Maximum quality (offline only)
    Ultra,
}

impl From<TimeStretchQuality> for Quality {
    fn from(q: TimeStretchQuality) -> Self {
        match q {
            TimeStretchQuality::Realtime => Quality::Realtime,
            TimeStretchQuality::High => Quality::High,
            TimeStretchQuality::Ultra => Quality::Ultra,
        }
    }
}

impl From<Quality> for TimeStretchQuality {
    fn from(q: Quality) -> Self {
        match q {
            Quality::Realtime => TimeStretchQuality::Realtime,
            Quality::High => TimeStretchQuality::High,
            Quality::Ultra => TimeStretchQuality::Ultra,
        }
    }
}

/// Transient mode for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub enum TimeStretchTransientMode {
    /// No special transient handling
    Off,
    /// Detect and preserve transients
    Preserve,
    /// Detect, separate, and reposition transients
    Separate,
    /// Crisp mode - aggressive transient preservation
    Crisp,
}

impl From<TimeStretchTransientMode> for TransientMode {
    fn from(m: TimeStretchTransientMode) -> Self {
        match m {
            TimeStretchTransientMode::Off => TransientMode::Off,
            TimeStretchTransientMode::Preserve => TransientMode::Preserve,
            TimeStretchTransientMode::Separate => TransientMode::Separate,
            TimeStretchTransientMode::Crisp => TransientMode::Crisp,
        }
    }
}

/// Flex marker type for Flutter
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub enum FlexMarkerTypeDto {
    /// Auto-detected transient
    Transient,
    /// User-placed warp marker
    WarpMarker,
    /// Beat grid marker
    BeatMarker,
    /// Anchor point (locked position)
    Anchor,
}

impl From<FlexMarkerType> for FlexMarkerTypeDto {
    fn from(t: FlexMarkerType) -> Self {
        match t {
            FlexMarkerType::Transient => FlexMarkerTypeDto::Transient,
            FlexMarkerType::WarpMarker => FlexMarkerTypeDto::WarpMarker,
            FlexMarkerType::BeatMarker => FlexMarkerTypeDto::BeatMarker,
            FlexMarkerType::Anchor => FlexMarkerTypeDto::Anchor,
        }
    }
}

impl From<FlexMarkerTypeDto> for FlexMarkerType {
    fn from(t: FlexMarkerTypeDto) -> Self {
        match t {
            FlexMarkerTypeDto::Transient => FlexMarkerType::Transient,
            FlexMarkerTypeDto::WarpMarker => FlexMarkerType::WarpMarker,
            FlexMarkerTypeDto::BeatMarker => FlexMarkerType::BeatMarker,
            FlexMarkerTypeDto::Anchor => FlexMarkerType::Anchor,
        }
    }
}

/// Flex marker DTO for Flutter
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct FlexMarkerDto {
    /// Original sample position
    pub original_pos: u64,
    /// Warped (current) sample position
    pub warped_pos: u64,
    /// Marker type
    pub marker_type: FlexMarkerTypeDto,
    /// Detection confidence (0.0 - 1.0)
    pub confidence: f32,
    /// Locked (cannot be auto-adjusted)
    pub locked: bool,
}

impl From<FlexMarker> for FlexMarkerDto {
    fn from(m: FlexMarker) -> Self {
        Self {
            original_pos: m.original_pos,
            warped_pos: m.warped_pos,
            marker_type: m.marker_type.into(),
            confidence: m.confidence,
            locked: m.locked,
        }
    }
}

impl From<&FlexMarker> for FlexMarkerDto {
    fn from(m: &FlexMarker) -> Self {
        Self {
            original_pos: m.original_pos,
            warped_pos: m.warped_pos,
            marker_type: m.marker_type.into(),
            confidence: m.confidence,
            locked: m.locked,
        }
    }
}

/// Stretch region DTO for Flutter visualization
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct StretchRegionDto {
    /// Start sample in source audio
    pub source_start: u64,
    /// End sample in source audio
    pub source_end: u64,
    /// Start sample in stretched output
    pub dest_start: u64,
    /// End sample in stretched output
    pub dest_end: u64,
    /// Stretch ratio for this region
    pub ratio: f64,
}

impl From<&StretchRegion> for StretchRegionDto {
    fn from(r: &StretchRegion) -> Self {
        Self {
            source_start: r.src_start,
            source_end: r.src_end,
            dest_start: r.dst_start,
            dest_end: r.dst_end,
            ratio: r.ratio(),
        }
    }
}

/// TimeStretch configuration DTO
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct TimeStretchConfigDto {
    /// Algorithm selection
    pub algorithm: TimeStretchAlgorithm,
    /// Quality preset
    pub quality: TimeStretchQuality,
    /// Preserve formants during pitch shift
    pub preserve_formants: bool,
    /// Formant shift in semitones
    pub formant_shift: f64,
    /// Transient handling mode
    pub transient_mode: TimeStretchTransientMode,
    /// Enable neural post-enhancement
    pub neural_enhance: bool,
    /// Sample rate
    pub sample_rate: f64,
}

impl Default for TimeStretchConfigDto {
    fn default() -> Self {
        Self {
            algorithm: TimeStretchAlgorithm::Auto,
            quality: TimeStretchQuality::High,
            preserve_formants: true,
            formant_shift: 0.0,
            transient_mode: TimeStretchTransientMode::Preserve,
            neural_enhance: false,
            sample_rate: 44100.0,
        }
    }
}

impl From<TimeStretchConfigDto> for TimeStretchConfig {
    fn from(c: TimeStretchConfigDto) -> Self {
        Self {
            algorithm: c.algorithm.into(),
            quality: c.quality.into(),
            formant_preserve: c.preserve_formants,
            formant_shift: c.formant_shift,
            transient_mode: c.transient_mode.into(),
            neural_enhance: c.neural_enhance,
            sample_rate: c.sample_rate,
        }
    }
}

/// Analysis result for a clip
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct ClipAnalysisDto {
    /// Detected transient count
    pub transient_count: usize,
    /// Transient density (transients per second)
    pub transient_density: f64,
    /// Is monophonic (suitable for WORLD)
    pub is_monophonic: bool,
    /// Estimated BPM (if rhythmic)
    pub bpm: Option<f64>,
    /// Recommended algorithm
    pub recommended_algorithm: TimeStretchAlgorithm,
    /// Quality score (0.0 - 1.0, how well stretch will work)
    pub quality_score: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// API FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Create time stretch processor for a clip
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_create(clip_id: u64, sample_rate: f64) -> bool {
    let config = TimeStretchConfig {
        sample_rate,
        ..Default::default()
    };
    let processor = UltimateTimeStretch::new(config);
    let mut processors = STRETCH_PROCESSORS.write();
    processors.insert(clip_id, Arc::new(RwLock::new(processor)));
    true
}

/// Destroy time stretch processor for a clip
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_destroy(clip_id: u64) -> bool {
    let mut processors = STRETCH_PROCESSORS.write();
    let mut regions = STRETCH_REGIONS.write();
    let mut markers = FLEX_MARKERS.write();

    processors.remove(&clip_id);
    regions.remove(&clip_id);
    markers.remove(&clip_id);
    true
}

/// Analyze clip for optimal stretch settings
#[flutter_rust_bridge::frb]
pub async fn timestretch_analyze(
    clip_id: u64,
    audio_data: Vec<f64>,
    sample_rate: f64,
) -> Option<ClipAnalysisDto> {
    let processors = STRETCH_PROCESSORS.read();
    let processor = processors.get(&clip_id)?;

    let mut proc = processor.write();
    let markers = proc.analyze(&audio_data);

    // Cache flex markers for visualization
    let markers_dto: Vec<FlexMarkerDto> = markers.iter().map(FlexMarkerDto::from).collect();

    let transient_count = markers.len();
    let duration_secs = audio_data.len() as f64 / sample_rate;
    let transient_density = if duration_secs > 0.0 {
        transient_count as f64 / duration_secs
    } else {
        0.0
    };

    drop(proc);
    drop(processors);

    let mut markers_cache = FLEX_MARKERS.write();
    markers_cache.insert(clip_id, markers_dto);

    // Determine recommended algorithm and monophonic status
    // Simple heuristics for now
    let is_monophonic = transient_density < 0.5; // Low transient density suggests monophonic

    let recommended = if is_monophonic {
        TimeStretchAlgorithm::World
    } else if transient_density > 5.0 {
        TimeStretchAlgorithm::Wsola
    } else if transient_density > 2.0 {
        TimeStretchAlgorithm::Hybrid
    } else {
        TimeStretchAlgorithm::PhaseVocoder
    };

    // Quality score based on content complexity
    let quality_score = if is_monophonic {
        0.95 // Monophonic = excellent results
    } else if transient_density < 1.0 {
        0.90 // Smooth = great results
    } else if transient_density < 3.0 {
        0.80 // Moderate transients = good results
    } else {
        0.70 // Dense transients = harder
    };

    Some(ClipAnalysisDto {
        transient_count,
        transient_density,
        is_monophonic,
        bpm: None, // TODO: BPM detection
        recommended_algorithm: recommended,
        quality_score,
    })
}

/// Process audio with time stretch
#[flutter_rust_bridge::frb]
pub async fn timestretch_process(
    clip_id: u64,
    audio_data: Vec<f64>,
    time_ratio: f64,
    pitch_ratio: f64,
) -> Option<Vec<f64>> {
    let processors = STRETCH_PROCESSORS.read();
    let processor = processors.get(&clip_id)?;

    let mut proc = processor.write();
    let output = proc.process_with_pitch(&audio_data, time_ratio, pitch_ratio);

    // Cache stretch regions for visualization
    let regions_dto: Vec<StretchRegionDto> = proc
        .get_regions()
        .iter()
        .map(StretchRegionDto::from)
        .collect();

    drop(proc);
    drop(processors);

    let mut regions_cache = STRETCH_REGIONS.write();
    regions_cache.insert(clip_id, regions_dto);

    Some(output)
}

/// Process audio with uniform time stretch (no pitch change)
#[flutter_rust_bridge::frb]
pub async fn timestretch_process_uniform(
    clip_id: u64,
    audio_data: Vec<f64>,
    ratio: f64,
) -> Option<Vec<f64>> {
    timestretch_process(clip_id, audio_data, ratio, 1.0).await
}

/// Process stereo audio with time stretch
#[flutter_rust_bridge::frb]
pub async fn timestretch_process_stereo(
    clip_id: u64,
    left: Vec<f64>,
    right: Vec<f64>,
    time_ratio: f64,
    pitch_ratio: f64,
) -> Option<(Vec<f64>, Vec<f64>)> {
    let processors = STRETCH_PROCESSORS.read();
    let processor = processors.get(&clip_id)?;

    let mut proc = processor.write();

    // Process left and right independently (for now)
    // TODO: Phase-locked stereo processing
    let out_l = proc.process_with_pitch(&left, time_ratio, pitch_ratio);
    proc.reset();
    let out_r = proc.process_with_pitch(&right, time_ratio, pitch_ratio);

    // Cache regions
    let regions_dto: Vec<StretchRegionDto> = proc
        .get_regions()
        .iter()
        .map(StretchRegionDto::from)
        .collect();

    drop(proc);
    drop(processors);

    let mut regions_cache = STRETCH_REGIONS.write();
    regions_cache.insert(clip_id, regions_dto);

    Some((out_l, out_r))
}

/// Get flex markers for a clip (for visualization)
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_get_markers(clip_id: u64) -> Vec<FlexMarkerDto> {
    let markers = FLEX_MARKERS.read();
    markers.get(&clip_id).cloned().unwrap_or_default()
}

/// Get stretch regions for a clip (for visualization)
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_get_regions(clip_id: u64) -> Vec<StretchRegionDto> {
    let regions = STRETCH_REGIONS.read();
    regions.get(&clip_id).cloned().unwrap_or_default()
}

/// Add or move a warp marker
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_add_warp_marker(clip_id: u64, original_pos: u64, warped_pos: u64) -> bool {
    let processors = STRETCH_PROCESSORS.read();
    if let Some(processor) = processors.get(&clip_id) {
        let mut proc = processor.write();
        proc.add_marker(original_pos, warped_pos);

        // Update cache
        let markers_dto: Vec<FlexMarkerDto> =
            proc.get_markers().iter().map(FlexMarkerDto::from).collect();

        drop(proc);
        drop(processors);

        let mut markers_cache = FLEX_MARKERS.write();
        markers_cache.insert(clip_id, markers_dto);

        true
    } else {
        false
    }
}

/// Set algorithm for a clip
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_set_algorithm(clip_id: u64, algorithm: TimeStretchAlgorithm) -> bool {
    let processors = STRETCH_PROCESSORS.read();
    if let Some(processor) = processors.get(&clip_id) {
        let mut proc = processor.write();
        let mut config = TimeStretchConfig::default();
        config.algorithm = algorithm.into();
        proc.set_config(config);
        true
    } else {
        false
    }
}

/// Set quality for a clip
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_set_quality(clip_id: u64, quality: TimeStretchQuality) -> bool {
    let processors = STRETCH_PROCESSORS.read();
    if let Some(processor) = processors.get(&clip_id) {
        let mut proc = processor.write();
        let mut config = TimeStretchConfig::default();
        config.quality = quality.into();
        proc.set_config(config);
        true
    } else {
        false
    }
}

/// Reset processor state
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_reset(clip_id: u64) -> bool {
    let processors = STRETCH_PROCESSORS.read();
    if let Some(processor) = processors.get(&clip_id) {
        let mut proc = processor.write();
        proc.reset();
        true
    } else {
        false
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH PROCESSING
// ═══════════════════════════════════════════════════════════════════════════════

/// Batch stretch job
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct BatchStretchJob {
    pub clip_id: u64,
    pub audio_data: Vec<f64>,
    pub time_ratio: f64,
    pub pitch_ratio: f64,
}

/// Process multiple clips in parallel (offline bounce)
#[flutter_rust_bridge::frb]
pub async fn timestretch_batch_process(jobs: Vec<BatchStretchJob>) -> Vec<Option<Vec<f64>>> {
    use rayon::prelude::*;

    jobs.into_par_iter()
        .map(|job| {
            let processors = STRETCH_PROCESSORS.read();
            if let Some(processor) = processors.get(&job.clip_id) {
                let mut proc = processor.write();
                Some(proc.process_with_pitch(&job.audio_data, job.time_ratio, job.pitch_ratio))
            } else {
                None
            }
        })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════════
// VISUALIZATION HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get stretch info for visualization at a specific sample position
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_get_ratio_at_position(clip_id: u64, sample_pos: u64) -> f64 {
    let regions = STRETCH_REGIONS.read();
    if let Some(clip_regions) = regions.get(&clip_id) {
        for region in clip_regions {
            if sample_pos >= region.source_start && sample_pos < region.source_end {
                return region.ratio;
            }
        }
    }
    1.0 // Default to no stretch
}

/// Check if position is near a transient
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_is_near_transient(clip_id: u64, sample_pos: u64, tolerance: u64) -> bool {
    let markers = FLEX_MARKERS.read();
    if let Some(clip_markers) = markers.get(&clip_id) {
        for marker in clip_markers {
            if marker.marker_type == FlexMarkerTypeDto::Transient {
                let diff = if sample_pos > marker.original_pos {
                    sample_pos - marker.original_pos
                } else {
                    marker.original_pos - sample_pos
                };
                if diff <= tolerance {
                    return true;
                }
            }
        }
    }
    false
}

/// Get visualization data for waveform overlay
#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct StretchVisualizationData {
    /// Stretch regions with normalized coordinates (0.0-1.0)
    pub regions: Vec<StretchRegionVisual>,
    /// Flex markers with normalized coordinates
    pub markers: Vec<FlexMarkerVisual>,
    /// Overall stretch ratio
    pub overall_ratio: f64,
}

#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct StretchRegionVisual {
    /// Normalized start position (0.0-1.0)
    pub start: f64,
    /// Normalized end position (0.0-1.0)
    pub end: f64,
    /// Stretch ratio
    pub ratio: f64,
    /// Color hint: -1.0 = compress, 0.0 = none, 1.0 = expand
    pub color_hint: f64,
}

#[derive(Debug, Clone)]
#[flutter_rust_bridge::frb(dart_metadata=("freezed"))]
pub struct FlexMarkerVisual {
    /// Normalized original position (0.0-1.0)
    pub original_x: f64,
    /// Normalized warped position (0.0-1.0)
    pub warped_x: f64,
    /// Marker type
    pub marker_type: FlexMarkerTypeDto,
    /// Is locked
    pub locked: bool,
}

/// Get visualization data for a clip
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_get_visualization(
    clip_id: u64,
    total_samples: u64,
) -> Option<StretchVisualizationData> {
    let regions = STRETCH_REGIONS.read();
    let markers = FLEX_MARKERS.read();

    let clip_regions = regions.get(&clip_id)?;
    let clip_markers = markers.get(&clip_id).cloned().unwrap_or_default();

    let total = total_samples as f64;

    let region_visuals: Vec<StretchRegionVisual> = clip_regions
        .iter()
        .map(|r| {
            let color_hint = if r.ratio > 1.01 {
                (r.ratio - 1.0).min(1.0) // Expand = positive
            } else if r.ratio < 0.99 {
                -(1.0 - r.ratio).min(1.0) // Compress = negative
            } else {
                0.0
            };

            StretchRegionVisual {
                start: r.source_start as f64 / total,
                end: r.source_end as f64 / total,
                ratio: r.ratio,
                color_hint,
            }
        })
        .collect();

    let marker_visuals: Vec<FlexMarkerVisual> = clip_markers
        .iter()
        .map(|m| FlexMarkerVisual {
            original_x: m.original_pos as f64 / total,
            warped_x: m.warped_pos as f64 / total,
            marker_type: m.marker_type,
            locked: m.locked,
        })
        .collect();

    // Calculate overall ratio
    let overall_ratio = if !clip_regions.is_empty() {
        let total_source: u64 = clip_regions
            .iter()
            .map(|r| r.source_end - r.source_start)
            .sum();
        let total_dest: u64 = clip_regions.iter().map(|r| r.dest_end - r.dest_start).sum();
        if total_source > 0 {
            total_dest as f64 / total_source as f64
        } else {
            1.0
        }
    } else {
        1.0
    };

    Some(StretchVisualizationData {
        regions: region_visuals,
        markers: marker_visuals,
        overall_ratio,
    })
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Convert semitones to frequency ratio
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_semitones_to_ratio(semitones: f64) -> f64 {
    rf_dsp::timestretch::semitones_to_ratio(semitones)
}

/// Convert frequency ratio to semitones
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_ratio_to_semitones(ratio: f64) -> f64 {
    rf_dsp::timestretch::ratio_to_semitones(ratio)
}

/// Convert cents to frequency ratio
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_cents_to_ratio(cents: f64) -> f64 {
    rf_dsp::timestretch::cents_to_ratio(cents)
}

/// Convert frequency ratio to cents
#[flutter_rust_bridge::frb(sync)]
pub fn timestretch_ratio_to_cents(ratio: f64) -> f64 {
    rf_dsp::timestretch::ratio_to_cents(ratio)
}
