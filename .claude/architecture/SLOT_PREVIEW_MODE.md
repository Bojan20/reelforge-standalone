# Slot Lab — Fullscreen Preview Mode

**Status:** ALL PHASES COMPLETE (1-4)
**Priority:** HIGH
**Created:** 2026-01-20
**Implemented:** 2026-01-20

---

## Koncept

Sound designer radi u Slot Lab sekciji — mapira evente, podešava RTPC krive, importuje audio. Ali pravi test audio dizajna je **celokupno iskustvo igrača**.

**Preview Mode** omogućava:
- Fullscreen slot mašina (bez toolbar-a, side panela)
- Igraj kao pravi igrač — SPIN, WIN, FEATURE
- Čuj kako audio flow zaista zvuči
- ESC vraća u Slot Lab **tačno gde si bio**

---

## Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                         SLOT LAB                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Event    │ │ Stage    │ │ Audio    │ │ RTPC     │           │
│  │ Registry │ │ Trace    │ │ Browser  │ │ Curves   │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Slot Preview Widget (small)                 │   │
│  │                    [▶ PREVIEW]                          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ F11 or [▶ PREVIEW] button
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   FULLSCREEN PREVIEW MODE                       │
│                                                                 │
│                  ┌───────────────────────┐                     │
│                  │                       │                     │
│                  │    ╔═══╦═══╦═══╗     │                     │
│                  │    ║ 7 ║ A ║ K ║     │                     │
│                  │    ╠═══╬═══╬═══╣     │                     │
│                  │    ║ Q ║ 7 ║ 10║     │                     │
│                  │    ╠═══╬═══╬═══╣     │                     │
│                  │    ║ A ║ K ║ 7 ║     │                     │
│                  │    ╚═══╩═══╩═══╝     │                     │
│                  │                       │                     │
│                  │      WIN: $125       │                     │
│                  │                       │                     │
│                  │    ┌──────────┐       │                     │
│                  │    │   SPIN   │       │                     │
│                  │    └──────────┘       │                     │
│                  └───────────────────────┘                     │
│                                                                 │
│  [D] Debug Overlay    [ESC] Exit Preview    [SPACE] Spin       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ ESC
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SLOT LAB                                │
│            (state preserved — scroll, selection, etc.)          │
└─────────────────────────────────────────────────────────────────┘
```

---

## UI Elementi

### Preview Mode Screen

| Element | Opis |
|---------|------|
| **Slot Grid** | 3x5 (ili konfigurisano) — centriran, 60-70% ekrana |
| **Reels** | Animirani spin sa blur efektom |
| **Win Display** | Veliki, centriran ispod grida |
| **SPIN Button** | Prominent, ili SPACE hotkey |
| **Balance** | Opciono — simulirani kredit |
| **Bet Controls** | Opciono — +/- bet amount |

### Debug Overlay (toggle sa D)

```
┌─────────────────────────────┐
│ STAGE TRACE (mini)          │
│ ├─ SPIN_START      0ms     │
│ ├─ REEL_STOP_0    450ms    │
│ ├─ REEL_STOP_1    600ms    │
│ ├─ WIN_PRESENT   1200ms    │
│ └─ ROLLUP_END    2500ms    │
│                             │
│ AUDIO LEVEL: ████████░░ -6dB│
└─────────────────────────────┘
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `SPACE` | Spin |
| `ESC` | Exit Preview Mode |
| `D` | Toggle Debug Overlay |
| `1-0` | Forced outcomes (kao u Slot Lab) |
| `M` | Mute/unmute |
| `+/-` | Bet amount (ako je enabled) |

---

## Visual Design

### Background

```
Gradient: #0a0a12 → #1a1a28 (radial, center lighter)
Vignette: Subtle darkening na ivicama
Optional: Particle ambient (floating lights)
```

### Slot Machine Frame

```
Border: 2px #4a9eff glow
Background: #121218 sa subtle noise texture
Shadow: 0 20px 60px rgba(0,0,0,0.8)
```

### Win Presentation

| Win Tier | Effect |
|----------|--------|
| Small | Text pulse, subtle glow |
| Big | Gold color, particle burst |
| Mega | Screen shake, coin rain |
| Epic | Full celebration, fireworks |
| Jackpot | Special animation, sustained |

### Reel Animations

```
Spin Start: Blur ramp up (0 → max over 200ms)
Spinning: Motion blur, symbol streak
Reel Stop: Bounce ease-out, impact sound
Anticipation: Glow border, pulse effect
```

---

## Implementation

### Architecture

```dart
// slot_lab_screen.dart
class SlotLabScreen extends StatefulWidget {
  // ...
}

class _SlotLabScreenState extends State<SlotLabScreen> {
  bool _isPreviewMode = false;

  @override
  Widget build(BuildContext context) {
    if (_isPreviewMode) {
      return FullscreenSlotPreview(
        onExit: () => setState(() => _isPreviewMode = false),
      );
    }

    return Scaffold(
      // Normal Slot Lab UI
      // ...
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _isPreviewMode = true),
        icon: Icon(Icons.play_arrow),
        label: Text('PREVIEW'),
      ),
    );
  }
}
```

### FullscreenSlotPreview Widget

```dart
class FullscreenSlotPreview extends StatefulWidget {
  final VoidCallback onExit;

  const FullscreenSlotPreview({required this.onExit});

  @override
  State<FullscreenSlotPreview> createState() => _FullscreenSlotPreviewState();
}

class _FullscreenSlotPreviewState extends State<FullscreenSlotPreview> {
  bool _showDebugOverlay = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a12),
      body: KeyboardListener(
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          children: [
            // Background gradient + vignette
            _buildBackground(),

            // Centered slot machine
            Center(
              child: SlotMachineWidget(
                size: SlotMachineSize.large, // 60-70% screen
                showFrame: true,
                enableAnimations: true,
              ),
            ),

            // Debug overlay (conditional)
            if (_showDebugOverlay)
              Positioned(
                top: 20,
                right: 20,
                child: _buildDebugOverlay(),
              ),

            // Exit hint
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: _buildControlHints(),
            ),
          ],
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          widget.onExit();
          break;
        case LogicalKeyboardKey.space:
          context.read<SlotLabProvider>().spin();
          break;
        case LogicalKeyboardKey.keyD:
          setState(() => _showDebugOverlay = !_showDebugOverlay);
          break;
        // Forced outcomes 1-0
        case LogicalKeyboardKey.digit1:
          context.read<SlotLabProvider>().spinForced(ForcedOutcome.lose);
          break;
        // ... etc
      }
    }
  }
}
```

### SlotMachineWidget Enhancements

```dart
enum SlotMachineSize { small, medium, large }

class SlotMachineWidget extends StatelessWidget {
  final SlotMachineSize size;
  final bool showFrame;
  final bool enableAnimations;

  // Size multipliers
  double get scale => switch (size) {
    SlotMachineSize.small => 0.5,
    SlotMachineSize.medium => 0.75,
    SlotMachineSize.large => 1.0,
  };

  // Premium visual options for large size
  bool get showParticles => size == SlotMachineSize.large;
  bool get showGlow => size == SlotMachineSize.large;
}
```

---

## State Management

### Preserved State

Kada uđeš u Preview Mode, sledeće se čuva:
- Event Registry mappings
- Audio pool contents
- RTPC curve settings
- Scroll pozicije svih panela
- Selekcije (selected event, selected region, etc.)
- Undo/redo stack

### Preview-Only State

- Current spin result
- Animation states
- Debug overlay visibility
- Win celebration progress

---

## Faze Implementacije

### Faza 1: Basic Preview Mode ✅ COMPLETE
- [x] `_isPreviewMode` flag u SlotLabScreen
- [x] `FullscreenSlotPreview` widget
- [x] Keyboard shortcuts (ESC, SPACE, D, H, 1-0)
- [x] PREVIEW button u header (F11 shortcut)
- [x] State preservation (automatic via provider)

### Faza 2: Visual Polish ✅ COMPLETE
- [x] Premium background (gradient, vignette)
- [x] Ambient particle system (30 floating particles)
- [x] Slot machine frame sa animated glow (win-tier aware)
- [x] Win tier badge with gradient colors
- [x] Pulsing spin button animation

### Faza 3: Debug Integration ✅ COMPLETE
- [x] Mini stage trace overlay (timeline + event list)
- [x] Live audio level meter (stereo, peak hold)
- [x] Event trigger indicators (flash animation)
- [x] Toggle with D key

### Faza 4: Advanced Features ✅ COMPLETE
- [x] Bet amount controls (+/- buttons, keyboard)
- [x] Simulated balance ($1000 start)
- [x] Session stats panel (RTP, hit rate, profit)
- [x] Toggle with S key
- [ ] Screenshot/recording mode (future)

---

## Audio Integration

Preview Mode koristi iste audio pathove kao Slot Lab:

```
SyntheticSlotEngine.spin()
        │
        ▼
    StageEvents
        │
        ▼
SlotLabProvider.playStages()
        │
        ▼
EventRegistry.trigger(stage)
        │
        ▼
    AudioPlayer(s)
```

**Nema promena u audio sistemu** — Preview je samo UI wrapper.

---

## Performance Considerations

| Aspect | Target |
|--------|--------|
| Enter/exit transition | < 100ms |
| Frame rate | 60fps (animations) |
| Memory overhead | < 10MB (particle cache) |
| State save/restore | Instant (no serialization) |

---

## Future Extensions

1. **Multi-Game Preview** — Switch između različitih slot konfiguracija
2. **A/B Testing** — Uporedi dva audio setup-a side by side
3. **Recording Mode** — Snimi gameplay + audio za demo
4. **Remote Preview** — Stream preview na drugi uređaj
5. **VR Preview** — Immersive slot experience (far future)

---

## References

- Existing: `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`
- Existing: `flutter_ui/lib/providers/slot_lab_provider.dart`
- Existing: `flutter_ui/lib/screens/slot_lab_screen.dart`
