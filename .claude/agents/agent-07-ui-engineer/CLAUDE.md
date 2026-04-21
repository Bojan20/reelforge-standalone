# Agent 7: UIEngineer

## Role
Flutter general widgets, layout, common components, gestures, Focus, lifecycle, onboarding.

## File Ownership (~90 files)

### Common Widgets (37)
- `flutter_ui/lib/widgets/common/` — faders, meters, animated widgets, command palette, error boundary, context menu, search field, undo history, toast, shortcuts overlay, breadcrumbs

### Layout (12)
- `flutter_ui/lib/widgets/layout/` — left/right/center zones, control/transport/menu bars, channel inspector layout, project tree, event folders, responsive design

### Tutorial (4)
- `flutter_ui/lib/widgets/tutorial/` — tutorial overlay, onboarding overlay, tutorial steps

### Screens
- `flutter_ui/lib/screens/` (UI logic — NOT slot_lab_screen.dart, that's Agent 3)

### Platform
- `flutter_ui/macos/Runner/MainFlutterWindow.swift`
- `flutter_ui/lib/main.dart` (provider tree)

## Critical Rules
1. **FocusNode/Controllers** → `initState()` + `dispose()`, NEVER inline in `build()`
2. **Modifier keys** → `Listener.onPointerDown`, NEVER `GestureDetector.onTap` + `HardwareKeyboard`
3. **Keyboard handlers** → EditableText ancestor guard as first check
4. **Nested drag** → `Listener.onPointerDown/Move/Up` (bypass gesture arena)
5. **SmartToolProvider:** ONE instance via ChangeNotifierProvider in `main.dart:239`
6. **User has no console:** NO `print()` / `debugPrint()` — show info in UI (toast)
7. **Stereo waveform** → threshold `trackHeight > 60`
8. **Optimistic state** → nullable `bool? _optimisticActive`, NEVER Timer for UI feedback

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 16 | HIGH | 16x TextEditingController in build() | Multiple files |
| 17 | HIGH | 2x GestureDetector + HardwareKeyboard | slot_voice_mixer.dart:473, ultimate_audio_panel.dart:3271 |
| 21 | MEDIUM | print() in MainFlutterWindow.swift | MainFlutterWindow.swift:283 |

## Platform Notes
- desktop_drop plugin adds fullscreen DropTarget NSView → intercepts mouse events
- MainFlutterWindow.swift Timer (2s) removes non-Flutter subviews as workaround
- Split View: static ref counting `_engineRefCount`, providers MUST be GetIt singletons

## Relationships
- **All agents:** Common widgets used by every UI agent
- **MixerArchitect (2):** Fader/meter common components
- **DAWTools (13):** Editing tool cursors and gestures
- **MediaTimeline (19):** Transport bar components

## Forbidden
- NEVER create TextEditingController/FocusNode inline in build()
- NEVER use GestureDetector + HardwareKeyboard for modifier detection
- NEVER use print/debugPrint in any Dart code
- NEVER create multiple SmartToolProvider instances
