//! Ultimate UI Widget Primitives
//!
//! Professional DAW widget definitions:
//! - Knobs (continuous, stepped)
//! - Sliders (horizontal, vertical)
//! - Buttons (toggle, momentary, radio)
//! - Meters (VU, PPM, LUFS)
//! - XY Pads
//! - Waveform displays
//! - Keyboard shortcuts

use serde::{Deserialize, Serialize};

/// Widget interaction state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InteractionState {
    #[default]
    Normal,
    Hovered,
    Pressed,
    Disabled,
    Focused,
}

/// Knob widget configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnobConfig {
    /// Minimum value
    pub min: f64,
    /// Maximum value
    pub max: f64,
    /// Default value
    pub default: f64,
    /// Step size (0 for continuous)
    pub step: f64,
    /// Rotation range in degrees (typically 270)
    pub rotation_range: f32,
    /// Fine control multiplier
    pub fine_multiplier: f64,
    /// Display unit (dB, Hz, %, etc.)
    pub unit: String,
    /// Value display format
    pub format: ValueFormat,
    /// Show value on hover
    pub show_value_on_hover: bool,
    /// Bipolar mode (center = 0)
    pub bipolar: bool,
}

impl Default for KnobConfig {
    fn default() -> Self {
        Self {
            min: 0.0,
            max: 1.0,
            default: 0.5,
            step: 0.0,
            rotation_range: 270.0,
            fine_multiplier: 0.1,
            unit: String::new(),
            format: ValueFormat::Decimal(2),
            show_value_on_hover: true,
            bipolar: false,
        }
    }
}

/// Value display format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ValueFormat {
    /// Integer
    Integer,
    /// Decimal with N places
    Decimal(u8),
    /// Percentage
    Percent,
    /// Decibels
    Decibels,
    /// Frequency (Hz/kHz)
    Frequency,
    /// Time (ms/s)
    Time,
    /// Custom format string
    Custom(String),
}

impl Default for ValueFormat {
    fn default() -> Self {
        Self::Decimal(2)
    }
}

impl ValueFormat {
    /// Format a value
    pub fn format(&self, value: f64, unit: &str) -> String {
        match self {
            Self::Integer => format!("{}{}", value.round() as i64, unit),
            Self::Decimal(n) => format!("{:.prec$}{}", value, unit, prec = *n as usize),
            Self::Percent => format!("{:.1}%", value * 100.0),
            Self::Decibels => {
                if value <= -144.0 {
                    String::from("-∞ dB")
                } else {
                    format!("{:+.1} dB", value)
                }
            }
            Self::Frequency => {
                if value >= 1000.0 {
                    format!("{:.2} kHz", value / 1000.0)
                } else {
                    format!("{:.1} Hz", value)
                }
            }
            Self::Time => {
                if value >= 1000.0 {
                    format!("{:.2} s", value / 1000.0)
                } else {
                    format!("{:.1} ms", value)
                }
            }
            Self::Custom(fmt) => fmt.replace("{}", &value.to_string()),
        }
    }
}

/// Knob state
#[derive(Debug, Clone, Default)]
pub struct KnobState {
    /// Current normalized value (0-1)
    pub normalized: f64,
    /// Interaction state
    pub interaction: InteractionState,
    /// Is being automated
    pub automated: bool,
    /// Has modulation
    pub modulated: bool,
    /// Modulation depth
    pub mod_depth: f64,
}

impl KnobState {
    /// Get actual value from normalized
    pub fn value(&self, config: &KnobConfig) -> f64 {
        config.min + self.normalized * (config.max - config.min)
    }

    /// Set value (clamped and normalized)
    pub fn set_value(&mut self, value: f64, config: &KnobConfig) {
        self.normalized = ((value - config.min) / (config.max - config.min)).clamp(0.0, 1.0);
    }

    /// Reset to default
    pub fn reset(&mut self, config: &KnobConfig) {
        self.set_value(config.default, config);
    }
}

/// Slider orientation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SliderOrientation {
    Horizontal,
    Vertical,
}

impl Default for SliderOrientation {
    fn default() -> Self {
        Self::Horizontal
    }
}

/// Slider configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SliderConfig {
    /// Minimum value
    pub min: f64,
    /// Maximum value
    pub max: f64,
    /// Default value
    pub default: f64,
    /// Step size (0 for continuous)
    pub step: f64,
    /// Orientation
    pub orientation: SliderOrientation,
    /// Track thickness
    pub track_thickness: f32,
    /// Handle size
    pub handle_size: f32,
    /// Display unit
    pub unit: String,
    /// Value format
    pub format: ValueFormat,
    /// Show ticks
    pub show_ticks: bool,
    /// Tick count
    pub tick_count: usize,
}

impl Default for SliderConfig {
    fn default() -> Self {
        Self {
            min: 0.0,
            max: 1.0,
            default: 0.5,
            step: 0.0,
            orientation: SliderOrientation::Horizontal,
            track_thickness: 4.0,
            handle_size: 16.0,
            unit: String::new(),
            format: ValueFormat::Decimal(2),
            show_ticks: false,
            tick_count: 5,
        }
    }
}

/// Button type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ButtonType {
    /// Standard click button
    Momentary,
    /// Toggle on/off
    Toggle,
    /// Radio button (mutually exclusive)
    Radio,
}

impl Default for ButtonType {
    fn default() -> Self {
        Self::Momentary
    }
}

/// Button configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ButtonConfig {
    /// Button type
    pub button_type: ButtonType,
    /// Label text
    pub label: String,
    /// Icon (optional)
    pub icon: Option<String>,
    /// Show label
    pub show_label: bool,
    /// Minimum width
    pub min_width: f32,
    /// Height
    pub height: f32,
}

impl Default for ButtonConfig {
    fn default() -> Self {
        Self {
            button_type: ButtonType::Momentary,
            label: String::new(),
            icon: None,
            show_label: true,
            min_width: 80.0,
            height: 28.0,
        }
    }
}

/// Button state
#[derive(Debug, Clone, Default)]
pub struct ButtonState {
    /// Is toggled on
    pub toggled: bool,
    /// Interaction state
    pub interaction: InteractionState,
}

/// Meter type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MeterType {
    /// Peak meter
    Peak,
    /// VU meter (average)
    Vu,
    /// PPM meter
    Ppm,
    /// True peak
    TruePeak,
    /// LUFS integrated
    LufsIntegrated,
    /// LUFS short-term
    LufsShortTerm,
    /// LUFS momentary
    LufsMomentary,
}

impl Default for MeterType {
    fn default() -> Self {
        Self::Peak
    }
}

/// Meter configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeterConfig {
    /// Meter type
    pub meter_type: MeterType,
    /// Minimum dB
    pub min_db: f64,
    /// Maximum dB
    pub max_db: f64,
    /// Reference level (0 dB point)
    pub reference_db: f64,
    /// Show peak hold
    pub peak_hold: bool,
    /// Peak hold time (ms)
    pub peak_hold_ms: f64,
    /// Orientation
    pub orientation: SliderOrientation,
    /// Width (or height for horizontal)
    pub thickness: f32,
    /// Show scale
    pub show_scale: bool,
    /// Show numeric value
    pub show_value: bool,
    /// Segmented display
    pub segmented: bool,
    /// Segment count
    pub segment_count: usize,
}

impl Default for MeterConfig {
    fn default() -> Self {
        Self {
            meter_type: MeterType::Peak,
            min_db: -60.0,
            max_db: 6.0,
            reference_db: 0.0,
            peak_hold: true,
            peak_hold_ms: 2000.0,
            orientation: SliderOrientation::Vertical,
            thickness: 8.0,
            show_scale: true,
            show_value: true,
            segmented: false,
            segment_count: 30,
        }
    }
}

/// Meter state
#[derive(Debug, Clone, Default)]
pub struct MeterState {
    /// Current level in dB
    pub level_db: f64,
    /// Peak hold level in dB
    pub peak_db: f64,
    /// Peak hold timestamp
    pub peak_time_ms: f64,
    /// Is clipping
    pub clipping: bool,
    /// Clip hold timestamp
    pub clip_time_ms: f64,
}

impl MeterState {
    /// Get normalized level (0-1)
    pub fn normalized(&self, config: &MeterConfig) -> f64 {
        ((self.level_db - config.min_db) / (config.max_db - config.min_db)).clamp(0.0, 1.0)
    }

    /// Get normalized peak (0-1)
    pub fn peak_normalized(&self, config: &MeterConfig) -> f64 {
        ((self.peak_db - config.min_db) / (config.max_db - config.min_db)).clamp(0.0, 1.0)
    }

    /// Update level
    pub fn update(&mut self, level_db: f64, current_time_ms: f64, config: &MeterConfig) {
        self.level_db = level_db;

        // Check clipping
        if level_db > config.max_db - 0.1 {
            self.clipping = true;
            self.clip_time_ms = current_time_ms;
        } else if current_time_ms - self.clip_time_ms > 2000.0 {
            self.clipping = false;
        }

        // Update peak hold
        if level_db > self.peak_db || current_time_ms - self.peak_time_ms > config.peak_hold_ms {
            self.peak_db = level_db;
            self.peak_time_ms = current_time_ms;
        }
    }
}

/// XY Pad configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XYPadConfig {
    /// X axis min
    pub x_min: f64,
    /// X axis max
    pub x_max: f64,
    /// Y axis min
    pub y_min: f64,
    /// Y axis max
    pub y_max: f64,
    /// X label
    pub x_label: String,
    /// Y label
    pub y_label: String,
    /// Show grid
    pub show_grid: bool,
    /// Grid divisions
    pub grid_divisions: usize,
    /// Handle size
    pub handle_size: f32,
}

impl Default for XYPadConfig {
    fn default() -> Self {
        Self {
            x_min: 0.0,
            x_max: 1.0,
            y_min: 0.0,
            y_max: 1.0,
            x_label: String::from("X"),
            y_label: String::from("Y"),
            show_grid: true,
            grid_divisions: 4,
            handle_size: 12.0,
        }
    }
}

/// XY Pad state
#[derive(Debug, Clone, Default)]
pub struct XYPadState {
    /// X value (normalized 0-1)
    pub x: f64,
    /// Y value (normalized 0-1)
    pub y: f64,
    /// Interaction state
    pub interaction: InteractionState,
}

/// Keyboard shortcut
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct KeyboardShortcut {
    /// Key code
    pub key: String,
    /// Requires Ctrl/Cmd
    pub ctrl: bool,
    /// Requires Shift
    pub shift: bool,
    /// Requires Alt/Option
    pub alt: bool,
    /// Requires Meta (Windows key / Cmd on extra)
    pub meta: bool,
}

impl KeyboardShortcut {
    /// Create simple shortcut with just a key
    pub fn key(key: &str) -> Self {
        Self {
            key: key.to_string(),
            ctrl: false,
            shift: false,
            alt: false,
            meta: false,
        }
    }

    /// Add Ctrl modifier
    pub fn ctrl(mut self) -> Self {
        self.ctrl = true;
        self
    }

    /// Add Shift modifier
    pub fn shift(mut self) -> Self {
        self.shift = true;
        self
    }

    /// Add Alt modifier
    pub fn alt(mut self) -> Self {
        self.alt = true;
        self
    }

    /// Format for display
    pub fn to_string_display(&self) -> String {
        let mut parts = Vec::new();

        #[cfg(target_os = "macos")]
        {
            if self.ctrl {
                parts.push("⌃");
            }
            if self.alt {
                parts.push("⌥");
            }
            if self.shift {
                parts.push("⇧");
            }
            if self.meta {
                parts.push("⌘");
            }
        }

        #[cfg(not(target_os = "macos"))]
        {
            if self.ctrl {
                parts.push("Ctrl");
            }
            if self.alt {
                parts.push("Alt");
            }
            if self.shift {
                parts.push("Shift");
            }
            if self.meta {
                parts.push("Win");
            }
        }

        parts.push(&self.key);
        parts.join("+")
    }
}

/// Common DAW shortcuts
pub mod shortcuts {
    use super::KeyboardShortcut;

    pub fn play() -> KeyboardShortcut {
        KeyboardShortcut::key("Space")
    }
    pub fn stop() -> KeyboardShortcut {
        KeyboardShortcut::key("Space")
    }
    pub fn record() -> KeyboardShortcut {
        KeyboardShortcut::key("R")
    }
    pub fn loop_toggle() -> KeyboardShortcut {
        KeyboardShortcut::key("L")
    }
    pub fn undo() -> KeyboardShortcut {
        KeyboardShortcut::key("Z").ctrl()
    }
    pub fn redo() -> KeyboardShortcut {
        KeyboardShortcut::key("Z").ctrl().shift()
    }
    pub fn save() -> KeyboardShortcut {
        KeyboardShortcut::key("S").ctrl()
    }
    pub fn save_as() -> KeyboardShortcut {
        KeyboardShortcut::key("S").ctrl().shift()
    }
    pub fn cut() -> KeyboardShortcut {
        KeyboardShortcut::key("X").ctrl()
    }
    pub fn copy() -> KeyboardShortcut {
        KeyboardShortcut::key("C").ctrl()
    }
    pub fn paste() -> KeyboardShortcut {
        KeyboardShortcut::key("V").ctrl()
    }
    pub fn delete() -> KeyboardShortcut {
        KeyboardShortcut::key("Delete")
    }
    pub fn select_all() -> KeyboardShortcut {
        KeyboardShortcut::key("A").ctrl()
    }
    pub fn zoom_in() -> KeyboardShortcut {
        KeyboardShortcut::key("=").ctrl()
    }
    pub fn zoom_out() -> KeyboardShortcut {
        KeyboardShortcut::key("-").ctrl()
    }
    pub fn zoom_fit() -> KeyboardShortcut {
        KeyboardShortcut::key("0").ctrl()
    }
}

/// Layout container direction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LayoutDirection {
    Horizontal,
    Vertical,
}

impl Default for LayoutDirection {
    fn default() -> Self {
        Self::Horizontal
    }
}

/// Layout alignment
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LayoutAlign {
    Start,
    Center,
    End,
    Stretch,
    SpaceBetween,
    SpaceAround,
}

impl Default for LayoutAlign {
    fn default() -> Self {
        Self::Start
    }
}

/// Widget size hint
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum SizeHint {
    /// Fixed size
    Fixed(f32),
    /// Fill available space
    Fill,
    /// Fill with weight
    FillWeight(f32),
    /// Fit to content
    FitContent,
    /// Minimum size
    Min(f32),
    /// Maximum size
    Max(f32),
}

impl Default for SizeHint {
    fn default() -> Self {
        Self::FitContent
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_value_format() {
        assert_eq!(ValueFormat::Integer.format(3.7, ""), "4");
        assert_eq!(ValueFormat::Percent.format(0.5, ""), "50.0%");
        assert_eq!(ValueFormat::Decibels.format(-3.0, ""), "-3.0 dB");
        assert_eq!(ValueFormat::Frequency.format(1500.0, ""), "1.50 kHz");
    }

    #[test]
    fn test_knob_state() {
        let config = KnobConfig {
            min: 0.0,
            max: 100.0,
            default: 50.0,
            ..Default::default()
        };
        let mut state = KnobState::default();
        state.set_value(75.0, &config);

        assert!((state.normalized - 0.75).abs() < 0.001);
        assert!((state.value(&config) - 75.0).abs() < 0.001);
    }

    #[test]
    fn test_keyboard_shortcut() {
        let shortcut = KeyboardShortcut::key("S").ctrl();
        assert!(shortcut.ctrl);
        assert!(!shortcut.shift);
    }

    #[test]
    fn test_meter_state() {
        let config = MeterConfig::default();
        let mut state = MeterState::default();
        state.update(-12.0, 0.0, &config);

        assert!(state.normalized(&config) > 0.0);
        assert!(state.normalized(&config) < 1.0);
    }
}
