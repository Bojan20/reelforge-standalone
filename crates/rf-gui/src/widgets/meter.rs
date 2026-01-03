//! Level meter widget

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::{mouse, Color, Element, Length, Rectangle, Size};

use crate::theme::{meter_color, Palette};

/// Meter orientation
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MeterOrientation {
    Vertical,
    Horizontal,
}

/// Level meter widget
pub struct Meter {
    level: f32,
    peak: f32,
    width: f32,
    height: f32,
    orientation: MeterOrientation,
    show_peak: bool,
}

impl Meter {
    pub fn new(level: f32) -> Self {
        Self {
            level: level.clamp(0.0, 1.0),
            peak: 0.0,
            width: 12.0,
            height: 200.0,
            orientation: MeterOrientation::Vertical,
            show_peak: true,
        }
    }

    pub fn peak(mut self, peak: f32) -> Self {
        self.peak = peak.clamp(0.0, 1.0);
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn orientation(mut self, orientation: MeterOrientation) -> Self {
        self.orientation = orientation;
        self
    }

    pub fn show_peak(mut self, show: bool) -> Self {
        self.show_peak = show;
        self
    }
}

impl<Message, Theme, Renderer> Widget<Message, Theme, Renderer> for Meter
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
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let bounds = layout.bounds();

        // Draw background
        renderer.fill_quad(
            renderer::Quad {
                bounds,
                border: iced::Border {
                    color: Palette::BG_SURFACE,
                    width: 1.0,
                    radius: 2.0.into(),
                },
                shadow: Default::default(),
            },
            Palette::BG_DEEPEST,
        );

        // Draw level bar
        match self.orientation {
            MeterOrientation::Vertical => {
                let level_height = bounds.height * self.level;
                let level_bounds = Rectangle {
                    x: bounds.x + 1.0,
                    y: bounds.y + bounds.height - level_height - 1.0,
                    width: bounds.width - 2.0,
                    height: level_height,
                };

                // Draw gradient segments
                let num_segments = 20;
                let segment_height = level_bounds.height / num_segments as f32;

                for i in 0..num_segments {
                    let segment_level = (num_segments - i) as f32 / num_segments as f32;
                    if segment_level <= self.level {
                        let segment_bounds = Rectangle {
                            x: level_bounds.x,
                            y: level_bounds.y + i as f32 * segment_height,
                            width: level_bounds.width,
                            height: segment_height - 1.0,
                        };

                        renderer.fill_quad(
                            renderer::Quad {
                                bounds: segment_bounds,
                                border: Default::default(),
                                shadow: Default::default(),
                            },
                            meter_color(segment_level),
                        );
                    }
                }

                // Draw peak indicator
                if self.show_peak && self.peak > 0.0 {
                    let peak_y = bounds.y + bounds.height * (1.0 - self.peak);
                    let peak_bounds = Rectangle {
                        x: bounds.x + 1.0,
                        y: peak_y - 1.0,
                        width: bounds.width - 2.0,
                        height: 2.0,
                    };

                    renderer.fill_quad(
                        renderer::Quad {
                            bounds: peak_bounds,
                            border: Default::default(),
                            shadow: Default::default(),
                        },
                        if self.peak > 0.95 {
                            Palette::METER_RED
                        } else {
                            Palette::TEXT_PRIMARY
                        },
                    );
                }
            }
            MeterOrientation::Horizontal => {
                let level_width = bounds.width * self.level;
                let level_bounds = Rectangle {
                    x: bounds.x + 1.0,
                    y: bounds.y + 1.0,
                    width: level_width,
                    height: bounds.height - 2.0,
                };

                // Draw gradient segments
                let num_segments = 20;
                let segment_width = level_bounds.width / num_segments as f32;

                for i in 0..num_segments {
                    let segment_level = i as f32 / num_segments as f32;
                    if segment_level <= self.level {
                        let segment_bounds = Rectangle {
                            x: level_bounds.x + i as f32 * segment_width,
                            y: level_bounds.y,
                            width: segment_width - 1.0,
                            height: level_bounds.height,
                        };

                        renderer.fill_quad(
                            renderer::Quad {
                                bounds: segment_bounds,
                                border: Default::default(),
                                shadow: Default::default(),
                            },
                            meter_color(segment_level),
                        );
                    }
                }

                // Draw peak indicator
                if self.show_peak && self.peak > 0.0 {
                    let peak_x = bounds.x + bounds.width * self.peak;
                    let peak_bounds = Rectangle {
                        x: peak_x - 1.0,
                        y: bounds.y + 1.0,
                        width: 2.0,
                        height: bounds.height - 2.0,
                    };

                    renderer.fill_quad(
                        renderer::Quad {
                            bounds: peak_bounds,
                            border: Default::default(),
                            shadow: Default::default(),
                        },
                        if self.peak > 0.95 {
                            Palette::METER_RED
                        } else {
                            Palette::TEXT_PRIMARY
                        },
                    );
                }
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<Meter> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: 'a,
    Theme: 'a,
{
    fn from(meter: Meter) -> Self {
        Element::new(meter)
    }
}

/// Stereo meter pair
pub struct StereoMeter {
    left_level: f32,
    right_level: f32,
    left_peak: f32,
    right_peak: f32,
    width: f32,
    height: f32,
}

impl StereoMeter {
    pub fn new(left: f32, right: f32) -> Self {
        Self {
            left_level: left.clamp(0.0, 1.0),
            right_level: right.clamp(0.0, 1.0),
            left_peak: 0.0,
            right_peak: 0.0,
            width: 28.0,
            height: 200.0,
        }
    }

    pub fn peaks(mut self, left: f32, right: f32) -> Self {
        self.left_peak = left.clamp(0.0, 1.0);
        self.right_peak = right.clamp(0.0, 1.0);
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }
}

impl<Message, Theme, Renderer> Widget<Message, Theme, Renderer> for StereoMeter
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
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let bounds = layout.bounds();
        let meter_width = (bounds.width - 4.0) / 2.0;

        // Left meter
        let left_bounds = Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: meter_width,
            height: bounds.height,
        };

        // Right meter
        let right_bounds = Rectangle {
            x: bounds.x + meter_width + 4.0,
            y: bounds.y,
            width: meter_width,
            height: bounds.height,
        };

        // Draw backgrounds
        for meter_bounds in [left_bounds, right_bounds] {
            renderer.fill_quad(
                renderer::Quad {
                    bounds: meter_bounds,
                    border: iced::Border {
                        color: Palette::BG_SURFACE,
                        width: 1.0,
                        radius: 2.0.into(),
                    },
                    shadow: Default::default(),
                },
                Palette::BG_DEEPEST,
            );
        }

        // Draw levels
        for (level, peak, meter_bounds) in [
            (self.left_level, self.left_peak, left_bounds),
            (self.right_level, self.right_peak, right_bounds),
        ] {
            let level_height = meter_bounds.height * level;
            let num_segments = 20;
            let segment_height = meter_bounds.height / num_segments as f32;

            for i in 0..num_segments {
                let segment_level = (num_segments - i) as f32 / num_segments as f32;
                if segment_level <= level {
                    let segment_bounds = Rectangle {
                        x: meter_bounds.x + 1.0,
                        y: meter_bounds.y + i as f32 * segment_height + 1.0,
                        width: meter_bounds.width - 2.0,
                        height: segment_height - 1.0,
                    };

                    renderer.fill_quad(
                        renderer::Quad {
                            bounds: segment_bounds,
                            border: Default::default(),
                            shadow: Default::default(),
                        },
                        meter_color(segment_level),
                    );
                }
            }

            // Peak indicator
            if peak > 0.0 {
                let peak_y = meter_bounds.y + meter_bounds.height * (1.0 - peak);
                let peak_bounds = Rectangle {
                    x: meter_bounds.x + 1.0,
                    y: peak_y - 1.0,
                    width: meter_bounds.width - 2.0,
                    height: 2.0,
                };

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: peak_bounds,
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    if peak > 0.95 {
                        Palette::METER_RED
                    } else {
                        Palette::TEXT_PRIMARY
                    },
                );
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<StereoMeter> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: 'a,
    Theme: 'a,
{
    fn from(meter: StereoMeter) -> Self {
        Element::new(meter)
    }
}
