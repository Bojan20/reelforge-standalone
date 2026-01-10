//! Unified Routing Example
//!
//! Demonstrates how to integrate PlaybackEngine with unified routing
//! in an audio callback (replacing legacy mixer-based routing).
//!
//! Run with: cargo run --example unified_routing --features unified_routing

use rf_engine::{PlaybackEngine, TrackManager};
use std::sync::Arc;

#[cfg(feature = "unified_routing")]
use rf_engine::routing::ChannelKind;

fn main() {
    #[cfg(not(feature = "unified_routing"))]
    {
        println!("ERROR: unified_routing feature not enabled");
        println!("Run with: cargo run --example unified_routing --features unified_routing");
        return;
    }

    #[cfg(feature = "unified_routing")]
    {
        println!("=== Unified Routing Example ===\n");

        // 1. Create TrackManager and PlaybackEngine
        let track_manager = Arc::new(TrackManager::new());
        let playback_engine = Arc::new(PlaybackEngine::new(track_manager.clone(), 48000));

        println!("✓ PlaybackEngine created");

        // 2. Initialize unified routing (OUTSIDE audio callback, in setup)
        let block_size = 256;
        let sample_rate = 48000.0;
        let mut routing_graph = playback_engine.init_unified_routing(block_size, sample_rate);

        println!("✓ RoutingGraphRT initialized");
        println!("  Block size: {}", block_size);
        println!("  Sample rate: {} Hz", sample_rate);

        // 3. Create some channels via UI thread (sends commands to audio thread)
        println!("\n--- Creating Routing Channels ---");

        playback_engine.create_routing_channel(ChannelKind::Audio, "Track 1");
        playback_engine.create_routing_channel(ChannelKind::Audio, "Track 2");
        playback_engine.create_routing_channel(ChannelKind::Bus, "Drums Bus");
        playback_engine.create_routing_channel(ChannelKind::Master, "Master");

        println!("✓ Created 4 channels (2 audio, 1 bus, 1 master)");

        // 4. Process commands in routing graph (normally done in audio thread)
        routing_graph.process_commands();

        println!("✓ Commands processed");

        // 5. Simulate audio callback (THIS RUNS IN AUDIO THREAD)
        println!("\n--- Simulating Audio Callback ---");

        let mut output_l = vec![0.0_f64; block_size];
        let mut output_r = vec![0.0_f64; block_size];

        for block_num in 0..5 {
            // Process audio through unified routing
            playback_engine.process_unified(&mut routing_graph, &mut output_l, &mut output_r);

            // Check output
            let peak_l = output_l.iter().map(|s| s.abs()).fold(0.0, f64::max);
            let peak_r = output_r.iter().map(|s| s.abs()).fold(0.0, f64::max);

            println!(
                "  Block {}: Peak L={:.6}, R={:.6}",
                block_num, peak_l, peak_r
            );
        }

        println!("\n✓ Unified routing working!");

        println!("\n=== Integration Pattern ===");
        println!("
In your audio callback:

```rust
// Setup (once):
let mut routing_graph = playback_engine.init_unified_routing(block_size, sample_rate);

// Audio callback loop:
let callback = move |output: &mut [f32]| {{
    let frames = output.len() / 2;
    let mut output_l = vec![0.0; frames];
    let mut output_r = vec![0.0; frames];

    // Process through unified routing
    playback_engine.process_unified(&mut routing_graph, &mut output_l, &mut output_r);

    // Interleave output
    for i in 0..frames {{
        output[i * 2] = output_l[i] as f32;
        output[i * 2 + 1] = output_r[i] as f32;
    }}
}};
```

UI thread can control routing via:
- playback_engine.create_routing_channel()
- playback_engine.set_routing_output()
- playback_engine.send_routing_command()
");
    }
}
