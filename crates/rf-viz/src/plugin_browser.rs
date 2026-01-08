//! Plugin Browser UI Component
//!
//! Professional plugin browser with:
//! - Category filtering
//! - Search functionality
//! - Grid/List views
//! - Plugin status indicators
//! - Drag & drop support

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Plugin browser configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginBrowserConfig {
    /// View mode (grid or list)
    pub view_mode: BrowserViewMode,
    /// Sort order
    pub sort_by: SortCriteria,
    /// Sort direction
    pub sort_ascending: bool,
    /// Show internal plugins
    pub show_internal: bool,
    /// Show VST3 plugins
    pub show_vst3: bool,
    /// Show CLAP plugins
    pub show_clap: bool,
    /// Show AU plugins
    pub show_au: bool,
    /// Show LV2 plugins
    pub show_lv2: bool,
    /// Category filter (None = all)
    pub category_filter: Option<PluginCategoryFilter>,
    /// Search query
    pub search_query: String,
    /// Grid cell size
    pub grid_cell_size: f32,
    /// List row height
    pub list_row_height: f32,
}

impl Default for PluginBrowserConfig {
    fn default() -> Self {
        Self {
            view_mode: BrowserViewMode::Grid,
            sort_by: SortCriteria::Name,
            sort_ascending: true,
            show_internal: true,
            show_vst3: true,
            show_clap: true,
            show_au: true,
            show_lv2: true,
            category_filter: None,
            search_query: String::new(),
            grid_cell_size: 100.0,
            list_row_height: 32.0,
        }
    }
}

/// View mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BrowserViewMode {
    /// Grid view with icons
    Grid,
    /// List view with details
    List,
}

/// Sort criteria
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SortCriteria {
    /// Sort by name
    Name,
    /// Sort by vendor
    Vendor,
    /// Sort by format (VST3, CLAP, etc.)
    Format,
    /// Sort by category
    Category,
    /// Sort by most recently used
    RecentlyUsed,
}

/// Plugin category filter
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PluginCategoryFilter {
    /// Effects
    Effect,
    /// Instruments
    Instrument,
    /// Analyzers
    Analyzer,
    /// Utilities
    Utility,
    /// Dynamics
    Dynamics,
    /// EQ
    Eq,
    /// Reverb & Delay
    TimeEffects,
    /// Spatial
    Spatial,
    /// Favorites
    Favorites,
}

/// Plugin item for display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginBrowserItem {
    /// Unique ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Vendor
    pub vendor: String,
    /// Format type
    pub format: PluginFormat,
    /// Category
    pub category: PluginCategoryFilter,
    /// Is favorite
    pub is_favorite: bool,
    /// Is recently used
    pub is_recent: bool,
    /// Last used timestamp
    pub last_used: Option<u64>,
    /// Use count
    pub use_count: u32,
    /// Validation status
    pub validation_status: PluginValidationStatus,
    /// Icon data (base64 or path)
    pub icon: Option<String>,
}

/// Plugin format type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PluginFormat {
    /// Internal ReelForge plugin
    Internal,
    /// VST3
    Vst3,
    /// CLAP
    Clap,
    /// Audio Unit
    AudioUnit,
    /// LV2
    Lv2,
}

/// Plugin validation status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PluginValidationStatus {
    /// Not yet validated
    Unknown,
    /// Currently being scanned
    Scanning,
    /// Validation passed
    Valid,
    /// Validation failed
    Invalid,
    /// Plugin crashed during scan
    Crashed,
    /// Blacklisted
    Blacklisted,
}

/// Browser state
#[derive(Debug, Clone, Default)]
pub struct PluginBrowserState {
    /// All available plugins
    pub plugins: Vec<PluginBrowserItem>,
    /// Filtered/sorted plugins for display
    pub filtered_plugins: Vec<usize>,
    /// Currently selected plugin index
    pub selected: Option<usize>,
    /// Hovered plugin index
    pub hovered: Option<usize>,
    /// Scroll position
    pub scroll_offset: f32,
    /// Is currently scanning
    pub is_scanning: bool,
    /// Scan progress (0.0 - 1.0)
    pub scan_progress: f32,
    /// Category counts
    pub category_counts: HashMap<PluginCategoryFilter, usize>,
    /// Format counts
    pub format_counts: HashMap<PluginFormat, usize>,
}

impl PluginBrowserState {
    /// Create new browser state
    pub fn new() -> Self {
        Self::default()
    }

    /// Update filtered plugins based on config
    pub fn apply_filter(&mut self, config: &PluginBrowserConfig) {
        let query = config.search_query.to_lowercase();

        self.filtered_plugins = self.plugins
            .iter()
            .enumerate()
            .filter(|(_, p)| {
                // Format filter
                let format_ok = match p.format {
                    PluginFormat::Internal => config.show_internal,
                    PluginFormat::Vst3 => config.show_vst3,
                    PluginFormat::Clap => config.show_clap,
                    PluginFormat::AudioUnit => config.show_au,
                    PluginFormat::Lv2 => config.show_lv2,
                };

                if !format_ok {
                    return false;
                }

                // Category filter
                if let Some(cat) = config.category_filter {
                    if p.category != cat && cat != PluginCategoryFilter::Favorites {
                        return false;
                    }
                    if cat == PluginCategoryFilter::Favorites && !p.is_favorite {
                        return false;
                    }
                }

                // Search filter
                if !query.is_empty() {
                    let name_match = p.name.to_lowercase().contains(&query);
                    let vendor_match = p.vendor.to_lowercase().contains(&query);
                    if !name_match && !vendor_match {
                        return false;
                    }
                }

                true
            })
            .map(|(i, _)| i)
            .collect();

        // Sort
        let plugins = &self.plugins;
        self.filtered_plugins.sort_by(|&a, &b| {
            let pa = &plugins[a];
            let pb = &plugins[b];

            let cmp = match config.sort_by {
                SortCriteria::Name => pa.name.cmp(&pb.name),
                SortCriteria::Vendor => pa.vendor.cmp(&pb.vendor),
                SortCriteria::Format => format!("{:?}", pa.format).cmp(&format!("{:?}", pb.format)),
                SortCriteria::Category => format!("{:?}", pa.category).cmp(&format!("{:?}", pb.category)),
                SortCriteria::RecentlyUsed => pb.last_used.cmp(&pa.last_used),
            };

            if config.sort_ascending {
                cmp
            } else {
                cmp.reverse()
            }
        });
    }

    /// Update category counts
    pub fn update_counts(&mut self) {
        self.category_counts.clear();
        self.format_counts.clear();

        for plugin in &self.plugins {
            *self.category_counts.entry(plugin.category).or_insert(0) += 1;
            *self.format_counts.entry(plugin.format).or_insert(0) += 1;
        }
    }

    /// Get selected plugin
    pub fn get_selected(&self) -> Option<&PluginBrowserItem> {
        self.selected.and_then(|i| self.plugins.get(i))
    }

    /// Add plugin to state
    pub fn add_plugin(&mut self, item: PluginBrowserItem) {
        self.plugins.push(item);
    }

    /// Clear all plugins
    pub fn clear(&mut self) {
        self.plugins.clear();
        self.filtered_plugins.clear();
        self.selected = None;
        self.category_counts.clear();
        self.format_counts.clear();
    }

    /// Toggle favorite status
    pub fn toggle_favorite(&mut self, id: &str) {
        if let Some(plugin) = self.plugins.iter_mut().find(|p| p.id == id) {
            plugin.is_favorite = !plugin.is_favorite;
        }
    }
}

/// Plugin browser layout calculations
#[derive(Debug, Clone)]
pub struct BrowserLayout {
    /// Total width
    pub width: f32,
    /// Total height
    pub height: f32,
    /// Sidebar width
    pub sidebar_width: f32,
    /// Header height
    pub header_height: f32,
    /// Content area
    pub content_rect: LayoutRect,
    /// Sidebar area
    pub sidebar_rect: LayoutRect,
    /// Search bar area
    pub search_rect: LayoutRect,
    /// Grid columns
    pub grid_columns: usize,
    /// Visible items count
    pub visible_items: usize,
}

/// Simple rect for layout
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
}

impl BrowserLayout {
    /// Calculate layout
    pub fn calculate(width: f32, height: f32, config: &PluginBrowserConfig) -> Self {
        let sidebar_width = 200.0;
        let header_height = 48.0;
        let padding = 8.0;

        let content_x = sidebar_width + padding;
        let content_y = header_height + padding;
        let content_width = width - sidebar_width - padding * 2.0;
        let content_height = height - header_height - padding * 2.0;

        let grid_columns = if config.view_mode == BrowserViewMode::Grid {
            ((content_width - padding) / (config.grid_cell_size + padding)).floor().max(1.0) as usize
        } else {
            1
        };

        let item_height = if config.view_mode == BrowserViewMode::Grid {
            config.grid_cell_size
        } else {
            config.list_row_height
        };

        let visible_items = (content_height / item_height).ceil() as usize * grid_columns;

        Self {
            width,
            height,
            sidebar_width,
            header_height,
            content_rect: LayoutRect::new(content_x, content_y, content_width, content_height),
            sidebar_rect: LayoutRect::new(0.0, header_height, sidebar_width, height - header_height),
            search_rect: LayoutRect::new(sidebar_width, 0.0, content_width, header_height),
            grid_columns,
            visible_items,
        }
    }

    /// Get item rect at index
    pub fn get_item_rect(&self, index: usize, config: &PluginBrowserConfig, scroll_offset: f32) -> LayoutRect {
        let padding = 8.0;

        if config.view_mode == BrowserViewMode::Grid {
            let col = index % self.grid_columns;
            let row = index / self.grid_columns;

            let x = self.content_rect.x + col as f32 * (config.grid_cell_size + padding);
            let y = self.content_rect.y + row as f32 * (config.grid_cell_size + padding) - scroll_offset;

            LayoutRect::new(x, y, config.grid_cell_size, config.grid_cell_size)
        } else {
            let x = self.content_rect.x;
            let y = self.content_rect.y + index as f32 * config.list_row_height - scroll_offset;

            LayoutRect::new(x, y, self.content_rect.width, config.list_row_height)
        }
    }

    /// Find item at position
    pub fn item_at_position(
        &self,
        x: f32,
        y: f32,
        config: &PluginBrowserConfig,
        scroll_offset: f32,
        item_count: usize,
    ) -> Option<usize> {
        if !self.content_rect.contains(x, y) {
            return None;
        }

        let padding = 8.0;
        let local_y = y - self.content_rect.y + scroll_offset;
        let local_x = x - self.content_rect.x;

        if config.view_mode == BrowserViewMode::Grid {
            let col = (local_x / (config.grid_cell_size + padding)).floor() as usize;
            let row = (local_y / (config.grid_cell_size + padding)).floor() as usize;

            if col < self.grid_columns {
                let index = row * self.grid_columns + col;
                if index < item_count {
                    return Some(index);
                }
            }
        } else {
            let row = (local_y / config.list_row_height).floor() as usize;
            if row < item_count {
                return Some(row);
            }
        }

        None
    }
}

/// GPU vertices for plugin browser rendering
#[repr(C)]
#[derive(Debug, Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
pub struct BrowserVertex {
    pub position: [f32; 2],
    pub uv: [f32; 2],
    pub color: [f32; 4],
}

/// Generate grid cell mesh
pub fn generate_grid_cell(rect: &LayoutRect, color: [f32; 4]) -> Vec<BrowserVertex> {
    vec![
        BrowserVertex { position: [rect.x, rect.y], uv: [0.0, 0.0], color },
        BrowserVertex { position: [rect.x + rect.width, rect.y], uv: [1.0, 0.0], color },
        BrowserVertex { position: [rect.x + rect.width, rect.y + rect.height], uv: [1.0, 1.0], color },
        BrowserVertex { position: [rect.x, rect.y], uv: [0.0, 0.0], color },
        BrowserVertex { position: [rect.x + rect.width, rect.y + rect.height], uv: [1.0, 1.0], color },
        BrowserVertex { position: [rect.x, rect.y + rect.height], uv: [0.0, 1.0], color },
    ]
}

/// Plugin format color
pub fn format_color(format: PluginFormat) -> [f32; 4] {
    match format {
        PluginFormat::Internal => [0.29, 0.62, 1.0, 1.0],  // Blue
        PluginFormat::Vst3 => [1.0, 0.56, 0.25, 1.0],     // Orange
        PluginFormat::Clap => [0.25, 1.0, 0.56, 1.0],     // Green
        PluginFormat::AudioUnit => [0.75, 0.56, 1.0, 1.0], // Purple
        PluginFormat::Lv2 => [1.0, 0.78, 0.25, 1.0],      // Yellow
    }
}

/// Validation status color
pub fn status_color(status: PluginValidationStatus) -> [f32; 4] {
    match status {
        PluginValidationStatus::Unknown => [0.5, 0.5, 0.5, 1.0],
        PluginValidationStatus::Scanning => [0.29, 0.62, 1.0, 1.0],
        PluginValidationStatus::Valid => [0.25, 1.0, 0.56, 1.0],
        PluginValidationStatus::Invalid => [1.0, 0.56, 0.25, 1.0],
        PluginValidationStatus::Crashed => [1.0, 0.25, 0.38, 1.0],
        PluginValidationStatus::Blacklisted => [1.0, 0.25, 0.38, 0.5],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_browser_config_default() {
        let config = PluginBrowserConfig::default();
        assert_eq!(config.view_mode, BrowserViewMode::Grid);
        assert!(config.show_vst3);
    }

    #[test]
    fn test_browser_layout() {
        let config = PluginBrowserConfig::default();
        let layout = BrowserLayout::calculate(1200.0, 800.0, &config);

        assert!(layout.grid_columns >= 1);
        assert!(layout.content_rect.width > 0.0);
    }

    #[test]
    fn test_browser_state() {
        let mut state = PluginBrowserState::new();
        state.add_plugin(PluginBrowserItem {
            id: "test.plugin".to_string(),
            name: "Test Plugin".to_string(),
            vendor: "Test Vendor".to_string(),
            format: PluginFormat::Vst3,
            category: PluginCategoryFilter::Effect,
            is_favorite: false,
            is_recent: false,
            last_used: None,
            use_count: 0,
            validation_status: PluginValidationStatus::Valid,
            icon: None,
        });

        assert_eq!(state.plugins.len(), 1);

        let config = PluginBrowserConfig::default();
        state.apply_filter(&config);

        assert_eq!(state.filtered_plugins.len(), 1);
    }

    #[test]
    fn test_format_colors() {
        let internal = format_color(PluginFormat::Internal);
        let vst3 = format_color(PluginFormat::Vst3);

        assert_ne!(internal, vst3);
    }
}
