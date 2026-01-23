/// Visual Reel Strip Editor
///
/// Drag-drop visual editor for configuring slot reel strips:
/// - Visual grid showing all reels and their symbol sequences
/// - Drag-drop symbol reordering within reels
/// - Add/remove symbols with context menu
/// - Symbol palette for quick assignment
/// - Strip statistics (symbol distribution, feature frequency)
/// - Import/export reel strip configurations
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Symbol type classification (mirrors Rust SymbolType)
enum SymbolType {
  regular,
  wild,
  scatter,
  bonus,
  jackpot,
  blank;

  Color get color => switch (this) {
        SymbolType.regular => const Color(0xFF4A9EFF),
        SymbolType.wild => const Color(0xFFFFD700),
        SymbolType.scatter => const Color(0xFF40FF90),
        SymbolType.bonus => const Color(0xFFFF40FF),
        SymbolType.jackpot => const Color(0xFFFF4040),
        SymbolType.blank => const Color(0xFF666666),
      };

  IconData get icon => switch (this) {
        SymbolType.regular => Icons.star,
        SymbolType.wild => Icons.flash_on,
        SymbolType.scatter => Icons.scatter_plot,
        SymbolType.bonus => Icons.card_giftcard,
        SymbolType.jackpot => Icons.emoji_events,
        SymbolType.blank => Icons.crop_square,
      };

  String get label => switch (this) {
        SymbolType.regular => 'Regular',
        SymbolType.wild => 'Wild',
        SymbolType.scatter => 'Scatter',
        SymbolType.bonus => 'Bonus',
        SymbolType.jackpot => 'Jackpot',
        SymbolType.blank => 'Blank',
      };
}

/// Symbol definition
class ReelSymbol {
  final int id;
  final String name;
  final SymbolType type;
  final int tier; // 0 = highest paying
  final List<double> payValues; // 3oak, 4oak, 5oak

  const ReelSymbol({
    required this.id,
    required this.name,
    required this.type,
    this.tier = 0,
    this.payValues = const [],
  });

  ReelSymbol copyWith({
    int? id,
    String? name,
    SymbolType? type,
    int? tier,
    List<double>? payValues,
  }) =>
      ReelSymbol(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        tier: tier ?? this.tier,
        payValues: payValues ?? this.payValues,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'tier': tier,
        'pay_values': payValues,
      };

  factory ReelSymbol.fromJson(Map<String, dynamic> json) => ReelSymbol(
        id: json['id'] as int,
        name: json['name'] as String,
        type: SymbolType.values.byName(json['type'] as String),
        tier: json['tier'] as int? ?? 0,
        payValues: (json['pay_values'] as List?)?.cast<double>() ?? [],
      );
}

/// Reel strip (sequence of symbol IDs)
class ReelStrip {
  final int reelIndex;
  final List<int> symbolIds;

  const ReelStrip({required this.reelIndex, required this.symbolIds});

  ReelStrip copyWith({int? reelIndex, List<int>? symbolIds}) => ReelStrip(
        reelIndex: reelIndex ?? this.reelIndex,
        symbolIds: symbolIds ?? List.from(this.symbolIds),
      );

  int get length => symbolIds.length;

  Map<String, dynamic> toJson() => {
        'reel_index': reelIndex,
        'symbols': symbolIds,
      };

  factory ReelStrip.fromJson(Map<String, dynamic> json) => ReelStrip(
        reelIndex: json['reel_index'] as int,
        symbolIds: (json['symbols'] as List).cast<int>(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEFAULT SYMBOL SET
// ═══════════════════════════════════════════════════════════════════════════════

/// Standard symbol set for classic 5-reel slots
List<ReelSymbol> get standardSymbolSet => const [
      // High paying
      ReelSymbol(
          id: 1,
          name: 'Seven',
          type: SymbolType.regular,
          tier: 0,
          payValues: [20, 100, 500]),
      ReelSymbol(
          id: 2,
          name: 'Bar3',
          type: SymbolType.regular,
          tier: 1,
          payValues: [15, 75, 300]),
      ReelSymbol(
          id: 3,
          name: 'Bar2',
          type: SymbolType.regular,
          tier: 2,
          payValues: [10, 50, 200]),
      ReelSymbol(
          id: 4,
          name: 'Bar1',
          type: SymbolType.regular,
          tier: 3,
          payValues: [8, 40, 150]),
      // Medium paying
      ReelSymbol(
          id: 5,
          name: 'Bell',
          type: SymbolType.regular,
          tier: 4,
          payValues: [5, 25, 100]),
      ReelSymbol(
          id: 6,
          name: 'Grape',
          type: SymbolType.regular,
          tier: 5,
          payValues: [4, 20, 80]),
      ReelSymbol(
          id: 7,
          name: 'Orange',
          type: SymbolType.regular,
          tier: 6,
          payValues: [3, 15, 60]),
      // Low paying
      ReelSymbol(
          id: 8,
          name: 'Plum',
          type: SymbolType.regular,
          tier: 7,
          payValues: [2, 10, 40]),
      ReelSymbol(
          id: 9,
          name: 'Cherry',
          type: SymbolType.regular,
          tier: 8,
          payValues: [1, 5, 20]),
      ReelSymbol(
          id: 10,
          name: 'Lemon',
          type: SymbolType.regular,
          tier: 9,
          payValues: [1, 5, 20]),
      // Special
      ReelSymbol(id: 11, name: 'Wild', type: SymbolType.wild, tier: 0),
      ReelSymbol(id: 12, name: 'Scatter', type: SymbolType.scatter, tier: 0),
      ReelSymbol(id: 13, name: 'Bonus', type: SymbolType.bonus, tier: 0),
    ];

// ═══════════════════════════════════════════════════════════════════════════════
// REEL STRIP EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

class ReelStripEditor extends StatefulWidget {
  /// Initial reel strips
  final List<ReelStrip>? initialStrips;

  /// Symbol definitions
  final List<ReelSymbol>? symbols;

  /// Number of reels (default 5)
  final int reelCount;

  /// Default strip length for new reels
  final int defaultStripLength;

  /// Callback when strips change
  final ValueChanged<List<ReelStrip>>? onStripsChanged;

  /// Callback when symbols change
  final ValueChanged<List<ReelSymbol>>? onSymbolsChanged;

  const ReelStripEditor({
    super.key,
    this.initialStrips,
    this.symbols,
    this.reelCount = 5,
    this.defaultStripLength = 32,
    this.onStripsChanged,
    this.onSymbolsChanged,
  });

  @override
  State<ReelStripEditor> createState() => _ReelStripEditorState();
}

class _ReelStripEditorState extends State<ReelStripEditor> {
  late List<ReelStrip> _strips;
  late List<ReelSymbol> _symbols;
  int _selectedReelIndex = 0;
  int? _hoveredPosition;
  int? _dragStartPosition;
  bool _showSymbolPalette = true;
  bool _showStatistics = true;

  // Scroll controllers for each reel
  final List<ScrollController> _scrollControllers = [];

  @override
  void initState() {
    super.initState();
    _symbols = widget.symbols ?? standardSymbolSet;
    _strips = widget.initialStrips ?? _generateDefaultStrips();

    // Create scroll controllers for each reel
    for (int i = 0; i < widget.reelCount; i++) {
      _scrollControllers.add(ScrollController());
    }
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<ReelStrip> _generateDefaultStrips() {
    final regularIds = _symbols
        .where((s) => s.type == SymbolType.regular)
        .map((s) => s.id)
        .toList();

    final wildId =
        _symbols.firstWhere((s) => s.type == SymbolType.wild).id;
    final scatterId =
        _symbols.firstWhere((s) => s.type == SymbolType.scatter).id;

    return List.generate(widget.reelCount, (reelIndex) {
      final symbols = <int>[];
      for (int i = 0; i < widget.defaultStripLength; i++) {
        if (i % 20 == 0 && reelIndex > 0) {
          symbols.add(wildId);
        } else if (i % 25 == 0) {
          symbols.add(scatterId);
        } else {
          symbols.add(regularIds[i % regularIds.length]);
        }
      }
      return ReelStrip(reelIndex: reelIndex, symbolIds: symbols);
    });
  }

  void _notifyChange() {
    widget.onStripsChanged?.call(_strips);
  }

  void _updateSymbolAt(int reelIndex, int position, int symbolId) {
    setState(() {
      final strip = _strips[reelIndex];
      final newSymbols = List<int>.from(strip.symbolIds);
      newSymbols[position] = symbolId;
      _strips[reelIndex] = strip.copyWith(symbolIds: newSymbols);
    });
    _notifyChange();
  }

  void _insertSymbolAt(int reelIndex, int position, int symbolId) {
    setState(() {
      final strip = _strips[reelIndex];
      final newSymbols = List<int>.from(strip.symbolIds);
      newSymbols.insert(position, symbolId);
      _strips[reelIndex] = strip.copyWith(symbolIds: newSymbols);
    });
    _notifyChange();
  }

  void _removeSymbolAt(int reelIndex, int position) {
    setState(() {
      final strip = _strips[reelIndex];
      if (strip.symbolIds.length > 1) {
        final newSymbols = List<int>.from(strip.symbolIds);
        newSymbols.removeAt(position);
        _strips[reelIndex] = strip.copyWith(symbolIds: newSymbols);
      }
    });
    _notifyChange();
  }

  void _moveSymbol(int reelIndex, int fromPosition, int toPosition) {
    if (fromPosition == toPosition) return;
    setState(() {
      final strip = _strips[reelIndex];
      final newSymbols = List<int>.from(strip.symbolIds);
      final symbol = newSymbols.removeAt(fromPosition);
      newSymbols.insert(toPosition, symbol);
      _strips[reelIndex] = strip.copyWith(symbolIds: newSymbols);
    });
    _notifyChange();
  }

  ReelSymbol? _getSymbol(int id) {
    return _symbols.where((s) => s.id == id).firstOrNull;
  }

  Map<int, int> _getSymbolDistribution(int reelIndex) {
    final distribution = <int, int>{};
    for (final symbolId in _strips[reelIndex].symbolIds) {
      distribution[symbolId] = (distribution[symbolId] ?? 0) + 1;
    }
    return distribution;
  }

  void _exportStrips() async {
    final json = jsonEncode({
      'symbols': _symbols.map((s) => s.toJson()).toList(),
      'strips': _strips.map((s) => s.toJson()).toList(),
    });
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reel strips copied to clipboard')),
      );
    }
  }

  void _importStrips() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;

    try {
      final json = jsonDecode(data!.text!) as Map<String, dynamic>;
      setState(() {
        if (json['symbols'] != null) {
          _symbols = (json['symbols'] as List)
              .map((s) => ReelSymbol.fromJson(s as Map<String, dynamic>))
              .toList();
          widget.onSymbolsChanged?.call(_symbols);
        }
        if (json['strips'] != null) {
          _strips = (json['strips'] as List)
              .map((s) => ReelStrip.fromJson(s as Map<String, dynamic>))
              .toList();
        }
      });
      _notifyChange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reel strips imported')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121216),
      child: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              children: [
                // Symbol palette (left)
                if (_showSymbolPalette) _buildSymbolPalette(),
                // Main reel editor (center)
                Expanded(child: _buildReelGrid()),
                // Statistics (right)
                if (_showStatistics) _buildStatisticsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.view_carousel, color: Color(0xFF4A9EFF), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Reel Strip Editor',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 16),
          // Reel selector
          ...List.generate(widget.reelCount, (i) {
            final isSelected = _selectedReelIndex == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => setState(() => _selectedReelIndex = i),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF4A9EFF).withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4A9EFF)
                          : Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    'R${i + 1}',
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF4A9EFF) : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Strip length
          Text(
            'Length: ${_strips[_selectedReelIndex].length}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 16),
          // Toggle buttons
          _buildToggleButton(
            'Palette',
            _showSymbolPalette,
            () => setState(() => _showSymbolPalette = !_showSymbolPalette),
          ),
          const SizedBox(width: 4),
          _buildToggleButton(
            'Stats',
            _showStatistics,
            () => setState(() => _showStatistics = !_showStatistics),
          ),
          const SizedBox(width: 8),
          // Import/Export
          IconButton(
            icon: const Icon(Icons.file_download, size: 16, color: Colors.white54),
            onPressed: _importStrips,
            tooltip: 'Import from clipboard',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload, size: 16, color: Colors.white54),
            onPressed: _exportStrips,
            tooltip: 'Export to clipboard',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4A9EFF).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF4A9EFF) : Colors.white54,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildSymbolPalette() {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Symbol Palette',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _symbols.length,
              itemBuilder: (context, index) {
                final symbol = _symbols[index];
                return Draggable<int>(
                  data: symbol.id,
                  feedback: _buildSymbolChip(symbol, isDragging: true),
                  childWhenDragging: Opacity(
                    opacity: 0.5,
                    child: _buildSymbolChip(symbol),
                  ),
                  child: _buildSymbolChip(symbol),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolChip(ReelSymbol symbol, {bool isDragging = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDragging
            ? symbol.type.color.withOpacity(0.3)
            : const Color(0xFF242430),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: symbol.type.color.withOpacity(isDragging ? 0.8 : 0.3),
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: symbol.type.color.withOpacity(0.3),
                  blurRadius: 8,
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(symbol.type.icon, color: symbol.type.color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              symbol.name,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '#${symbol.id}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReelGrid() {
    return Column(
      children: [
        // All reels overview (compact)
        Container(
          height: 60,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: List.generate(widget.reelCount, (reelIndex) {
              final strip = _strips[reelIndex];
              final isSelected = reelIndex == _selectedReelIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedReelIndex = reelIndex),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4A9EFF).withOpacity(0.1)
                          : const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4A9EFF)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Reel ${reelIndex + 1}',
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF4A9EFF)
                                : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${strip.length} symbols',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // Selected reel detail view
        Expanded(
          child: _buildReelDetailView(),
        ),
      ],
    );
  }

  Widget _buildReelDetailView() {
    final strip = _strips[_selectedReelIndex];
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Reel ${_selectedReelIndex + 1} Strip',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 16, color: Colors.white54),
                  onPressed: () => _insertSymbolAt(
                    _selectedReelIndex,
                    strip.length,
                    _symbols.first.id,
                  ),
                  tooltip: 'Add symbol',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          // Symbol grid
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _scrollControllers[_selectedReelIndex],
              padding: const EdgeInsets.all(8),
              itemCount: strip.symbolIds.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                _moveSymbol(_selectedReelIndex, oldIndex, newIndex);
              },
              itemBuilder: (context, position) {
                final symbolId = strip.symbolIds[position];
                final symbol = _getSymbol(symbolId);
                return _buildSymbolSlot(
                  key: ValueKey('$_selectedReelIndex-$position'),
                  position: position,
                  symbol: symbol,
                  symbolId: symbolId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolSlot({
    required Key key,
    required int position,
    required ReelSymbol? symbol,
    required int symbolId,
  }) {
    final isHovered = _hoveredPosition == position;

    return DragTarget<int>(
      key: key,
      onAcceptWithDetails: (details) {
        _updateSymbolAt(_selectedReelIndex, position, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredPosition = position),
          onExit: (_) => setState(() => _hoveredPosition = null),
          child: GestureDetector(
            onSecondaryTapDown: (details) {
              _showSymbolContextMenu(context, details.globalPosition, position);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDropTarget
                    ? const Color(0xFF4A9EFF).withOpacity(0.2)
                    : isHovered
                        ? const Color(0xFF242430)
                        : const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDropTarget
                      ? const Color(0xFF4A9EFF)
                      : (symbol?.type.color ?? Colors.grey).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  // Position number
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${position.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  // Symbol icon
                  Icon(
                    symbol?.type.icon ?? Icons.help_outline,
                    color: symbol?.type.color ?? Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  // Symbol name
                  Expanded(
                    child: Text(
                      symbol?.name ?? 'Unknown',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  // Symbol ID
                  Text(
                    '#$symbolId',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                    ),
                  ),
                  // Drag handle
                  const SizedBox(width: 8),
                  const Icon(Icons.drag_handle, color: Colors.white24, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSymbolContextMenu(
      BuildContext context, Offset position, int symbolPosition) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          child: const Row(
            children: [
              Icon(Icons.swap_horiz, size: 16),
              SizedBox(width: 8),
              Text('Change Symbol'),
            ],
          ),
          onTap: () => _showSymbolPicker(symbolPosition),
        ),
        PopupMenuItem<void>(
          child: const Row(
            children: [
              Icon(Icons.add, size: 16),
              SizedBox(width: 8),
              Text('Insert Above'),
            ],
          ),
          onTap: () => _insertSymbolAt(
            _selectedReelIndex,
            symbolPosition,
            _symbols.first.id,
          ),
        ),
        PopupMenuItem<void>(
          child: const Row(
            children: [
              Icon(Icons.content_copy, size: 16),
              SizedBox(width: 8),
              Text('Duplicate'),
            ],
          ),
          onTap: () {
            final symbolId = _strips[_selectedReelIndex].symbolIds[symbolPosition];
            _insertSymbolAt(_selectedReelIndex, symbolPosition + 1, symbolId);
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Colors.red.shade300),
              const SizedBox(width: 8),
              Text('Remove', style: TextStyle(color: Colors.red.shade300)),
            ],
          ),
          onTap: () => _removeSymbolAt(_selectedReelIndex, symbolPosition),
        ),
      ],
    );
  }

  void _showSymbolPicker(int symbolPosition) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: const Text('Select Symbol', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: _symbols.length,
            itemBuilder: (context, index) {
              final symbol = _symbols[index];
              return ListTile(
                leading: Icon(symbol.type.icon, color: symbol.type.color),
                title: Text(symbol.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  symbol.type.label,
                  style: TextStyle(color: symbol.type.color, fontSize: 11),
                ),
                onTap: () {
                  _updateSymbolAt(_selectedReelIndex, symbolPosition, symbol.id);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsPanel() {
    final distribution = _getSymbolDistribution(_selectedReelIndex);
    final strip = _strips[_selectedReelIndex];
    final totalSymbols = strip.length;

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Statistics',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Reel ${_selectedReelIndex + 1} Distribution',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: _symbols.map((symbol) {
                final count = distribution[symbol.id] ?? 0;
                final percentage =
                    totalSymbols > 0 ? (count / totalSymbols * 100) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(symbol.type.icon,
                              color: symbol.type.color, size: 12),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              symbol.name,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$count (${percentage.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor:
                            AlwaysStoppedAnimation(symbol.type.color.withOpacity(0.7)),
                        minHeight: 3,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // Summary
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Column(
              children: [
                _buildStatRow('Total', '$totalSymbols'),
                _buildStatRow(
                  'Wild %',
                  '${((distribution[11] ?? 0) / totalSymbols * 100).toStringAsFixed(1)}%',
                ),
                _buildStatRow(
                  'Scatter %',
                  '${((distribution[12] ?? 0) / totalSymbols * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
