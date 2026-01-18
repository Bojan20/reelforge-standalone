# DAW Waveform Display & Zoom System — Comparison Summary

## Quick Reference Table

| DAW | Peak File | GPU Accel | Max Zoom | Spectral | Pitch Edit | Unique Feature |
|-----|-----------|-----------|----------|----------|------------|----------------|
| **Cubase** | .peak | Metal/DirectX | Sample | SpectraLayers | VariAudio | Mipmap structure |
| **Pro Tools** | .wfm | Core Graphics | Sample | No (3rd party) | Elastic Audio | 5 zoom presets |
| **Logic Pro** | Internal | Metal | Sample | No | Flex Pitch | Trackpad gestures |
| **Ableton** | .asd | Metal | Sample | No | Warp markers | Clip/Arrange dual |
| **REAPER** | .reapeaks | GDI/Cairo | Sample | Built-in | Stretch markers | Spectral peaks mode |
| **Studio One** | /Cache | Hardware | Sample | No | Audio Bend | ARA integration |
| **Pyramix** | Internal | N/A | Frame | CEDAR | No | DSD scrubbing |

---

## Peak File Formats Comparison

### File Structures

| DAW | Extension | Location | Multi-Resolution | Contents |
|-----|-----------|----------|------------------|----------|
| Cubase | .peak | Project/Images/ | Yes (mipmap) | Min/max/RMS |
| Pro Tools | .wfm | Same as audio | Yes | Min/max |
| Logic | Internal | .logicx package | Yes | Min/max |
| Ableton | .asd | Same as audio | Yes | Peaks + warp + tempo |
| REAPER | .reapeaks | Same as audio | Yes (mipmap) | Min/max |
| Studio One | .peak | Project/Cache/ | Yes | Min/max |
| Pyramix | Internal | Project | Yes | High-res peaks |

### Resolution Levels (Typical)

```
Standard Mipmap Structure:
Level 0:  1 peak per 256 samples     (detail)
Level 1:  1 peak per 1024 samples    (standard)
Level 2:  1 peak per 4096 samples    (overview)
Level 3:  1 peak per 16384 samples   (full project)
```

---

## GPU Acceleration Status

| DAW | macOS | Windows | Linux | Focus |
|-----|-------|---------|-------|-------|
| **Cubase** | Metal | DirectX | N/A | UI rendering |
| **Pro Tools** | Core Graphics | DirectX | N/A | Timeline scroll |
| **Logic** | Metal (native) | N/A | N/A | Full UI |
| **Ableton** | Metal (11.2+) | Hardware Accel | N/A | UI rendering |
| **REAPER** | Core Graphics | GDI/Direct2D | Cairo | Minimal GPU |
| **Studio One** | Hardware Accel | Hardware Accel | N/A | UI rendering |
| **Pyramix** | N/A | Windows only | N/A | CPU-focused |

**Key Insight**: No DAW uses specialized GPU compute shaders for waveform rendering. All GPU acceleration is for general UI painting.

---

## Zoom System Comparison

### Zoom Controls

| DAW | Keyboard | Mouse | Trackpad | Presets |
|-----|----------|-------|----------|---------|
| Cubase | G/H keys | Scroll+Mod | Basic | Quick zoom |
| Pro Tools | R/T keys | Zoom tool | Basic | 5 slots |
| Logic | Cmd+Arrow | Scroll+Mod | Pinch | 3 slots |
| Ableton | Scroll | Ruler drag | Basic | None |
| REAPER | +/- keys | Scroll+Mod | Basic | Actions |
| Studio One | Slider | Double-click | Basic | None |
| Pyramix | Custom | Scroll | N/A | Custom |

### Zoom Range

All DAWs support:
- **Minimum**: Full project overview (hours)
- **Maximum**: Sample-level editing (1 sample/pixel)

### Logarithmic vs Linear

| DAW | Scale Type | Behavior |
|-----|------------|----------|
| Cubase | Logarithmic | Smooth zoom |
| Pro Tools | Stepped | Preset-based |
| Logic | Logarithmic | Momentum zoom |
| Ableton | Mixed | Ruler-based |
| REAPER | Logarithmic | Customizable |
| Studio One | Logarithmic | Smooth |
| Pyramix | Linear steps | Frame-accurate |

---

## Display Mode Comparison

### Waveform Modes

| Mode | Cubase | PT | Logic | Ableton | REAPER | S1 | Pyramix |
|------|--------|-----|-------|---------|--------|-----|---------|
| Peak | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| RMS | ✓ | ✓ | No | No | ✓ | No | ✓ |
| Rectified | ✓ | ✓ | No | No | ✓ | No | No |
| Spectral | SpectraLayers | No | No | No | ✓ | No | CEDAR |
| Spectrogram | Via SL | No | No | No | ✓ | No | Via CEDAR |

### Visual Overlays

| Overlay | Cubase | PT | Logic | Ableton | REAPER | S1 | Pyramix |
|---------|--------|-----|-------|---------|--------|-----|---------|
| Pitch blobs | VariAudio | No | Flex Pitch | No | No | ARA | No |
| Warp markers | AudioWarp | Elastic | Flex Time | ✓ | Stretch | Bend | No |
| Fade curves | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Clip gain | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Transients | Hitpoints | Beat Det. | Transients | Transients | Dynamic Split | Bend | ✓ |

---

## Performance Characteristics

### Large Project Handling

| DAW | 100+ Tracks | Memory Efficiency | Background Gen |
|-----|-------------|-------------------|----------------|
| Cubase | Good | Good | Yes |
| Pro Tools | Excellent | Good | Yes |
| Logic | Excellent | Good | Yes |
| Ableton | Good | Good | Yes |
| REAPER | Excellent | Excellent | Yes |
| Studio One | Good | Good | Yes |
| Pyramix | Excellent | Good | Yes |

### Rendering Performance

| DAW | Frame Rate Target | Scroll Smoothness |
|-----|-------------------|-------------------|
| Cubase | 60fps | Good |
| Pro Tools | 60fps | Excellent |
| Logic | 120fps (ProMotion) | Excellent |
| Ableton | 60fps | Good |
| REAPER | Variable | Good |
| Studio One | 60fps | Good |
| Pyramix | 60fps | Good |

---

## Unique Features by DAW

### Cubase
- **VariAudio 3**: Pitch blob editing with Smart Controls
- **SpectraLayers**: Full spectral editing via ARA
- **Mipmap .peak**: Multi-resolution in single file

### Pro Tools
- **5 Zoom Presets**: One-click zoom recall
- **Beat Detective**: Visual transient analysis
- **Playlist Lanes**: Multi-take waveform comparison

### Logic Pro
- **Metal Native**: Apple Silicon optimized
- **Trackpad Gestures**: Pinch zoom, momentum scroll
- **Flex Pitch**: Integrated pitch editing

### Ableton Live
- **.asd Files**: Store warp + tempo + peaks
- **Clip/Arrangement**: Dual view modes
- **Warp Markers**: Visual time-stretching

### REAPER
- **Spectral Peaks**: Frequency-colored waveforms
- **Full Spectrogram**: Built-in spectral view
- **.reapeaks Mipmap**: Efficient multi-level cache
- **WALTER Theming**: Complete visual customization

### Studio One
- **Audio Bend**: Visual transient manipulation
- **ARA Deep Integration**: Melodyne overlays
- **Cache System**: Organized peak storage

### Pyramix
- **DSD Scrubbing**: Only DAW with native DSD display
- **Source/Destination**: Multi-take comparison
- **Frame-Accurate**: CD frame precision (1/75 sec)
- **384 Channels**: Professional broadcast scale

---

## Implementation Recommendations for FluxForge

### Priority 1: Core System

1. **Peak File Format**
   - Use mipmap structure (REAPER/Cubase style)
   - Levels: 256, 1024, 4096, 16384 samples/peak
   - Store min/max/RMS per block
   - Binary format for speed

2. **Multi-Resolution Selection**
   ```rust
   fn select_level(samples_per_pixel: f64) -> usize {
       // Target 1-4 peaks per pixel
       for (i, level) in levels.iter().enumerate() {
           if level.samples_per_peak <= samples_per_pixel * 4.0 {
               return i;
           }
       }
       levels.len() - 1
   }
   ```

3. **Zoom System**
   - Logarithmic scale
   - Keyboard shortcuts (G/H style)
   - 5 storable presets
   - Zoom to selection

### Priority 2: GPU Rendering

1. **Skia/Impeller Integration**
   - Use Flutter's GPU pipeline
   - Batch waveform drawing
   - Efficient vertex buffers

2. **Frame Rate Target**
   - 60fps minimum
   - 120fps on ProMotion displays
   - Smooth zoom transitions

### Priority 3: Advanced Features

1. **Spectral Display** (Future)
   - FFT-based visualization
   - Color palette options
   - rf-viz integration

2. **Pitch Overlay** (Future)
   - Similar to VariAudio/Flex Pitch
   - rf-dsp pitch detection
   - Node-based editing

3. **Transient Markers**
   - Dynamic split integration
   - Visual threshold adjustment
   - Quantize preview

---

## File Locations

Individual DAW analyses:

| DAW | File |
|-----|------|
| Ableton Live | [ABLETON_LIVE_WAVEFORM.md](ABLETON_LIVE_WAVEFORM.md) |
| Cubase Pro | [CUBASE_PRO_WAVEFORM.md](CUBASE_PRO_WAVEFORM.md) |
| Logic Pro | [LOGIC_PRO_WAVEFORM.md](LOGIC_PRO_WAVEFORM.md) |
| Pro Tools | [PRO_TOOLS_WAVEFORM.md](PRO_TOOLS_WAVEFORM.md) |
| Pyramix | [PYRAMIX_WAVEFORM.md](PYRAMIX_WAVEFORM.md) |
| REAPER | [REAPER_WAVEFORM.md](REAPER_WAVEFORM.md) |
| Studio One | [STUDIO_ONE_WAVEFORM.md](STUDIO_ONE_WAVEFORM.md) |

---

*Document created: January 2026*
*For FluxForge Studio implementation reference*
