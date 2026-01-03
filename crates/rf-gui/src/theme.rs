//! ReelForge color theme and styling

use iced::Color;

/// Color palette for ReelForge
pub struct Palette;

impl Palette {
    // Backgrounds
    pub const BG_DEEPEST: Color = Color::from_rgb(0.039, 0.039, 0.047); // #0a0a0c
    pub const BG_DEEP: Color = Color::from_rgb(0.071, 0.071, 0.086);    // #121216
    pub const BG_MID: Color = Color::from_rgb(0.102, 0.102, 0.125);     // #1a1a20
    pub const BG_SURFACE: Color = Color::from_rgb(0.141, 0.141, 0.188); // #242430

    // Accents
    pub const ACCENT_BLUE: Color = Color::from_rgb(0.290, 0.620, 1.000);   // #4a9eff
    pub const ACCENT_ORANGE: Color = Color::from_rgb(1.000, 0.565, 0.251); // #ff9040
    pub const ACCENT_GREEN: Color = Color::from_rgb(0.251, 1.000, 0.565);  // #40ff90
    pub const ACCENT_RED: Color = Color::from_rgb(1.000, 0.251, 0.376);    // #ff4060
    pub const ACCENT_CYAN: Color = Color::from_rgb(0.251, 0.784, 1.000);   // #40c8ff

    // Text
    pub const TEXT_PRIMARY: Color = Color::WHITE;
    pub const TEXT_SECONDARY: Color = Color::from_rgb(0.690, 0.690, 0.753); // #b0b0c0
    pub const TEXT_DISABLED: Color = Color::from_rgb(0.376, 0.376, 0.502);  // #606080

    // Meter gradient colors
    pub const METER_CYAN: Color = Color::from_rgb(0.251, 0.784, 1.000);    // #40c8ff
    pub const METER_GREEN: Color = Color::from_rgb(0.251, 1.000, 0.565);   // #40ff90
    pub const METER_YELLOW: Color = Color::from_rgb(1.000, 1.000, 0.251);  // #ffff40
    pub const METER_ORANGE: Color = Color::from_rgb(1.000, 0.565, 0.251);  // #ff9040
    pub const METER_RED: Color = Color::from_rgb(1.000, 0.251, 0.251);     // #ff4040
}

/// Get meter color based on level (0.0 to 1.0)
pub fn meter_color(level: f32) -> Color {
    if level < 0.5 {
        // Cyan to green
        let t = level * 2.0;
        interpolate_color(Palette::METER_CYAN, Palette::METER_GREEN, t)
    } else if level < 0.75 {
        // Green to yellow
        let t = (level - 0.5) * 4.0;
        interpolate_color(Palette::METER_GREEN, Palette::METER_YELLOW, t)
    } else if level < 0.9 {
        // Yellow to orange
        let t = (level - 0.75) * 6.67;
        interpolate_color(Palette::METER_YELLOW, Palette::METER_ORANGE, t)
    } else {
        // Orange to red
        let t = (level - 0.9) * 10.0;
        interpolate_color(Palette::METER_ORANGE, Palette::METER_RED, t)
    }
}

fn interpolate_color(c1: Color, c2: Color, t: f32) -> Color {
    Color::from_rgb(
        c1.r + (c2.r - c1.r) * t,
        c1.g + (c2.g - c1.g) * t,
        c1.b + (c2.b - c1.b) * t,
    )
}

/// Standard sizes
pub struct Sizes;

impl Sizes {
    pub const TEXT_SMALL: f32 = 11.0;
    pub const TEXT_NORMAL: f32 = 13.0;
    pub const TEXT_HEADER: f32 = 16.0;

    pub const KNOB_SMALL: f32 = 32.0;
    pub const KNOB_MEDIUM: f32 = 48.0;
    pub const KNOB_LARGE: f32 = 64.0;

    pub const BUTTON_HEIGHT: f32 = 28.0;
    pub const BUTTON_PADDING: f32 = 12.0;

    pub const SPACING_SMALL: f32 = 4.0;
    pub const SPACING_NORMAL: f32 = 8.0;
    pub const SPACING_LARGE: f32 = 16.0;

    pub const BORDER_RADIUS: f32 = 4.0;
}

/// Animation durations in milliseconds
pub struct Durations;

impl Durations {
    pub const HOVER: u64 = 80;
    pub const TRANSITION: u64 = 200;
    pub const METER_ATTACK: u64 = 10;
    pub const METER_RELEASE: u64 = 150;
}
