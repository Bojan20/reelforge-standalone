# FluxForge Slot Machine Middleware — Vodič za Implementaciju

**Autori:** Chief Audio Architect, Lead DSP Engineer
**Datum:** 2026-01-16
**Verzija:** 1.0

---

## Executive Summary

Ovaj dokument objašnjava kako koristiti FluxForge middleware event system za **slot machine igre**. Prikazuje se kako State Groups, Switch Groups i RTPC parametri mogu kontrolisati audio ponašanje u realnom vremenu.

---

## 1. ARHITEKTURA ZA SLOT IGRE

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SLOT MACHINE AUDIO MIDDLEWARE                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   GAME ENGINE (Flutter/Unity/Unreal)                                     │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │ Slot Logic                                                     │     │
│   │ ├── Spin Started     →  PostEvent("Spin_Start")               │     │
│   │ ├── Reel Stopping    →  PostEvent("Reel_Stop", reelId)        │     │
│   │ ├── Win Type Changed →  SetState("WinType", winTypeId)        │     │
│   │ ├── Balance Changed  →  SetRTPC("Balance", balance)           │     │
│   │ └── Bonus Triggered  →  PostEvent("Bonus_Enter")              │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                              │                                           │
│                              ▼                                           │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │ FluxForge Middleware API                                       │     │
│   │ ├── PostEvent(eventId, gameObjectId)                          │     │
│   │ ├── SetState(groupId, stateId)                                │     │
│   │ ├── SetSwitch(gameObjectId, groupId, switchId)                │     │
│   │ └── SetRTPC(rtpcId, value, interpolationMs)                   │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                              │                                           │
│                              ▼                                           │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │ Event Manager (Audio Thread)                                   │     │
│   │ ├── Process Commands (lock-free queue)                        │     │
│   │ ├── Execute Actions (state-aware)                             │     │
│   │ ├── Interpolate RTPCs                                         │     │
│   │ └── Manage Voice Lifecycle                                    │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. STATE GROUPS ZA SLOT

### 2.1 Definicija State Groups

```dart
// Dart — Definicija state grupa za slot
const Map<String, List<String>> kSlotStateGroups = {
  // Glavni game state
  'GameState': [
    'Idle',           // 0 - Čekanje na spin
    'Spinning',       // 1 - Bubnjevi se vrte
    'Anticipation',   // 2 - Poslednji bubanj, moguć dobitak
    'Revealing',      // 3 - Otkrivanje rezultata
    'Celebrating',    // 4 - Animacija dobitka
    'BonusGame',      // 5 - Bonus igra aktivna
  ],

  // Tip dobitka
  'WinType': [
    'NoWin',          // 0 - Nema dobitka
    'SmallWin',       // 1 - Mali dobitak (< 10x)
    'MediumWin',      // 2 - Srednji dobitak (10-50x)
    'BigWin',         // 3 - Veliki dobitak (50-100x)
    'MegaWin',        // 4 - Mega dobitak (100-500x)
    'EpicWin',        // 5 - Epski dobitak (> 500x)
  ],

  // Muzički mood
  'MusicMood': [
    'Normal',         // 0 - Standardna muzika
    'Tense',          // 1 - Napeta (anticipacija)
    'Exciting',       // 2 - Uzbudljivo (dobitak)
    'Triumphant',     // 3 - Trijumfalno (big win)
  ],

  // Bonus tip
  'BonusType': [
    'None',           // 0 - Nema bonusa
    'FreeSpins',      // 1 - Free spins
    'PickBonus',      // 2 - Pick bonus
    'Wheel',          // 3 - Wheel of Fortune
    'Cascade',        // 4 - Cascade/Avalanche
  ],
};
```

### 2.2 Registracija u Flutter

```dart
// U MiddlewareProvider
void initializeSlotStateGroups() {
  kSlotStateGroups.forEach((name, states) {
    registerStateGroupFromPreset(name, states);
  });
}
```

### 2.3 Korišćenje u Igri

```dart
// Kada počinje spin
void onSpinStart() {
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('GameState'),
    1, // Spinning
  );
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('MusicMood'),
    0, // Normal
  );
  nativeFfi.middlewarePostEvent(eventIds['Spin_Start']!, 0);
}

// Kada se detektuje potencijalni dobitak
void onAnticipation() {
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('GameState'),
    2, // Anticipation
  );
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('MusicMood'),
    1, // Tense
  );
}

// Kada se otkrije dobitak
void onWinRevealed(WinType winType) {
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('WinType'),
    winType.index,
  );

  // Music mood baziran na tipu dobitka
  final musicMood = switch (winType) {
    WinType.noWin => 0,
    WinType.smallWin => 0,
    WinType.mediumWin => 2,
    WinType.bigWin => 3,
    _ => 3,
  };
  middlewareProvider.setState(
    middlewareProvider.getStateGroupId('MusicMood'),
    musicMood,
  );
}
```

---

## 3. SWITCH GROUPS ZA SLOT

### 3.1 Definicija Switch Groups

```dart
// Switches su per-game-object — idealno za bubnjeve
const Map<String, List<String>> kSlotSwitchGroups = {
  // Tip simbola na bubnjevima (za reel-specific zvukove)
  'SymbolType': [
    'Low_1',          // Niska vrednost (10, J)
    'Low_2',          // Niska vrednost (Q, K)
    'Low_3',          // Niska vrednost (A)
    'Mid_1',          // Srednja vrednost
    'Mid_2',          // Srednja vrednost
    'High_1',         // Visoka vrednost
    'High_2',         // Visoka vrednost
    'Wild',           // Wild simbol
    'Scatter',        // Scatter simbol
    'Bonus',          // Bonus simbol
  ],

  // Material bubnja (za reel stop zvuk)
  'ReelMaterial': [
    'Classic',        // Klasični mehanički zvuk
    'Modern',         // Moderni elektronski
    'Futuristic',     // Futuristički
  ],
};
```

### 3.2 Korišćenje Switches

```dart
// Svaki bubanj ima svoj gameObjectId
final reelGameObjectIds = [1001, 1002, 1003, 1004, 1005];

// Kada bubanj prikazuje Wild
void onSymbolLanded(int reelIndex, SymbolType symbol) {
  final gameObjectId = reelGameObjectIds[reelIndex];

  middlewareProvider.setSwitch(
    gameObjectId,
    middlewareProvider.getSwitchGroupId('SymbolType'),
    symbol.index,
  );

  // Post event za specifičan bubanj
  nativeFfi.middlewarePostEvent(
    eventIds['Reel_Stop']!,
    gameObjectId,
  );
}
```

---

## 4. RTPC ZA SLOT

### 4.1 Definicija RTPC Parametara

```dart
const List<Map<String, dynamic>> kSlotRtpcDefinitions = [
  // Finansijski
  {'id': 1, 'name': 'Balance', 'min': 0.0, 'max': 1000000.0, 'default': 1000.0},
  {'id': 2, 'name': 'BetSize', 'min': 0.1, 'max': 1000.0, 'default': 1.0},
  {'id': 3, 'name': 'WinMultiplier', 'min': 0.0, 'max': 10000.0, 'default': 0.0},

  // Gameplay
  {'id': 10, 'name': 'SpinSpeed', 'min': 0.5, 'max': 3.0, 'default': 1.0},
  {'id': 11, 'name': 'ReelsSpinning', 'min': 0.0, 'max': 5.0, 'default': 0.0},
  {'id': 12, 'name': 'WinLineCount', 'min': 0.0, 'max': 50.0, 'default': 0.0},

  // Tension/Excitement
  {'id': 20, 'name': 'TensionLevel', 'min': 0.0, 'max': 100.0, 'default': 0.0},
  {'id': 21, 'name': 'ExcitementLevel', 'min': 0.0, 'max': 100.0, 'default': 0.0},

  // Free Spins
  {'id': 30, 'name': 'FreeSpinsRemaining', 'min': 0.0, 'max': 100.0, 'default': 0.0},
  {'id': 31, 'name': 'FreeSpinsMultiplier', 'min': 1.0, 'max': 10.0, 'default': 1.0},

  // Audio Control
  {'id': 40, 'name': 'MusicVolume', 'min': 0.0, 'max': 1.0, 'default': 0.8},
  {'id': 41, 'name': 'SFXVolume', 'min': 0.0, 'max': 1.0, 'default': 1.0},
  {'id': 42, 'name': 'VoiceVolume', 'min': 0.0, 'max': 1.0, 'default': 1.0},
];
```

### 4.2 RTPC Bindings za Audio Parametre

```dart
// Povezivanje TensionLevel → Music LPF
final tensionBinding = middlewareProvider.createBinding(
  20, // TensionLevel RTPC
  RtpcTargetParameter.lowPassFilter,
  busId: musicBusId,
);

// Custom curve: Low tension = bright, High tension = muffled
middlewareProvider.updateBindingCurve(
  tensionBinding.id,
  RtpcCurve(points: [
    RtpcCurvePoint(x: 0.0, y: 20000.0),   // 0% tension = 20kHz (open)
    RtpcCurvePoint(x: 50.0, y: 8000.0),   // 50% tension = 8kHz
    RtpcCurvePoint(x: 100.0, y: 2000.0),  // 100% tension = 2kHz (muffled)
  ]),
);

// Povezivanje ExcitementLevel → Music Pitch
final excitementBinding = middlewareProvider.createBinding(
  21, // ExcitementLevel RTPC
  RtpcTargetParameter.pitch,
  busId: musicBusId,
);

middlewareProvider.updateBindingCurve(
  excitementBinding.id,
  RtpcCurve(points: [
    RtpcCurvePoint(x: 0.0, y: 0.0),      // Normal pitch
    RtpcCurvePoint(x: 50.0, y: 1.0),     // +1 semitone
    RtpcCurvePoint(x: 100.0, y: 3.0),    // +3 semitones (excited)
  ]),
);

// Povezivanje WinMultiplier → SFX Volume
final winVolumeBinding = middlewareProvider.createBinding(
  3, // WinMultiplier RTPC
  RtpcTargetParameter.volume,
  busId: sfxBusId,
);

middlewareProvider.updateBindingCurve(
  winVolumeBinding.id,
  RtpcCurve.linear(0.0, 1000.0, 0.8, 1.5), // Louder for bigger wins
);
```

### 4.3 RTPC Update u Igri

```dart
// Tokom spin-a
void updateSpinState(int reelsStillSpinning, double tensionLevel) {
  middlewareProvider.setRtpc(
    11, // ReelsSpinning
    reelsStillSpinning.toDouble(),
    interpolationMs: 100,
  );

  middlewareProvider.setRtpc(
    20, // TensionLevel
    tensionLevel,
    interpolationMs: 500, // Smooth transition
  );
}

// Kada se otkrije dobitak
void onWinCalculated(double multiplier, int winLines) {
  middlewareProvider.setRtpc(
    3, // WinMultiplier
    multiplier,
    interpolationMs: 0, // Instant
  );

  middlewareProvider.setRtpc(
    12, // WinLineCount
    winLines.toDouble(),
    interpolationMs: 0,
  );

  // Excitement raste sa multiplier-om
  final excitement = (multiplier / 100.0).clamp(0.0, 100.0);
  middlewareProvider.setRtpc(
    21, // ExcitementLevel
    excitement,
    interpolationMs: 200,
  );
}
```

---

## 5. EVENT DEFINICIJE ZA SLOT

### 5.1 Osnovni Eventi

```dart
final slotEvents = {
  // ═══════════════════════════════════════════════════════════════
  // SPIN EVENTS
  // ═══════════════════════════════════════════════════════════════

  'Spin_Start': MiddlewareEvent(
    id: 1000,
    name: 'Spin_Start',
    category: 'Spin',
    actions: [
      // Smanji muziku
      MiddlewareAction(
        type: ActionType.setVolume,
        bus: 'Music',
        gain: 0.6,
        fadeTime: 0.2,
      ),
      // Pusti spin loop
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'spin_loop',
        bus: 'SFX',
        loop: true,
      ),
    ],
  ),

  'Spin_Stop': MiddlewareEvent(
    id: 1001,
    name: 'Spin_Stop',
    category: 'Spin',
    actions: [
      // Zaustavi spin loop
      MiddlewareAction(
        type: ActionType.stop,
        assetId: 'spin_loop',
        fadeTime: 0.1,
      ),
      // Vrati muziku
      MiddlewareAction(
        type: ActionType.setVolume,
        bus: 'Music',
        gain: 1.0,
        fadeTime: 0.5,
      ),
    ],
  ),

  'Reel_Stop': MiddlewareEvent(
    id: 1002,
    name: 'Reel_Stop',
    category: 'Spin',
    actions: [
      // Zvuk zavisi od Switch-a (SymbolType)
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'reel_stop_generic',
        bus: 'SFX',
      ),
      // Wild ima poseban zvuk (conditional)
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'reel_stop_wild',
        bus: 'SFX',
        // Samo ako je switch = Wild
      ).withSwitchCondition(switchGroupId: symbolTypeGroupId, switchId: 7),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════
  // WIN EVENTS
  // ═══════════════════════════════════════════════════════════════

  'Win_Small': MiddlewareEvent(
    id: 2000,
    name: 'Win_Small',
    category: 'Win',
    actions: [
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'win_coins_small',
        bus: 'Wins',
      ),
    ],
  ),

  'Win_Big': MiddlewareEvent(
    id: 2001,
    name: 'Win_Big',
    category: 'Win',
    actions: [
      // Smanji muziku dramatično
      MiddlewareAction(
        type: ActionType.setVolume,
        bus: 'Music',
        gain: 0.3,
        fadeTime: 0.5,
      ),
      // Fanfare
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'big_win_fanfare',
        bus: 'Wins',
        priority: ActionPriority.high,
      ),
      // Coin cascade (looped)
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'coin_cascade_loop',
        bus: 'Wins',
        delay: 1.0,
        loop: true,
      ),
    ],
  ),

  'Win_End': MiddlewareEvent(
    id: 2002,
    name: 'Win_End',
    category: 'Win',
    actions: [
      // Zaustavi coin cascade
      MiddlewareAction(
        type: ActionType.stop,
        assetId: 'coin_cascade_loop',
        fadeTime: 0.5,
      ),
      // Vrati muziku
      MiddlewareAction(
        type: ActionType.setVolume,
        bus: 'Music',
        gain: 1.0,
        fadeTime: 1.0,
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════
  // BONUS EVENTS
  // ═══════════════════════════════════════════════════════════════

  'Bonus_Trigger': MiddlewareEvent(
    id: 3000,
    name: 'Bonus_Trigger',
    category: 'Bonus',
    actions: [
      // Stinger za bonus
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'bonus_trigger_stinger',
        bus: 'SFX',
        priority: ActionPriority.highest,
      ),
      // Smanji base music
      MiddlewareAction(
        type: ActionType.setVolume,
        bus: 'Music',
        gain: 0.0,
        fadeTime: 1.0,
      ),
      // Set state
      MiddlewareAction(
        type: ActionType.setState,
        groupId: gameStateGroupId,
        valueId: 5, // BonusGame
      ),
    ],
  ),

  'Bonus_Music_Start': MiddlewareEvent(
    id: 3001,
    name: 'Bonus_Music_Start',
    category: 'Bonus',
    actions: [
      // Pusti bonus muziku (conditional na BonusType)
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'bonus_music_freespins',
        bus: 'Music',
        loop: true,
      ).withStateCondition(groupId: bonusTypeGroupId, stateId: 1), // FreeSpins

      MiddlewareAction(
        type: ActionType.play,
        assetId: 'bonus_music_pickbonus',
        bus: 'Music',
        loop: true,
      ).withStateCondition(groupId: bonusTypeGroupId, stateId: 2), // PickBonus

      MiddlewareAction(
        type: ActionType.play,
        assetId: 'bonus_music_wheel',
        bus: 'Music',
        loop: true,
      ).withStateCondition(groupId: bonusTypeGroupId, stateId: 3), // Wheel
    ],
  ),

  'Bonus_End': MiddlewareEvent(
    id: 3002,
    name: 'Bonus_End',
    category: 'Bonus',
    actions: [
      // Zaustavi bonus muziku
      MiddlewareAction(
        type: ActionType.stopAll,
        bus: 'Music',
        fadeTime: 1.0,
      ),
      // Vrati base muziku
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'base_game_music',
        bus: 'Music',
        loop: true,
        delay: 1.5,
      ),
      // Set state back
      MiddlewareAction(
        type: ActionType.setState,
        groupId: gameStateGroupId,
        valueId: 0, // Idle
      ),
      MiddlewareAction(
        type: ActionType.setState,
        groupId: bonusTypeGroupId,
        valueId: 0, // None
      ),
    ],
  ),

  // ═══════════════════════════════════════════════════════════════
  // FREE SPINS EVENTS
  // ═══════════════════════════════════════════════════════════════

  'FreeSpins_Awarded': MiddlewareEvent(
    id: 4000,
    name: 'FreeSpins_Awarded',
    category: 'FreeSpins',
    actions: [
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'freespins_awarded',
        bus: 'VO',
      ),
    ],
  ),

  'FreeSpins_Counter': MiddlewareEvent(
    id: 4001,
    name: 'FreeSpins_Counter',
    category: 'FreeSpins',
    actions: [
      // Zvuk zavisi od broja preostalih (RTPC condition)
      MiddlewareAction(
        type: ActionType.play,
        assetId: 'freespin_tick_normal',
        bus: 'SFX',
      ).withRtpcCondition(rtpcId: 30, min: 3.0, max: 100.0), // > 3 remaining

      MiddlewareAction(
        type: ActionType.play,
        assetId: 'freespin_tick_urgent',
        bus: 'SFX',
      ).withRtpcCondition(rtpcId: 30, min: 1.0, max: 2.99), // 1-3 remaining

      MiddlewareAction(
        type: ActionType.play,
        assetId: 'freespin_tick_last',
        bus: 'SFX',
        priority: ActionPriority.high,
      ).withRtpcCondition(rtpcId: 30, min: 0.0, max: 0.99), // Last one
    ],
  ),
};
```

---

## 6. KOMPLETNI INTEGRATION FLOW

### 6.1 Inicijalizacija

```dart
class SlotAudioManager {
  final MiddlewareProvider _middleware;
  final NativeFFI _ffi;

  // Event IDs
  late Map<String, int> _eventIds;

  // State/Switch Group IDs
  late int _gameStateGroupId;
  late int _winTypeGroupId;
  late int _musicMoodGroupId;
  late int _bonusTypeGroupId;
  late int _symbolTypeGroupId;

  SlotAudioManager(this._middleware, this._ffi) {
    _initialize();
  }

  void _initialize() {
    // 1. Registruj state grupe
    kSlotStateGroups.forEach((name, states) {
      _middleware.registerStateGroupFromPreset(name, states);
    });

    // 2. Sačuvaj group IDs
    _gameStateGroupId = _middleware.getStateGroupIdByName('GameState')!;
    _winTypeGroupId = _middleware.getStateGroupIdByName('WinType')!;
    _musicMoodGroupId = _middleware.getStateGroupIdByName('MusicMood')!;
    _bonusTypeGroupId = _middleware.getStateGroupIdByName('BonusType')!;

    // 3. Registruj switch grupe
    kSlotSwitchGroups.forEach((name, switches) {
      _middleware.registerSwitchGroupFromPreset(name, switches);
    });
    _symbolTypeGroupId = _middleware.getSwitchGroupIdByName('SymbolType')!;

    // 4. Registruj RTPCs
    for (final preset in kSlotRtpcDefinitions) {
      _middleware.registerRtpcFromPreset(preset);
    }

    // 5. Kreiraj RTPC bindings
    _createRtpcBindings();

    // 6. Registruj evente
    _registerEvents();

    // 7. Pokreni base muziku
    _ffi.middlewarePostEvent(_eventIds['Base_Music_Start']!, 0);
  }

  void _createRtpcBindings() {
    // TensionLevel → Music LPF
    final tensionLpf = _middleware.createBinding(
      20, RtpcTargetParameter.lowPassFilter, busId: 0,
    );
    _middleware.updateBindingCurve(tensionLpf.id, RtpcCurve(points: [
      RtpcCurvePoint(x: 0.0, y: 20000.0),
      RtpcCurvePoint(x: 100.0, y: 2000.0, shape: RtpcCurveShape.exp1),
    ]));

    // ExcitementLevel → Music Pitch
    final excitementPitch = _middleware.createBinding(
      21, RtpcTargetParameter.pitch, busId: 0,
    );
    _middleware.updateBindingCurve(excitementPitch.id, RtpcCurve(points: [
      RtpcCurvePoint(x: 0.0, y: 0.0),
      RtpcCurvePoint(x: 100.0, y: 3.0, shape: RtpcCurveShape.sCurve),
    ]));
  }

  void _registerEvents() {
    _eventIds = {};
    slotEvents.forEach((name, event) {
      _ffi.middlewareRegisterEvent(event.id, name, event.category);
      for (final action in event.actions) {
        _ffi.middlewareAddAction(event.id, action);
      }
      _eventIds[name] = event.id;
    });
  }
}
```

### 6.2 Runtime Kontrola

```dart
extension SlotAudioManagerRuntime on SlotAudioManager {

  // ═══════════════════════════════════════════════════════════════
  // SPIN LIFECYCLE
  // ═══════════════════════════════════════════════════════════════

  void onSpinPressed() {
    // Update states
    _middleware.setState(_gameStateGroupId, 1); // Spinning
    _middleware.setState(_winTypeGroupId, 0);   // NoWin (reset)

    // Reset RTPCs
    _middleware.setRtpc(20, 0.0);  // TensionLevel = 0
    _middleware.setRtpc(21, 0.0);  // ExcitementLevel = 0
    _middleware.setRtpc(11, 5.0);  // ReelsSpinning = 5

    // Post event
    _ffi.middlewarePostEvent(_eventIds['Spin_Start']!, 0);
  }

  void onReelStopping(int reelIndex, bool hasAnticipation) {
    // Update reels spinning
    final reelsRemaining = 5 - reelIndex - 1;
    _middleware.setRtpc(11, reelsRemaining.toDouble(), interpolationMs: 100);

    if (hasAnticipation && reelsRemaining <= 1) {
      // Anticipation za poslednje bubnjeve
      _middleware.setState(_gameStateGroupId, 2); // Anticipation
      _middleware.setRtpc(20, 80.0, interpolationMs: 500); // High tension
    }
  }

  void onReelStopped(int reelIndex, int gameObjectId, SymbolType symbol) {
    // Update switch za ovaj bubanj
    _middleware.setSwitch(gameObjectId, _symbolTypeGroupId, symbol.index);

    // Post event sa gameObjectId
    _ffi.middlewarePostEvent(_eventIds['Reel_Stop']!, gameObjectId);
  }

  void onAllReelsStopped() {
    _middleware.setState(_gameStateGroupId, 3); // Revealing
    _middleware.setRtpc(11, 0.0); // ReelsSpinning = 0
    _ffi.middlewarePostEvent(_eventIds['Spin_Stop']!, 0);
  }

  // ═══════════════════════════════════════════════════════════════
  // WIN HANDLING
  // ═══════════════════════════════════════════════════════════════

  void onWinCalculated(WinType winType, double multiplier, int winLines) {
    // Update states
    _middleware.setState(_winTypeGroupId, winType.index);
    _middleware.setState(_gameStateGroupId, 4); // Celebrating

    // Update RTPCs
    _middleware.setRtpc(3, multiplier);       // WinMultiplier
    _middleware.setRtpc(12, winLines.toDouble()); // WinLineCount
    _middleware.setRtpc(20, 0.0, interpolationMs: 300);  // Reset tension

    // Excitement based on win type
    final excitement = switch (winType) {
      WinType.noWin => 0.0,
      WinType.smallWin => 20.0,
      WinType.mediumWin => 50.0,
      WinType.bigWin => 80.0,
      _ => 100.0,
    };
    _middleware.setRtpc(21, excitement, interpolationMs: 200);

    // Post appropriate event
    final eventName = switch (winType) {
      WinType.noWin => null,
      WinType.smallWin => 'Win_Small',
      WinType.mediumWin => 'Win_Medium',
      _ => 'Win_Big',
    };

    if (eventName != null) {
      _ffi.middlewarePostEvent(_eventIds[eventName]!, 0);
    }
  }

  void onWinCelebrationComplete() {
    _middleware.setState(_gameStateGroupId, 0); // Idle
    _middleware.setRtpc(21, 0.0, interpolationMs: 500); // Reset excitement
    _ffi.middlewarePostEvent(_eventIds['Win_End']!, 0);
  }

  // ═══════════════════════════════════════════════════════════════
  // BONUS HANDLING
  // ═══════════════════════════════════════════════════════════════

  void onBonusTriggered(BonusType bonusType) {
    _middleware.setState(_bonusTypeGroupId, bonusType.index);
    _ffi.middlewarePostEvent(_eventIds['Bonus_Trigger']!, 0);

    // Delayed music start
    Future.delayed(Duration(seconds: 2), () {
      _ffi.middlewarePostEvent(_eventIds['Bonus_Music_Start']!, 0);
    });
  }

  void onFreeSpinsUpdated(int remaining) {
    _middleware.setRtpc(30, remaining.toDouble());
    _ffi.middlewarePostEvent(_eventIds['FreeSpins_Counter']!, 0);
  }

  void onBonusComplete() {
    _ffi.middlewarePostEvent(_eventIds['Bonus_End']!, 0);
  }
}
```

---

## 7. DEBUGGING & PROFILING

### 7.1 Stats Display

```dart
Widget buildAudioDebugOverlay() {
  return Consumer<MiddlewareProvider>(
    builder: (context, middleware, _) {
      final stats = middleware.stats;
      final bindings = middleware.evaluateAllBindings();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('State Groups: ${stats.stateGroups}'),
          Text('Switch Groups: ${stats.switchGroups}'),
          Text('RTPCs: ${stats.rtpcs}'),
          Text('Active Bindings: ${bindings.length}'),

          Divider(),

          // Current States
          for (final group in middleware.stateGroups)
            Text('${group.name}: ${group.currentStateName}'),

          Divider(),

          // Current RTPCs
          for (final rtpc in middleware.rtpcDefinitions)
            Text('${rtpc.name}: ${rtpc.currentValue.toStringAsFixed(2)}'),
        ],
      );
    },
  );
}
```

---

## 8. BEST PRACTICES

### 8.1 Performance
- Koristi `interpolationMs` za smooth RTPC transitions
- Grupiši state promene zajedno pre PostEvent
- Koristi `ActionPriority` za kritične zvukove (wins, bonuses)

### 8.2 Design
- State Groups za globalne promene (GameState, WinType)
- Switch Groups za per-object varijacije (reels, symbols)
- RTPC za kontinualne parametre (balance, tension, volume)

### 8.3 Maintainability
- Definiši sve konstante u jednom mestu
- Koristi category za organizaciju evenata
- Dokumentuj RTPC ranges i namenu

---

*Vodič kreiran: 2026-01-16*
*Chief Audio Architect / Lead DSP Engineer*
