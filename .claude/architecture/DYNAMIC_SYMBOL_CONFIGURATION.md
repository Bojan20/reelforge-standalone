# Dynamic Symbol Configuration System — Specification

**Version:** 1.0.0
**Created:** 2026-01-25
**Author:** Claude Code (Principal Engineer)
**Status:** SPECIFICATION — Implementation Pending

---

## 1. EXECUTIVE SUMMARY

### Problem

Trenutni SlotLab mockup ima **hardcoded simbole**:
- Special: Wild, Scatter, Bonus, Symbol Glow (fiksno 4)
- High Pay: HP1, HP2, HP3, HP4 (fiksno 4)
- Medium Pay: MP1, MP2 (fiksno 2)
- Low Pay: LP1, LP2, LP3, LP4 (fiksno 4)

Ovo ne odgovara stvarnim igrama koje mogu imati:
- 3 HP simbola umesto 4
- 0 MP simbola (direktno HP → LP)
- Custom simbole: MYSTERY, EXPANDING, STICKY, MULTIPLIER
- Različite konfiguracije po igri

### Rešenje

**Data-driven symbol system** gde korisnik konfiguriše simbole, a UI se automatski prilagođava:

```
SlotLabProjectProvider.symbols (List<SymbolDefinition>)
        ↓
DroppableSlotPreview čita iz providera
        ↓
Grupiše po SymbolType
        ↓
Auto-generiše Drop Zone chips
        ↓
Stage mapping: SYMBOL_LAND_{ID}, WIN_SYMBOL_HIGHLIGHT_{ID}
```

---

## 2. DATA MODELS

### 2.1 SymbolDefinition (Existing — Enhanced)

**Lokacija:** `flutter_ui/lib/models/slot_lab_models.dart`

```dart
/// Tip simbola — određuje grupu u UI-u i default preset
enum SymbolType {
  wild,      // Special — zlatna boja, highest priority
  scatter,   // Special — ljubičasta, trigger features
  bonus,     // Special — narandžasta, bonus games
  highPay,   // HP grupa — crvena/narandžasta
  mediumPay, // MP grupa — plava
  lowPay,    // LP grupa — zelena/siva
  custom,    // Custom — korisnički definisana boja
}

/// Konteksti u kojima simbol proizvodi audio
enum SymbolAudioContext {
  land,      // Kada simbol sleti na reel (SYMBOL_LAND_{id})
  win,       // Kada je deo pobedničke kombinacije (WIN_SYMBOL_HIGHLIGHT_{id})
  expand,    // Kada se širi (SYMBOL_EXPAND_{id})
  lock,      // Kada se zaključa (Hold & Win) (SYMBOL_LOCK_{id})
  transform, // Kada se transformiše (SYMBOL_TRANSFORM_{id})
  collect,   // Kada se skuplja (SYMBOL_COLLECT_{id})
}

/// Definicija jednog simbola
class SymbolDefinition {
  final String id;           // Unique ID: 'hp1', 'wild', 'mystery'
  final String name;         // Display name: 'High Pay 1', 'Wild', 'Mystery'
  final String emoji;        // Emoji za vizualni prikaz: '🃏', '⭐', '❓'
  final SymbolType type;     // Tip simbola
  final Set<SymbolAudioContext> audioContexts;  // Koji audio eventi postoje
  final Color? customColor;  // Opciona custom boja (za type=custom)
  final int sortOrder;       // Redosled unutar grupe (0, 1, 2...)
  final Map<String, dynamic>? metadata;  // Extra podaci (multiplier value, etc.)

  // Computed properties
  String get stageIdLand => 'SYMBOL_LAND_${id.toUpperCase()}';
  String get stageIdWin => 'WIN_SYMBOL_HIGHLIGHT_${id.toUpperCase()}';
  String get stageIdExpand => 'SYMBOL_EXPAND_${id.toUpperCase()}';
  String get stageIdLock => 'SYMBOL_LOCK_${id.toUpperCase()}';
  String get stageIdTransform => 'SYMBOL_TRANSFORM_${id.toUpperCase()}';
  String get stageIdCollect => 'SYMBOL_COLLECT_${id.toUpperCase()}';

  String get dropTargetIdLand => 'symbol.${id.toLowerCase()}';
  String get dropTargetIdWin => 'symbol.win.${id.toLowerCase()}';

  // JSON serialization
  Map<String, dynamic> toJson();
  factory SymbolDefinition.fromJson(Map<String, dynamic> json);

  // Copy with
  SymbolDefinition copyWith({...});
}
```

### 2.2 SymbolPreset — Quick Setup Templates

```dart
/// Preset konfiguracije za brzo podešavanje
class SymbolPreset {
  final String id;
  final String name;
  final String description;
  final List<SymbolDefinition> symbols;

  // Built-in presets
  static SymbolPreset get standard5x3 => SymbolPreset(
    id: 'standard_5x3',
    name: 'Standard 5×3 Slot',
    description: '1 Wild, 1 Scatter, 4 HP, 2 MP, 4 LP',
    symbols: [
      SymbolDefinition(id: 'wild', name: 'Wild', emoji: '⭐', type: SymbolType.wild, ...),
      SymbolDefinition(id: 'scatter', name: 'Scatter', emoji: '💎', type: SymbolType.scatter, ...),
      SymbolDefinition(id: 'hp1', name: 'High Pay 1', emoji: '👑', type: SymbolType.highPay, ...),
      SymbolDefinition(id: 'hp2', name: 'High Pay 2', emoji: '💰', type: SymbolType.highPay, ...),
      SymbolDefinition(id: 'hp3', name: 'High Pay 3', emoji: '💎', type: SymbolType.highPay, ...),
      SymbolDefinition(id: 'hp4', name: 'High Pay 4', emoji: '🎰', type: SymbolType.highPay, ...),
      SymbolDefinition(id: 'mp1', name: 'Medium Pay 1', emoji: '🔷', type: SymbolType.mediumPay, ...),
      SymbolDefinition(id: 'mp2', name: 'Medium Pay 2', emoji: '🔶', type: SymbolType.mediumPay, ...),
      SymbolDefinition(id: 'lp1', name: 'Low Pay 1', emoji: 'A', type: SymbolType.lowPay, ...),
      SymbolDefinition(id: 'lp2', name: 'Low Pay 2', emoji: 'K', type: SymbolType.lowPay, ...),
      SymbolDefinition(id: 'lp3', name: 'Low Pay 3', emoji: 'Q', type: SymbolType.lowPay, ...),
      SymbolDefinition(id: 'lp4', name: 'Low Pay 4', emoji: 'J', type: SymbolType.lowPay, ...),
    ],
  );

  static SymbolPreset get megaways => SymbolPreset(
    id: 'megaways',
    name: 'Megaways Style',
    description: '1 Wild, 1 Scatter, 1 Mystery, 6 HP, 0 MP, 6 LP (cards)',
    symbols: [...],
  );

  static SymbolPreset get holdAndWin => SymbolPreset(
    id: 'hold_and_win',
    name: 'Hold & Win',
    description: '1 Wild, 3 Coins (Mini/Minor/Major), 1 Grand, 4 HP, 4 LP',
    symbols: [...],
  );

  static SymbolPreset get cascading => SymbolPreset(
    id: 'cascading',
    name: 'Cascading/Cluster',
    description: '1 Wild, 1 Scatter, 8 Gems (no HP/MP/LP tiers)',
    symbols: [...],
  );

  static List<SymbolPreset> get allPresets => [standard5x3, megaways, holdAndWin, cascading];
}
```

### 2.3 SymbolGroup — UI Grouping

```dart
/// Grupa simbola za prikaz u UI-u
class SymbolGroup {
  final SymbolType type;
  final String label;
  final Color color;
  final IconData icon;
  final List<SymbolDefinition> symbols;
  final bool isCollapsible;
  final bool isExpanded;

  // Factory za grupisanje iz liste simbola
  static List<SymbolGroup> groupSymbols(List<SymbolDefinition> symbols) {
    final groups = <SymbolGroup>[];

    // Special (wild, scatter, bonus, custom with isSpecial)
    final special = symbols.where((s) =>
      s.type == SymbolType.wild ||
      s.type == SymbolType.scatter ||
      s.type == SymbolType.bonus
    ).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (special.isNotEmpty) {
      groups.add(SymbolGroup(
        type: SymbolType.wild, // Representative type
        label: 'Special',
        color: const Color(0xFFFFD700),
        icon: Icons.star,
        symbols: special,
        isCollapsible: true,
        isExpanded: true,
      ));
    }

    // High Pay
    final hp = symbols.where((s) => s.type == SymbolType.highPay)
        .toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (hp.isNotEmpty) {
      groups.add(SymbolGroup(
        type: SymbolType.highPay,
        label: 'High Pay',
        color: const Color(0xFFFF6B6B),
        icon: Icons.workspace_premium,
        symbols: hp,
        isCollapsible: true,
        isExpanded: true,
      ));
    }

    // Medium Pay
    final mp = symbols.where((s) => s.type == SymbolType.mediumPay)
        .toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (mp.isNotEmpty) {
      groups.add(SymbolGroup(
        type: SymbolType.mediumPay,
        label: 'Medium Pay',
        color: const Color(0xFF4ECDC4),
        icon: Icons.diamond,
        symbols: mp,
        isCollapsible: true,
        isExpanded: true,
      ));
    }

    // Low Pay
    final lp = symbols.where((s) => s.type == SymbolType.lowPay)
        .toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (lp.isNotEmpty) {
      groups.add(SymbolGroup(
        type: SymbolType.lowPay,
        label: 'Low Pay',
        color: const Color(0xFF95A5A6),
        icon: Icons.casino,
        symbols: lp,
        isCollapsible: true,
        isExpanded: false, // Collapsed by default
      ));
    }

    // Custom
    final custom = symbols.where((s) => s.type == SymbolType.custom)
        .toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (custom.isNotEmpty) {
      groups.add(SymbolGroup(
        type: SymbolType.custom,
        label: 'Custom',
        color: const Color(0xFF9B59B6),
        icon: Icons.extension,
        symbols: custom,
        isCollapsible: true,
        isExpanded: true,
      ));
    }

    return groups;
  }
}
```

---

## 3. PROVIDER INTEGRATION

### 3.1 SlotLabProjectProvider (Enhanced)

**Lokacija:** `flutter_ui/lib/providers/slot_lab_project_provider.dart`

```dart
class SlotLabProjectProvider extends ChangeNotifier {
  // Existing fields...

  // === SYMBOL MANAGEMENT ===

  List<SymbolDefinition> _symbols = [];
  List<SymbolDefinition> get symbols => List.unmodifiable(_symbols);

  // Grouped for UI
  List<SymbolGroup> get symbolGroups => SymbolGroup.groupSymbols(_symbols);

  // Quick access by type
  List<SymbolDefinition> getSymbolsByType(SymbolType type) =>
      _symbols.where((s) => s.type == type).toList();

  // Get symbol by ID
  SymbolDefinition? getSymbol(String id) =>
      _symbols.firstWhereOrNull((s) => s.id == id);

  // === CRUD OPERATIONS ===

  /// Add new symbol
  void addSymbol(SymbolDefinition symbol) {
    // Validate unique ID
    if (_symbols.any((s) => s.id == symbol.id)) {
      throw ArgumentError('Symbol with ID "${symbol.id}" already exists');
    }
    _symbols.add(symbol);
    _sortSymbols();
    notifyListeners();
  }

  /// Remove symbol by ID
  void removeSymbol(String id) {
    _symbols.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  /// Update symbol
  void updateSymbol(String id, SymbolDefinition updated) {
    final index = _symbols.indexWhere((s) => s.id == id);
    if (index != -1) {
      _symbols[index] = updated;
      _sortSymbols();
      notifyListeners();
    }
  }

  /// Reorder symbol within its group
  void reorderSymbol(String id, int newSortOrder) {
    final symbol = getSymbol(id);
    if (symbol != null) {
      updateSymbol(id, symbol.copyWith(sortOrder: newSortOrder));
    }
  }

  /// Load preset
  void loadPreset(SymbolPreset preset) {
    _symbols = List.from(preset.symbols);
    _sortSymbols();
    notifyListeners();
  }

  /// Clear all symbols
  void clearSymbols() {
    _symbols.clear();
    notifyListeners();
  }

  // === HELPERS ===

  void _sortSymbols() {
    _symbols.sort((a, b) {
      // First by type priority
      final typePriority = _typeOrder(a.type).compareTo(_typeOrder(b.type));
      if (typePriority != 0) return typePriority;
      // Then by sort order within type
      return a.sortOrder.compareTo(b.sortOrder);
    });
  }

  int _typeOrder(SymbolType type) => switch (type) {
    SymbolType.wild => 0,
    SymbolType.scatter => 1,
    SymbolType.bonus => 2,
    SymbolType.highPay => 3,
    SymbolType.mediumPay => 4,
    SymbolType.lowPay => 5,
    SymbolType.custom => 6,
  };

  /// Generate next available ID for type
  String generateSymbolId(SymbolType type) {
    final prefix = switch (type) {
      SymbolType.wild => 'wild',
      SymbolType.scatter => 'scatter',
      SymbolType.bonus => 'bonus',
      SymbolType.highPay => 'hp',
      SymbolType.mediumPay => 'mp',
      SymbolType.lowPay => 'lp',
      SymbolType.custom => 'custom',
    };

    // For single-instance types
    if (type == SymbolType.wild || type == SymbolType.scatter || type == SymbolType.bonus) {
      if (!_symbols.any((s) => s.type == type)) {
        return prefix;
      }
      // If exists, add number
      int i = 2;
      while (_symbols.any((s) => s.id == '$prefix$i')) i++;
      return '$prefix$i';
    }

    // For multi-instance types (hp1, hp2, hp3...)
    int i = 1;
    while (_symbols.any((s) => s.id == '$prefix$i')) i++;
    return '$prefix$i';
  }

  /// Get all stages for configured symbols
  Set<String> getAllSymbolStages() {
    final stages = <String>{};
    for (final symbol in _symbols) {
      for (final context in symbol.audioContexts) {
        stages.add(switch (context) {
          SymbolAudioContext.land => symbol.stageIdLand,
          SymbolAudioContext.win => symbol.stageIdWin,
          SymbolAudioContext.expand => symbol.stageIdExpand,
          SymbolAudioContext.lock => symbol.stageIdLock,
          SymbolAudioContext.transform => symbol.stageIdTransform,
          SymbolAudioContext.collect => symbol.stageIdCollect,
        });
      }
    }
    return stages;
  }
}
```

---

## 4. UI COMPONENTS

### 4.1 DroppableSlotPreview (Refactored)

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/auto_event_builder/droppable_slot_preview.dart`

**Promene:**

```dart
// BEFORE (hardcoded):
Widget _buildSymbolStrip() {
  return Column(
    children: [
      _buildCollapsibleSection(
        'Special',
        _specialExpanded,
        () => setState(() => _specialExpanded = !_specialExpanded),
        child: Wrap(
          children: [
            _buildSymbolChip('Wild', 'wild', Icons.star, Color(0xFFFFD700)),
            _buildSymbolChip('Scatter', 'scatter', ...),
            // ... hardcoded
          ],
        ),
      ),
      // ... more hardcoded sections
    ],
  );
}

// AFTER (dynamic):
Widget _buildSymbolStrip() {
  return Consumer<SlotLabProjectProvider>(
    builder: (context, provider, _) {
      final groups = provider.symbolGroups;

      if (groups.isEmpty) {
        return _buildEmptySymbolsPlaceholder();
      }

      return Column(
        children: [
          // Header with Add button
          _buildSymbolStripHeader(),

          // Dynamic groups
          for (final group in groups)
            _buildDynamicSymbolGroup(group),

          // Symbol Glow (generic) — always present
          _buildSymbolGlowChip(),

          // Win Lines section (unchanged)
          _buildWinLinesSection(),
        ],
      );
    },
  );
}

Widget _buildDynamicSymbolGroup(SymbolGroup group) {
  return _buildCollapsibleSection(
    group.label,
    group.isExpanded,
    onToggle: () => _toggleGroupExpanded(group.type),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final symbol in group.symbols)
          _buildDynamicSymbolChip(symbol),
      ],
    ),
  );
}

Widget _buildDynamicSymbolChip(SymbolDefinition symbol) {
  final color = _getSymbolColor(symbol);
  final icon = _getSymbolIcon(symbol);

  return DropTargetWrapper(
    target: SlotDropZones.symbolZone(symbol.id),
    showBadge: false,
    onEventCreated: widget.onSymbolEventCreated != null
        ? (e) => widget.onSymbolEventCreated!(symbol.dropTargetIdLand, e)
        : null,
    child: Consumer<AutoEventBuilderProvider>(
      builder: (ctx, provider, _) {
        final count = provider.getEventCountForTarget(symbol.dropTargetIdLand);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
          decoration: BoxDecoration(
            color: count > 0 ? color.withOpacity(0.2) : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: count > 0 ? color.withOpacity(0.7) : FluxForgeTheme.borderSubtle,
              width: count > 0 ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji or Icon
              Text(symbol.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              // Name
              Text(
                symbol.name,
                style: TextStyle(
                  color: count > 0 ? color : FluxForgeTheme.textMuted,
                  fontSize: 12,
                  fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              // Count badge
              if (count > 0) ...[
                const SizedBox(width: 4),
                _buildCountBadge(count, color),
              ],
            ],
          ),
        );
      },
    ),
  );
}
```

### 4.2 AddSymbolDialog

**Nova komponenta:** `flutter_ui/lib/widgets/slot_lab/dialogs/add_symbol_dialog.dart`

```dart
class AddSymbolDialog extends StatefulWidget {
  final SymbolDefinition? editingSymbol; // null = add new, non-null = edit existing

  static Future<SymbolDefinition?> show(BuildContext context, {SymbolDefinition? editing}) {
    return showDialog<SymbolDefinition>(
      context: context,
      builder: (_) => AddSymbolDialog(editingSymbol: editing),
    );
  }
}

class _AddSymbolDialogState extends State<AddSymbolDialog> {
  late TextEditingController _nameController;
  late SymbolType _selectedType;
  late String _selectedEmoji;
  late Set<SymbolAudioContext> _selectedContexts;

  // Emoji picker options per type
  static const _emojiOptions = {
    SymbolType.wild: ['⭐', '🃏', '🌟', '✨', '💫', '🔮'],
    SymbolType.scatter: ['💎', '🎰', '💠', '🔷', '💜', '🎯'],
    SymbolType.bonus: ['🎁', '🎪', '🎲', '🎮', '🎯', '🏆'],
    SymbolType.highPay: ['👑', '💰', '💎', '🏆', '🎖️', '💵', '🔥', '❤️'],
    SymbolType.mediumPay: ['🔷', '🔶', '💜', '💚', '🧡', '💙'],
    SymbolType.lowPay: ['A', 'K', 'Q', 'J', '10', '9', '♠', '♥', '♦', '♣'],
    SymbolType.custom: ['❓', '🔒', '📦', '⚡', '🌀', '🎭', '💥', '🌈'],
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editingSymbol == null ? 'Add Symbol' : 'Edit Symbol'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Symbol Type Dropdown
            _buildTypeDropdown(),
            const SizedBox(height: 16),

            // Name Field
            _buildNameField(),
            const SizedBox(height: 16),

            // Emoji Picker
            _buildEmojiPicker(),
            const SizedBox(height: 16),

            // Audio Contexts Checkboxes
            _buildAudioContexts(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid ? _submit : null,
          child: Text(widget.editingSymbol == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<SymbolType>(
      value: _selectedType,
      decoration: const InputDecoration(
        labelText: 'Symbol Type',
        border: OutlineInputBorder(),
      ),
      items: SymbolType.values.map((type) => DropdownMenuItem(
        value: type,
        child: Row(
          children: [
            Icon(_iconForType(type), size: 18),
            const SizedBox(width: 8),
            Text(_labelForType(type)),
          ],
        ),
      )).toList(),
      onChanged: (type) {
        if (type != null) {
          setState(() {
            _selectedType = type;
            // Reset emoji to first option for new type
            _selectedEmoji = _emojiOptions[type]!.first;
            // Auto-generate name
            if (_nameController.text.isEmpty || _isAutoGeneratedName) {
              _nameController.text = _defaultNameForType(type);
            }
          });
        }
      },
    );
  }

  Widget _buildEmojiPicker() {
    final options = _emojiOptions[_selectedType] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icon/Emoji', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((emoji) => GestureDetector(
            onTap: () => setState(() => _selectedEmoji = emoji),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _selectedEmoji == emoji
                    ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                    : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedEmoji == emoji
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.borderSubtle,
                  width: _selectedEmoji == emoji ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildAudioContexts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Audio Events', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: SymbolAudioContext.values.map((context) => FilterChip(
            label: Text(_labelForContext(context)),
            selected: _selectedContexts.contains(context),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedContexts.add(context);
                } else {
                  _selectedContexts.remove(context);
                }
              });
            },
          )).toList(),
        ),
        const SizedBox(height: 8),
        // Preview of generated stages
        Text(
          'Stages: ${_previewStages()}',
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  String _previewStages() {
    final provider = context.read<SlotLabProjectProvider>();
    final id = widget.editingSymbol?.id ?? provider.generateSymbolId(_selectedType);
    return _selectedContexts.map((c) => switch (c) {
      SymbolAudioContext.land => 'SYMBOL_LAND_${id.toUpperCase()}',
      SymbolAudioContext.win => 'WIN_SYMBOL_HIGHLIGHT_${id.toUpperCase()}',
      SymbolAudioContext.expand => 'SYMBOL_EXPAND_${id.toUpperCase()}',
      SymbolAudioContext.lock => 'SYMBOL_LOCK_${id.toUpperCase()}',
      SymbolAudioContext.transform => 'SYMBOL_TRANSFORM_${id.toUpperCase()}',
      SymbolAudioContext.collect => 'SYMBOL_COLLECT_${id.toUpperCase()}',
    }).join(', ');
  }

  void _submit() {
    final provider = context.read<SlotLabProjectProvider>();
    final id = widget.editingSymbol?.id ?? provider.generateSymbolId(_selectedType);

    final symbol = SymbolDefinition(
      id: id,
      name: _nameController.text.trim(),
      emoji: _selectedEmoji,
      type: _selectedType,
      audioContexts: _selectedContexts,
      sortOrder: widget.editingSymbol?.sortOrder ??
          provider.getSymbolsByType(_selectedType).length,
    );

    Navigator.pop(context, symbol);
  }
}
```

### 4.3 SymbolStripHeader

```dart
Widget _buildSymbolStripHeader() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        const Icon(Icons.casino, size: 14, color: FluxForgeTheme.textMuted),
        const SizedBox(width: 6),
        const Text(
          'SYMBOLS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FluxForgeTheme.textMuted,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        // Preset dropdown
        PopupMenuButton<SymbolPreset>(
          tooltip: 'Load Preset',
          icon: const Icon(Icons.dashboard_customize, size: 16),
          onSelected: (preset) {
            context.read<SlotLabProjectProvider>().loadPreset(preset);
          },
          itemBuilder: (_) => SymbolPreset.allPresets.map((p) => PopupMenuItem(
            value: p,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(p.description, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          )).toList(),
        ),
        // Add button
        IconButton(
          tooltip: 'Add Symbol',
          icon: const Icon(Icons.add_circle_outline, size: 18),
          onPressed: () async {
            final symbol = await AddSymbolDialog.show(context);
            if (symbol != null) {
              context.read<SlotLabProjectProvider>().addSymbol(symbol);
            }
          },
        ),
      ],
    ),
  );
}
```

---

## 5. STAGE MAPPING

### 5.1 Dynamic Stage Resolution

**Lokacija:** `flutter_ui/lib/screens/slot_lab_screen.dart` — `_targetIdToStage()`

```dart
String _targetIdToStage(String targetId) {
  // ... existing mappings ...

  // === DYNAMIC SYMBOL STAGES ===

  // symbol.{id} → SYMBOL_LAND_{ID}
  if (targetId.startsWith('symbol.') && !targetId.startsWith('symbol.win')) {
    final symbolId = targetId.split('.').last.toUpperCase();
    return 'SYMBOL_LAND_$symbolId';
  }

  // symbol.win → WIN_SYMBOL_HIGHLIGHT (generic)
  if (targetId == 'symbol.win' || targetId == 'symbol.win.all') {
    return 'WIN_SYMBOL_HIGHLIGHT';
  }

  // symbol.win.{id} → WIN_SYMBOL_HIGHLIGHT_{ID}
  if (targetId.startsWith('symbol.win.')) {
    final symbolId = targetId.split('.').last.toUpperCase();
    return 'WIN_SYMBOL_HIGHLIGHT_$symbolId';
  }

  // symbol.expand.{id} → SYMBOL_EXPAND_{ID}
  if (targetId.startsWith('symbol.expand.')) {
    final symbolId = targetId.split('.').last.toUpperCase();
    return 'SYMBOL_EXPAND_$symbolId';
  }

  // symbol.lock.{id} → SYMBOL_LOCK_{ID}
  if (targetId.startsWith('symbol.lock.')) {
    final symbolId = targetId.split('.').last.toUpperCase();
    return 'SYMBOL_LOCK_$symbolId';
  }

  // ... rest of mappings ...
}
```

### 5.2 SlotDropZones Updates

**Lokacija:** `flutter_ui/lib/widgets/slot_lab/auto_event_builder/droppable_slot_preview.dart` — `SlotDropZones`

```dart
class SlotDropZones {
  // ... existing methods ...

  // Dynamic symbol zone (land)
  static DropTarget symbolZone(String symbolId) => DropTarget(
    targetId: 'symbol.$symbolId',
    targetType: TargetType.symbolZone,
    targetTags: ['symbol', symbolId],
    stageContext: StageContext.global,
    interactionSemantics: const ['land'],
  );

  // Dynamic symbol win highlight
  static DropTarget symbolWinHighlight(String symbolId) => DropTarget(
    targetId: 'symbol.win.$symbolId',
    targetType: TargetType.symbolZone,
    targetTags: ['symbol', 'win', symbolId],
    stageContext: StageContext.global,
    interactionSemantics: const ['glow', 'pulse', 'highlight'],
  );

  // Dynamic symbol expand
  static DropTarget symbolExpand(String symbolId) => DropTarget(
    targetId: 'symbol.expand.$symbolId',
    targetType: TargetType.symbolZone,
    targetTags: ['symbol', 'expand', symbolId],
    stageContext: StageContext.global,
    interactionSemantics: const ['expand'],
  );

  // Dynamic symbol lock (Hold & Win)
  static DropTarget symbolLock(String symbolId) => DropTarget(
    targetId: 'symbol.lock.$symbolId',
    targetType: TargetType.symbolZone,
    targetTags: ['symbol', 'lock', symbolId],
    stageContext: StageContext.global,
    interactionSemantics: const ['lock'],
  );
}
```

---

## 6. PERSISTENCE

### 6.1 Project Save/Load

Simboli se čuvaju kao deo `SlotLabProject`:

```dart
class SlotLabProject {
  // ... existing fields ...

  final List<SymbolDefinition> symbols;

  Map<String, dynamic> toJson() => {
    // ... existing ...
    'symbols': symbols.map((s) => s.toJson()).toList(),
  };

  factory SlotLabProject.fromJson(Map<String, dynamic> json) {
    return SlotLabProject(
      // ... existing ...
      symbols: (json['symbols'] as List?)
          ?.map((s) => SymbolDefinition.fromJson(s))
          .toList() ?? [],
    );
  }
}
```

### 6.2 GDD Import Integration

Kada se importuje GDD, automatski se generišu simboli:

```dart
// U GddImportService
List<SymbolDefinition> _generateSymbolsFromGdd(GameDesignDocument gdd) {
  final symbols = <SymbolDefinition>[];

  for (final gddSymbol in gdd.symbols) {
    final type = _inferSymbolType(gddSymbol);
    symbols.add(SymbolDefinition(
      id: gddSymbol.id.toLowerCase(),
      name: gddSymbol.name,
      emoji: _inferEmoji(gddSymbol),
      type: type,
      audioContexts: _inferAudioContexts(gddSymbol),
      sortOrder: symbols.where((s) => s.type == type).length,
    ));
  }

  return symbols;
}
```

---

## 7. IMPLEMENTATION PHASES

### Phase 1: Data Models (Est. ~200 LOC)
- [ ] Enhance `SymbolDefinition` in `slot_lab_models.dart`
- [ ] Add `SymbolAudioContext` enum
- [ ] Add `SymbolPreset` class
- [ ] Add `SymbolGroup` helper class

### Phase 2: Provider Integration (Est. ~300 LOC)
- [ ] Add symbol CRUD methods to `SlotLabProjectProvider`
- [ ] Add `generateSymbolId()` helper
- [ ] Add `getAllSymbolStages()` method
- [ ] Add preset loading

### Phase 3: UI — AddSymbolDialog (Est. ~400 LOC)
- [ ] Create `add_symbol_dialog.dart`
- [ ] Type dropdown
- [ ] Name field
- [ ] Emoji picker
- [ ] Audio contexts checkboxes
- [ ] Stage preview

### Phase 4: UI — DroppableSlotPreview Refactor (Est. ~300 LOC)
- [ ] Replace hardcoded sections with Consumer
- [ ] Create `_buildDynamicSymbolGroup()`
- [ ] Create `_buildDynamicSymbolChip()`
- [ ] Add header with preset dropdown + add button
- [ ] Keep Symbol Glow and Win Lines sections

### Phase 5: Stage Mapping (Est. ~100 LOC)
- [ ] Update `_targetIdToStage()` for dynamic symbols
- [ ] Add new `SlotDropZones` factory methods

### Phase 6: Persistence (Est. ~50 LOC)
- [ ] Update `SlotLabProject.toJson/fromJson`
- [ ] Test save/load cycle

### Phase 7: GDD Integration (Est. ~100 LOC)
- [ ] Update GDD import to generate symbols
- [ ] Map GDD symbol types to SymbolType enum

**Total Estimated:** ~1,450 LOC

---

## 8. TESTING CHECKLIST

### Functional Tests

- [ ] Add symbol via dialog
- [ ] Edit existing symbol
- [ ] Remove symbol
- [ ] Load preset (Standard, Megaways, Hold&Win)
- [ ] Drag audio to dynamic symbol chip
- [ ] Verify stage triggered matches `SYMBOL_LAND_{ID}`
- [ ] Verify win highlight stage `WIN_SYMBOL_HIGHLIGHT_{ID}`
- [ ] Save project with custom symbols
- [ ] Load project — symbols restored
- [ ] Import GDD — symbols auto-generated

### Edge Cases

- [ ] Empty symbols list — shows placeholder
- [ ] Duplicate ID prevention
- [ ] Max symbols per type (reasonable limit)
- [ ] Special characters in symbol name
- [ ] Very long symbol names — text truncation

---

## 9. MIGRATION NOTES

### Backwards Compatibility

Projekti pre V15 nemaju `symbols` field. Pri učitavanju:

```dart
factory SlotLabProject.fromJson(Map<String, dynamic> json) {
  // If no symbols field, load default preset
  final symbols = json['symbols'] != null
      ? (json['symbols'] as List).map((s) => SymbolDefinition.fromJson(s)).toList()
      : SymbolPreset.standard5x3.symbols;

  return SlotLabProject(
    symbols: symbols,
    // ...
  );
}
```

### Stage Compatibility

Postojeći eventi sa hardcoded stage-ovima (`SYMBOL_LAND_HP1`) i dalje rade jer se stage mapping ne menja — samo UI postaje dinamičan.

---

## 10. RELATED DOCUMENTATION

- [SLOTLAB_DROP_ZONE_SPEC.md](SLOTLAB_DROP_ZONE_SPEC.md) — Drop zone system
- [SLOT_LAB_AUDIO_FEATURES.md](SLOT_LAB_AUDIO_FEATURES.md) — Audio features
- [SLOT_LAB_SYSTEM.md](SLOT_LAB_SYSTEM.md) — Overall SlotLab architecture

---

**END OF SPECIFICATION**

*This document defines the Dynamic Symbol Configuration system. Implementation should follow this specification exactly.*
