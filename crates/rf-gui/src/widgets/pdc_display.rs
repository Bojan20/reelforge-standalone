//! PDC (Plugin Delay Compensation) Display Widget
//!
//! Shows latency information like Cubase:
//! - Total system latency
//! - Per-track latency breakdown
//! - Constrain mode indicator
//! - Visual latency graph
//!
//! ## Visual Design
//! ```text
//! ┌───────────────────────────────────────────────────┐
//! │  ⏱ Plugin Delay Compensation                      │
//! ├───────────────────────────────────────────────────┤
//! │  Total Latency: 512 samples (10.67ms)             │
//! │  ┌──────────────────────────────────────────────┐ │
//! │  │▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│ │
//! │  └──────────────────────────────────────────────┘ │
//! │                                                   │
//! │  Track Latencies:                                 │
//! │  ├─ Track 1: 512 samples (Linear Phase EQ)       │
//! │  ├─ Track 2: 256 samples (Limiter)               │
//! │  └─ Track 3: 0 samples                           │
//! │                                                   │
//! │  [✓] PDC Enabled  [ ] Constrain (512 samples)    │
//! └───────────────────────────────────────────────────┘
//! ```

use iced::widget::{checkbox, column, container, row, scrollable, text};
use iced::{Color, Element, Length, Theme};

// ═══════════════════════════════════════════════════════════════════════════════
// PDC DISPLAY STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Track latency info for display
#[derive(Debug, Clone)]
pub struct TrackLatencyInfo {
    pub track_id: u32,
    pub track_name: String,
    pub plugin_latency: u32,
    pub compensation: u32,
    pub is_bypassed: bool,
    /// Plugin causing most latency
    pub latency_source: Option<String>,
}

/// PDC display state
#[derive(Debug, Clone)]
pub struct PdcDisplayState {
    /// Total system latency in samples
    pub total_latency_samples: u32,
    /// Sample rate for ms calculation
    pub sample_rate: u32,
    /// PDC enabled
    pub enabled: bool,
    /// Constrain mode enabled
    pub constrain_enabled: bool,
    /// Constrain threshold in samples
    pub constrain_threshold: u32,
    /// Per-track latency info
    pub tracks: Vec<TrackLatencyInfo>,
    /// Number of compensated nodes
    pub compensated_count: usize,
    /// Number of bypassed nodes
    pub bypassed_count: usize,
}

impl Default for PdcDisplayState {
    fn default() -> Self {
        Self {
            total_latency_samples: 0,
            sample_rate: 48000,
            enabled: true,
            constrain_enabled: false,
            constrain_threshold: 512,
            tracks: Vec::new(),
            compensated_count: 0,
            bypassed_count: 0,
        }
    }
}

impl PdcDisplayState {
    /// Get total latency in milliseconds
    pub fn total_latency_ms(&self) -> f64 {
        (self.total_latency_samples as f64 / self.sample_rate as f64) * 1000.0
    }

    /// Get constrain threshold in milliseconds
    pub fn constrain_threshold_ms(&self) -> f64 {
        (self.constrain_threshold as f64 / self.sample_rate as f64) * 1000.0
    }

    /// Get latency as percentage of max (for bar display)
    pub fn latency_percentage(&self, max_samples: u32) -> f32 {
        if max_samples == 0 {
            0.0
        } else {
            (self.total_latency_samples as f32 / max_samples as f32).min(1.0)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGES
// ═══════════════════════════════════════════════════════════════════════════════

/// PDC display messages
#[derive(Debug, Clone)]
pub enum PdcMessage {
    /// Toggle PDC enabled
    ToggleEnabled(bool),
    /// Toggle constrain mode
    ToggleConstrain(bool),
    /// Set constrain threshold
    SetConstrainThreshold(u32),
    /// Request state refresh
    Refresh,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDC DISPLAY WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Create PDC display view
pub fn pdc_display<'a>(state: &PdcDisplayState) -> Element<'a, PdcMessage> {
    // Header
    let header = container(
        text("Plugin Delay Compensation").size(14)
    )
    .padding(10)
    .width(Length::Fill)
    .style(|_theme: &Theme| container::Style {
        background: Some(Color::from_rgb(0.12, 0.12, 0.16).into()),
        ..Default::default()
    });

    // Total latency display
    let latency_text = if state.enabled {
        format!(
            "Total Latency: {} samples ({:.2}ms)",
            state.total_latency_samples,
            state.total_latency_ms()
        )
    } else {
        "PDC Disabled".to_string()
    };

    let latency_row = row![
        text(latency_text).size(12),
    ]
    .spacing(10);

    // Latency bar
    let bar_percentage = state.latency_percentage(2048); // Max ~2K samples for display
    let is_enabled = state.enabled;
    let bar_color = if is_enabled {
        if bar_percentage > 0.75 {
            Color::from_rgb(1.0, 0.4, 0.2) // Orange/red for high latency
        } else if bar_percentage > 0.5 {
            Color::from_rgb(1.0, 0.8, 0.2) // Yellow
        } else {
            Color::from_rgb(0.29, 0.62, 1.0) // Blue
        }
    } else {
        Color::from_rgb(0.3, 0.3, 0.35)
    };
    let bar_fill = (bar_percentage * 100.0) as u16;
    let bar_empty = 100u16.saturating_sub(bar_fill);

    let latency_bar = container(
        row![
            container(text(""))
                .width(Length::FillPortion(bar_fill.max(1)))
                .height(Length::Fixed(8.0))
                .style(move |_theme: &Theme| container::Style {
                    background: Some(bar_color.into()),
                    ..Default::default()
                }),
            container(text(""))
                .width(Length::FillPortion(bar_empty.max(1)))
                .height(Length::Fixed(8.0))
                .style(|_theme: &Theme| container::Style {
                    background: Some(Color::from_rgb(0.15, 0.15, 0.18).into()),
                    ..Default::default()
                }),
        ]
    )
    .width(Length::Fill)
    .style(|_theme: &Theme| container::Style {
        background: Some(Color::from_rgb(0.1, 0.1, 0.12).into()),
        border: iced::Border {
            radius: 4.0.into(),
            ..Default::default()
        },
        ..Default::default()
    });

    // Track latencies
    let sample_rate = state.sample_rate;
    let track_list: Element<'a, PdcMessage> = if state.tracks.is_empty() {
        text("No tracks").size(11).into()
    } else {
        let items: Vec<Element<'a, PdcMessage>> = state.tracks.iter().map(|track| {
            let status_color = if track.is_bypassed {
                Color::from_rgb(1.0, 0.4, 0.2) // Orange for bypassed
            } else if track.plugin_latency > 0 {
                Color::from_rgb(0.29, 0.62, 1.0) // Blue for latent
            } else {
                Color::from_rgb(0.5, 0.5, 0.55) // Gray for no latency
            };

            let latency_info = if track.plugin_latency > 0 {
                let ms = (track.plugin_latency as f64 / sample_rate as f64) * 1000.0;
                if let Some(source) = &track.latency_source {
                    format!("{} samples ({:.1}ms) - {}", track.plugin_latency, ms, source)
                } else {
                    format!("{} samples ({:.1}ms)", track.plugin_latency, ms)
                }
            } else {
                "0 samples".to_string()
            };

            let bypassed_text = if track.is_bypassed {
                " [BYPASSED]".to_string()
            } else {
                String::new()
            };

            let track_name = track.track_name.clone();

            row![
                text("├─").size(11).color(Color::from_rgb(0.4, 0.4, 0.45)),
                text(track_name).size(11).color(status_color),
                text(": ").size(11),
                text(latency_info).size(11).color(Color::from_rgb(0.6, 0.6, 0.65)),
                text(bypassed_text).size(11).color(Color::from_rgb(1.0, 0.4, 0.2)),
            ]
            .spacing(5)
            .into()
        }).collect();

        scrollable(
            column(items).spacing(4)
        )
        .height(Length::Fixed(120.0))
        .into()
    };

    // Statistics row
    let stats_row = row![
        text(format!("Compensated: {}", state.compensated_count)).size(10).color(Color::from_rgb(0.5, 0.5, 0.55)),
        text(format!("Bypassed: {}", state.bypassed_count)).size(10).color(
            if state.bypassed_count > 0 {
                Color::from_rgb(1.0, 0.4, 0.2)
            } else {
                Color::from_rgb(0.5, 0.5, 0.55)
            }
        ),
    ]
    .spacing(20);

    // Controls row
    let pdc_checkbox = checkbox("PDC Enabled", state.enabled)
        .on_toggle(PdcMessage::ToggleEnabled)
        .text_size(11);

    let constrain_text = format!(
        "Constrain ({} samples / {:.1}ms)",
        state.constrain_threshold,
        state.constrain_threshold_ms()
    );

    let constrain_checkbox = checkbox(constrain_text, state.constrain_enabled)
        .on_toggle(PdcMessage::ToggleConstrain)
        .text_size(11);

    let controls_row = row![
        pdc_checkbox,
        constrain_checkbox,
    ]
    .spacing(20);

    // Main content
    let content = column![
        header,
        container(
            column![
                latency_row,
                latency_bar,
                text("Track Latencies:").size(11),
                track_list,
                stats_row,
                controls_row,
            ]
            .spacing(10)
        )
        .padding(15)
    ]
    .spacing(0);

    container(content)
        .width(Length::Fixed(400.0))
        .style(|_theme: &Theme| container::Style {
            background: Some(Color::from_rgb(0.1, 0.1, 0.12).into()),
            border: iced::Border {
                color: Color::from_rgba(1.0, 1.0, 1.0, 0.1),
                width: 1.0,
                radius: 8.0.into(),
            },
            ..Default::default()
        })
        .into()
}

/// Compact PDC indicator for transport bar
pub fn pdc_indicator<'a>(state: &PdcDisplayState) -> Element<'a, PdcMessage> {
    let color = if !state.enabled {
        Color::from_rgb(0.4, 0.4, 0.45) // Gray when disabled
    } else if state.bypassed_count > 0 {
        Color::from_rgb(1.0, 0.6, 0.2) // Orange when bypassing
    } else if state.total_latency_samples > 1024 {
        Color::from_rgb(1.0, 0.8, 0.2) // Yellow for high latency
    } else {
        Color::from_rgb(0.29, 0.62, 1.0) // Blue normal
    };

    let label = if state.enabled {
        format!("PDC: {:.1}ms", state.total_latency_ms())
    } else {
        "PDC: OFF".to_string()
    };

    container(
        text(label).size(10).color(color)
    )
    .padding([4, 8])
    .style(move |_theme: &Theme| container::Style {
        background: Some(Color::from_rgb(0.12, 0.12, 0.15).into()),
        border: iced::Border {
            color: color.scale_alpha(0.3),
            width: 1.0,
            radius: 4.0.into(),
        },
        ..Default::default()
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
    fn test_latency_ms_calculation() {
        let state = PdcDisplayState {
            total_latency_samples: 480,
            sample_rate: 48000,
            ..Default::default()
        };

        assert!((state.total_latency_ms() - 10.0).abs() < 0.01);
    }

    #[test]
    fn test_latency_percentage() {
        let state = PdcDisplayState {
            total_latency_samples: 512,
            ..Default::default()
        };

        assert!((state.latency_percentage(1024) - 0.5).abs() < 0.01);
        assert!((state.latency_percentage(512) - 1.0).abs() < 0.01);
    }
}
