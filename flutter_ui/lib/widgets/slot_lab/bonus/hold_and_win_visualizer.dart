// ═══════════════════════════════════════════════════════════════════════════════
// HOLD & WIN VISUALIZER — Real-time grid visualization for H&W feature
// ═══════════════════════════════════════════════════════════════════════════════
//
// Visual components:
// - 5x3 grid with locked symbols (coins with values)
// - Remaining respins counter
// - Fill progress bar
// - Total accumulated value display
// - Symbol type indicators (Mini/Minor/Major/Grand jackpots)
//
// Uses FFI for real-time state updates from Rust engine.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../src/rust/native_ffi.dart';
import '../../../theme/fluxforge_theme.dart';

/// Hold & Win feature state from Rust engine
class HoldAndWinState {
  final bool isActive;
  final int remainingRespins;
  final int totalRespins;
  final int lockedCount;
  final int gridSize;
  final double fillPercentage;
  final double totalValue;
  final List<LockedSymbol> lockedSymbols;

  const HoldAndWinState({
    required this.isActive,
    required this.remainingRespins,
    required this.totalRespins,
    required this.lockedCount,
    required this.gridSize,
    required this.fillPercentage,
    required this.totalValue,
    required this.lockedSymbols,
  });

  factory HoldAndWinState.empty() => const HoldAndWinState(
        isActive: false,
        remainingRespins: 0,
        totalRespins: 0,
        lockedCount: 0,
        gridSize: 15,
        fillPercentage: 0,
        totalValue: 0,
        lockedSymbols: [],
      );

  factory HoldAndWinState.fromJson(Map<String, dynamic> json) {
    final symbols = (json['locked_symbols'] as List? ?? [])
        .map((s) => LockedSymbol.fromJson(s as Map<String, dynamic>))
        .toList();

    return HoldAndWinState(
      isActive: json['is_active'] as bool? ?? false,
      remainingRespins: json['remaining_respins'] as int? ?? 0,
      totalRespins: json['total_respins'] as int? ?? 0,
      lockedCount: json['locked_count'] as int? ?? 0,
      gridSize: json['grid_size'] as int? ?? 15,
      fillPercentage: (json['fill_percentage'] as num?)?.toDouble() ?? 0,
      totalValue: (json['total_value'] as num?)?.toDouble() ?? 0,
      lockedSymbols: symbols,
    );
  }
}

/// A locked symbol in the H&W grid
class LockedSymbol {
  final int position;
  final double value;
  final HoldSymbolType symbolType;

  const LockedSymbol({
    required this.position,
    required this.value,
    required this.symbolType,
  });

  factory LockedSymbol.fromJson(Map<String, dynamic> json) {
    return LockedSymbol(
      position: json['position'] as int? ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0,
      symbolType: HoldSymbolType.fromString(json['symbol_type'] as String? ?? 'Normal'),
    );
  }

  /// Get grid row (0-2 for 5x3)
  int get row => position ~/ 5;

  /// Get grid column (0-4 for 5x3)
  int get column => position % 5;
}

/// Hold symbol type (jackpot tier)
enum HoldSymbolType {
  normal,
  mini,
  minor,
  major,
  grand;

  static HoldSymbolType fromString(String s) {
    return switch (s.toLowerCase()) {
      'mini' => mini,
      'minor' => minor,
      'major' => major,
      'grand' => grand,
      _ => normal,
    };
  }

  Color get color => switch (this) {
        normal => Colors.amber,
        mini => Colors.blue,
        minor => Colors.green,
        major => Colors.purple,
        grand => Colors.red,
      };

  String get label => switch (this) {
        normal => '',
        mini => 'MINI',
        minor => 'MINOR',
        major => 'MAJOR',
        grand => 'GRAND',
      };
}

/// Hold & Win Grid Visualizer Widget
class HoldAndWinVisualizer extends StatefulWidget {
  final int reels;
  final int rows;
  final Duration refreshInterval;
  final VoidCallback? onRespin;
  final VoidCallback? onComplete;

  const HoldAndWinVisualizer({
    super.key,
    this.reels = 5,
    this.rows = 3,
    this.refreshInterval = const Duration(milliseconds: 200),
    this.onRespin,
    this.onComplete,
  });

  @override
  State<HoldAndWinVisualizer> createState() => _HoldAndWinVisualizerState();
}

class _HoldAndWinVisualizerState extends State<HoldAndWinVisualizer>
    with SingleTickerProviderStateMixin {
  HoldAndWinState _state = HoldAndWinState.empty();
  Timer? _refreshTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;

    try {
      final json = NativeFFI.instance.holdAndWinGetStateJson();
      if (json != null && json.isNotEmpty) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        setState(() {
          _state = HoldAndWinState.fromJson(data);
        });
      }
    } catch (e) {
      debugPrint('[HoldAndWin] Refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _state.isActive ? Colors.amber.withOpacity(0.5) : FluxForgeTheme.borderSubtle,
          width: _state.isActive ? 2 : 1,
        ),
        boxShadow: _state.isActive
            ? [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildGrid(),
          const SizedBox(height: 16),
          _buildProgressBar(),
          const SizedBox(height: 12),
          _buildStats(),
          if (_state.isActive) ...[
            const SizedBox(height: 16),
            _buildControls(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Icon(
              Icons.grid_on,
              color: _state.isActive
                  ? Color.lerp(Colors.amber, Colors.orange, _pulseController.value)
                  : Colors.white38,
              size: 20,
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          'HOLD & WIN',
          style: TextStyle(
            color: _state.isActive ? Colors.amber : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (_state.isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '${_state.remainingRespins}',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const Text(
                  ' RESPINS',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            'INACTIVE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _buildGrid() {
    final cellSize = 60.0;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.rows, (row) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.reels, (col) {
                final position = row * widget.reels + col;
                final symbol = _state.lockedSymbols
                    .where((s) => s.position == position)
                    .firstOrNull;

                return _buildCell(position, symbol, cellSize);
              }),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCell(int position, LockedSymbol? symbol, double size) {
    final isLocked = symbol != null;

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isLocked
            ? symbol.symbolType.color.withOpacity(0.2)
            : FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLocked
              ? symbol.symbolType.color
              : FluxForgeTheme.borderSubtle.withOpacity(0.5),
          width: isLocked ? 2 : 1,
        ),
        boxShadow: isLocked
            ? [
                BoxShadow(
                  color: symbol.symbolType.color.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: isLocked
          ? _buildLockedSymbol(symbol)
          : Center(
              child: Text(
                '${position + 1}',
                style: TextStyle(
                  color: Colors.white12,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
    );
  }

  Widget _buildLockedSymbol(LockedSymbol symbol) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (symbol.symbolType != HoldSymbolType.normal)
          Text(
            symbol.symbolType.label,
            style: TextStyle(
              color: symbol.symbolType.color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        Icon(
          Icons.monetization_on,
          color: symbol.symbolType.color,
          size: symbol.symbolType == HoldSymbolType.normal ? 24 : 20,
        ),
        Text(
          _formatValue(symbol.value),
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final percentage = _state.fillPercentage.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'GRID FILL',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: percentage >= 1.0 ? Colors.green : Colors.amber,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: FluxForgeTheme.bgMid,
            valueColor: AlwaysStoppedAnimation(
              percentage >= 1.0 ? Colors.green : Colors.amber,
            ),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'LOCKED',
            '${_state.lockedCount}/${_state.gridSize}',
            Icons.lock,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'TOTAL WIN',
            _formatValue(_state.totalValue),
            Icons.attach_money,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'SPINS USED',
            '${_state.totalRespins}',
            Icons.replay,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onRespin,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('RESPIN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () {
            final payout = NativeFFI.instance.holdAndWinComplete();
            debugPrint('[HoldAndWin] Complete payout: $payout');
            widget.onComplete?.call();
          },
          icon: const Icon(Icons.done, size: 16),
          label: const Text('COLLECT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      ],
    );
  }

  String _formatValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else if (value >= 100) {
      return value.toStringAsFixed(0);
    } else {
      return value.toStringAsFixed(2);
    }
  }
}

/// Compact Hold & Win status badge for toolbars
class HoldAndWinStatusBadge extends StatefulWidget {
  final Duration refreshInterval;

  const HoldAndWinStatusBadge({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 500),
  });

  @override
  State<HoldAndWinStatusBadge> createState() => _HoldAndWinStatusBadgeState();
}

class _HoldAndWinStatusBadgeState extends State<HoldAndWinStatusBadge> {
  bool _isActive = false;
  int _remainingRespins = 0;
  double _fillPercentage = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;

    try {
      final isActive = NativeFFI.instance.holdAndWinIsActive();
      final remaining = NativeFFI.instance.holdAndWinRemainingRespins();
      final fill = NativeFFI.instance.holdAndWinFillPercentage();

      if (_isActive != isActive ||
          _remainingRespins != remaining ||
          _fillPercentage != fill) {
        setState(() {
          _isActive = isActive;
          _remainingRespins = remaining;
          _fillPercentage = fill;
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.grid_on, size: 12, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            'H&W',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 40,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _fillPercentage.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$_remainingRespins',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
