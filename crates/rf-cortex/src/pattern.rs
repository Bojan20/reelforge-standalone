// file: crates/rf-cortex/src/pattern.rs
//! Pattern matching engine — recognizes signal sequences and temporal patterns.
//!
//! While reflexes react to individual signals, patterns detect sequences:
//! "3 underruns in 10 seconds", "CPU spike followed by plugin fault",
//! "repeated clipping on the same bus". This is the cortex's pattern recognition.

use crate::signal::{NeuralSignal, SignalKind, SignalOrigin};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// A recognized pattern — a sequence of signals that form a meaningful event.
#[derive(Debug, Clone)]
pub struct RecognizedPattern {
    /// Name of the pattern that was recognized.
    pub name: String,
    /// When the pattern was completed (recognized).
    pub recognized_at: Instant,
    /// Severity of this pattern (0.0 = informational, 1.0 = critical).
    pub severity: f32,
    /// Human-readable description of what was detected.
    pub description: String,
    /// IDs of the signals that formed this pattern.
    pub signal_ids: Vec<u64>,
}

/// A pattern detector that watches a signal window for specific sequences.
pub struct PatternDetector {
    /// Name of this detector.
    pub name: String,
    /// The detection function.
    #[allow(clippy::type_complexity)]
    detect_fn: Box<dyn Fn(&[NeuralSignal]) -> Option<(f32, String)> + Send>,
    /// How many times this pattern has been recognized.
    pub recognition_count: u64,
    /// Minimum time between pattern recognitions (debounce).
    pub cooldown: Duration,
    /// Last recognition time.
    last_recognized: Option<Instant>,
}

impl PatternDetector {
    pub fn new(
        name: impl Into<String>,
        cooldown: Duration,
        detect_fn: impl Fn(&[NeuralSignal]) -> Option<(f32, String)> + Send + 'static,
    ) -> Self {
        Self {
            name: name.into(),
            detect_fn: Box::new(detect_fn),
            recognition_count: 0,
            cooldown,
            last_recognized: None,
        }
    }

    fn is_ready(&self) -> bool {
        self.last_recognized
            .map(|t| t.elapsed() >= self.cooldown)
            .unwrap_or(true)
    }

    fn try_detect(&mut self, window: &[NeuralSignal]) -> Option<RecognizedPattern> {
        if !self.is_ready() {
            return None;
        }
        if let Some((severity, description)) = (self.detect_fn)(window) {
            self.recognition_count += 1;
            self.last_recognized = Some(Instant::now());
            Some(RecognizedPattern {
                name: self.name.clone(),
                recognized_at: Instant::now(),
                severity,
                description,
                signal_ids: window.iter().map(|s| s.id).collect(),
            })
        } else {
            None
        }
    }
}

/// The pattern recognition engine — maintains a sliding window of recent signals
/// and runs detectors against it.
pub struct PatternEngine {
    /// Sliding window of recent signals.
    window: VecDeque<NeuralSignal>,
    /// Maximum window size (oldest signals are evicted).
    window_size: usize,
    /// Maximum window age — signals older than this are evicted.
    window_age: Duration,
    /// All registered pattern detectors.
    detectors: Vec<PatternDetector>,
}

impl PatternEngine {
    pub fn new(window_size: usize, window_age: Duration) -> Self {
        Self {
            window: VecDeque::with_capacity(window_size),
            window_size,
            window_age,
            detectors: Vec::new(),
        }
    }

    /// Register a pattern detector.
    pub fn register(&mut self, detector: PatternDetector) {
        self.detectors.push(detector);
    }

    /// Feed a signal into the engine and check for pattern matches.
    pub fn feed(&mut self, signal: NeuralSignal) -> Vec<RecognizedPattern> {
        // Add to window
        self.window.push_back(signal);

        // Evict by size
        while self.window.len() > self.window_size {
            self.window.pop_front();
        }

        // Evict by age
        let cutoff = Instant::now() - self.window_age;
        while self
            .window
            .front()
            .is_some_and(|s| s.timestamp < cutoff)
        {
            self.window.pop_front();
        }

        // Run all detectors
        let window_slice: Vec<_> = self.window.iter().cloned().collect();
        let mut patterns = Vec::new();
        for detector in &mut self.detectors {
            if let Some(pattern) = detector.try_detect(&window_slice) {
                patterns.push(pattern);
            }
        }
        patterns
    }

    /// Get detector stats.
    pub fn stats(&self) -> Vec<PatternDetectorStats> {
        self.detectors
            .iter()
            .map(|d| PatternDetectorStats {
                name: d.name.clone(),
                recognition_count: d.recognition_count,
            })
            .collect()
    }

    /// Current window size.
    pub fn window_len(&self) -> usize {
        self.window.len()
    }

    /// Create an engine with default FluxForge pattern detectors.
    pub fn with_defaults() -> Self {
        let mut engine = Self::new(1000, Duration::from_secs(60));

        // Pattern: Repeated underruns (3+ in 10 seconds)
        engine.register(PatternDetector::new(
            "repeated-underruns",
            Duration::from_secs(15),
            |window| {
                let ten_sec_ago = Instant::now() - Duration::from_secs(10);
                let recent_underruns: Vec<_> = window
                    .iter()
                    .filter(|s| {
                        s.timestamp > ten_sec_ago
                            && matches!(s.kind, SignalKind::BufferUnderrun { .. })
                    })
                    .collect();

                if recent_underruns.len() >= 3 {
                    Some((
                        0.9,
                        format!(
                            "{} buffer underruns in last 10s — audio engine struggling",
                            recent_underruns.len()
                        ),
                    ))
                } else {
                    None
                }
            },
        ));

        // Pattern: CPU spike followed by underrun (within 2 seconds)
        engine.register(PatternDetector::new(
            "cpu-spike-then-underrun",
            Duration::from_secs(10),
            |window| {
                let two_sec_ago = Instant::now() - Duration::from_secs(2);
                let recent: Vec<_> = window
                    .iter()
                    .filter(|s| s.timestamp > two_sec_ago)
                    .collect();

                let has_cpu_spike = recent.iter().any(|s| {
                    matches!(s.kind, SignalKind::CpuLoadAlert { load_percent } if load_percent > 80.0)
                });
                let has_underrun = recent
                    .iter()
                    .any(|s| matches!(s.kind, SignalKind::BufferUnderrun { .. }));

                if has_cpu_spike && has_underrun {
                    Some((
                        0.85,
                        "CPU spike caused buffer underrun — consider increasing buffer size".into(),
                    ))
                } else {
                    None
                }
            },
        ));

        // Pattern: Same bus clipping repeatedly
        engine.register(PatternDetector::new(
            "persistent-clipping",
            Duration::from_secs(5),
            |window| {
                let five_sec_ago = Instant::now() - Duration::from_secs(5);
                let clip_channels: Vec<u32> = window
                    .iter()
                    .filter(|s| s.timestamp > five_sec_ago)
                    .filter_map(|s| {
                        if let SignalKind::ClipDetected { channel, .. } = &s.kind {
                            Some(*channel)
                        } else {
                            None
                        }
                    })
                    .collect();

                if clip_channels.len() >= 3 {
                    // Check if same channel
                    if let Some(&first) = clip_channels.first() {
                        let same_channel = clip_channels.iter().filter(|&&c| c == first).count();
                        if same_channel >= 3 {
                            return Some((
                                0.7,
                                format!("Channel {} clipping persistently — reduce gain", first),
                            ));
                        }
                    }
                }
                None
            },
        ));

        // Pattern: Multiple subsystem heartbeat loss (something is frozen)
        engine.register(PatternDetector::new(
            "subsystem-silence",
            Duration::from_secs(30),
            |window| {
                // Check if any origin that used to send signals has gone silent
                let thirty_sec_ago = Instant::now() - Duration::from_secs(30);
                let ten_sec_ago = Instant::now() - Duration::from_secs(10);

                let old_origins: std::collections::HashSet<SignalOrigin> = window
                    .iter()
                    .filter(|s| s.timestamp > thirty_sec_ago && s.timestamp < ten_sec_ago)
                    .map(|s| s.origin)
                    .collect();

                let recent_origins: std::collections::HashSet<SignalOrigin> = window
                    .iter()
                    .filter(|s| s.timestamp > ten_sec_ago)
                    .map(|s| s.origin)
                    .collect();

                let silent: Vec<_> = old_origins.difference(&recent_origins).collect();

                if silent.len() >= 2 {
                    Some((
                        0.75,
                        format!(
                            "{} subsystems went silent — possible freeze",
                            silent.len()
                        ),
                    ))
                } else {
                    None
                }
            },
        ));

        engine
    }
}

impl Default for PatternEngine {
    fn default() -> Self {
        Self::new(1000, Duration::from_secs(60))
    }
}

/// Stats for a pattern detector.
#[derive(Debug, Clone)]
pub struct PatternDetectorStats {
    pub name: String,
    pub recognition_count: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_signal(origin: SignalOrigin, kind: SignalKind) -> NeuralSignal {
        let mut sig = NeuralSignal::new(origin, crate::signal::SignalUrgency::Normal, kind);
        sig.id = 1; // would normally be assigned by bus
        sig
    }

    #[test]
    fn empty_window_no_patterns() {
        let mut engine = PatternEngine::with_defaults();
        let sig = make_signal(SignalOrigin::Cortex, SignalKind::Heartbeat);
        let patterns = engine.feed(sig);
        assert!(patterns.is_empty());
    }

    #[test]
    fn repeated_underruns_detected() {
        let mut engine = PatternEngine::with_defaults();

        for i in 0..5 {
            let patterns = engine.feed(make_signal(
                SignalOrigin::AudioEngine,
                SignalKind::BufferUnderrun { count: i },
            ));
            if i >= 2 {
                // After 3rd underrun, pattern should be recognized
                if !patterns.is_empty() {
                    assert_eq!(patterns[0].name, "repeated-underruns");
                    assert!(patterns[0].severity > 0.8);
                    return;
                }
            }
        }
        // Pattern should have been detected
        panic!("Expected repeated-underruns pattern to be detected");
    }

    #[test]
    fn window_size_eviction() {
        let mut engine = PatternEngine::new(5, Duration::from_secs(60));
        engine.register(PatternDetector::new(
            "count-check",
            Duration::from_millis(0),
            |window| {
                if window.len() > 5 {
                    Some((1.0, "too many!".into()))
                } else {
                    None
                }
            },
        ));

        for _ in 0..10 {
            let patterns = engine.feed(make_signal(SignalOrigin::Cortex, SignalKind::Heartbeat));
            // Should never detect "too many" because window is capped at 5
            assert!(patterns.is_empty());
        }
        assert!(engine.window_len() <= 5);
    }

    #[test]
    fn detector_cooldown() {
        let mut engine = PatternEngine::new(100, Duration::from_secs(60));
        engine.register(PatternDetector::new(
            "always-fires",
            Duration::from_secs(60), // long cooldown
            |_window| Some((0.5, "fired".into())),
        ));

        let p1 = engine.feed(make_signal(SignalOrigin::Cortex, SignalKind::Heartbeat));
        assert_eq!(p1.len(), 1);

        let p2 = engine.feed(make_signal(SignalOrigin::Cortex, SignalKind::Heartbeat));
        assert!(p2.is_empty()); // cooldown prevents firing
    }

    #[test]
    fn stats_tracking() {
        let mut engine = PatternEngine::new(100, Duration::from_secs(60));
        engine.register(PatternDetector::new(
            "counter",
            Duration::from_millis(0),
            |_| Some((0.1, "test".into())),
        ));

        for _ in 0..5 {
            engine.feed(make_signal(SignalOrigin::Cortex, SignalKind::Heartbeat));
        }

        let stats = engine.stats();
        assert_eq!(stats[0].recognition_count, 5);
    }

    #[test]
    fn default_engine_has_detectors() {
        let engine = PatternEngine::with_defaults();
        assert!(engine.stats().len() >= 4);
    }
}
