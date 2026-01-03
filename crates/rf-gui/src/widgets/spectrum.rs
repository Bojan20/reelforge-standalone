//! Spectrum Analyzer Widget
//!
//! Real-time frequency spectrum display with:
//! - Log-frequency scale (20Hz - 20kHz)
//! - Peak hold
//! - Configurable dB range
//! - Gradient fill

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::{Element, Length, Rectangle, Size};

use crate::theme::Palette;

/// Spectrum analyzer widget
pub struct SpectrumAnalyzer<'a> {
    /// Magnitude data (linear 0-1, indexed by frequency bin)
    magnitudes: &'a [f32],
    /// Peak hold data (optional)
    peaks: Option<&'a [f32]>,
    width: f32,
    height: f32,
    min_db: f32,
    max_db: f32,
    /// Show peak hold line
    show_peaks: bool,
    /// Frequency range
    min_freq: f32,
    max_freq: f32,
    /// Sample rate (for frequency calculation)
    sample_rate: f32,
}

impl<'a> SpectrumAnalyzer<'a> {
    pub fn new(magnitudes: &'a [f32]) -> Self {
        Self {
            magnitudes,
            peaks: None,
            width: 800.0,
            height: 200.0,
            min_db: -90.0,
            max_db: 0.0,
            show_peaks: true,
            min_freq: 20.0,
            max_freq: 20000.0,
            sample_rate: 48000.0,
        }
    }

    pub fn peaks(mut self, peaks: &'a [f32]) -> Self {
        self.peaks = Some(peaks);
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn db_range(mut self, min: f32, max: f32) -> Self {
        self.min_db = min;
        self.max_db = max;
        self
    }

    pub fn frequency_range(mut self, min: f32, max: f32) -> Self {
        self.min_freq = min;
        self.max_freq = max;
        self
    }

    pub fn sample_rate(mut self, rate: f32) -> Self {
        self.sample_rate = rate;
        self
    }

    pub fn show_peaks(mut self, show: bool) -> Self {
        self.show_peaks = show;
        self
    }

    // Convert linear magnitude to dB
    fn linear_to_db(linear: f32) -> f32 {
        if linear > 0.0 {
            20.0 * linear.log10()
        } else {
            -120.0
        }
    }

    // Convert dB to y position
    fn db_to_y(&self, db: f32, bounds: &Rectangle) -> f32 {
        let db_range = self.max_db - self.min_db;
        let t = ((db - self.min_db) / db_range).clamp(0.0, 1.0);
        bounds.y + (1.0 - t) * bounds.height
    }

    // Convert frequency to x position (log scale)
    fn freq_to_x(&self, freq: f32, bounds: &Rectangle) -> f32 {
        let log_min = self.min_freq.ln();
        let log_max = self.max_freq.ln();
        let t = (freq.ln() - log_min) / (log_max - log_min);
        bounds.x + t.clamp(0.0, 1.0) * bounds.width
    }

    // Convert bin index to frequency
    fn bin_to_freq(&self, bin: usize, num_bins: usize) -> f32 {
        (bin as f32 / num_bins as f32) * (self.sample_rate / 2.0)
    }

    // Get color for a given dB level (gradient from cyan to orange to red)
    fn level_color(&self, db: f32) -> iced::Color {
        let t = ((db - self.min_db) / (self.max_db - self.min_db)).clamp(0.0, 1.0);

        if t < 0.6 {
            // Cyan to green
            let local_t = t / 0.6;
            iced::Color::from_rgb(
                0.25 + local_t * 0.0,
                0.78 * (1.0 - local_t) + 1.0 * local_t,
                1.0 * (1.0 - local_t) + 0.56 * local_t,
            )
        } else if t < 0.85 {
            // Green to yellow/orange
            let local_t = (t - 0.6) / 0.25;
            iced::Color::from_rgb(
                0.25 + local_t * 0.75,
                1.0 - local_t * 0.44,
                0.56 * (1.0 - local_t) + 0.25 * local_t,
            )
        } else {
            // Orange to red
            let local_t = (t - 0.85) / 0.15;
            iced::Color::from_rgb(
                1.0,
                0.56 * (1.0 - local_t) + 0.25 * local_t,
                0.25 * (1.0 - local_t),
            )
        }
    }
}

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for SpectrumAnalyzer<'a>
where
    Renderer: renderer::Renderer,
{
    fn size(&self) -> Size<Length> {
        Size::new(Length::Fixed(self.width), Length::Fixed(self.height))
    }

    fn layout(
        &self,
        _tree: &mut widget::Tree,
        _renderer: &Renderer,
        _limits: &layout::Limits,
    ) -> layout::Node {
        layout::Node::new(Size::new(self.width, self.height))
    }

    fn draw(
        &self,
        _tree: &widget::Tree,
        renderer: &mut Renderer,
        _theme: &Theme,
        _style: &renderer::Style,
        layout: Layout<'_>,
        _cursor: iced::mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let bounds = layout.bounds();

        // Background
        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 4.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Draw grid
        self.draw_grid(renderer, &bounds);

        // Draw spectrum bars
        if !self.magnitudes.is_empty() {
            self.draw_spectrum(renderer, &bounds);
        }

        // Draw peak hold
        if self.show_peaks {
            if let Some(peaks) = self.peaks {
                self.draw_peaks(renderer, &bounds, peaks);
            }
        }
    }
}

impl<'a> SpectrumAnalyzer<'a> {
    fn draw_grid<Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle)
    where
        Renderer: renderer::Renderer,
    {
        // Horizontal lines (dB)
        let db_lines: [f32; 7] = [-80.0, -60.0, -40.0, -20.0, -10.0, -6.0, 0.0];
        for &db in &db_lines {
            if db >= self.min_db && db <= self.max_db {
                let y = self.db_to_y(db, bounds);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: bounds.x,
                            y: y - 0.5,
                            width: bounds.width,
                            height: 1.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    if db == 0.0 || db == -6.0 {
                        Palette::BG_SURFACE
                    } else {
                        Palette::BG_MID
                    },
                );
            }
        }

        // Vertical lines (frequency)
        let freq_lines: [f32; 10] = [30.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];
        for &freq in &freq_lines {
            if freq >= self.min_freq && freq <= self.max_freq {
                let x = self.freq_to_x(freq, bounds);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: x - 0.5,
                            y: bounds.y,
                            width: 1.0,
                            height: bounds.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    Palette::BG_MID,
                );
            }
        }
    }

    fn draw_spectrum<Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle)
    where
        Renderer: renderer::Renderer,
    {
        let num_bins = self.magnitudes.len();
        if num_bins == 0 {
            return;
        }

        // Number of visual bars to draw
        let num_bars = (bounds.width / 3.0) as usize;
        let bar_width = bounds.width / num_bars as f32;

        for bar_idx in 0..num_bars {
            // Calculate frequency range for this bar (log scale)
            let t1 = bar_idx as f32 / num_bars as f32;
            let t2 = (bar_idx + 1) as f32 / num_bars as f32;

            let log_min = self.min_freq.ln();
            let log_max = self.max_freq.ln();

            let freq1 = (log_min + t1 * (log_max - log_min)).exp();
            let freq2 = (log_min + t2 * (log_max - log_min)).exp();

            // Find max magnitude in this frequency range
            let bin1 = ((freq1 / (self.sample_rate / 2.0)) * num_bins as f32) as usize;
            let bin2 = ((freq2 / (self.sample_rate / 2.0)) * num_bins as f32) as usize;

            let mut max_mag = 0.0_f32;
            for bin in bin1.min(num_bins - 1)..=bin2.min(num_bins - 1) {
                max_mag = max_mag.max(self.magnitudes[bin]);
            }

            // Convert to dB and draw bar
            let db = Self::linear_to_db(max_mag);
            if db > self.min_db {
                let x = bounds.x + bar_idx as f32 * bar_width;
                let y = self.db_to_y(db, bounds);
                let bottom_y = bounds.y + bounds.height;
                let height = (bottom_y - y).max(0.0);

                let color = self.level_color(db);

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y,
                            width: bar_width - 1.0,
                            height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    color,
                );
            }
        }
    }

    fn draw_peaks<Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle, peaks: &[f32])
    where
        Renderer: renderer::Renderer,
    {
        let num_bins = peaks.len();
        if num_bins == 0 {
            return;
        }

        let num_bars = (bounds.width / 3.0) as usize;
        let bar_width = bounds.width / num_bars as f32;

        for bar_idx in 0..num_bars {
            let t1 = bar_idx as f32 / num_bars as f32;
            let t2 = (bar_idx + 1) as f32 / num_bars as f32;

            let log_min = self.min_freq.ln();
            let log_max = self.max_freq.ln();

            let freq1 = (log_min + t1 * (log_max - log_min)).exp();
            let freq2 = (log_min + t2 * (log_max - log_min)).exp();

            let bin1 = ((freq1 / (self.sample_rate / 2.0)) * num_bins as f32) as usize;
            let bin2 = ((freq2 / (self.sample_rate / 2.0)) * num_bins as f32) as usize;

            let mut max_peak = 0.0_f32;
            for bin in bin1.min(num_bins - 1)..=bin2.min(num_bins - 1) {
                max_peak = max_peak.max(peaks[bin]);
            }

            let db = Self::linear_to_db(max_peak);
            if db > self.min_db {
                let x = bounds.x + bar_idx as f32 * bar_width;
                let y = self.db_to_y(db, bounds);

                // Draw peak marker
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x,
                            y: y - 1.0,
                            width: bar_width - 1.0,
                            height: 2.0,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    Palette::TEXT_PRIMARY,
                );
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<SpectrumAnalyzer<'a>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: 'a,
    Theme: 'a,
{
    fn from(spectrum: SpectrumAnalyzer<'a>) -> Self {
        Element::new(spectrum)
    }
}
