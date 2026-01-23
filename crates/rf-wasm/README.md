# FluxForge WASM

WebAssembly port of FluxForge audio middleware for web browsers.

## Features

- Web Audio API integration
- Event-based audio playback
- Bus routing and volume control
- RTPC (Real-Time Parameter Control)
- State/Switch system
- Voice pooling and stealing
- Minimal binary size (~50KB gzipped)

## Building

### Prerequisites

- Rust (nightly recommended)
- wasm-pack: `cargo install wasm-pack`

### Build Commands

```bash
# Development build
wasm-pack build --target web --dev

# Release build (optimized for size)
wasm-pack build --target web --release

# Build for bundlers (webpack, rollup, etc.)
wasm-pack build --target bundler --release

# Build for Node.js
wasm-pack build --target nodejs --release
```

### Build Output

After building, the `pkg/` directory contains:
- `rf_wasm.js` - JavaScript glue code
- `rf_wasm_bg.wasm` - WebAssembly binary
- `rf_wasm.d.ts` - TypeScript definitions
- `package.json` - npm package metadata

## Usage

### Basic Setup

```typescript
import { initFluxForge, FluxForgeAudioManager, AudioBus } from '@fluxforge/wasm';

// Initialize WASM (once, on app start)
await initFluxForge();

// Create audio manager (must be from user gesture)
const audio = new FluxForgeAudioManager({
  maxVoices: 32,
  maxVoicesPerEvent: 4,
});

await audio.init();

// Load events
audio.loadEvents([
  {
    id: 'spin_start',
    name: 'Spin Start',
    stages: ['SPIN_START'],
    layers: [
      {
        audio_path: '/audio/spin.mp3',
        volume: 1.0,
        pan: 0.0,
        delay_ms: 0,
        offset_ms: 0,
        bus: AudioBus.Sfx,
        loop_enabled: false,
      },
    ],
    priority: 80,
  },
]);

// Play!
audio.triggerStage('SPIN_START');
```

### Event Playback

```typescript
// Play by event ID
audio.playEvent('spin_start', 1.0, 1.0); // volume, pitch

// Trigger by stage name
audio.triggerStage('REEL_STOP_0');

// Convenience for reel stops
audio.triggerReelStop(0); // reel index 0-4

// Stop sounds
audio.stopEvent('spin_start', 100); // fade time ms
audio.stopAll(500);
```

### Bus Control

```typescript
// Volume (0-2, 1.0 = unity)
audio.setBusVolume(AudioBus.Music, 0.8);
audio.setBusVolume(AudioBus.Sfx, 1.0);
audio.setMasterVolume(0.9);

// Mute
audio.setBusMute(AudioBus.Voice, true);
```

### RTPC

```typescript
// Load RTPC definitions
audio.loadRtpc([
  { name: 'WinAmount', min: 0, max: 10000, default: 0 },
  { name: 'CascadeDepth', min: 0, max: 10, default: 0 },
]);

// Set values
audio.setRtpc('WinAmount', 500);
audio.setRtpc('CascadeDepth', 3);

// Get values
const win = audio.getRtpc('WinAmount');
const normalized = audio.getRtpcNormalized('WinAmount'); // 0-1
```

### State System

```typescript
// Load state groups
audio.loadStateGroups([
  {
    name: 'GameState',
    states: ['BASE', 'FREESPINS', 'BONUS'],
    default_state: 'BASE',
  },
]);

// Set state
audio.setState('GameState', 'FREESPINS');

// Get state
const state = audio.getState('GameState'); // 'FREESPINS'
```

### Frame Updates

```typescript
function gameLoop() {
  // Call periodically to cleanup finished voices
  audio.update();

  // Check stats
  console.log(`Active voices: ${audio.activeVoiceCount}`);

  requestAnimationFrame(gameLoop);
}
```

## TypeScript Wrapper

The `js/fluxforge-audio.ts` file provides a high-level TypeScript wrapper:

```typescript
import {
  FluxForgeAudioManager,
  AudioBus,
  VoiceStealMode,
  initDefaultManager,
  dbToLinear,
  linearToDb,
} from '@fluxforge/wasm/fluxforge-audio';

// Use default manager for simple apps
const audio = await initDefaultManager();
audio.triggerStage('SPIN_START');

// Utility functions
const gain = dbToLinear(-6); // 0.501
const db = linearToDb(0.5);  // -6.02
```

## Binary Size

| Build | Size (raw) | Size (gzipped) |
|-------|-----------|----------------|
| Debug | ~200KB | ~80KB |
| Release | ~120KB | ~45KB |
| Release + wee_alloc | ~100KB | ~38KB |

## Browser Support

- Chrome 57+
- Firefox 52+
- Safari 11+
- Edge 79+

Requires Web Audio API and WebAssembly support.

## License

MIT
