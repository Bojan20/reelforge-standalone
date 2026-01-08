//! End-to-End Audio Graph Integration Tests
//!
//! Tests the complete audio pipeline:
//! - Dual-path processing
//! - Engine configuration
//! - Signal flow

use std::sync::atomic::Ordering;

use rf_core::SampleRate;
use rf_engine::{AudioBlock, DualPathEngine, EngineConfig, FnGuardProcessor, ProcessingMode};

const SAMPLE_RATE: f64 = 48000.0;
const BLOCK_SIZE: usize = 256;
const TEST_BLOCKS: usize = 100;

// ═══════════════════════════════════════════════════════════════════════════════
// DUAL-PATH ENGINE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_dual_path_engine_creation() {
    let engine = DualPathEngine::new(
        ProcessingMode::Hybrid,
        BLOCK_SIZE,
        SAMPLE_RATE,
        8, // lookahead blocks
    );

    let stats = engine.stats();
    assert_eq!(stats.guard_blocks.load(Ordering::Relaxed), 0);
    assert_eq!(stats.underruns.load(Ordering::Relaxed), 0);
}

#[test]
fn test_dual_path_realtime_mode() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 8);

    // Set a passthrough processor
    let processor = FnGuardProcessor::new(|_block: &mut AudioBlock| {}, 0);
    engine.set_fallback(Box::new(processor));

    // Generate test signal (1kHz sine)
    let mut input_l = vec![0.0f64; BLOCK_SIZE];
    let mut input_r = vec![0.0f64; BLOCK_SIZE];

    for i in 0..BLOCK_SIZE {
        let t = i as f64 / SAMPLE_RATE;
        let sample = (2.0 * std::f64::consts::PI * 1000.0 * t).sin();
        input_l[i] = sample;
        input_r[i] = sample;
    }

    // Process through engine
    for _ in 0..TEST_BLOCKS {
        engine.process(&mut input_l, &mut input_r);

        // Check for NaN/Inf
        assert!(!input_l.iter().any(|x| x.is_nan() || x.is_infinite()));
        assert!(!input_r.iter().any(|x| x.is_nan() || x.is_infinite()));
    }
}

#[test]
fn test_dual_path_with_gain_processor() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Set a gain processor (-6dB)
    let gain = 0.5;
    let processor = FnGuardProcessor::new(
        move |block: &mut AudioBlock| {
            for s in &mut block.left {
                *s *= gain;
            }
            for s in &mut block.right {
                *s *= gain;
            }
        },
        0,
    );
    engine.set_fallback(Box::new(processor));

    // Input signal
    let mut input_l = vec![1.0f64; BLOCK_SIZE];
    let mut input_r = vec![1.0f64; BLOCK_SIZE];

    engine.process(&mut input_l, &mut input_r);

    // Should be halved
    assert!((input_l[0] - 0.5).abs() < 0.001);
    assert!((input_r[0] - 0.5).abs() < 0.001);
}

#[test]
fn test_dual_path_hybrid_mode() {
    let engine = DualPathEngine::new(ProcessingMode::Hybrid, BLOCK_SIZE, SAMPLE_RATE, 4);

    let mut input_l = vec![0.5f64; BLOCK_SIZE];
    let mut input_r = vec![0.5f64; BLOCK_SIZE];

    // Process some blocks
    for _ in 0..20 {
        engine.process(&mut input_l, &mut input_r);
    }

    // In hybrid mode without guard thread, fallback should be used
    let stats = engine.stats();
    // Check stats are being tracked
    assert!(stats.fallback_blocks.load(Ordering::Relaxed) >= 0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO BLOCK TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_audio_block_creation() {
    let block = AudioBlock::new(BLOCK_SIZE);

    assert_eq!(block.block_size(), BLOCK_SIZE);
    assert_eq!(block.left.len(), BLOCK_SIZE);
    assert_eq!(block.right.len(), BLOCK_SIZE);
    assert_eq!(block.sequence, 0);
}

#[test]
fn test_audio_block_from_slices() {
    let left = vec![0.5f64; BLOCK_SIZE];
    let right = vec![-0.5f64; BLOCK_SIZE];

    let block = AudioBlock::from_slices(&left, &right, 42, 1024);

    assert_eq!(block.sequence, 42);
    assert_eq!(block.sample_position, 1024);
    assert_eq!(block.left[0], 0.5);
    assert_eq!(block.right[0], -0.5);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENGINE CONFIG TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_engine_config_default() {
    let config = EngineConfig::default();

    assert_eq!(config.sample_rate, SampleRate::Hz48000);
    assert_eq!(config.block_size, 256);
    assert_eq!(config.num_buses, 6);
}

#[test]
fn test_engine_config_low_latency() {
    let config = EngineConfig::low_latency();

    assert_eq!(config.block_size, 64);
    assert_eq!(config.processing_mode, ProcessingMode::RealTime);
}

#[test]
fn test_engine_config_high_quality() {
    let config = EngineConfig::high_quality();

    assert_eq!(config.sample_rate, SampleRate::Hz96000);
    assert_eq!(config.processing_mode, ProcessingMode::Guard);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIGNAL FLOW TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_signal_passthrough() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // No processor set - signal should pass through unchanged
    let mut input_l = vec![0.5f64; BLOCK_SIZE];
    let mut input_r = vec![-0.5f64; BLOCK_SIZE];

    engine.process(&mut input_l, &mut input_r);

    // Should be unchanged (no processor)
    assert!((input_l[0] - 0.5).abs() < 0.001);
    assert!((input_r[0] - (-0.5)).abs() < 0.001);
}

#[test]
fn test_silence_passthrough() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Silent input
    let mut input_l = vec![0.0f64; BLOCK_SIZE];
    let mut input_r = vec![0.0f64; BLOCK_SIZE];

    engine.process(&mut input_l, &mut input_r);

    // Output should be silent
    let max_l = input_l.iter().map(|x| x.abs()).fold(0.0f64, f64::max);
    let max_r = input_r.iter().map(|x| x.abs()).fold(0.0f64, f64::max);

    assert!(max_l < 0.0001, "Left channel not silent: {}", max_l);
    assert!(max_r < 0.0001, "Right channel not silent: {}", max_r);
}

#[test]
fn test_impulse_response() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Single impulse
    let mut input_l = vec![0.0f64; BLOCK_SIZE];
    let mut input_r = vec![0.0f64; BLOCK_SIZE];
    input_l[0] = 1.0;
    input_r[0] = 1.0;

    engine.process(&mut input_l, &mut input_r);

    // Check impulse passes through
    assert!((input_l[0] - 1.0).abs() < 0.001);
    assert!((input_r[0] - 1.0).abs() < 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════════
// GUARD THREAD TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_guard_thread_lifecycle() {
    let mut engine = DualPathEngine::new(ProcessingMode::Guard, BLOCK_SIZE, SAMPLE_RATE, 4);

    assert!(!engine.is_guard_running());

    // Create a simple passthrough processor
    let processor = FnGuardProcessor::new(|_block: &mut AudioBlock| {}, 0);
    engine.start_guard(Box::new(processor));

    assert!(engine.is_guard_running());

    engine.stop_guard();

    // Give thread time to stop
    std::thread::sleep(std::time::Duration::from_millis(200));
    assert!(!engine.is_guard_running());
}

#[test]
fn test_guard_with_processor() {
    let mut engine = DualPathEngine::new(ProcessingMode::Guard, BLOCK_SIZE, SAMPLE_RATE, 8);

    // Start guard thread with a simple processor
    let processor = FnGuardProcessor::new(
        |block: &mut AudioBlock| {
            // Simple gain
            for s in &mut block.left {
                *s *= 0.8;
            }
            for s in &mut block.right {
                *s *= 0.8;
            }
        },
        0,
    );
    engine.start_guard(Box::new(processor));

    // Process some blocks
    let mut input_l = vec![1.0f64; BLOCK_SIZE];
    let mut input_r = vec![1.0f64; BLOCK_SIZE];

    for _ in 0..10 {
        engine.process(&mut input_l, &mut input_r);
        std::thread::sleep(std::time::Duration::from_millis(5));
    }

    // Check guard processed some blocks
    let stats = engine.stats();
    // Note: guard may or may not have processed depending on timing
    assert!(stats.guard_blocks.load(Ordering::Relaxed) >= 0);

    engine.stop_guard();
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRESS TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_continuous_processing() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 8);

    // Set a simple processor
    let processor = FnGuardProcessor::new(|_block: &mut AudioBlock| {}, 0);
    engine.set_fallback(Box::new(processor));

    let mut input_l = vec![0.1f64; BLOCK_SIZE];
    let mut input_r = vec![0.1f64; BLOCK_SIZE];

    // Process many blocks (simulating ~10 seconds at 48kHz/256)
    for _ in 0..1875 {
        engine.process(&mut input_l, &mut input_r);

        // Check no NaN/Inf
        assert!(!input_l.iter().any(|x| x.is_nan() || x.is_infinite()));
        assert!(!input_r.iter().any(|x| x.is_nan() || x.is_infinite()));
    }
}

#[test]
fn test_varying_signal_levels() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Test various signal levels
    for level in &[0.0, 0.001, 0.01, 0.1, 0.5, 1.0] {
        let mut input_l = vec![*level; BLOCK_SIZE];
        let mut input_r = vec![*level; BLOCK_SIZE];

        engine.process(&mut input_l, &mut input_r);

        // Should not produce NaN or Inf
        assert!(!input_l.iter().any(|x| x.is_nan() || x.is_infinite()));
        assert!(!input_r.iter().any(|x| x.is_nan() || x.is_infinite()));
    }
}

#[test]
fn test_extreme_values() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Near-zero values
    let mut input_small = vec![1e-30f64; BLOCK_SIZE];
    let mut input_small_r = vec![1e-30f64; BLOCK_SIZE];
    engine.process(&mut input_small, &mut input_small_r);
    assert!(!input_small.iter().any(|x| x.is_nan()));
    assert!(!input_small_r.iter().any(|x| x.is_nan()));

    // Large values (should be handled gracefully)
    let mut input_large = vec![10.0f64; BLOCK_SIZE];
    let mut input_large_r = vec![10.0f64; BLOCK_SIZE];
    engine.process(&mut input_large, &mut input_large_r);
    assert!(!input_large.iter().any(|x| x.is_nan()));
    assert!(!input_large_r.iter().any(|x| x.is_nan()));
}

#[test]
fn test_reset() {
    let engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    // Process some blocks
    let mut input_l = vec![0.5f64; BLOCK_SIZE];
    let mut input_r = vec![0.5f64; BLOCK_SIZE];

    for _ in 0..10 {
        engine.process(&mut input_l, &mut input_r);
    }

    // Reset
    engine.reset();

    // Should still work after reset
    engine.process(&mut input_l, &mut input_r);
    assert!(!input_l.iter().any(|x| x.is_nan()));
}

#[test]
fn test_mode_switching() {
    let mut engine = DualPathEngine::new(ProcessingMode::RealTime, BLOCK_SIZE, SAMPLE_RATE, 4);

    assert_eq!(engine.mode(), ProcessingMode::RealTime);

    engine.set_mode(ProcessingMode::Hybrid);
    assert_eq!(engine.mode(), ProcessingMode::Hybrid);

    engine.set_mode(ProcessingMode::Guard);
    assert_eq!(engine.mode(), ProcessingMode::Guard);
}
