//! Utility functions and helpers

use wasm_bindgen::prelude::*;

/// Get WASM module version.
#[wasm_bindgen]
pub fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Check if module is ready.
#[wasm_bindgen]
pub fn is_ready() -> bool {
    true
}

/// Benchmark: process empty buffer to measure overhead.
#[wasm_bindgen]
pub fn benchmark_overhead(iterations: u32) -> f64 {
    let start = js_sys::Date::now();

    let mut dummy = 0.0f32;
    for i in 0..iterations {
        dummy += (i as f32).sin();
    }

    let end = js_sys::Date::now();

    // Prevent optimization
    if dummy > f32::MAX {
        return -1.0;
    }

    end - start
}

/// Fill buffer with test tone (sine wave).
#[wasm_bindgen]
pub fn fill_test_tone(buffer: &mut [f32], frequency: f32, sample_rate: f32, amplitude: f32) {
    let len = buffer.len() / 2;
    let phase_inc = 2.0 * std::f32::consts::PI * frequency / sample_rate;

    for i in 0..len {
        let idx = i * 2;
        let sample = (phase_inc * i as f32).sin() * amplitude;
        buffer[idx] = sample;     // L
        buffer[idx + 1] = sample; // R
    }
}

/// Generate white noise (for testing).
#[wasm_bindgen]
pub fn fill_white_noise(buffer: &mut [f32], amplitude: f32) {
    // Simple LCG PRNG
    let mut seed: u32 = 12345;

    for sample in buffer.iter_mut() {
        seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
        let rand = ((seed >> 16) as f32 / 32768.0) - 1.0;
        *sample = rand * amplitude;
    }
}
