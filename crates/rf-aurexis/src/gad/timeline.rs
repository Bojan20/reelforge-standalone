//! Dual Timeline — Musical (bars/beats) + Gameplay (frame/event-driven)
//!
//! Musical timeline maps to traditional DAW bar|beat|tick positioning.
//! Gameplay timeline maps to slot machine events/frames with hook triggers.
//! Both run in parallel, synced via anchor points.

use serde::{Deserialize, Serialize};

/// Musical position in bars/beats/ticks.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct MusicalPosition {
    pub bar: u32,
    pub beat: u32,
    pub tick: u32, // 480 PPQN
}

impl MusicalPosition {
    pub fn new(bar: u32, beat: u32, tick: u32) -> Self {
        Self { bar, beat, tick }
    }

    /// Convert to absolute ticks (480 PPQN, assuming 4/4 time).
    pub fn to_ticks(&self, time_sig: &TimeSignature) -> u64 {
        let ticks_per_bar = 480 * time_sig.numerator as u64;
        (self.bar as u64) * ticks_per_bar + (self.beat as u64) * 480 + self.tick as u64
    }

    /// Convert absolute ticks back to musical position.
    pub fn from_ticks(ticks: u64, time_sig: &TimeSignature) -> Self {
        let ticks_per_bar = 480 * time_sig.numerator as u64;
        let bar = (ticks / ticks_per_bar) as u32;
        let remaining = ticks % ticks_per_bar;
        let beat = (remaining / 480) as u32;
        let tick = (remaining % 480) as u32;
        Self { bar, beat, tick }
    }
}

impl Default for MusicalPosition {
    fn default() -> Self {
        Self {
            bar: 0,
            beat: 0,
            tick: 0,
        }
    }
}

/// Gameplay position in frames and event context.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GameplayPosition {
    /// Frame index from session start.
    pub frame: u64,
    /// Current game hook (e.g., "SPIN_START", "REEL_STOP_3").
    pub hook: String,
    /// Spin index within current session.
    pub spin_index: u32,
    /// Current gameplay substate (base, freespin, bonus, etc.).
    pub substate: String,
}

impl Default for GameplayPosition {
    fn default() -> Self {
        Self {
            frame: 0,
            hook: String::new(),
            spin_index: 0,
            substate: "base".into(),
        }
    }
}

/// Time signature for musical timeline.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct TimeSignature {
    pub numerator: u8,
    pub denominator: u8,
}

impl Default for TimeSignature {
    fn default() -> Self {
        Self {
            numerator: 4,
            denominator: 4,
        }
    }
}

/// Tempo change event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempoChange {
    pub position: MusicalPosition,
    pub bpm: f64,
    /// Ramp type: instant or gradual over beats.
    pub ramp_beats: f64,
}

/// Timeline marker type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MarkerType {
    /// Musical cue point.
    Cue,
    /// Game hook anchor (syncs musical ↔ gameplay).
    HookAnchor,
    /// Region start.
    RegionStart,
    /// Region end.
    RegionEnd,
    /// Loop point.
    LoopPoint,
    /// Bake boundary — defines stem cut points.
    BakeBoundary,
}

/// A marker on either timeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineMarker {
    pub id: String,
    pub name: String,
    pub marker_type: MarkerType,
    pub musical_pos: MusicalPosition,
    pub gameplay_pos: Option<GameplayPosition>,
    pub color: u32, // ARGB
}

/// Musical timeline — bars, beats, tempo, time signature.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicalTimeline {
    /// Base tempo in BPM.
    pub base_bpm: f64,
    /// Time signature.
    pub time_sig: TimeSignature,
    /// Tempo automation events.
    pub tempo_changes: Vec<TempoChange>,
    /// Total length in bars.
    pub length_bars: u32,
    /// Sample rate for frame conversion.
    pub sample_rate: u32,
}

impl Default for MusicalTimeline {
    fn default() -> Self {
        Self {
            base_bpm: 120.0,
            time_sig: TimeSignature::default(),
            tempo_changes: Vec::new(),
            length_bars: 32,
            sample_rate: 48000,
        }
    }
}

impl MusicalTimeline {
    /// Convert musical position to sample offset.
    pub fn position_to_samples(&self, pos: &MusicalPosition) -> u64 {
        let ticks = pos.to_ticks(&self.time_sig);
        let seconds = ticks as f64 / (480.0 * self.base_bpm / 60.0);
        (seconds * self.sample_rate as f64) as u64
    }

    /// Convert sample offset to musical position.
    pub fn samples_to_position(&self, samples: u64) -> MusicalPosition {
        let seconds = samples as f64 / self.sample_rate as f64;
        let ticks = (seconds * 480.0 * self.base_bpm / 60.0) as u64;
        MusicalPosition::from_ticks(ticks, &self.time_sig)
    }

    /// Total duration in seconds.
    pub fn duration_seconds(&self) -> f64 {
        let total_beats = self.length_bars as f64 * self.time_sig.numerator as f64;
        total_beats * 60.0 / self.base_bpm
    }
}

/// Gameplay timeline — frame-based with hook events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameplayTimeline {
    /// Registered hooks at specific frames.
    pub hook_events: Vec<HookEvent>,
    /// Total frames.
    pub total_frames: u64,
    /// Frame rate (gameplay ticks per second).
    pub frame_rate: f64,
}

/// A single hook event on the gameplay timeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HookEvent {
    pub frame: u64,
    pub hook: String,
    pub spin_index: u32,
    pub substate: String,
    /// Duration in frames (0 = instant).
    pub duration_frames: u64,
}

impl Default for GameplayTimeline {
    fn default() -> Self {
        Self {
            hook_events: Vec::new(),
            total_frames: 0,
            frame_rate: 60.0,
        }
    }
}

impl GameplayTimeline {
    /// Get hooks at a specific frame.
    pub fn hooks_at_frame(&self, frame: u64) -> Vec<&HookEvent> {
        self.hook_events
            .iter()
            .filter(|h| h.frame <= frame && frame < h.frame + h.duration_frames.max(1))
            .collect()
    }

    /// Total duration in seconds.
    pub fn duration_seconds(&self) -> f64 {
        self.total_frames as f64 / self.frame_rate
    }
}

/// Dual Timeline — the core of GAD. Musical + Gameplay running in parallel.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DualTimeline {
    pub musical: MusicalTimeline,
    pub gameplay: GameplayTimeline,
    pub markers: Vec<TimelineMarker>,
    /// Anchor points syncing musical ↔ gameplay positions.
    pub anchors: Vec<TimelineAnchor>,
}

/// An anchor point linking musical and gameplay positions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineAnchor {
    pub id: String,
    pub musical_pos: MusicalPosition,
    pub gameplay_frame: u64,
    pub hook: String,
}

impl Default for DualTimeline {
    fn default() -> Self {
        Self {
            musical: MusicalTimeline::default(),
            gameplay: GameplayTimeline::default(),
            markers: Vec::new(),
            anchors: Vec::new(),
        }
    }
}

impl DualTimeline {
    /// Create a new dual timeline with given tempo and length.
    pub fn new(bpm: f64, length_bars: u32, frame_rate: f64) -> Self {
        Self {
            musical: MusicalTimeline {
                base_bpm: bpm,
                length_bars,
                ..Default::default()
            },
            gameplay: GameplayTimeline {
                frame_rate,
                ..Default::default()
            },
            ..Default::default()
        }
    }

    /// Add an anchor syncing musical and gameplay positions.
    pub fn add_anchor(
        &mut self,
        id: impl Into<String>,
        musical_pos: MusicalPosition,
        gameplay_frame: u64,
        hook: impl Into<String>,
    ) {
        self.anchors.push(TimelineAnchor {
            id: id.into(),
            musical_pos,
            gameplay_frame,
            hook: hook.into(),
        });
    }

    /// Add a marker.
    pub fn add_marker(&mut self, marker: TimelineMarker) {
        self.markers.push(marker);
    }

    /// Get musical position from gameplay frame (interpolated between anchors).
    pub fn gameplay_to_musical(&self, frame: u64) -> MusicalPosition {
        if self.anchors.is_empty() {
            // No anchors — direct conversion via frame rate → seconds → musical
            let seconds = frame as f64 / self.gameplay.frame_rate;
            let ticks = (seconds * 480.0 * self.musical.base_bpm / 60.0) as u64;
            return MusicalPosition::from_ticks(ticks, &self.musical.time_sig);
        }

        // Find surrounding anchors
        let mut before: Option<&TimelineAnchor> = None;
        let mut after: Option<&TimelineAnchor> = None;

        for anchor in &self.anchors {
            if anchor.gameplay_frame <= frame {
                match before {
                    Some(b) if anchor.gameplay_frame > b.gameplay_frame => before = Some(anchor),
                    None => before = Some(anchor),
                    _ => {}
                }
            }
            if anchor.gameplay_frame >= frame {
                match after {
                    Some(a) if anchor.gameplay_frame < a.gameplay_frame => after = Some(anchor),
                    None => after = Some(anchor),
                    _ => {}
                }
            }
        }

        match (before, after) {
            (Some(b), Some(a)) if b.gameplay_frame != a.gameplay_frame => {
                // Interpolate
                let t = (frame - b.gameplay_frame) as f64
                    / (a.gameplay_frame - b.gameplay_frame) as f64;
                let b_ticks = b.musical_pos.to_ticks(&self.musical.time_sig);
                let a_ticks = a.musical_pos.to_ticks(&self.musical.time_sig);
                let interp_ticks = b_ticks as f64 + t * (a_ticks as f64 - b_ticks as f64);
                MusicalPosition::from_ticks(interp_ticks as u64, &self.musical.time_sig)
            }
            (Some(b), _) => b.musical_pos,
            (_, Some(a)) => a.musical_pos,
            _ => MusicalPosition::default(),
        }
    }

    /// Get all bake boundaries (sorted by musical position).
    pub fn bake_boundaries(&self) -> Vec<&TimelineMarker> {
        let mut boundaries: Vec<_> = self
            .markers
            .iter()
            .filter(|m| m.marker_type == MarkerType::BakeBoundary)
            .collect();
        boundaries.sort_by_key(|m| m.musical_pos.to_ticks(&self.musical.time_sig));
        boundaries
    }

    /// Export timeline to JSON.
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_musical_position_ticks_roundtrip() {
        let ts = TimeSignature {
            numerator: 4,
            denominator: 4,
        };
        let pos = MusicalPosition::new(2, 3, 120);
        let ticks = pos.to_ticks(&ts);
        let restored = MusicalPosition::from_ticks(ticks, &ts);
        assert_eq!(pos, restored);
    }

    #[test]
    fn test_musical_timeline_position_to_samples() {
        let tl = MusicalTimeline {
            base_bpm: 120.0,
            time_sig: TimeSignature::default(),
            sample_rate: 48000,
            length_bars: 4,
            ..Default::default()
        };
        // Bar 0, beat 0, tick 0 = 0 samples
        let samples = tl.position_to_samples(&MusicalPosition::new(0, 0, 0));
        assert_eq!(samples, 0);
        // Bar 1 at 120bpm, 4/4 = 2 seconds = 96000 samples
        let samples = tl.position_to_samples(&MusicalPosition::new(1, 0, 0));
        assert_eq!(samples, 96000);
    }

    #[test]
    fn test_dual_timeline_anchor_interpolation() {
        let mut dt = DualTimeline::new(120.0, 8, 60.0);
        dt.add_anchor("a1", MusicalPosition::new(0, 0, 0), 0, "SPIN_START");
        dt.add_anchor("a2", MusicalPosition::new(4, 0, 0), 240, "SPIN_END");

        // Midpoint: frame 120 → should be bar 2
        let pos = dt.gameplay_to_musical(120);
        assert_eq!(pos.bar, 2);
        assert_eq!(pos.beat, 0);
    }

    #[test]
    fn test_gameplay_hooks_at_frame() {
        let mut gt = GameplayTimeline::default();
        gt.hook_events.push(HookEvent {
            frame: 10,
            hook: "SPIN_START".into(),
            spin_index: 0,
            substate: "base".into(),
            duration_frames: 5,
        });
        gt.hook_events.push(HookEvent {
            frame: 20,
            hook: "REEL_STOP".into(),
            spin_index: 0,
            substate: "base".into(),
            duration_frames: 0,
        });

        assert_eq!(gt.hooks_at_frame(12).len(), 1);
        assert_eq!(gt.hooks_at_frame(12)[0].hook, "SPIN_START");
        assert_eq!(gt.hooks_at_frame(16).len(), 0); // past duration
        assert_eq!(gt.hooks_at_frame(20).len(), 1);
    }

    #[test]
    fn test_bake_boundaries() {
        let mut dt = DualTimeline::new(120.0, 8, 60.0);
        dt.add_marker(TimelineMarker {
            id: "b1".into(),
            name: "Stem 1".into(),
            marker_type: MarkerType::BakeBoundary,
            musical_pos: MusicalPosition::new(4, 0, 0),
            gameplay_pos: None,
            color: 0xFF00FF00,
        });
        dt.add_marker(TimelineMarker {
            id: "b0".into(),
            name: "Stem 0".into(),
            marker_type: MarkerType::BakeBoundary,
            musical_pos: MusicalPosition::new(0, 0, 0),
            gameplay_pos: None,
            color: 0xFF00FF00,
        });
        dt.add_marker(TimelineMarker {
            id: "cue".into(),
            name: "Cue".into(),
            marker_type: MarkerType::Cue,
            musical_pos: MusicalPosition::new(2, 0, 0),
            gameplay_pos: None,
            color: 0xFFFF0000,
        });

        let boundaries = dt.bake_boundaries();
        assert_eq!(boundaries.len(), 2); // only BakeBoundary markers
        assert_eq!(boundaries[0].id, "b0"); // sorted by position
        assert_eq!(boundaries[1].id, "b1");
    }
}
