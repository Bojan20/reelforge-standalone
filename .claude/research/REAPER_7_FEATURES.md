# REAPER 7 Complete Feature Analysis

**Research Date:** 2026-01-15
**Purpose:** Gap analysis for FluxForge Studio comparison

---

## 1. Audio Engine

### Core Processing
| Feature | Specification |
|---------|---------------|
| **Internal Processing** | 64-bit float |
| **Max Track Channels** | 128 channels per track (up from 64 in v6) |
| **MIDI Bus Routing** | 128 buses |
| **Hardware I/O** | 128 MIDI in/out devices |
| **Track Limits** | None (unlimited) |
| **Send/Receive Limits** | None (unlimited) |

### Anticipative FX Processing
REAPER's flagship multiprocessing system:
- Runs FX processing slightly ahead of real-time
- Irregular intervals, out-of-order execution
- Achieves 95%+ utilization on 8+ core CPUs
- Dramatically lower interface latencies
- Separate "Live FX Multiprocessing" for real-time needs

### Plugin Delay Compensation (PDC)
| Feature | Description |
|---------|-------------|
| **Automatic PDC** | Activates automatically when plugins report latency |
| **Dynamic PDC** | Supports plugins that change latency at runtime |
| **Multi-channel PDC** | Per-channel delay compensation in JSFX |
| **MIDI PDC** | Optional MIDI delay compensation (`pdc_midi=1.0`) |
| **Hardware Insert PDC** | ReaInsert has built-in ping/auto-detect |
| **Performance Meter** | View per-track PDC in real-time |

### Sample Rate Handling
| Feature | Specification |
|---------|---------------|
| **Sample Rates** | 44.1kHz - 384kHz+ |
| **Resampling Engine** | r8brain free (highest quality) |
| **Playback Resampling** | Configurable: 64-192 sample point interpolation |
| **On-the-fly Conversion** | Automatic when project rate differs from source |
| **Per-FX Oversampling** | Any plugin up to 768 kHz |
| **Per-FX-Chain Oversampling** | Entire chains can be oversampled |

---

## 2. Editing Features

### Item Editing
- Non-destructive editing throughout
- Slip editing (move content within item boundaries)
- Time selection and loop selection
- Ripple editing modes (per-track or all tracks)
- Split at cursor/time selection
- Heal splits (merge adjacent items)
- Item grouping and group editing
- Item locking

### Take System (REAPER 7 Lanes)
| Feature | Description |
|---------|-------------|
| **Track Lanes** | Visual lanes for multiple takes |
| **Swipe Comping** | Click-drag to select best parts across takes |
| **One-click A/B** | Instantly compare comp versions |
| **Crossfade Control** | Customizable crossfades between comp segments |
| **Edit While Comping** | Continue recording/editing during comp |
| **Comp From Comps** | Build comps from other comps |

### Stretch Markers
- Insert at transients (auto-detected)
- Manual stretch marker insertion
- Per-marker time stretch
- Dynamic Split can generate stretch markers
- Razor edit can add stretch markers
- Pitch shift modes: polyphase synthesis, elastique

### Spectral Editing
| Feature | Description |
|---------|-------------|
| **Location** | Main project window (not separate editor) |
| **Selection** | Time + frequency box selection |
| **Operations** | Gain, fade, filter affected frequencies |
| **Controls** | Small knobs for each spectral edit region |
| **Use Cases** | Remove specific frequencies, noise reduction |

### Razor Editing
- Alt+Right-drag to marquee select portions
- Shift+Alt for multiple selections
- Discontiguous selections allowed
- Works on items AND automation envelopes
- Cut, copy, move, stretch operations
- Per-track or across multiple tracks
- REAPER 7: Dedicated tool activation action

### Track Edit Grouping (REAPER 7)
- 64 separately configurable edit groups
- Group tracks for synchronized media/razor edits
- Per-group enable/disable

---

## 3. Mixing Features

### Routing Matrix
| Feature | Description |
|---------|-------------|
| **Track Channels** | 128 internal channels per track |
| **Pin Connector** | Full matrix routing for each plugin |
| **Sends** | Unlimited, can tap from any plugin point |
| **Receives** | Unlimited |
| **Hardware Outputs** | Flexible multi-output routing |
| **Sidechain** | Native support throughout |

### FX Containers (REAPER 7)
- Self-contained FX chain modules
- Complex internal routing preserved
- Configurable parameter mapping
- Store and recall as presets
- Nest containers within containers

### Parallel FX Processing (REAPER 7)
- Right-click plugin → "Run in parallel with previous FX"
- Visual indicator (||) in FX chain
- Multiple plugins in parallel
- Works with FX containers

### Track Templates
- Save any track configuration as template
- Include FX chains, routing, settings
- Import templates via drag-drop or menu
- Hierarchical organization

### FX Chain Features
| Feature | Description |
|---------|-------------|
| **Auto-bypass** | Disable processing when input is silent |
| **Oversampling** | Per-FX or per-chain up to 768kHz |
| **Delta Solo** | Hear only what plugin is adding |
| **Gain Reduction Meters** | Visual GR feedback |
| **Multi-mono/stereo** | ReaPlug supports multiple processing modes |

### Metering (REAPER 7)
- Per-track customizable LUFS loudness metering
- Gain reduction meters
- New JSFX LUFS Loudness Meter
- New JSFX Multichannel Mapper-Downmixer

---

## 4. Recording Features

### Multi-Take Recording
| Feature | Description |
|---------|-------------|
| **Loop Recording** | Automatic new takes on each pass |
| **Lane Recording** | Takes go to lanes (REAPER 7) |
| **Overdub Mode** | Non-destructive layering |
| **Arm While Playing** | No stop required |

### Punch Recording
- Manual punch in/out
- Auto-punch with time selection
- Pre-roll/post-roll settings
- Hands-free punching (foot pedal support)
- Preserve PDC in recorded items option

### Input FX
| Feature | Description |
|---------|-------------|
| **Insert Point** | Before recording to disk |
| **Monitoring** | With or without software FX |
| **Record Options** | Before or after FX processing |
| **Zero-Latency Option** | Direct/input monitoring bypass |

### Input Monitoring
- Software monitoring (with FX)
- Direct/hardware monitoring (zero latency)
- Hybrid setups (dry direct + wet DAW)
- Per-track monitoring options

---

## 5. Customization

### Actions System
| Feature | Description |
|---------|-------------|
| **Built-in Actions** | Thousands of assignable actions |
| **Custom Actions** | Chain multiple actions together |
| **Macros** | Complex multi-step automation |
| **Conditional Actions** | If/else logic in custom actions |
| **Marker Actions** | Run actions when playhead crosses marker |
| **Context Menus** | Fully customizable |

### Keyboard Shortcuts
- Multiple shortcut sets (REAPER 7)
- Switch between sets instantly
- Different contexts (arrange, MIDI, etc.)
- Mouse modifier customization

### ReaScript (Lua, EEL, Python)
| Language | Built-in | Performance | UI Support |
|----------|----------|-------------|------------|
| **Lua v5.4** | Yes | Good | Yes (graphics, dialogs) |
| **EEL2** | Yes | High | Yes (graphics, dialogs) |
| **Python 2.7-3.x** | No (separate install) | Lower | No |

**API Access:**
- Full REAPER API (same as compiled extensions)
- Action triggering
- Parameter control
- Media item manipulation
- Project structure access

### Themes
| Feature | Description |
|---------|-------------|
| **Theme Adjuster** | Comprehensive GUI for customization |
| **Element Reordering** | Drag TCP/MCP elements |
| **Gamma/Brightness/Contrast** | Global appearance tuning |
| **Custom Themes** | .ReaperThemeZip format |
| **Theme Development SDK** | WALTER language |
| **Community Themes** | stash.reaper.fm |

### Custom Toolbars
- Add/remove actions to any toolbar
- Create new toolbars
- Custom icons
- Context-specific toolbars
- Floating or docked

---

## 6. Video Features

### Video Support (REAPER 7 Enhanced)
| Feature | Description |
|---------|-------------|
| **Codecs Input** | H.264, H.265, ProRes, DNxHD, MOV, MP4, AVI, WMV |
| **Codecs Output** | MOV, MP4, AVI (via FFmpeg) |
| **Colorspaces** | YV12, YUY2, RGB |
| **Backend** | OpenGL (automatic) |
| **Background Projects** | Video support in background tabs |

### Video Editing
- Video on any track (mixed with audio, MIDI, images)
- Cut, trim, split
- Fade in/out, crossfades
- Opacity control
- Basic motion/position
- Text titles
- Wipes, transitions

### Video Processing
| Feature | Description |
|---------|-------------|
| **Effects System** | EEL-based video processor |
| **Presets** | Community presets available |
| **Chroma Key** | Available via presets |
| **Motion Detection** | Supported |
| **Thumbnail Strip** | Timeline preview |

### Rendering to Video
- FFmpeg 4.4+ integration
- Direct export to MP4/MOV
- Social media formats
- Batch video rendering
- Separate audio/video render options

---

## 7. Unique Features

### Portable Installation
| Feature | Description |
|---------|-------------|
| **USB Install** | Full REAPER on removable drive |
| **No Registry** | Self-contained installation |
| **Settings Portable** | All preferences travel with install |
| **Cross-Platform** | Same portable install concept |

### Resource Efficiency
| Metric | REAPER |
|--------|--------|
| **Install Size** | ~15MB (macOS), ~3MB compressed |
| **RAM Idle** | ~20MB |
| **CPU Optimization** | Works well on 8 cores |
| **Minimum Specs** | 2GB RAM, any modern CPU |
| **Freeze Track** | Reduce CPU for heavy tracks |

### JSFX (Jesusonic FX)
| Feature | Description |
|---------|-------------|
| **Language** | EEL2 (C/JavaScript-like) |
| **Distribution** | Source code (text files) |
| **Editing** | Real-time in-DAW editing |
| **UI** | Custom vector-based interfaces |
| **Performance** | Compiled on load, very efficient |
| **Sharing** | gmem[] shared memory between instances |
| **Included Effects** | 200+ stock JSFX |

**Stock JSFX Categories:**
- Delays, compressors, limiters
- Convolution, distortion
- Spectral noise editors
- Analyzers (loudness, spectrum)
- Loop samplers
- Creative effects
- Loudness Meter (LUFS)
- Super 8 sampler
- Megababy MIDI sequencer

### SWS/S&M Extensions
| Feature | Description |
|---------|-------------|
| **Size** | <4MB |
| **Actions** | Hundreds of additional actions |
| **Snapshots** | Save/recall track parameters |
| **Loudness** | Analysis tools |
| **Cycle Actions** | Multi-step action sequences |
| **Region Playlist** | Non-linear playback |
| **Live Configs** | Performance/FX pedal mode |
| **Tempo Mapping** | Advanced tools |
| **Auto-Color** | Name-based coloring |
| **Groove Tool** | MIDI groove quantize |
| **Installation** | ReaPack (since 2024) |

---

## 8. Built-in Plugins (ReaPlugs)

### Dynamics
| Plugin | Features |
|--------|----------|
| **ReaComp** | Transparent compressor, sidechain, lookahead, knee control |
| **ReaGate** | Noise gate, sidechain support, ducking |
| **ReaLimit** | Limiter, ceiling control, look-ahead |
| **ReaXcomp** | Multiband compressor, per-band settings, auto-gain |

### EQ & Filters
| Plugin | Features |
|--------|----------|
| **ReaEQ** | Parametric EQ, unlimited bands, spectrum analyzer, zero-latency |
| **ReaFIR** | FFT-based EQ, noise profile subtraction |

### Time-Based
| Plugin | Features |
|--------|----------|
| **ReaDelay** | Multi-tap delay, per-tap params, modulation, ping-pong |
| **ReaVerb** | Convolution reverb, IR loading, reverb generator, modular design |

### Pitch & Tuning
| Plugin | Features |
|--------|----------|
| **ReaTune** | Tuner, auto pitch correction, manual correction, elastique algorithms |
| **ReaPitch** | Pitch shift, harmony creation, zero-latency mode |

### Analysis
| Plugin | Features |
|--------|----------|
| **ReaFIR** | Spectral display, noise profiling |
| **JS: Loudness Meter** | LUFS metering (REAPER 7) |

### Utility
| Plugin | Features |
|--------|----------|
| **ReaInsert** | Hardware insert with PDC, ping detection |
| **ReaSurround** | 3D panner, custom speaker configs |
| **ReaStream** | Network audio streaming |
| **ReaControlMIDI** | MIDI generation/control |

---

## 9. Additional Features

### Automation
| Feature | Description |
|---------|-------------|
| **Modes** | Trim/Read, Read, Write, Latch, Touch |
| **Envelopes** | Per-parameter, visible on track or lane |
| **Auto-create** | Envelopes created on parameter touch |
| **Transition Time** | Configurable envelope merge time |
| **Envelope Points** | Bezier curves, shapes |

### Markers & Regions
- Project markers
- Time signature markers
- Tempo markers
- Regions
- Region playlist (SWS)
- Marker actions (SWS)

### Media Explorer
| Feature | Description |
|---------|-------------|
| **Database** | Custom libraries with metadata |
| **Metadata** | BWF tags, BPM, Key, custom tags |
| **Preview** | Rate control, partial selection import |
| **Search** | Boolean operators (OR, NOT, quotes) |
| **Routing** | Preview through any track/output |

### Rendering
| Feature | Description |
|---------|-------------|
| **Formats** | WAV, FLAC, MP3, OGG, AIFF, etc. |
| **Stems** | Selected tracks as separate files |
| **Regions** | Batch render through regions |
| **Queue** | Save render settings, batch process |
| **Second Pass** | Two-pass loudness normalization |
| **Multi-core** | Parallel batch conversion |

### Surround/Spatial
| Feature | Description |
|---------|-------------|
| **Max Channels** | 128 per track |
| **ReaSurroundPan** | 3D panner with custom speaker layouts |
| **Atmos Support** | Via Dolby Panner plugin |
| **Ambisonic** | IEM plugin suite compatible |
| **Format Conversion** | 5.1 → 7.1 → Atmos (via scripts) |

### Project Organization
| Feature | Description |
|---------|-------------|
| **Project Tabs** | Multiple projects open |
| **Subprojects** | Nested projects as media items |
| **Background Projects** | Run multiple projects simultaneously |
| **Loopback Audio** | 256 stereo channels between tabs |
| **RPP-PROX** | Auto-rendered subproject proxies |

### Undo System
| Feature | Description |
|---------|-------------|
| **Memory Limit** | Default 30MB (configurable) |
| **Multiple Redo Paths** | Tree-based undo (optional) |
| **Per-Project** | Separate history per tab |
| **Save to Disk** | Preserve undo with project |

### Collaboration
| Feature | Description |
|---------|-------------|
| **NINJAM** | Real-time network jamming |
| **ReaStream** | Audio streaming between DAWs |
| **MTC Sync** | MIDI Time Code synchronization |
| **OSC Support** | Open Sound Control integration |

---

## 10. Plugin Format Support

| Format | Status |
|--------|--------|
| **VST2** | Full support |
| **VST3** | Full support |
| **AU** | Full support (macOS) |
| **CLAP** | Full support |
| **LV2** | Full support |
| **DX** | Full support (Windows) |
| **JSFX** | Native format |

---

## 11. Performance Optimization Settings

### Key Settings
| Setting | Recommendation |
|---------|----------------|
| **Anticipative FX** | Enable |
| **Live FX Multiprocessing** | Enable, match core count |
| **Thread Priority** | Highest |
| **Auto-detect Threads** | Enable or manually set |
| **Auto-bypass on Silence** | Enable (project setting) |
| **Buffer Size** | Low for recording, high for playback |

### Monitoring
- Performance Meter (RT CPU most useful)
- Per-track CPU display
- Plugin CPU usage
- PDC display

---

## Sources

- [REAPER Official](https://www.reaper.fm/)
- [REAPER About](https://www.reaper.fm/about.php)
- [What's New in REAPER 7 - REAPER Blog](https://reaper.blog/2023/10/whats-new-in-reaper-7/)
- [REAPER Tips](https://www.reapertips.com/)
- [SWS Extension](https://sws-extension.org/)
- [REAPER ReaScript Documentation](https://www.reaper.fm/sdk/reascript/reascript.php)
- [REAPER JSFX Programming](https://www.reaper.fm/sdk/js/js.php)
- [REAPER ReaPlugs](https://www.reaper.fm/reaplugs/)
- [REAPER PDC Guide - Home Music Maker](https://www.homemusicmaker.com/reaper-delay-compensation)
- [Spectral Editing in REAPER - Sound On Sound](https://www.soundonsound.com/techniques/spectral-editing-reaper)
- [Razor Editing - REAPER Blog](https://reaper.blog/2023/11/activating-razor-edit-tool/)
- [REAPER Automation - Envato Tuts+](https://music.tutsplus.com/how-to-use-reaper-automation-and-envelopes--cms-107723t)
- [REAPER Subprojects - Sound On Sound](https://www.soundonsound.com/techniques/reaper-subprojects)
- [SWS Extension v2.14 - REAPER Blog](https://reaper.blog/2024/02/sws-214/)
