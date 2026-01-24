# Stage Ingest Provider Ultra-Detailed Analysis

**Datum:** 2026-01-24
**Fajl:** `flutter_ui/lib/providers/stage_ingest_provider.dart`
**LOC:** ~1270
**Status:** ANALYSIS COMPLETE — NO P1 ISSUES

---

## Executive Summary

StageIngestProvider je ChangeNotifier za Universal Stage Ingest System — slot-agnostički sistem za integraciju sa bilo kojim game engine-om. Koristi semantičke STAGES umesto engine-specifičnih eventa.

### Filozofija

```
FluxForge NIKAD ne razume engine-specific events — samo STAGES.
Svi slot games prolaze kroz iste semantičke faze:
  Spin starts → Reels stop → Wins evaluated → Features triggered
```

### Arhitektura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       STAGE INGEST PROVIDER                                  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ THREE-LAYER INGEST                                                      ││
│  │ • Layer 1: DirectEvent — Engine ima event log → direktno mapiranje      ││
│  │ • Layer 2: SnapshotDiff — Engine ima pre/post state → diff derivacija   ││
│  │ • Layer 3: RuleBased — Generički events → heuristička rekonstrukcija    ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ TWO OPERATION MODES                                                     ││
│  │ • OFFLINE: JSON import → Adapter Wizard → StageTrace → Audio design    ││
│  │ • LIVE: WebSocket/TCP → Real-time STAGES → Live audio preview          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ RESOURCE MANAGEMENT                                                     ││
│  │ • _adapters: Map<String, AdapterInfo>                                   ││
│  │ • _traces: Map<int, StageTraceHandle>                                   ││
│  │ • _timedTraces: Map<int, TimedTraceHandle>                              ││
│  │ • _configs: Map<int, IngestConfig>                                      ││
│  │ • _wizards: Map<int, int>                                               ││
│  │ • _ruleEngines: Map<int, int>                                           ││
│  │ • _connectors: Map<int, ConnectorHandle>                                ││
│  │ • _liveEventController: StreamController<IngestStageEvent>              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Analiza po Ulogama

---

### 1. Chief Audio Architect 🎵

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Semantic stages** | 10-19 | Clean abstraction from engine events |
| **Timing profiles** | 39-46 | normal, turbo, mobile, instant, studio |
| **Stage creation helpers** | 1127-1137 | spinStart, spinEnd, reelStop, winPresent |
| **Bigwin thresholds** | 763-773 | Configurable win tier detection |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

**Verdict:** Excellent audio-first architecture for engine integration.

---

### 2. Lead DSP Engineer 🔧

**Ocena:** N/A

Not DSP-focused — provider handles data ingestion, not audio processing.

---

### 3. Engine Architect ⚙️

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Resource disposal** | 317-366 | Comprehensive cleanup of all handles |
| **Map-based tracking** | 234-263 | Clear handle→resource mapping |
| **StreamController** | 259-260 | Broadcast stream for live events |
| **Timer cleanup** | 326, 1044, 1159 | Proper cancel on dispose/stop |
| **Factory constructor** | 313-315 | Service locator integration |
| **Error handling** | 462-465, 698-701 | Destroys handles on error |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| Poll loop unbounded | 1050-1057 | Could process many events per tick | P2 |
| Generic catch in loadTraceFromJson | 462 | Catches all errors | P3 |

---

### 4. Technical Director 📐

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Assessment |
|---------|------------|
| **Enum-based types** | IngestLayer, TimingProfile, ConnectorState, ConnectorProtocol |
| **Factory constructors** | All models have fromJson() |
| **Comprehensive API** | 60+ public methods, well-organized by section |
| **Service locator** | Clean DI integration |
| **Mock engine** | Built-in staging mode for testing |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

---

### 5. UI/UX Expert 🎨

**Ocena:** ⭐⭐⭐⭐⭐ (5/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Rich getters** | 279-304 | adapters, traces, configs, connectors, etc. |
| **Staging mode** | 1169-1269 | Mock engine for offline testing |
| **Event stream** | 291 | liveEvents stream for UI binding |
| **Wizard API** | 781-860 | Auto-config generation |

#### Weaknesses ❌

| Issue | Impact | Priority |
|-------|--------|----------|
| None identified | — | — |

---

### 6. Graphics Engineer 🎮

**Ocena:** N/A

No direct rendering — provider is pure data/state management.

---

### 7. Security Expert 🔒

**Ocena:** ⭐⭐⭐⭐ (4/5)

#### Strengths ✅

| Feature | Lines | Assessment |
|---------|-------|------------|
| **Safe JSON parsing** | 81-88, 159-174, etc. | Uses .as? with fallbacks |
| **Handle validation** | 429-430, 444-445, etc. | Returns null/0 on failure |
| **Error recovery** | 462-465, 698-701 | Cleans up on parse failure |

#### Weaknesses ❌

| Issue | Line | Impact | Priority |
|-------|------|--------|----------|
| WebSocket URL not validated | 941-943 | Malformed URLs could cause issues | P2 |
| JSON sample not sanitized | 800-801 | Large JSON could consume memory | P3 |

---

## Identified Issues Summary

### P1 — Critical (Fix Immediately)

**NONE** — This provider is well-designed with no critical issues.

### P2 — High Priority

| ID | Issue | Line | Impact |
|----|-------|------|--------|
| P2.1 | Poll loop should be bounded | 1050-1057 | Could cause UI jank with many events |
| P2.2 | WebSocket URL validation | 941-943 | Malformed URLs not caught early |

### P3 — Lower Priority

| ID | Issue | Line | Impact |
|----|-------|------|--------|
| P3.1 | Generic catch clause | 462 | Could hide specific errors |
| P3.2 | Large JSON not bounded | 800-801 | Memory exhaustion possible |

---

## Architecture Highlights

### Clean Handle Management

```dart
/// Create a new stage trace
StageTraceHandle? createTrace(String traceId, String gameId) {
  final handle = _ffi.stageTraceCreate(traceId, gameId);
  if (handle == 0) return null;  // FFI failure check

  final traceHandle = StageTraceHandle(
    handle: handle,
    traceId: traceId,
    gameId: gameId,
  );
  _traces[handle] = traceHandle;  // Track for disposal
  notifyListeners();
  return traceHandle;
}
```

### Comprehensive Disposal

```dart
@override
void dispose() {
  _mockEngineSubscription?.cancel();
  if (_isStagingMode) MockEngineService.instance.stop();
  _pollingTimer?.cancel();
  _liveEventController.close();

  // Destroy all resources
  for (final handle in _traces.keys.toList()) {
    _ffi.stageTraceDestroy(handle);
  }
  // ... same for timedTraces, configs, wizards, ruleEngines, connectors

  super.dispose();
}
```

### Staging Mode for Testing

```dart
void enableStagingMode() {
  if (_isStagingMode) return;

  // Disconnect live connectors
  for (final connector in _connectors.values) {
    disconnect(connector.connectorId);
  }

  _isStagingMode = true;

  // Subscribe to mock engine events
  _mockEngineSubscription = MockEngineService.instance.events.listen((event) {
    final ingestEvent = IngestStageEvent(
      stage: event.stage,
      timestampMs: event.timestampMs,
      data: event.data,
    );
    _liveEventController.add(ingestEvent);
  });

  notifyListeners();
}
```

---

## Stats & Metrics

| Metric | Value |
|--------|-------|
| Total LOC | ~1270 |
| Enums | 4 (IngestLayer, TimingProfile, ConnectorState, ConnectorProtocol) |
| Data Models | 7 (AdapterInfo, StageTraceHandle, TimedTraceHandle, IngestConfig, WizardResult, ConnectorHandle, IngestStageEvent) |
| Provider Methods | 60+ |
| Resource Maps | 7 |
| FFI Integrations | 70+ calls to NativeFFI |

---

## Conclusion

**StageIngestProvider je primer enterprise-grade Flutter providera:**

✅ Comprehensive resource tracking (7 Maps)
✅ Proper disposal of all handles
✅ StreamController with broadcast for events
✅ Service locator integration
✅ Mock engine for testing
✅ Safe JSON parsing throughout
✅ Error recovery with cleanup
✅ No memory leaks

**No P1 fixes required.**

---

**Last Updated:** 2026-01-24 (Analysis COMPLETE — NO P1 ISSUES)
