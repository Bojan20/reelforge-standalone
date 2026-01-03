//! Automation Curve Editor Widget
//!
//! Professional automation curve editing with:
//! - Multiple curve types (linear, bezier, step)
//! - Point manipulation (add, move, delete)
//! - Multi-selection and range editing
//! - Snap to grid
//! - Smooth/thin operations
//! - Copy/paste/duplicate

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer;
use iced::advanced::widget::{self, Widget};
use iced::advanced::{Clipboard, Shell};
use iced::mouse;
use iced::{Element, Event, Length, Rectangle, Size};

use crate::theme::Palette;

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Curve interpolation type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CurveType {
    #[default]
    Linear,
    Bezier,
    Step,
    Smooth,
    SCurve,
    Exponential,
    Logarithmic,
}

/// Automation point
#[derive(Debug, Clone, Copy)]
pub struct AutomationPoint {
    /// Position in samples
    pub position: u64,
    /// Normalized value (0.0 to 1.0)
    pub value: f64,
    /// Curve type for segment AFTER this point
    pub curve_type: CurveType,
    /// Tension for bezier curves (-1.0 to 1.0)
    pub tension: f64,
    /// Is selected
    pub selected: bool,
}

impl AutomationPoint {
    pub fn new(position: u64, value: f64) -> Self {
        Self {
            position,
            value: value.clamp(0.0, 1.0),
            curve_type: CurveType::Linear,
            tension: 0.0,
            selected: false,
        }
    }

    pub fn with_curve(mut self, curve_type: CurveType) -> Self {
        self.curve_type = curve_type;
        self
    }

    pub fn with_tension(mut self, tension: f64) -> Self {
        self.tension = tension.clamp(-1.0, 1.0);
        self
    }
}

/// Automation lane data
#[derive(Debug, Clone)]
pub struct AutomationLane {
    /// Lane ID
    pub id: String,
    /// Parameter name
    pub name: String,
    /// Points in the lane
    pub points: Vec<AutomationPoint>,
    /// Lane color
    pub color: Option<u32>,
    /// Is visible
    pub visible: bool,
    /// Is armed for writing
    pub armed: bool,
    /// Value range (for display)
    pub min_value: f64,
    pub max_value: f64,
    /// Default value
    pub default_value: f64,
    /// Unit suffix (dB, %, Hz, etc.)
    pub unit: String,
}

impl AutomationLane {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            points: Vec::new(),
            color: None,
            visible: true,
            armed: false,
            min_value: 0.0,
            max_value: 1.0,
            default_value: 0.5,
            unit: String::new(),
        }
    }

    pub fn with_range(mut self, min: f64, max: f64, default: f64) -> Self {
        self.min_value = min;
        self.max_value = max;
        self.default_value = default;
        self
    }

    pub fn with_unit(mut self, unit: &str) -> Self {
        self.unit = unit.to_string();
        self
    }

    /// Get value at position (interpolated)
    pub fn value_at(&self, position: u64) -> f64 {
        if self.points.is_empty() {
            return self.default_value;
        }

        // Find surrounding points
        let mut prev: Option<&AutomationPoint> = None;
        let mut next: Option<&AutomationPoint> = None;

        for point in &self.points {
            if point.position <= position {
                prev = Some(point);
            } else {
                next = Some(point);
                break;
            }
        }

        match (prev, next) {
            (None, None) => self.default_value,
            (Some(p), None) => p.value,
            (None, Some(n)) => n.value,
            (Some(p), Some(n)) => {
                let t = (position - p.position) as f64 / (n.position - p.position) as f64;
                Self::interpolate(p.value, n.value, t, p.curve_type, p.tension)
            }
        }
    }

    /// Interpolate between two values
    fn interpolate(v0: f64, v1: f64, t: f64, curve_type: CurveType, tension: f64) -> f64 {
        let t = t.clamp(0.0, 1.0);

        match curve_type {
            CurveType::Linear => v0 + (v1 - v0) * t,
            CurveType::Step => v0,
            CurveType::Bezier => {
                // Cubic bezier with tension control
                let t2 = t * t;
                let t3 = t2 * t;
                let mt = 1.0 - t;
                let mt2 = mt * mt;
                let mt3 = mt2 * mt;

                let cp1 = v0 + tension * 0.5 * (v1 - v0);
                let cp2 = v1 - tension * 0.5 * (v1 - v0);

                mt3 * v0 + 3.0 * mt2 * t * cp1 + 3.0 * mt * t2 * cp2 + t3 * v1
            }
            CurveType::Smooth => {
                // Smoothstep
                let t = t * t * (3.0 - 2.0 * t);
                v0 + (v1 - v0) * t
            }
            CurveType::SCurve => {
                // Stronger S-curve
                let t = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
                v0 + (v1 - v0) * t
            }
            CurveType::Exponential => {
                // Exponential ease
                let t = if tension >= 0.0 {
                    t.powf(1.0 + tension * 2.0)
                } else {
                    1.0 - (1.0 - t).powf(1.0 - tension * 2.0)
                };
                v0 + (v1 - v0) * t
            }
            CurveType::Logarithmic => {
                // Logarithmic ease
                let t = ((t * 9.0 + 1.0).ln() / 10.0_f64.ln()).clamp(0.0, 1.0);
                v0 + (v1 - v0) * t
            }
        }
    }

    /// Add point
    pub fn add_point(&mut self, point: AutomationPoint) {
        // Insert in sorted order
        let pos = self.points.iter().position(|p| p.position > point.position);
        match pos {
            Some(i) => self.points.insert(i, point),
            None => self.points.push(point),
        }
    }

    /// Remove point at index
    pub fn remove_point(&mut self, index: usize) -> Option<AutomationPoint> {
        if index < self.points.len() {
            Some(self.points.remove(index))
        } else {
            None
        }
    }

    /// Select points in range
    pub fn select_range(&mut self, start: u64, end: u64) {
        for point in &mut self.points {
            point.selected = point.position >= start && point.position <= end;
        }
    }

    /// Clear selection
    pub fn clear_selection(&mut self) {
        for point in &mut self.points {
            point.selected = false;
        }
    }

    /// Delete selected points
    pub fn delete_selected(&mut self) {
        self.points.retain(|p| !p.selected);
    }
}

/// Automation editor messages
#[derive(Debug, Clone)]
pub enum AutomationMessage {
    /// Add point
    AddPoint(usize, AutomationPoint), // lane index, point
    /// Move point
    MovePoint(usize, usize, u64, f64), // lane, point, new_position, new_value
    /// Delete point
    DeletePoint(usize, usize), // lane, point
    /// Select point
    SelectPoint(usize, usize, bool), // lane, point, add_to_selection
    /// Select range
    SelectRange(u64, u64),
    /// Clear selection
    ClearSelection,
    /// Change curve type for selected
    SetCurveType(CurveType),
    /// Toggle lane visibility
    ToggleLaneVisibility(usize),
    /// Toggle lane arm
    ToggleLaneArm(usize),
    /// Zoom changed
    ZoomChanged(f64),
    /// Scroll changed
    ScrollChanged(u64),
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Automation curve editor widget
pub struct AutomationEditor<'a, Message> {
    /// Automation lanes
    lanes: &'a [AutomationLane],
    /// Active lane index
    active_lane: Option<usize>,
    /// Samples per pixel (zoom)
    samples_per_pixel: f64,
    /// Scroll position (samples)
    scroll_samples: u64,
    /// Total duration (samples)
    total_duration: u64,
    /// Sample rate
    sample_rate: u32,
    /// Show grid
    show_grid: bool,
    /// Snap to grid
    snap_to_grid: bool,
    /// Grid resolution (samples)
    grid_resolution: u64,
    /// Lane header width
    header_width: f32,
    /// Widget dimensions
    width: f32,
    height: f32,
    /// Message callback
    on_message: Option<Box<dyn Fn(AutomationMessage) -> Message + 'a>>,
}

impl<'a, Message> AutomationEditor<'a, Message> {
    const POINT_RADIUS: f32 = 5.0;
    const CURVE_WIDTH: f32 = 2.0;
    const LANE_HEADER_HEIGHT: f32 = 24.0;

    pub fn new(lanes: &'a [AutomationLane]) -> Self {
        Self {
            lanes,
            active_lane: None,
            samples_per_pixel: 500.0,
            scroll_samples: 0,
            total_duration: 48000 * 60 * 5, // 5 min default
            sample_rate: 48000,
            show_grid: true,
            snap_to_grid: true,
            grid_resolution: 48000, // 1 second
            header_width: 150.0,
            width: 800.0,
            height: 200.0,
            on_message: None,
        }
    }

    pub fn active_lane(mut self, index: Option<usize>) -> Self {
        self.active_lane = index;
        self
    }

    pub fn zoom(mut self, samples_per_pixel: f64) -> Self {
        self.samples_per_pixel = samples_per_pixel.max(1.0);
        self
    }

    pub fn scroll(mut self, samples: u64) -> Self {
        self.scroll_samples = samples;
        self
    }

    pub fn total_duration(mut self, samples: u64) -> Self {
        self.total_duration = samples;
        self
    }

    pub fn sample_rate(mut self, rate: u32) -> Self {
        self.sample_rate = rate;
        self
    }

    pub fn grid(mut self, show: bool, snap: bool, resolution: u64) -> Self {
        self.show_grid = show;
        self.snap_to_grid = snap;
        self.grid_resolution = resolution;
        self
    }

    pub fn size(mut self, width: f32, height: f32) -> Self {
        self.width = width;
        self.height = height;
        self
    }

    pub fn on_message<F>(mut self, callback: F) -> Self
    where
        F: Fn(AutomationMessage) -> Message + 'a,
    {
        self.on_message = Some(Box::new(callback));
        self
    }

    // Coordinate conversions
    fn samples_to_x(&self, samples: u64, bounds: &Rectangle) -> f32 {
        let content_x = bounds.x + self.header_width;
        let relative = samples.saturating_sub(self.scroll_samples);
        content_x + (relative as f64 / self.samples_per_pixel) as f32
    }

    fn x_to_samples(&self, x: f32, bounds: &Rectangle) -> u64 {
        let content_x = bounds.x + self.header_width;
        if x < content_x {
            return self.scroll_samples;
        }
        let relative_x = x - content_x;
        self.scroll_samples + (relative_x as f64 * self.samples_per_pixel) as u64
    }

    fn value_to_y(&self, value: f64, content_bounds: &Rectangle) -> f32 {
        content_bounds.y + content_bounds.height * (1.0 - value.clamp(0.0, 1.0)) as f32
    }

    fn y_to_value(&self, y: f32, content_bounds: &Rectangle) -> f64 {
        let relative = (y - content_bounds.y) / content_bounds.height;
        (1.0 - relative as f64).clamp(0.0, 1.0)
    }

    fn snap_to_grid_samples(&self, samples: u64) -> u64 {
        if self.snap_to_grid && self.grid_resolution > 0 {
            (samples / self.grid_resolution) * self.grid_resolution
        } else {
            samples
        }
    }

    fn content_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x + self.header_width,
            y: bounds.y,
            width: bounds.width - self.header_width,
            height: bounds.height,
        }
    }

    fn header_bounds(&self, bounds: &Rectangle) -> Rectangle {
        Rectangle {
            x: bounds.x,
            y: bounds.y,
            width: self.header_width,
            height: bounds.height,
        }
    }

    fn point_at(&self, lane: &AutomationLane, x: f32, y: f32, bounds: &Rectangle) -> Option<usize> {
        let content = self.content_bounds(bounds);

        for (i, point) in lane.points.iter().enumerate() {
            let px = self.samples_to_x(point.position, bounds);
            let py = self.value_to_y(point.value, &content);

            let dx = x - px;
            let dy = y - py;
            let dist = (dx * dx + dy * dy).sqrt();

            if dist <= Self::POINT_RADIUS * 2.0 {
                return Some(i);
            }
        }
        None
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION EDITOR STATE
// ═══════════════════════════════════════════════════════════════════════════════

#[derive(Default)]
pub struct AutomationEditorState {
    dragging_point: Option<(usize, usize)>, // (lane, point)
    selecting_range: bool,
    selection_start: (f32, f32),
    hovered_point: Option<(usize, usize)>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIDGET IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message, Theme, Renderer> Widget<Message, Theme, Renderer> for AutomationEditor<'a, Message>
where
    Renderer: renderer::Renderer,
    Message: Clone,
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
        tree: &widget::Tree,
        renderer: &mut Renderer,
        _theme: &Theme,
        _style: &renderer::Style,
        layout: Layout<'_>,
        _cursor: mouse::Cursor,
        _viewport: &Rectangle,
    ) {
        let state = tree.state.downcast_ref::<AutomationEditorState>();
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

        // Draw header
        self.draw_header(renderer, &bounds);

        // Draw content
        let content = self.content_bounds(&bounds);
        self.draw_grid(renderer, &content);
        self.draw_curves(renderer, &bounds, state);
    }

    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<AutomationEditorState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(AutomationEditorState::default())
    }

    fn on_event(
        &mut self,
        tree: &mut widget::Tree,
        event: Event,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        _renderer: &Renderer,
        _clipboard: &mut dyn Clipboard,
        shell: &mut Shell<'_, Message>,
        _viewport: &Rectangle,
    ) -> iced::event::Status {
        let state = tree.state.downcast_mut::<AutomationEditorState>();
        let bounds = layout.bounds();
        let content = self.content_bounds(&bounds);

        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                if let Some(pos) = cursor.position() {
                    if content.contains(pos) {
                        // Check if clicking on a point
                        if let Some(lane_idx) = self.active_lane {
                            if lane_idx < self.lanes.len() {
                                if let Some(point_idx) = self.point_at(&self.lanes[lane_idx], pos.x, pos.y, &bounds) {
                                    // Start dragging
                                    state.dragging_point = Some((lane_idx, point_idx));
                                    return iced::event::Status::Captured;
                                } else {
                                    // Add new point
                                    let samples = self.snap_to_grid_samples(self.x_to_samples(pos.x, &bounds));
                                    let value = self.y_to_value(pos.y, &content);
                                    let point = AutomationPoint::new(samples, value);

                                    if let Some(ref on_message) = self.on_message {
                                        shell.publish(on_message(AutomationMessage::AddPoint(lane_idx, point)));
                                    }
                                    return iced::event::Status::Captured;
                                }
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Right)) => {
                if let Some(pos) = cursor.position() {
                    if content.contains(pos) {
                        if let Some(lane_idx) = self.active_lane {
                            if lane_idx < self.lanes.len() {
                                if let Some(point_idx) = self.point_at(&self.lanes[lane_idx], pos.x, pos.y, &bounds) {
                                    // Delete point
                                    if let Some(ref on_message) = self.on_message {
                                        shell.publish(on_message(AutomationMessage::DeletePoint(lane_idx, point_idx)));
                                    }
                                    return iced::event::Status::Captured;
                                }
                            }
                        }
                    }
                }
            }

            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left)) => {
                if state.dragging_point.is_some() {
                    state.dragging_point = None;
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::CursorMoved { position }) => {
                // Update hovered point
                state.hovered_point = None;
                if let Some(lane_idx) = self.active_lane {
                    if lane_idx < self.lanes.len() {
                        if let Some(point_idx) = self.point_at(&self.lanes[lane_idx], position.x, position.y, &bounds) {
                            state.hovered_point = Some((lane_idx, point_idx));
                        }
                    }
                }

                // Handle dragging
                if let Some((lane_idx, point_idx)) = state.dragging_point {
                    let samples = self.snap_to_grid_samples(self.x_to_samples(position.x, &bounds));
                    let value = self.y_to_value(position.y, &content);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(AutomationMessage::MovePoint(lane_idx, point_idx, samples, value)));
                    }
                    return iced::event::Status::Captured;
                }
            }

            Event::Mouse(mouse::Event::WheelScrolled { delta }) => {
                if cursor.is_over(bounds) {
                    let scroll_amount = match delta {
                        mouse::ScrollDelta::Lines { y, .. } => y * 0.1,
                        mouse::ScrollDelta::Pixels { y, .. } => y * 0.001,
                    };

                    let new_zoom = (self.samples_per_pixel * (1.0 - scroll_amount as f64)).clamp(1.0, 10000.0);

                    if let Some(ref on_message) = self.on_message {
                        shell.publish(on_message(AutomationMessage::ZoomChanged(new_zoom)));
                    }
                    return iced::event::Status::Captured;
                }
            }

            _ => {}
        }

        iced::event::Status::Ignored
    }

    fn mouse_interaction(
        &self,
        tree: &widget::Tree,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        _viewport: &Rectangle,
        _renderer: &Renderer,
    ) -> mouse::Interaction {
        let state = tree.state.downcast_ref::<AutomationEditorState>();

        if state.dragging_point.is_some() {
            return mouse::Interaction::Grabbing;
        }

        if state.hovered_point.is_some() {
            return mouse::Interaction::Grab;
        }

        let bounds = layout.bounds();
        let content = self.content_bounds(&bounds);

        if let Some(pos) = cursor.position() {
            if content.contains(pos) {
                return mouse::Interaction::Crosshair;
            }
        }

        mouse::Interaction::default()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

impl<'a, Message> AutomationEditor<'a, Message>
where
    Message: Clone,
{
    fn draw_header<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, bounds: &Rectangle) {
        let header = self.header_bounds(bounds);

        renderer.fill_quad(
            renderer::Quad {
                bounds: header,
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_DEEP,
        );

        // Draw lane headers
        let lane_height = bounds.height / self.lanes.len().max(1) as f32;
        let mut y = bounds.y;

        for (_i, lane) in self.lanes.iter().enumerate() {
            let lane_header = Rectangle {
                x: header.x,
                y,
                width: header.width,
                height: lane_height,
            };

            // Lane color indicator
            let color = lane.color.map(|c| {
                iced::Color::from_rgb(
                    ((c >> 16) & 0xFF) as f32 / 255.0,
                    ((c >> 8) & 0xFF) as f32 / 255.0,
                    (c & 0xFF) as f32 / 255.0,
                )
            }).unwrap_or(Palette::ACCENT_CYAN);

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: lane_header.x,
                        y: lane_header.y,
                        width: 4.0,
                        height: lane_header.height,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                color,
            );

            // Separator
            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: lane_header.x,
                        y: lane_header.y + lane_header.height - 1.0,
                        width: lane_header.width,
                        height: 1.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                Palette::BG_SURFACE,
            );

            y += lane_height;
        }

        // Right border
        renderer.fill_quad(
            renderer::Quad {
                bounds: Rectangle {
                    x: header.x + header.width - 1.0,
                    y: header.y,
                    width: 1.0,
                    height: header.height,
                },
                border: Default::default(),
                shadow: Default::default(),
            },
            Palette::BG_SURFACE,
        );
    }

    fn draw_grid<Renderer: renderer::Renderer>(&self, renderer: &mut Renderer, content: &Rectangle) {
        if !self.show_grid {
            return;
        }

        // Value grid lines (horizontal)
        let num_lines = 5;
        for i in 0..=num_lines {
            let y = content.y + content.height * i as f32 / num_lines as f32;

            renderer.fill_quad(
                renderer::Quad {
                    bounds: Rectangle {
                        x: content.x,
                        y: y - 0.5,
                        width: content.width,
                        height: 1.0,
                    },
                    border: Default::default(),
                    shadow: Default::default(),
                },
                if i == num_lines / 2 {
                    Palette::BG_SURFACE
                } else {
                    iced::Color::from_rgba(0.15, 0.15, 0.18, 0.5)
                },
            );
        }

        // Time grid lines (vertical)
        let visible_samples = (content.width as f64 * self.samples_per_pixel) as u64;
        let end_samples = self.scroll_samples + visible_samples;

        let first_grid = (self.scroll_samples / self.grid_resolution) * self.grid_resolution;
        let mut grid_pos = first_grid;

        while grid_pos <= end_samples {
            let x = self.samples_to_x(grid_pos, &Rectangle {
                x: content.x - self.header_width,
                ..*content
            });

            if x >= content.x && x <= content.x + content.width {
                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: x - 0.5,
                            y: content.y,
                            width: 1.0,
                            height: content.height,
                        },
                        border: Default::default(),
                        shadow: Default::default(),
                    },
                    iced::Color::from_rgba(0.15, 0.15, 0.18, 0.5),
                );
            }

            grid_pos += self.grid_resolution;
        }
    }

    fn draw_curves<Renderer: renderer::Renderer>(
        &self,
        renderer: &mut Renderer,
        bounds: &Rectangle,
        state: &AutomationEditorState,
    ) {
        let content = self.content_bounds(bounds);

        for (lane_idx, lane) in self.lanes.iter().enumerate() {
            if !lane.visible || lane.points.is_empty() {
                continue;
            }

            let is_active = self.active_lane == Some(lane_idx);
            let color = lane.color.map(|c| {
                iced::Color::from_rgb(
                    ((c >> 16) & 0xFF) as f32 / 255.0,
                    ((c >> 8) & 0xFF) as f32 / 255.0,
                    (c & 0xFF) as f32 / 255.0,
                )
            }).unwrap_or(Palette::ACCENT_CYAN);

            let curve_color = if is_active {
                color
            } else {
                iced::Color::from_rgba(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.5)
            };

            // Draw curve segments
            for i in 0..lane.points.len() {
                let p1 = &lane.points[i];
                let x1 = self.samples_to_x(p1.position, bounds);
                let y1 = self.value_to_y(p1.value, &content);

                if i + 1 < lane.points.len() {
                    let p2 = &lane.points[i + 1];
                    let x2 = self.samples_to_x(p2.position, bounds);
                    let y2 = self.value_to_y(p2.value, &content);

                    // Draw curve segment (simplified as lines)
                    let num_steps = ((x2 - x1).abs() as usize).max(2).min(100);
                    let mut prev_x = x1;
                    let mut prev_y = y1;

                    for step in 1..=num_steps {
                        let t = step as f64 / num_steps as f64;
                        let v = AutomationLane::interpolate(p1.value, p2.value, t, p1.curve_type, p1.tension);
                        let curr_x = x1 + (x2 - x1) * t as f32;
                        let curr_y = self.value_to_y(v, &content);

                        // Draw line segment
                        let dx = curr_x - prev_x;
                        let dy = curr_y - prev_y;
                        let len = (dx * dx + dy * dy).sqrt().max(1.0);

                        renderer.fill_quad(
                            renderer::Quad {
                                bounds: Rectangle {
                                    x: prev_x.min(curr_x),
                                    y: prev_y.min(curr_y),
                                    width: dx.abs().max(Self::CURVE_WIDTH),
                                    height: dy.abs().max(Self::CURVE_WIDTH),
                                },
                                border: Default::default(),
                                shadow: Default::default(),
                            },
                            curve_color,
                        );

                        prev_x = curr_x;
                        prev_y = curr_y;
                    }
                }

                // Draw point
                let is_hovered = state.hovered_point == Some((lane_idx, i));
                let point_color = if p1.selected {
                    Palette::ACCENT_BLUE
                } else if is_hovered {
                    iced::Color::from_rgba(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0)
                } else {
                    color
                };

                let radius = if p1.selected || is_hovered {
                    Self::POINT_RADIUS * 1.5
                } else {
                    Self::POINT_RADIUS
                };

                renderer.fill_quad(
                    renderer::Quad {
                        bounds: Rectangle {
                            x: x1 - radius,
                            y: y1 - radius,
                            width: radius * 2.0,
                            height: radius * 2.0,
                        },
                        border: iced::Border {
                            color: if p1.selected { Palette::ACCENT_BLUE } else { Palette::BG_SURFACE },
                            width: if p1.selected { 2.0 } else { 1.0 },
                            radius: radius.into(),
                        },
                        shadow: Default::default(),
                    },
                    point_color,
                );
            }
        }
    }
}

impl<'a, Message, Theme, Renderer> From<AutomationEditor<'a, Message>> for Element<'a, Message, Theme, Renderer>
where
    Renderer: renderer::Renderer + 'a,
    Message: Clone + 'a,
    Theme: 'a,
{
    fn from(editor: AutomationEditor<'a, Message>) -> Self {
        Element::new(editor)
    }
}
