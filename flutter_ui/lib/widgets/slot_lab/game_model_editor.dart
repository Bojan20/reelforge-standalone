/// Game Model Editor Panel
///
/// Visual editor for GameModel configuration:
/// - Game Info (name, id, provider, volatility, RTP)
/// - Grid Setup (reels, rows)
/// - Symbols (id, name, type, value, variants)
/// - Features (Free Spins, Cascades, Hold & Win, etc.)
/// - Win Tiers (Small, Medium, Big, Mega, Epic, Ultra)
/// - Timing Profile
/// - Math Settings
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';
// FFI bindings will be used when integrating with provider
// import '../../src/rust/native_ffi.dart';
// import '../../src/rust/slot_lab_v2_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// GAME MODEL EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

class GameModelEditor extends StatefulWidget {
  final Map<String, dynamic>? initialModel;
  final ValueChanged<Map<String, dynamic>>? onModelChanged;
  final VoidCallback? onClose;

  const GameModelEditor({
    super.key,
    this.initialModel,
    this.onModelChanged,
    this.onClose,
  });

  @override
  State<GameModelEditor> createState() => _GameModelEditorState();
}

class _GameModelEditorState extends State<GameModelEditor>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Model data
  Map<String, dynamic> _model = {};
  bool _isDirty = false;

  // Form controllers
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _providerController = TextEditingController();
  final _rtpController = TextEditingController();

  // Grid
  int _reels = 5;
  int _rows = 3;

  // Mode & Volatility
  String _mode = 'gdd_only';
  String _volatility = 'medium';

  // Symbols list
  List<Map<String, dynamic>> _symbols = [];

  // Features list
  List<Map<String, dynamic>> _features = [];

  // Win tiers
  List<Map<String, dynamic>> _winTiers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadModel(widget.initialModel ?? _createDefaultModel());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _providerController.dispose();
    _rtpController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _createDefaultModel() {
    return {
      'info': {
        'name': 'New Game',
        'id': 'new_game',
        'version': '1.0.0',
        'provider': 'FluxForge Studio',
        'volatility': 'medium',
        'target_rtp': 0.965,
      },
      'grid': {
        'reels': 5,
        'rows': 3,
      },
      'mode': 'gdd_only',
      'symbols': _createDefaultSymbols(),
      'features': [],
      'win_tiers': _createDefaultWinTiers(),
      'timing': {
        'spin_duration_ms': 2000,
        'reel_stop_interval_ms': 200,
        'anticipation_delay_ms': 1500,
        'win_presentation_ms': 3000,
      },
    };
  }

  List<Map<String, dynamic>> _createDefaultSymbols() {
    return [
      {'id': 0, 'name': 'Wild', 'symbol_type': 'wild', 'value': 1000},
      {'id': 1, 'name': 'Scatter', 'symbol_type': 'scatter', 'value': 0},
      {'id': 2, 'name': 'Premium 1', 'symbol_type': 'paying', 'value': 500},
      {'id': 3, 'name': 'Premium 2', 'symbol_type': 'paying', 'value': 400},
      {'id': 4, 'name': 'Premium 3', 'symbol_type': 'paying', 'value': 300},
      {'id': 5, 'name': 'Low 1', 'symbol_type': 'paying', 'value': 100},
      {'id': 6, 'name': 'Low 2', 'symbol_type': 'paying', 'value': 80},
      {'id': 7, 'name': 'Low 3', 'symbol_type': 'paying', 'value': 60},
      {'id': 8, 'name': 'Low 4', 'symbol_type': 'paying', 'value': 40},
      {'id': 9, 'name': 'Low 5', 'symbol_type': 'paying', 'value': 20},
    ];
  }

  List<Map<String, dynamic>> _createDefaultWinTiers() {
    return [
      {'id': 'small', 'name': 'Small Win', 'min_multiplier': 0.5, 'max_multiplier': 2.0},
      {'id': 'medium', 'name': 'Medium Win', 'min_multiplier': 2.0, 'max_multiplier': 10.0},
      {'id': 'big', 'name': 'Big Win', 'min_multiplier': 10.0, 'max_multiplier': 25.0},
      {'id': 'mega', 'name': 'Mega Win', 'min_multiplier': 25.0, 'max_multiplier': 50.0},
      {'id': 'epic', 'name': 'Epic Win', 'min_multiplier': 50.0, 'max_multiplier': 100.0},
      {'id': 'ultra', 'name': 'Ultra Win', 'min_multiplier': 100.0, 'max_multiplier': null},
    ];
  }

  void _loadModel(Map<String, dynamic> model) {
    _model = Map<String, dynamic>.from(model);

    // Info
    final info = model['info'] as Map<String, dynamic>? ?? {};
    _nameController.text = info['name'] as String? ?? 'Unnamed';
    _idController.text = info['id'] as String? ?? 'unnamed';
    _providerController.text = info['provider'] as String? ?? '';
    _volatility = info['volatility'] as String? ?? 'medium';
    _rtpController.text = ((info['target_rtp'] as num? ?? 0.965) * 100).toStringAsFixed(2);

    // Grid
    final grid = model['grid'] as Map<String, dynamic>? ?? {};
    _reels = grid['reels'] as int? ?? 5;
    _rows = grid['rows'] as int? ?? 3;

    // Mode
    _mode = model['mode'] as String? ?? 'gdd_only';

    // Symbols
    final symbols = model['symbols'] as List? ?? [];
    _symbols = symbols.map((s) => Map<String, dynamic>.from(s as Map)).toList();

    // Features
    final features = model['features'] as List? ?? [];
    _features = features.map((f) => Map<String, dynamic>.from(f as Map)).toList();

    // Win tiers
    final winTiers = model['win_tiers'] as List? ?? _createDefaultWinTiers();
    _winTiers = winTiers.map((t) => Map<String, dynamic>.from(t as Map)).toList();

    setState(() {});
  }

  Map<String, dynamic> _buildModel() {
    return {
      'info': {
        'name': _nameController.text,
        'id': _idController.text,
        'version': '1.0.0',
        'provider': _providerController.text,
        'volatility': _volatility,
        'target_rtp': (double.tryParse(_rtpController.text) ?? 96.5) / 100,
      },
      'grid': {
        'reels': _reels,
        'rows': _rows,
      },
      'mode': _mode,
      'symbols': _symbols,
      'features': _features,
      'win_tiers': _winTiers,
      'timing': _model['timing'] ?? {
        'spin_duration_ms': 2000,
        'reel_stop_interval_ms': 200,
        'anticipation_delay_ms': 1500,
        'win_presentation_ms': 3000,
      },
    };
  }

  void _markDirty() {
    if (!_isDirty) {
      setState(() => _isDirty = true);
    }
  }

  void _applyChanges() {
    final model = _buildModel();
    widget.onModelChanged?.call(model);
    setState(() => _isDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Tab bar
          _buildTabBar(),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(),
                _buildGridTab(),
                _buildSymbolsTab(),
                _buildFeaturesTab(),
                _buildWinTiersTab(),
                _buildTimingTab(),
              ],
            ),
          ),
          // Footer with Apply button
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.settings_applications, size: 18, color: FluxForgeTheme.accent),
          const SizedBox(width: 8),
          const Text(
            'Game Model Editor',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (_isDirty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Modified',
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ),
          const SizedBox(width: 8),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              color: FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: FluxForgeTheme.accent,
        unselectedLabelColor: FluxForgeTheme.textMuted,
        indicatorColor: FluxForgeTheme.accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'INFO'),
          Tab(text: 'GRID'),
          Tab(text: 'SYMBOLS'),
          Tab(text: 'FEATURES'),
          Tab(text: 'WIN TIERS'),
          Tab(text: 'TIMING'),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(top: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          // Export JSON button
          TextButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Export'),
            onPressed: _exportJson,
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.textMuted,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          // Import JSON button
          TextButton.icon(
            icon: const Icon(Icons.upload, size: 16),
            label: const Text('Import'),
            onPressed: _importJson,
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.textMuted,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const Spacer(),
          // Apply button
          ElevatedButton(
            onPressed: _isDirty ? _applyChanges : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxForgeTheme.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: FluxForgeTheme.border,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INFO TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Game Information'),
          const SizedBox(height: 12),
          // Name
          _buildTextField(
            label: 'Game Name',
            controller: _nameController,
            hint: 'Enter game name',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 12),
          // ID
          _buildTextField(
            label: 'Game ID',
            controller: _idController,
            hint: 'unique_game_id',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 12),
          // Provider
          _buildTextField(
            label: 'Provider',
            controller: _providerController,
            hint: 'Studio name',
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Game Settings'),
          const SizedBox(height: 12),
          // Mode dropdown
          _buildDropdown<String>(
            label: 'Mode',
            value: _mode,
            items: const [
              DropdownMenuItem(value: 'gdd_only', child: Text('GDD Only (Scripted)')),
              DropdownMenuItem(value: 'math_driven', child: Text('Math Driven')),
            ],
            onChanged: (v) {
              setState(() => _mode = v ?? 'gdd_only');
              _markDirty();
            },
          ),
          const SizedBox(height: 12),
          // Volatility dropdown
          _buildDropdown<String>(
            label: 'Volatility',
            value: _volatility,
            items: const [
              DropdownMenuItem(value: 'low', child: Text('Low')),
              DropdownMenuItem(value: 'medium_low', child: Text('Medium-Low')),
              DropdownMenuItem(value: 'medium', child: Text('Medium')),
              DropdownMenuItem(value: 'medium_high', child: Text('Medium-High')),
              DropdownMenuItem(value: 'high', child: Text('High')),
              DropdownMenuItem(value: 'very_high', child: Text('Very High')),
            ],
            onChanged: (v) {
              setState(() => _volatility = v ?? 'medium');
              _markDirty();
            },
          ),
          const SizedBox(height: 12),
          // RTP
          _buildTextField(
            label: 'Target RTP (%)',
            controller: _rtpController,
            hint: '96.50',
            keyboardType: TextInputType.number,
            onChanged: (_) => _markDirty(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRID TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Grid Configuration'),
          const SizedBox(height: 16),
          // Visual grid preview
          Center(
            child: Container(
              width: 300,
              height: 200,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FluxForgeTheme.border),
              ),
              child: CustomPaint(
                painter: _GridPreviewPainter(reels: _reels, rows: _rows),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Reels slider
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Reels: $_reels',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _reels.toDouble(),
                  min: 3,
                  max: 8,
                  divisions: 5,
                  activeColor: FluxForgeTheme.accent,
                  onChanged: (v) {
                    setState(() => _reels = v.round());
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
          // Rows slider
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Rows: $_rows',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _rows.toDouble(),
                  min: 2,
                  max: 6,
                  divisions: 4,
                  activeColor: FluxForgeTheme.accent,
                  onChanged: (v) {
                    setState(() => _rows = v.round());
                    _markDirty();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Common presets
          _buildSectionHeader('Quick Presets'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('5x3', 5, 3),
              _buildPresetChip('5x4', 5, 4),
              _buildPresetChip('6x4', 6, 4),
              _buildPresetChip('3x3', 3, 3),
              _buildPresetChip('6x5', 6, 5),
              _buildPresetChip('8x6', 8, 6),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, int reels, int rows) {
    final isSelected = _reels == reels && _rows == rows;
    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? FluxForgeTheme.accent : FluxForgeTheme.surface,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : FluxForgeTheme.textMuted,
      ),
      onPressed: () {
        setState(() {
          _reels = reels;
          _rows = rows;
        });
        _markDirty();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOLS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSymbolsTab() {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addSymbol,
                tooltip: 'Add Symbol',
                color: FluxForgeTheme.textMuted,
              ),
              const Spacer(),
              Text(
                '${_symbols.length} symbols',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        // Symbol list
        Expanded(
          child: ListView.builder(
            itemCount: _symbols.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) => _buildSymbolCard(_symbols[index], index),
          ),
        ),
      ],
    );
  }

  Widget _buildSymbolCard(Map<String, dynamic> symbol, int index) {
    final id = symbol['id'] as int? ?? index;
    final name = symbol['name'] as String? ?? 'Symbol $id';
    final type = symbol['symbol_type'] as String? ?? 'paying';
    final value = symbol['value'] as int? ?? 0;

    Color typeColor;
    switch (type) {
      case 'wild':
        typeColor = Colors.purple;
        break;
      case 'scatter':
        typeColor = Colors.amber;
        break;
      case 'bonus':
        typeColor = Colors.green;
        break;
      default:
        typeColor = FluxForgeTheme.accent;
    }

    return Card(
      color: FluxForgeTheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: typeColor),
          ),
          alignment: Alignment.center,
          child: Text(
            '$id',
            style: TextStyle(color: typeColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '$type • Value: $value',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editSymbol(index),
              color: FluxForgeTheme.textMuted,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
              onPressed: () => _deleteSymbol(index),
              color: Colors.red.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _addSymbol() {
    final newId = _symbols.isEmpty ? 0 :
        (_symbols.map((s) => s['id'] as int? ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    setState(() {
      _symbols.add({
        'id': newId,
        'name': 'Symbol $newId',
        'symbol_type': 'paying',
        'value': 10,
      });
    });
    _markDirty();
  }

  void _editSymbol(int index) {
    // Show dialog to edit symbol
    showDialog(
      context: context,
      builder: (context) => _SymbolEditDialog(
        symbol: _symbols[index],
        onSave: (updated) {
          setState(() => _symbols[index] = updated);
          _markDirty();
        },
      ),
    );
  }

  void _deleteSymbol(int index) {
    setState(() => _symbols.removeAt(index));
    _markDirty();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFeaturesTab() {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
          ),
          child: Row(
            children: [
              PopupMenuButton<String>(
                icon: Icon(Icons.add, size: 18, color: FluxForgeTheme.textMuted),
                tooltip: 'Add Feature',
                onSelected: _addFeature,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'free_spins', child: Text('Free Spins')),
                  const PopupMenuItem(value: 'cascades', child: Text('Cascades')),
                  const PopupMenuItem(value: 'hold_and_win', child: Text('Hold & Win')),
                  const PopupMenuItem(value: 'jackpot', child: Text('Jackpot')),
                  const PopupMenuItem(value: 'gamble', child: Text('Gamble/Risk')),
                  const PopupMenuItem(value: 'multiplier', child: Text('Multiplier Trail')),
                  const PopupMenuItem(value: 'custom', child: Text('Custom')),
                ],
              ),
              const Spacer(),
              Text(
                '${_features.length} features',
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        // Feature list
        Expanded(
          child: _features.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.extension_off, size: 48, color: FluxForgeTheme.textMuted),
                      const SizedBox(height: 8),
                      Text(
                        'No features configured',
                        style: TextStyle(color: FluxForgeTheme.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Click + to add a feature',
                        style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _features.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) => _buildFeatureCard(_features[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(Map<String, dynamic> feature, int index) {
    final id = feature['id'] as String? ?? 'feature_$index';
    final featureType = feature['feature_type'] as String? ?? 'custom';
    final name = feature['name'] as String? ?? _getFeatureTypeName(featureType);

    IconData icon;
    Color color;
    switch (featureType) {
      case 'free_spins':
        icon = Icons.autorenew;
        color = Colors.green;
        break;
      case 'cascades':
        icon = Icons.layers;
        color = Colors.blue;
        break;
      case 'hold_and_win':
        icon = Icons.lock;
        color = Colors.purple;
        break;
      case 'jackpot':
        icon = Icons.diamond;
        color = Colors.amber;
        break;
      case 'gamble':
        icon = Icons.casino;
        color = Colors.red;
        break;
      case 'multiplier':
        icon = Icons.trending_up;
        color = Colors.orange;
        break;
      default:
        icon = Icons.extension;
        color = FluxForgeTheme.accent;
    }

    return Card(
      color: FluxForgeTheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          id,
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, size: 16),
          onPressed: () {
            setState(() => _features.removeAt(index));
            _markDirty();
          },
          color: Colors.red.shade400,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildFeatureConfig(feature, index),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureConfig(Map<String, dynamic> feature, int index) {
    final featureType = feature['feature_type'] as String? ?? 'custom';

    switch (featureType) {
      case 'free_spins':
        return _buildFreeSpinsConfig(feature, index);
      case 'cascades':
        return _buildCascadesConfig(feature, index);
      case 'hold_and_win':
        return _buildHoldAndWinConfig(feature, index);
      case 'jackpot':
        return _buildJackpotConfig(feature, index);
      default:
        return _buildCustomFeatureConfig(feature, index);
    }
  }

  Widget _buildFreeSpinsConfig(Map<String, dynamic> feature, int index) {
    final config = feature['config'] as Map<String, dynamic>? ?? {};
    final baseSpins = config['base_spins'] as int? ?? 10;
    final extraPerScatter = config['extra_per_scatter'] as int? ?? 5;
    final multiplier = config['multiplier'] as num? ?? 1.0;
    final retriggerEnabled = config['retrigger_enabled'] as bool? ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConfigRow('Base Spins', baseSpins.toString(), (v) {
          config['base_spins'] = int.tryParse(v) ?? baseSpins;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
        _buildConfigRow('Extra Per Scatter', extraPerScatter.toString(), (v) {
          config['extra_per_scatter'] = int.tryParse(v) ?? extraPerScatter;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
        _buildConfigRow('Multiplier', multiplier.toString(), (v) {
          config['multiplier'] = double.tryParse(v) ?? multiplier;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
        SwitchListTile(
          title: const Text('Retrigger Enabled', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: retriggerEnabled,
          activeColor: FluxForgeTheme.accent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) {
            config['retrigger_enabled'] = v;
            feature['config'] = config;
            setState(() => _features[index] = feature);
            _markDirty();
          },
        ),
      ],
    );
  }

  Widget _buildCascadesConfig(Map<String, dynamic> feature, int index) {
    final config = feature['config'] as Map<String, dynamic>? ?? {};
    final maxCascades = config['max_cascades'] as int? ?? 0;
    final multiplierProgression = config['multiplier_progression'] as List? ?? [1, 2, 3, 5, 10];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConfigRow('Max Cascades (0=unlimited)', maxCascades.toString(), (v) {
          config['max_cascades'] = int.tryParse(v) ?? maxCascades;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
        const SizedBox(height: 8),
        Text(
          'Multiplier Progression: ${multiplierProgression.join(", ")}x',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildHoldAndWinConfig(Map<String, dynamic> feature, int index) {
    final config = feature['config'] as Map<String, dynamic>? ?? {};
    final initialSpins = config['initial_spins'] as int? ?? 3;
    final maxSpins = config['max_spins'] as int? ?? 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConfigRow('Initial Spins', initialSpins.toString(), (v) {
          config['initial_spins'] = int.tryParse(v) ?? initialSpins;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
        _buildConfigRow('Max Spins', maxSpins.toString(), (v) {
          config['max_spins'] = int.tryParse(v) ?? maxSpins;
          feature['config'] = config;
          setState(() => _features[index] = feature);
          _markDirty();
        }),
      ],
    );
  }

  Widget _buildJackpotConfig(Map<String, dynamic> feature, int index) {
    final config = feature['config'] as Map<String, dynamic>? ?? {};
    final tiers = config['tiers'] as List? ?? ['mini', 'minor', 'major', 'grand'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jackpot Tiers: ${tiers.join(", ")}',
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: tiers.map((tier) {
            Color color;
            switch (tier) {
              case 'mini': color = Colors.blue; break;
              case 'minor': color = Colors.green; break;
              case 'major': color = Colors.orange; break;
              case 'grand': color = Colors.purple; break;
              default: color = FluxForgeTheme.textMuted;
            }
            return Chip(
              label: Text(tier.toString().toUpperCase()),
              backgroundColor: color.withValues(alpha: 0.2),
              labelStyle: TextStyle(color: color, fontSize: 11),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCustomFeatureConfig(Map<String, dynamic> feature, int index) {
    return Text(
      'Custom feature configuration',
      style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
    );
  }

  Widget _buildConfigRow(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 80,
            height: 28,
            child: TextField(
              controller: TextEditingController(text: value),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.accent),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  void _addFeature(String featureType) {
    final id = '${featureType}_${DateTime.now().millisecondsSinceEpoch}';
    Map<String, dynamic> config = {};

    switch (featureType) {
      case 'free_spins':
        config = {
          'base_spins': 10,
          'extra_per_scatter': 5,
          'multiplier': 1.0,
          'retrigger_enabled': true,
        };
        break;
      case 'cascades':
        config = {
          'max_cascades': 0,
          'multiplier_progression': [1, 2, 3, 5, 10],
        };
        break;
      case 'hold_and_win':
        config = {
          'initial_spins': 3,
          'max_spins': 5,
        };
        break;
      case 'jackpot':
        config = {
          'tiers': ['mini', 'minor', 'major', 'grand'],
        };
        break;
      case 'gamble':
        config = {
          'max_attempts': 5,
          'double_up_probability': 0.5,
        };
        break;
    }

    setState(() {
      _features.add({
        'id': id,
        'feature_type': featureType,
        'name': _getFeatureTypeName(featureType),
        'config': config,
      });
    });
    _markDirty();
  }

  String _getFeatureTypeName(String type) {
    switch (type) {
      case 'free_spins': return 'Free Spins';
      case 'cascades': return 'Cascading Reels';
      case 'hold_and_win': return 'Hold & Win';
      case 'jackpot': return 'Jackpot';
      case 'gamble': return 'Gamble';
      case 'multiplier': return 'Multiplier Trail';
      default: return 'Custom Feature';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIERS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWinTiersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Win Tier Configuration'),
          const SizedBox(height: 8),
          Text(
            'Define multiplier ranges for each win tier. '
            'Used for celebration intensity and audio selection.',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ..._winTiers.asMap().entries.map((e) => _buildWinTierRow(e.value, e.key)),
        ],
      ),
    );
  }

  Widget _buildWinTierRow(Map<String, dynamic> tier, int index) {
    final id = tier['id'] as String? ?? 'tier_$index';
    final name = tier['name'] as String? ?? id;
    final minMult = tier['min_multiplier'] as num? ?? 0;
    final maxMult = tier['max_multiplier'] as num?;

    Color tierColor;
    switch (id) {
      case 'small': tierColor = Colors.green; break;
      case 'medium': tierColor = Colors.blue; break;
      case 'big': tierColor = Colors.orange; break;
      case 'mega': tierColor = Colors.purple; break;
      case 'epic': tierColor = Colors.pink; break;
      case 'ultra': tierColor = Colors.red; break;
      default: tierColor = FluxForgeTheme.accent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tierColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 50,
            decoration: BoxDecoration(
              color: tierColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(id, style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: TextEditingController(text: minMult.toString()),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                    decoration: _compactInputDecoration('Min'),
                    onChanged: (v) {
                      tier['min_multiplier'] = double.tryParse(v) ?? minMult;
                      setState(() => _winTiers[index] = tier);
                      _markDirty();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('—', style: TextStyle(color: FluxForgeTheme.textMuted)),
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: TextEditingController(text: maxMult?.toString() ?? '∞'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                    decoration: _compactInputDecoration('Max'),
                    onChanged: (v) {
                      tier['max_multiplier'] = v == '∞' || v.isEmpty ? null : double.tryParse(v);
                      setState(() => _winTiers[index] = tier);
                      _markDirty();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('x bet', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _compactInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: FluxForgeTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: FluxForgeTheme.accent),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimingTab() {
    final timing = _model['timing'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Timing Configuration'),
          const SizedBox(height: 8),
          Text(
            'Timing values in milliseconds for spin phases.',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildTimingSlider(
            'Spin Duration',
            timing['spin_duration_ms'] as int? ?? 2000,
            500, 5000,
            (v) {
              timing['spin_duration_ms'] = v;
              _model['timing'] = timing;
              _markDirty();
            },
          ),
          _buildTimingSlider(
            'Reel Stop Interval',
            timing['reel_stop_interval_ms'] as int? ?? 200,
            50, 500,
            (v) {
              timing['reel_stop_interval_ms'] = v;
              _model['timing'] = timing;
              _markDirty();
            },
          ),
          _buildTimingSlider(
            'Anticipation Delay',
            timing['anticipation_delay_ms'] as int? ?? 1500,
            500, 5000,
            (v) {
              timing['anticipation_delay_ms'] = v;
              _model['timing'] = timing;
              _markDirty();
            },
          ),
          _buildTimingSlider(
            'Win Presentation',
            timing['win_presentation_ms'] as int? ?? 3000,
            1000, 10000,
            (v) {
              timing['win_presentation_ms'] = v;
              _model['timing'] = timing;
              _markDirty();
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Timing Presets'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTimingPresetChip('Normal', {'spin_duration_ms': 2000, 'reel_stop_interval_ms': 200, 'anticipation_delay_ms': 1500, 'win_presentation_ms': 3000}),
              _buildTimingPresetChip('Turbo', {'spin_duration_ms': 1000, 'reel_stop_interval_ms': 100, 'anticipation_delay_ms': 800, 'win_presentation_ms': 1500}),
              _buildTimingPresetChip('Mobile', {'spin_duration_ms': 1500, 'reel_stop_interval_ms': 150, 'anticipation_delay_ms': 1000, 'win_presentation_ms': 2000}),
              _buildTimingPresetChip('Studio', {'spin_duration_ms': 3000, 'reel_stop_interval_ms': 300, 'anticipation_delay_ms': 2500, 'win_presentation_ms': 5000}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimingSlider(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Text('${value}ms', style: TextStyle(color: FluxForgeTheme.accent, fontSize: 12)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ 50,
          activeColor: FluxForgeTheme.accent,
          onChanged: (v) {
            setState(() {});
            onChanged(v.round());
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTimingPresetChip(String label, Map<String, int> preset) {
    return ActionChip(
      label: Text(label),
      backgroundColor: FluxForgeTheme.surface,
      labelStyle: TextStyle(color: FluxForgeTheme.textMuted),
      onPressed: () {
        setState(() {
          _model['timing'] = preset;
        });
        _markDirty();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: FluxForgeTheme.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: FluxForgeTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: FluxForgeTheme.accent),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: FluxForgeTheme.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: FluxForgeTheme.surface,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT/EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  void _exportJson() {
    final model = _buildModel();
    final json = const JsonEncoder.withIndent('  ').convert(model);
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model JSON copied to clipboard')),
    );
  }

  void _importJson() {
    showDialog(
      context: context,
      builder: (context) => _ImportJsonDialog(
        onImport: (json) {
          try {
            final model = jsonDecode(json) as Map<String, dynamic>;
            _loadModel(model);
            _markDirty();
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Invalid JSON: $e')),
            );
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRID PREVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _GridPreviewPainter extends CustomPainter {
  final int reels;
  final int rows;

  _GridPreviewPainter({required this.reels, required this.rows});

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = (size.width - 40) / reels;
    final cellHeight = (size.height - 40) / rows;
    final cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

    final gridWidth = cellSize * reels;
    final gridHeight = cellSize * rows;
    final offsetX = (size.width - gridWidth) / 2;
    final offsetY = (size.height - gridHeight) / 2;

    final paint = Paint()
      ..color = FluxForgeTheme.accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final fillPaint = Paint()
      ..color = FluxForgeTheme.accent.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    for (int r = 0; r < reels; r++) {
      for (int row = 0; row < rows; row++) {
        final rect = Rect.fromLTWH(
          offsetX + r * cellSize,
          offsetY + row * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPreviewPainter oldDelegate) {
    return oldDelegate.reels != reels || oldDelegate.rows != rows;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SYMBOL EDIT DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _SymbolEditDialog extends StatefulWidget {
  final Map<String, dynamic> symbol;
  final ValueChanged<Map<String, dynamic>> onSave;

  const _SymbolEditDialog({required this.symbol, required this.onSave});

  @override
  State<_SymbolEditDialog> createState() => _SymbolEditDialogState();
}

class _SymbolEditDialogState extends State<_SymbolEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _valueController;
  late String _type;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.symbol['name'] as String? ?? '');
    _valueController = TextEditingController(text: (widget.symbol['value'] as int? ?? 0).toString());
    _type = widget.symbol['symbol_type'] as String? ?? 'paying';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      title: const Text('Edit Symbol', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: _type,
            isExpanded: true,
            dropdownColor: FluxForgeTheme.surface,
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'wild', child: Text('Wild')),
              DropdownMenuItem(value: 'scatter', child: Text('Scatter')),
              DropdownMenuItem(value: 'bonus', child: Text('Bonus')),
              DropdownMenuItem(value: 'paying', child: Text('Paying')),
              DropdownMenuItem(value: 'blank', child: Text('Blank')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'paying'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Value'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final updated = Map<String, dynamic>.from(widget.symbol);
            updated['name'] = _nameController.text;
            updated['symbol_type'] = _type;
            updated['value'] = int.tryParse(_valueController.text) ?? 0;
            widget.onSave(updated);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMPORT JSON DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _ImportJsonDialog extends StatefulWidget {
  final ValueChanged<String> onImport;

  const _ImportJsonDialog({required this.onImport});

  @override
  State<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends State<_ImportJsonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      title: const Text('Import Model JSON', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400,
        height: 300,
        child: TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
          maxLines: null,
          expands: true,
          decoration: InputDecoration(
            hintText: 'Paste JSON here...',
            hintStyle: TextStyle(color: FluxForgeTheme.textMuted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onImport(_controller.text);
            Navigator.pop(context);
          },
          child: const Text('Import'),
        ),
      ],
    );
  }
}
