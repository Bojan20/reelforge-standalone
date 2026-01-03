//! Crossfade Editor Widget
//!
//! Professional crossfade editing like Cubase:
//! - Visual crossfade curve display
//! - Curve type selection
//! - Length adjustment
//! - Real-time preview
//! - Equal power/linear curves
//!
//! ## Visual Design
//! ```text
//! ┌─────────────────────────────────────────┐
//! │  ◀ Crossfade Editor ▶                   │
//! ├─────────────────────────────────────────┤
//! │     ╲                    ╱              │
//! │      ╲                  ╱               │
//! │       ╲      ╳        ╱                │
//! │        ╲            ╱                   │
//! │         ╲──────────╱                    │
//! ├─────────────────────────────────────────┤
//! │ [Linear] [Equal Power] [S-Curve]        │
//! │ Length: [====●=======] 50ms             │
//! │ Asymmetry: [====●=====] 0%              │
//! └─────────────────────────────────────────┘
//! ```

use iced::widget::{canvas, column, container, row, slider, text, button};
use iced::{
    Color, Element, Length, Point, Rectangle, Size, Theme,
    mouse, Renderer,
};
use iced::widget::canvas::{Cache, Frame, Geometry, Path, Stroke, Program};

// ═══════════════════════════════════════════════════════════════════════════════
// CROSSFADE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CrossfadeCurve {
    Linear,
    #[default]
    EqualPower,
    SCurve,
    Exponential,
    Logarithmic,
}

impl CrossfadeCurve {
    /// Calculate fade-out gain at position (0.0 to 1.0)
    pub fn fade_out(&self, t: f64) -> f64 {
        match self {
            CrossfadeCurve::Linear => 1.0 - t,
            CrossfadeCurve::EqualPower => {
                ((1.0 - t) * std::f64::consts::FRAC_PI_2).sin()
            }
            CrossfadeCurve::SCurve => {
                (1.0 + (t * std::f64::consts::PI).cos()) * 0.5
            }
            CrossfadeCurve::Exponential => {
                (1.0 - t).powf(2.0)
            }
            CrossfadeCurve::Logarithmic => {
                1.0 - (1.0 + t * 9.0).log10()
            }
        }
    }

    /// Calculate fade-in gain at position (0.0 to 1.0)
    pub fn fade_in(&self, t: f64) -> f64 {
        match self {
            CrossfadeCurve::Linear => t,
            CrossfadeCurve::EqualPower => {
                (t * std::f64::consts::FRAC_PI_2).sin()
            }
            CrossfadeCurve::SCurve => {
                (1.0 - (t * std::f64::consts::PI).cos()) * 0.5
            }
            CrossfadeCurve::Exponential => {
                t.powf(2.0)
            }
            CrossfadeCurve::Logarithmic => {
                (1.0 + t * 9.0).log10()
            }
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            CrossfadeCurve::Linear => "Linear",
            CrossfadeCurve::EqualPower => "Equal Power",
            CrossfadeCurve::SCurve => "S-Curve",
            CrossfadeCurve::Exponential => "Exponential",
            CrossfadeCurve::Logarithmic => "Logarithmic",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CROSSFADE STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade editor state
#[derive(Debug, Clone)]
pub struct CrossfadeState {
    /// Curve type
    pub curve: CrossfadeCurve,
    /// Length in milliseconds
    pub length_ms: f64,
    /// Asymmetry (-1.0 to 1.0)
    pub asymmetry: f64,
    /// Is previewing
    pub previewing: bool,
}

impl Default for CrossfadeState {
    fn default() -> Self {
        Self {
            curve: CrossfadeCurve::EqualPower,
            length_ms: 50.0,
            asymmetry: 0.0,
            previewing: false,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGES
// ═══════════════════════════════════════════════════════════════════════════════

/// Crossfade editor messages
#[derive(Debug, Clone)]
pub enum CrossfadeMessage {
    CurveChanged(CrossfadeCurve),
    LengthChanged(f64),
    AsymmetryChanged(f64),
    Preview,
    Apply,
    Cancel,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CURVE CANVAS
// ═══════════════════════════════════════════════════════════════════════════════

/// Canvas for drawing crossfade curves
pub struct CrossfadeCurveCanvas {
    state: CrossfadeState,
    cache: Cache,
}

impl CrossfadeCurveCanvas {
    pub fn new(state: CrossfadeState) -> Self {
        Self {
            state,
            cache: Cache::default(),
        }
    }

    pub fn update_state(&mut self, state: CrossfadeState) {
        if self.state.curve != state.curve || self.state.asymmetry != state.asymmetry {
            self.cache.clear();
        }
        self.state = state;
    }
}

impl<Message> Program<Message> for CrossfadeCurveCanvas {
    type State = ();

    fn draw(
        &self,
        _state: &Self::State,
        renderer: &Renderer,
        _theme: &Theme,
        bounds: Rectangle,
        _cursor: mouse::Cursor,
    ) -> Vec<Geometry> {
        let geometry = self.cache.draw(renderer, bounds.size(), |frame| {
            let width = bounds.width;
            let height = bounds.height;

            // Background
            frame.fill_rectangle(
                Point::ORIGIN,
                Size::new(width, height),
                Color::from_rgb(0.07, 0.07, 0.09),
            );

            // Grid lines
            let grid_color = Color::from_rgba(1.0, 1.0, 1.0, 0.1);
            for i in 1..4 {
                let x = width * i as f32 / 4.0;
                let path = Path::line(
                    Point::new(x, 0.0),
                    Point::new(x, height),
                );
                frame.stroke(&path, Stroke::default().with_color(grid_color).with_width(1.0));
            }
            for i in 1..4 {
                let y = height * i as f32 / 4.0;
                let path = Path::line(
                    Point::new(0.0, y),
                    Point::new(width, y),
                );
                frame.stroke(&path, Stroke::default().with_color(grid_color).with_width(1.0));
            }

            // Draw fade-out curve (left event, going from top-left to bottom-right)
            let fade_out_color = Color::from_rgb(0.29, 0.62, 1.0); // Blue
            let mut fade_out_path = iced::widget::canvas::path::Builder::new();
            fade_out_path.move_to(Point::new(0.0, 0.0));
            for i in 0..=100 {
                let t = i as f64 / 100.0;
                let gain = self.state.curve.fade_out(t) as f32;
                let x = t as f32 * width;
                let y = (1.0 - gain) * height;
                fade_out_path.line_to(Point::new(x, y));
            }
            frame.stroke(
                &fade_out_path.build(),
                Stroke::default()
                    .with_color(fade_out_color)
                    .with_width(2.5),
            );

            // Draw fade-in curve (right event, going from bottom-left to top-right)
            let fade_in_color = Color::from_rgb(1.0, 0.56, 0.25); // Orange
            let mut fade_in_path = iced::widget::canvas::path::Builder::new();
            fade_in_path.move_to(Point::new(0.0, height));
            for i in 0..=100 {
                let t = i as f64 / 100.0;
                let gain = self.state.curve.fade_in(t) as f32;
                let x = t as f32 * width;
                let y = (1.0 - gain) * height;
                fade_in_path.line_to(Point::new(x, y));
            }
            frame.stroke(
                &fade_in_path.build(),
                Stroke::default()
                    .with_color(fade_in_color)
                    .with_width(2.5),
            );

            // Crossover point
            let crossover_x = width / 2.0;
            let crossover_y = height / 2.0;
            let crossover_path = Path::circle(Point::new(crossover_x, crossover_y), 4.0);
            frame.fill(&crossover_path, Color::WHITE);

            // Border
            frame.stroke(
                &Path::rectangle(Point::ORIGIN, Size::new(width, height)),
                Stroke::default()
                    .with_color(Color::from_rgba(1.0, 1.0, 1.0, 0.2))
                    .with_width(1.0),
            );
        });

        vec![geometry]
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CROSSFADE EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Create crossfade editor view
pub fn crossfade_editor<'a>(
    state: &CrossfadeState,
) -> Element<'a, CrossfadeMessage> {
    let header = container(
        text("Crossfade Editor")
            .size(14)
    )
    .padding(10)
    .style(|_theme: &Theme| container::Style {
        background: Some(Color::from_rgb(0.12, 0.12, 0.16).into()),
        ..Default::default()
    });

    // Curve canvas
    let curve_canvas = canvas(CrossfadeCurveCanvas::new(state.clone()))
        .width(Length::Fill)
        .height(Length::Fixed(150.0));

    // Curve type buttons
    let curve_buttons = row![
        curve_button("Linear", CrossfadeCurve::Linear, state.curve),
        curve_button("Equal Power", CrossfadeCurve::EqualPower, state.curve),
        curve_button("S-Curve", CrossfadeCurve::SCurve, state.curve),
    ]
    .spacing(5);

    // Length slider
    let length_row = row![
        text("Length:").size(12),
        slider(5.0..=500.0, state.length_ms, CrossfadeMessage::LengthChanged)
            .width(Length::Fixed(150.0)),
        text(format!("{:.0}ms", state.length_ms)).size(12),
    ]
    .spacing(10)
    .align_y(iced::Alignment::Center);

    // Asymmetry slider
    let asymmetry_row = row![
        text("Asymmetry:").size(12),
        slider(-1.0..=1.0, state.asymmetry, CrossfadeMessage::AsymmetryChanged)
            .width(Length::Fixed(150.0)),
        text(format!("{:.0}%", state.asymmetry * 100.0)).size(12),
    ]
    .spacing(10)
    .align_y(iced::Alignment::Center);

    // Action buttons
    let action_buttons = row![
        button(text("Preview").size(12))
            .on_press(CrossfadeMessage::Preview)
            .padding([5, 15]),
        button(text("Apply").size(12))
            .on_press(CrossfadeMessage::Apply)
            .padding([5, 15]),
        button(text("Cancel").size(12))
            .on_press(CrossfadeMessage::Cancel)
            .padding([5, 15]),
    ]
    .spacing(10);

    let content = column![
        header,
        container(curve_canvas).padding(10),
        container(curve_buttons).padding(10),
        container(length_row).padding([5, 10]),
        container(asymmetry_row).padding([5, 10]),
        container(action_buttons).padding(10),
    ]
    .spacing(5);

    container(content)
        .width(Length::Fixed(350.0))
        .style(|_theme: &Theme| container::Style {
            background: Some(Color::from_rgb(0.1, 0.1, 0.12).into()),
            border: iced::Border {
                color: Color::from_rgba(1.0, 1.0, 1.0, 0.15),
                width: 1.0,
                radius: 8.0.into(),
            },
            ..Default::default()
        })
        .into()
}

fn curve_button<'a>(
    label: &'a str,
    curve: CrossfadeCurve,
    current: CrossfadeCurve,
) -> Element<'a, CrossfadeMessage> {
    let is_selected = curve == current;

    button(text(label).size(11))
        .on_press(CrossfadeMessage::CurveChanged(curve))
        .padding([4, 10])
        .style(move |_theme: &Theme, status| {
            let background = if is_selected {
                Color::from_rgb(0.29, 0.62, 1.0)
            } else {
                match status {
                    button::Status::Hovered => Color::from_rgb(0.25, 0.25, 0.3),
                    _ => Color::from_rgb(0.18, 0.18, 0.22),
                }
            };

            button::Style {
                background: Some(background.into()),
                text_color: Color::WHITE,
                border: iced::Border {
                    radius: 4.0.into(),
                    ..Default::default()
                },
                ..Default::default()
            }
        })
        .into()
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_crossfade_curves() {
        // Linear: should be 0.5 at midpoint
        assert!((CrossfadeCurve::Linear.fade_in(0.5) - 0.5).abs() < 0.001);
        assert!((CrossfadeCurve::Linear.fade_out(0.5) - 0.5).abs() < 0.001);

        // Equal power: sum of squares should be ~1.0 (constant power)
        for i in 0..=10 {
            let t = i as f64 / 10.0;
            let in_gain = CrossfadeCurve::EqualPower.fade_in(t);
            let out_gain = CrossfadeCurve::EqualPower.fade_out(t);
            let power = in_gain * in_gain + out_gain * out_gain;
            assert!((power - 1.0).abs() < 0.01, "Power at t={}: {}", t, power);
        }
    }

    #[test]
    fn test_crossfade_endpoints() {
        for curve in [
            CrossfadeCurve::Linear,
            CrossfadeCurve::EqualPower,
            CrossfadeCurve::SCurve,
        ] {
            // Fade in: 0 at start, 1 at end
            assert!((curve.fade_in(0.0) - 0.0).abs() < 0.01);
            assert!((curve.fade_in(1.0) - 1.0).abs() < 0.01);

            // Fade out: 1 at start, 0 at end
            assert!((curve.fade_out(0.0) - 1.0).abs() < 0.01);
            assert!((curve.fade_out(1.0) - 0.0).abs() < 0.01);
        }
    }
}
