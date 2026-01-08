//! Ultimate UI Theme System
//!
//! Professional DAW theming with:
//! - Pro audio dark theme (default)
//! - High contrast mode
//! - Color blindness support
//! - Custom accent colors
//! - GPU-optimized color formats

use serde::{Deserialize, Serialize};

/// RGBA color in linear space
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Color {
    pub const TRANSPARENT: Self = Self::new(0.0, 0.0, 0.0, 0.0);
    pub const BLACK: Self = Self::new(0.0, 0.0, 0.0, 1.0);
    pub const WHITE: Self = Self::new(1.0, 1.0, 1.0, 1.0);

    #[inline]
    pub const fn new(r: f32, g: f32, b: f32, a: f32) -> Self {
        Self { r, g, b, a }
    }

    /// Create color from hex string (e.g., "#ff9040" or "ff9040")
    pub fn from_hex(hex: &str) -> Option<Self> {
        let hex = hex.trim_start_matches('#');
        if hex.len() != 6 && hex.len() != 8 {
            return None;
        }

        let r = u8::from_str_radix(&hex[0..2], 16).ok()? as f32 / 255.0;
        let g = u8::from_str_radix(&hex[2..4], 16).ok()? as f32 / 255.0;
        let b = u8::from_str_radix(&hex[4..6], 16).ok()? as f32 / 255.0;
        let a = if hex.len() == 8 {
            u8::from_str_radix(&hex[6..8], 16).ok()? as f32 / 255.0
        } else {
            1.0
        };

        Some(Self::new(r, g, b, a))
    }

    /// Create from sRGB hex value
    pub fn from_srgb_hex(hex: u32) -> Self {
        let r = ((hex >> 16) & 0xFF) as f32 / 255.0;
        let g = ((hex >> 8) & 0xFF) as f32 / 255.0;
        let b = (hex & 0xFF) as f32 / 255.0;
        Self::new(r, g, b, 1.0)
    }

    /// Convert to array for GPU
    #[inline]
    pub fn to_array(self) -> [f32; 4] {
        [self.r, self.g, self.b, self.a]
    }

    /// Blend with another color
    pub fn blend(self, other: Self, t: f32) -> Self {
        Self::new(
            self.r + (other.r - self.r) * t,
            self.g + (other.g - self.g) * t,
            self.b + (other.b - self.b) * t,
            self.a + (other.a - self.a) * t,
        )
    }

    /// Lighten the color
    pub fn lighten(self, amount: f32) -> Self {
        Self::new(
            (self.r + amount).min(1.0),
            (self.g + amount).min(1.0),
            (self.b + amount).min(1.0),
            self.a,
        )
    }

    /// Darken the color
    pub fn darken(self, amount: f32) -> Self {
        Self::new(
            (self.r - amount).max(0.0),
            (self.g - amount).max(0.0),
            (self.b - amount).max(0.0),
            self.a,
        )
    }

    /// Set alpha
    pub fn with_alpha(self, a: f32) -> Self {
        Self::new(self.r, self.g, self.b, a)
    }
}

impl Default for Color {
    fn default() -> Self {
        Self::BLACK
    }
}

/// Theme variant
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThemeVariant {
    /// Pro audio dark (default)
    ProDark,
    /// Higher contrast dark
    HighContrast,
    /// Light theme (rare in DAWs)
    Light,
    /// Custom
    Custom,
}

impl Default for ThemeVariant {
    fn default() -> Self {
        Self::ProDark
    }
}

/// Color blindness mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ColorBlindMode {
    /// Normal vision
    None,
    /// Red-green (most common)
    Deuteranopia,
    /// Red-green
    Protanopia,
    /// Blue-yellow
    Tritanopia,
}

impl Default for ColorBlindMode {
    fn default() -> Self {
        Self::None
    }
}

/// Complete theme definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Theme {
    /// Theme variant
    pub variant: ThemeVariant,
    /// Color blind mode
    pub color_blind_mode: ColorBlindMode,

    // Background colors (darkest to lightest)
    pub bg_deepest: Color,
    pub bg_deep: Color,
    pub bg_mid: Color,
    pub bg_surface: Color,
    pub bg_elevated: Color,

    // Text colors
    pub text_primary: Color,
    pub text_secondary: Color,
    pub text_tertiary: Color,
    pub text_disabled: Color,

    // Accent colors
    pub accent_primary: Color,   // Focus, selection
    pub accent_secondary: Color, // Active elements
    pub accent_tertiary: Color,  // Highlights

    // Semantic colors
    pub success: Color, // Green - OK, positive
    pub warning: Color, // Yellow/Orange - caution
    pub error: Color,   // Red - clip, error
    pub info: Color,    // Blue - information

    // Metering colors
    pub meter_low: Color,  // Green
    pub meter_mid: Color,  // Yellow
    pub meter_high: Color, // Orange
    pub meter_clip: Color, // Red

    // EQ/Spectrum colors
    pub spectrum_bg: Color,
    pub spectrum_line: Color,
    pub spectrum_fill: Color,
    pub eq_boost: Color,
    pub eq_cut: Color,
    pub eq_neutral: Color,

    // Track colors (8 default track colors)
    pub track_colors: [Color; 8],

    // Waveform colors
    pub waveform_pos: Color,
    pub waveform_neg: Color,
    pub waveform_rms: Color,

    // Selection/focus
    pub selection: Color,
    pub focus_ring: Color,
    pub hover: Color,

    // Borders
    pub border_subtle: Color,
    pub border_default: Color,
    pub border_strong: Color,

    // Shadows
    pub shadow: Color,
    pub glow: Color,

    // Special
    pub grid_major: Color,
    pub grid_minor: Color,
    pub playhead: Color,
    pub loop_region: Color,
}

impl Default for Theme {
    fn default() -> Self {
        Self::pro_dark()
    }
}

impl Theme {
    /// Pro audio dark theme (default)
    pub fn pro_dark() -> Self {
        Self {
            variant: ThemeVariant::ProDark,
            color_blind_mode: ColorBlindMode::None,

            // Backgrounds
            bg_deepest: Color::from_srgb_hex(0x0a0a0c),
            bg_deep: Color::from_srgb_hex(0x121216),
            bg_mid: Color::from_srgb_hex(0x1a1a20),
            bg_surface: Color::from_srgb_hex(0x242430),
            bg_elevated: Color::from_srgb_hex(0x2e2e3a),

            // Text
            text_primary: Color::from_srgb_hex(0xf0f0f5),
            text_secondary: Color::from_srgb_hex(0xa0a0b0),
            text_tertiary: Color::from_srgb_hex(0x707080),
            text_disabled: Color::from_srgb_hex(0x505060),

            // Accents
            accent_primary: Color::from_srgb_hex(0x4a9eff), // Blue
            accent_secondary: Color::from_srgb_hex(0xff9040), // Orange
            accent_tertiary: Color::from_srgb_hex(0x40c8ff), // Cyan

            // Semantic
            success: Color::from_srgb_hex(0x40ff90), // Green
            warning: Color::from_srgb_hex(0xffff40), // Yellow
            error: Color::from_srgb_hex(0xff4060),   // Red
            info: Color::from_srgb_hex(0x4a9eff),    // Blue

            // Metering
            meter_low: Color::from_srgb_hex(0x40c8ff),
            meter_mid: Color::from_srgb_hex(0x40ff90),
            meter_high: Color::from_srgb_hex(0xff9040),
            meter_clip: Color::from_srgb_hex(0xff4040),

            // EQ/Spectrum
            spectrum_bg: Color::from_srgb_hex(0x0a0a0c).with_alpha(0.8),
            spectrum_line: Color::from_srgb_hex(0x40c8ff),
            spectrum_fill: Color::from_srgb_hex(0x40c8ff).with_alpha(0.2),
            eq_boost: Color::from_srgb_hex(0xff9040),
            eq_cut: Color::from_srgb_hex(0x40c8ff),
            eq_neutral: Color::from_srgb_hex(0x707080),

            // Track colors
            track_colors: [
                Color::from_srgb_hex(0x4a9eff), // Blue
                Color::from_srgb_hex(0xff9040), // Orange
                Color::from_srgb_hex(0x40ff90), // Green
                Color::from_srgb_hex(0xff4060), // Red
                Color::from_srgb_hex(0xffff40), // Yellow
                Color::from_srgb_hex(0x40c8ff), // Cyan
                Color::from_srgb_hex(0xff40ff), // Magenta
                Color::from_srgb_hex(0x8040ff), // Purple
            ],

            // Waveform
            waveform_pos: Color::from_srgb_hex(0x40c8ff),
            waveform_neg: Color::from_srgb_hex(0x40c8ff),
            waveform_rms: Color::from_srgb_hex(0x4a9eff),

            // Selection
            selection: Color::from_srgb_hex(0x4a9eff).with_alpha(0.3),
            focus_ring: Color::from_srgb_hex(0x4a9eff),
            hover: Color::from_srgb_hex(0xffffff).with_alpha(0.05),

            // Borders
            border_subtle: Color::from_srgb_hex(0x303040),
            border_default: Color::from_srgb_hex(0x404050),
            border_strong: Color::from_srgb_hex(0x606070),

            // Shadows
            shadow: Color::from_srgb_hex(0x000000).with_alpha(0.5),
            glow: Color::from_srgb_hex(0x4a9eff).with_alpha(0.3),

            // Grid
            grid_major: Color::from_srgb_hex(0x404050),
            grid_minor: Color::from_srgb_hex(0x282830),
            playhead: Color::from_srgb_hex(0xff9040),
            loop_region: Color::from_srgb_hex(0x40c8ff).with_alpha(0.15),
        }
    }

    /// High contrast theme
    pub fn high_contrast() -> Self {
        let mut theme = Self::pro_dark();
        theme.variant = ThemeVariant::HighContrast;

        // Increase text contrast
        theme.text_primary = Color::WHITE;
        theme.text_secondary = Color::from_srgb_hex(0xcccccc);

        // Increase background contrast
        theme.bg_deepest = Color::BLACK;
        theme.bg_surface = Color::from_srgb_hex(0x303040);

        // Stronger borders
        theme.border_default = Color::from_srgb_hex(0x606070);
        theme.border_strong = Color::from_srgb_hex(0x808090);

        theme
    }

    /// Apply color blindness correction
    pub fn apply_color_blind_mode(&mut self, mode: ColorBlindMode) {
        self.color_blind_mode = mode;

        match mode {
            ColorBlindMode::None => {}
            ColorBlindMode::Deuteranopia | ColorBlindMode::Protanopia => {
                // Use blue/yellow instead of red/green
                self.success = Color::from_srgb_hex(0x40c8ff); // Blue instead of green
                self.error = Color::from_srgb_hex(0xffaa00); // Orange instead of red
                self.meter_low = Color::from_srgb_hex(0x4080ff);
                self.meter_mid = Color::from_srgb_hex(0x40c0ff);
                self.meter_high = Color::from_srgb_hex(0xffaa00);
            }
            ColorBlindMode::Tritanopia => {
                // Use red/cyan instead of blue/yellow
                self.warning = Color::from_srgb_hex(0xff8080);
                self.info = Color::from_srgb_hex(0x80ffff);
            }
        }
    }

    /// Get color for meter value (0.0 to 1.0+)
    pub fn meter_color(&self, value: f32) -> Color {
        if value >= 1.0 {
            self.meter_clip
        } else if value >= 0.7 {
            self.meter_high
        } else if value >= 0.4 {
            self.meter_mid
        } else {
            self.meter_low
        }
    }

    /// Get track color by index
    pub fn track_color(&self, index: usize) -> Color {
        self.track_colors[index % self.track_colors.len()]
    }
}

/// Font configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FontConfig {
    /// Primary UI font family
    pub family: String,
    /// Monospace font family
    pub mono_family: String,
    /// Base font size
    pub base_size: f32,
    /// Scale factor for different sizes
    pub scale: FontScale,
}

impl Default for FontConfig {
    fn default() -> Self {
        Self {
            family: String::from("Inter"),
            mono_family: String::from("JetBrains Mono"),
            base_size: 13.0,
            scale: FontScale::default(),
        }
    }
}

/// Font size scale
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FontScale {
    pub tiny: f32,   // labels
    pub small: f32,  // secondary text
    pub normal: f32, // body text
    pub medium: f32, // headings
    pub large: f32,  // titles
    pub xlarge: f32, // big displays
}

impl Default for FontScale {
    fn default() -> Self {
        Self {
            tiny: 0.75,
            small: 0.875,
            normal: 1.0,
            medium: 1.125,
            large: 1.5,
            xlarge: 2.0,
        }
    }
}

/// Spacing system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Spacing {
    /// Base unit (usually 4px)
    pub unit: f32,
    /// Extra small (0.5 * unit)
    pub xs: f32,
    /// Small (1 * unit)
    pub sm: f32,
    /// Medium (2 * unit)
    pub md: f32,
    /// Large (4 * unit)
    pub lg: f32,
    /// Extra large (8 * unit)
    pub xl: f32,
}

impl Default for Spacing {
    fn default() -> Self {
        let unit = 4.0;
        Self {
            unit,
            xs: unit * 0.5,
            sm: unit,
            md: unit * 2.0,
            lg: unit * 4.0,
            xl: unit * 8.0,
        }
    }
}

impl Spacing {
    /// Get spacing by multiplier
    #[inline]
    pub fn get(&self, multiplier: f32) -> f32 {
        self.unit * multiplier
    }
}

/// Border radius configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BorderRadius {
    pub none: f32,
    pub sm: f32,
    pub md: f32,
    pub lg: f32,
    pub full: f32,
}

impl Default for BorderRadius {
    fn default() -> Self {
        Self {
            none: 0.0,
            sm: 2.0,
            md: 4.0,
            lg: 8.0,
            full: 9999.0,
        }
    }
}

/// Animation timing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimationTiming {
    /// Fast (100ms)
    pub fast_ms: f32,
    /// Normal (200ms)
    pub normal_ms: f32,
    /// Slow (400ms)
    pub slow_ms: f32,
    /// Easing function
    pub easing: EasingFunction,
}

impl Default for AnimationTiming {
    fn default() -> Self {
        Self {
            fast_ms: 100.0,
            normal_ms: 200.0,
            slow_ms: 400.0,
            easing: EasingFunction::EaseOut,
        }
    }
}

/// Easing function type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EasingFunction {
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
}

impl Default for EasingFunction {
    fn default() -> Self {
        Self::EaseOut
    }
}

impl EasingFunction {
    /// Apply easing to a 0-1 value
    pub fn apply(self, t: f32) -> f32 {
        match self {
            Self::Linear => t,
            Self::EaseIn => t * t,
            Self::EaseOut => 1.0 - (1.0 - t) * (1.0 - t),
            Self::EaseInOut => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(2) / 2.0
                }
            }
        }
    }
}

/// Complete design system
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DesignSystem {
    pub theme: Theme,
    pub fonts: FontConfig,
    pub spacing: Spacing,
    pub radius: BorderRadius,
    pub animation: AnimationTiming,
}

impl DesignSystem {
    /// Create pro audio design system
    pub fn pro_audio() -> Self {
        Self {
            theme: Theme::pro_dark(),
            fonts: FontConfig::default(),
            spacing: Spacing::default(),
            radius: BorderRadius::default(),
            animation: AnimationTiming::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_color_from_hex() {
        let color = Color::from_hex("#ff9040").unwrap();
        assert!((color.r - 1.0).abs() < 0.01);
        assert!((color.g - 0.56).abs() < 0.02);
    }

    #[test]
    fn test_color_blend() {
        let a = Color::BLACK;
        let b = Color::WHITE;
        let mid = a.blend(b, 0.5);
        assert!((mid.r - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_theme_default() {
        let theme = Theme::default();
        assert_eq!(theme.variant, ThemeVariant::ProDark);
    }

    #[test]
    fn test_meter_color() {
        let theme = Theme::pro_dark();
        let low = theme.meter_color(0.2);
        let clip = theme.meter_color(1.0);
        assert_ne!(low.to_array(), clip.to_array());
    }

    #[test]
    fn test_easing() {
        assert_eq!(EasingFunction::Linear.apply(0.5), 0.5);
        assert!(EasingFunction::EaseOut.apply(0.5) > 0.5);
    }

    #[test]
    fn test_design_system() {
        let ds = DesignSystem::pro_audio();
        assert_eq!(ds.spacing.md, 8.0);
    }
}
