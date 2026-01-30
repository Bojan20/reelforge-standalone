/// GDD Preview Dialog V10
///
/// Large, detailed preview of imported GDD configuration with tabbed layout.
/// Shows slot mockup, symbols with payouts, features, stages, and math model.
library;

import 'package:flutter/material.dart';
import '../../services/gdd_import_service.dart';

/// Dialog that displays the imported GDD configuration with comprehensive preview
class GddPreviewDialog extends StatefulWidget {
  final GddImportResult importResult;

  const GddPreviewDialog({
    super.key,
    required this.importResult,
  });

  /// Show the preview dialog
  static Future<bool?> show(BuildContext context, GddImportResult result) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GddPreviewDialog(importResult: result),
    );
  }

  @override
  State<GddPreviewDialog> createState() => _GddPreviewDialogState();
}

class _GddPreviewDialogState extends State<GddPreviewDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  GddImportResult get result => widget.importResult;
  GameDesignDocument get gdd => result.gdd;
  GddGridConfig get grid => gdd.grid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Use 90% of screen, min 1200x800, max 1600x1000
    final dialogWidth = (screenSize.width * 0.9).clamp(1200.0, 1600.0);
    final dialogHeight = (screenSize.height * 0.9).clamp(800.0, 1000.0);

    return Dialog(
      backgroundColor: const Color(0xFF121216),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              // ═══════════════════════════════════════════════════════════════
              // HEADER
              // ═══════════════════════════════════════════════════════════════
              _buildHeader(),

              // ═══════════════════════════════════════════════════════════════
              // TAB BAR
              // ═══════════════════════════════════════════════════════════════
              _buildTabBar(),

              // ═══════════════════════════════════════════════════════════════
              // TAB CONTENT
              // ═══════════════════════════════════════════════════════════════
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildSymbolsTab(),
                    _buildFeaturesTab(),
                    _buildStagesTab(),
                    _buildMathTab(),
                  ],
                ),
              ),

              // ═══════════════════════════════════════════════════════════════
              // FOOTER
              // ═══════════════════════════════════════════════════════════════
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a1a20),
            const Color(0xFF1a1a20).withValues(alpha: 0.95),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF4a9eff).withValues(alpha: 0.3),
                  const Color(0xFF4a9eff).withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(Icons.casino, color: Color(0xFF4a9eff), size: 32),
          ),
          const SizedBox(width: 20),

          // Title & Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gdd.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildHeaderBadge(
                      'v${gdd.version}',
                      const Color(0xFF4a9eff),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderBadge(
                      '${grid.columns}×${grid.rows} GRID',
                      const Color(0xFF40ff90),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderBadge(
                      grid.mechanic.toUpperCase(),
                      _mechanicColor(grid.mechanic),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderBadge(
                      '${gdd.symbols.length} SYMBOLS',
                      const Color(0xFFff9040),
                    ),
                    const SizedBox(width: 10),
                    _buildHeaderBadge(
                      '${gdd.features.length} FEATURES',
                      const Color(0xFFff40ff),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 28),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF4a9eff),
        indicatorWeight: 3,
        labelColor: const Color(0xFF4a9eff),
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard, size: 20),
            text: 'OVERVIEW',
            height: 56,
          ),
          Tab(
            icon: Icon(Icons.stars, size: 20),
            text: 'SYMBOLS',
            height: 56,
          ),
          Tab(
            icon: Icon(Icons.auto_awesome, size: 20),
            text: 'FEATURES',
            height: 56,
          ),
          Tab(
            icon: Icon(Icons.timeline, size: 20),
            text: 'STAGES',
            height: 56,
          ),
          Tab(
            icon: Icon(Icons.calculate, size: 20),
            text: 'MATH MODEL',
            height: 56,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT: Slot Mockup (larger)
          Expanded(
            flex: 5,
            child: _buildSlotMockup(),
          ),
          const SizedBox(width: 24),

          // RIGHT: Quick Info Panels
          Expanded(
            flex: 3,
            child: _buildQuickInfoPanels(),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotMockup() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0c),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4a9eff).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4a9eff).withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4a9eff).withValues(alpha: 0.25),
                    const Color(0xFF4a9eff).withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.grid_view, color: Color(0xFF4a9eff), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'SLOT PREVIEW: ${grid.columns}×${grid.rows}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _mechanicColor(grid.mechanic).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _mechanicColor(grid.mechanic).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      grid.mechanic.toUpperCase(),
                      style: TextStyle(
                        color: _mechanicColor(grid.mechanic),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildGrid(),
              ),
            ),

            // Paylines/Ways info
            _buildPaylineInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final symbols = gdd.symbols;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCellWidth =
            (constraints.maxWidth - (grid.columns - 1) * 10) / grid.columns;
        final maxCellHeight =
            (constraints.maxHeight - (grid.rows - 1) * 10) / grid.rows;
        final cellSize = (maxCellWidth < maxCellHeight ? maxCellWidth : maxCellHeight)
            .clamp(50.0, 100.0);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(grid.rows, (row) {
              return Padding(
                padding: EdgeInsets.only(bottom: row < grid.rows - 1 ? 10 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(grid.columns, (col) {
                    final symbolIndex =
                        (row * grid.columns + col) % (symbols.isEmpty ? 1 : symbols.length);
                    final symbol = symbols.isNotEmpty ? symbols[symbolIndex] : null;

                    return Padding(
                      padding: EdgeInsets.only(right: col < grid.columns - 1 ? 10 : 0),
                      child: _buildSymbolCell(symbol, cellSize),
                    );
                  }),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildSymbolCell(GddSymbol? symbol, double size) {
    final tierColor = symbol != null ? _tierColor(symbol.tier) : Colors.grey;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tierColor.withValues(alpha: 0.35),
            tierColor.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Center(
        child: symbol != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _emojiForSymbol(symbol),
                    style: TextStyle(fontSize: size * 0.38),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      symbol.id.length > 6
                          ? '${symbol.id.substring(0, 5)}…'
                          : symbol.id,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Icon(
                Icons.help_outline,
                color: Colors.white.withValues(alpha: 0.3),
                size: size * 0.4,
              ),
      ),
    );
  }

  Widget _buildPaylineInfo() {
    if (grid.paylines == null && grid.ways == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (grid.paylines != null) ...[
            Icon(Icons.linear_scale, color: Colors.white.withValues(alpha: 0.6), size: 18),
            const SizedBox(width: 6),
            Text(
              '${grid.paylines} PAYLINES',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (grid.ways != null) ...[
            Icon(Icons.all_inclusive, color: Colors.white.withValues(alpha: 0.6), size: 18),
            const SizedBox(width: 6),
            Text(
              '${grid.ways} WAYS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickInfoPanels() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Math Model Quick View
          _buildInfoCard(
            'MATH MODEL',
            Icons.calculate,
            const Color(0xFF40ff90),
            [
              _infoRow('Target RTP', '${(gdd.math.rtp * 100).toStringAsFixed(2)}%'),
              _infoRow('Volatility', gdd.math.volatility.toUpperCase()),
              _infoRow('Hit Frequency', '${(gdd.math.hitFrequency * 100).toStringAsFixed(1)}%'),
              _infoRow('Win Tiers', '${gdd.math.winTiers.length}'),
            ],
          ),
          const SizedBox(height: 16),

          // Top Symbols Preview
          _buildInfoCard(
            'TOP SYMBOLS',
            Icons.stars,
            const Color(0xFFffd700),
            gdd.symbols.take(5).map((s) {
              final maxPay = s.payouts.isEmpty
                  ? 0.0
                  : s.payouts.values.reduce((a, b) => a > b ? a : b);
              return _infoRow(
                '${_emojiForSymbol(s)} ${s.name}',
                maxPay > 0 ? '${maxPay.toStringAsFixed(0)}x' : '—',
                color: _tierColor(s.tier),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Features Preview
          _buildInfoCard(
            'FEATURES',
            Icons.auto_awesome,
            const Color(0xFF40c8ff),
            gdd.features.take(4).map((f) {
              return _infoRow(
                f.name,
                f.type.label,
                color: _featureColor(f.type),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Stages Summary
          _buildInfoCard(
            'STAGES SUMMARY',
            Icons.timeline,
            const Color(0xFFff40ff),
            [
              _infoRow('Total Stages', '${result.generatedStages.length}'),
              _infoRow('Spin Stages', '${_countStagesByPrefix('SPIN_', 'REEL_')}'),
              _infoRow('Win Stages', '${_countStagesByPrefix('WIN_', 'ROLLUP_')}'),
              _infoRow('Feature Stages', '${_countStagesByPrefix('FS_', 'BONUS_', 'HOLD_')}'),
            ],
          ),

          // Warnings
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              'WARNINGS (${result.warnings.length})',
              Icons.warning_amber,
              const Color(0xFFff9040),
              result.warnings.take(3).map((w) => _warningRow(w)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  int _countStagesByPrefix(String prefix1, [String? prefix2, String? prefix3]) {
    return result.generatedStages.where((s) {
      if (s.startsWith(prefix1)) return true;
      if (prefix2 != null && s.startsWith(prefix2)) return true;
      if (prefix3 != null && s.startsWith(prefix3)) return true;
      return false;
    }).length;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: SYMBOLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSymbolsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with counts per tier
          _buildSymbolsTierBar(),
          const SizedBox(height: 20),

          // Symbols grid
          Expanded(
            child: _buildSymbolsGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolsTierBar() {
    final tierCounts = <SymbolTier, int>{};
    for (final s in gdd.symbols) {
      tierCounts[s.tier] = (tierCounts[s.tier] ?? 0) + 1;
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: SymbolTier.values.map((tier) {
        final count = tierCounts[tier] ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _tierColor(tier).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _tierColor(tier).withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _tierColor(tier),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${tier.label}: $count',
                style: TextStyle(
                  color: _tierColor(tier),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSymbolsGrid() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: gdd.symbols.length,
          separatorBuilder: (_, _a) => Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
          ),
          itemBuilder: (context, index) {
            final symbol = gdd.symbols[index];
            return _buildSymbolRow(symbol, index);
          },
        ),
      ),
    );
  }

  Widget _buildSymbolRow(GddSymbol symbol, int index) {
    final tierColor = _tierColor(symbol.tier);
    final sortedPayouts = symbol.payouts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 32,
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ),

          // Emoji
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tierColor.withValues(alpha: 0.3),
                  tierColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tierColor.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(
                _emojiForSymbol(symbol),
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Name & ID
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${symbol.id}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Tier badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tierColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              symbol.tier.label.toUpperCase(),
              style: TextStyle(
                color: tierColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Special badges
          if (symbol.isWild || symbol.isScatter || symbol.isBonus)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                symbol.isWild
                    ? 'WILD'
                    : symbol.isScatter
                        ? 'SCATTER'
                        : 'BONUS',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          // Payouts
          Expanded(
            flex: 3,
            child: sortedPayouts.isEmpty
                ? Text(
                    'No payouts defined',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: sortedPayouts.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${entry.key}× ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                ),
                              ),
                              TextSpan(
                                text: '${entry.value.toStringAsFixed(entry.value == entry.value.truncate() ? 0 : 1)}x',
                                style: TextStyle(
                                  color: tierColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: FEATURES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFeaturesTab() {
    if (gdd.features.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No features defined in GDD',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.8,
        ),
        itemCount: gdd.features.length,
        itemBuilder: (context, index) {
          return _buildFeatureCard(gdd.features[index]);
        },
      ),
    );
  }

  Widget _buildFeatureCard(GddFeature feature) {
    final color = _featureColor(feature.type);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _featureIcon(feature.type),
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        feature.type.label.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),

          // Details
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (feature.triggerCondition != null)
                _featureDetail('Trigger', feature.triggerCondition!, color),
              if (feature.initialSpins != null)
                _featureDetail('Spins', '${feature.initialSpins}', color),
              if (feature.retriggerable != null && feature.retriggerable! > 0)
                _featureDetail('', 'Retriggerable', color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureDetail(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              '$label: ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _featureIcon(GddFeatureType type) {
    return switch (type) {
      GddFeatureType.freeSpins => Icons.replay,
      GddFeatureType.bonus => Icons.card_giftcard,
      GddFeatureType.holdAndSpin => Icons.lock,
      GddFeatureType.cascade => Icons.waterfall_chart,
      GddFeatureType.gamble => Icons.casino,
      GddFeatureType.jackpot => Icons.emoji_events,
      GddFeatureType.multiplier => Icons.close,
      GddFeatureType.expanding => Icons.open_in_full,
      GddFeatureType.sticky => Icons.push_pin,
      GddFeatureType.random => Icons.shuffle,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesTab() {
    final stages = result.generatedStages;

    // Group by category
    final grouped = <String, List<String>>{};
    for (final stage in stages) {
      final cat = _getCategoryForStage(stage);
      grouped.putIfAbsent(cat, () => []).add(stage);
    }

    final categories = grouped.keys.toList()
      ..sort((a, b) => _categoryOrder(a).compareTo(_categoryOrder(b)));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with total count
          Row(
            children: [
              const Icon(Icons.layers, color: Color(0xFF40ff90), size: 22),
              const SizedBox(width: 10),
              Text(
                '${stages.length} STAGES WILL BE REGISTERED',
                style: const TextStyle(
                  color: Color(0xFF40ff90),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Categories grid
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final stagesInCat = grouped[category]!;
                final color = _getCategoryColor(category);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: index < 3,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    shape: const RoundedRectangleBorder(),
                    collapsedShape: const RoundedRectangleBorder(),
                    iconColor: color,
                    collapsedIconColor: color.withValues(alpha: 0.6),
                    title: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${stagesInCat.length}',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: stagesInCat.map((stage) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              stage,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getCategoryForStage(String stage) {
    if (stage.startsWith('SPIN_') || stage.startsWith('REEL_')) return 'Spin';
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return 'Win';
    if (stage.startsWith('FS_') || stage.startsWith('FREESPIN_')) return 'Free Spins';
    if (stage.startsWith('BONUS_')) return 'Bonus';
    if (stage.startsWith('HOLD_') || stage.startsWith('RESPIN_')) return 'Hold & Win';
    if (stage.startsWith('CASCADE_') || stage.startsWith('TUMBLE_')) return 'Cascade';
    if (stage.startsWith('JACKPOT_')) return 'Jackpot';
    if (stage.startsWith('GAMBLE_')) return 'Gamble';
    if (stage.startsWith('WILD_')) return 'Wild';
    if (stage.startsWith('SCATTER_') || stage.startsWith('ANTICIPATION_')) return 'Scatter';
    if (stage.startsWith('SYMBOL_')) return 'Symbol';
    if (stage.startsWith('MULT_')) return 'Multiplier';
    if (stage.startsWith('MUSIC_') || stage.startsWith('AMBIENT_')) return 'Music';
    if (stage.startsWith('UI_')) return 'UI';
    return 'Custom';
  }

  int _categoryOrder(String category) {
    return switch (category) {
      'Spin' => 0,
      'Win' => 1,
      'Symbol' => 2,
      'Cascade' => 3,
      'Wild' => 4,
      'Scatter' => 5,
      'Free Spins' => 6,
      'Bonus' => 7,
      'Hold & Win' => 8,
      'Jackpot' => 9,
      'Gamble' => 10,
      'Multiplier' => 11,
      'Music' => 12,
      'UI' => 13,
      _ => 99,
    };
  }

  Color _getCategoryColor(String category) {
    return switch (category) {
      'Spin' => const Color(0xFF4a9eff),
      'Win' => const Color(0xFFffd700),
      'Free Spins' => const Color(0xFF40ff90),
      'Bonus' => const Color(0xFF40ff90),
      'Hold & Win' => const Color(0xFFff9040),
      'Cascade' => const Color(0xFF40c8ff),
      'Jackpot' => const Color(0xFFff4040),
      'Gamble' => const Color(0xFFe040fb),
      'Wild' => const Color(0xFFffb6c1),
      'Scatter' => const Color(0xFFffb6c1),
      'Symbol' => const Color(0xFF888899),
      'Multiplier' => const Color(0xFFff9040),
      'Music' => const Color(0xFF40c8ff),
      'UI' => const Color(0xFF888888),
      _ => Colors.white54,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 5: MATH MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMathTab() {
    final math = gdd.math;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT: Core Stats
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMathCard(
                  'CORE STATISTICS',
                  Icons.analytics,
                  const Color(0xFF40ff90),
                  [
                    _buildMathRow('Target RTP', '${(math.rtp * 100).toStringAsFixed(2)}%',
                        const Color(0xFF40ff90)),
                    _buildMathRow('Volatility', math.volatility.toUpperCase(),
                        _volatilityColor(math.volatility)),
                    _buildMathRow('Hit Frequency', '${(math.hitFrequency * 100).toStringAsFixed(2)}%',
                        const Color(0xFF40c8ff)),
                  ],
                ),
                const SizedBox(height: 20),
                _buildMathCard(
                  'GRID CONFIGURATION',
                  Icons.grid_view,
                  const Color(0xFF4a9eff),
                  [
                    _buildMathRow('Reels × Rows', '${grid.columns} × ${grid.rows}',
                        Colors.white),
                    _buildMathRow('Mechanic', grid.mechanic.toUpperCase(),
                        _mechanicColor(grid.mechanic)),
                    if (grid.paylines != null)
                      _buildMathRow('Paylines', '${grid.paylines}', Colors.white),
                    if (grid.ways != null)
                      _buildMathRow('Ways to Win', '${grid.ways}', Colors.white),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // RIGHT: Win Tiers
          Expanded(
            flex: 3,
            child: _buildWinTiersCard(math.winTiers),
          ),
        ],
      ),
    );
  }

  Widget _buildMathCard(String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMathRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinTiersCard(List<GddWinTier> tiers) {
    if (tiers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Text(
            'No win tiers defined',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFffd700).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFffd700).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: Color(0xFFffd700), size: 22),
              const SizedBox(width: 10),
              const Text(
                'WIN TIERS',
                style: TextStyle(
                  color: Color(0xFFffd700),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${tiers.length} tiers',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: tiers.length,
              separatorBuilder: (_, _a) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final tier = tiers[index];
                final color = _winTierColor(tier.name);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tier.name.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${tier.minMultiplier.toStringAsFixed(0)}x',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${tier.maxMultiplier.toStringAsFixed(0)}x',
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _winTierColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('ultra') || lower.contains('massive')) return const Color(0xFFff4040);
    if (lower.contains('epic') || lower.contains('huge')) return const Color(0xFFe040fb);
    if (lower.contains('mega') || lower.contains('great')) return const Color(0xFFffd700);
    if (lower.contains('super') || lower.contains('large')) return const Color(0xFFff9040);
    if (lower.contains('big') || lower.contains('major')) return const Color(0xFF40ff90);
    if (lower.contains('medium') || lower.contains('nice')) return const Color(0xFF40c8ff);
    return Colors.white70;
  }

  Color _volatilityColor(String vol) {
    return switch (vol.toLowerCase()) {
      'low' => const Color(0xFF40c8ff),
      'medium' || 'med' => const Color(0xFF40ff90),
      'high' => const Color(0xFFff9040),
      'extreme' || 'very high' => const Color(0xFFff4040),
      _ => Colors.white70,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Warnings summary
          if (result.warnings.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFff9040).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFff9040).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFff9040), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${result.warnings.length} warning${result.warnings.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFff9040),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Cancel button
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),

          // Apply button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40ff90),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check, size: 22),
            label: const Text(
              'Apply Configuration',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInfoCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            height: 1,
            color: color.withValues(alpha: 0.12),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: TextStyle(
                color: color ?? Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _warningRow(String warning) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, size: 14, color: Color(0xFFff9040)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: const TextStyle(color: Color(0xFFff9040), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Color _tierColor(SymbolTier tier) {
    return switch (tier) {
      SymbolTier.low => const Color(0xFF7986cb),
      SymbolTier.mid => const Color(0xFF4caf50),
      SymbolTier.high => const Color(0xFFff6699),
      SymbolTier.premium => const Color(0xFFffd700),
      SymbolTier.wild => const Color(0xFFffd700),
      SymbolTier.scatter => const Color(0xFFe040fb),
      SymbolTier.bonus => const Color(0xFF40c8ff),
      SymbolTier.special => const Color(0xFFff4060),
    };
  }

  Color _mechanicColor(String mechanic) {
    return switch (mechanic.toLowerCase()) {
      'lines' => const Color(0xFF40c8ff),
      'ways' => const Color(0xFF40ff90),
      'megaways' => const Color(0xFFffd700),
      'cluster' => const Color(0xFFff40ff),
      _ => const Color(0xFF4a9eff),
    };
  }

  Color _featureColor(GddFeatureType type) {
    return switch (type) {
      GddFeatureType.freeSpins => const Color(0xFF40ff90),
      GddFeatureType.bonus => const Color(0xFF40c8ff),
      GddFeatureType.holdAndSpin => const Color(0xFFff9040),
      GddFeatureType.cascade => const Color(0xFF40c8ff),
      GddFeatureType.gamble => const Color(0xFFe040fb),
      GddFeatureType.jackpot => const Color(0xFFffd700),
      GddFeatureType.multiplier => const Color(0xFFff9040),
      GddFeatureType.expanding => const Color(0xFFffb6c1),
      GddFeatureType.sticky => const Color(0xFFffb6c1),
      GddFeatureType.random => const Color(0xFF888899),
    };
  }

  String _emojiForSymbol(GddSymbol symbol) {
    final nameLower = symbol.name.toLowerCase();
    final idLower = symbol.id.toLowerCase();

    if (symbol.isWild) return '🌟';
    if (symbol.isScatter) return '💠';
    if (symbol.isBonus) return '🎁';

    // Playing cards
    if (idLower == '10' || nameLower.contains('ten')) return '🔟';
    if (idLower == 'j' || nameLower.contains('jack')) return '🃏';
    if (idLower == 'q' || nameLower.contains('queen')) return '👸';
    if (idLower == 'k' || nameLower.contains('king')) return '🤴';
    if (idLower == 'a' || nameLower.contains('ace')) return '🅰️';

    // Greek mythology
    if (nameLower.contains('zeus')) return '⚡';
    if (nameLower.contains('poseidon')) return '🔱';
    if (nameLower.contains('hades')) return '💀';
    if (nameLower.contains('athena')) return '🦉';
    if (nameLower.contains('apollo')) return '☀️';
    if (nameLower.contains('hermes')) return '👟';
    if (nameLower.contains('ares')) return '⚔️';
    if (nameLower.contains('medusa')) return '🐍';
    if (nameLower.contains('pegasus')) return '🦄';
    if (nameLower.contains('olympus')) return '🏛️';

    // Egyptian
    if (nameLower.contains('pharaoh')) return '👑';
    if (nameLower.contains('cleopatra')) return '👸';
    if (nameLower.contains('anubis')) return '🐺';
    if (nameLower.contains('ra') || nameLower.contains('sun')) return '☀️';
    if (nameLower.contains('horus')) return '🦅';
    if (nameLower.contains('scarab')) return '🪲';
    if (nameLower.contains('eye')) return '👁️';
    if (nameLower.contains('pyramid')) return '🔺';

    // Asian
    if (nameLower.contains('dragon')) return '🐉';
    if (nameLower.contains('phoenix')) return '🦅';
    if (nameLower.contains('tiger')) return '🐅';
    if (nameLower.contains('koi')) return '🐟';
    if (nameLower.contains('panda')) return '🐼';
    if (nameLower.contains('lantern')) return '🏮';
    if (nameLower.contains('coin')) return '🪙';

    // Irish/Celtic
    if (nameLower.contains('leprechaun')) return '🧙';
    if (nameLower.contains('pot')) return '🪙';
    if (nameLower.contains('rainbow')) return '🌈';
    if (nameLower.contains('clover') || nameLower.contains('shamrock')) return '🍀';
    if (nameLower.contains('horseshoe')) return '🧲';

    // Norse
    if (nameLower.contains('odin')) return '👁️';
    if (nameLower.contains('thor')) return '🔨';
    if (nameLower.contains('freya')) return '💕';
    if (nameLower.contains('loki')) return '🎭';
    if (nameLower.contains('raven')) return '🐦‍⬛';
    if (nameLower.contains('viking')) return '⛵';

    // Common symbols
    if (nameLower.contains('gem') || nameLower.contains('diamond')) return '💎';
    if (nameLower.contains('gold')) return '🪙';
    if (nameLower.contains('crown')) return '👑';
    if (nameLower.contains('star')) return '⭐';
    if (nameLower.contains('seven') || idLower == '7') return '7️⃣';
    if (nameLower.contains('bar')) return '🎰';
    if (nameLower.contains('bell')) return '🔔';
    if (nameLower.contains('cherry')) return '🍒';
    if (nameLower.contains('lemon')) return '🍋';
    if (nameLower.contains('grape')) return '🍇';
    if (nameLower.contains('orange')) return '🍊';
    if (nameLower.contains('watermelon')) return '🍉';

    // Fallback by tier
    return switch (symbol.tier) {
      SymbolTier.premium => '💎',
      SymbolTier.high => '🔶',
      SymbolTier.mid => '🔷',
      SymbolTier.low => '🔹',
      _ => '🎰',
    };
  }
}

// Extensions SymbolTierExtension and GddFeatureTypeExtension are defined in gdd_import_service.dart
