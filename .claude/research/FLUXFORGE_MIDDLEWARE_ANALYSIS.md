# FluxForge Middleware Sekcija — Detaljna Analiza

**Autori:** Chief Audio Architect, Lead DSP Engineer, Engine Architect
**Datum:** 2026-01-16
**Fokus:** Samo middleware aspekti (event system, voice management, RTPC, etc.)

---

## Executive Summary

FluxForge ima **parcijalno implementiranu middleware sekciju**:
- ✅ **UI/Dart modeli** — Kompletni Wwise/FMOD-style data modeli
- ❌ **Rust backend** — NE POSTOJI implementacija
- ❌ **FFI bridge** — Nema konekcije UI↔Engine za middleware

### Status

| Komponenta | UI (Dart) | Backend (Rust) | FFI Bridge |
|------------|-----------|----------------|------------|
| Event System | ✅ Modeli | ❌ | ❌ |
| Actions (Play/Stop/etc) | ✅ Modeli | ❌ | ❌ |
| State Groups | ✅ Modeli | ❌ | ❌ |
| Switch Groups | ✅ Modeli | ❌ | ❌ |
| RTPC | ⚠️ Partial (automation) | ⚠️ Partial | ⚠️ |
| Voice Management | ❌ | ❌ | ❌ |
| Soundbanks | ❌ | ❌ | ❌ |
| Profiler | ❌ | ❌ | ❌ |

---

## 1. ŠTA POSTOJI (UI Layer)

### 1.1 Middleware Models (Dart)

**Lokacija:** `flutter_ui/lib/models/middleware_models.dart`

```dart
// Kompletni Wwise/FMOD action tipovi
enum ActionType {
  play,
  playAndContinue,
  stop, stopAll,
  pause, pauseAll,
  resume, resumeAll,
  break_,
  mute, unmute,
  setVolume, setPitch,
  setLPF, setHPF,
  setBusVolume,
  setState, setSwitch, setRTPC, resetRTPC,
  seek, trigger, postEvent,
}

// Scope kao u Wwise
enum ActionScope {
  global, gameObject, emitter, all, firstOnly, random,
}

// Priority sistem
enum ActionPriority {
  highest, high, aboveNormal, normal, belowNormal, low, lowest,
}

// Fade curves
enum FadeCurve {
  linear, log3, sine, log1, invSCurve, sCurve, exp1, exp3,
}
```

**Ovo je ODLIČNO dizajnirano** — pokriva sve Wwise/FMOD akcije.

### 1.2 Middleware Event Model

```dart
class MiddlewareAction {
  final ActionType type;
  final String assetId;
  final String bus;
  final ActionScope scope;
  final ActionPriority priority;
  final FadeCurve fadeCurve;
  final double fadeTime;
  final double gain;
  final double pan;        // -1.0 (left) to +1.0 (right)
  final double delay;
  final bool loop;

  // Extended playback parameters (2026-01-26)
  final double fadeInMs;    // Fade-in duration (0 = instant)
  final double fadeOutMs;   // Fade-out duration (0 = instant)
  final double trimStartMs; // Non-destructive trim start
  final double trimEndMs;   // Non-destructive trim end
}

class MiddlewareEvent {
  final String id;
  final String name;
  final String category;
  final List<MiddlewareAction> actions;
}
```

### 1.3 State/Switch Groups

```dart
const Map<String, List<String>> kStateGroups = {
  'GameState': ['Menu', 'BaseGame', 'Bonus', 'FreeSpins', 'Paused'],
  'MusicState': ['Normal', 'Suspense', 'Action', 'Victory', 'Defeat'],
  'PlayerState': ['Idle', 'Spinning', 'Winning', 'Waiting'],
  'BonusState': ['None', 'Triggered', 'Active', 'Ending'],
  'Intensity': ['Low', 'Medium', 'High', 'Extreme'],
};

const List<String> kSwitchGroups = [
  'Surface', 'Footsteps', 'Material', 'Weapon', 'Environment',
];
```

---

## 2. ŠTA NEDOSTAJE (Rust Backend)

### 2.1 Voice Management System — ❌ NE POSTOJI

**Wwise ima:**
```cpp
// 4096 virtual voices
// Smart voice stealing based on audibility
// Distance-based culling
// 3D virtualization (keep position, stop playback)
AK::SoundEngine::PostEvent("Play_Footstep", gameObjectID);
// Wwise automatski upravlja voice poolom
```

**FluxForge NEMA NIŠTA od ovoga.**

**Potrebno implementirati (`rf-voice` crate):**
```rust
pub const MAX_PHYSICAL_VOICES: usize = 256;
pub const MAX_VIRTUAL_VOICES: usize = 4096;

pub struct VoiceManager {
    physical_voices: [Voice; MAX_PHYSICAL_VOICES],
    virtual_voices: Vec<VirtualVoice>,
    priority_queue: BinaryHeap<VoicePriority>,
    distance_culler: DistanceCuller,
}

pub struct Voice {
    id: VoiceId,
    game_object: GameObjectId,
    priority: u8,
    volume: f32,
    distance: f32,
    audibility: f32,  // volume * distance_attenuation * obstruction
    state: VoiceState,
    stream: Option<StreamRT>,
}

impl VoiceManager {
    /// Allocate voice with priority-based stealing
    pub fn play(&mut self, sound_id: SoundId, game_object: GameObjectId) -> Option<VoiceId>;

    /// Smart voice stealing
    fn steal_voice(&mut self, new_priority: u8) -> Option<VoiceId>;

    /// Virtualize voice (keep state, free resources)
    pub fn virtualize(&mut self, voice_id: VoiceId);

    /// Distance-based culling update
    pub fn update_distances(&mut self, listener_pos: Vec3);
}
```

### 2.2 Event System — ❌ NE POSTOJI

**Wwise/FMOD imaju:**
```cpp
// Wwise
AK::SoundEngine::PostEvent("Play_Music", gameObjectID);
AK::SoundEngine::PostEvent("Stop_All", AK_INVALID_GAME_OBJECT);

// FMOD
FMOD::Studio::EventInstance* instance;
eventDescription->createInstance(&instance);
instance->start();
```

**FluxForge NEMA event sistem u Rust-u.**

**Potrebno implementirati (`rf-event` crate):**
```rust
pub type EventId = u32;
pub type GameObjectId = u64;

pub enum AudioAction {
    Play { sound_id: SoundId, fade_ms: u32 },
    Stop { fade_ms: u32 },
    Pause,
    Resume,
    SetVolume { value: f32, fade_ms: u32 },
    SetPitch { value: f32 },
    SetLPF { value: f32 },
    SetHPF { value: f32 },
    SetBusVolume { bus_id: BusId, value: f32 },
    SetState { group_id: StateGroupId, state_id: StateId },
    SetSwitch { group_id: SwitchGroupId, switch_id: SwitchId },
    SetRTPC { rtpc_id: RtpcId, value: f32, interpolation_ms: u32 },
    Trigger,
}

pub struct AudioEvent {
    pub id: EventId,
    pub name: String,
    pub actions: Vec<(AudioAction, u32)>,  // (action, delay_ms)
}

pub struct EventManager {
    events: HashMap<EventId, AudioEvent>,
    active_instances: Vec<EventInstance>,
    state_groups: HashMap<StateGroupId, StateId>,
    switch_groups: HashMap<(GameObjectId, SwitchGroupId), SwitchId>,
    rtpcs: HashMap<RtpcId, RtpcValue>,
}

impl EventManager {
    /// Post event (Wwise-style API)
    pub fn post_event(&mut self, event_id: EventId, game_object: GameObjectId);

    /// Stop all on game object
    pub fn stop_all(&mut self, game_object: GameObjectId, fade_ms: u32);

    /// Set global state
    pub fn set_state(&mut self, group: StateGroupId, state: StateId);

    /// Set switch on game object
    pub fn set_switch(&mut self, game_object: GameObjectId, group: SwitchGroupId, switch: SwitchId);

    /// Set RTPC value
    pub fn set_rtpc(&mut self, rtpc_id: RtpcId, value: f32, game_object: Option<GameObjectId>);
}
```

### 2.3 RTPC (Real-Time Parameter Control) — ⚠️ PARTIAL

**Wwise ima:**
```cpp
AK::SoundEngine::SetRTPCValue("Health", 0.5f, gameObjectID);
// Automatski mapira na volume, pitch, filter, etc.
// Ima curves (linear, log, bezier)
```

**FluxForge ima automation system, ali:**
- ✅ `AutomationLane` sa curves
- ✅ Sample-accurate parameter changes
- ❌ NEMA game-object scoped RTPC
- ❌ NEMA RTPC → multiple parameter mapping
- ❌ NEMA real-time curve evaluation

**Potrebno proširiti:**
```rust
pub struct RtpcDefinition {
    pub id: RtpcId,
    pub name: String,
    pub default_value: f32,
    pub min: f32,
    pub max: f32,
    pub mappings: Vec<RtpcMapping>,
}

pub struct RtpcMapping {
    pub target: ParameterTarget,  // Volume, Pitch, LPF, etc.
    pub curve: RtpcCurve,
    pub range: (f32, f32),
}

pub enum RtpcCurve {
    Linear,
    Log3,
    Exp3,
    SCurve,
    InverseSCurve,
    Custom(Vec<(f32, f32)>),  // Bezier points
}
```

### 2.4 State Machine — ❌ NE POSTOJI

**Wwise ima:**
```cpp
AK::SoundEngine::SetState(STATE_GROUP_GAMESTATE, STATE_MENU);
// Sve zvukove koji slušaju GameState automatski menja
```

**FluxForge NEMA state machine.**

**Potrebno:**
```rust
pub struct StateGroup {
    pub id: StateGroupId,
    pub name: String,
    pub states: Vec<State>,
    pub current_state: StateId,
    pub transition_time_ms: u32,
}

pub struct StateListener {
    pub sound_id: SoundId,
    pub parameter: ParameterTarget,
    pub state_values: HashMap<StateId, f32>,
}
```

### 2.5 Switch Container — ❌ NE POSTOJI

**Wwise ima:**
```cpp
// Switch Container: Footstep
//   - Concrete -> sfx_footstep_concrete
//   - Wood -> sfx_footstep_wood
//   - Grass -> sfx_footstep_grass

AK::SoundEngine::SetSwitch(SWITCH_GROUP_SURFACE, SWITCH_CONCRETE, gameObjectID);
// Sledeći Play_Footstep će svirati concrete verziju
```

**FluxForge NEMA switch sistem.**

### 2.6 Soundbanks — ❌ NE POSTOJI

**Wwise ima:**
```cpp
AK::SoundEngine::LoadBank("Init.bnk", bankID);
AK::SoundEngine::LoadBank("Level1.bnk", bankID);
// Lazy loading, streaming, memory management
```

**FluxForge nema bank sistem** — sve se učitava direktno.

### 2.7 Profiler — ❌ NE POSTOJI

**Wwise ima:**
```
- Voice count (physical/virtual)
- CPU per voice
- Memory per bank
- Bus levels
- Distance culling stats
- Streaming buffer health
```

**FluxForge ima samo basic metering**, ne game audio profiler.

---

## 3. POREĐENJE SA KONKURENCIJOM

### 3.1 Feature Matrix

| Feature | FluxForge | Wwise | FMOD | Criware |
|---------|-----------|-------|------|---------|
| **Voice Pooling** | ❌ | ✅ 4096 | ✅ 1000+ | ✅ |
| **Voice Stealing** | ❌ | ✅ Smart | ✅ | ✅ |
| **Virtual Voices** | ❌ | ✅ | ✅ | ✅ |
| **Distance Culling** | ❌ | ✅ | ✅ | ✅ |
| **Event System** | UI only | ✅ | ✅ | ✅ |
| **PostEvent API** | ❌ | ✅ | ✅ | ✅ |
| **State Groups** | UI only | ✅ | ✅ | ✅ |
| **Switch Groups** | UI only | ✅ | ✅ | ✅ |
| **RTPC** | ⚠️ Partial | ✅ | ✅ | ✅ (AISAC) |
| **Soundbanks** | ❌ | ✅ | ✅ | ✅ |
| **Profiler** | ❌ | ✅ | ✅ | ✅ |
| **Randomization** | ❌ | ✅ | ✅ | ✅ |
| **Blend Containers** | ❌ | ✅ | ✅ | ❌ |
| **Interactive Music** | ❌ | ✅ | ✅ | ✅ |
| **Dialogue System** | ❌ | ✅ | ❌ | ❌ |

### 3.2 Ocena

| Aspekt | FluxForge | Wwise | FMOD |
|--------|-----------|-------|------|
| **Voice Management** | 0/10 | 10/10 | 9/10 |
| **Event System** | 2/10 (UI only) | 10/10 | 10/10 |
| **State/Switch** | 2/10 (UI only) | 10/10 | 9/10 |
| **RTPC** | 4/10 | 10/10 | 10/10 |
| **Memory Management** | 3/10 | 10/10 | 9/10 |
| **Profiling** | 1/10 | 10/10 | 9/10 |
| **OVERALL MIDDLEWARE** | **2/10** | **10/10** | **9/10** |

---

## 4. ŠTA TREBA IMPLEMENTIRATI

### 4.1 Priority 1: Voice Management (`rf-voice`)

**Zašto:** Bez voice managementa, FluxForge ne može da se koristi kao game middleware.

```rust
// rf-voice/src/lib.rs
pub mod pool;
pub mod stealing;
pub mod virtual;
pub mod distance;
pub mod priority;

pub struct VoiceManager { ... }
```

**Estimated LOC:** ~2000

### 4.2 Priority 2: Event System (`rf-event`)

**Zašto:** Core API za game integration. Bez PostEvent, nema middleware.

```rust
// rf-event/src/lib.rs
pub mod event;
pub mod action;
pub mod instance;
pub mod state;
pub mod switch;
pub mod rtpc;

pub struct EventManager { ... }
```

**Estimated LOC:** ~3000

### 4.3 Priority 3: FFI Bridge za Middleware

**Zašto:** Povezati Dart UI modele sa Rust backend.

```rust
// rf-bridge/src/middleware.rs
#[no_mangle]
pub extern "C" fn ff_post_event(event_id: u32, game_object: u64) -> i32;

#[no_mangle]
pub extern "C" fn ff_set_state(group: u32, state: u32) -> i32;

#[no_mangle]
pub extern "C" fn ff_set_switch(game_object: u64, group: u32, switch: u32) -> i32;

#[no_mangle]
pub extern "C" fn ff_set_rtpc(rtpc_id: u32, value: f32, game_object: u64) -> i32;
```

**Estimated LOC:** ~1000

### 4.4 Priority 4: Soundbank System (`rf-bank`)

**Zašto:** Memory management za large projects.

```rust
// rf-bank/src/lib.rs
pub struct SoundBank { ... }
pub struct BankManager { ... }
```

**Estimated LOC:** ~1500

### 4.5 Priority 5: Profiler (`rf-profile`)

**Zašto:** Debugging i optimization.

```rust
// rf-profile/src/lib.rs
pub struct AudioProfiler {
    pub voice_count: AtomicU32,
    pub virtual_voice_count: AtomicU32,
    pub cpu_usage: AtomicF32,
    pub memory_used: AtomicU64,
    pub streams_active: AtomicU32,
}
```

**Estimated LOC:** ~800

---

## 5. ROADMAP

### Phase 1: Voice Foundation (2-3 weeks)
- [ ] `rf-voice` crate
- [ ] Voice pool sa fixed capacity
- [ ] Priority-based stealing
- [ ] Basic virtual voices

### Phase 2: Event System (2-3 weeks)
- [ ] `rf-event` crate
- [ ] PostEvent API
- [ ] Action execution
- [ ] Event instances

### Phase 3: State/Switch (1-2 weeks)
- [ ] State groups
- [ ] Switch containers
- [ ] State transitions

### Phase 4: RTPC Enhancement (1-2 weeks)
- [ ] Game-object scoped RTPC
- [ ] RTPC curves
- [ ] Multi-parameter mapping

### Phase 5: FFI Bridge (1 week)
- [ ] Rust FFI exports
- [ ] Dart bindings
- [ ] Test integration

### Phase 6: Soundbanks (2 weeks)
- [ ] Bank format
- [ ] Lazy loading
- [ ] Memory tracking

### Phase 7: Profiler (1 week)
- [ ] Stats collection
- [ ] UI integration
- [ ] Export

**Total estimated time:** 10-14 weeks

---

## 6. ZAKLJUČAK

### Trenutni Status

FluxForge middleware sekcija je **NEDOVRŠENA**:
- UI dizajn je odličan (Wwise/FMOD-style modeli)
- Rust backend je **PRAZAN**
- Nema FFI konekcije

### Verdict

| Aspekt | Status |
|--------|--------|
| **UI Design** | ⭐⭐⭐⭐⭐ (excellent) |
| **Rust Implementation** | ⭐ (non-existent) |
| **Game-Ready** | ❌ NO |
| **Competitive** | ❌ NO |

### Preporuka

1. **Ako je cilj DAW** — middleware sekcija nije prioritet
2. **Ako je cilj game middleware** — potrebno 10-14 weeks rada

### TL;DR

**FluxForge ima LEPE PLANOVE za middleware (UI modeli), ali NEMA IMPLEMENTACIJU.**

Dart layer ima sve ActionType, Scope, Priority, FadeCurve — ali Rust engine ne zna ništa o tome.

Da bi FluxForge bio pravi middleware competitor:
- Implementirati `rf-voice` (voice pooling)
- Implementirati `rf-event` (PostEvent API)
- Povezati FFI bridge
- Dodati state/switch sisteme

Bez toga, middleware sekcija je samo **mockup UI bez funkcionalnosti**.

---

*Analiza završena: 2026-01-16*
*Chief Audio Architect / Lead DSP Engineer / Engine Architect*
