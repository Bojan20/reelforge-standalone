# Merging Pyramix — Waveform Display & Zoom System Analysis

## 1. Peak Cache System

### Cache Architecture
- Project-based peak storage
- High-resolution cache for professional mastering
- DSD-specific peak representation
- Multi-resolution for zoom levels

### DSD Waveform Handling
```
DSD Peak Generation:
├── Convert DSD to DXD (352.8kHz) for display
├── Generate peaks from DXD representation
├── Store multi-resolution data
└── Real-time scrubbing via DXD bridge

Note: Pyramix is ONLY DAW that can display/scrub native DSD
```

---

## 2. High-Resolution Display

### Professional Quality
| Feature | Specification |
|---------|---------------|
| Resolution | Up to 192kHz/384kHz display |
| Bit depth | 32-bit float internal |
| Channel count | Up to 128 channels |
| Precision | Frame-accurate editing |

### DXD Bridge Display
```
DSD → DXD → Display Pipeline:
┌─────────────────────────────────────────────────────────────────┐
│ DSD64 (2.8MHz) → DXD (352.8kHz) → Peak Cache → Waveform       │
│ DSD128 (5.6MHz) → DXD (352.8kHz) → Peak Cache → Waveform      │
│ DSD256 (11.2MHz) → DXD (352.8kHz) → Peak Cache → Waveform     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Zoom System

### Horizontal Zoom
| Range | Application |
|-------|-------------|
| Full session | Hours of content |
| Standard | Minutes/seconds |
| Detail | Milliseconds |
| Sample | Individual samples |
| Frame-accurate | CD frame (1/75 sec) |

### Frame-Accurate Editing
```
CD Frame Resolution:
├── 1 frame = 1/75 second
├── 588 samples at 44.1kHz
├── Essential for Red Book mastering
└── Visual grid at frame boundaries
```

### Zoom Controls
- Keyboard shortcuts
- Mouse wheel with modifiers
- Zoom presets
- Zoom to selection

---

## 4. Source/Destination View

### Dual Window Display
```
┌─────────────────────────────────────────────────────────────────┐
│ SOURCE WINDOW:                                                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Take 1: [▁▂▃▅▇█=IN=█▇▅▃=OUT=▂▁]                            │ │
│ │ Take 2: [▂▃▅▇█=IN===OUT=▇▅▃▂]                              │ │
│ │ Take 3: [▃▅▇█=IN======OUT=█▇▅]                             │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ DESTINATION WINDOW:                                              │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ [▁▂▃▅][=IN=DEST=OUT=][▅▃▂▁]                                │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Multi-Take Comparison
- Simultaneous waveform display
- Quick A/B comparison
- 4-point editing (source IN/OUT + dest IN/OUT)
- Essential for classical recording

---

## 5. Waveform Display Options

### Display Modes
| Mode | Description |
|------|-------------|
| Peak | Standard amplitude |
| RMS | Average level |
| Peak + RMS | Combined |
| Vectorscope | Phase correlation |

### Color Options
- Track-based coloring
- Clip-based coloring
- Fade area visualization
- Selection highlighting

---

## 6. Mastering View

### CD Track Visualization
```
┌─────────────────────────────────────────────────────────────────┐
│ Mastering View - CD Layout                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Track 1      Track 2      Track 3      Track 4                  │
│ [▁▂▃▅▇█▇▅▃][▂▃▅▇█▇▅▃▂][▃▅▇█▇▅▃▂▁][▅▇█▇▅▃▂▁▂]                 │
│ ─────────── ─────────── ─────────── ───────────                 │
│ 3:24.12     4:15.38     5:02.67     3:48.21                     │
│                                                                  │
│ [Gap: 2s]   [Gap: 2s]   [Gap: 1s]   [Gap: 2s]                   │
│                                                                  │
│ Total: 16:30.38 / 79:57 available                               │
└─────────────────────────────────────────────────────────────────┘
```

### Red Book Elements
| Element | Visual Representation |
|---------|----------------------|
| Track markers | Vertical lines with number |
| Index points | Sub-markers |
| Gaps | Visual spacing |
| CD-Text | Overlay labels |

---

## 7. Metering Integration

### Final Check Tool
```
┌─────────────────────────────────────────────────────────────────┐
│ Integrated Display:                                              │
│                                                                  │
│ Waveform:    [▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁]                        │
│                                                                  │
│ Loudness:    -23.2 LUFS ███████████░░░░░░░░░                    │
│ True Peak:   -1.2 dBTP  ██████████████████░░                    │
│ LRA:         15.2 LU    ████████████████░░░░                    │
│                                                                  │
│ Loudness graph synchronized with waveform timeline               │
└─────────────────────────────────────────────────────────────────┘
```

### Broadcast Compliance
- EBU R128 visualization
- True Peak markers
- LRA display
- History graph

---

## 8. Multi-Channel Display

### Surround Waveforms
```
┌─────────────────────────────────────────────────────────────────┐
│ 5.1 Surround Display:                                            │
├─────────────────────────────────────────────────────────────────┤
│ L:   [▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁]                                │
│ C:   [▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁▂]                                │
│ R:   [▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁]                                │
│ Ls:  [░▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁░]                                │
│ Rs:  [░▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁░]                                │
│ LFE: [▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃]                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Up to 22.2 Support
- NHK 22.2 waveform display
- Individual channel views
- Grouped display options
- Object track visualization

---

## 9. Performance Optimizations

### MassCore Integration
| Feature | Benefit |
|---------|---------|
| Dedicated cores | Isolated waveform rendering |
| Priority processing | No audio dropouts |
| Deterministic timing | Consistent performance |

### Large Session Handling
- 384 channel support
- Efficient memory management
- Background peak generation
- Incremental loading

---

## Key Technical Patterns for FluxForge Implementation

### 1. High-Resolution Design
```rust
struct PyramixPeakCache {
    sample_rate: u32,  // Up to 384kHz
    channels: u32,     // Up to 128
    bit_depth: u32,    // 32-bit float
    levels: Vec<MipmapLevel>,
}
```

### 2. DSD Bridge Concept
- Convert to high-rate PCM for display
- Maintain DSD for playback
- Seamless scrubbing
- Frame-accurate editing

### 3. Source/Destination
- Multi-window architecture
- Take comparison system
- 4-point editing UI
- Classical workflow support

### 4. Mastering Features
- Red Book compliance display
- Gap visualization
- CD-Text overlay
- DDP preview

---

## Sources

- [Merging Technologies - Pyramix](https://www.merging.com/products/pyramix)
- [Merging Technologies - Pyramix Key Features](https://www.merging.com/products/pyramix/key-features)
- [Merging Technologies - DSD-DXD Production Guide](https://www.merging.com/uploads/assets/Merging_pdfs/Merging_Technologies_DSD-DXD_Production_Guide.pdf)
- [Production Expert - Pyramix Coverage](https://www.production-expert.com/production-expert-1/why-some-classical-recording-engineers-choose-pyramix-over-pro-tools)

---

*Document created: January 2026*
*For FluxForge Studio implementation reference*
