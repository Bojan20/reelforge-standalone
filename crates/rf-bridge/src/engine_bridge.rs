//! Engine bridge internals

use crate::EngineBridge;

impl EngineBridge {
    /// Process a single audio block (called from audio thread)
    pub fn process_block(&mut self, input_l: &[f32], input_r: &[f32], output_l: &mut [f32], output_r: &mut [f32]) {
        // Update position
        if self.transport.is_playing {
            let samples_per_block = output_l.len() as u64;
            self.transport.position_samples += samples_per_block;
            self.transport.position_seconds =
                self.transport.position_samples as f64 / self.config.sample_rate.as_f64();

            // Loop handling
            if self.transport.loop_enabled {
                if self.transport.position_seconds >= self.transport.loop_end {
                    self.transport.position_seconds = self.transport.loop_start;
                    self.transport.position_samples =
                        (self.transport.loop_start * self.config.sample_rate.as_f64()) as u64;
                }
            }
        }

        // TODO: Route through DualPathEngine
        // For now, pass through with gain
        let gain = 1.0f32;
        for (i, (out_l, out_r)) in output_l.iter_mut().zip(output_r.iter_mut()).enumerate() {
            *out_l = input_l.get(i).copied().unwrap_or(0.0) * gain;
            *out_r = input_r.get(i).copied().unwrap_or(0.0) * gain;
        }

        // Update metering (peak detection)
        self.update_metering(output_l, output_r);
    }

    /// Update metering values from processed audio
    fn update_metering(&mut self, left: &[f32], right: &[f32]) {
        let peak_l = left.iter().fold(0.0f32, |acc, &s| acc.max(s.abs()));
        let peak_r = right.iter().fold(0.0f32, |acc, &s| acc.max(s.abs()));

        // Simple peak hold with decay
        const DECAY: f32 = 0.9995;
        self.metering.master_peak_l = (self.metering.master_peak_l * DECAY).max(peak_l);
        self.metering.master_peak_r = (self.metering.master_peak_r * DECAY).max(peak_r);

        // RMS calculation
        let rms_l = (left.iter().map(|s| s * s).sum::<f32>() / left.len() as f32).sqrt();
        let rms_r = (right.iter().map(|s| s * s).sum::<f32>() / right.len() as f32).sqrt();

        // Smooth RMS
        const SMOOTH: f32 = 0.3;
        self.metering.master_rms_l = self.metering.master_rms_l * (1.0 - SMOOTH) + rms_l * SMOOTH;
        self.metering.master_rms_r = self.metering.master_rms_r * (1.0 - SMOOTH) + rms_r * SMOOTH;
    }
}
