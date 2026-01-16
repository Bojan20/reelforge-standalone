# Apple Logic Pro — Waveform Display & Zoom System Analysis

## 1. Peak Cache System

### Cache Location
| Element | Path |
|---------|------|
| Project cache | Inside .logicx package |
| System cache | ~/Library/Caches/com.apple.logic10 |
| Audio files | Within project package |

### Cache Characteristics
- Integrated within project package
- Automatic generation on import
- Multi-resolution peak data
- Seamless rebuild if corrupted

---

## 2. GPU Acceleration (Metal)

### Rendering Technology
| Feature | Implementation |
|---------|----------------|
| Primary | Metal (Apple Silicon native) |
| Fallback | OpenGL (Intel) |
| UI Framework | AppKit + Metal |

### Metal Benefits
- Native Apple Silicon optimization
- Efficient GPU memory management
- Smooth zoom and scroll
- 120fps capable (ProMotion displays)

### Performance
- Hardware-accelerated waveform rendering
- Efficient layer compositing
- GPU-powered effects overlays
- Minimal CPU for display

---

## 3. Zoom System

### Zoom Controls
| Control | Function |
|---------|----------|
| Cmd+Arrow | Horizontal zoom |
| Ctrl+Arrow | Vertical zoom |
| Pinch gesture | Trackpad zoom |
| Slider | Fine control |
| Auto-zoom | Options available |

### Trackpad Gestures
```
Gestures:
├── Pinch: Horizontal zoom
├── Shift+Pinch: Vertical zoom
├── Two-finger scroll: Navigate
└── Double-tap: Zoom to selection
```

### Zoom Presets
- Store current zoom: Ctrl+Option+Cmd+[1-3]
- Recall zoom: Option+Cmd+[1-3]
- 3 preset slots available

### Zoom Behavior
| Mode | Description |
|------|-------------|
| Standard | Zoom centered on playhead |
| Selection | Zoom to selected region |
| Overview | Full project view |
| Sample | Maximum detail |

---

## 4. Flex Time/Pitch Visualization

### Flex Time Display
```
┌─────────────────────────────────────────────────────────────────┐
│ Flex Mode: Rhythmic                                              │
├─────────────────────────────────────────────────────────────────┤
│       ○         ○         ○         ○    ← Flex markers         │
│ ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁                             │
│       ↕         ↕         ↕         ↕    ← Drag handles         │
│                                                                  │
│ Transients shown as vertical lines                               │
└─────────────────────────────────────────────────────────────────┘
```

### Flex Pitch Display
```
┌─────────────────────────────────────────────────────────────────┐
│ Pitch │                                                          │
│   C4 ─│───────[████████]──────────────────────                  │
│   B3 ─│───────────────────[██████]────────────                  │
│   A3 ─│─[██████]──────────────────[████]──────                  │
│       │                                                          │
│ Waveform visible behind pitch notes                              │
└─────────────────────────────────────────────────────────────────┘
```

### Flex Markers
| Marker Type | Color | Purpose |
|-------------|-------|---------|
| Transient | Gray | Auto-detected |
| User | Orange | Manually placed |
| Anchor | Yellow | Fixed points |

---

## 5. Waveform Display Options

### Display Preferences
```
Logic Pro > Settings > Display > Waveform:
├── Show Waveforms: On/Off
├── Waveform Zoom Level
├── Waveform Color Mode
├── Stereo/Mono Display
└── Fade Curve Display
```

### Color Modes
| Mode | Description |
|------|-------------|
| Track Color | Inherit from track |
| Region Color | Per-region coloring |
| Custom | User-defined colors |

### Stereo Display
- Dual channel (stacked)
- Merged (overlapped)
- Sum (mono preview)
- Side-by-side

---

## 6. Sample Editor Features

### Sample-Level View
```
┌─────────────────────────────────────────────────────────────────┐
│ Sample Editor - Maximum Zoom                                     │
├─────────────────────────────────────────────────────────────────┤
│ Time: 00:01:234.567                                              │
│                                                                  │
│     ●                                                            │
│    ●  ●                           ●                              │
│   ●    ●                         ● ●                             │
│  ●      ●       ●               ●   ●                            │
│ ●        ●     ● ●             ●     ●                           │
│           ●   ●   ●           ●       ●                          │
│            ● ●     ●         ●                                   │
│             ●       ●       ●                                    │
│                      ●     ●                                     │
│                       ● ● ●                                      │
│ Individual samples as dots, connected by lines                   │
└─────────────────────────────────────────────────────────────────┘
```

### Pencil Tool
- Draw individual samples
- Repair clicks/pops
- Sample-accurate editing
- Undo support

---

## 7. Screensets & Layout

### Screenset Workflow
| Screenset | Typical Use |
|-----------|-------------|
| 1 | Arrange (large waveforms) |
| 2 | Mix (smaller waveforms) |
| 3 | Edit (detailed view) |
| 4 | Score (minimal waveforms) |

### Track Height Options
| Size | Use Case |
|------|----------|
| Minimum | Overview, many tracks |
| Small | Standard mixing |
| Medium | General editing |
| Large | Detailed editing |
| Maximum | Fine waveform work |

---

## 8. Multi-Resolution Display

### Resolution Levels
```
Display Resolution Hierarchy:
├── Overview: 1 peak per 1000+ samples
├── Standard: 1 peak per 100 samples
├── Detail: 1 peak per 10 samples
├── High: 1 peak per sample
└── Sample: Individual sample points
```

### Automatic Selection
- Based on horizontal zoom level
- Smooth LOD transitions
- No visible artifacts
- Efficient memory usage

---

## 9. Performance Features

### Large Project Handling
| Feature | Benefit |
|---------|---------|
| Lazy loading | Load waveforms on demand |
| Background generation | Non-blocking import |
| Memory management | Efficient caching |
| Track freezing | Reduce display load |

### Optimization Tips
1. Use Freeze for complex tracks
2. Close unused track lanes
3. Use appropriate zoom level
4. Consider Project Alternatives for versions

### Apple Silicon Optimization
- Native M1/M2/M3 performance
- Unified memory benefits
- Neural Engine for analysis
- ProMotion display support

---

## 10. Smart Tempo Visualization

### Tempo Analysis Display
```
┌─────────────────────────────────────────────────────────────────┐
│ Smart Tempo Editor                                               │
├─────────────────────────────────────────────────────────────────┤
│ Beat Markers: |  |  |  |  |  |  |  |  |  |                      │
│                                                                  │
│ Waveform:     ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██                    │
│                                                                  │
│ Tempo Curve:  ─────────╱────────────╲───────────                │
│               120   122   121   119   120 BPM                    │
└─────────────────────────────────────────────────────────────────┘
```

### Elements
| Element | Description |
|---------|-------------|
| Beat markers | Detected downbeats |
| Tempo curve | BPM over time |
| Waveform | Audio reference |
| Analysis quality | Confidence display |

---

## Key Technical Patterns for FluxForge Implementation

### 1. Metal Rendering
```rust
// Conceptual Metal integration
struct MetalWaveformRenderer {
    device: metal::Device,
    command_queue: metal::CommandQueue,
    peak_buffer: metal::Buffer,
    render_pipeline: metal::RenderPipeline,
}
```

### 2. Gesture Support
- Pinch zoom (trackpad)
- Momentum scrolling
- Double-tap zoom
- Force Touch peek

### 3. Flex Visualization
- Transient overlay
- Pitch note display
- Marker system
- Real-time preview

### 4. Smart Tempo
- Beat detection display
- Tempo curve overlay
- Analysis visualization
- Confidence indicators

---

## Sources

- [Logic Pro User Guide](https://support.apple.com/guide/logicpro/welcome/mac)
- [Logic Pro Release Notes](https://support.apple.com/en-us/109503)
- [Sound on Sound - Logic Pro Techniques](https://www.soundonsound.com/techniques)
- [Logic Pro Help](https://www.logicprohelp.com)
- [Music Tech - Logic Tutorials](https://musictech.com/tutorials/logic-pro/)

---

*Document created: January 2026*
*For FluxForge Studio implementation reference*
