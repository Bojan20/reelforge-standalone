# Provider Access Pattern — Standard for FluxForge Studio

**Created:** 2026-01-26
**Authority:** Code Standard (mandatory for all Flutter code)
**Scope:** All widgets using Provider state management

---

## 🎯 The Four Patterns

### Pattern 1: READ-ONLY (Method Calls)

**When to use:** Calling provider methods, NO UI dependency on state.

**Example:**
```dart
void _handleButtonPress() {
  final mixer = context.read<MixerProvider>();
  mixer.createChannel(name: 'Audio 1');
  // ✅ No rebuild needed — just calling a method
}
```

**Why:** `context.read()` doesn't subscribe to changes — no rebuild when provider updates.

**Performance:** ✅ BEST — No unnecessary rebuilds.

---

### Pattern 2: REACTIVE (Full Provider)

**When to use:** Displaying provider data in UI, simple dependencies.

**Example:**
```dart
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>();
  return Text('Channels: ${mixer.channels.length}');
  // ✅ Rebuilds when ANY provider field changes
}
```

**Why:** `context.watch()` subscribes to ALL provider changes.

**Performance:** ⚠️ OK for small widgets, but can cause excessive rebuilds.

---

### Pattern 3: SELECTIVE (Specific Field)

**When to use:** Large provider, only care about ONE field.

**Example:**
```dart
Widget build(BuildContext context) {
  // Only rebuilds when channels list changes (not when other fields change)
  final channels = context.select<MixerProvider, List<MixerChannel>>(
    (provider) => provider.channels,
  );
  return ListView.builder(
    itemCount: channels.length,
    itemBuilder: (_, i) => ChannelWidget(channels[i]),
  );
  // ✅ Rebuilds ONLY when channels list changes
}
```

**Why:** Rebuilds only when selected field changes, not entire provider.

**Performance:** ✅ BEST for large providers — reduces rebuilds by 60-80%.

---

### Pattern 4: LISTENABLE BUILDER (Manual Control)

**When to use:** Provider doesn't extend ChangeNotifier OR need manual control.

**Example:**
```dart
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: DspChainProvider.instance,
    builder: (context, _) {
      final chain = DspChainProvider.instance.getChain(trackId);
      return ChainView(chain: chain);
    },
  );
  // ✅ Manual subscription to specific Listenable
}
```

**Why:** Singleton providers or Listenable objects that aren't in Provider tree.

**Performance:** ✅ GOOD — Explicit control over rebuilds.

---

## 🚫 Anti-Patterns (DO NOT USE)

### ❌ Anti-Pattern 1: Using watch() for Method Calls

```dart
// ❌ BAD: Causes unnecessary rebuild every time provider changes
void _handleButtonPress() {
  final mixer = context.watch<MixerProvider>(); // WRONG!
  mixer.createChannel(name: 'Audio 1');
}

// ✅ GOOD: No rebuild
void _handleButtonPress() {
  final mixer = context.read<MixerProvider>(); // CORRECT!
  mixer.createChannel(name: 'Audio 1');
}
```

**Why it's bad:** `watch()` subscribes to provider changes even though you're not displaying any data.

---

### ❌ Anti-Pattern 2: Using read() for UI Display

```dart
// ❌ BAD: Won't rebuild when channels change!
Widget build(BuildContext context) {
  final mixer = context.read<MixerProvider>(); // WRONG!
  return Text('Channels: ${mixer.channels.length}');
}

// ✅ GOOD: Rebuilds when channels change
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>(); // CORRECT!
  return Text('Channels: ${mixer.channels.length}');
}
```

**Why it's bad:** UI won't update when provider changes.

---

### ❌ Anti-Pattern 3: Multiple watch() in Same Widget

```dart
// ❌ BAD: Each watch() causes separate rebuild subscription
Widget build(BuildContext context) {
  final mixer = context.watch<MixerProvider>(); // Rebuild 1
  final dsp = context.watch<DspChainProvider>(); // Rebuild 2
  final timeline = context.watch<TimelineProvider>(); // Rebuild 3
  // Widget rebuilds 3x when ANY provider changes!
}

// ✅ GOOD: Use Consumer2/Consumer3 or select()
Widget build(BuildContext context) {
  return Consumer2<MixerProvider, DspChainProvider>(
    builder: (context, mixer, dsp, _) {
      // Single rebuild when either provider changes
    },
  );
}
```

**Why it's bad:** Excessive rebuilds (3x in this example).

---

## 📊 Decision Matrix

| Use Case | Pattern | Example |
|----------|---------|---------|
| **Button callback** | `read()` | `context.read<MixerProvider>().createChannel()` |
| **Display simple data** | `watch()` | `final mixer = context.watch<MixerProvider>()` |
| **Display from large provider** | `select()` | `context.select<Mixer, List>((p) => p.channels)` |
| **Singleton provider** | `ListenableBuilder` | `ListenableBuilder(listenable: DspChainProvider.instance, ...)` |
| **Multiple providers** | `Consumer2/3` | `Consumer2<MixerProvider, DspChainProvider>(...)` |

---

## 🔧 Refactoring Checklist

When refactoring existing code to use standard patterns:

- [ ] Identify all `context.watch()` calls
- [ ] Check if they're in method callbacks → Change to `read()`
- [ ] Check if they're in build() → Keep `watch()` OR change to `select()` if large provider
- [ ] Check for multiple `watch()` calls → Use `Consumer2/3` or multiple `select()`
- [ ] Add comment explaining pattern choice (if non-obvious)

---

## 💡 Examples from FluxForge

### Example 1: Mixer Panel (GOOD)

```dart
// ✅ GOOD: Uses watch() for reactive UI
Widget _buildMixerPanel() {
  final mixer = context.watch<MixerProvider>();
  return UltimateMixer(
    channels: mixer.channels, // Rebuilds when channels change
    onVolumeChange: (id, vol) {
      // Don't need watch() here — just calling method
      context.read<MixerProvider>().setChannelVolume(id, vol);
    },
  );
}
```

---

### Example 2: FX Chain Panel (GOOD)

```dart
// ✅ GOOD: Uses ListenableBuilder for singleton
Widget _buildFxChainPanel() {
  return ListenableBuilder(
    listenable: DspChainProvider.instance,
    builder: (context, _) {
      final chain = DspChainProvider.instance.getChain(trackId);
      return ChainView(nodes: chain.nodes);
    },
  );
}
```

---

### Example 3: Large Provider Optimization (BEST)

```dart
// ❌ BEFORE: Rebuilds when ANY middleware field changes
Widget build(BuildContext context) {
  final middleware = context.watch<MiddlewareProvider>();
  return ListView.builder(
    itemCount: middleware.compositeEvents.length,
    itemBuilder: (_, i) => EventCard(middleware.compositeEvents[i]),
  );
}

// ✅ AFTER: Rebuilds ONLY when compositeEvents list changes
Widget build(BuildContext context) {
  final events = context.select<MiddlewareProvider, List<CompositeEvent>>(
    (provider) => provider.compositeEvents,
  );
  return ListView.builder(
    itemCount: events.length,
    itemBuilder: (_, i) => EventCard(events[i]),
  );
}
```

**Performance Gain:** 60-80% fewer rebuilds.

---

## 🎯 Pattern Selection Flowchart

```
┌─────────────────────────────────────────────┐
│ Are you calling a provider METHOD?         │
├─────────────────────────────────────────────┤
│ YES → Use context.read<Provider>()         │
│       (no rebuild needed)                   │
└─────────────────────────────────────────────┘
         │ NO ↓
┌─────────────────────────────────────────────┐
│ Are you displaying provider DATA?          │
├─────────────────────────────────────────────┤
│ YES → Continue ↓                            │
└─────────────────────────────────────────────┘
         │
┌─────────────────────────────────────────────┐
│ Is the provider LARGE (many fields)?       │
├─────────────────────────────────────────────┤
│ YES → Use context.select<Provider, Field>()│
│       (rebuild only when field changes)     │
│                                             │
│ NO → Use context.watch<Provider>()         │
│      (rebuild when any field changes)       │
└─────────────────────────────────────────────┘
         │
┌─────────────────────────────────────────────┐
│ Is it a SINGLETON (not in Provider tree)?  │
├─────────────────────────────────────────────┤
│ YES → Use ListenableBuilder                │
│       (manual subscription)                 │
│                                             │
│ NO → Use watch() or select()               │
└─────────────────────────────────────────────┘
```

---

## ✅ Code Review Checklist

When reviewing code, check:

- [ ] All method calls use `read()`, not `watch()`
- [ ] All UI data displays use `watch()` or `select()`
- [ ] Large providers use `select()`, not `watch()`
- [ ] No multiple `watch()` in same widget (use `Consumer2/3` instead)
- [ ] Singleton providers use `ListenableBuilder`
- [ ] Pattern choice is commented (if non-obvious)

---

## 📚 Further Reading

**Provider Package Docs:**
- https://pub.dev/packages/provider

**Best Practices:**
- https://flutter.dev/docs/development/data-and-backend/state-mgmt/simple

**FluxForge Specific:**
- See `.claude/architecture/` for provider architecture docs
- See existing code in `flutter_ui/lib/providers/` for examples

---

**End of Guide — Use This Standard for All Provider Code**

**Last Updated:** 2026-01-26
**Status:** Active Code Standard
