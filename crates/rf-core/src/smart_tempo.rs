//! Smart Tempo (Logic Pro Style)
//!
//! Automatic tempo detection and adaptation:
//! - Detect tempo from audio
//! - Adapt project tempo to match content
//! - Flex audio to match project tempo
//! - Beat grid alignment

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

/// Tempo detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempoDetection {
    /// Detected BPM
    pub bpm: f64,
    /// Confidence (0.0-1.0)
    pub confidence: f64,
    /// Alternative tempos (half/double)
    pub alternatives: Vec<f64>,
    /// Detected downbeats (sample positions)
    pub downbeats: Vec<u64>,
    /// Is tempo stable throughout
    pub stable: bool,
}

/// Smart tempo mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum SmartTempoMode {
    /// Keep project tempo, flex audio to match
    #[default]
    KeepProject,
    /// Adapt project tempo to match audio
    AdaptProject,
    /// Automatic detection
    Automatic,
    /// Manual (no adjustment)
    Manual,
}

impl SmartTempoMode {
    pub fn description(&self) -> &'static str {
        match self {
            Self::KeepProject => "Flex audio to match project tempo",
            Self::AdaptProject => "Change project tempo to match audio",
            Self::Automatic => "Automatically detect and decide",
            Self::Manual => "No automatic tempo adjustment",
        }
    }
}

/// Smart tempo change event (sample-based, different from tick-based TempoEvent in tempo.rs)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartTempoEvent {
    /// Position in samples
    pub position: u64,
    /// BPM at this position
    pub bpm: f64,
    /// Transition type
    pub transition: TempoTransition,
}

/// Tempo transition type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TempoTransition {
    /// Instant change
    #[default]
    Instant,
    /// Linear ramp
    Linear,
    /// Exponential curve
    Exponential,
    /// S-curve (smooth)
    SCurve,
}

/// Sample-based tempo map for variable tempo (different from tick-based TempoMap in tempo.rs)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SmartTempoMap {
    /// Base tempo
    pub base_tempo: f64,
    /// Tempo events (sorted by position)
    events: Vec<SmartTempoEvent>,
    /// Sample rate
    sample_rate: f64,
}

impl SmartTempoMap {
    /// Create with constant tempo
    pub fn new(bpm: f64, sample_rate: f64) -> Self {
        Self {
            base_tempo: bpm,
            events: Vec::new(),
            sample_rate,
        }
    }

    /// Add tempo event
    pub fn add_event(&mut self, event: SmartTempoEvent) {
        self.events.push(event);
        self.events.sort_by_key(|e| e.position);
    }

    /// Get tempo at sample position
    pub fn tempo_at(&self, position: u64) -> f64 {
        if self.events.is_empty() {
            return self.base_tempo;
        }

        // Find surrounding events
        let mut prev_event: Option<&SmartTempoEvent> = None;
        let mut next_event: Option<&SmartTempoEvent> = None;

        for event in &self.events {
            if event.position <= position {
                prev_event = Some(event);
            } else {
                next_event = Some(event);
                break;
            }
        }

        match (prev_event, next_event) {
            (Some(prev), Some(next)) => {
                // Interpolate based on transition type
                let span = next.position - prev.position;
                if span == 0 {
                    return prev.bpm;
                }
                let t = (position - prev.position) as f64 / span as f64;

                match prev.transition {
                    TempoTransition::Instant => prev.bpm,
                    TempoTransition::Linear => prev.bpm + t * (next.bpm - prev.bpm),
                    TempoTransition::Exponential => {
                        let ratio = next.bpm / prev.bpm;
                        prev.bpm * ratio.powf(t)
                    }
                    TempoTransition::SCurve => {
                        let smooth_t = t * t * (3.0 - 2.0 * t);
                        prev.bpm + smooth_t * (next.bpm - prev.bpm)
                    }
                }
            }
            (Some(prev), None) => prev.bpm,
            (None, _) => self.base_tempo,
        }
    }

    /// Get samples per beat at position
    pub fn samples_per_beat_at(&self, position: u64) -> f64 {
        let tempo = self.tempo_at(position);
        (self.sample_rate * 60.0) / tempo
    }

    /// Convert beat position to sample position
    pub fn beat_to_samples(&self, beat: f64) -> u64 {
        if self.events.is_empty() {
            let spb = (self.sample_rate * 60.0) / self.base_tempo;
            return (beat * spb) as u64;
        }

        // Integrate through tempo changes
        let mut current_beat = 0.0f64;
        let mut current_sample = 0u64;
        let mut current_tempo = self.base_tempo;

        for event in &self.events {
            let spb = (self.sample_rate * 60.0) / current_tempo;
            let samples_to_event = event.position - current_sample;
            let beats_to_event = samples_to_event as f64 / spb;

            if current_beat + beats_to_event >= beat {
                // Target is before this event
                let remaining_beats = beat - current_beat;
                return current_sample + (remaining_beats * spb) as u64;
            }

            current_beat += beats_to_event;
            current_sample = event.position;
            current_tempo = event.bpm;
        }

        // Past all events
        let spb = (self.sample_rate * 60.0) / current_tempo;
        current_sample + ((beat - current_beat) * spb) as u64
    }

    /// Convert sample position to beat position
    pub fn samples_to_beat(&self, position: u64) -> f64 {
        if self.events.is_empty() {
            let spb = (self.sample_rate * 60.0) / self.base_tempo;
            return position as f64 / spb;
        }

        // Integrate through tempo changes
        let mut current_beat = 0.0f64;
        let mut current_sample = 0u64;
        let mut current_tempo = self.base_tempo;

        for event in &self.events {
            if event.position > position {
                break;
            }

            let spb = (self.sample_rate * 60.0) / current_tempo;
            let samples_since = event.position - current_sample;
            current_beat += samples_since as f64 / spb;
            current_sample = event.position;
            current_tempo = event.bpm;
        }

        // Add remaining
        let spb = (self.sample_rate * 60.0) / current_tempo;
        current_beat + (position - current_sample) as f64 / spb
    }

    /// Clear all tempo events
    pub fn clear(&mut self) {
        self.events.clear();
    }

    /// Get all events
    pub fn events(&self) -> &[SmartTempoEvent] {
        &self.events
    }
}

/// Tempo detector using autocorrelation
pub struct TempoDetector {
    /// Sample rate
    sample_rate: f64,
    /// Minimum BPM to detect
    min_bpm: f64,
    /// Maximum BPM to detect
    max_bpm: f64,
    /// Energy history for onset detection
    energy_history: VecDeque<f64>,
    /// Onset times
    onsets: Vec<u64>,
    /// Current position
    position: u64,
}

impl TempoDetector {
    /// Create new detector
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            min_bpm: 60.0,
            max_bpm: 200.0,
            energy_history: VecDeque::with_capacity(4096),
            onsets: Vec::new(),
            position: 0,
        }
    }

    /// Set BPM range
    pub fn set_range(&mut self, min_bpm: f64, max_bpm: f64) {
        self.min_bpm = min_bpm;
        self.max_bpm = max_bpm;
    }

    /// Process audio block for tempo detection
    pub fn process(&mut self, audio: &[f64]) {
        const BLOCK_SIZE: usize = 512;

        for chunk in audio.chunks(BLOCK_SIZE) {
            // Calculate energy
            let energy: f64 = chunk.iter().map(|s| s * s).sum::<f64>() / chunk.len() as f64;

            // Add to history
            self.energy_history.push_back(energy);
            if self.energy_history.len() > 4096 {
                self.energy_history.pop_front();
            }

            // Detect onset (energy spike)
            if self.energy_history.len() >= 4 {
                let recent: f64 = self.energy_history.iter().rev().take(2).sum::<f64>() / 2.0;
                let older: f64 = self.energy_history.iter().rev().skip(2).take(2).sum::<f64>() / 2.0;

                if recent > older * 1.5 && recent > 0.01 {
                    self.onsets.push(self.position);
                }
            }

            self.position += chunk.len() as u64;
        }
    }

    /// Analyze and return tempo detection
    pub fn analyze(&self) -> TempoDetection {
        if self.onsets.len() < 4 {
            return TempoDetection {
                bpm: 120.0,
                confidence: 0.0,
                alternatives: vec![60.0, 240.0],
                downbeats: Vec::new(),
                stable: false,
            };
        }

        // Calculate inter-onset intervals
        let mut intervals: Vec<f64> = Vec::with_capacity(self.onsets.len() - 1);
        for i in 1..self.onsets.len() {
            let interval = self.onsets[i] - self.onsets[i - 1];
            intervals.push(interval as f64);
        }

        // Find most common interval using histogram
        let min_interval = (self.sample_rate * 60.0 / self.max_bpm) as u64;
        let max_interval = (self.sample_rate * 60.0 / self.min_bpm) as u64;

        let mut histogram: Vec<u32> = vec![0; 256];
        for &interval in &intervals {
            if interval >= min_interval as f64 && interval <= max_interval as f64 {
                // Quantize to histogram bins
                let normalized = (interval - min_interval as f64)
                    / (max_interval - min_interval) as f64;
                let bin = (normalized * 255.0) as usize;
                if bin < 256 {
                    histogram[bin] += 1;
                }
            }
        }

        // Find peak in histogram
        let (peak_bin, peak_count) = histogram
            .iter()
            .enumerate()
            .max_by_key(|(_, count)| *count)
            .unwrap_or((128, &0));

        // Convert back to BPM
        let normalized = peak_bin as f64 / 255.0;
        let interval = min_interval as f64 + normalized * (max_interval - min_interval) as f64;
        let bpm = (self.sample_rate * 60.0) / interval;

        // Calculate confidence
        let total_intervals = intervals.len() as u32;
        let confidence = if total_intervals > 0 {
            (*peak_count as f64 / total_intervals as f64).min(1.0)
        } else {
            0.0
        };

        // Check stability
        let mean_interval: f64 = intervals.iter().sum::<f64>() / intervals.len() as f64;
        let variance: f64 = intervals.iter().map(|i| (i - mean_interval).powi(2)).sum::<f64>()
            / intervals.len() as f64;
        let std_dev = variance.sqrt();
        let stable = std_dev / mean_interval < 0.1; // <10% variation

        // Find potential downbeats (every 4 onsets roughly)
        let downbeats: Vec<u64> = self.onsets.iter().step_by(4).copied().collect();

        TempoDetection {
            bpm,
            confidence,
            alternatives: vec![bpm / 2.0, bpm * 2.0],
            downbeats,
            stable,
        }
    }

    /// Reset detector
    pub fn reset(&mut self) {
        self.energy_history.clear();
        self.onsets.clear();
        self.position = 0;
    }
}

/// Smart tempo processor
pub struct SmartTempo {
    /// Mode
    mode: SmartTempoMode,
    /// Tempo map
    tempo_map: SmartTempoMap,
    /// Detector
    detector: TempoDetector,
    /// Current detection
    detection: Option<TempoDetection>,
}

impl SmartTempo {
    /// Create new smart tempo processor
    pub fn new(sample_rate: f64, initial_bpm: f64) -> Self {
        Self {
            mode: SmartTempoMode::KeepProject,
            tempo_map: SmartTempoMap::new(initial_bpm, sample_rate),
            detector: TempoDetector::new(sample_rate),
            detection: None,
        }
    }

    /// Set mode
    pub fn set_mode(&mut self, mode: SmartTempoMode) {
        self.mode = mode;
    }

    /// Get mode
    pub fn mode(&self) -> SmartTempoMode {
        self.mode
    }

    /// Analyze audio for tempo
    pub fn analyze(&mut self, audio: &[f64]) -> &TempoDetection {
        self.detector.reset();
        self.detector.process(audio);
        self.detection = Some(self.detector.analyze());
        self.detection.as_ref().unwrap()
    }

    /// Apply detected tempo based on mode
    pub fn apply(&mut self) -> Option<f64> {
        let detection = self.detection.as_ref()?;

        match self.mode {
            SmartTempoMode::AdaptProject => {
                // Change project tempo to match audio
                self.tempo_map.base_tempo = detection.bpm;
                Some(detection.bpm)
            }
            SmartTempoMode::KeepProject => {
                // Keep project tempo, return stretch ratio
                let ratio = self.tempo_map.base_tempo / detection.bpm;
                Some(ratio)
            }
            SmartTempoMode::Automatic => {
                if detection.confidence > 0.7 {
                    // High confidence: adapt project
                    self.tempo_map.base_tempo = detection.bpm;
                    Some(detection.bpm)
                } else {
                    // Low confidence: keep project
                    Some(1.0)
                }
            }
            SmartTempoMode::Manual => None,
        }
    }

    /// Get tempo map
    pub fn tempo_map(&self) -> &SmartTempoMap {
        &self.tempo_map
    }

    /// Get mutable tempo map
    pub fn tempo_map_mut(&mut self) -> &mut SmartTempoMap {
        &mut self.tempo_map
    }

    /// Get last detection
    pub fn detection(&self) -> Option<&TempoDetection> {
        self.detection.as_ref()
    }

    /// Set project tempo
    pub fn set_project_tempo(&mut self, bpm: f64) {
        self.tempo_map.base_tempo = bpm;
    }

    /// Get project tempo
    pub fn project_tempo(&self) -> f64 {
        self.tempo_map.base_tempo
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tempo_map_constant() {
        let map = SmartTempoMap::new(120.0, 48000.0);

        // At 120 BPM, 48kHz: 1 beat = 24000 samples
        assert!((map.tempo_at(0) - 120.0).abs() < 0.001);
        assert!((map.samples_per_beat_at(0) - 24000.0).abs() < 1.0);
    }

    #[test]
    fn test_tempo_map_with_event() {
        let mut map = SmartTempoMap::new(120.0, 48000.0);

        map.add_event(SmartTempoEvent {
            position: 48000, // 1 second
            bpm: 140.0,
            transition: TempoTransition::Instant,
        });

        assert!((map.tempo_at(0) - 120.0).abs() < 0.001);
        assert!((map.tempo_at(50000) - 140.0).abs() < 0.001);
    }

    #[test]
    fn test_beat_sample_conversion() {
        let map = SmartTempoMap::new(120.0, 48000.0);

        // Beat 0 = sample 0
        assert_eq!(map.beat_to_samples(0.0), 0);

        // Beat 1 = 24000 samples at 120 BPM
        let samples = map.beat_to_samples(1.0);
        assert!((samples as f64 - 24000.0).abs() < 10.0);

        // Reverse
        let beat = map.samples_to_beat(24000);
        assert!((beat - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_smart_tempo_modes() {
        let mut smart = SmartTempo::new(48000.0, 120.0);

        assert_eq!(smart.mode(), SmartTempoMode::KeepProject);

        smart.set_mode(SmartTempoMode::AdaptProject);
        assert_eq!(smart.mode(), SmartTempoMode::AdaptProject);
    }

    #[test]
    fn test_tempo_detection_empty() {
        let detector = TempoDetector::new(48000.0);
        let detection = detector.analyze();

        // Should return default with low confidence
        assert!((detection.bpm - 120.0).abs() < 0.001);
        assert!(detection.confidence < 0.1);
    }
}
