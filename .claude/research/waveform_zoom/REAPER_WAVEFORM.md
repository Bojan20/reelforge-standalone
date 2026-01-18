# Cockos REAPER — Waveform Display & Zoom System Analysis

## 1. .reapeaks File Format

### File Structure
| Element | Description |
|---------|-------------|
| Extension | `.reapeaks` |
| Location | Same folder as audio file |
| Structure | Binary mipmap data |
| Regeneration | Automatic if deleted |

### Mipmap Architecture
```
.reapeaks File Structure:
├── Header: Version, sample rate, channels
├── Level 0: 1 peak per 256 samples
├── Level 1: 1 peak per 1024 samples
├── Level 2: 1 peak per 4096 samples
├── Level 3: 1 peak per 16384 samples
└── Level N: Overview level

Each level: Array of (min, max) f32 pairs
```

### Preferences
```
Options > Preferences > Media:
├── Generate peak files
├── Peak file location (same as audio / project folder)
├── Peak cache size
└── Background peak generation
```

---

## 2. Rendering Technology

### Display Engine
| Platform | Technology |
|----------|------------|
| Windows | GDI / Direct2D |
| macOS | Core Graphics / Metal |
| Linux | GTK+ / Cairo |

### WALTER Theme Engine
- Complete UI customization
- Vector graphics support
- Custom waveform rendering
- Resolution-independent display

### Rendering Characteristics
- CPU-based peak rendering
- Efficient mipmap selection
- Theme-controlled appearance
- Minimal GPU requirements

---

## 3. Zoom System

### Horizontal Zoom
| Control | Function |
|---------|----------|
| +/- keys | Zoom in/out |
| Scroll wheel | With Ctrl modifier |
| Mouse drag | In ruler area |
| Zoom buttons | Toolbar |

### Vertical Zoom
| Control | Function |
|---------|----------|
| Ctrl+Up/Down | Track height |
| Mouse drag | Track dividers |
| Scroll wheel | In track area |

### Zoom Presets
```
View > Zoom:
├── Zoom In/Out Horizontal
├── Zoom In/Out Vertical
├── Zoom to Selection
├── Zoom to Project
├── Zoom to Time Selection
└── Custom zoom presets via Actions

Action: View: Zoom to 1 pixel per sample
Action: View: Zoom out max (project extents)
Action: View: Zoom to selection
```

### Sample-Level Zoom
- Maximum zoom shows individual samples
- Sample dots with interpolation
- Edit at sample level
- Pencil tool for drawing

---

## 4. Waveform Display Options

### Display Modes
| Mode | Description |
|------|-------------|
| Peak | Standard min/max display |
| Peak + RMS | Combined view |
| Outline only | Hollow waveform |
| Spectral peaks | Frequency coloring |

### Theme Control
```
WALTER Theme Configuration:
├── Waveform colors
├── Peak/RMS colors
├── Outline thickness
├── Background colors
├── Grid overlay
└── Custom rendering code
```

### Spectral Peaks
```
┌─────────────────────────────────────────────────────────────────┐
│ Spectral Peaks Mode:                                             │
├─────────────────────────────────────────────────────────────────┤
│ Color represents frequency content:                              │
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                      │
│ Red=Low, Yellow=Mid, Blue=High frequencies                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Spectrogram View

### Full Spectrogram
```
┌─────────────────────────────────────────────────────────────────┐
│ Spectrogram View (Item Properties > Spectrogram)                 │
├─────────────────────────────────────────────────────────────────┤
│ 20kHz─│░░░▓▓░░░▓▓░░░▓▓░░░                                       │
│ 10kHz─│░░▓▓▓▓░▓▓▓▓░▓▓▓▓░░                                       │
│  5kHz─│░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░                                       │
│  1kHz─│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                       │
│ 100Hz─│░▓▓▓▓░░▓▓▓▓░░▓▓▓▓░                                       │
│       └────────────────────────                                  │
│         Time →                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Spectrogram Settings
| Setting | Range |
|---------|-------|
| FFT size | 128-8192 |
| Window | Blackman-Harris, Hamming, etc. |
| Overlap | 0-95% |
| Color scheme | Multiple palettes |
| Frequency scale | Linear / Log |

---

## 6. Dynamic Split Visualization

### Transient Detection
```
┌─────────────────────────────────────────────────────────────────┐
│ Dynamic Split - Gate Mode                                        │
├─────────────────────────────────────────────────────────────────┤
│ Threshold ───────────────────────────────────────────           │
│                    ╱╲          ╱╲        ╱╲                     │
│ ▁▂▃▅▇██▇▅│▂▁▂▃▅▇██▇▅│▂▁▂▃▅▇██▇│▂▁                              │
│           ↑          ↑          ↑                                │
│         Split points at detected transients                      │
│                                                                  │
│ Gate threshold: [-30 dB ████░░░░░░░░░░]                         │
│ Min length: [50 ms]                                              │
│ Lookahead: [5 ms]                                                │
└─────────────────────────────────────────────────────────────────┘
```

### Split Markers
| Type | Purpose |
|------|---------|
| Transient | Auto-detected hits |
| Grid | Musical divisions |
| Manual | User-placed splits |

---

## 7. Stretch Marker Visualization

### Stretch Display
```
┌─────────────────────────────────────────────────────────────────┐
│ Stretch Markers Mode                                             │
├─────────────────────────────────────────────────────────────────┤
│ Original:  |  1  |  2  |  3  |  4  |                            │
│            ○     ○     ○     ○                                   │
│ ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁                             │
│            ↓     ↓      ↓    ↓                                   │
│ Stretched: |  1  | 2  |   3   | 4|                              │
│ (Visual shows compression/expansion)                             │
└─────────────────────────────────────────────────────────────────┘
```

### Marker Types
| Type | Visual |
|------|--------|
| Fixed | Circle (anchor point) |
| Movable | Diamond (stretchable) |
| Grid-aligned | Snapped to beat |

---

## 8. Multi-Resolution (Mipmap) System

### Automatic Level Selection
```
Mipmap Selection Algorithm:
├── Calculate pixels per sample
├── Select level with ~1-4 peaks per pixel
├── Interpolate between levels if needed
└── Smooth transition during zoom

Example:
Zoom level: 1000 samples/pixel
→ Select Level 2 (4096 samples/peak)
→ ~4 peaks per pixel (optimal)
```

### Level Structure
| Level | Samples/Peak | Use Case |
|-------|--------------|----------|
| 0 | 256 | Detail view |
| 1 | 1024 | Standard |
| 2 | 4096 | Overview |
| 3 | 16384 | Full project |
| Raw | 1 | Sample edit |

---

## 9. Performance Features

### Peak Generation
| Feature | Description |
|---------|-------------|
| Background | Non-blocking generation |
| Priority | Visible items first |
| Incremental | Generate as needed |
| Persistent | Saved to .reapeaks |

### Large Project Handling
- Efficient mipmap system
- Lazy loading
- Memory-mapped files
- Disk streaming

### Optimization Settings
```
Options > Preferences > Media:
├── Build peaks in background
├── Peak build priority
├── Disk read speed limit
└── Peak cache size: [512 MB]
```

---

## 10. ReaScript Peak Access

### API Functions
```lua
-- Get peak value at sample position
reaper.GetMediaItemPeaks(item, position, num_peaks, peaks_buf)

-- Custom peak visualization
-- Available via ReaScript API for extensions
```

### Extensibility
- Full peak data access via API
- Custom waveform rendering possible
- JSFX can access audio data
- SWS extensions add features

---

## Key Technical Patterns for FluxForge Implementation

### 1. Mipmap Design
```rust
struct ReaperPeakFile {
    header: PeakHeader,
    levels: Vec<MipmapLevel>,
}

struct MipmapLevel {
    samples_per_peak: u32,  // 256, 1024, 4096, ...
    peaks: Vec<(f32, f32)>, // (min, max) pairs
}

impl ReaperPeakFile {
    fn select_level(&self, samples_per_pixel: f64) -> &MipmapLevel {
        // Select level with ~1-4 peaks per pixel
        for level in &self.levels {
            if level.samples_per_peak as f64 <= samples_per_pixel * 4.0 {
                return level;
            }
        }
        &self.levels.last().unwrap()
    }
}
```

### 2. Zoom Implementation
- Logarithmic scale
- Keyboard shortcuts
- Action-based customization
- Sample-level editing support

### 3. Spectral Display
- FFT-based visualization
- Real-time or cached
- Color palette options
- Frequency scale modes

### 4. Stretch Visualization
- Marker overlay system
- Real-time preview
- Algorithm selection
- Time/pitch display

---

## Sources

- [REAPER Official](https://www.reaper.fm/)
- [REAPER User Guide](https://www.reaper.fm/userguide.php)
- [REAPER SDK - Peak Files](https://www.reaper.fm/sdk/)
- [Cockos Wiki](https://wiki.cockos.com/)
- [REAPER Blog](https://reaper.blog/)
- [Sound on Sound - REAPER Articles](https://www.soundonsound.com/techniques/reaper)

---

*Document created: January 2026*
*For FluxForge Studio implementation reference*
