# Unified SlotLab Architecture

**Status:** IN PROGRESS
**Branch:** `feature/unified-slotlab-middleware`
**Created:** 2026-03-04

---

## Princip

SlotLab JESTE middleware za slot igre. Nema odvojene middleware sekcije.
Korisnik nikad ne napušta SlotLab — sve alate ima na jednom ekranu.

## Navigacija (NOVO)

```
Launcher → SlotLab (unified — slot mašina + middleware alati)
Launcher → DAW (netaknuto)
```

**UKIDA SE:**
- MiddlewareHubScreen (launcher za middleware projekte)
- EditorMode.middleware (middleware kao zaseban mod)
- Middleware lower zone widget
- Navigacija Middleware → SlotLab → Back to Middleware

**OSTAJE:**
- EditorMode.daw (DAW mod — netaknut)
- EditorMode.slot (sada se otvara direktno sa LauncherScreen)

---

## Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ CONTROL BAR: Transport | Mode (DAW/SlotLab) | Settings          │
├────────────┬─────────────────────────────────┬───────────────────┤
│ LEFT ZONE  │        CENTER ZONE              │  RIGHT ZONE       │
│            │                                 │                   │
│ Audio      │  Slot Machine Preview           │  Event Inspector  │
│ Assignment │  (Premium/Basic)                │  - Selected event │
│ by Stage   │                                 │  - Layer details  │
│            │  Timeline                       │  - Properties     │
│ Event      │  (stages + audio regions)       │  - Trigger stages │
│ Browser    │                                 │  - RTPC bindings  │
│ (tree)     │                                 │                   │
├────────────┴─────────────────────────────────┴───────────────────┤
│ LOWER ZONE (tabbed)                                              │
│                                                                  │
│ Core tabs:                                                       │
│ [Events] [Mixer] [RTPC] [Containers] [Music] [Meters] [Debug]  │
│                                                                  │
│ Advanced [+] menu:                                               │
│ Ducking | Attenuation | States | Switches | Spatial |            │
│ Automation | Stage Flow | Game Config                            │
└──────────────────────────────────────────────────────────────────┘
```

---

## Lower Zone Tabovi

### Core (uvek u tab baru):

| Tab | Sadržaj | Izvor |
|-----|---------|-------|
| Events | Composite editor — DAW-style layer timeline + properties | Merge: CompositeEditorPanel + EventEditorPanel |
| Mixer | Bus hierarchy + aux sends + metering per bus | Postojeći iz SlotLab |
| RTPC | RTPC krive + macro editor + debugger | Iz middleware: rtpc_macro_editor, rtpc_debugger |
| Containers | Blend + Random + Sequence (3 sub-taba) | Iz middleware: blend/random/sequence_container_panel |
| Music | Segments + stingers + transitions | Iz middleware: music_system_panel |
| Meters | LUFS + Peak + Correlation + spectrum | Postojeći iz SlotLab |
| Debug | Event log + profiler + resources + engine | Postojeći iz SlotLab |

### Advanced [+] menu (popup, otvara se po potrebi):

| Stavka | Sadržaj | Izvor |
|--------|---------|-------|
| Ducking | Ducking matrix sa pravilima | Iz middleware: ducking_matrix_panel |
| Attenuation | Game value → audio parameter krive | Iz middleware: attenuation_curve_panel |
| States | Wwise-style state grupe | Iz middleware: advanced_middleware_panel (States tab) |
| Switches | Per-object zvučne varijante | Iz middleware: advanced_middleware_panel (Switches tab) |
| Spatial | 3D pozicioniranje | Iz middleware: spatial_designer_widget |
| Automation | Automation lane editor | Iz middleware: automation_lane_editor |
| Stage Flow | Stage flow dijagram + editor | Postojeći iz SlotLab |
| Game Config | Game model + GDD import | Postojeći iz SlotLab |
| Scenarios | Scenario editor + kontrole | Postojeći iz SlotLab |

---

## Šta se briše (duplikati)

| Fajl | LOC | Razlog |
|------|-----|--------|
| middleware_hub_screen.dart | 1,270 | Nepotreban launcher |
| events_folder_panel.dart (middleware/) | 2,400 | Duplikat EventsPanelWidget |
| middleware_lower_zone_widget.dart | ~1,500 | Zamenjuje ga unified lower zone |
| middleware_lower_zone_controller.dart | ~500 | Kontroler za obrisani widget |

**Total brisanje:** ~5,670 LOC

---

## Šta se SELI u SlotLab lower zone

| Fajl | LOC | Destinacija |
|------|-----|-------------|
| event_editor_panel.dart | 4,900 | Events tab (unified layer editor) |
| blend_container_panel.dart | 950 | Containers tab |
| random_container_panel.dart | 1,120 | Containers tab |
| sequence_container_panel.dart | 1,150 | Containers tab |
| ducking_matrix_panel.dart | 1,180 | Advanced → Ducking |
| attenuation_curve_panel.dart | 1,010 | Advanced → Attenuation |
| rtpc_macro_editor_panel.dart | 900 | RTPC tab |
| rtpc_debugger_panel.dart | 800 | RTPC tab |
| music_system_panel.dart | 1,200 | Music tab |
| spatial_designer_widget.dart | 800 | Advanced → Spatial |
| automation_lane_editor.dart | 865 | Advanced → Automation |
| bus_hierarchy_panel.dart (middleware/) | 2,000 | NE SELI — SlotLab ima svoj |

---

## Šta se NE MENJA

### Provideri (svi ostaju):
- MiddlewareProvider (4,074 LOC)
- 16 subsystem providera (9,286 LOC)
- EventRegistry (3,929 LOC)
- EventSyncService, StageAudioMapper, StageConfigurationService
- Svi SlotLab provideri (32 komada)

### SlotLab UI (ostaje isto):
- SlotPreviewWidget, PremiumSlotPreview
- UltimateAudioPanel (levi panel)
- UltimateTimelineWidget (centar)
- EventsPanelWidget (desni panel)
- Svi bonus paneli, template paneli, GDD import

### DAW (potpuno netaknut):
- DawHubScreen, DawLowerZoneWidget
- Timeline, clips, tracks
- DSP paneli, mixer

---

## Implementacioni koraci

### Korak 1: Navigacija
- LauncherScreen: zameni "Middleware" dugme sa "SlotLab"
- EngineConnectedLayout: ukloni EditorMode.middleware logiku
- SlotLab se otvara direktno (ne preko middleware moda)

### Korak 2: Lower Zone proširenje
- Dodaj tabove u SlotLabLowerZoneWidget: RTPC, Containers, Music
- Integriši middleware panele kao sadržaj tih tabova
- Dodaj [+] Advanced menu sa Ducking, Attenuation, States, Switches, Spatial

### Korak 3: Events tab upgrade
- Merge EventEditorPanel funkcionalnost u postojeći Events tab
- Unified layer editor: timeline + properties + RTPC + action type

### Korak 4: Brisanje
- Obriši middleware_hub_screen.dart
- Obriši events_folder_panel.dart (middleware/)
- Obriši middleware_lower_zone_widget.dart + controller
- Obriši EditorMode.middleware reference
- Obriši LauncherScreen middleware opciju

### Korak 5: Verifikacija
- flutter analyze = 0 errors
- Svi provideri rade
- Event kreiranje → layer dodavanje → audio playback → radi u SlotLab-u
- DAW mod netaknut
- Nema reference na obrisane fajlove

---

## Rizici i mitigacija

| Rizik | Mitigacija |
|-------|-----------|
| Engine connected layout je 5000+ LOC — teško za editovanje | Hirurški rezovi, ne refaktor celog fajla |
| Middleware paneli koriste engine_connected_layout state | Provere da li čitaju iz providera (ok) ili iz lokalnog state-a (problem) |
| SlotLab lower zone widget je 4900 LOC — dodavanje tabova ga povećava | Svaki tab je zaseban widget, lower zone je samo router |
| DAW korisnici slučajno pogođeni | DAW mod potpuno izolovan — EditorMode.daw ostaje |
