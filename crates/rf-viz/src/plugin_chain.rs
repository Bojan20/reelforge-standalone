//! Plugin Chain UI Component
//!
//! Professional plugin chain visualization with:
//! - Drag & drop reordering
//! - Bypass/Solo controls
//! - Wet/Dry mix knobs
//! - Latency indicators
//! - PDC visualization

use serde::{Deserialize, Serialize};

/// Plugin chain display configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginChainConfig {
    /// Slot width
    pub slot_width: f32,
    /// Slot height
    pub slot_height: f32,
    /// Gap between slots
    pub slot_gap: f32,
    /// Show latency indicators
    pub show_latency: bool,
    /// Show PDC compensation
    pub show_pdc: bool,
    /// Show CPU meters
    pub show_cpu: bool,
    /// Horizontal layout
    pub horizontal: bool,
    /// Compact mode
    pub compact: bool,
}

impl Default for PluginChainConfig {
    fn default() -> Self {
        Self {
            slot_width: 200.0,
            slot_height: 80.0,
            slot_gap: 8.0,
            show_latency: true,
            show_pdc: true,
            show_cpu: true,
            horizontal: true,
            compact: false,
        }
    }
}

/// Plugin chain slot state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainSlotState {
    /// Slot index
    pub index: usize,
    /// Plugin ID
    pub plugin_id: String,
    /// Plugin name
    pub plugin_name: String,
    /// Vendor name
    pub vendor: String,
    /// Is bypassed
    pub bypassed: bool,
    /// Is soloed
    pub soloed: bool,
    /// Wet/dry mix (0-1)
    pub mix: f32,
    /// Latency in samples
    pub latency_samples: u32,
    /// PDC compensation in samples
    pub pdc_compensation: u32,
    /// CPU usage percentage
    pub cpu_usage: f32,
    /// Is editor open
    pub editor_open: bool,
    /// Has pending parameter changes
    pub has_changes: bool,
}

impl ChainSlotState {
    /// Create new slot state
    pub fn new(index: usize, plugin_id: &str, plugin_name: &str) -> Self {
        Self {
            index,
            plugin_id: plugin_id.to_string(),
            plugin_name: plugin_name.to_string(),
            vendor: String::new(),
            bypassed: false,
            soloed: false,
            mix: 1.0,
            latency_samples: 0,
            pdc_compensation: 0,
            cpu_usage: 0.0,
            editor_open: false,
            has_changes: false,
        }
    }
}

/// Plugin chain UI state
#[derive(Debug, Clone, Default)]
pub struct PluginChainState {
    /// Chain slots
    pub slots: Vec<ChainSlotState>,
    /// Selected slot index
    pub selected: Option<usize>,
    /// Hovered slot index
    pub hovered: Option<usize>,
    /// Dragging slot index
    pub dragging: Option<usize>,
    /// Drop target index
    pub drop_target: Option<usize>,
    /// Total chain latency
    pub total_latency: u32,
    /// Total CPU usage
    pub total_cpu: f32,
    /// Chain is processing
    pub is_processing: bool,
    /// Chain is bypassed
    pub chain_bypassed: bool,
}

impl PluginChainState {
    /// Create new chain state
    pub fn new() -> Self {
        Self::default()
    }

    /// Add slot to chain
    pub fn add_slot(&mut self, slot: ChainSlotState) {
        self.slots.push(slot);
        self.recalculate_totals();
    }

    /// Remove slot at index
    pub fn remove_slot(&mut self, index: usize) -> Option<ChainSlotState> {
        if index < self.slots.len() {
            let slot = self.slots.remove(index);
            // Update indices
            for (i, s) in self.slots.iter_mut().enumerate() {
                s.index = i;
            }
            self.recalculate_totals();
            Some(slot)
        } else {
            None
        }
    }

    /// Move slot from one index to another
    pub fn move_slot(&mut self, from: usize, to: usize) {
        if from < self.slots.len() && to <= self.slots.len() && from != to {
            let slot = self.slots.remove(from);
            let insert_at = if to > from { to - 1 } else { to };
            self.slots.insert(insert_at, slot);

            // Update indices
            for (i, s) in self.slots.iter_mut().enumerate() {
                s.index = i;
            }
        }
    }

    /// Toggle bypass on slot
    pub fn toggle_bypass(&mut self, index: usize) {
        if let Some(slot) = self.slots.get_mut(index) {
            slot.bypassed = !slot.bypassed;
            self.recalculate_totals();
        }
    }

    /// Toggle solo on slot
    pub fn toggle_solo(&mut self, index: usize) {
        if let Some(slot) = self.slots.get_mut(index) {
            slot.soloed = !slot.soloed;
        }
    }

    /// Set mix on slot
    pub fn set_mix(&mut self, index: usize, mix: f32) {
        if let Some(slot) = self.slots.get_mut(index) {
            slot.mix = mix.clamp(0.0, 1.0);
        }
    }

    /// Recalculate total latency and CPU
    pub fn recalculate_totals(&mut self) {
        self.total_latency = self.slots
            .iter()
            .filter(|s| !s.bypassed)
            .map(|s| s.latency_samples)
            .max()
            .unwrap_or(0);

        self.total_cpu = self.slots
            .iter()
            .filter(|s| !s.bypassed)
            .map(|s| s.cpu_usage)
            .sum();
    }

    /// Check if any slot is soloed
    pub fn has_solo(&self) -> bool {
        self.slots.iter().any(|s| s.soloed)
    }

    /// Get effective slots (considering solo)
    pub fn get_active_slots(&self) -> Vec<usize> {
        if self.has_solo() {
            self.slots
                .iter()
                .enumerate()
                .filter(|(_, s)| s.soloed && !s.bypassed)
                .map(|(i, _)| i)
                .collect()
        } else {
            self.slots
                .iter()
                .enumerate()
                .filter(|(_, s)| !s.bypassed)
                .map(|(i, _)| i)
                .collect()
        }
    }
}

/// Chain layout calculations
#[derive(Debug, Clone)]
pub struct ChainLayout {
    /// Total width
    pub width: f32,
    /// Total height
    pub height: f32,
    /// Header height
    pub header_height: f32,
    /// Slot positions
    pub slot_rects: Vec<LayoutRect>,
    /// Add button rect
    pub add_button_rect: LayoutRect,
    /// Total chain rect
    pub chain_rect: LayoutRect,
}

/// Simple rect
#[derive(Debug, Clone, Copy, Default)]
pub struct LayoutRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl LayoutRect {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self { x, y, width, height }
    }

    pub fn contains(&self, px: f32, py: f32) -> bool {
        px >= self.x && px < self.x + self.width &&
        py >= self.y && py < self.y + self.height
    }

    pub fn center(&self) -> (f32, f32) {
        (self.x + self.width / 2.0, self.y + self.height / 2.0)
    }
}

impl ChainLayout {
    /// Calculate layout
    pub fn calculate(
        width: f32,
        height: f32,
        slot_count: usize,
        config: &PluginChainConfig,
    ) -> Self {
        let header_height = if config.compact { 24.0 } else { 36.0 };
        let slot_width = if config.compact { config.slot_width * 0.75 } else { config.slot_width };
        let slot_height = if config.compact { config.slot_height * 0.75 } else { config.slot_height };
        let gap = config.slot_gap;
        let padding = 8.0;

        let mut slot_rects = Vec::with_capacity(slot_count);

        if config.horizontal {
            // Horizontal layout
            let start_x = padding;
            let start_y = header_height + padding;

            for i in 0..slot_count {
                let x = start_x + i as f32 * (slot_width + gap);
                slot_rects.push(LayoutRect::new(x, start_y, slot_width, slot_height));
            }

            let add_x = start_x + slot_count as f32 * (slot_width + gap);
            let add_button_rect = LayoutRect::new(add_x, start_y, 48.0, slot_height);

            let chain_width = add_x + 48.0 + padding;
            let chain_rect = LayoutRect::new(0.0, 0.0, chain_width, height);

            Self {
                width,
                height,
                header_height,
                slot_rects,
                add_button_rect,
                chain_rect,
            }
        } else {
            // Vertical layout
            let start_x = padding;
            let start_y = header_height + padding;

            for i in 0..slot_count {
                let y = start_y + i as f32 * (slot_height + gap);
                slot_rects.push(LayoutRect::new(start_x, y, slot_width, slot_height));
            }

            let add_y = start_y + slot_count as f32 * (slot_height + gap);
            let add_button_rect = LayoutRect::new(start_x, add_y, slot_width, 48.0);

            let chain_height = add_y + 48.0 + padding;
            let chain_rect = LayoutRect::new(0.0, 0.0, width, chain_height);

            Self {
                width,
                height,
                header_height,
                slot_rects,
                add_button_rect,
                chain_rect,
            }
        }
    }

    /// Find slot at position
    pub fn slot_at_position(&self, x: f32, y: f32) -> Option<usize> {
        self.slot_rects
            .iter()
            .position(|r| r.contains(x, y))
    }

    /// Find drop target between slots
    pub fn drop_target_at_position(&self, x: f32, y: f32, config: &PluginChainConfig) -> Option<usize> {
        if self.slot_rects.is_empty() {
            return Some(0);
        }

        if config.horizontal {
            for (i, rect) in self.slot_rects.iter().enumerate() {
                if x < rect.x + rect.width / 2.0 {
                    return Some(i);
                }
            }
            Some(self.slot_rects.len())
        } else {
            for (i, rect) in self.slot_rects.iter().enumerate() {
                if y < rect.y + rect.height / 2.0 {
                    return Some(i);
                }
            }
            Some(self.slot_rects.len())
        }
    }
}

/// GPU vertex for chain rendering
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct ChainVertex {
    pub position: [f32; 2],
    pub uv: [f32; 2],
    pub color: [f32; 4],
}

/// Generate slot background mesh
pub fn generate_slot_mesh(rect: &LayoutRect, color: [f32; 4], _corner_radius: f32) -> Vec<ChainVertex> {
    // For simplicity, generate a basic rectangle
    // A proper implementation would generate rounded corners
    vec![
        ChainVertex { position: [rect.x, rect.y], uv: [0.0, 0.0], color },
        ChainVertex { position: [rect.x + rect.width, rect.y], uv: [1.0, 0.0], color },
        ChainVertex { position: [rect.x + rect.width, rect.y + rect.height], uv: [1.0, 1.0], color },
        ChainVertex { position: [rect.x, rect.y], uv: [0.0, 0.0], color },
        ChainVertex { position: [rect.x + rect.width, rect.y + rect.height], uv: [1.0, 1.0], color },
        ChainVertex { position: [rect.x, rect.y + rect.height], uv: [0.0, 1.0], color },
    ]
}

/// Generate connection line between slots
pub fn generate_connection_line(
    from: &LayoutRect,
    to: &LayoutRect,
    color: [f32; 4],
    thickness: f32,
    horizontal: bool,
) -> Vec<ChainVertex> {
    let (x1, y1) = if horizontal {
        (from.x + from.width, from.y + from.height / 2.0)
    } else {
        (from.x + from.width / 2.0, from.y + from.height)
    };

    let (x2, y2) = if horizontal {
        (to.x, to.y + to.height / 2.0)
    } else {
        (to.x + to.width / 2.0, to.y)
    };

    let half = thickness / 2.0;

    if horizontal {
        vec![
            ChainVertex { position: [x1, y1 - half], uv: [0.0, 0.0], color },
            ChainVertex { position: [x2, y2 - half], uv: [1.0, 0.0], color },
            ChainVertex { position: [x2, y2 + half], uv: [1.0, 1.0], color },
            ChainVertex { position: [x1, y1 - half], uv: [0.0, 0.0], color },
            ChainVertex { position: [x2, y2 + half], uv: [1.0, 1.0], color },
            ChainVertex { position: [x1, y1 + half], uv: [0.0, 1.0], color },
        ]
    } else {
        vec![
            ChainVertex { position: [x1 - half, y1], uv: [0.0, 0.0], color },
            ChainVertex { position: [x1 + half, y1], uv: [1.0, 0.0], color },
            ChainVertex { position: [x2 + half, y2], uv: [1.0, 1.0], color },
            ChainVertex { position: [x1 - half, y1], uv: [0.0, 0.0], color },
            ChainVertex { position: [x2 + half, y2], uv: [1.0, 1.0], color },
            ChainVertex { position: [x2 - half, y2], uv: [0.0, 1.0], color },
        ]
    }
}

/// Slot state colors
pub fn slot_color(state: &ChainSlotState, is_selected: bool, is_hovered: bool) -> [f32; 4] {
    let base = if state.bypassed {
        [0.15, 0.15, 0.18, 1.0]  // Dark gray for bypassed
    } else if state.soloed {
        [0.2, 0.25, 0.15, 1.0]  // Greenish for soloed
    } else {
        [0.1, 0.1, 0.12, 1.0]  // Default dark
    };

    if is_selected {
        [base[0] + 0.1, base[1] + 0.15, base[2] + 0.25, 1.0]
    } else if is_hovered {
        [base[0] + 0.05, base[1] + 0.05, base[2] + 0.08, 1.0]
    } else {
        base
    }
}

/// Latency indicator color
pub fn latency_color(latency_samples: u32, sample_rate: u32) -> [f32; 4] {
    let latency_ms = latency_samples as f32 / sample_rate as f32 * 1000.0;

    if latency_ms < 1.0 {
        [0.25, 1.0, 0.56, 1.0]  // Green - negligible
    } else if latency_ms < 5.0 {
        [1.0, 0.78, 0.25, 1.0]  // Yellow - noticeable
    } else if latency_ms < 20.0 {
        [1.0, 0.56, 0.25, 1.0]  // Orange - significant
    } else {
        [1.0, 0.25, 0.38, 1.0]  // Red - problematic
    }
}

/// CPU usage color
pub fn cpu_color(cpu_percent: f32) -> [f32; 4] {
    if cpu_percent < 10.0 {
        [0.25, 1.0, 0.56, 1.0]  // Green - low
    } else if cpu_percent < 30.0 {
        [1.0, 0.78, 0.25, 1.0]  // Yellow - moderate
    } else if cpu_percent < 60.0 {
        [1.0, 0.56, 0.25, 1.0]  // Orange - high
    } else {
        [1.0, 0.25, 0.38, 1.0]  // Red - critical
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chain_config_default() {
        let config = PluginChainConfig::default();
        assert!(config.show_latency);
        assert!(config.horizontal);
    }

    #[test]
    fn test_chain_state() {
        let mut state = PluginChainState::new();
        state.add_slot(ChainSlotState::new(0, "test.eq", "Test EQ"));

        assert_eq!(state.slots.len(), 1);
        assert_eq!(state.slots[0].plugin_name, "Test EQ");
    }

    #[test]
    fn test_chain_layout() {
        let config = PluginChainConfig::default();
        let layout = ChainLayout::calculate(800.0, 120.0, 3, &config);

        assert_eq!(layout.slot_rects.len(), 3);
    }

    #[test]
    fn test_move_slot() {
        let mut state = PluginChainState::new();
        state.add_slot(ChainSlotState::new(0, "plugin.1", "Plugin 1"));
        state.add_slot(ChainSlotState::new(1, "plugin.2", "Plugin 2"));
        state.add_slot(ChainSlotState::new(2, "plugin.3", "Plugin 3"));

        state.move_slot(0, 2);

        assert_eq!(state.slots[0].plugin_id, "plugin.2");
        assert_eq!(state.slots[1].plugin_id, "plugin.1");
    }

    #[test]
    fn test_bypass_toggle() {
        let mut state = PluginChainState::new();
        state.add_slot(ChainSlotState::new(0, "test", "Test"));

        assert!(!state.slots[0].bypassed);
        state.toggle_bypass(0);
        assert!(state.slots[0].bypassed);
    }
}
