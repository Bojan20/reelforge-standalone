# Provider Access Pattern Guide

**Purpose:** Standard patterns for accessing Providers in FluxForge Studio

---

## Quick Reference

| Need | Pattern | Example |
|------|---------|---------|
| Display data (rebuilds on change) | `context.watch<T>()` | `final mixer = context.watch<MixerProvider>();` |
| Call methods (no rebuild) | `context.read<T>()` | `context.read<MixerProvider>().createChannel();` |
| Select specific field | `context.select<T, V>()` | `context.select<MixerProvider, int>((p) => p.channels.length);` |
| Singleton (non-Provider) | Direct access | `DspChainProvider.instance.getChain(trackId)` |

---

## Patterns

### 1. `context.watch<T>()` — Reactive

Use in `build()` to display data that should update on changes.

```dart
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>();
  return Text('Channels: ${mixer.channels.length}');
}
```

### 2. `context.read<T>()` — One-shot

Use in callbacks, handlers, `initState()`, `dispose()`, timers.

```dart
void _handleClick() {
  context.read<MixerProvider>().createChannel(name: 'Audio 1');
}
```

### 3. `context.select<T, V>()` — Selective

Only rebuilds when selected value changes. Use for large providers.

```dart
final count = context.select<MixerProvider, int>((p) => p.channels.length);
```

### 4. Singleton Access

```dart
final chain = DspChainProvider.instance.getChain(trackId);

// For reactivity:
ListenableBuilder(
  listenable: DspChainProvider.instance,
  builder: (context, _) => _buildChainView(DspChainProvider.instance.getChain(trackId)),
)
```

**Singletons:** `DspChainProvider.instance`, `TrackPresetService.instance`, `NativeFFI.instance`

---

## Anti-Patterns

| BAD | GOOD | Why |
|-----|------|-----|
| `watch()` in callbacks | `read()` in callbacks | watch causes unnecessary rebuilds |
| `read()` in `build()` for display | `watch()` in `build()` | read won't update UI |
| Multiple `watch()` on large providers | `select()` for specific fields | Reduces rebuild scope |
| Multiple `watch()` calls | `Consumer2`/`Consumer3` | Cleaner multi-provider access |

---

## Error Handling

```dart
// Try-catch pattern
MixerProvider? mixer;
try {
  mixer = context.watch<MixerProvider>();
} catch (_) {
  return _buildProviderUnavailableUI('MixerProvider');
}

// Or use ProviderErrorBoundary widget
ProviderErrorBoundary(
  providerName: 'MixerProvider',
  child: Consumer<MixerProvider>(
    builder: (context, mixer, _) => _buildContent(mixer),
  ),
)
```

---

## Provider Inventory

| Provider | Type | Access |
|----------|------|--------|
| `MixerProvider` | ChangeNotifier | watch/read |
| `RoutingProvider` | ChangeNotifier | watch/read |
| `DspChainProvider` | Singleton | .instance + ListenableBuilder |
| `MiddlewareProvider` | ChangeNotifier | watch/read |
| `SlotLabProvider` | ChangeNotifier | watch/read |
| `TimelinePlaybackProvider` | ChangeNotifier | watch/read |
| `AudioAssetManager` | Singleton | .instance |
| `NativeFFI` | Singleton | .instance |

---

## Decision Flowchart

```
Need UI rebuild on change?
├─ YES → Singleton? → YES: ListenableBuilder
│                   → NO:  context.watch<T>()
└─ NO  → Callback?  → YES: context.read<T>()
                    → NO:  context.select<T,V>()
```

## Checklist

- `watch()` only in `build()`
- `read()` in callbacks
- `select()` over multiple `watch()` when possible
- Singletons via `.instance`
- Error handling for missing providers
