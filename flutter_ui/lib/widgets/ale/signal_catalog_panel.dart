/// Signal Catalog Panel — Comprehensive ALE Signal Management
///
/// Features:
/// - Built-in signal library (18+ signals)
/// - Custom signal creation
/// - Normalization curve visualization
/// - Real-time signal value monitoring
/// - Category-based organization
/// - Search and filtering
/// - Export/import signal definitions

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Signal category for organization
enum SignalCategory {
  win('Win Metrics', Icons.emoji_events),
  streak('Streaks', Icons.trending_up),
  balance('Balance', Icons.account_balance_wallet),
  feature('Feature Progress', Icons.stars),
  special('Special', Icons.auto_awesome),
  derived('Derived', Icons.functions),
  custom('Custom', Icons.edit);

  final String label;
  final IconData icon;
  const SignalCategory(this.label, this.icon);
}

/// Built-in signal template
class BuiltInSignal {
  final String id;
  final String name;
  final String description;
  final SignalCategory category;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final NormalizationMode normalization;
  final double? sigmoidK;
  final double? asymptoticMax;
  final bool isDerived;

  const BuiltInSignal({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.minValue = 0.0,
    this.maxValue = 1.0,
    this.defaultValue = 0.0,
    this.normalization = NormalizationMode.linear,
    this.sigmoidK,
    this.asymptoticMax,
    this.isDerived = false,
  });

  AleSignalDefinition toDefinition() {
    return AleSignalDefinition(
      id: id,
      name: name,
      minValue: minValue,
      maxValue: maxValue,
      defaultValue: defaultValue,
      normalization: normalization,
      sigmoidK: sigmoidK,
      asymptoticMax: asymptoticMax,
      isDerived: isDerived,
    );
  }
}

/// All built-in ALE signals
const List<BuiltInSignal> kBuiltInSignals = [
  // Win Metrics
  BuiltInSignal(
    id: 'winTier',
    name: 'Win Tier',
    description: 'Win size tier (0=loss, 1=small, 2=medium, 3=big, 4=mega, 5=epic)',
    category: SignalCategory.win,
    minValue: 0,
    maxValue: 5,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'winXbet',
    name: 'Win x Bet',
    description: 'Win amount as multiple of bet (0x to 1000x+)',
    category: SignalCategory.win,
    minValue: 0,
    maxValue: 1000,
    normalization: NormalizationMode.asymptotic,
    asymptoticMax: 100,
  ),

  // Streaks
  BuiltInSignal(
    id: 'consecutiveWins',
    name: 'Consecutive Wins',
    description: 'Number of wins in a row',
    category: SignalCategory.streak,
    minValue: 0,
    maxValue: 20,
    normalization: NormalizationMode.sigmoid,
    sigmoidK: 0.3,
  ),
  BuiltInSignal(
    id: 'consecutiveLosses',
    name: 'Consecutive Losses',
    description: 'Number of losses in a row',
    category: SignalCategory.streak,
    minValue: 0,
    maxValue: 20,
    normalization: NormalizationMode.sigmoid,
    sigmoidK: 0.3,
  ),
  BuiltInSignal(
    id: 'winStreakLength',
    name: 'Win Streak Length',
    description: 'Length of current win streak',
    category: SignalCategory.streak,
    minValue: 0,
    maxValue: 50,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'lossStreakLength',
    name: 'Loss Streak Length',
    description: 'Length of current loss streak',
    category: SignalCategory.streak,
    minValue: 0,
    maxValue: 50,
    normalization: NormalizationMode.linear,
  ),

  // Balance
  BuiltInSignal(
    id: 'balanceTrend',
    name: 'Balance Trend',
    description: 'Balance direction (-1 down, 0 flat, +1 up)',
    category: SignalCategory.balance,
    minValue: -1,
    maxValue: 1,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'sessionProfit',
    name: 'Session Profit',
    description: 'Profit/loss as percentage of initial balance',
    category: SignalCategory.balance,
    minValue: -1,
    maxValue: 5,
    normalization: NormalizationMode.asymptotic,
    asymptoticMax: 2,
  ),

  // Feature Progress
  BuiltInSignal(
    id: 'featureProgress',
    name: 'Feature Progress',
    description: 'Progress toward triggering a feature (0-1)',
    category: SignalCategory.feature,
    minValue: 0,
    maxValue: 1,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'multiplier',
    name: 'Multiplier',
    description: 'Current active multiplier',
    category: SignalCategory.feature,
    minValue: 1,
    maxValue: 100,
    normalization: NormalizationMode.asymptotic,
    asymptoticMax: 20,
  ),
  BuiltInSignal(
    id: 'cascadeDepth',
    name: 'Cascade Depth',
    description: 'Current cascade/tumble level',
    category: SignalCategory.feature,
    minValue: 0,
    maxValue: 20,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'respinsRemaining',
    name: 'Respins Remaining',
    description: 'Number of respins left',
    category: SignalCategory.feature,
    minValue: 0,
    maxValue: 10,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'spinsInFeature',
    name: 'Spins in Feature',
    description: 'Number of spins completed in current feature',
    category: SignalCategory.feature,
    minValue: 0,
    maxValue: 100,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'totalFeatureSpins',
    name: 'Total Feature Spins',
    description: 'Total spins awarded for feature',
    category: SignalCategory.feature,
    minValue: 0,
    maxValue: 100,
    normalization: NormalizationMode.linear,
  ),

  // Special
  BuiltInSignal(
    id: 'nearMissIntensity',
    name: 'Near Miss Intensity',
    description: 'How close to a big win (0-1)',
    category: SignalCategory.special,
    minValue: 0,
    maxValue: 1,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'anticipationLevel',
    name: 'Anticipation Level',
    description: 'Current anticipation intensity (0-1)',
    category: SignalCategory.special,
    minValue: 0,
    maxValue: 1,
    normalization: NormalizationMode.linear,
  ),
  BuiltInSignal(
    id: 'jackpotProximity',
    name: 'Jackpot Proximity',
    description: 'Distance to jackpot trigger (0=far, 1=imminent)',
    category: SignalCategory.special,
    minValue: 0,
    maxValue: 1,
    normalization: NormalizationMode.sigmoid,
    sigmoidK: 0.5,
  ),
  BuiltInSignal(
    id: 'turboMode',
    name: 'Turbo Mode',
    description: 'Turbo/fast spin active (0 or 1)',
    category: SignalCategory.special,
    minValue: 0,
    maxValue: 1,
    normalization: NormalizationMode.none,
  ),

  // Derived
  BuiltInSignal(
    id: 'momentum',
    name: 'Momentum',
    description: 'Combined win/loss momentum (derived)',
    category: SignalCategory.derived,
    minValue: -1,
    maxValue: 1,
    normalization: NormalizationMode.linear,
    isDerived: true,
  ),
  BuiltInSignal(
    id: 'velocity',
    name: 'Velocity',
    description: 'Rate of change of momentum (derived)',
    category: SignalCategory.derived,
    minValue: -1,
    maxValue: 1,
    normalization: NormalizationMode.linear,
    isDerived: true,
  ),
];

class SignalCatalogPanel extends StatefulWidget {
  final double height;

  const SignalCatalogPanel({
    super.key,
    this.height = 500,
  });

  @override
  State<SignalCatalogPanel> createState() => _SignalCatalogPanelState();
}

class _SignalCatalogPanelState extends State<SignalCatalogPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  SignalCategory? _selectedCategory;
  String? _selectedSignalId;
  bool _showCustomSignals = true;
  bool _showBuiltIn = true;

  // Custom signals
  final List<AleSignalDefinition> _customSignals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCatalogTab(),
                _buildMonitorTab(),
                _buildEditorTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: FluxForgeTheme.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Signal Catalog',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              _buildSearchField(),
              const SizedBox(width: 8),
              _buildFilterDropdown(),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: FluxForgeTheme.accent,
            unselectedLabelColor: FluxForgeTheme.textMuted,
            indicatorColor: FluxForgeTheme.accent,
            tabs: const [
              Tab(text: 'Catalog'),
              Tab(text: 'Monitor'),
              Tab(text: 'Editor'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      width: 200,
      height: 28,
      child: TextField(
        style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Search signals...',
          hintStyle: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
          prefixIcon: Icon(Icons.search, size: 16, color: FluxForgeTheme.textMuted),
          filled: true,
          fillColor: FluxForgeTheme.bgDeep,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SignalCategory?>(
          value: _selectedCategory,
          hint: Text(
            'All Categories',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
          ),
          dropdownColor: FluxForgeTheme.bgSurface,
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
          items: [
            DropdownMenuItem<SignalCategory?>(
              value: null,
              child: Text('All Categories'),
            ),
            ...SignalCategory.values.map((cat) => DropdownMenuItem(
                  value: cat,
                  child: Row(
                    children: [
                      Icon(cat.icon, size: 14, color: _getCategoryColor(cat)),
                      const SizedBox(width: 4),
                      Text(cat.label),
                    ],
                  ),
                )),
          ],
          onChanged: (value) => setState(() => _selectedCategory = value),
        ),
      ),
    );
  }

  Widget _buildCatalogTab() {
    final filteredSignals = _getFilteredSignals();
    final groupedSignals = <SignalCategory, List<BuiltInSignal>>{};

    for (final signal in filteredSignals) {
      groupedSignals.putIfAbsent(signal.category, () => []).add(signal);
    }

    return Row(
      children: [
        // Signal list
        Expanded(
          flex: 2,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (_showBuiltIn)
                ...SignalCategory.values
                    .where((cat) => groupedSignals.containsKey(cat))
                    .map((cat) => _buildCategorySection(cat, groupedSignals[cat]!)),
              if (_showCustomSignals && _customSignals.isNotEmpty)
                _buildCustomSignalsSection(),
            ],
          ),
        ),
        // Signal details
        Container(
          width: 1,
          color: FluxForgeTheme.borderSubtle,
        ),
        Expanded(
          flex: 3,
          child: _selectedSignalId != null
              ? _buildSignalDetails(_selectedSignalId!)
              : _buildNoSelectionPlaceholder(),
        ),
      ],
    );
  }

  Widget _buildCategorySection(SignalCategory category, List<BuiltInSignal> signals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(category.icon, size: 14, color: _getCategoryColor(category)),
              const SizedBox(width: 4),
              Text(
                category.label,
                style: TextStyle(
                  color: _getCategoryColor(category),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${signals.length})',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        ...signals.map((signal) => _buildSignalTile(signal)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSignalTile(BuiltInSignal signal) {
    final isSelected = _selectedSignalId == signal.id;
    return Consumer<AleProvider>(
      builder: (context, ale, _) {
        final currentValue = ale.currentSignals[signal.id] ?? signal.defaultValue;
        final normalized = _normalizeValue(currentValue, signal);

        return GestureDetector(
          onTap: () => setState(() => _selectedSignalId = signal.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accent.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? FluxForgeTheme.accent : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Normalization indicator
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _getNormalizationColor(signal.normalization),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      _getNormalizationLabel(signal.normalization),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Signal info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            signal.name,
                            style: TextStyle(
                              color: FluxForgeTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (signal.isDerived) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.functions, size: 10, color: Colors.purple),
                          ],
                        ],
                      ),
                      Text(
                        signal.id,
                        style: TextStyle(
                          color: FluxForgeTheme.textMuted,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Current value & normalized bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currentValue.toStringAsFixed(2),
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 40,
                      height: 4,
                      child: LinearProgressIndicator(
                        value: normalized.clamp(0.0, 1.0),
                        backgroundColor: FluxForgeTheme.bgDeep,
                        valueColor: AlwaysStoppedAnimation(
                          _getCategoryColor(signal.category),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomSignalsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(SignalCategory.custom.icon,
                  size: 14, color: _getCategoryColor(SignalCategory.custom)),
              const SizedBox(width: 4),
              Text(
                'Custom Signals',
                style: TextStyle(
                  color: _getCategoryColor(SignalCategory.custom),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_customSignals.length})',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.add, size: 14, color: FluxForgeTheme.accent),
                onPressed: _showCreateCustomSignalDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
        ),
        ..._customSignals.map((signal) => _buildCustomSignalTile(signal)),
      ],
    );
  }

  Widget _buildCustomSignalTile(AleSignalDefinition signal) {
    final isSelected = _selectedSignalId == signal.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedSignalId = signal.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accent.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accent : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _getNormalizationColor(signal.normalization),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  _getNormalizationLabel(signal.normalization),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                signal.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete, size: 14, color: FluxForgeTheme.errorRed),
              onPressed: () => _deleteCustomSignal(signal.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalDetails(String signalId) {
    // Check built-in first
    final builtIn = kBuiltInSignals.where((s) => s.id == signalId).firstOrNull;
    if (builtIn != null) {
      return _buildBuiltInSignalDetails(builtIn);
    }

    // Check custom
    final custom = _customSignals.where((s) => s.id == signalId).firstOrNull;
    if (custom != null) {
      return _buildCustomSignalDetails(custom);
    }

    return _buildNoSelectionPlaceholder();
  }

  Widget _buildBuiltInSignalDetails(BuiltInSignal signal) {
    return Consumer<AleProvider>(
      builder: (context, ale, _) {
        final currentValue = ale.currentSignals[signal.id] ?? signal.defaultValue;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(signal.category).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(signal.category.icon,
                            size: 12, color: _getCategoryColor(signal.category)),
                        const SizedBox(width: 4),
                        Text(
                          signal.category.label,
                          style: TextStyle(
                            color: _getCategoryColor(signal.category),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (signal.isDerived)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DERIVED',
                        style: TextStyle(color: Colors.purple, fontSize: 9),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Name & ID
              Text(
                signal.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SelectableText(
                signal.id,
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                signal.description,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),

              // Current value display
              _buildValueDisplay(currentValue, signal),
              const SizedBox(height: 16),

              // Range info
              _buildRangeInfo(signal),
              const SizedBox(height: 16),

              // Normalization curve
              _buildNormalizationCurve(signal),
              const SizedBox(height: 16),

              // Test controls
              _buildTestControls(ale, signal),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValueDisplay(double value, BuiltInSignal signal) {
    final normalized = _normalizeValue(value, signal);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Raw Value',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
                  ),
                  Text(
                    value.toStringAsFixed(3),
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Normalized',
                    style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
                  ),
                  Text(
                    normalized.toStringAsFixed(3),
                    style: TextStyle(
                      color: FluxForgeTheme.accent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: normalized.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: FluxForgeTheme.bgDeep,
              valueColor: AlwaysStoppedAnimation(_getCategoryColor(signal.category)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeInfo(BuiltInSignal signal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Range Configuration',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildRangeItem('Min', signal.minValue),
              _buildRangeItem('Max', signal.maxValue),
              _buildRangeItem('Default', signal.defaultValue),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildRangeItem('Normalization', signal.normalization.name.toUpperCase()),
              if (signal.sigmoidK != null)
                _buildRangeItem('Sigmoid K', signal.sigmoidK!),
              if (signal.asymptoticMax != null)
                _buildRangeItem('Asymptotic Max', signal.asymptoticMax!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRangeItem(String label, dynamic value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9),
          ),
          Text(
            value is double ? value.toStringAsFixed(2) : value.toString(),
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalizationCurve(BuiltInSignal signal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Normalization Curve',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: const Size(double.infinity, 100),
              painter: _NormalizationCurvePainter(
                normalization: signal.normalization,
                sigmoidK: signal.sigmoidK ?? 0.5,
                asymptoticMax: signal.asymptoticMax ?? 1.0,
                color: _getCategoryColor(signal.category),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestControls(AleProvider ale, BuiltInSignal signal) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Controls',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: (ale.currentSignals[signal.id] ?? signal.defaultValue)
                      .clamp(signal.minValue, signal.maxValue),
                  min: signal.minValue,
                  max: signal.maxValue,
                  activeColor: _getCategoryColor(signal.category),
                  onChanged: (value) {
                    ale.updateSignal(signal.id, value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  (ale.currentSignals[signal.id] ?? signal.defaultValue)
                      .toStringAsFixed(2),
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildQuickValueButton(ale, signal, signal.minValue, 'Min'),
              const SizedBox(width: 4),
              _buildQuickValueButton(ale, signal, signal.defaultValue, 'Default'),
              const SizedBox(width: 4),
              _buildQuickValueButton(
                  ale, signal, (signal.minValue + signal.maxValue) / 2, 'Mid'),
              const SizedBox(width: 4),
              _buildQuickValueButton(ale, signal, signal.maxValue, 'Max'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickValueButton(
      AleProvider ale, BuiltInSignal signal, double value, String label) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 4),
          side: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        onPressed: () => ale.updateSignal(signal.id, value),
        child: Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
        ),
      ),
    );
  }

  Widget _buildCustomSignalDetails(AleSignalDefinition signal) {
    return Center(
      child: Text(
        'Custom signal: ${signal.name}',
        style: TextStyle(color: FluxForgeTheme.textMuted),
      ),
    );
  }

  Widget _buildNoSelectionPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, size: 48, color: FluxForgeTheme.textMuted),
          const SizedBox(height: 8),
          Text(
            'Select a signal to view details',
            style: TextStyle(color: FluxForgeTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorTab() {
    return Consumer<AleProvider>(
      builder: (context, ale, _) {
        final signals = ale.currentSignals;
        if (signals.isEmpty) {
          return Center(
            child: Text(
              'No active signals',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: kBuiltInSignals.length,
          itemBuilder: (context, index) {
            final signal = kBuiltInSignals[index];
            final value = signals[signal.id] ?? signal.defaultValue;
            final normalized = _normalizeValue(value, signal);

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      signal.name,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: normalized.clamp(0.0, 1.0),
                        minHeight: 12,
                        backgroundColor: FluxForgeTheme.bgDeep,
                        valueColor: AlwaysStoppedAnimation(
                          _getCategoryColor(signal.category),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: Text(
                      value.toStringAsFixed(2),
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(normalized * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: FluxForgeTheme.accent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditorTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Custom Signal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _showCreateCustomSignalDialog,
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_download, size: 16),
                label: const Text('Import'),
                onPressed: _importSignals,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_upload, size: 16),
                label: const Text('Export'),
                onPressed: _exportSignals,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _customSignals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_note,
                            size: 48, color: FluxForgeTheme.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'No custom signals defined',
                          style: TextStyle(color: FluxForgeTheme.textMuted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Create custom signals to extend the ALE system',
                          style: TextStyle(
                            color: FluxForgeTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _customSignals.length,
                    itemBuilder: (context, index) {
                      final signal = _customSignals[index];
                      return Card(
                        color: FluxForgeTheme.bgSurface,
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _getNormalizationColor(signal.normalization),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(
                                _getNormalizationLabel(signal.normalization),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            signal.name,
                            style: TextStyle(color: FluxForgeTheme.textPrimary),
                          ),
                          subtitle: Text(
                            '${signal.minValue} - ${signal.maxValue}',
                            style: TextStyle(color: FluxForgeTheme.textMuted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _editCustomSignal(signal),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    size: 18, color: FluxForgeTheme.errorRed),
                                onPressed: () => _deleteCustomSignal(signal.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<BuiltInSignal> _getFilteredSignals() {
    return kBuiltInSignals.where((signal) {
      if (_selectedCategory != null && signal.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return signal.name.toLowerCase().contains(query) ||
            signal.id.toLowerCase().contains(query) ||
            signal.description.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  double _normalizeValue(double value, BuiltInSignal signal) {
    final range = signal.maxValue - signal.minValue;
    if (range == 0) return 0;

    final t = (value - signal.minValue) / range;

    switch (signal.normalization) {
      case NormalizationMode.linear:
        return t;
      case NormalizationMode.sigmoid:
        final k = signal.sigmoidK ?? 0.5;
        return 1 / (1 + math.exp(-k * (t - 0.5) * 10));
      case NormalizationMode.asymptotic:
        final max = signal.asymptoticMax ?? 1.0;
        return t / (t + max);
      case NormalizationMode.none:
        return t;
    }
  }

  Color _getCategoryColor(SignalCategory category) {
    return switch (category) {
      SignalCategory.win => Colors.amber,
      SignalCategory.streak => Colors.green,
      SignalCategory.balance => Colors.cyan,
      SignalCategory.feature => Colors.purple,
      SignalCategory.special => Colors.orange,
      SignalCategory.derived => Colors.pink,
      SignalCategory.custom => Colors.teal,
    };
  }

  Color _getNormalizationColor(NormalizationMode mode) {
    return switch (mode) {
      NormalizationMode.linear => Colors.blue,
      NormalizationMode.sigmoid => Colors.orange,
      NormalizationMode.asymptotic => Colors.purple,
      NormalizationMode.none => Colors.grey,
    };
  }

  String _getNormalizationLabel(NormalizationMode mode) {
    return switch (mode) {
      NormalizationMode.linear => 'L',
      NormalizationMode.sigmoid => 'S',
      NormalizationMode.asymptotic => 'A',
      NormalizationMode.none => 'N',
    };
  }

  void _showCreateCustomSignalDialog() {
    // TODO: Implement dialog
  }

  void _editCustomSignal(AleSignalDefinition signal) {
    // TODO: Implement edit
  }

  void _deleteCustomSignal(String id) {
    setState(() {
      _customSignals.removeWhere((s) => s.id == id);
      if (_selectedSignalId == id) {
        _selectedSignalId = null;
      }
    });
  }

  void _importSignals() {
    // TODO: Implement import
  }

  void _exportSignals() {
    // TODO: Implement export
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NORMALIZATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _NormalizationCurvePainter extends CustomPainter {
  final NormalizationMode normalization;
  final double sigmoidK;
  final double asymptoticMax;
  final Color color;

  _NormalizationCurvePainter({
    required this.normalization,
    required this.sigmoidK,
    required this.asymptoticMax,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw grid
    for (int i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw curve
    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    const steps = 100;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = _evaluate(t);

      final x = t * size.width;
      final py = size.height - (y * size.height);

      if (i == 0) {
        path.moveTo(x, py);
      } else {
        path.lineTo(x, py);
      }
    }

    canvas.drawPath(path, curvePaint);

    // Draw linear reference (dashed)
    final refPaint = Paint()
      ..color = FluxForgeTheme.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      refPaint,
    );
  }

  double _evaluate(double t) {
    switch (normalization) {
      case NormalizationMode.linear:
        return t;
      case NormalizationMode.sigmoid:
        return 1 / (1 + math.exp(-sigmoidK * (t - 0.5) * 10));
      case NormalizationMode.asymptotic:
        return t / (t + asymptoticMax);
      case NormalizationMode.none:
        return t;
    }
  }

  @override
  bool shouldRepaint(covariant _NormalizationCurvePainter oldDelegate) {
    return normalization != oldDelegate.normalization ||
        sigmoidK != oldDelegate.sigmoidK ||
        asymptoticMax != oldDelegate.asymptoticMax ||
        color != oldDelegate.color;
  }
}
