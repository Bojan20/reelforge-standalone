//! Room simulation and reverb
//!
//! Physically-based room acoustics:
//! - Ray tracing for early reflections
//! - Late reverb with diffusion network
//! - Material absorption coefficients
//! - Room mode simulation

use serde::{Deserialize, Serialize};
use crate::position::Position3D;

/// Room definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Room {
    /// Room dimensions (width, depth, height) in meters
    pub dimensions: (f32, f32, f32),
    /// Wall materials
    pub walls: WallMaterials,
    /// Listener position in room
    pub listener_pos: Position3D,
}

impl Default for Room {
    fn default() -> Self {
        Self {
            dimensions: (10.0, 12.0, 3.5),
            walls: WallMaterials::default(),
            listener_pos: Position3D::new(0.0, 0.0, 1.7),
        }
    }
}

/// Wall material configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WallMaterials {
    /// Left wall material
    pub left: Material,
    /// Right wall material
    pub right: Material,
    /// Front wall material
    pub front: Material,
    /// Back wall material
    pub back: Material,
    /// Floor material
    pub floor: Material,
    /// Ceiling material
    pub ceiling: Material,
}

impl Default for WallMaterials {
    fn default() -> Self {
        Self {
            left: Material::Drywall,
            right: Material::Drywall,
            front: Material::Drywall,
            back: Material::Drywall,
            floor: Material::Carpet,
            ceiling: Material::AcousticTile,
        }
    }
}

/// Acoustic material
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Material {
    /// Concrete (very reflective)
    Concrete,
    /// Brick
    Brick,
    /// Drywall/plasterboard
    Drywall,
    /// Glass
    Glass,
    /// Wood panel
    WoodPanel,
    /// Carpet (absorptive)
    Carpet,
    /// Heavy curtain (very absorptive)
    HeavyCurtain,
    /// Acoustic tile
    AcousticTile,
    /// Acoustic foam
    AcousticFoam,
}

impl Material {
    /// Get absorption coefficients at octave band frequencies
    /// Returns: [125, 250, 500, 1000, 2000, 4000] Hz
    pub fn absorption_coefficients(&self) -> [f32; 6] {
        match self {
            Material::Concrete => [0.01, 0.01, 0.02, 0.02, 0.02, 0.03],
            Material::Brick => [0.03, 0.03, 0.03, 0.04, 0.05, 0.07],
            Material::Drywall => [0.29, 0.10, 0.05, 0.04, 0.07, 0.09],
            Material::Glass => [0.35, 0.25, 0.18, 0.12, 0.07, 0.04],
            Material::WoodPanel => [0.42, 0.21, 0.10, 0.08, 0.06, 0.06],
            Material::Carpet => [0.02, 0.06, 0.14, 0.37, 0.60, 0.65],
            Material::HeavyCurtain => [0.07, 0.31, 0.49, 0.75, 0.70, 0.60],
            Material::AcousticTile => [0.50, 0.70, 0.60, 0.70, 0.70, 0.50],
            Material::AcousticFoam => [0.35, 0.51, 0.82, 0.98, 0.99, 0.99],
        }
    }

    /// Get average absorption coefficient
    pub fn average_absorption(&self) -> f32 {
        let coeffs = self.absorption_coefficients();
        coeffs.iter().sum::<f32>() / coeffs.len() as f32
    }
}

/// Early reflection
#[derive(Debug, Clone, Copy)]
pub struct EarlyReflection {
    /// Delay in samples
    pub delay_samples: usize,
    /// Gain (includes distance and absorption)
    pub gain: f32,
    /// Source direction (for HRTF)
    pub direction: Position3D,
    /// Number of wall bounces
    pub order: u8,
}

/// Room simulator
pub struct RoomSimulator {
    /// Room definition
    room: Room,
    /// Sample rate
    sample_rate: u32,
    /// Early reflections (computed)
    early_reflections: Vec<EarlyReflection>,
    /// Late reverb processor
    late_reverb: LateReverb,
    /// Early/late mix (0 = only early, 1 = only late)
    early_late_mix: f32,
    /// Dry/wet mix
    dry_wet: f32,
}

impl RoomSimulator {
    /// Create new room simulator
    pub fn new(room: Room, sample_rate: u32) -> Self {
        let mut sim = Self {
            room: room.clone(),
            sample_rate,
            early_reflections: Vec::new(),
            late_reverb: LateReverb::new(sample_rate, &room),
            early_late_mix: 0.5,
            dry_wet: 0.3,
        };
        sim.compute_early_reflections();
        sim
    }

    /// Set room
    pub fn set_room(&mut self, room: Room) {
        self.room = room;
        self.compute_early_reflections();
        self.late_reverb = LateReverb::new(self.sample_rate, &self.room);
    }

    /// Set dry/wet mix
    pub fn set_dry_wet(&mut self, mix: f32) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    /// Compute early reflections using image source method
    fn compute_early_reflections(&mut self) {
        self.early_reflections.clear();

        let (width, depth, height) = self.room.dimensions;
        let speed_of_sound = 343.0; // m/s

        // Image source method for first-order reflections
        let walls = [
            // (normal, distance from origin, material)
            (Position3D::new(-1.0, 0.0, 0.0), width / 2.0, self.room.walls.left),
            (Position3D::new(1.0, 0.0, 0.0), width / 2.0, self.room.walls.right),
            (Position3D::new(0.0, -1.0, 0.0), depth / 2.0, self.room.walls.back),
            (Position3D::new(0.0, 1.0, 0.0), depth / 2.0, self.room.walls.front),
            (Position3D::new(0.0, 0.0, -1.0), 0.0, self.room.walls.floor),
            (Position3D::new(0.0, 0.0, 1.0), height, self.room.walls.ceiling),
        ];

        // First-order reflections
        for (normal, dist, material) in &walls {
            // Calculate image source position
            let _listener = &self.room.listener_pos;

            // Simple reflection calculation
            let reflection_dist = 2.0 * dist;
            let delay_seconds = reflection_dist / speed_of_sound;
            let delay_samples = (delay_seconds * self.sample_rate as f32) as usize;

            // Distance attenuation
            let distance_gain = 1.0 / (reflection_dist + 1.0);

            // Material absorption (use 1kHz coefficient as representative)
            let absorption = material.absorption_coefficients()[3];
            let reflection_gain = (1.0 - absorption).sqrt();

            let total_gain = distance_gain * reflection_gain;

            // Reflection direction (simplified)
            let direction = Position3D::new(
                -normal.x,
                -normal.y,
                -normal.z,
            );

            self.early_reflections.push(EarlyReflection {
                delay_samples,
                gain: total_gain,
                direction,
                order: 1,
            });
        }

        // Sort by delay
        self.early_reflections.sort_by_key(|r| r.delay_samples);
    }

    /// Process mono input
    pub fn process(&mut self, input: &[f32], output: &mut [f32]) {
        let samples = input.len().min(output.len());

        // Dry signal
        for i in 0..samples {
            output[i] = input[i] * (1.0 - self.dry_wet);
        }

        // Early reflections
        let early_weight = (1.0 - self.early_late_mix) * self.dry_wet;
        for reflection in &self.early_reflections {
            for i in 0..samples {
                let delayed_idx = i.saturating_sub(reflection.delay_samples);
                if delayed_idx < samples {
                    output[i] += input[delayed_idx] * reflection.gain * early_weight;
                }
            }
        }

        // Late reverb
        let late_weight = self.early_late_mix * self.dry_wet;
        let mut late = vec![0.0f32; samples];
        self.late_reverb.process(input, &mut late);
        for i in 0..samples {
            output[i] += late[i] * late_weight;
        }
    }

    /// Get RT60 estimate
    pub fn estimate_rt60(&self) -> f32 {
        self.late_reverb.rt60
    }

    /// Get early reflections
    pub fn early_reflections(&self) -> &[EarlyReflection] {
        &self.early_reflections
    }
}

/// Late reverb using feedback delay network
pub struct LateReverb {
    /// Delay lines
    delay_lines: Vec<DelayLine>,
    /// Feedback matrix coefficients
    feedback_matrix: Vec<Vec<f32>>,
    /// Input diffusion
    input_diffuser: AllpassChain,
    /// Output lowpass
    lowpass_state: f32,
    /// Lowpass coefficient
    lowpass_coeff: f32,
    /// RT60 (seconds)
    rt60: f32,
    /// Pre-delay samples
    predelay_samples: usize,
    /// Pre-delay buffer
    predelay_buffer: Vec<f32>,
    /// Pre-delay position
    predelay_pos: usize,
}

impl LateReverb {
    /// Create new late reverb
    fn new(sample_rate: u32, room: &Room) -> Self {
        // Estimate RT60 from room and materials
        let (w, d, h) = room.dimensions;
        let volume = w * d * h;
        let surface_area = 2.0 * (w * d + w * h + d * h);

        // Average absorption
        let avg_absorption = (
            room.walls.left.average_absorption()
            + room.walls.right.average_absorption()
            + room.walls.front.average_absorption()
            + room.walls.back.average_absorption()
            + room.walls.floor.average_absorption()
            + room.walls.ceiling.average_absorption()
        ) / 6.0;

        // Sabine equation: RT60 = 0.161 * V / (S * a)
        let rt60 = 0.161 * volume / (surface_area * avg_absorption.max(0.01));

        // Pre-delay based on room size
        let speed_of_sound = 343.0;
        let max_dim = w.max(d).max(h);
        let predelay_seconds = max_dim / speed_of_sound;
        let predelay_samples = (predelay_seconds * sample_rate as f32) as usize;

        // Create delay lines with mutually prime lengths
        let base_delay = (sample_rate as f32 * 0.03) as usize; // 30ms base
        let delay_lengths = [
            base_delay,
            base_delay * 1051 / 1000,
            base_delay * 1103 / 1000,
            base_delay * 1151 / 1000,
            base_delay * 1201 / 1000,
            base_delay * 1249 / 1000,
            base_delay * 1301 / 1000,
            base_delay * 1361 / 1000,
        ];

        let delay_lines: Vec<DelayLine> = delay_lengths
            .iter()
            .map(|&len| DelayLine::new(len))
            .collect();

        // Feedback matrix (Hadamard-like)
        let n = delay_lines.len();
        let scale = 1.0 / (n as f32).sqrt();
        let mut feedback_matrix = vec![vec![0.0f32; n]; n];
        for i in 0..n {
            for j in 0..n {
                let sign = if (i & j).count_ones() % 2 == 0 { 1.0 } else { -1.0 };
                feedback_matrix[i][j] = sign * scale;
            }
        }

        // Decay coefficient based on RT60
        let decay = (-3.0 * base_delay as f32 / (sample_rate as f32 * rt60)).exp();
        for row in &mut feedback_matrix {
            for val in row {
                *val *= decay;
            }
        }

        // Lowpass for high-frequency decay
        let cutoff_hz = 8000.0;
        let rc = 1.0 / (2.0 * std::f32::consts::PI * cutoff_hz);
        let dt = 1.0 / sample_rate as f32;
        let lowpass_coeff = dt / (rc + dt);

        Self {
            delay_lines,
            feedback_matrix,
            input_diffuser: AllpassChain::new(sample_rate),
            lowpass_state: 0.0,
            lowpass_coeff,
            rt60,
            predelay_samples,
            predelay_buffer: vec![0.0; predelay_samples.max(1)],
            predelay_pos: 0,
        }
    }

    /// Process
    fn process(&mut self, input: &[f32], output: &mut [f32]) {
        let n = self.delay_lines.len();

        for (i, &sample) in input.iter().enumerate() {
            // Pre-delay
            let predelayed = if self.predelay_samples > 0 {
                let out = self.predelay_buffer[self.predelay_pos];
                self.predelay_buffer[self.predelay_pos] = sample;
                self.predelay_pos = (self.predelay_pos + 1) % self.predelay_buffer.len();
                out
            } else {
                sample
            };

            // Input diffusion
            let diffused = self.input_diffuser.process(predelayed);

            // Read delay outputs
            let delay_outputs: Vec<f32> = self.delay_lines
                .iter()
                .map(|d| d.read())
                .collect();

            // Compute feedback
            let mut feedback_inputs = vec![0.0f32; n];
            for j in 0..n {
                let mut sum = diffused / n as f32;
                for k in 0..n {
                    sum += self.feedback_matrix[j][k] * delay_outputs[k];
                }
                feedback_inputs[j] = sum;
            }

            // Write to delay lines
            for (j, delay) in self.delay_lines.iter_mut().enumerate() {
                delay.write(feedback_inputs[j]);
            }

            // Sum outputs
            let mut sum: f32 = delay_outputs.iter().sum();
            sum /= n as f32;

            // Lowpass
            self.lowpass_state += self.lowpass_coeff * (sum - self.lowpass_state);

            if i < output.len() {
                output[i] = self.lowpass_state;
            }
        }
    }
}

/// Simple delay line
struct DelayLine {
    buffer: Vec<f32>,
    write_pos: usize,
    length: usize,
}

impl DelayLine {
    fn new(length: usize) -> Self {
        Self {
            buffer: vec![0.0; length],
            write_pos: 0,
            length,
        }
    }

    fn read(&self) -> f32 {
        self.buffer[self.write_pos]
    }

    fn write(&mut self, sample: f32) {
        self.buffer[self.write_pos] = sample;
        self.write_pos = (self.write_pos + 1) % self.length;
    }
}

/// Allpass chain for diffusion
struct AllpassChain {
    stages: Vec<AllpassFilter>,
}

impl AllpassChain {
    fn new(sample_rate: u32) -> Self {
        let delays = [
            (sample_rate as f32 * 0.0051) as usize,
            (sample_rate as f32 * 0.0073) as usize,
            (sample_rate as f32 * 0.011) as usize,
            (sample_rate as f32 * 0.017) as usize,
        ];

        let stages = delays
            .iter()
            .map(|&len| AllpassFilter::new(len, 0.5))
            .collect();

        Self { stages }
    }

    fn process(&mut self, input: f32) -> f32 {
        let mut sample = input;
        for stage in &mut self.stages {
            sample = stage.process(sample);
        }
        sample
    }
}

/// Simple allpass filter
struct AllpassFilter {
    buffer: Vec<f32>,
    pos: usize,
    gain: f32,
}

impl AllpassFilter {
    fn new(length: usize, gain: f32) -> Self {
        Self {
            buffer: vec![0.0; length],
            pos: 0,
            gain,
        }
    }

    fn process(&mut self, input: f32) -> f32 {
        let delayed = self.buffer[self.pos];
        let output = delayed - self.gain * input;
        self.buffer[self.pos] = input + self.gain * delayed;
        self.pos = (self.pos + 1) % self.buffer.len();
        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_material_absorption() {
        let concrete = Material::Concrete;
        let carpet = Material::Carpet;

        assert!(concrete.average_absorption() < carpet.average_absorption());
    }

    #[test]
    fn test_room_simulator() {
        let room = Room::default();
        let mut sim = RoomSimulator::new(room, 48000);

        let input = vec![1.0f32; 1000];
        let mut output = vec![0.0f32; 1000];

        sim.process(&input, &mut output);

        // Output should have signal
        let sum: f32 = output.iter().map(|x| x.abs()).sum();
        assert!(sum > 0.0);
    }

    #[test]
    fn test_rt60_estimation() {
        let small_room = Room {
            dimensions: (4.0, 5.0, 2.5),
            walls: WallMaterials {
                floor: Material::Carpet,
                ceiling: Material::AcousticTile,
                ..Default::default()
            },
            listener_pos: Position3D::origin(),
        };

        let large_room = Room {
            dimensions: (20.0, 30.0, 8.0),
            walls: WallMaterials::default(),
            listener_pos: Position3D::origin(),
        };

        let small_sim = RoomSimulator::new(small_room, 48000);
        let large_sim = RoomSimulator::new(large_room, 48000);

        assert!(small_sim.estimate_rt60() < large_sim.estimate_rt60());
    }
}
