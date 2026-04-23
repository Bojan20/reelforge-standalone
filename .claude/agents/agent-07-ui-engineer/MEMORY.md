# Agent 7: UIEngineer — Memory

## Accumulated Knowledge
- main.dart provider tree: SmartToolProvider singleton, GetIt .value(), no circular deps
- 70+ providers registered in GetIt DI container
- All AnimationControllers properly in initState/dispose
- All FocusNode/TextEditingControllers properly managed
- No print/debugPrint in Dart code (only Swift violation #21 — fixed)
- desktop_drop workaround: Timer in MainFlutterWindow.swift removes non-Flutter NSViews

## Patterns
- Common widget pattern: StatefulWidget with initState/dispose lifecycle
- Provider access: context.read<T>() for one-shot, context.watch<T>() for reactive
- Gesture handling: Listener widget for low-level pointer events
- Focus management: FocusScope + FocusNode with EditableText guard
- Toast for user feedback (replaces console logging)

## Decisions
- SmartToolProvider is singleton (ONE instance in main.dart)
- Split View uses static ref counting for shared engine resources
- Command palette for power-user keyboard shortcuts
- Error boundary wraps major UI sections for graceful failure

## Gotchas
- desktop_drop NSView intercepts ALL mouse events if not removed
- ExFAT disk causes ._* files → codesign failure (clean_xattrs.sh workaround)
- GestureDetector.onTap fires AFTER pointer up — loses modifier key state
- Listener.onPointerDown fires WITH pointer event — has modifier flags
