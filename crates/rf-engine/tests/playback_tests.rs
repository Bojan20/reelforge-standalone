//! PlaybackEngine Integration Tests
//!
//! Tests for:
//! - Voice creation and playback lifecycle
//! - Bus routing (6 buses: Master=0, Music=1, Sfx=2, Voice=3, Ambience=4, Aux=5)
//! - Voice stealing (when MAX_ONE_SHOT_VOICES=32 exceeded)
//! - Volume/pan parameter setting and clamping
//! - Mute/Solo state management
//! - Fade-out operations
//! - Section-based playback filtering
//! - Audio cache insertion and retrieval

use rf_engine::{
    AudioCache, ImportedAudio, PlaybackEngine, TrackManager,
    playback::{PlaybackSource, VoicePoolStats},
};
use std::sync::Arc;

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

const TEST_SAMPLE_RATE: u32 = 48000;

/// Create a PlaybackEngine with default TrackManager for testing.
fn create_test_engine() -> PlaybackEngine {
    let track_manager = Arc::new(TrackManager::new());
    PlaybackEngine::new(track_manager, TEST_SAMPLE_RATE)
}

/// Create synthetic stereo ImportedAudio (1 second of silence).
fn create_test_audio(name: &str) -> Arc<ImportedAudio> {
    let num_frames = TEST_SAMPLE_RATE as usize;
    let samples = vec![0.0f32; num_frames * 2]; // stereo interleaved
    Arc::new(ImportedAudio {
        samples,
        sample_rate: TEST_SAMPLE_RATE,
        channels: 2,
        duration_secs: 1.0,
        sample_count: num_frames,
        source_path: format!("/test/{}.wav", name),
        name: format!("{}.wav", name),
        bit_depth: Some(16),
        format: "wav".to_string(),
    })
}

/// Insert synthetic audio into the engine cache and return the path key.
fn insert_test_audio(engine: &PlaybackEngine, name: &str) -> String {
    let audio = create_test_audio(name);
    let path = audio.source_path.clone();
    engine.cache().insert(path.clone(), audio);
    path
}

// ═══════════════════════════════════════════════════════════════════════════════
// ENGINE CONSTRUCTION
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_engine_construction_defaults() {
    let engine = create_test_engine();

    // Master volume defaults to 1.0
    assert!(
        (engine.master_volume() - 1.0).abs() < f64::EPSILON,
        "Default master volume should be 1.0, got {}",
        engine.master_volume()
    );

    // Default active section is Daw
    assert_eq!(
        engine.get_active_section(),
        PlaybackSource::Daw,
        "Default active section should be Daw"
    );

    // Voice pool should start empty
    let stats = engine.get_voice_pool_stats();
    assert_eq!(stats.active_count, 0, "Should start with 0 active voices");
    assert_eq!(stats.max_voices, 32, "Max voices should be 32");
    assert_eq!(stats.looping_count, 0, "Should start with 0 looping voices");

    // Position should start at 0
    assert_eq!(engine.position_samples(), 0);
    assert!((engine.position_seconds() - 0.0).abs() < f64::EPSILON);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MASTER VOLUME
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_master_volume_set_and_get() {
    let engine = create_test_engine();

    engine.set_master_volume(0.75);
    assert!(
        (engine.master_volume() - 0.75).abs() < f64::EPSILON,
        "Master volume should be 0.75"
    );

    engine.set_master_volume(0.0);
    assert!(
        (engine.master_volume() - 0.0).abs() < f64::EPSILON,
        "Master volume should be 0.0"
    );

    engine.set_master_volume(1.5);
    assert!(
        (engine.master_volume() - 1.5).abs() < f64::EPSILON,
        "Master volume should accept 1.5 (max)"
    );
}

#[test]
fn test_master_volume_clamping() {
    let engine = create_test_engine();

    // Above max (1.5) should clamp
    engine.set_master_volume(5.0);
    assert!(
        (engine.master_volume() - 1.5).abs() < f64::EPSILON,
        "Master volume should clamp to 1.5, got {}",
        engine.master_volume()
    );

    // Below min (0.0) should clamp
    engine.set_master_volume(-1.0);
    assert!(
        (engine.master_volume() - 0.0).abs() < f64::EPSILON,
        "Master volume should clamp to 0.0, got {}",
        engine.master_volume()
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUS STATE — VOLUME
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bus_volume_defaults() {
    let engine = create_test_engine();

    // All 6 buses should default to volume=1.0
    for bus_idx in 0..6 {
        let state = engine.get_bus_state(bus_idx).expect("Bus should exist");
        assert!(
            (state.volume - 1.0).abs() < f64::EPSILON,
            "Bus {} default volume should be 1.0, got {}",
            bus_idx,
            state.volume
        );
    }
}

#[test]
fn test_bus_volume_set_per_bus() {
    let engine = create_test_engine();

    let test_volumes = [0.0, 0.25, 0.5, 0.75, 1.0, 1.5];

    for (bus_idx, &volume) in test_volumes.iter().enumerate() {
        engine.set_bus_volume(bus_idx, volume);
        let state = engine.get_bus_state(bus_idx).expect("Bus should exist");
        assert!(
            (state.volume - volume).abs() < f64::EPSILON,
            "Bus {} volume should be {}, got {}",
            bus_idx,
            volume,
            state.volume
        );
    }
}

#[test]
fn test_bus_volume_clamping() {
    let engine = create_test_engine();

    engine.set_bus_volume(0, 3.0);
    let state = engine.get_bus_state(0).expect("Bus should exist");
    assert!(
        (state.volume - 1.5).abs() < f64::EPSILON,
        "Bus volume should clamp to 1.5, got {}",
        state.volume
    );

    engine.set_bus_volume(0, -0.5);
    let state = engine.get_bus_state(0).expect("Bus should exist");
    assert!(
        (state.volume - 0.0).abs() < f64::EPSILON,
        "Bus volume should clamp to 0.0, got {}",
        state.volume
    );
}

#[test]
fn test_bus_volume_independence() {
    let engine = create_test_engine();

    // Set different volumes per bus
    engine.set_bus_volume(0, 0.1);
    engine.set_bus_volume(1, 0.3);
    engine.set_bus_volume(2, 0.5);
    engine.set_bus_volume(3, 0.7);
    engine.set_bus_volume(4, 0.9);
    engine.set_bus_volume(5, 1.1);

    // Verify each is independent
    let expected = [0.1, 0.3, 0.5, 0.7, 0.9, 1.1];
    for (bus_idx, &exp) in expected.iter().enumerate() {
        let state = engine.get_bus_state(bus_idx).unwrap();
        assert!(
            (state.volume - exp).abs() < 1e-10,
            "Bus {} volume should be {}, got {}",
            bus_idx,
            exp,
            state.volume
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUS STATE — PAN
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bus_pan_defaults() {
    let engine = create_test_engine();

    for bus_idx in 0..6 {
        let state = engine.get_bus_state(bus_idx).unwrap();
        assert!(
            (state.pan - 0.0).abs() < f64::EPSILON,
            "Bus {} default pan should be 0.0 (center), got {}",
            bus_idx,
            state.pan
        );
        assert!(
            (state.pan_right - 0.0).abs() < f64::EPSILON,
            "Bus {} default pan_right should be 0.0, got {}",
            bus_idx,
            state.pan_right
        );
    }
}

#[test]
fn test_bus_pan_set_and_get() {
    let engine = create_test_engine();

    // Full left
    engine.set_bus_pan(0, -1.0);
    assert!((engine.get_bus_state(0).unwrap().pan - (-1.0)).abs() < f64::EPSILON);

    // Center
    engine.set_bus_pan(1, 0.0);
    assert!((engine.get_bus_state(1).unwrap().pan - 0.0).abs() < f64::EPSILON);

    // Full right
    engine.set_bus_pan(2, 1.0);
    assert!((engine.get_bus_state(2).unwrap().pan - 1.0).abs() < f64::EPSILON);
}

#[test]
fn test_bus_pan_clamping() {
    let engine = create_test_engine();

    engine.set_bus_pan(0, 5.0);
    assert!((engine.get_bus_state(0).unwrap().pan - 1.0).abs() < f64::EPSILON);

    engine.set_bus_pan(0, -5.0);
    assert!((engine.get_bus_state(0).unwrap().pan - (-1.0)).abs() < f64::EPSILON);
}

#[test]
fn test_bus_pan_right_stereo_dual_pan() {
    let engine = create_test_engine();

    // Set independent L/R pan values
    engine.set_bus_pan(0, -0.5); // L channel panned slightly left
    engine.set_bus_pan_right(0, 0.5); // R channel panned slightly right

    let state = engine.get_bus_state(0).unwrap();
    assert!((state.pan - (-0.5)).abs() < f64::EPSILON);
    assert!((state.pan_right - 0.5).abs() < f64::EPSILON);
}

#[test]
fn test_bus_pan_right_clamping() {
    let engine = create_test_engine();

    engine.set_bus_pan_right(0, 2.0);
    assert!((engine.get_bus_state(0).unwrap().pan_right - 1.0).abs() < f64::EPSILON);

    engine.set_bus_pan_right(0, -2.0);
    assert!((engine.get_bus_state(0).unwrap().pan_right - (-1.0)).abs() < f64::EPSILON);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUS STATE — MUTE / SOLO
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bus_mute_defaults() {
    let engine = create_test_engine();

    for bus_idx in 0..6 {
        let state = engine.get_bus_state(bus_idx).unwrap();
        assert!(
            !state.muted,
            "Bus {} should not be muted by default",
            bus_idx
        );
    }
}

#[test]
fn test_bus_mute_toggle() {
    let engine = create_test_engine();

    // Mute bus 2
    engine.set_bus_mute(2, true);
    assert!(engine.get_bus_state(2).unwrap().muted);
    // Other buses should not be affected
    assert!(!engine.get_bus_state(0).unwrap().muted);
    assert!(!engine.get_bus_state(1).unwrap().muted);

    // Unmute bus 2
    engine.set_bus_mute(2, false);
    assert!(!engine.get_bus_state(2).unwrap().muted);
}

#[test]
fn test_bus_solo_defaults() {
    let engine = create_test_engine();

    for bus_idx in 0..6 {
        let state = engine.get_bus_state(bus_idx).unwrap();
        assert!(
            !state.soloed,
            "Bus {} should not be soloed by default",
            bus_idx
        );
    }
}

#[test]
fn test_bus_solo_toggle() {
    let engine = create_test_engine();

    // Solo bus 1
    engine.set_bus_solo(1, true);
    assert!(engine.get_bus_state(1).unwrap().soloed);

    // Solo bus 3
    engine.set_bus_solo(3, true);
    assert!(engine.get_bus_state(3).unwrap().soloed);

    // Unsolo bus 1
    engine.set_bus_solo(1, false);
    assert!(!engine.get_bus_state(1).unwrap().soloed);
    assert!(engine.get_bus_state(3).unwrap().soloed); // Bus 3 still soloed
}

#[test]
fn test_bus_mute_and_solo_combined() {
    let engine = create_test_engine();

    engine.set_bus_mute(0, true);
    engine.set_bus_solo(0, true);

    let state = engine.get_bus_state(0).unwrap();
    assert!(state.muted);
    assert!(state.soloed);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUS STATE — OUT OF BOUNDS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bus_state_invalid_index() {
    let engine = create_test_engine();

    // Bus index 6 is out of range (valid: 0-5)
    assert!(engine.get_bus_state(6).is_none());
    assert!(engine.get_bus_state(100).is_none());
    assert!(engine.get_bus_state(usize::MAX).is_none());
}

#[test]
fn test_bus_operations_on_invalid_index_are_silent() {
    let engine = create_test_engine();

    // These should not panic
    engine.set_bus_volume(99, 0.5);
    engine.set_bus_pan(99, 0.5);
    engine.set_bus_pan_right(99, 0.5);
    engine.set_bus_mute(99, true);
    engine.set_bus_solo(99, true);

    // Verify valid buses are unaffected
    for bus_idx in 0..6 {
        let state = engine.get_bus_state(bus_idx).unwrap();
        assert!((state.volume - 1.0).abs() < f64::EPSILON);
        assert!((state.pan - 0.0).abs() < f64::EPSILON);
        assert!(!state.muted);
        assert!(!state.soloed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION-BASED PLAYBACK FILTERING
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_active_section_default() {
    let engine = create_test_engine();
    assert_eq!(engine.get_active_section(), PlaybackSource::Daw);
}

#[test]
fn test_active_section_set_and_get() {
    let engine = create_test_engine();

    engine.set_active_section(PlaybackSource::SlotLab);
    assert_eq!(engine.get_active_section(), PlaybackSource::SlotLab);

    engine.set_active_section(PlaybackSource::Middleware);
    assert_eq!(engine.get_active_section(), PlaybackSource::Middleware);

    engine.set_active_section(PlaybackSource::Browser);
    assert_eq!(engine.get_active_section(), PlaybackSource::Browser);

    engine.set_active_section(PlaybackSource::Daw);
    assert_eq!(engine.get_active_section(), PlaybackSource::Daw);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYBACK SOURCE CONVERSION
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_playback_source_from_u8() {
    assert_eq!(PlaybackSource::from(0), PlaybackSource::Daw);
    assert_eq!(PlaybackSource::from(1), PlaybackSource::SlotLab);
    assert_eq!(PlaybackSource::from(2), PlaybackSource::Middleware);
    assert_eq!(PlaybackSource::from(3), PlaybackSource::Browser);

    // Invalid values default to Daw
    assert_eq!(PlaybackSource::from(4), PlaybackSource::Daw);
    assert_eq!(PlaybackSource::from(255), PlaybackSource::Daw);
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO CACHE
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_audio_cache_insert_and_load() {
    let cache = AudioCache::new();

    let audio = create_test_audio("test");
    let path = "/test/test.wav".to_string();
    cache.insert(path.clone(), audio.clone());

    let loaded = cache.load(&path);
    assert!(loaded.is_some(), "Cached audio should be retrievable");

    let loaded = loaded.unwrap();
    assert_eq!(loaded.sample_rate, TEST_SAMPLE_RATE);
    assert_eq!(loaded.channels, 2);
    assert_eq!(loaded.name, "test.wav");
}

#[test]
fn test_audio_cache_miss() {
    let cache = AudioCache::new();

    // Non-existent paths should return None (not panic)
    let result = cache.load("/nonexistent/audio.wav");
    assert!(result.is_none(), "Non-cached path should return None");
}

#[test]
fn test_audio_cache_clear() {
    let cache = AudioCache::new();

    cache.insert("/test/a.wav".to_string(), create_test_audio("a"));
    cache.insert("/test/b.wav".to_string(), create_test_audio("b"));

    assert!(cache.load("/test/a.wav").is_some());
    assert!(cache.load("/test/b.wav").is_some());

    cache.clear();

    assert!(
        cache.load("/test/a.wav").is_none(),
        "Cache should be cleared"
    );
    assert!(
        cache.load("/test/b.wav").is_none(),
        "Cache should be cleared"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ONE-SHOT VOICE LIFECYCLE — PLAY
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_play_one_shot_returns_nonzero_id() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "click");

    let voice_id = engine.play_one_shot_to_bus(
        &path,
        1.0, // volume
        0.0, // pan
        2,   // bus_id = Sfx
        PlaybackSource::SlotLab,
    );

    assert_ne!(
        voice_id, 0,
        "Successful play should return non-zero voice ID"
    );
}

#[test]
fn test_play_one_shot_ids_are_unique() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "click");

    let id1 = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);
    let id2 = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);
    let id3 = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    assert_ne!(id1, 0);
    assert_ne!(id2, 0);
    assert_ne!(id3, 0);
    assert_ne!(id1, id2, "Voice IDs should be unique");
    assert_ne!(id2, id3, "Voice IDs should be unique");
    assert_ne!(id1, id3, "Voice IDs should be unique");
}

#[test]
fn test_play_one_shot_invalid_path_returns_zero() {
    let engine = create_test_engine();

    let voice_id = engine.play_one_shot_to_bus(
        "/nonexistent/sound.wav",
        1.0,
        0.0,
        2,
        PlaybackSource::SlotLab,
    );

    assert_eq!(voice_id, 0, "Invalid path should return 0");
}

#[test]
fn test_play_looping_returns_nonzero_id() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "loop");

    let voice_id = engine.play_looping_to_bus(
        &path,
        0.8,
        0.0,
        1, // Music bus
        PlaybackSource::SlotLab,
    );

    assert_ne!(
        voice_id, 0,
        "Successful looping play should return non-zero voice ID"
    );
}

#[test]
fn test_play_one_shot_ex_returns_nonzero_id() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "extended");

    let voice_id = engine.play_one_shot_to_bus_ex(
        &path,
        0.9,  // volume
        -0.3, // pan
        2,    // bus_id = Sfx
        PlaybackSource::Middleware,
        50.0,  // fade_in_ms
        100.0, // fade_out_ms
        0.0,   // trim_start_ms
        500.0, // trim_end_ms
    );

    assert_ne!(voice_id, 0, "Extended play should return non-zero voice ID");
}

// ═══════════════════════════════════════════════════════════════════════════════
// ONE-SHOT VOICE — BUS ROUTING
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_play_one_shot_all_bus_ids() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "routed");

    // Test all valid bus IDs (0-5)
    for bus_id in 0..=5u32 {
        let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, bus_id, PlaybackSource::Daw);
        assert_ne!(voice_id, 0, "Play to bus {} should succeed", bus_id);
    }

    // Invalid bus ID should still succeed (defaults to Sfx)
    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 99, PlaybackSource::Daw);
    assert_ne!(
        voice_id, 0,
        "Invalid bus_id should default to Sfx, not fail"
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ONE-SHOT VOICE — STOP / FADE-OUT
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_stop_one_shot_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "stoppable");

    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    // Stop should not panic
    engine.stop_one_shot(voice_id);
}

#[test]
fn test_stop_nonexistent_voice_does_not_panic() {
    let engine = create_test_engine();

    // Stopping a voice that doesn't exist should be safe
    engine.stop_one_shot(0);
    engine.stop_one_shot(99999);
    engine.stop_one_shot(u64::MAX);
}

#[test]
fn test_stop_all_one_shots_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "mass_stop");

    // Queue several voices
    for _ in 0..5 {
        engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);
    }

    // Stop all should not panic
    engine.stop_all_one_shots();
}

#[test]
fn test_stop_source_one_shots_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "source_stop");

    engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);
    engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::Middleware);

    // Stop only SlotLab voices
    engine.stop_source_one_shots(PlaybackSource::SlotLab);
    // Stop only Middleware voices
    engine.stop_source_one_shots(PlaybackSource::Middleware);
}

#[test]
fn test_fade_out_one_shot_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "fadeable");

    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    // Fade-out with 50ms duration
    engine.fade_out_one_shot(voice_id, 50);
}

#[test]
fn test_fade_out_nonexistent_voice_does_not_panic() {
    let engine = create_test_engine();

    // Fade-out on nonexistent voice should be safe
    engine.fade_out_one_shot(0, 100);
    engine.fade_out_one_shot(99999, 200);
}

#[test]
fn test_fade_out_zero_duration() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "instant_fade");

    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    // Zero fade should not panic
    engine.fade_out_one_shot(voice_id, 0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ONE-SHOT VOICE — PITCH
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_set_voice_pitch_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "pitched");

    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    // Various pitch values within range
    engine.set_voice_pitch(voice_id, 0.0); // No shift
    engine.set_voice_pitch(voice_id, 12.0); // Octave up
    engine.set_voice_pitch(voice_id, -12.0); // Octave down
    engine.set_voice_pitch(voice_id, 24.0); // Max up
    engine.set_voice_pitch(voice_id, -24.0); // Max down
}

#[test]
fn test_set_voice_pitch_clamped_values() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "clamped_pitch");

    let voice_id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);

    // Values beyond -24..+24 should be sent clamped (not panic)
    engine.set_voice_pitch(voice_id, 100.0);
    engine.set_voice_pitch(voice_id, -100.0);
}

#[test]
fn test_set_voice_pitch_nonexistent_voice() {
    let engine = create_test_engine();

    // Pitch on nonexistent voice should be safe
    engine.set_voice_pitch(0, 5.0);
    engine.set_voice_pitch(99999, -3.0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE POOL STATS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_voice_pool_stats_empty() {
    let engine = create_test_engine();

    let stats = engine.get_voice_pool_stats();
    assert_eq!(stats.active_count, 0);
    assert_eq!(stats.max_voices, 32);
    assert_eq!(stats.looping_count, 0);
    assert_eq!(stats.daw_voices, 0);
    assert_eq!(stats.slotlab_voices, 0);
    assert_eq!(stats.middleware_voices, 0);
    assert_eq!(stats.browser_voices, 0);
    assert_eq!(stats.sfx_voices, 0);
    assert_eq!(stats.music_voices, 0);
    assert_eq!(stats.voice_voices, 0);
    assert_eq!(stats.ambience_voices, 0);
    assert_eq!(stats.aux_voices, 0);
    assert_eq!(stats.master_voices, 0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE STEALING — Commands queued but processing is internal
// The one-shot command ring buffer has capacity 256. We verify that
// queuing many voices does not panic and IDs remain unique.
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_queue_many_voices_does_not_panic() {
    let engine = create_test_engine();
    let path = insert_test_audio(&engine, "stress");

    let mut ids = Vec::new();
    // Queue more than MAX_ONE_SHOT_VOICES (32) voice commands.
    // The ring buffer holds 256, so 64 should fit fine.
    for _ in 0..64 {
        let id = engine.play_one_shot_to_bus(&path, 1.0, 0.0, 2, PlaybackSource::SlotLab);
        assert_ne!(id, 0, "Should not fail to queue voice command");
        ids.push(id);
    }

    // Verify all IDs are unique
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), 64, "All 64 voice IDs should be unique");
}

// ═══════════════════════════════════════════════════════════════════════════════
// VARISPEED CONTROL
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_varispeed_defaults() {
    let engine = create_test_engine();

    assert!(
        !engine.is_varispeed_enabled(),
        "Varispeed should be disabled by default"
    );
    assert!((engine.varispeed_rate() - 1.0).abs() < f64::EPSILON);
    assert!((engine.effective_playback_rate() - 1.0).abs() < f64::EPSILON);
}

#[test]
fn test_varispeed_enable_disable() {
    let engine = create_test_engine();

    engine.set_varispeed_enabled(true);
    assert!(engine.is_varispeed_enabled());

    engine.set_varispeed_rate(2.0);
    assert!((engine.effective_playback_rate() - 2.0).abs() < f64::EPSILON);

    engine.set_varispeed_enabled(false);
    assert!(!engine.is_varispeed_enabled());
    assert!(
        (engine.effective_playback_rate() - 1.0).abs() < f64::EPSILON,
        "Disabled varispeed should return 1.0"
    );
}

#[test]
fn test_varispeed_rate_clamping() {
    let engine = create_test_engine();

    engine.set_varispeed_rate(0.1); // Below min 0.25
    assert!((engine.varispeed_rate() - 0.25).abs() < f64::EPSILON);

    engine.set_varispeed_rate(10.0); // Above max 4.0
    assert!((engine.varispeed_rate() - 4.0).abs() < f64::EPSILON);
}

#[test]
fn test_varispeed_semitone_conversion() {
    // +12 semitones = 2x speed
    let rate = PlaybackEngine::semitones_to_varispeed(12.0);
    assert!((rate - 2.0).abs() < 1e-10);

    // -12 semitones = 0.5x speed
    let rate = PlaybackEngine::semitones_to_varispeed(-12.0);
    assert!((rate - 0.5).abs() < 1e-10);

    // 0 semitones = 1.0x speed
    let rate = PlaybackEngine::semitones_to_varispeed(0.0);
    assert!((rate - 1.0).abs() < 1e-10);

    // Round-trip conversion
    let semitones = PlaybackEngine::varispeed_to_semitones(2.0);
    assert!((semitones - 12.0).abs() < 1e-10);
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMPORTED AUDIO CONSTRUCTION
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_imported_audio_mono() {
    let samples = vec![0.0f32; 48000]; // 1 second mono at 48kHz
    let audio = ImportedAudio::new_mono(samples, 48000, "/test/mono.wav");

    assert_eq!(audio.channels, 1);
    assert_eq!(audio.sample_rate, 48000);
    assert_eq!(audio.sample_count, 48000);
    assert!((audio.duration_secs - 1.0).abs() < 1e-6);
    assert_eq!(audio.name, "mono.wav");
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDGE CASES
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bus_state_full_cycle() {
    let engine = create_test_engine();

    // Full cycle: set all properties, verify, reset, verify defaults
    engine.set_bus_volume(3, 0.42);
    engine.set_bus_pan(3, -0.7);
    engine.set_bus_pan_right(3, 0.3);
    engine.set_bus_mute(3, true);
    engine.set_bus_solo(3, true);

    let state = engine.get_bus_state(3).unwrap();
    assert!((state.volume - 0.42).abs() < 1e-10);
    assert!((state.pan - (-0.7)).abs() < 1e-10);
    assert!((state.pan_right - 0.3).abs() < 1e-10);
    assert!(state.muted);
    assert!(state.soloed);

    // Reset to defaults
    engine.set_bus_volume(3, 1.0);
    engine.set_bus_pan(3, 0.0);
    engine.set_bus_pan_right(3, 0.0);
    engine.set_bus_mute(3, false);
    engine.set_bus_solo(3, false);

    let state = engine.get_bus_state(3).unwrap();
    assert!((state.volume - 1.0).abs() < f64::EPSILON);
    assert!((state.pan - 0.0).abs() < f64::EPSILON);
    assert!((state.pan_right - 0.0).abs() < f64::EPSILON);
    assert!(!state.muted);
    assert!(!state.soloed);
}

#[test]
fn test_multiple_engines_independent() {
    let engine1 = create_test_engine();
    let engine2 = create_test_engine();

    engine1.set_master_volume(0.3);
    engine2.set_master_volume(0.7);

    assert!((engine1.master_volume() - 0.3).abs() < f64::EPSILON);
    assert!((engine2.master_volume() - 0.7).abs() < f64::EPSILON);

    engine1.set_bus_volume(0, 0.1);
    assert!(
        (engine2.get_bus_state(0).unwrap().volume - 1.0).abs() < f64::EPSILON,
        "Engine2 bus should be unaffected by engine1"
    );
}

#[test]
fn test_track_meter_empty() {
    use rf_engine::TrackMeter;

    let meter = TrackMeter::empty();
    assert!((meter.peak_l - 0.0).abs() < f64::EPSILON);
    assert!((meter.peak_r - 0.0).abs() < f64::EPSILON);
    assert!((meter.rms_l - 0.0).abs() < f64::EPSILON);
    assert!((meter.rms_r - 0.0).abs() < f64::EPSILON);
    assert!(
        (meter.correlation - 1.0).abs() < f64::EPSILON,
        "Silent correlation should be 1.0 (mono)"
    );
}

#[test]
fn test_track_meter_decay() {
    use rf_engine::TrackMeter;

    let mut meter = TrackMeter {
        peak_l: 1.0,
        peak_r: 0.8,
        rms_l: 0.5,
        rms_r: 0.4,
        correlation: 0.9,
    };

    meter.decay(0.5);

    assert!((meter.peak_l - 0.5).abs() < f64::EPSILON);
    assert!((meter.peak_r - 0.4).abs() < f64::EPSILON);
    assert!((meter.rms_l - 0.25).abs() < f64::EPSILON);
    assert!((meter.rms_r - 0.2).abs() < f64::EPSILON);
}

#[test]
fn test_voice_pool_stats_struct_default() {
    let stats = VoicePoolStats::default();
    assert_eq!(stats.active_count, 0);
    assert_eq!(stats.max_voices, 0); // Default derive gives 0, engine fills 32
    assert_eq!(stats.looping_count, 0);
    assert_eq!(stats.daw_voices, 0);
    assert_eq!(stats.slotlab_voices, 0);
    assert_eq!(stats.middleware_voices, 0);
    assert_eq!(stats.browser_voices, 0);
}
