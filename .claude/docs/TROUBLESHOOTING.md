## 🔧 TROUBLESHOOTING — SLOTLAB AUDIO NE RADI

### Problem: Spin ne proizvodi zvuk

**Simptomi:**
- Stage-vi se prikazuju u Event Log
- Ali nema audio output-a
- Event Log pokazuje `⚠️ STAGE_NAME (no audio)`

**Root Causes i Rešenja:**

#### 1. EventRegistry je prazan

**Provera:** Event Log status bar pokazuje "No events registered"

**Uzrok:** `_syncAllEventsToRegistry()` nije pozvan pri mount-u SlotLab screen-a

**Fix (2026-01-21):** Dodato u `slot_lab_screen.dart` initState:
```dart
if (_compositeEvents.isNotEmpty) {
  _syncAllEventsToRegistry();
}
```

**Verifikacija:** Debug log treba da pokaže:
```
[SlotLab] Initial sync: X events → EventRegistry
[SlotLab] ✅ Registered "Event Name" under N stage(s)
```

#### 2. Case-sensitivity mismatch

**Uzrok:** SlotLabProvider šalje `"SPIN_START"`, EventRegistry traži `"spin_start"`

**Fix (2026-01-21):** `event_registry.dart` triggerStage() sada radi case-insensitive lookup:
```dart
final normalizedStage = stage.toUpperCase().trim();
// Tries: exact match → normalized → case-insensitive search
```

#### 3. FFI nije učitan

**Simptom:** Event Log pokazuje `FAILED: FFI not loaded`

**Rešenje:** Full rebuild po CLAUDE.md proceduri:
```bash
cargo build --release
cp target/release/*.dylib flutter_ui/macos/Frameworks/
# + xcodebuild + copy to App Bundle
```

#### 4. Nema kreiranih eventa

**Simptom:** Event Log pokazuje `⚠️ SPIN_START (no audio)` za SVE stage-ove

**Rešenje:** Kreiraj AudioEvent-e u SlotLab UI:
1. Events Folder → Create Event
2. Dodeli stage (npr. `SPIN_START`)
3. Dodaj audio layer sa `.wav` fajlom
4. Save

#### 5. Double pozivi u QuickSheet flow-u (2026-01-23)

**Simptom:**
- Drop audio na slot element radi (QuickSheet se prikazuje)
- Commit klik radi (popup se zatvara)
- Ali event se NE kreira u Events panelu
- Spin ne proizvodi zvuk

**Uzrok #1:** `commitDraft()` se pozivao DVAPUT:
1. Prvo u `quick_sheet.dart` onCommit handler
2. Zatim u `drop_target_wrapper.dart` callback

**Uzrok #2:** `createDraft()` se TAKOĐE pozivao DVAPUT:
1. Prvo u `drop_target_wrapper.dart` _handleDrop()
2. Zatim u `quick_sheet.dart` showQuickSheet()

**Fix #1:** Uklonjen `commitDraft()` iz `quick_sheet.dart`
**Fix #2:** Uklonjen `createDraft()` iz `drop_target_wrapper.dart`

**Pravilan flow:**
```
showQuickSheet()           → createDraft() ← JEDINI POZIV
DropTargetWrapper.onCommit → commitDraft() ← JEDINI POZIV
```

**Verifikacija:**
1. Drop audio na SPIN dugme u Edit mode
2. Klikni Commit u QuickSheet popup
3. Event mora da se pojavi u Events panelu (desno)
4. Klikni Spin → audio mora da svira
5. Ponovi za druge elemente (reels, win overlays, itd.)

**Ključni fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/auto_event_builder/quick_sheet.dart` — createDraft()
- `flutter_ui/lib/widgets/slot_lab/auto_event_builder/drop_target_wrapper.dart` — commitDraft()

**Detaljna dokumentacija:** `.claude/architecture/EVENT_SYNC_SYSTEM.md`

### Event Log Format (2026-01-21)

**Sa audio-om:**
```
12:34:56.789  🎵 Spin Sound → SPIN_START [spin.wav, whoosh.wav]
              voice=5, bus=2, section=slotLab
```

**Bez audio-a (upozorava da nedostaje event):**
```
12:34:56.789  ⚠️ REEL_STOP_3 (no audio)
              Create event for this stage to hear audio
```

### Debug Log Patterns

| Log Pattern | Značenje |
|-------------|----------|
| `[SlotLab] Initial sync: X events` | EventRegistry uspešno popunjen |
| `[SlotLab] ✅ Registered "..."` | Event registrovan za stage |
| `[EventRegistry] ❌ No event for stage` | Stage nema registrovan event |
| `[EventRegistry] ✅ Playing: ...` | Audio uspešno pokrenut |
| `FAILED: FFI not loaded` | Dylib-ovi nisu kopirani |

### Relevantna dokumentacija

- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Detalji sync sistema
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback sekcije
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab arhitektura
- `.claude/architecture/ANTICIPATION_SYSTEM.md` — Industry-standard anticipation sa per-reel tension levels

#### 6. Double-Spin Trigger (2026-01-24)

**Simptom:**
- Klik na Spin dugme trigeruje DVA spina uzastopno
- Debug log pokazuje dva `[SlotPreview] 🆕 New spin detected`
- Slot mašina odmah pokreće drugi spin nakon prvog

**Uzrok:**
U `_onProviderUpdate()`, nakon što `_finalizeSpin()` postavi `_isSpinning = false`:
- Provider's `isPlayingStages` je još uvek `true` (procesira WIN_PRESENT, ROLLUP, itd.)
- `stages` lista još sadrži 'spin_start'
- Uslov prolazi ponovo → `_startSpin()` se poziva dvaput!

**Fix (2026-01-24):** Dodati guard flagovi u `slot_preview_widget.dart`:

```dart
bool _spinFinalized = false;      // Sprečava re-trigger nakon finalize
String? _lastProcessedSpinId;     // Prati koji spin rezultat je već procesiran

void _onProviderUpdate() {
  // Guards:
  // 1. Ne pokreći ako je spin već finalizovan
  // 2. Ne pokreći ako je isti spinId kao prethodni
  if (isPlaying && stages.isNotEmpty && !_isSpinning && !_spinFinalized) {
    final spinId = result?.spinId;
    if (hasSpinStart && spinId != null && spinId != _lastProcessedSpinId) {
      _lastProcessedSpinId = spinId;
      _startSpin(result);
    }
  }

  // Reset finalized flag kad provider završi (spreman za sledeći spin)
  if (!isPlaying && _spinFinalized) {
    _spinFinalized = false;
  }
}

void _finalizeSpin(SlotLabSpinResult result) {
  setState(() {
    _isSpinning = false;
    _spinFinalized = true;  // KRITIČNO: Sprečava re-trigger
  });
}
```

**Verifikacija:**
1. Klikni Spin → samo jedan spin se pokreće
2. Sačekaj da se završi → samo jedan `✅ FINALIZE SPIN` u logu
3. Klikni ponovo → novi spin se pokreće normalno

**Ključni fajl:** `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

#### 7. SPACE Key Stop-Not-Working (2026-01-26)

**Simptom:**
- SPACE dugme za STOP ne radi u embedded modu (centralni panel)
- Reelovi nastavljaju da se vrte ILI odmah startuju novi spin
- Izgleda kao da SPACE uopšte ne reaguje

**Uzrok:**
Dva nezavisna keyboard handlera procesirala isti SPACE event:
1. Global handler (`slot_lab_screen.dart:_globalKeyHandler`) — preko `HardwareKeyboard.instance.addHandler()`
2. Focus handler (`premium_slot_preview.dart:_handleKeyEvent`) — preko `Focus(onKeyEvent: ...)`

Oba su imala nezavisne debounce timer-e. Kada je SPACE pritisnut za STOP:
- Global handler pozove `stopStagePlayback()` → `isReelsSpinning = false`
- Focus handler vidi `isReelsSpinning = false` → odmah pozove `spin()`
- Rezultat: STOP pa instant SPIN — izgleda kao da SPACE ne radi

**Fix (2026-01-26):** Dodat `isFullscreen` parametar u `PremiumSlotPreview`:

```dart
// premium_slot_preview.dart constructor
const PremiumSlotPreview({
  required this.onExit,
  this.reels = 5,
  this.rows = 3,
  this.isFullscreen = false,  // NEW
});

// In _handleKeyEvent:
case LogicalKeyboardKey.space:
  if (!widget.isFullscreen) {
    return KeyEventResult.ignored;  // Let global handler handle it
  }
  // ... rest of SPACE handling
```

**Instantiation:**
```dart
// Fullscreen mode (F11)
PremiumSlotPreview(isFullscreen: true, ...)

// Embedded mode (centralni panel)
PremiumSlotPreview(isFullscreen: false, ...)
```

**Verifikacija:**
Debug log bi trebao pokazati:
```
# Embedded mode (isFullscreen=false):
[SlotLab] 🌍 GLOBAL Space key handler...
[PremiumSlotPreview] ⏭️ SPACE ignored (embedded mode)

# Fullscreen mode (isFullscreen=true):
[SlotLab] 🌍 GLOBAL Space — SKIPPED (Fullscreen)
[PremiumSlotPreview] 🎰 SPACE pressed...
```

**Ključni fajlovi:**
- `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart:4861,5712`
- `flutter_ui/lib/screens/slot_lab_screen.dart:923,2237,7052`

#### 8. Reel Phase Transition Infinite Loop (2026-01-31)

**Simptom:**
- Win presentation ne počinje automatski nakon što se reelovi zaustave
- `isSpinning` ostaje `true` zauvek
- Mora se ponovo pritisnuti SPIN da bi se nešto desilo

**Uzrok:**
Bug u `professional_reel_animation.dart` linija 243:
```dart
// BUG:
} else if (effectiveElapsedMs < bounceStart || phase == ReelPhase.decelerating) {
```

`|| phase == ReelPhase.decelerating` kreira beskonačnu petlju — kada reel uđe u `decelerating` fazu, uslov je uvek `true`, pa reel nikada ne može preći u `bouncing` ili `stopped`.

**Fix (2026-01-31):**
```dart
// FIXED:
} else if (elapsedMs < bounceStart) {
  // NOTE: Removed "|| phase == ReelPhase.decelerating" which caused infinite loop!
```

**Phase Flow (Corrected):**
```
idle → accelerating → spinning → decelerating → bouncing → stopped
                                      ↑
                                   FIX HERE
```

**Dokumentacija:** `.claude/analysis/REEL_PHASE_TRANSITION_FIX_2026_01_31.md`

#### 9. Animation Controller Race Condition (2026-02-01)

**Simptom:**
- Svi rilovi su vizuelno zaustavljeni
- Ali animacije (anticipation glow, itd.) se nastavljaju
- Spin završava tek nakon ~2000ms umesto ~1250ms
- Četvrti ril "treperi" ili ima ghost animaciju

**Uzrok:**
Dva NEZAVISNA mehanizma kontrolisala su spin:
1. `_reelController` (AnimationController) — trajao je 2000ms
2. `_scheduleReelStops()` (Timer-based) — zadnji reel stajao nakon ~1250ms

Kod je čekao da `_reelController` završi pre promene `_gameState`, ali rilovi su vizuelno stali 750ms ranije. U tom gap-u animacije su nastavljale.

**Fix (2026-02-01):**

1. **Immediate State Transition** — Kada svi rilovi stanu, odmah prelazi u `revealing`:
```dart
if (_reelStopped.every((stopped) => stopped)) {
  setState(() {
    _anticipationReelIndex = -1;
    if (_gameState == GameState.spinning || _gameState == GameState.anticipation) {
      _gameState = GameState.revealing;  // ODMAH, ne čekaj controller
    }
  });
  if (_reelController.isAnimating) {
    _reelController.stop();  // Zaustavi controller early
  }
}
```

2. **Guard Flag** — Sprečava dvostruko izvršavanje `_revealResult()`:
```dart
bool _revealProcessed = false;  // Instance variable

void _revealResult(...) {
  if (_revealProcessed) return;  // Guard
  _revealProcessed = true;
  // ...
}

// Reset u obe spin metode
void _startSpin() {
  _revealProcessed = false;
  // ...
}
```

**Verifikacija:**
1. Spin → svi rilovi staju → animacije odmah prestaju
2. Nema ghost glow-a na zaustavlјenim rilovima
3. Spin završava čim poslednji ril stane

**Ključni fajl:** `flutter_ui/lib/widgets/slot_lab/embedded_slot_mockup.dart`

**Dokumentacija:** `.claude/analysis/EMBEDDED_SLOT_ANIMATION_RACE_FIX_2026_02_01.md`

#### 10. CLAP/LV2 Plugin Crash na Destroy (2026-03-25)

**Simptom:**
- Plugin radi tokom playback-a
- App crashuje pri zatvaranju ili unload-u plugina
- Crash log: null pointer dereference ili double-free

**Uzrok:** Plugin pointer nije nulliran posle destroy/cleanup. Ako Drop pozove ponovo, double-free.

**Fix (2026-03-25):**
- CLAP: `self.plugin_ptr = std::ptr::null()` posle `destroy()`
- LV2: `self.handle = std::ptr::null_mut()` + `self.descriptor = std::ptr::null()` posle `cleanup()`

**Ključni fajlovi:** `rf-plugin/src/clap.rs` (Drop impl), `rf-plugin/src/lv2.rs` (Drop impl)

#### 11. Multi-Output Instrument — Nedostaju Kanali (2026-03-25)

**Simptom:**
- Kontakt sa 16 stereo output-a
- Neki kanali tihi ili distortirani
- Zvuk koji fali pojavljuje se na pogrešnom bus-u

**Uzrok:** Race condition — višestruki `try_read()` pozivi na output_channel_map dozvoljavaju promenu mape između čitanja.

**Fix (2026-03-25):** Jedan `try_read()` scope pokriva SVE channel routing odluke. Nema međustanja.

**Ključni fajl:** `rf-engine/src/playback.rs` — channel routing loop

#### 12. Project Save/Load Tiho Ne Radi (2026-03-25)

**Simptom:**
- Save/Load ne prijavljuje grešku ali se ništa ne desi
- Projekat se ne sačuva na disk / ne učita sa diska

**Uzrok:** Dart FFI lookupovao `engine_save_project` / `engine_load_project` — deprecated stubovi u ffi.rs koji vraćaju 0 (failure).

**Fix (2026-03-25):**
- Prerutirano na `project_save` / `project_load` iz rf-bridge project_ffi.rs
- UI sada prikazuje error snackbar ako save/load vrati false
- Automation CurveType (6 varijanti) i ParamId se pravilno serijalizuju
- Clip properties (reversed, pitch_shift, stretch_ratio) sačuvani

**Ključni fajlovi:** `native_ffi.dart`, `engine_provider.dart`, `engine_connected_layout.dart`, `api_project.rs`

---

