# FluxForge Studio — Project Format Deep Dive

> Detaljne specifikacije project formata po uzoru na REAPER RPP (human-readable)

---

## 1. THE PROBLEM WITH BINARY PROJECT FILES

### 1.1 Industry Status

```
PROJECT FORMAT COMPARISON
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌───────────────┬──────────────┬───────────────┬─────────────────────────┐│
│  │ DAW           │ Format       │ Type          │ Problems                ││
│  ├───────────────┼──────────────┼───────────────┼─────────────────────────┤│
│  │ Pro Tools     │ .ptx         │ Binary        │ Opaque, no git diff     ││
│  │ Logic Pro     │ .logic       │ Package+Binary│ Partially readable      ││
│  │ Cubase        │ .cpr         │ Binary        │ Opaque, corruption      ││
│  │ Ableton       │ .als         │ Gzip XML      │ Better but bloated      ││
│  │ FL Studio     │ .flp         │ Binary        │ Completely opaque       ││
│  │ Studio One    │ .song        │ Zip+XML       │ Moderate                ││
│  │ REAPER        │ .rpp         │ Plain text    │ NONE! ✓                 ││
│  │ Ardour        │ .ardour      │ XML           │ Verbose but readable    ││
│  └───────────────┴──────────────┴───────────────┴─────────────────────────┘│
│                                                                              │
│  PROBLEMS WITH BINARY FORMATS:                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ 1. NO VERSION CONTROL                                                   ││
│  │    • Git diff shows: "Binary files differ"                              ││
│  │    • Can't see what changed between commits                            ││
│  │    • Merge conflicts are impossible to resolve                         ││
│  │    • Can't cherry-pick specific changes                                ││
│  │                                                                          ││
│  │ 2. NO EXTERNAL EDITING                                                   ││
│  │    • Can't batch-rename tracks with sed/awk                            ││
│  │    • Can't script project modifications                                ││
│  │    • Can't programmatically generate projects                          ││
│  │                                                                          ││
│  │ 3. CORRUPTION = TOTAL LOSS                                               ││
│  │    • Single bit flip = unreadable project                              ││
│  │    • No way to manually repair                                         ││
│  │    • Backup or lose everything                                         ││
│  │                                                                          ││
│  │ 4. DEBUGGING NIGHTMARES                                                  ││
│  │    • User reports bug: "My project won't open"                         ││
│  │    • Developer: "Send me the file"                                     ││
│  │    • Can only load in DAW, can't inspect                               ││
│  │                                                                          ││
│  │ 5. INTEROPERABILITY                                                      ││
│  │    • Can't convert between DAWs                                        ││
│  │    • No standard format                                                ││
│  │    • AAF/OMF only partial solutions                                    ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 REAPER RPP — The Gold Standard

```
REAPER RPP FORMAT
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  SAMPLE RPP FILE:                                                            │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ <REAPER_PROJECT 0.1 "7.0" 1705315200                                    ││
│  │   RIPPLE 0                                                              ││
│  │   GROUPOVERRIDE 0 0 0                                                   ││
│  │   AUTOXFADE 1                                                           ││
│  │   ENVATTACH 1                                                           ││
│  │   TEMPO 120 4 4                                                         ││
│  │   PLAYRATE 1 0 0.25 4                                                   ││
│  │   MASTERAUTOMODE 0                                                      ││
│  │   MASTERTRACKHEIGHT 0 0                                                 ││
│  │   MASTERMUTESOLO 0                                                      ││
│  │   MASTERTRACKVIEW 0 0.6667 0.5 0.5 0 0 0                               ││
│  │   <TRACK                                                                ││
│  │     NAME "Vocals"                                                       ││
│  │     PEAKCOL 16576           # Track color                               ││
│  │     BEAT -1                                                             ││
│  │     AUTOMODE 0                                                          ││
│  │     VOLPAN 1 0 -1 -1 1      # Volume, Pan, L, R, Width                 ││
│  │     MUTESOLO 0 0 0                                                      ││
│  │     IPHASE 0                # Input phase                               ││
│  │     ISBUS 0 0               # Folder depth                              ││
│  │     BUSCOMP 0 0             # Bus comp settings                         ││
│  │     <FXCHAIN                                                            ││
│  │       WNDRECT 0 0 0 0                                                   ││
│  │       SHOW 0                                                            ││
│  │       LASTSEL 0                                                         ││
│  │       DOCKED 0                                                          ││
│  │       <VST "VST: ReaEQ (Cockos)" reaeq.dll 0 "" 1919247729              ││
│  │         bWFjcwAAAAB...      # Base64 state                              ││
│  │       >                                                                 ││
│  │     >                                                                   ││
│  │     <ITEM                                                               ││
│  │       POSITION 10.5                                                     ││
│  │       LENGTH 45.2                                                       ││
│  │       LOOP 0                                                            ││
│  │       ALLTAKES 0                                                        ││
│  │       FADEIN 1 0.01 0 1 0 0 0                                          ││
│  │       FADEOUT 1 0.01 0 1 0 0 0                                          ││
│  │       MUTE 0                                                            ││
│  │       SEL 0                                                             ││
│  │       NAME "Vocal Take 3"                                               ││
│  │       VOLPAN 1 0 1 -1                                                   ││
│  │       <SOURCE WAVE                                                      ││
│  │         FILE "audio/vocal_take3.wav"                                    ││
│  │         STARTPOS 5.2        # Offset into source file                   ││
│  │       >                                                                 ││
│  │     >                                                                   ││
│  │   >                                                                     ││
│  │ >                                                                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  BENEFITS:                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Git-friendly — meaningful diffs                                      ││
│  │ ✓ Human-readable — understand structure at glance                      ││
│  │ ✓ Script-editable — sed, awk, Python can modify                        ││
│  │ ✓ Recoverable — partial corruption = partial data                      ││
│  │ ✓ Debuggable — open in text editor to inspect                          ││
│  │ ✓ Mergeable — text merge tools work                                    ││
│  │ ✓ Versionable — track project evolution over time                      ││
│  │ ✓ Lightweight — plain text compresses well                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. FLUXFORGE PROJECT FORMAT (.flux)

### 2.1 Design Principles

```
FLUXFORGE PROJECT FORMAT PRINCIPLES
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  1. HUMAN-READABLE                                                           │
│     • JSON for structure (standard, tooling)                                │
│     • Clear field names, no abbreviations                                   │
│     • Comments allowed (JSON5 or JSONC)                                     │
│                                                                              │
│  2. GIT-OPTIMIZED                                                            │
│     • One line per logical unit                                             │
│     • Consistent key ordering                                               │
│     • Minimal nesting where possible                                        │
│     • No UUIDs (deterministic IDs)                                          │
│                                                                              │
│  3. VERSIONED SCHEMA                                                         │
│     • Schema version in header                                              │
│     • Backward compatibility guaranteed                                     │
│     • Migration scripts for old versions                                    │
│                                                                              │
│  4. MODULAR                                                                  │
│     • Main file: .flux (project metadata + structure)                       │
│     • Track files: .flux-track (per-track data)                            │
│     • Plugin states: .flux-state (base64 or JSON)                          │
│     • Undo history: .flux-undo (optional, .gitignore)                       │
│                                                                              │
│  5. RELATIVE PATHS                                                           │
│     • All paths relative to project root                                    │
│     • Portable between machines                                             │
│     • Works on any OS                                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Project Structure

```
PROJECT DIRECTORY STRUCTURE
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  my-song/                                                                    │
│  ├── my-song.flux                 # Main project file                       │
│  ├── .flux/                       # Project data directory                  │
│  │   ├── schema.json              # Schema version info                     │
│  │   ├── tracks/                  # Per-track data                          │
│  │   │   ├── track-001.json       # Vocal track                            │
│  │   │   ├── track-002.json       # Guitar track                           │
│  │   │   └── track-003.json       # Drums track                            │
│  │   ├── clips/                   # Clip metadata                           │
│  │   │   ├── clip-001.json        # Audio clip 1                           │
│  │   │   └── clip-002.json        # Audio clip 2                           │
│  │   ├── plugins/                 # Plugin states                           │
│  │   │   ├── eq-instance-001.json # EQ settings                            │
│  │   │   └── comp-instance-001.json # Compressor settings                  │
│  │   ├── automation/              # Automation data                         │
│  │   │   ├── track-001-volume.json                                         │
│  │   │   └── track-001-pan.json                                            │
│  │   └── history/                 # Undo history (gitignore)                │
│  │       └── undo-stack.json                                               │
│  ├── audio/                       # Audio files                             │
│  │   ├── vocal-take-1.wav                                                  │
│  │   ├── vocal-take-2.wav                                                  │
│  │   └── drums-stereo.wav                                                  │
│  ├── bounces/                     # Exported audio                          │
│  │   └── my-song-master.wav                                                │
│  ├── .gitignore                   # Ignore: peaks, history, cache          │
│  └── README.md                    # Project notes (optional)                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Main Project File Schema

```json
// my-song.flux
{
  "$schema": "https://fluxforge.io/schema/v1/project.json",
  "version": "1.0.0",
  "fluxforge_version": "1.0.0",
  "created_at": "2026-01-14T10:30:00Z",
  "modified_at": "2026-01-14T15:45:00Z",

  "project": {
    "name": "My Song",
    "artist": "Artist Name",
    "album": "Album Title",
    "description": "Demo session for new single",
    "tags": ["rock", "demo", "2026"]
  },

  "settings": {
    "sample_rate": 48000,
    "bit_depth": 32,
    "format": "float",
    "tempo": 120.0,
    "time_signature": {
      "numerator": 4,
      "denominator": 4
    },
    "key": "C",
    "scale": "major",
    "start_time": 0.0,
    "end_time": 180.0,
    "loop_start": 0.0,
    "loop_end": 180.0,
    "loop_enabled": false
  },

  "markers": [
    { "id": 1, "position": 0.0, "name": "Intro", "color": "#4A9EFF" },
    { "id": 2, "position": 16.0, "name": "Verse 1", "color": "#40FF90" },
    { "id": 3, "position": 48.0, "name": "Chorus", "color": "#FF9040" },
    { "id": 4, "position": 80.0, "name": "Verse 2", "color": "#40FF90" },
    { "id": 5, "position": 112.0, "name": "Bridge", "color": "#FF40A0" },
    { "id": 6, "position": 144.0, "name": "Outro", "color": "#4A9EFF" }
  ],

  "tempo_map": [
    { "position": 0.0, "tempo": 120.0, "curve": "linear" },
    { "position": 112.0, "tempo": 115.0, "curve": "smooth" },
    { "position": 144.0, "tempo": 120.0, "curve": "linear" }
  ],

  "tracks": [
    { "id": 1, "file": ".flux/tracks/track-001.json" },
    { "id": 2, "file": ".flux/tracks/track-002.json" },
    { "id": 3, "file": ".flux/tracks/track-003.json" },
    { "id": 4, "file": ".flux/tracks/track-master.json" }
  ],

  "routing": {
    "sends": [
      { "from": 1, "to": 10, "level_db": -6.0, "pre_fader": false },
      { "from": 2, "to": 10, "level_db": -12.0, "pre_fader": false }
    ],
    "master_output": 4
  },

  "metadata": {
    "session_notes": "Recorded at Studio A, January 2026",
    "engineer": "John Doe",
    "producer": "Jane Smith",
    "custom": {
      "client": "Record Label Inc.",
      "project_code": "RL-2026-001"
    }
  }
}
```

### 2.4 Track File Schema

```json
// .flux/tracks/track-001.json
{
  "id": 1,
  "name": "Lead Vocal",
  "color": "#4A9EFF",
  "type": "audio",

  "display": {
    "height": 80,
    "collapsed": false,
    "show_waveform": true,
    "waveform_style": "filled"
  },

  "input": {
    "source": "hardware",
    "device_id": 0,
    "channels": [0, 1],
    "record_armed": false,
    "monitoring": "auto"
  },

  "output": {
    "destination": "parent",
    "destination_id": null,
    "channels": [0, 1]
  },

  "mixer": {
    "input_trim_db": 0.0,
    "phase_invert": false,
    "fader_db": -3.2,
    "pan": 0.0,
    "width": 1.0,
    "mute": false,
    "solo": false
  },

  "inserts": {
    "pre_fader": [
      { "slot": 0, "plugin": ".flux/plugins/eq-001.json", "bypass": false },
      { "slot": 1, "plugin": ".flux/plugins/comp-001.json", "bypass": false },
      { "slot": 2, "plugin": null, "bypass": false },
      { "slot": 3, "plugin": null, "bypass": false },
      { "slot": 4, "plugin": null, "bypass": false }
    ],
    "post_fader": [
      { "slot": 5, "plugin": null, "bypass": false },
      { "slot": 6, "plugin": null, "bypass": false },
      { "slot": 7, "plugin": null, "bypass": false },
      { "slot": 8, "plugin": null, "bypass": false },
      { "slot": 9, "plugin": null, "bypass": false }
    ]
  },

  "sends": [
    {
      "index": 0,
      "destination_id": 10,
      "level_db": -6.0,
      "pan": 0.0,
      "pre_fader": false,
      "mute": false
    }
  ],

  "clips": [
    { "id": 101, "file": ".flux/clips/clip-101.json" },
    { "id": 102, "file": ".flux/clips/clip-102.json" }
  ],

  "automation": [
    { "parameter": "fader", "file": ".flux/automation/track-001-volume.json" },
    { "parameter": "pan", "file": ".flux/automation/track-001-pan.json" }
  ],

  "folder": {
    "is_folder": false,
    "parent_id": null,
    "depth": 0
  }
}
```

### 2.5 Clip File Schema

```json
// .flux/clips/clip-101.json
{
  "id": 101,
  "track_id": 1,
  "name": "Vocal Take 3",
  "color": null,

  "timeline": {
    "position": 10.5,
    "length": 45.2,
    "offset": 0.0
  },

  "source": {
    "type": "audio",
    "file": "audio/vocal-take-3.wav",
    "channels": 2,
    "sample_rate": 48000,
    "start_sample": 0,
    "end_sample": 2169600
  },

  "processing": {
    "clip_gain_db": 0.0,
    "time_stretch": {
      "enabled": false,
      "ratio": 1.0,
      "algorithm": "elastique"
    },
    "pitch_shift": {
      "enabled": false,
      "semitones": 0,
      "cents": 0
    }
  },

  "fades": {
    "fade_in": {
      "length": 0.01,
      "curve": "linear"
    },
    "fade_out": {
      "length": 0.01,
      "curve": "linear"
    }
  },

  "loop": {
    "enabled": false,
    "start": 0.0,
    "end": 0.0
  },

  "takes": [
    { "id": 1, "active": false, "file": "audio/vocal-take-1.wav" },
    { "id": 2, "active": false, "file": "audio/vocal-take-2.wav" },
    { "id": 3, "active": true, "file": "audio/vocal-take-3.wav" }
  ],

  "selected": false,
  "muted": false,
  "locked": false
}
```

### 2.6 Plugin State Schema

```json
// .flux/plugins/eq-001.json
{
  "id": "eq-001",
  "plugin": {
    "name": "FluxForge EQ",
    "vendor": "FluxForge",
    "format": "internal",
    "version": "1.0.0"
  },

  "parameters": {
    "output_gain_db": 0.0,
    "phase_mode": "minimum",
    "auto_gain": true,

    "bands": [
      {
        "id": 1,
        "enabled": true,
        "type": "low_cut",
        "frequency": 80.0,
        "gain_db": 0.0,
        "q": 0.707,
        "slope": "12db_oct",
        "solo": false
      },
      {
        "id": 2,
        "enabled": true,
        "type": "bell",
        "frequency": 250.0,
        "gain_db": -3.5,
        "q": 2.0,
        "slope": null,
        "solo": false
      },
      {
        "id": 3,
        "enabled": true,
        "type": "bell",
        "frequency": 3200.0,
        "gain_db": 2.0,
        "q": 1.5,
        "slope": null,
        "solo": false
      },
      {
        "id": 4,
        "enabled": true,
        "type": "high_shelf",
        "frequency": 8000.0,
        "gain_db": 1.5,
        "q": 0.707,
        "slope": null,
        "solo": false
      }
    ]
  },

  "ui_state": {
    "window_position": [100, 100],
    "window_size": [800, 600],
    "collapsed": false,
    "spectrum_visible": true,
    "piano_roll_visible": false
  }
}
```

### 2.7 Automation File Schema

```json
// .flux/automation/track-001-volume.json
{
  "track_id": 1,
  "parameter": "fader",
  "unit": "db",
  "default_value": -3.2,

  "mode": "read",
  "touch_threshold_db": 0.5,

  "points": [
    { "time": 0.0, "value": -3.2, "curve": "linear" },
    { "time": 16.0, "value": -3.2, "curve": "linear" },
    { "time": 16.5, "value": 0.0, "curve": "smooth" },
    { "time": 48.0, "value": 0.0, "curve": "linear" },
    { "time": 48.5, "value": -6.0, "curve": "smooth" },
    { "time": 80.0, "value": -6.0, "curve": "linear" },
    { "time": 80.5, "value": 0.0, "curve": "smooth" },
    { "time": 144.0, "value": 0.0, "curve": "linear" },
    { "time": 150.0, "value": -96.0, "curve": "smooth" }
  ],

  "regions": [
    { "start": 0.0, "end": 16.0, "name": "Intro level" },
    { "start": 48.0, "end": 80.0, "name": "Bridge dip" }
  ]
}
```

---

## 3. RUST IMPLEMENTATION

### 3.1 Project Serialization

```rust
// crates/rf-file/src/project/mod.rs

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::fs;

// ═══════════════════════════════════════════════════════════════════════════
// PROJECT SCHEMA VERSION
// ═══════════════════════════════════════════════════════════════════════════

pub const SCHEMA_VERSION: &str = "1.0.0";
pub const FLUXFORGE_VERSION: &str = env!("CARGO_PKG_VERSION");

// ═══════════════════════════════════════════════════════════════════════════
// MAIN PROJECT STRUCTURE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FluxProject {
    #[serde(rename = "$schema")]
    pub schema: String,
    pub version: String,
    pub fluxforge_version: String,
    pub created_at: String,
    pub modified_at: String,

    pub project: ProjectInfo,
    pub settings: ProjectSettings,
    pub markers: Vec<Marker>,
    pub tempo_map: Vec<TempoPoint>,
    pub tracks: Vec<TrackRef>,
    pub routing: RoutingConfig,
    pub metadata: ProjectMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectInfo {
    pub name: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectSettings {
    pub sample_rate: u32,
    pub bit_depth: u8,
    pub format: String,
    pub tempo: f64,
    pub time_signature: TimeSignature,
    pub key: Option<String>,
    pub scale: Option<String>,
    pub start_time: f64,
    pub end_time: f64,
    pub loop_start: f64,
    pub loop_end: f64,
    pub loop_enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeSignature {
    pub numerator: u8,
    pub denominator: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Marker {
    pub id: u32,
    pub position: f64,
    pub name: String,
    pub color: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempoPoint {
    pub position: f64,
    pub tempo: f64,
    pub curve: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackRef {
    pub id: u32,
    pub file: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingConfig {
    pub sends: Vec<RoutingSend>,
    pub master_output: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingSend {
    pub from: u32,
    pub to: u32,
    pub level_db: f64,
    pub pre_fader: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectMetadata {
    pub session_notes: Option<String>,
    pub engineer: Option<String>,
    pub producer: Option<String>,
    pub custom: std::collections::HashMap<String, String>,
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK STRUCTURE
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Track {
    pub id: u32,
    pub name: String,
    pub color: String,
    #[serde(rename = "type")]
    pub track_type: String,

    pub display: TrackDisplay,
    pub input: TrackInput,
    pub output: TrackOutput,
    pub mixer: MixerSettings,
    pub inserts: InsertChain,
    pub sends: Vec<SendConfig>,
    pub clips: Vec<ClipRef>,
    pub automation: Vec<AutomationRef>,
    pub folder: FolderConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackDisplay {
    pub height: u32,
    pub collapsed: bool,
    pub show_waveform: bool,
    pub waveform_style: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackInput {
    pub source: String,
    pub device_id: Option<u32>,
    pub channels: Vec<u32>,
    pub record_armed: bool,
    pub monitoring: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrackOutput {
    pub destination: String,
    pub destination_id: Option<u32>,
    pub channels: Vec<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MixerSettings {
    pub input_trim_db: f64,
    pub phase_invert: bool,
    pub fader_db: f64,
    pub pan: f64,
    pub width: f64,
    pub mute: bool,
    pub solo: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsertChain {
    pub pre_fader: Vec<InsertSlot>,
    pub post_fader: Vec<InsertSlot>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsertSlot {
    pub slot: u8,
    pub plugin: Option<String>,
    pub bypass: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendConfig {
    pub index: u8,
    pub destination_id: u32,
    pub level_db: f64,
    pub pan: f64,
    pub pre_fader: bool,
    pub mute: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipRef {
    pub id: u32,
    pub file: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutomationRef {
    pub parameter: String,
    pub file: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderConfig {
    pub is_folder: bool,
    pub parent_id: Option<u32>,
    pub depth: i32,
}

// ═══════════════════════════════════════════════════════════════════════════
// PROJECT MANAGER
// ═══════════════════════════════════════════════════════════════════════════

pub struct ProjectManager {
    project_path: PathBuf,
    project: FluxProject,
    tracks: Vec<Track>,
    modified: bool,
}

impl ProjectManager {
    /// Create new empty project
    pub fn new(path: impl AsRef<Path>, name: &str) -> Result<Self, ProjectError> {
        let project_path = path.as_ref().to_path_buf();

        // Create directory structure
        fs::create_dir_all(project_path.join(".flux/tracks"))?;
        fs::create_dir_all(project_path.join(".flux/clips"))?;
        fs::create_dir_all(project_path.join(".flux/plugins"))?;
        fs::create_dir_all(project_path.join(".flux/automation"))?;
        fs::create_dir_all(project_path.join("audio"))?;
        fs::create_dir_all(project_path.join("bounces"))?;

        // Create gitignore
        let gitignore = r#"
# FluxForge project ignores
.flux/history/
.flux/cache/
*.peak
*.waveform
*.tmp

# OS files
.DS_Store
Thumbs.db
"#;
        fs::write(project_path.join(".gitignore"), gitignore)?;

        let project = FluxProject {
            schema: "https://fluxforge.io/schema/v1/project.json".into(),
            version: SCHEMA_VERSION.into(),
            fluxforge_version: FLUXFORGE_VERSION.into(),
            created_at: chrono::Utc::now().to_rfc3339(),
            modified_at: chrono::Utc::now().to_rfc3339(),
            project: ProjectInfo {
                name: name.into(),
                artist: None,
                album: None,
                description: None,
                tags: Vec::new(),
            },
            settings: ProjectSettings {
                sample_rate: 48000,
                bit_depth: 32,
                format: "float".into(),
                tempo: 120.0,
                time_signature: TimeSignature {
                    numerator: 4,
                    denominator: 4,
                },
                key: None,
                scale: None,
                start_time: 0.0,
                end_time: 300.0,
                loop_start: 0.0,
                loop_end: 0.0,
                loop_enabled: false,
            },
            markers: Vec::new(),
            tempo_map: vec![TempoPoint {
                position: 0.0,
                tempo: 120.0,
                curve: "linear".into(),
            }],
            tracks: Vec::new(),
            routing: RoutingConfig {
                sends: Vec::new(),
                master_output: 0,
            },
            metadata: ProjectMetadata {
                session_notes: None,
                engineer: None,
                producer: None,
                custom: std::collections::HashMap::new(),
            },
        };

        let mut manager = Self {
            project_path,
            project,
            tracks: Vec::new(),
            modified: true,
        };

        // Create master track
        manager.create_master_track()?;

        Ok(manager)
    }

    /// Open existing project
    pub fn open(path: impl AsRef<Path>) -> Result<Self, ProjectError> {
        let project_path = path.as_ref().to_path_buf();

        // Find .flux file
        let flux_file = project_path
            .read_dir()?
            .filter_map(|e| e.ok())
            .find(|e| {
                e.path().extension().map_or(false, |ext| ext == "flux")
            })
            .ok_or(ProjectError::NoProjectFile)?
            .path();

        // Parse main project file
        let content = fs::read_to_string(&flux_file)?;
        let project: FluxProject = serde_json::from_str(&content)?;

        // Load tracks
        let mut tracks = Vec::new();
        for track_ref in &project.tracks {
            let track_path = project_path.join(&track_ref.file);
            let track_content = fs::read_to_string(&track_path)?;
            let track: Track = serde_json::from_str(&track_content)?;
            tracks.push(track);
        }

        Ok(Self {
            project_path,
            project,
            tracks,
            modified: false,
        })
    }

    /// Save project
    pub fn save(&mut self) -> Result<(), ProjectError> {
        // Update modified time
        self.project.modified_at = chrono::Utc::now().to_rfc3339();

        // Save main project file
        let project_file = self.project_path.join(format!("{}.flux", self.project.project.name));
        let content = serde_json::to_string_pretty(&self.project)?;
        fs::write(&project_file, content)?;

        // Save each track
        for track in &self.tracks {
            let track_file = self.project_path.join(format!(".flux/tracks/track-{:03}.json", track.id));
            let content = serde_json::to_string_pretty(track)?;
            fs::write(&track_file, content)?;
        }

        self.modified = false;
        Ok(())
    }

    /// Create master track
    fn create_master_track(&mut self) -> Result<(), ProjectError> {
        let master = Track {
            id: 0,
            name: "Master".into(),
            color: "#808080".into(),
            track_type: "master".into(),
            display: TrackDisplay {
                height: 80,
                collapsed: false,
                show_waveform: false,
                waveform_style: "filled".into(),
            },
            input: TrackInput {
                source: "bus".into(),
                device_id: None,
                channels: vec![0, 1],
                record_armed: false,
                monitoring: "off".into(),
            },
            output: TrackOutput {
                destination: "hardware".into(),
                destination_id: Some(0),
                channels: vec![0, 1],
            },
            mixer: MixerSettings {
                input_trim_db: 0.0,
                phase_invert: false,
                fader_db: 0.0,
                pan: 0.0,
                width: 1.0,
                mute: false,
                solo: false,
            },
            inserts: InsertChain {
                pre_fader: (0..5).map(|i| InsertSlot { slot: i, plugin: None, bypass: false }).collect(),
                post_fader: (5..10).map(|i| InsertSlot { slot: i, plugin: None, bypass: false }).collect(),
            },
            sends: Vec::new(),
            clips: Vec::new(),
            automation: Vec::new(),
            folder: FolderConfig {
                is_folder: false,
                parent_id: None,
                depth: 0,
            },
        };

        self.tracks.push(master);
        self.project.tracks.push(TrackRef {
            id: 0,
            file: ".flux/tracks/track-000.json".into(),
        });
        self.project.routing.master_output = 0;
        self.modified = true;

        Ok(())
    }

    /// Add new track
    pub fn add_track(&mut self, name: &str, track_type: &str) -> u32 {
        let id = self.tracks.iter().map(|t| t.id).max().unwrap_or(0) + 1;

        let track = Track {
            id,
            name: name.into(),
            color: "#4A9EFF".into(),
            track_type: track_type.into(),
            display: TrackDisplay {
                height: 80,
                collapsed: false,
                show_waveform: true,
                waveform_style: "filled".into(),
            },
            input: TrackInput {
                source: "hardware".into(),
                device_id: Some(0),
                channels: vec![0, 1],
                record_armed: false,
                monitoring: "auto".into(),
            },
            output: TrackOutput {
                destination: "parent".into(),
                destination_id: None,
                channels: vec![0, 1],
            },
            mixer: MixerSettings {
                input_trim_db: 0.0,
                phase_invert: false,
                fader_db: 0.0,
                pan: 0.0,
                width: 1.0,
                mute: false,
                solo: false,
            },
            inserts: InsertChain {
                pre_fader: (0..5).map(|i| InsertSlot { slot: i, plugin: None, bypass: false }).collect(),
                post_fader: (5..10).map(|i| InsertSlot { slot: i, plugin: None, bypass: false }).collect(),
            },
            sends: Vec::new(),
            clips: Vec::new(),
            automation: Vec::new(),
            folder: FolderConfig {
                is_folder: false,
                parent_id: None,
                depth: 0,
            },
        };

        self.tracks.push(track);
        self.project.tracks.push(TrackRef {
            id,
            file: format!(".flux/tracks/track-{:03}.json", id),
        });
        self.modified = true;

        id
    }

    /// Get track by ID
    pub fn get_track(&self, id: u32) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == id)
    }

    /// Get mutable track by ID
    pub fn get_track_mut(&mut self, id: u32) -> Option<&mut Track> {
        self.modified = true;
        self.tracks.iter_mut().find(|t| t.id == id)
    }

    /// Check if project has unsaved changes
    pub fn is_modified(&self) -> bool {
        self.modified
    }
}

#[derive(Debug)]
pub enum ProjectError {
    Io(std::io::Error),
    Json(serde_json::Error),
    NoProjectFile,
    InvalidVersion(String),
}

impl From<std::io::Error> for ProjectError {
    fn from(err: std::io::Error) -> Self {
        Self::Io(err)
    }
}

impl From<serde_json::Error> for ProjectError {
    fn from(err: serde_json::Error) -> Self {
        Self::Json(err)
    }
}
```

---

## 4. GIT DIFF EXAMPLE

```
EXAMPLE GIT DIFF (FluxForge vs Binary)
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  BINARY FORMAT (Pro Tools .ptx):                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ $ git diff my-song.ptx                                                  ││
│  │ Binary files a/my-song.ptx and b/my-song.ptx differ                     ││
│  │                                                                          ││
│  │ $ # What changed? NO IDEA! 🤷                                           ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  FLUXFORGE .flux FORMAT:                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ $ git diff                                                              ││
│  │                                                                          ││
│  │ diff --git a/.flux/tracks/track-001.json b/.flux/tracks/track-001.json  ││
│  │ @@ -15,8 +15,8 @@                                                       ││
│  │    "mixer": {                                                           ││
│  │      "input_trim_db": 0.0,                                              ││
│  │      "phase_invert": false,                                             ││
│  │ -    "fader_db": -3.2,                                                  ││
│  │ +    "fader_db": -1.5,                                                  ││
│  │      "pan": 0.0,                                                        ││
│  │ -    "width": 1.0,                                                      ││
│  │ +    "width": 0.8,                                                      ││
│  │      "mute": false,                                                     ││
│  │                                                                          ││
│  │ diff --git a/.flux/automation/track-001-volume.json ...                 ││
│  │ @@ -10,6 +10,7 @@                                                       ││
│  │    { "time": 48.0, "value": 0.0, "curve": "linear" },                   ││
│  │    { "time": 48.5, "value": -6.0, "curve": "smooth" },                  ││
│  │ +  { "time": 52.0, "value": -3.0, "curve": "smooth" },                  ││
│  │    { "time": 80.0, "value": -6.0, "curve": "linear" },                  ││
│  │                                                                          ││
│  │ $ # INSTANTLY see: fader changed, width reduced, automation point added││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  GIT LOG WITH MEANING:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ $ git log --oneline                                                     ││
│  │                                                                          ││
│  │ a1b2c3d Add automation dip at 52s for vocal                             ││
│  │ d4e5f6g Reduce lead vocal width to 0.8                                  ││
│  │ g7h8i9j Boost vocal fader from -3.2 to -1.5 dB                         ││
│  │ j0k1l2m Add EQ band at 3.2kHz for presence                              ││
│  │ m3n4o5p Initial project setup                                           ││
│  │                                                                          ││
│  │ $ # Full project history with meaningful messages!                      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. SUMMARY — FluxForge Project Format

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              FLUXFORGE PROJECT FORMAT — GIT-NATIVE DAW                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  FILE FORMAT:                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ JSON-based (human-readable, standard tooling)                        ││
│  │ ✓ Versioned schema (backward compatibility)                             ││
│  │ ✓ Modular structure (split by track/clip/automation)                   ││
│  │ ✓ Relative paths (portable)                                            ││
│  │ ✓ Comments supported (JSON5/JSONC)                                     ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  VERSION CONTROL:                                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Git-friendly diffs (see exactly what changed)                        ││
│  │ ✓ Meaningful commits (track fader changes, EQ adjustments)             ││
│  │ ✓ Merge-capable (text-based conflict resolution)                       ││
│  │ ✓ Branch workflow (experiment without losing original)                 ││
│  │ ✓ Cherry-pick changes between versions                                 ││
│  │ ✓ Blame/annotate (who changed what, when)                              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  SCRIPTING:                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Batch operations (rename tracks, adjust all faders)                  ││
│  │ ✓ Project generation (templates, CI/CD)                                ││
│  │ ✓ External tools (Python, jq, sed)                                     ││
│  │ ✓ API access (programmatic project manipulation)                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  RECOVERY:                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ✓ Partial corruption = partial data loss (not total)                   ││
│  │ ✓ Manual repair possible (text editor)                                 ││
│  │ ✓ Debug-friendly (inspect project structure)                           ││
│  │ ✓ Validation tools (schema checking)                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  COMPARISON:                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Pro Tools .ptx:  Binary → No diff, no merge, no history                ││
│  │ REAPER .rpp:     Text   → Good diff, limited structure                 ││
│  │ FluxForge .flux: JSON   → Perfect diff, modular, typed schema          ││
│  │                                                                          ││
│  │ FLUXFORGE = BEST OF REAPER + MODERN JSON TOOLING                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Sources:**
- REAPER RPP format documentation
- JSON Schema specification
- Git version control best practices
- FluxForge rf-file existing implementation
