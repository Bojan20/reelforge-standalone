# DAW Workflow Patterns Reference

## Professional Audio Software UI/UX Patterns

This document captures interaction patterns, keyboard shortcuts, and UI conventions from world-class DAWs: Pro Tools, Logic Pro, Cubase, Ableton Live, Studio One, and Reaper.

---

## 1. Timeline/Arrangement

### 1.1 Clip Editing Operations

#### Split/Separate
| DAW | Shortcut | Behavior |
|-----|----------|----------|
| Pro Tools | `Cmd+E` / `Ctrl+E` | Separate clip at insertion point |
| Logic Pro | `Cmd+T` | Split at playhead |
| Cubase | `Alt+X` | Split at cursor |
| Ableton | `Cmd+E` / `Ctrl+E` | Split clip at selection |
| Studio One | `Alt+X` | Split at cursor |
| Reaper | `S` | Split items at cursor |

#### Trim
| DAW | Tool | Behavior |
|-----|------|----------|
| Pro Tools | Trim Tool / Smart Tool edges | Drag clip boundaries to reveal/hide audio |
| Logic Pro | Pointer at edge | Resize regions |
| Cubase | Object Selection at edge | Trim events |
| Ableton | Click+drag edges | Adjust start/end |

#### Fade/Crossfade
Pro Tools Smart Tool:
- Position cursor at top corners of clip → creates fade
- Position where two clips meet → creates crossfade
- `Cmd+F` → Create fade/crossfade on selection
- `Cmd+A, Cmd+F` → Crossfade every clip in session

Standard crossfade lengths:
- Quick transitions: 5-10ms (prevents clicks)
- Smooth transitions: 20-50ms
- Musical transitions: 100ms-3s
- DJ-style: 5-30 seconds

### 1.2 Snap Modes & Grid Systems

#### Pro Tools Edit Modes
| Mode | Shortcut | Behavior |
|------|----------|----------|
| Shuffle | `F1` | Clips auto-snap to each other, no gaps |
| Spot | `F2` | Dialog for precise timecode placement |
| Slip | `F3` | Free movement, no snapping |
| Grid | `F4` | Snap to grid values |

Grid Mode Variants:
- **Absolute Grid**: Snaps to exact grid positions
- **Relative Grid**: Maintains offset from grid while moving in grid increments

#### Grid Value Settings
Common grid values:
- Bars (1, 2, 4 bars)
- Beats (1/4, 1/8, 1/16, 1/32)
- Samples (for precise editing)
- Frames (for video work)
- Min:Sec (for dialogue)

#### Adaptive Grid (Studio One)
- Automatically adjusts grid density based on zoom level
- Zoomed out = coarser grid (bars)
- Zoomed in = finer grid (beats, subdivisions)

### 1.3 Zoom/Scroll Behavior

#### Pro Tools Zoom Shortcuts
| Action | Shortcut |
|--------|----------|
| Horizontal zoom in/out | `Alt + Scroll` |
| Horizontal scroll | `Shift + Scroll` |
| Vertical audio zoom | `Alt+Shift + Scroll` |
| Vertical MIDI zoom | `Alt+Ctrl + Scroll` (Mac: `Alt+Control`) |
| Zoom to selection | `E` (in Commands Focus mode) |
| Toggle zoom preset | `E` again to toggle back |
| Zoom toggle | Uses Zoom Presets 1-5 |

#### Ableton Live Zoom
| Action | Shortcut |
|--------|----------|
| Zoom in | `+` key |
| Zoom out | `-` key |
| Zoom to selection | `Z` |
| Revert zoom state | `X` |
| Full arrangement | Double-click beat ruler |
| Zoom with trackpad | `Cmd/Ctrl + Scroll` |

#### Logic Pro Zoom
| Action | Shortcut |
|--------|----------|
| Horizontal zoom in | `Cmd + Right Arrow` |
| Horizontal zoom out | `Cmd + Left Arrow` |
| Vertical zoom in | `Cmd + Down Arrow` |
| Vertical zoom out | `Cmd + Up Arrow` |
| Zoom to fit selection | `Z` |
| Zoom to fit all | `Shift + Z` |

### 1.4 Multi-Track Selection

#### Group Types
| Type | Purpose |
|------|---------|
| Edit Groups | Linked editing operations |
| Mix Groups | Linked fader/pan/mute/solo |
| VCA Groups | Master fader control without routing |
| Folder/Track Stacks | Visual organization + optional summing |

#### Pro Tools Grouping
- `Cmd+G` → Create new group
- `Cmd+Shift+G` → Modify group
- Groups can include: Volume, Pan, Mute, Solo, Send Levels, Inserts, Record Arm, Editing

#### Selection Modifiers
| Action | Modifier |
|--------|----------|
| Add to selection | `Shift + Click` |
| Toggle selection | `Cmd/Ctrl + Click` |
| Select range | `Click` → `Shift + Click` end |
| Select all on track | `Cmd/Ctrl + A` (with track focused) |
| Select all following | DAW-specific |

### 1.5 Keyboard Shortcuts Summary

#### Universal (Most DAWs)
| Action | Mac | Windows |
|--------|-----|---------|
| Play/Stop | `Space` | `Space` |
| Record | `R` or `Cmd+R` | `R` or `Ctrl+R` |
| Undo | `Cmd+Z` | `Ctrl+Z` |
| Redo | `Cmd+Shift+Z` | `Ctrl+Shift+Z` |
| Save | `Cmd+S` | `Ctrl+S` |
| Cut | `Cmd+X` | `Ctrl+X` |
| Copy | `Cmd+C` | `Ctrl+C` |
| Paste | `Cmd+V` | `Ctrl+V` |
| Duplicate | `Cmd+D` | `Ctrl+D` |
| Delete | `Delete` | `Delete` |
| Select All | `Cmd+A` | `Ctrl+A` |

---

## 2. Mixer Workflows

### 2.1 Channel Strip Layout

#### Standard Signal Flow
```
Input → Inserts (Pre-Fader) → EQ → Dynamics → Fader → Pan → Sends (Post-Fader) → Output
```

#### Cubase Channel Strip
Position in signal flow (configurable):
- Gate
- Compressor (Standard/Tube/Vintage)
- EQ
- Tools (De-esser/Envelope Shaper)
- Saturation
- Limiter

Pro Tip: Copy channel strip settings: `Cmd/Ctrl + Click+Drag` from Strip header to destination.

### 2.2 Routing Matrix Patterns

#### Output Routing Hierarchy
```
Track Output → Group/Bus → Master Bus
              ↓
         FX Returns ← FX Sends
```

#### Common Bus Configurations
| Bus Type | Purpose | Count |
|----------|---------|-------|
| Drums | Drum submix | 1-2 |
| Bass | Bass instruments | 1 |
| Guitars | All guitars | 1-2 |
| Keys/Synths | Keyboards | 1-2 |
| Vocals | All vocals | 1-2 |
| FX Returns | Reverb/Delay | 2-4 |
| Parallel Compression | NY compression | 1-2 |
| Master | Final output | 1 |

### 2.3 Aux/Bus/VCA Grouping

#### VCA vs Submix Comparison
| Feature | VCA | Submix Bus |
|---------|-----|-----------|
| Audio routing | No | Yes |
| Insert effects | No | Yes |
| Post-fader sends behavior | Fades with VCA | Independent |
| Parallel processing | No | Yes |
| CPU overhead | None | Minimal |

**VCA Use Cases:**
- Automation trim across multiple tracks
- Quick level adjustments without affecting sends
- Mix balancing

**Submix Use Cases:**
- Group processing (bus compression)
- Parallel effects
- Stem exports

### 2.4 Insert/Send Workflow

#### Insert Workflow
- Pre-fader (default position)
- 6-8 slots typical
- Signal flows through sequentially
- Drag to reorder

#### Send Workflow
| Type | Signal Source | Use Case |
|------|--------------|----------|
| Pre-Fader | Before fader | Headphone cue mixes |
| Post-Fader | After fader | Effects sends (reverb, delay) |

### 2.5 Metering Placement & Behavior

#### Meter Types
| Type | Response | Reference | Use |
|------|----------|-----------|-----|
| VU | ~300ms integration | -18dBFS = 0VU | Average level, analog feel |
| PPM | Fast attack (~10ms) | Various | Peak detection |
| True Peak | Inter-sample | 0dBTP | Digital clipping prevention |
| LUFS | 400ms / 3s / Integrated | Various | Loudness measurement |

#### LUFS Standards
| Platform | Target | True Peak |
|----------|--------|-----------|
| Spotify | -14 LUFS | -1 dBTP |
| Apple Music | -16 LUFS | -1 dBTP |
| YouTube | -14 LUFS | -1 dBTP |
| Broadcast (EBU R128) | -23 LUFS | -1 dBTP |
| Broadcast (ATSC A/85) | -24 LKFS | -2 dBTP |

**Best Practice:** Place LUFS meter as last plugin on master bus.

---

## 3. Transport & Navigation

### 3.1 Locators and Markers

#### Pro Tools Memory Locations
| Action | Shortcut |
|--------|----------|
| Create marker | `Enter` (numpad) |
| Navigate to marker | `Period + Number + Period` |
| Previous/Next marker | `Tab` over marker ruler |

#### Logic Pro Markers
| Action | Shortcut |
|--------|----------|
| Create marker | `Option + '` |
| Previous marker | `Option + ,` |
| Next marker | `Option + .` |
| Rename marker | `Shift + Cmd + '` |

#### Ableton Locators
| Action | Shortcut |
|--------|----------|
| Create locator | `Ctrl/Cmd + Shift + A` |
| Previous locator | Mappable |
| Next locator | Mappable |
| Jump to locator | Click in scrub area |

### 3.2 Loop/Cycle Regions

#### Setting Loop Points
| DAW | Method |
|-----|--------|
| Pro Tools | Click+drag in ruler / Selection → Loop |
| Logic | Drag in ruler / `Cmd+U` from selection |
| Cubase | Drag locators / `P` to set from selection |
| Ableton | Drag loop brace / Select → `Cmd+L` |

#### Logic Cycle Tips
- Move cycle forward/back: `Shift+Cmd + < / >`
- Move by markers: `Option + < / >`

### 3.3 Scrubbing/Shuttling

#### Scrub Modes
| Mode | Behavior |
|------|----------|
| Scrub | Audio follows jog wheel speed |
| Shuttle | Continuous playback, speed controlled by wheel position |
| Jog | Frame-by-frame movement |

#### Hardware Controllers
- Contour ShuttlePRO v2: 15 programmable buttons + jog/shuttle
- Contour Shuttle Xpress: 5 buttons + jog/shuttle (compact)
- Reports: 10-30% time savings over mouse-only editing

### 3.4 Pre-Roll/Post-Roll

#### Settings
| Parameter | Typical Range | Use |
|-----------|---------------|-----|
| Pre-roll | 1-4 bars | Hear context before punch-in |
| Post-roll | 1-2 bars | Verify recording after punch-out |

#### Pro Tools Pre/Post Roll
- Click time display values to edit
- Use with punch record for seamless drops

### 3.5 Punch In/Out Recording

#### Quick Punch Mode
- Drop in/out of record on the fly
- Non-destructive (original audio preserved)
- Multiple takes possible

#### Pre/Post with Punch
1. Set locators for punch region
2. Enable Punch In/Out
3. Enable Pre-roll/Post-roll
4. Playback starts at pre-roll
5. Auto-punch at left locator
6. Auto-punch out at right locator
7. Continue playing through post-roll

---

## 4. Plugin Windows

### 4.1 Floating vs Embedded

| Approach | DAW Examples | Pros | Cons |
|----------|--------------|------|------|
| Floating | Pro Tools, Logic | Multi-monitor, flexible | Window management overhead |
| Embedded | Ableton (bottom panel) | Always visible, consistent | Limited space |
| Hybrid | Bitwig, Cubase | Best of both | More complex |

#### Bitwig Window Management
- Everything dockable, floatable, resizable
- Display Profiles for different monitor setups
- Pop-out windows to different monitors

### 4.2 A/B Comparison

#### Built-in A/B
Many plugins include:
- A/B button to toggle between two settings
- Copy A→B / B→A functionality
- Some support up to 8 snapshots (A-H)

#### External Tools
- **EXPOSE by Mastering the Mix**: Auto-gain matching, instant switching
- **Reference**: Compare against commercial tracks
- Arrow keys for quick A/B with minimal audible gap

### 4.3 Preset Management

#### Standard Patterns
- Factory presets (read-only)
- User presets (writable)
- Folder organization
- Favorites/tags
- Search functionality

#### DAW Preset Systems
| DAW | Format | Features |
|-----|--------|----------|
| Pro Tools | Plugin-specific | Session recall |
| Logic | .fxp/.aupreset | Channel strip presets |
| Cubase | .vstpreset | MediaBay integration |
| Ableton | .adv/.adg | Device presets |

### 4.4 Parameter Linking

- MIDI Learn (map controller to parameter)
- Modulation routing (LFO → parameters)
- Macro controls (one knob → multiple params)
- Parameter automation lanes

### 4.5 Undo/Redo Scope

| Scope | Description |
|-------|-------------|
| Global Undo | All changes in session |
| Plugin Undo | Only plugin changes |
| Edit Undo | Only edit operations |

Note: Some plugins maintain their own undo stack separate from DAW.

---

## 5. Drag & Drop

### 5.1 Audio File Import

#### Common Behaviors
| Action | Result |
|--------|--------|
| Drag to empty area | Create new track |
| Drag to track | Place at drop point |
| Drag to timeline ruler | Place at bar/beat |

#### Import Options
- Copy to project folder (recommended)
- Reference original location
- Convert sample rate
- Convert bit depth

### 5.2 Clip Movement

#### Pro Tools Drag Behaviors
- Normal drag: Move clip
- `Option + Drag`: Copy clip
- `Ctrl + Drag` (Mac): Constrain to track

### 5.3 Effect Routing

- Drag plugin to insert slot
- Drag between slots to reorder
- Drag to different track to copy
- `Option/Alt + Drag` typically copies

### 5.4 Cross-Window Operations

- Drag from browser to timeline
- Drag from timeline to sampler
- Drag between DAW and Finder/Explorer
- Drag plugin from favorites to insert

---

## 6. Selection & Editing

### 6.1 Time Selection vs Object Selection

| Type | Purpose | Tool |
|------|---------|------|
| Time Selection | Select time range across tracks | Selector/Range tool |
| Object Selection | Select clips/events | Pointer/Object tool |

#### Pro Tools Smart Tool Zones
- Top half of clip → Selector (time selection)
- Bottom half of clip → Grabber (object selection)
- Edges → Trimmer
- Corners → Fade handles

### 6.2 Edit Modes

#### Pro Tools Edit Modes
| Mode | Behavior |
|------|----------|
| Shuffle | Clips ripple to close gaps |
| Slip | Free movement |
| Spot | Precise numerical placement |
| Grid | Snap to grid |

#### Relative vs Absolute Grid
- **Absolute**: Clips snap to exact grid lines
- **Relative**: Clips maintain their offset while moving in grid increments

### 6.3 Ripple Editing

#### What is Ripple Edit?
When you delete/cut, content after the edit point moves to close the gap.

#### DAW Support
| DAW | Ripple Support |
|-----|---------------|
| Pro Tools | Shuffle mode |
| Reaper | Full ripple editing with options |
| Studio One | Ripple Edit button |
| Logic | Cut/Insert Time (not per-track ripple) |
| Premiere/Resolve | Native ripple tools |

#### Ripple Options
- Ripple selected tracks only
- Ripple all tracks
- Ripple from cursor to end
- Ripple within selection

**Best Practice:** Enable ripple only when needed, disable immediately after to avoid unintended timeline shifts.

### 6.4 Group Editing

#### Linked Track Editing (Ableton 11+)
- Link multiple tracks for phase-locked editing
- Comping across multiple tracks
- Edit one, all follow

#### Pro Tools Edit Groups
| Property | Effect |
|----------|--------|
| Edit | Cuts, fades, nudges sync |
| Clip Gain | Gain changes sync |
| Automation | Automation editing syncs |

#### Use Cases
- Drum editing (multi-mic phase alignment)
- Vocal comping (lead + doubles)
- Orchestra sections (strings, brass, etc.)

---

## 7. Implementation Recommendations for ReelForge

### 7.1 Timeline Priorities

1. **Smart Tool implementation**
   - Zone-based tool switching (Pro Tools model)
   - Top half = selection, bottom half = grab, edges = trim

2. **Snap/Grid system**
   - Absolute and Relative modes
   - Adaptive grid based on zoom
   - Common values: bars, beats, frames, samples

3. **Zoom behavior**
   - Scroll wheel + modifiers for zoom
   - Zoom to selection
   - Zoom presets with toggle

### 7.2 Mixer Priorities

1. **Channel strip order flexibility**
   - Configurable insert/strip order
   - Drag to reorder

2. **Metering**
   - VU, PPM, LUFS, True Peak options
   - Place meters at strategic points
   - Color gradient for level indication

3. **Routing matrix**
   - Visual patching or dropdown menus
   - Bus/VCA hybrid approach

### 7.3 Keyboard Shortcuts

1. **Follow conventions**
   - Space = Play/Stop
   - R = Record
   - Cmd/Ctrl+E = Split
   - Cmd/Ctrl+D = Duplicate

2. **Customization**
   - User-definable shortcuts
   - Import/export shortcut sets
   - Single-key mode (like Pro Tools Commands Focus)

### 7.4 Unique Opportunities

Areas where ReelForge can differentiate:

1. **GPU-accelerated waveforms** with real-time LOD
2. **Modern touch gestures** for zoom/scroll
3. **Smart crossfades** with curve presets
4. **Integrated loudness metering** per track
5. **Contextual tool switching** based on click position

---

## Sources

### Pro Tools
- [47 Must-Know Pro Tools Shortcuts (Evercast)](https://www.evercast.us/blog/pro-tools-shortcuts)
- [Pro Tools Shortcuts Guide (Splice)](https://splice.com/blog/pro-tools-shortcuts-guide/)
- [Pro Tools 2025.10 Workflow Tips](https://www.nico-essig.com/post/boost-your-pro-tools-2025-10-workflow-with-shortcuts-macros-and-stream-deck-tips)
- [Pro Tools Editing with Smart Tool (Sound on Sound)](https://www.soundonsound.com/techniques/pro-tools-editing-smart-tool)
- [Edit Modes in Pro Tools (Pro Tools Training)](https://www.protoolstraining.com/blog-help/pro-tools-blog/tips-and-tricks/457-edit-modes-in-pro-tools-explained)
- [Navigating Pro Tools with Ease (Sound on Sound)](https://www.soundonsound.com/techniques/navigating-pro-tools-ease)
- [Smart Tool in Pro Tools (Pro Mix Academy)](https://promixacademy.com/blog/using-the-smart-tool-in-pro-tools/)

### Logic Pro
- [11 Logic Pro Tips (Why Logic Pro Rules)](https://whylogicprorules.com/11-logic-pro-tips-improve-workflow/)
- [Logic Pro Key Commands Ultimate Guide (Morningdew Media)](https://www.morningdewmedia.com/logic-pro-key-commands-ultimate-guide/)
- [40+ Logic Pro Shortcuts (Hyperbits)](https://hyperbits.com/logic-pro-shortcuts/)
- [Logic Pro Cycling Tips (macProVideo)](https://macprovideo.com/article/audio-software/6-logic-pro-x-cycling-tips-for-a-faster-production-workflow)

### Cubase
- [Cubase Channel Strip Processors (MusicTech)](https://musictech.com/tutorials/cubase/cubase-channel-strip-processors/)
- [Cubase MixConsole Rack (Sound on Sound)](https://www.soundonsound.com/techniques/using-cubases-mixconsole-rack)
- [Cubase 14 Channel Settings (Steinberg)](https://www.steinberg.help/r/cubase-pro/14.0/en/cubase_nuendo/topics/mixconsole/mixconsole_channel_settings_channel_strip_equalizer_r.html)
- [Cubase Routing for Mixing (Skippy Studio)](https://skippystudio.nl/2024/10/cubase-routing-for-mixing-and-recording/)

### Ableton Live
- [Arrangement View Manual (Ableton)](https://www.ableton.com/en/manual/arrangement-view/)
- [Quick Editing in Arrangement View (MusicTech)](https://musictech.com/tutorials/ableton-live/quick-editing-in-ableton-lives-arrangement-view/)
- [Session & Arrangement Views (Sound on Sound)](https://www.soundonsound.com/techniques/ableton-live-session-arrangement-views)
- [10 Essential Workflow Tips (Production Music Live)](https://www.productionmusiclive.com/blogs/news/10-essential-workflow-tips-for-ableton-live)

### Metering & Standards
- [Audio Metering Ultimate Guide (eMastered)](https://emastered.com/blog/audio-metering)
- [Mixing with LEVELS (Mastering the Mix)](https://www.masteringthemix.com/pages/mixing-with-levels)
- [What is Metering (iZotope)](https://www.izotope.com/en/learn/what-is-metering-in-mixing-and-mastering.html)
- [Loudness Standards LUFS (Sweetwater)](https://www.sweetwater.com/insync/what-is-lufs-and-why-should-i-care/)

### VCA & Routing
- [VCA vs Sub-Groups (iZotope)](https://www.izotope.com/en/learn/the-difference-between-vca-and-sub-groups-in-mixing.html)
- [What Are VCA Faders (Mixing Monster)](https://mixingmonster.com/what-are-vca-faders-in-audio-mixing/)
- [Buses vs VCAs vs Groups (Techie MD)](https://techiemd.wordpress.com/2025/06/19/busses-vs-vcas-vs-groups-vs-track-stacks-in-logic-pro-x-how-to-differentiate-and-use-them-like-a-pro/)

### Group Editing & Ripple
- [What Are DAW Groups (Fox Music Production)](https://foxmusicproduction.com/daw-groups/)
- [Understanding Ripple Editing (Craig Anderton)](https://craiganderton.org/understanding-ripple-editing/)
- [Ripple Edit in Studio One 4 (Sound on Sound)](https://www.soundonsound.com/techniques/ripple-edit-studio-one-4)

### Hardware Controllers
- [Contour ShuttlePRO v2 (Contour Design)](https://contourdesign.com/products/shuttle-pro-v2)
- [Mackie Control Jog/Scrub (Apple Support)](https://support.apple.com/guide/logicpro-css/jogscrub-wheel-ctls72228ef7/mac)

---

*Document created: 2026-01-10*
*For ReelForge DAW development reference*
