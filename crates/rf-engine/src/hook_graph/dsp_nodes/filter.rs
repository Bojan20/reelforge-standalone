//! Biquad filter node — TDF-II implementation (matches rf-dsp convention).
//! Supports LP, HP, BP, notch, peak EQ, shelves.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FilterType {
    Lowpass = 0,
    Highpass = 1,
    Bandpass = 2,
    Notch = 3,
    PeakEQ = 4,
    LowShelf = 5,
    HighShelf = 6,
}

impl FilterType {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::Highpass,
            2 => Self::Bandpass,
            3 => Self::Notch,
            4 => Self::PeakEQ,
            5 => Self::LowShelf,
            6 => Self::HighShelf,
            _ => Self::Lowpass,
        }
    }
}

pub struct FilterNode {
    filter_type: FilterType,
    freq: f32,
    q: f32,
    gain_db: f32,
    // TDF-II state (stereo)
    z1_l: f64,
    z2_l: f64,
    z1_r: f64,
    z2_r: f64,
    // Coefficients
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    needs_recalc: bool,
    last_sample_rate: u32,
}

impl FilterNode {
    pub fn new(filter_type: FilterType, freq: f32, q: f32, gain_db: f32) -> Self {
        let mut node = Self {
            filter_type,
            freq: freq.clamp(20.0, 20000.0),
            q: q.clamp(0.1, 30.0),
            gain_db,
            z1_l: 0.0, z2_l: 0.0,
            z1_r: 0.0, z2_r: 0.0,
            b0: 1.0, b1: 0.0, b2: 0.0,
            a1: 0.0, a2: 0.0,
            needs_recalc: true,
            last_sample_rate: 0,
        };
        node
    }

    pub fn set_params(&mut self, freq: f32, q: f32, gain_db: f32) {
        self.freq = freq.clamp(20.0, 20000.0);
        self.q = q.clamp(0.1, 30.0);
        self.gain_db = gain_db;
        self.needs_recalc = true;
    }

    fn recalc_coefficients(&mut self, sample_rate: u32) {
        let sr = sample_rate as f64;
        let w0 = 2.0 * std::f64::consts::PI * self.freq as f64 / sr;
        let cos_w0 = w0.cos();
        let sin_w0 = w0.sin();
        let alpha = sin_w0 / (2.0 * self.q as f64);
        let a_lin = 10.0_f64.powf(self.gain_db as f64 / 40.0);

        let (b0, b1, b2, a0, a1, a2) = match self.filter_type {
            FilterType::Lowpass => {
                let b1 = 1.0 - cos_w0;
                let b0 = b1 / 2.0;
                (b0, b1, b0, 1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha)
            }
            FilterType::Highpass => {
                let b1 = -(1.0 + cos_w0);
                let b0 = (1.0 + cos_w0) / 2.0;
                (b0, b1, b0, 1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha)
            }
            FilterType::Bandpass => {
                (alpha, 0.0, -alpha, 1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha)
            }
            FilterType::Notch => {
                (1.0, -2.0 * cos_w0, 1.0, 1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha)
            }
            FilterType::PeakEQ => {
                (
                    1.0 + alpha * a_lin,
                    -2.0 * cos_w0,
                    1.0 - alpha * a_lin,
                    1.0 + alpha / a_lin,
                    -2.0 * cos_w0,
                    1.0 - alpha / a_lin,
                )
            }
            FilterType::LowShelf => {
                let two_sqrt_a_alpha = 2.0 * a_lin.sqrt() * alpha;
                (
                    a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cos_w0 + two_sqrt_a_alpha),
                    2.0 * a_lin * ((a_lin - 1.0) - (a_lin + 1.0) * cos_w0),
                    a_lin * ((a_lin + 1.0) - (a_lin - 1.0) * cos_w0 - two_sqrt_a_alpha),
                    (a_lin + 1.0) + (a_lin - 1.0) * cos_w0 + two_sqrt_a_alpha,
                    -2.0 * ((a_lin - 1.0) + (a_lin + 1.0) * cos_w0),
                    (a_lin + 1.0) + (a_lin - 1.0) * cos_w0 - two_sqrt_a_alpha,
                )
            }
            FilterType::HighShelf => {
                let two_sqrt_a_alpha = 2.0 * a_lin.sqrt() * alpha;
                (
                    a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cos_w0 + two_sqrt_a_alpha),
                    -2.0 * a_lin * ((a_lin - 1.0) + (a_lin + 1.0) * cos_w0),
                    a_lin * ((a_lin + 1.0) + (a_lin - 1.0) * cos_w0 - two_sqrt_a_alpha),
                    (a_lin + 1.0) - (a_lin - 1.0) * cos_w0 + two_sqrt_a_alpha,
                    2.0 * ((a_lin - 1.0) - (a_lin + 1.0) * cos_w0),
                    (a_lin + 1.0) - (a_lin - 1.0) * cos_w0 - two_sqrt_a_alpha,
                )
            }
        };

        let inv_a0 = 1.0 / a0;
        self.b0 = b0 * inv_a0;
        self.b1 = b1 * inv_a0;
        self.b2 = b2 * inv_a0;
        self.a1 = a1 * inv_a0;
        self.a2 = a2 * inv_a0;
        self.needs_recalc = false;
        self.last_sample_rate = sample_rate;
    }

    #[inline(always)]
    fn process_sample_tdf2(
        x: f64,
        b0: f64, b1: f64, b2: f64,
        a1: f64, a2: f64,
        z1: &mut f64, z2: &mut f64,
    ) -> f64 {
        let y = b0 * x + *z1;
        *z1 = b1 * x - a1 * y + *z2;
        *z2 = b2 * x - a2 * y;
        y
    }
}

impl AudioNode for FilterNode {
    fn type_id(&self) -> &'static str { "Filter" }

    fn process(
        &mut self,
        inputs: &[&AudioBuffer],
        output: &mut AudioBuffer,
        ctx: &NodeContext,
    ) {
        let input = match inputs.first() {
            Some(i) => *i,
            None => { output.clear(); return; }
        };

        if self.needs_recalc || self.last_sample_rate != ctx.sample_rate {
            self.recalc_coefficients(ctx.sample_rate);
        }

        for i in 0..output.frames {
            output.left[i] = Self::process_sample_tdf2(
                input.left[i] as f64,
                self.b0, self.b1, self.b2, self.a1, self.a2,
                &mut self.z1_l, &mut self.z2_l,
            ) as f32;
            output.right[i] = Self::process_sample_tdf2(
                input.right[i] as f64,
                self.b0, self.b1, self.b2, self.a1, self.a2,
                &mut self.z1_r, &mut self.z2_r,
            ) as f32;
        }
    }

    fn reset(&mut self) {
        self.z1_l = 0.0; self.z2_l = 0.0;
        self.z1_r = 0.0; self.z2_r = 0.0;
    }
}
