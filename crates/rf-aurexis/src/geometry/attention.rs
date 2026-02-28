use serde::{Deserialize, Serialize};
use crate::MAX_SCREEN_EVENTS;

/// A screen event with position and importance for attention tracking.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenEvent {
    pub event_id: u32,
    /// Screen X position: -1.0 (left) to +1.0 (right).
    pub x: f32,
    /// Screen Y position: -1.0 (bottom) to +1.0 (top).
    pub y: f32,
    /// Importance weight (0.0-1.0+).
    pub weight: f32,
    /// Priority (higher = more important).
    pub priority: i32,
}

/// Computed attention vector: where audio should focus.
#[derive(Debug, Clone, Copy, Default)]
pub struct AttentionVector {
    /// X center of gravity (-1.0 to +1.0).
    pub x: f64,
    /// Y center of gravity (-1.0 to +1.0).
    pub y: f64,
    /// Focus weight (0.0 = dispersed, 1.0 = highly focused).
    pub weight: f64,
}

/// Computes audio attention center from screen events.
///
/// Formula: attention = Σ(eventWeight × screenPosition × priority) / Σ(eventWeight × priority)
pub struct AttentionVectorEngine {
    events: Vec<ScreenEvent>,
}

impl AttentionVectorEngine {
    pub fn new() -> Self {
        Self {
            events: Vec::with_capacity(MAX_SCREEN_EVENTS),
        }
    }

    /// Register a screen event (or update existing by event_id).
    pub fn register_event(&mut self, event: ScreenEvent) -> bool {
        // Update existing
        if let Some(existing) = self.events.iter_mut().find(|e| e.event_id == event.event_id) {
            *existing = event;
            return true;
        }

        if self.events.len() >= MAX_SCREEN_EVENTS {
            log::warn!("AUREXIS: Screen event capacity exceeded ({MAX_SCREEN_EVENTS})");
            return false;
        }
        self.events.push(event);
        true
    }

    /// Clear all screen events.
    pub fn clear(&mut self) {
        self.events.clear();
    }

    /// Get current event count.
    pub fn event_count(&self) -> usize {
        self.events.len()
    }

    /// Compute the attention vector (weighted center of gravity).
    pub fn compute_vector(&self) -> AttentionVector {
        if self.events.is_empty() {
            return AttentionVector::default();
        }

        let mut sum_x = 0.0_f64;
        let mut sum_y = 0.0_f64;
        let mut sum_weight = 0.0_f64;

        for event in &self.events {
            let w = event.weight as f64 * (event.priority.max(1) as f64);
            sum_x += event.x as f64 * w;
            sum_y += event.y as f64 * w;
            sum_weight += w;
        }

        if sum_weight <= 0.0 {
            return AttentionVector::default();
        }

        let center_x = sum_x / sum_weight;
        let center_y = sum_y / sum_weight;

        // Focus weight: how concentrated are the events?
        // If all events are at the same position, focus = 1.0.
        // If spread widely, focus → 0.0.
        let focus = if self.events.len() == 1 {
            1.0
        } else {
            let mut variance = 0.0_f64;
            for event in &self.events {
                let w = event.weight as f64 * (event.priority.max(1) as f64);
                let dx = event.x as f64 - center_x;
                let dy = event.y as f64 - center_y;
                variance += w * (dx * dx + dy * dy);
            }
            variance /= sum_weight;
            // Map variance to 0-1: low variance = high focus
            // Max possible variance in [-1,1]² is 4.0
            (1.0 - (variance / 2.0).sqrt()).clamp(0.0, 1.0)
        };

        AttentionVector {
            x: center_x.clamp(-1.0, 1.0),
            y: center_y.clamp(-1.0, 1.0),
            weight: focus,
        }
    }

    /// Get all events.
    pub fn events(&self) -> &[ScreenEvent] {
        &self.events
    }
}

impl Default for AttentionVectorEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_returns_zero() {
        let engine = AttentionVectorEngine::new();
        let v = engine.compute_vector();
        assert_eq!(v.x, 0.0);
        assert_eq!(v.y, 0.0);
        assert_eq!(v.weight, 0.0);
    }

    #[test]
    fn test_single_event() {
        let mut engine = AttentionVectorEngine::new();
        engine.register_event(ScreenEvent {
            event_id: 1,
            x: 0.5,
            y: -0.3,
            weight: 1.0,
            priority: 10,
        });

        let v = engine.compute_vector();
        assert!((v.x - 0.5).abs() < 0.01);
        assert!((v.y - (-0.3)).abs() < 0.01);
        assert_eq!(v.weight, 1.0); // single event = fully focused
    }

    #[test]
    fn test_weighted_center() {
        let mut engine = AttentionVectorEngine::new();
        engine.register_event(ScreenEvent {
            event_id: 1, x: -1.0, y: 0.0, weight: 1.0, priority: 1,
        });
        engine.register_event(ScreenEvent {
            event_id: 2, x: 1.0, y: 0.0, weight: 1.0, priority: 1,
        });

        let v = engine.compute_vector();
        assert!(v.x.abs() < 0.01, "Center of L+R should be 0: {}", v.x);
    }

    #[test]
    fn test_priority_weighting() {
        let mut engine = AttentionVectorEngine::new();
        engine.register_event(ScreenEvent {
            event_id: 1, x: -1.0, y: 0.0, weight: 1.0, priority: 1,
        });
        engine.register_event(ScreenEvent {
            event_id: 2, x: 1.0, y: 0.0, weight: 1.0, priority: 10,
        });

        let v = engine.compute_vector();
        // Higher priority event should pull center toward it
        assert!(v.x > 0.5, "High-priority right event should pull center right: {}", v.x);
    }

    #[test]
    fn test_focus_dispersed() {
        let mut engine = AttentionVectorEngine::new();
        // Events at all corners
        engine.register_event(ScreenEvent { event_id: 1, x: -1.0, y: -1.0, weight: 1.0, priority: 1 });
        engine.register_event(ScreenEvent { event_id: 2, x: 1.0, y: -1.0, weight: 1.0, priority: 1 });
        engine.register_event(ScreenEvent { event_id: 3, x: -1.0, y: 1.0, weight: 1.0, priority: 1 });
        engine.register_event(ScreenEvent { event_id: 4, x: 1.0, y: 1.0, weight: 1.0, priority: 1 });

        let v = engine.compute_vector();
        assert!(v.weight < 0.5, "Widely dispersed events should have low focus: {}", v.weight);
    }

    #[test]
    fn test_update_existing() {
        let mut engine = AttentionVectorEngine::new();
        engine.register_event(ScreenEvent { event_id: 1, x: -1.0, y: 0.0, weight: 1.0, priority: 1 });
        engine.register_event(ScreenEvent { event_id: 1, x: 1.0, y: 0.0, weight: 1.0, priority: 1 }); // update

        assert_eq!(engine.event_count(), 1);
        let v = engine.compute_vector();
        assert!((v.x - 1.0).abs() < 0.01, "Updated event should be at new position");
    }

    #[test]
    fn test_clear() {
        let mut engine = AttentionVectorEngine::new();
        engine.register_event(ScreenEvent { event_id: 1, x: 0.5, y: 0.5, weight: 1.0, priority: 1 });
        engine.clear();
        assert_eq!(engine.event_count(), 0);
    }
}
