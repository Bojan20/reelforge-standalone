# Steinberg Cubase Pro 14 — Waveform Display & Zoom System Analysis

## 1. Peak File Format (.peak)

### File Structure
| Element | Description |
|---------|-------------|
| Extension | `.peak` |
| Location | Project `Images/` folder |
| Generation | Automatic on audio import |
| Multi-resolution | Yes, mipmap-style |

### Cache Architecture
```
Project/
├── MyProject.cpr
├── Audio/
│   ├── Recording_01.wav
│   └── Recording_02.wav
└── Images/
    ├── Recording_01.peak    ← Peak cache files
    └── Recording_02.peak
```

### Peak Data Structure
- Multiple resolution levels stored in single file
- Mipmap approach (1:2:4:8:16... ratios)
- Min/max pairs for each block
- RMS data for optional display

---

## 2. GPU Acceleration

### Rendering Technology
| Platform | Technology |
|----------|------------|
| macOS | Metal (via Skia) |
| Windows | DirectX / OpenGL |

### Acceleration Scope
- General UI rendering accelerated
- Waveform painting benefits from GPU
- Not specialized GPU compute for waveforms
- Focus on smooth scrolling/zooming

### Performance Characteristics
- 60fps target for UI updates
- Hardware-accelerated compositing
- Efficient layer management
- Smooth zoom transitions

---

## 3. Zoom System

### Zoom Controls
| Control | Function |
|---------|----------|
| G/H keys | Horizontal zoom out/in |
| Shift+G/H | Vertical zoom |
| Slider | Fine zoom control |
| Mouse wheel | With modifier keys |
| Zoom tool | Area selection zoom |

### Zoom Presets
- **F key**: Full project overview
- **Shift+F**: Zoom to selection
- **Alt+S**: Zoom to locator range
- Numeric keypad shortcuts

### Zoom Behavior
```
Zoom Levels (approximate):
├── Level 1: Full project (hours)
├── Level 5: Minutes
├── Level 10: Seconds
├── Level 15: Milliseconds
└── Level 20: Sample-level

Logarithmic scale between levels
```

### Zoom Undo/Redo
- Navigation history maintained
- Ctrl+Z includes zoom changes
- Window-specific zoom memory

---

## 4. Waveform Display Options

### Display Modes
| Mode | Description |
|------|-------------|
| Peak | Standard amplitude display |
| RMS/Power | Shows average energy |
| Rectified | Absolute value display |
| Channels | Stereo/mono toggle |

### Visual Customization
```
Preferences → Event Display → Audio:
├── Show Waveforms: On/Off
├── Interpolate Audio Images: Quality setting
├── Waveform Brightness
├── Waveform Outline Intensity
├── Background Color Mode
└── Fade Handles Visibility
```

### Waveform Colors
- Track color inheritance
- Custom waveform colors
- Fade area visualization
- Clip gain envelope overlay

---

## 5. VariAudio Waveform Overlay

### Pitch Display
```
┌─────────────────────────────────────────────────────────────────┐
│ Pitch Scale │                                                    │
│     C5 ─────│─────[▓▓▓▓▓▓]──────────────────────────            │
│     B4 ─────│────────────────[▓▓▓▓▓]────────────────            │
│     A4 ─────│──[▓▓▓▓▓▓▓▓]────────────[▓▓▓▓]─────────            │
│     G4 ─────│──────────────────────────────[▓▓▓▓▓]──            │
│             │                                                    │
│ Waveform:   │ ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁                │
└─────────────────────────────────────────────────────────────────┘
```

### VariAudio Elements
| Element | Description |
|---------|-------------|
| Pitch segments | Note "blobs" on grid |
| Pitch curve | Micro-pitch variation |
| Smart Controls | Warp handles |
| Scale Assistant | Pitch grid overlay |

### AudioWarp Visualization
- Warp markers on timeline
- Stretch visualization
- Hitpoint markers
- Free warp mode display

---

## 6. Spectrum Display Options

### SpectraLayers Integration
- ARA2 integration for spectral editing
- Time-frequency display overlay
- Layer-based spectral view
- Non-destructive spectral editing

### Spectrum Modes
| Mode | Use Case |
|------|----------|
| Waveform | Standard editing |
| Spectral | Frequency content |
| Combined | Both overlaid |

---

## 7. Performance Optimizations

### Waveform Image Cache
| Setting | Effect |
|---------|--------|
| Interpolate Audio Images | Quality vs speed |
| Cache Size | Memory allocation |
| Background Generation | Async peak building |

### Large Project Handling
- Async waveform generation
- Background thread processing
- Progressive loading
- Memory-efficient caching

### Best Practices
1. Store projects on SSD
2. Allow peak file generation to complete
3. Use appropriate zoom level for editing
4. Enable/disable waveforms per need

---

## 8. Timeline/Arrangement View Features

### Track Display Options
| Option | Description |
|--------|-------------|
| Track height | Individual or global |
| Waveform zoom | Vertical amplitude |
| Show channels | Mono/stereo display |
| Lane display | Comping view |

### Fade Visualization
```
Fade Types:
├── Linear
├── Cosine (S-Curve)
├── Logarithmic
├── Exponential
└── Custom curves

Visual: Shaded overlay on waveform
```

### Clip Gain Envelope
- Visual overlay on waveform
- Node-based editing
- Pre-fader gain control
- Per-clip automation

---

## 9. Multi-Resolution System

### Mipmap Structure
```
Level 0: 1 peak per sample (maximum detail)
Level 1: 1 peak per 2 samples
Level 2: 1 peak per 4 samples
Level 3: 1 peak per 8 samples
Level 4: 1 peak per 16 samples
Level 5: 1 peak per 32 samples
...
Level N: Overview level
```

### Resolution Selection
- Automatic based on zoom level
- Smooth LOD transitions
- No visible popping between levels
- Interpolation for smooth display

---

## Key Technical Patterns for FluxForge Implementation

### 1. Peak File Design
```rust
struct CubasePeakFile {
    header: PeakHeader,
    levels: Vec<MipmapLevel>,
}

struct MipmapLevel {
    samples_per_peak: u32,
    data: Vec<PeakData>,
}

struct PeakData {
    min: f32,
    max: f32,
    rms: f32,  // Optional
}
```

### 2. Zoom Implementation
- Logarithmic scale between levels
- Keyboard shortcuts for common operations
- Zoom presets with instant recall
- Navigation history stack

### 3. Overlay System
- VariAudio-style pitch display
- Warp marker visualization
- Clip gain envelope overlay
- Fade curve display

### 4. Performance Strategy
- Background peak generation
- Async loading
- Memory-efficient caching
- Progressive display

---

## Sources

- [Steinberg Help - Cubase Pro 14](https://www.steinberg.help/r/cubase-pro/14.0/en/)
- [Steinberg Help - Audio Event Display](https://www.steinberg.help/r/cubase-pro/14.0/en/audio_event_display.html)
- [Sound on Sound - Cubase Pro Techniques](https://www.soundonsound.com/techniques/cubase-pro)
- [Sound on Sound - VariAudio 3 Smart Controls](https://www.soundonsound.com/techniques/cubase-pro-variaudio-3-smart-controls)
- [Steinberg Forums](https://forums.steinberg.net/)

---

*Document created: January 2026*
*For FluxForge Studio implementation reference*
