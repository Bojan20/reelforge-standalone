# Provider Access Pattern Guide

**Created:** 2026-01-29
**Purpose:** Standard patterns for accessing Providers in FluxForge Studio
**Applies To:** All Flutter widgets in `flutter_ui/`

---

## Quick Reference

| Need | Pattern | Example |
|------|---------|---------|
| Display data (UI must update) | `context.watch<T>()` | `final mixer = context.watch<MixerProvider>();` |
| Call methods (no UI update needed) | `context.read<T>()` | `context.read<MixerProvider>().createChannel();` |
| Select specific field | `context.select<T, V>()` | `final count = context.select<MixerProvider, int>((p) => p.channels.length);` |
| Singleton (non-Provider) | Direct access | `DspChainProvider.instance.getChain(trackId)` |

---

## Detailed Patterns

### 1. REACTIVE ACCESS — `context.watch<T>()`

**Use when:** Displaying provider data in UI that should rebuild when provider changes.

```dart
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>();

  return Column(
    children: [
      Text('Channels: ${mixer.channels.length}'),
      for (final ch in mixer.channels)
        ChannelWidget(channel: ch),
    ],
  );
}
```

**Behavior:** Widget rebuilds whenever `notifyListeners()` is called on the provider.

---

### 2. READ-ONLY ACCESS — `context.read<T>()`

**Use when:** Calling a method, performing an action, or accessing data that doesn't affect UI rebuild.

```dart
void _handleCreateChannel() {
  final mixer = context.read<MixerProvider>();
  mixer.createChannel(name: 'Audio ${mixer.channels.length + 1}');
}
```

**Behavior:** No rebuild triggered. Use in callbacks, button handlers, lifecycle methods.

**Common use cases:**
- Button `onPressed` handlers
- Gesture callbacks
- `initState()` / `dispose()`
- Timer callbacks

---

### 3. SELECTIVE LISTENING — `context.select<T, V>()`

**Use when:** Large provider but only need to rebuild when specific field changes.

```dart
Widget build(BuildContext context) {
  // Only rebuild when channel count changes, not on volume/pan changes
  final channelCount = context.select<MixerProvider, int>(
    (provider) => provider.channels.length,
  );

  return Text('$channelCount channels');
}
```

**Behavior:** Only rebuilds when selected value changes. Reduces unnecessary rebuilds.

**Good for:**
- Large providers with many fields
- Performance-critical widgets
- Derived values (counts, sums, booleans)

---

### 4. SINGLETON ACCESS

**Use when:** Provider is a singleton and doesn't need `context`.

```dart
// DspChainProvider is a singleton
final chain = DspChainProvider.instance.getChain(trackId);

// With ListenableBuilder for reactivity
ListenableBuilder(
  listenable: DspChainProvider.instance,
  builder: (context, _) {
    final chain = DspChainProvider.instance.getChain(trackId);
    return _buildChainView(chain);
  },
)
```

**Singleton providers in FluxForge:**
- `DspChainProvider.instance`
- `TrackPresetService.instance`
- `NativeFFI.instance`

---

## Anti-Patterns (DO NOT USE)

### Using `watch()` in callbacks

```dart
// BAD: Causes unnecessary rebuild
void _handleClick() {
  final mixer = context.watch<MixerProvider>(); // Should be read()!
  mixer.doSomething();
}

// GOOD: Use read() for callbacks
void _handleClick() {
  final mixer = context.read<MixerProvider>();
  mixer.doSomething();
}
```

### Using `read()` for display data

```dart
// BAD: UI won't update when channels change
Widget build(BuildContext context) {
  final mixer = context.read<MixerProvider>(); // Should be watch()!
  return Text('Channels: ${mixer.channels.length}');
}

// GOOD: Use watch() for reactive display
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>();
  return Text('Channels: ${mixer.channels.length}');
}
```

### Multiple `watch()` calls in same build

```dart
// BAD: Excessive rebuilds
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>();
  final dsp = context.watch<DspChainProvider>();
  final routing = context.watch<RoutingProvider>();
  // Rebuilds on ANY change to ANY provider
}

// BETTER: Use Consumer2/Consumer3
Widget build(BuildContext context) {
  return Consumer2<MixerProvider, DspChainProvider>(
    builder: (context, mixer, dsp, _) {
      return _buildContent(mixer, dsp);
    },
  );
}

// BEST: Use select() for specific fields
Widget build(BuildContext context) {
  final channelCount = context.select<MixerProvider, int>((p) => p.channels.length);
  final chainCount = context.select<DspChainProvider, int>((p) => p.hasChain(trackId) ? 1 : 0);
  return Text('$channelCount channels, $chainCount chains');
}
```

---

## Provider Error Handling

Always wrap provider access in try-catch when provider might not be available:

```dart
Widget _buildMixerPanel() {
  MixerProvider? mixer;
  try {
    mixer = context.watch<MixerProvider>();
  } catch (_) {
    return _buildProviderUnavailableUI('MixerProvider');
  }

  return _buildMixerContent(mixer);
}
```

Or use `ProviderErrorBoundary`:

```dart
Widget _buildMixerPanel() {
  return ProviderErrorBoundary(
    providerName: 'MixerProvider',
    child: Consumer<MixerProvider>(
      builder: (context, mixer, _) => _buildMixerContent(mixer),
    ),
  );
}
```

---

## FluxForge Provider Inventory

| Provider | Type | Access Pattern |
|----------|------|----------------|
| `MixerProvider` | ChangeNotifier | `context.watch/read` |
| `RoutingProvider` | ChangeNotifier | `context.watch/read` |
| `DspChainProvider` | Singleton | `.instance` + `ListenableBuilder` |
| `MiddlewareProvider` | ChangeNotifier | `context.watch/read` |
| `SlotLabProvider` | ChangeNotifier | `context.watch/read` |
| `TimelinePlaybackProvider` | ChangeNotifier | `context.watch/read` |
| `AudioAssetManager` | Singleton | `.instance` |
| `NativeFFI` | Singleton | `.instance` |

---

## Decision Flowchart

```
Do I need the UI to rebuild when provider changes?
├─ YES → Is it a singleton?
│        ├─ YES → Use ListenableBuilder
│        └─ NO → Use context.watch<T>()
└─ NO → Am I in a callback/action handler?
         ├─ YES → Use context.read<T>()
         └─ NO → Consider context.select<T,V>() for specific fields
```

---

## Verification Checklist

When reviewing code, check:

- [ ] `watch()` only in `build()` methods
- [ ] `read()` in callbacks, not `watch()`
- [ ] No multiple `watch()` when `select()` would suffice
- [ ] Singleton providers accessed via `.instance`
- [ ] Error handling for potentially missing providers

---

**Document Version:** 1.0
**Last Updated:** 2026-01-29
