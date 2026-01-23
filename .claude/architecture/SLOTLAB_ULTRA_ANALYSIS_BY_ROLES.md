# SLOTLAB ULTRA ANALYSIS BY ROLES — Stage Map Vision

**Date:** 2026-01-23
**Status:** ULTIMATIVNA ANALIZA
**Scope:** Event Builder + Stage Map + Slot Mockup Ultra-Modifikacije
**Princip:** UVEK ULTIMATIVNO NAJBOLJE REŠENJE, NIKAD JEDNOSTAVNO

---

## EXECUTIVE SUMMARY

Trenutni SlotLab layout ima tri panela:
- **LEFT:** Game Spec & Paytable (260px)
- **CENTER:** Timeline + Stage Trace + Mock Slot (flex: 3)
- **RIGHT:** Event Editor + Audio Browser (300px)

**Problem:** Event Builder nije uvek vidljiv. Stage Map ne postoji. Slot Mockup nema semantičke drop zone.

**Ultimativno rešenje:** Stage Map kao PRIMARY NAVIGATION + Persistent Event Builder + Intelligent Drop Zones.

---

## 🎮 ULOGA 1: Slot Game Designer

### Šta koristi
- Game Spec panel (reels, rows, volatility)
- Mock Slot Preview
- Paytable visualization
- Feature flow indicators

### Šta nedostaje (CRITICAL)

| Gap | Impact | Priority |
|-----|--------|----------|
| **Stage Map** | Nema vizuelnu mapu audio arhitekture igre | 🔴 P0 |
| **GDD Visual Hierarchy** | Ne vidi strukturu GLOBAL→BASE→FS→FEATURES→OVERLAYS | 🔴 P0 |
| **Symbol Groups** | Hardcoded SymbolTier enum umesto dinamičkih GDD grupa | 🟠 P1 |
| **Feature Blocks** | Ne može vizualizovati custom feature audio zone | 🟠 P1 |
| **Win Tier Mapping** | Win tierovi nisu povezani sa Stage Map | 🟡 P2 |

### ULTRA MODIFIKACIJA — Stage Map Navigation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SLOTLAB ULTRA                                   │
├────────────────────┬────────────────────────────────────────┬───────────────┤
│                    │                                        │               │
│   ┌────────────┐   │    ╔═══════════════════════════╗      │  ┌─────────┐  │
│   │ STAGE MAP  │   │    ║     MOCK SLOT PREVIEW     ║      │  │ EVENT   │  │
│   │            │   │    ║   (DROP-ENABLED ZONES)    ║      │  │ BUILDER │  │
│   │ ▼ GLOBAL   │   │    ╚═══════════════════════════╝      │  │         │  │
│   │   UI       │   │                                        │  │ Always  │  │
│   │   AMB      │   │    ╔═══════════════════════════╗      │  │ Visible │  │
│   │   VO       │   │    ║      AUDIO TIMELINE       ║      │  │         │  │
│   │            │   │    ║   (Synced with Stage)     ║      │  │ Context │  │
│   │ ▼ BASE     │   │    ╚═══════════════════════════╝      │  │ Aware   │  │
│   │   Music    │   │                                        │  │         │  │
│   │   Reels    │   │    ═══════════════════════════════    │  │ Drop    │  │
│   │   Symbols  │   │           STAGE PROGRESS BAR          │  │ Target  │  │
│   │   Wins     │   │    ═══════════════════════════════    │  │         │  │
│   │   UI       │   │                                        │  └─────────┘  │
│   │            │   ├────────────────────────────────────────┤               │
│   │ ▼ FREESPINS│   │         LOWER ZONE (Tabs)              │  ┌─────────┐  │
│   │   (inherit)│   │  Timeline│Bus│RTPC│Events│GDD│Ingest   │  │ AUDIO   │  │
│   │            │   │                                        │  │ BROWSER │  │
│   │ ▼ FEATURES │   │                                        │  │         │  │
│   │   Bonus_A  │   │                                        │  │ Drag    │  │
│   │   Bonus_B  │   │                                        │  │ Source  │  │
│   │            │   │                                        │  │         │  │
│   │ ▼ OVERLAYS │   │                                        │  └─────────┘  │
│   │   BigWin   │   │                                        │               │
│   │   Jackpot  │   │                                        │               │
│   └────────────┘   │                                        │               │
│                    │                                        │               │
│       200px        │              FLEX                      │     350px     │
└────────────────────┴────────────────────────────────────────┴───────────────┘
```

### Konkretne promene za Slot Game Designer

1. **Stage Map panel na LEFT** — zamenjuje Game Spec
   - Game Spec se seli u modal/settings
   - Stage Map postaje PRIMARY navigation

2. **GDD-Driven Tree** — dinamički generisano
   ```dart
   StageMapTree(
     gdd: currentGdd,
     onZoneSelected: (zone) => _setEventBuilderContext(zone),
     onAudioDropped: (zone, path) => _createEventForZone(zone, path),
   )
   ```

3. **Symbol Groups iz GDD** — ne hardcoded tier-ovi
   ```dart
   // Before: enum SymbolTier { low, mid, high, premium, special, wild, scatter, bonus }
   // After:
   class DynamicSymbolGroup {
     final String id;           // "fruits", "royals", "themed"
     final String displayName;  // "Fruit Symbols"
     final List<Symbol> symbols;
     final Color color;
   }
   ```

---

## 🎵 ULOGA 2: Audio Designer / Composer

### Šta koristi
- Audio Timeline (region editing)
- Composite Events panel
- Audio Browser (file selection)
- Bus Hierarchy panel
- RTPC editor

### Šta nedostaje (CRITICAL)

| Gap | Impact | Priority |
|-----|--------|----------|
| **Event Builder uvek vidljiv** | Mora menjati tab da kreira event | 🔴 P0 |
| **Drop Zone Feedback** | Nema vizuelni feedback šta se dešava na drop | 🔴 P0 |
| **Context-Aware Creation** | Ne zna automatski stage iz drop zone | 🟠 P1 |
| **Multi-Layer Preview** | Teško čuti sve layere zajedno pre commit-a | 🟠 P1 |
| **Bus Assignment Suggestions** | Nema automatski predlog busa | 🟡 P2 |

### ULTRA MODIFIKACIJA — Persistent Event Builder

**Princip:** Event Builder je UVEK vidljiv, UVEK kontekstualno svestan.

```dart
/// Persistent Event Builder Widget (desni panel, uvek prisutan)
class PersistentEventBuilder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EventBuilderContext>(
      builder: (ctx, builderCtx, _) {
        return Column(
          children: [
            // CONTEXT HEADER — Shows where audio will be bound
            _ContextHeader(
              stage: builderCtx.currentStage,      // "BASE_GAME.REELS.REEL_STOP_3"
              zone: builderCtx.currentZone,        // "reel.3"
              suggestedBus: builderCtx.suggestedBus, // "SFX/Reels"
            ),

            Divider(),

            // QUICK BUILDER — Minimal form for rapid creation
            _QuickBuilder(
              onAssetDropped: (path) => builderCtx.addLayer(path),
              currentLayers: builderCtx.pendingLayers,
            ),

            Divider(),

            // LAYER LIST — Preview pending layers
            Expanded(
              child: _PendingLayersList(
                layers: builderCtx.pendingLayers,
                onLayerRemoved: builderCtx.removeLayer,
                onLayerReordered: builderCtx.reorderLayers,
              ),
            ),

            // COMMIT BUTTON
            _CommitButton(
              enabled: builderCtx.canCommit,
              onCommit: () => builderCtx.commitEvent(),
            ),
          ],
        );
      },
    );
  }
}
```

### Context Flow

```
DROP on Stage Map Zone
        ↓
EventBuilderContext updated
        ↓
PersistentEventBuilder reflects:
  • Stage: "BASE_GAME"
  • Zone: "REELS → Reel 3 → Stop"
  • Suggested Bus: "SFX/Reels"
  • Suggested Preset: "reel_stop"
        ↓
Audio layer added to pending list
        ↓
Preview button → hear all layers
        ↓
Commit → SlotCompositeEvent created
```

### Drop Zone Visual Feedback

```dart
class DropZoneIndicator extends StatelessWidget {
  final DropZoneState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 150),
      decoration: BoxDecoration(
        border: Border.all(
          color: switch (state) {
            DropZoneState.empty => Colors.white24,
            DropZoneState.hovered => FluxForgeTheme.accentBlue,
            DropZoneState.populated => FluxForgeTheme.accentGreen,
            DropZoneState.hasVariants => FluxForgeTheme.accentOrange,
          },
          width: state == DropZoneState.hovered ? 2 : 1,
        ),
        boxShadow: state == DropZoneState.hovered ? [
          BoxShadow(
            color: FluxForgeTheme.accentBlue.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ] : null,
      ),
      child: Stack(
        children: [
          // Zone content
          child,

          // Status indicator
          if (state == DropZoneState.populated)
            Positioned(
              top: 4, right: 4,
              child: Icon(Icons.check_circle,
                color: FluxForgeTheme.accentGreen, size: 12),
            ),

          if (state == DropZoneState.hasVariants)
            Positioned(
              top: 4, right: 4,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('3', style: TextStyle(fontSize: 10, color: Colors.black)),
              ),
            ),
        ],
      ),
    );
  }
}
```

---

## 🧠 ULOGA 3: Audio Middleware Architect

### Šta koristi
- Event Registry
- Stage → Event mappings
- Bus hierarchy
- Voice pool configuration
- RTPC bindings
- State/Switch groups

### Šta nedostaje (CRITICAL)

| Gap | Impact | Priority |
|-----|--------|----------|
| **Stage Map = Event Architecture** | Nema vizuelnu reprezentaciju event grafa | 🔴 P0 |
| **Override Visualization** | Ne vidi gde FreeSpins override-uje BaseGame | 🔴 P0 |
| **Dependency Graph** | Nema event dependency visualization | 🟠 P1 |
| **Voice Pool Monitor** | Teško pratiti voice allocation u realnom vremenu | 🟠 P1 |
| **Takeover Policies** | Overlay behavior nije vizualizovan | 🟡 P2 |

### ULTRA MODIFIKACIJA — Stage Map as Event Architecture

```
STAGE MAP NODE:
┌───────────────────────────────────────────────┐
│ ▼ BASE_GAME.REELS.REEL_STOP_3                 │
├───────────────────────────────────────────────┤
│ 🎵 Event: reel_stop_3_main                    │
│    ├─ Layers: 3                               │
│    ├─ Bus: SFX/Reels                          │
│    ├─ Preset: reel_stop                       │
│    └─ Polyphony: 5                            │
│                                               │
│ 📊 Stats:                                     │
│    ├─ Triggers/session: 847                   │
│    ├─ Voice steals: 12                        │
│    └─ Avg latency: 1.2ms                      │
│                                               │
│ 🔗 Dependencies:                              │
│    └─ Stops: reel_spin_loop_3                 │
│                                               │
│ [Edit] [Preview] [Delete]                     │
└───────────────────────────────────────────────┘
```

### Stage Override Visualization

```dart
/// Shows which stages override parent stages
class StageOverrideIndicator extends StatelessWidget {
  final StageMapNode baseStage;
  final StageMapNode? overrideStage;

  @override
  Widget build(BuildContext context) {
    if (overrideStage == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.2),
        border: Border.all(color: Colors.purple),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers, size: 12, color: Colors.purple),
          SizedBox(width: 4),
          Text(
            'Overrides: ${baseStage.label}',
            style: TextStyle(fontSize: 10, color: Colors.purple),
          ),
        ],
      ),
    );
  }
}
```

### Event Dependency Graph

```dart
/// Visualizes event dependencies in Stage Map
class EventDependencyArrows extends StatelessWidget {
  final List<EventDependency> dependencies;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DependencyArrowsPainter(
        dependencies: dependencies,
        arrowColor: FluxForgeTheme.accentCyan.withOpacity(0.6),
        arrowStyle: DependencyArrowStyle.curved,
      ),
    );
  }
}

class EventDependency {
  final String sourceEventId;
  final String targetEventId;
  final DependencyType type; // after, stops, triggers, ducks
}
```

---

## 🛠 ULOGA 4: Engine / Runtime Developer

### Šta koristi
- FFI bindings
- Voice pool stats
- Latency monitoring
- Memory budget
- Profiler panel

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Live FFI Metrics** | Nema real-time FFI latency per operation | 🟠 P1 |
| **Voice Allocation View** | Teško videti voice→event mapping | 🟠 P1 |
| **Memory per Zone** | Nema memory breakdown po Stage Map zonama | 🟡 P2 |

### ULTRA MODIFIKACIJA — Stage Map Performance Overlay

```dart
/// Overlay that shows performance metrics per stage zone
class StagePerformanceOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<PerformanceMetrics>(
      builder: (ctx, metrics, _) {
        return Stack(
          children: [
            // Per-zone metrics badges
            for (final zone in metrics.activeZones)
              Positioned(
                left: zone.visualPosition.dx,
                top: zone.visualPosition.dy,
                child: _ZoneMetricsBadge(
                  zone: zone,
                  activeVoices: metrics.voicesForZone(zone.id),
                  avgLatencyMs: metrics.avgLatencyForZone(zone.id),
                  memoryKb: metrics.memoryForZone(zone.id),
                ),
              ),
          ],
        );
      },
    );
  }
}
```

---

## 🧩 ULOGA 5: Tooling / Editor Developer

### Šta koristi
- Widget structure
- Provider patterns
- Drag-drop implementations
- Keyboard shortcuts
- Lower zone tabs

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Stage Map Widget System** | Nema reusable Stage Map components | 🔴 P0 |
| **Drop Zone Registry** | Drop zones su hard-coded, ne deklarativne | 🔴 P0 |
| **Event Builder Context Provider** | Nema centralizovan context za builder | 🟠 P1 |
| **Keyboard Navigation** | Stage Map nema keyboard nav | 🟡 P2 |

### ULTRA MODIFIKACIJA — Declarative Stage Map System

```dart
/// Stage Map widget system - fully declarative
library stage_map;

// ═══════════════════════════════════════════════════════════════════════════
// CORE MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Node in Stage Map tree
class StageMapNode {
  final String id;
  final StageMapNodeType type;
  final String label;
  final List<StageMapNode> children;
  final StageMapZone? zone;
  final StageMapNode? parent;

  bool get isDropZone => zone != null;
  bool get isCollapsible => children.isNotEmpty;
  String get fullPath => parent != null
    ? '${parent!.fullPath}.$id'
    : id;
}

enum StageMapNodeType {
  root,           // Koren stabla
  globalZone,     // GLOBAL AUDIO LAYER
  stageBlock,     // BASE GAME, FREE SPINS, FEATURE: X
  systemZone,     // Music, Reels, Symbols, Wins, UI
  groupZone,      // Symbol grupa, Reel index
  entityZone,     // Konkretan simbol, UI element
  dropZone,       // Leaf - audio binding point
}

/// Drop zone definition
class StageMapZone {
  final String stageId;
  final String systemType;
  final String? groupId;
  final String? entityId;
  final List<String> interactionTypes; // press, land, stop, loop
  final String suggestedBus;
  final String suggestedPreset;

  bool get isPopulated => _eventRegistry.hasEventForZone(this);
  int get variantCount => _eventRegistry.variantCountForZone(this);
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

/// Main Stage Map widget
class StageMapWidget extends StatefulWidget {
  final StageMapNode root;
  final void Function(StageMapZone zone)? onZoneTapped;
  final void Function(StageMapZone zone, String audioPath)? onAudioDropped;
  final void Function(StageMapNode node)? onNodeExpanded;
  final void Function(StageMapNode node)? onNodeCollapsed;

  const StageMapWidget({
    required this.root,
    this.onZoneTapped,
    this.onAudioDropped,
    this.onNodeExpanded,
    this.onNodeCollapsed,
  });
}

/// Individual tree node
class StageMapNodeWidget extends StatelessWidget {
  final StageMapNode node;
  final int depth;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node header
        InkWell(
          onTap: node.isCollapsible ? onToggle : null,
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Row(
              children: [
                if (node.isCollapsible)
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                  ),

                _NodeIcon(type: node.type),
                SizedBox(width: 8),
                Text(node.label),

                if (node.isDropZone) ...[
                  Spacer(),
                  _DropZoneBadge(zone: node.zone!),
                ],
              ],
            ),
          ),
        ),

        // Children (if expanded)
        if (isExpanded && node.children.isNotEmpty)
          ...node.children.map((child) =>
            StageMapNodeWidget(
              node: child,
              depth: depth + 1,
              isExpanded: _isNodeExpanded(child.id),
              onToggle: () => _toggleNode(child.id),
            ),
          ),
      ],
    );
  }
}

/// Drop zone widget with drag target
class StageMapDropZone extends StatelessWidget {
  final StageMapZone zone;
  final void Function(String audioPath)? onAudioDropped;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _isValidAudioPath(details.data),
      onAcceptWithDetails: (details) {
        onAudioDropped?.call(details.data);

        // Auto-update EventBuilderContext
        context.read<EventBuilderContext>().setZone(zone);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return DropZoneIndicator(
          state: isHovered
            ? DropZoneState.hovered
            : zone.isPopulated
              ? (zone.variantCount > 1 ? DropZoneState.hasVariants : DropZoneState.populated)
              : DropZoneState.empty,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(_getIconForInteraction(zone.interactionTypes.first), size: 14),
                SizedBox(width: 4),
                Text(zone.interactionTypes.first, style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Generates Stage Map from GDD
class StageMapGenerator {
  StageMapNode generateFromGdd(GameDesignDocument gdd) {
    return StageMapNode(
      id: 'root',
      type: StageMapNodeType.root,
      label: gdd.name,
      children: [
        _buildGlobalZone(),
        _buildBaseGameStage(gdd),
        if (gdd.hasFreeSpins) _buildFreeSpinsStage(gdd),
        ..._buildFeatureStages(gdd.features),
        _buildOverlaysStage(gdd),
      ],
    );
  }

  StageMapNode _buildGlobalZone() {
    return StageMapNode(
      id: 'global',
      type: StageMapNodeType.globalZone,
      label: 'GLOBAL AUDIO LAYER',
      children: [
        _buildSystemZone('ui', 'Global UI', [
          _dropZone('hover', 'UI_HOVER'),
          _dropZone('error', 'UI_ERROR'),
          _dropZone('notification', 'UI_NOTIF'),
        ]),
        _buildSystemZone('ambience', 'Global Ambience', [
          _dropZone('room_loop', 'AMBIENT_ROOM'),
          _dropZone('environment', 'AMBIENT_ENV'),
        ]),
        _buildSystemZone('vo', 'Global VO', [
          _dropZone('narrator', 'VO_NARRATOR'),
          _dropZone('announcer', 'VO_ANNOUNCER'),
        ]),
      ],
    );
  }

  StageMapNode _buildBaseGameStage(GameDesignDocument gdd) {
    return StageMapNode(
      id: 'base',
      type: StageMapNodeType.stageBlock,
      label: 'BASE GAME',
      children: [
        _buildMusicZone('base'),
        _buildReelsZone(gdd.grid.columns),
        _buildSymbolsZone(gdd.symbolGroups),
        _buildWinsZone(gdd.math.winTiers),
        _buildUiZone(gdd.uiElements),
      ],
    );
  }

  StageMapNode _buildReelsZone(int reelCount) {
    return StageMapNode(
      id: 'reels',
      type: StageMapNodeType.systemZone,
      label: 'REELS SYSTEM',
      children: List.generate(reelCount, (i) => StageMapNode(
        id: 'reel_$i',
        type: StageMapNodeType.groupZone,
        label: 'Reel $i',
        children: [
          _dropZone('spin_start', 'REEL_${i}_SPIN_START', suggestedBus: 'SFX/Reels'),
          _dropZone('spin_loop', 'REEL_${i}_SPIN_LOOP', suggestedBus: 'SFX/Reels'),
          _dropZone('stop', 'REEL_${i}_STOP', suggestedBus: 'SFX/Reels', suggestedPreset: 'reel_stop'),
          _dropZone('anticipation', 'REEL_${i}_ANTICIPATION', suggestedBus: 'SFX/Reels'),
        ],
      )),
    );
  }

  StageMapNode _buildSymbolsZone(List<SymbolGroup> groups) {
    return StageMapNode(
      id: 'symbols',
      type: StageMapNodeType.systemZone,
      label: 'SYMBOLS',
      children: groups.map((group) => StageMapNode(
        id: group.id,
        type: StageMapNodeType.groupZone,
        label: group.displayName,
        children: group.symbols.map((symbol) => StageMapNode(
          id: symbol.id,
          type: StageMapNodeType.entityZone,
          label: symbol.name,
          children: [
            _dropZone('land', 'SYMBOL_${symbol.id}_LAND', suggestedBus: 'SFX/Symbols'),
            _dropZone('highlight', 'SYMBOL_${symbol.id}_HIGHLIGHT', suggestedBus: 'SFX/Symbols'),
            if (symbol.isSpecial) _dropZone('special', 'SYMBOL_${symbol.id}_SPECIAL', suggestedBus: 'SFX/Symbols'),
          ],
        )).toList(),
      )).toList(),
    );
  }
}
```

---

## 🎨 ULOGA 6: UX / UI Designer

### Šta koristi
- Vizuelni layout
- Drag-drop interakcije
- Color coding
- Panel organization

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Stage Map as Navigation** | Korisnik se gubi u flat tabovima | 🔴 P0 |
| **Visual Hierarchy** | Nema jasnu strukturu GLOBAL→BASE→... | 🔴 P0 |
| **Drag Feedback** | Loš feedback prilikom drag-a | 🟠 P1 |
| **Context Persistence** | Gubi se context pri promeni panela | 🟠 P1 |
| **Keyboard Accessibility** | Stage Map nema keyboard nav | 🟡 P2 |

### ULTRA MODIFIKACIJA — Visual Hierarchy & Navigation

**Princip:** Stage Map je PRIMARY NAVIGATION — sve ostalo je DETAIL VIEW.

```
USER MENTAL MODEL:
═══════════════════════════════════════════════════════════════════════════

1. LEFT PANEL = Stage Map (Navigation)
   - Vidim CEO audio graf igre
   - Kliknem na zonu → details desno
   - Drop-ujem audio → event se kreira

2. CENTER = Work Area (Detail)
   - Timeline za selektovanu zonu
   - Mock Slot za preview
   - Stage trace za context

3. RIGHT PANEL = Tools (Action)
   - Event Builder (ALWAYS VISIBLE)
   - Audio Browser (drag source)

═══════════════════════════════════════════════════════════════════════════
```

### Color Coding System

```dart
/// Stage Map color scheme
class StageMapColors {
  // Zone types
  static const global = Color(0xFF9E9E9E);     // Gray — always active
  static const baseGame = Color(0xFF4A9EFF);   // Blue — default context
  static const freeSpins = Color(0xFF40FF90);  // Green — bonus context
  static const feature = Color(0xFFFF9040);    // Orange — special context
  static const overlay = Color(0xFFFF4060);    // Red — takeover context

  // System types
  static const music = Color(0xFFAA66FF);      // Purple
  static const sfx = Color(0xFF66CCFF);        // Cyan
  static const vo = Color(0xFFFFCC66);         // Gold
  static const amb = Color(0xFF66FF99);        // Mint

  // Drop zone states
  static const empty = Color(0x33FFFFFF);      // Transparent white
  static const hovered = Color(0xFF4A9EFF);    // Blue glow
  static const populated = Color(0xFF40FF90);  // Green check
  static const hasVariants = Color(0xFFFF9040); // Orange badge
}
```

### Drag & Drop Visual Language

```dart
/// Consistent drag feedback across all drop zones
class DragFeedbackWidget extends StatelessWidget {
  final String audioPath;
  final bool isValidTarget;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: isValidTarget
        ? FluxForgeTheme.accentBlue.withOpacity(0.9)
        : Colors.red.withOpacity(0.7),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isValidTarget ? Icons.add_circle : Icons.block,
              color: Colors.white,
              size: 16,
            ),
            SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 200),
              child: Text(
                audioPath.split('/').last,
                style: TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 🧪 ULOGA 7: QA / Determinism Engineer

### Šta koristi
- Event tracing
- Profiler panel
- Regression tests
- Deterministic playback

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Stage Coverage Report** | Ne zna koje zone nemaju audio | 🔴 P0 |
| **Event Trigger Log** | Nema hronološki log triggera | 🟠 P1 |
| **Comparison Mode** | Teško uporediti dva profila | 🟡 P2 |

### ULTRA MODIFIKACIJA — Coverage Report per Stage Zone

```dart
/// Stage Map coverage overlay
class StageCoverageOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<CoverageMetrics>(
      builder: (ctx, coverage, _) {
        return Stack(
          children: [
            // Coverage badges on Stage Map
            for (final zone in coverage.allZones)
              _CoverageBadge(
                zone: zone,
                status: coverage.statusForZone(zone.id),
                // ✅ populated, ⚠️ partial, ❌ missing
              ),

            // Summary panel
            Positioned(
              bottom: 8, left: 8,
              child: _CoverageSummaryPanel(
                totalZones: coverage.totalZones,
                populatedZones: coverage.populatedZones,
                percentComplete: coverage.percentComplete,
              ),
            ),
          ],
        );
      },
    );
  }
}

enum ZoneCoverageStatus {
  populated,    // Has event assigned
  partial,      // Some interactions missing
  missing,      // No audio at all
  notRequired,  // Optional zone
}
```

---

## 🧬 ULOGA 8: DSP / Audio Processing Engineer

### Šta koristi
- Bus hierarchy
- DSP chain
- RTPC curves
- Voice pool
- Profiler

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Per-Zone DSP Preview** | Mora ići u Bus panel da čuje effects | 🟠 P1 |
| **RTPC Visualization on Stage Map** | Ne vidi koje zone imaju RTPC | 🟡 P2 |
| **Loudness per Zone** | Nema loudness stats po zonama | 🟡 P2 |

### ULTRA MODIFIKACIJA — DSP Info on Stage Map

```dart
/// Zone DSP info badge (pokazuje na Stage Map)
class ZoneDspBadge extends StatelessWidget {
  final StageMapZone zone;

  @override
  Widget build(BuildContext context) {
    final dspInfo = context.read<DspRegistry>().getZoneInfo(zone.id);

    return Tooltip(
      message: '''
Bus: ${dspInfo.bus}
Chain: ${dspInfo.dspChain.map((d) => d.name).join(' → ')}
LUFS: ${dspInfo.integratedLufs.toStringAsFixed(1)}
RTPC: ${dspInfo.rtpcBindings.isNotEmpty ? 'Yes' : 'No'}
''',
      child: Container(
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(Icons.tune, size: 10, color: Colors.purple),
      ),
    );
  }
}
```

---

## 🧭 ULOGA 9: Producer / Product Owner

### Šta koristi
- Feature completeness overview
- Timeline for milestones
- Export capabilities

### Šta nedostaje

| Gap | Impact | Priority |
|-----|--------|----------|
| **Audio Coverage Dashboard** | Ne zna % completeness | 🔴 P0 |
| **Stage Map as Spec** | Ne može exportovati Stage Map kao dokument | 🟠 P1 |
| **Progress Tracking** | Nema % po fazama (Base, FS, Features) | 🟡 P2 |

### ULTRA MODIFIKACIJA — Coverage Dashboard

```dart
/// Producer dashboard widget
class AudioCoverageDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<CoverageMetrics>(
      builder: (ctx, coverage, _) {
        return Column(
          children: [
            // Overall progress
            _ProgressCircle(
              percent: coverage.overallPercent,
              label: 'Audio Coverage',
            ),

            SizedBox(height: 16),

            // Per-stage breakdown
            _CoverageBreakdown(
              items: [
                ('GLOBAL', coverage.globalPercent),
                ('BASE GAME', coverage.baseGamePercent),
                ('FREE SPINS', coverage.freeSpinsPercent),
                ('FEATURES', coverage.featuresPercent),
                ('OVERLAYS', coverage.overlaysPercent),
              ],
            ),

            SizedBox(height: 16),

            // Export button
            ElevatedButton.icon(
              icon: Icon(Icons.download),
              label: Text('Export Coverage Report'),
              onPressed: () => _exportCoverageReport(coverage),
            ),
          ],
        );
      },
    );
  }
}
```

---

## 10. MOCK SLOT ULTRA MODIFIKACIJE

### Trenutno stanje

Mock Slot (`_buildMockSlot()`) prikazuje reel grid sa simbolima, ali:
- Nema semantičke drop zone
- Nema visual feedback za hovered zone
- Ne koristi Stage Map kontekst

### ULTIMATIVNO REŠENJE — DroppableSlotPreview++

```dart
/// Ultra-enhanced droppable slot preview
class UltraDroppableSlotPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer2<GddProvider, EventBuilderContext>(
      builder: (ctx, gdd, builderCtx, _) {
        return Stack(
          children: [
            // Base slot visualization
            _SlotVisualization(gdd: gdd.current),

            // ═══════════════════════════════════════════════════════════════
            // OVERLAY: DROP ZONES (per element)
            // ═══════════════════════════════════════════════════════════════

            // Reels drop zones
            Positioned.fill(
              child: Row(
                children: List.generate(gdd.current.grid.columns, (reelIndex) {
                  return Expanded(
                    child: _ReelDropColumn(
                      reelIndex: reelIndex,
                      zones: [
                        StageMapZones.reelSpinStart(reelIndex),
                        StageMapZones.reelSpinLoop(reelIndex),
                        StageMapZones.reelStop(reelIndex),
                        StageMapZones.reelAnticipation(reelIndex),
                      ],
                      onZoneHovered: (zone) => builderCtx.previewZone(zone),
                      onAudioDropped: (zone, path) => builderCtx.addLayerForZone(zone, path),
                    ),
                  );
                }),
              ),
            ),

            // Symbol positions (show on hover)
            if (builderCtx.showSymbolZones)
              Positioned.fill(
                child: _SymbolDropGrid(
                  symbols: gdd.current.symbols,
                  onSymbolZoneHovered: (symbolId) => builderCtx.previewSymbolZone(symbolId),
                  onAudioDropped: (symbolId, path) => builderCtx.addLayerForSymbol(symbolId, path),
                ),
              ),

            // UI elements drop zones
            _UiDropZones(
              elements: ['spin_button', 'bet_up', 'bet_down', 'turbo', 'auto'],
              builderContext: builderCtx,
            ),

            // Win overlay zones
            _WinOverlayZones(
              tiers: gdd.current.math.winTiers,
              builderContext: builderCtx,
            ),

            // ═══════════════════════════════════════════════════════════════
            // CONTEXT INDICATOR (shows where audio will bind)
            // ═══════════════════════════════════════════════════════════════
            if (builderCtx.currentZone != null)
              Positioned(
                bottom: 8, left: 8, right: 8,
                child: _ZoneContextBar(
                  zone: builderCtx.currentZone!,
                  suggestedBus: builderCtx.suggestedBus,
                  suggestedPreset: builderCtx.suggestedPreset,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Reel column with multiple drop zones
class _ReelDropColumn extends StatefulWidget {
  final int reelIndex;
  final List<StageMapZone> zones;
  final void Function(StageMapZone)? onZoneHovered;
  final void Function(StageMapZone, String)? onAudioDropped;

  @override
  State<_ReelDropColumn> createState() => _ReelDropColumnState();
}

class _ReelDropColumnState extends State<_ReelDropColumn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: Border.all(
            color: _isHovered
              ? FluxForgeTheme.accentBlue.withOpacity(0.5)
              : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Reel content (symbols)
            _ReelSymbols(reelIndex: widget.reelIndex),

            // Drop zones (appear on hover)
            if (_isHovered)
              Positioned.fill(
                child: Column(
                  children: widget.zones.map((zone) {
                    return Expanded(
                      child: _MiniDropZone(
                        zone: zone,
                        label: zone.interactionTypes.first,
                        onHovered: () => widget.onZoneHovered?.call(zone),
                        onDropped: (path) => widget.onAudioDropped?.call(zone, path),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mini drop zone within slot preview
class _MiniDropZone extends StatelessWidget {
  final StageMapZone zone;
  final String label;
  final VoidCallback? onHovered;
  final void Function(String)? onDropped;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDropped?.call(details.data),
      builder: (context, candidateData, _) {
        final isHovered = candidateData.isNotEmpty;

        return MouseRegion(
          onEnter: (_) => onHovered?.call(),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 100),
            margin: EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isHovered
                ? FluxForgeTheme.accentBlue.withOpacity(0.3)
                : Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHovered
                  ? FluxForgeTheme.accentBlue
                  : zone.isPopulated
                    ? FluxForgeTheme.accentGreen
                    : Colors.white24,
                width: isHovered ? 2 : 1,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (zone.isPopulated)
                    Icon(Icons.check, size: 10, color: FluxForgeTheme.accentGreen),
                  SizedBox(width: 4),
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
```

---

## 11. IMPLEMENTATION ROADMAP

### Phase 1: Stage Map Foundation (3 days)

| Task | Est | Priority |
|------|-----|----------|
| StageMapNode data model | 0.5d | P0 |
| StageMapGenerator from GDD | 1d | P0 |
| StageMapWidget base | 1d | P0 |
| Integration with slot_lab_screen.dart | 0.5d | P0 |

### Phase 2: Drop Zone System (2 days)

| Task | Est | Priority |
|------|-----|----------|
| StageMapZone model | 0.5d | P0 |
| DropZoneIndicator widget | 0.5d | P0 |
| Drag-drop integration | 1d | P0 |

### Phase 3: Persistent Event Builder (2 days)

| Task | Est | Priority |
|------|-----|----------|
| EventBuilderContext provider | 0.5d | P0 |
| PersistentEventBuilder widget | 1d | P0 |
| Integration with Stage Map | 0.5d | P0 |

### Phase 4: Ultra Slot Mockup (2 days)

| Task | Est | Priority |
|------|-----|----------|
| UltraDroppableSlotPreview | 1d | P1 |
| _ReelDropColumn zones | 0.5d | P1 |
| _SymbolDropGrid zones | 0.5d | P1 |

### Phase 5: Coverage & Analytics (1 day)

| Task | Est | Priority |
|------|-----|----------|
| CoverageMetrics provider | 0.5d | P2 |
| StageCoverageOverlay | 0.5d | P2 |

### Phase 6: Polish (1 day)

| Task | Est | Priority |
|------|-----|----------|
| Keyboard navigation | 0.5d | P2 |
| Animation polish | 0.5d | P2 |

**Total:** ~11 days

---

## 12. FILE CHANGES SUMMARY

### New Files

| File | Description | LOC Est |
|------|-------------|---------|
| `lib/widgets/stage_map/stage_map_widget.dart` | Main Stage Map widget | ~600 |
| `lib/widgets/stage_map/stage_map_node.dart` | Node widget | ~300 |
| `lib/widgets/stage_map/drop_zone_indicator.dart` | Drop zone visual | ~150 |
| `lib/widgets/stage_map/stage_map_generator.dart` | GDD → Stage Map | ~400 |
| `lib/models/stage_map_models.dart` | Data models | ~200 |
| `lib/providers/event_builder_context.dart` | Builder context | ~250 |
| `lib/widgets/slot_lab/persistent_event_builder.dart` | Always-visible builder | ~400 |
| `lib/widgets/slot_lab/ultra_droppable_preview.dart` | Enhanced slot mockup | ~500 |
| `lib/widgets/slot_lab/coverage_overlay.dart` | Coverage visualization | ~250 |

**Total new:** ~3,050 LOC

### Modified Files

| File | Changes | Impact |
|------|---------|--------|
| `slot_lab_screen.dart` | Replace left panel, integrate Stage Map | HIGH |
| `gdd_import_service.dart` | Add symbol groups support | MEDIUM |
| `gdd_import_wizard.dart` | Generate Stage Map on import | MEDIUM |
| `middleware_provider.dart` | Add zone→event mapping | LOW |

---

*Document created: 2026-01-23*
*Analysis: Claude Opus 4.5*
*Principle: UVEK ULTIMATIVNO NAJBOLJE REŠENJE, NIKAD JEDNOSTAVNO*
