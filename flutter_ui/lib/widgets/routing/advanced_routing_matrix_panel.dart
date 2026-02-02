// Advanced Routing Matrix Panel
//
// Professional audio routing matrix with:
// - Full track x bus matrix (clickable cells)
// - Send level sliders per cell
// - Pre/post fader toggles
// - Visual indicators for active routes
// - Bulk operations (route all drums to Drum bus)
// - Solo/Mute routing visualization

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/mixer_provider.dart';

// =============================================================================
// ROUTING CELL DATA
// =============================================================================

/// Represents the routing state of a single cell in the matrix
class RoutingCellData {
  final String sourceId;
  final String targetId;
  final bool isConnected;
  final double sendLevel;
  final bool preFader;
  final bool enabled;
  final bool isMuted;
  final bool isSoloed;

  const RoutingCellData({
    required this.sourceId,
    required this.targetId,
    this.isConnected = false,
    this.sendLevel = 1.0,
    this.preFader = false,
    this.enabled = true,
    this.isMuted = false,
    this.isSoloed = false,
  });

  RoutingCellData copyWith({
    bool? isConnected,
    double? sendLevel,
    bool? preFader,
    bool? enabled,
  }) {
    return RoutingCellData(
      sourceId: sourceId,
      targetId: targetId,
      isConnected: isConnected ?? this.isConnected,
      sendLevel: sendLevel ?? this.sendLevel,
      preFader: preFader ?? this.preFader,
      enabled: enabled ?? this.enabled,
      isMuted: isMuted,
      isSoloed: isSoloed,
    );
  }
}

// =============================================================================
// BULK OPERATION TYPE
// =============================================================================

/// Types of bulk routing operations
enum BulkRoutingOperation {
  /// Connect all selected sources to target
  connectAll,
  /// Disconnect all selected sources from target
  disconnectAll,
  /// Set all send levels to value
  setAllLevels,
  /// Set all to pre-fader
  setAllPreFader,
  /// Set all to post-fader
  setAllPostFader,
}

// =============================================================================
// ADVANCED ROUTING MATRIX PANEL
// =============================================================================

class AdvancedRoutingMatrixPanel extends StatefulWidget {
  /// Callback when a route is toggled
  final void Function(String sourceId, String targetId, bool connected)? onRouteToggle;

  /// Callback when send level changes
  final void Function(String sourceId, String targetId, double level)? onSendLevelChange;

  /// Callback when pre/post fader is toggled
  final void Function(String sourceId, String targetId, bool preFader)? onPreFaderToggle;

  const AdvancedRoutingMatrixPanel({
    super.key,
    this.onRouteToggle,
    this.onSendLevelChange,
    this.onPreFaderToggle,
  });

  @override
  State<AdvancedRoutingMatrixPanel> createState() => _AdvancedRoutingMatrixPanelState();
}

class _AdvancedRoutingMatrixPanelState extends State<AdvancedRoutingMatrixPanel> {
  // Selection state
  final Set<String> _selectedSources = {};
  String? _selectedTarget;

  // View options
  bool _showSendLevels = true;
  bool _showMuteState = true;
  bool _compactMode = false;

  // Hover state
  String? _hoveredSourceId;
  String? _hoveredTargetId;

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, _) {
        final channels = mixer.channels;
        final buses = mixer.buses;

        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              _buildToolbar(mixer),
              Expanded(
                child: _buildMatrix(channels, buses, mixer),
              ),
              _buildStatusBar(channels, buses),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // TOOLBAR
  // ===========================================================================

  Widget _buildToolbar(MixerProvider mixer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.grid_on, color: FluxForgeTheme.accentBlue, size: 16),
          const SizedBox(width: 8),
          const Text(
            'ADVANCED ROUTING',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 16),

          // View toggles
          _buildToggleButton(
            'Sends',
            _showSendLevels,
            (v) => setState(() => _showSendLevels = v),
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            'M/S',
            _showMuteState,
            (v) => setState(() => _showMuteState = v),
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            'Compact',
            _compactMode,
            (v) => setState(() => _compactMode = v),
          ),

          const Spacer(),

          // Bulk operations
          if (_selectedSources.isNotEmpty && _selectedTarget != null) ...[
            _buildBulkButton('Route All', Icons.check, () {
              _performBulkOperation(BulkRoutingOperation.connectAll, mixer);
            }),
            const SizedBox(width: 4),
            _buildBulkButton('Clear All', Icons.clear, () {
              _performBulkOperation(BulkRoutingOperation.disconnectAll, mixer);
            }),
            const SizedBox(width: 4),
            _buildBulkButton('Pre', Icons.arrow_upward, () {
              _performBulkOperation(BulkRoutingOperation.setAllPreFader, mixer);
            }),
            const SizedBox(width: 4),
            _buildBulkButton('Post', Icons.arrow_forward, () {
              _performBulkOperation(BulkRoutingOperation.setAllPostFader, mixer);
            }),
          ],

          // Clear selection
          if (_selectedSources.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.deselect, size: 16),
              color: FluxForgeTheme.textSecondary,
              tooltip: 'Clear Selection',
              onPressed: () => setState(() {
                _selectedSources.clear();
                _selectedTarget = null;
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: value ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBulkButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.accentGreen),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: FluxForgeTheme.accentGreen),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MATRIX
  // ===========================================================================

  Widget _buildMatrix(
    List<MixerChannel> channels,
    List<MixerChannel> buses,
    MixerProvider mixer,
  ) {
    final cellSize = _compactMode ? 36.0 : 52.0;
    final headerWidth = _compactMode ? 70.0 : 90.0;
    final headerHeight = _compactMode ? 28.0 : 36.0;

    // Include master as a target
    final targets = [
      ...buses,
      mixer.master,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row (target names)
              Row(
                children: [
                  // Corner cell with select all
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_selectedSources.length == channels.length) {
                        _selectedSources.clear();
                      } else {
                        _selectedSources.addAll(channels.map((c) => c.id));
                      }
                    }),
                    child: Container(
                      width: headerWidth,
                      height: headerHeight,
                      decoration: BoxDecoration(
                        color: _selectedSources.isNotEmpty
                            ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                            : FluxForgeTheme.bgMid,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedSources.length == channels.length
                                  ? Icons.check_box
                                  : _selectedSources.isNotEmpty
                                      ? Icons.indeterminate_check_box
                                      : Icons.check_box_outline_blank,
                              size: 14,
                              color: FluxForgeTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'SRC',
                              style: TextStyle(
                                color: FluxForgeTheme.textSecondary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Target headers
                  ...targets.map((target) => _buildTargetHeader(
                        target,
                        cellSize,
                        headerHeight,
                      )),
                ],
              ),

              // Source rows
              ...channels.map((channel) => _buildSourceRow(
                    channel,
                    targets,
                    cellSize,
                    headerWidth,
                    mixer,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetHeader(MixerChannel target, double cellSize, double headerHeight) {
    final isHovered = _hoveredTargetId == target.id;
    final isSelected = _selectedTarget == target.id;
    final isMaster = target.type == ChannelType.master;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedTarget = _selectedTarget == target.id ? null : target.id;
      }),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredTargetId = target.id),
        onExit: (_) => setState(() => _hoveredTargetId = null),
        child: Container(
          width: cellSize,
          height: headerHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? target.color.withValues(alpha: 0.3)
                : isHovered
                    ? target.color.withValues(alpha: 0.15)
                    : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? target.color
                  : isHovered
                      ? target.color.withValues(alpha: 0.6)
                      : FluxForgeTheme.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isMaster ? 'MST' : (target.type == ChannelType.aux ? 'AUX' : 'BUS'),
                style: TextStyle(
                  color: target.color.withValues(alpha: 0.7),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                target.name,
                style: TextStyle(
                  color: isSelected || isHovered
                      ? target.color
                      : FluxForgeTheme.textPrimary,
                  fontSize: _compactMode ? 8 : 9,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (_showMuteState && (target.muted || target.soloed))
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (target.muted)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentRed.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'M',
                          style: TextStyle(
                            color: FluxForgeTheme.accentRed,
                            fontSize: 7,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (target.soloed)
                      Container(
                        margin: const EdgeInsets.only(top: 2, left: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'S',
                          style: TextStyle(
                            color: FluxForgeTheme.accentOrange,
                            fontSize: 7,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceRow(
    MixerChannel channel,
    List<MixerChannel> targets,
    double cellSize,
    double headerWidth,
    MixerProvider mixer,
  ) {
    final isHovered = _hoveredSourceId == channel.id;
    final isSelected = _selectedSources.contains(channel.id);

    return Row(
      children: [
        // Source header with checkbox
        GestureDetector(
          onTap: () => setState(() {
            if (_selectedSources.contains(channel.id)) {
              _selectedSources.remove(channel.id);
            } else {
              _selectedSources.add(channel.id);
            }
          }),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredSourceId = channel.id),
            onExit: (_) => setState(() => _hoveredSourceId = null),
            child: Container(
              width: headerWidth,
              height: cellSize,
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? channel.color.withValues(alpha: 0.2)
                    : isHovered
                        ? FluxForgeTheme.bgMid
                        : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? channel.color
                      : isHovered
                          ? channel.color.withValues(alpha: 0.5)
                          : FluxForgeTheme.borderSubtle,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Checkbox
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 14,
                      color: isSelected ? channel.color : FluxForgeTheme.textSecondary,
                    ),
                  ),
                  // Color bar
                  Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: channel.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Name and status
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.name,
                          style: TextStyle(
                            color: isSelected || isHovered
                                ? FluxForgeTheme.textPrimary
                                : FluxForgeTheme.textSecondary,
                            fontSize: _compactMode ? 9 : 10,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_showMuteState && (channel.muted || channel.soloed))
                          Row(
                            children: [
                              if (channel.muted)
                                const Text(
                                  'M',
                                  style: TextStyle(
                                    color: FluxForgeTheme.accentRed,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (channel.soloed)
                                Padding(
                                  padding: EdgeInsets.only(left: channel.muted ? 2 : 0),
                                  child: const Text(
                                    'S',
                                    style: TextStyle(
                                      color: FluxForgeTheme.accentOrange,
                                      fontSize: 7,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Routing cells
        ...targets.map((target) => _buildRoutingCell(
              channel,
              target,
              cellSize,
              mixer,
            )),
      ],
    );
  }

  Widget _buildRoutingCell(
    MixerChannel source,
    MixerChannel target,
    double cellSize,
    MixerProvider mixer,
  ) {
    final isConnected = source.outputBus == target.id ||
        source.sends.any((s) => s.auxId == target.id && s.enabled);
    final isHovered = _hoveredSourceId == source.id || _hoveredTargetId == target.id;
    final isAux = target.type == ChannelType.aux;
    final isMaster = target.type == ChannelType.master;

    // Get send info for aux connections
    final send = source.sends.where((s) => s.auxId == target.id).firstOrNull;
    final sendLevel = send?.level ?? 0.0;
    final preFader = send?.preFader ?? false;

    // Determine effective connection state
    final effectiveConnected = isConnected && (!isAux || (send?.enabled ?? false));

    return GestureDetector(
      onTap: () => _handleCellTap(source, target, isConnected, mixer),
      onLongPress: isAux && effectiveConnected
          ? () => _showSendLevelDialog(source, target, sendLevel, preFader)
          : null,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredSourceId = source.id;
          _hoveredTargetId = target.id;
        }),
        onExit: (_) => setState(() {
          _hoveredSourceId = null;
          _hoveredTargetId = null;
        }),
        child: Container(
          width: cellSize,
          height: cellSize,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: effectiveConnected
                ? (isAux
                    ? target.color.withValues(alpha: 0.25)
                    : source.color.withValues(alpha: 0.25))
                : isHovered
                    ? FluxForgeTheme.bgMid
                    : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: effectiveConnected
                  ? (isAux ? target.color : source.color)
                  : isHovered
                      ? FluxForgeTheme.textSecondary.withValues(alpha: 0.4)
                      : FluxForgeTheme.borderSubtle,
              width: effectiveConnected ? 2 : 1,
            ),
          ),
          child: effectiveConnected
              ? _buildCellContent(source, target, sendLevel, preFader, isAux, isMaster, cellSize)
              : null,
        ),
      ),
    );
  }

  Widget _buildCellContent(
    MixerChannel source,
    MixerChannel target,
    double sendLevel,
    bool preFader,
    bool isAux,
    bool isMaster,
    double cellSize,
  ) {
    if (isAux && _showSendLevels) {
      // Show send level indicator for aux
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            preFader ? Icons.arrow_upward : Icons.arrow_forward,
            size: cellSize * 0.22,
            color: target.color,
          ),
          const SizedBox(height: 2),
          Text(
            '${(sendLevel * 100).toInt()}%',
            style: TextStyle(
              color: target.color,
              fontSize: cellSize * 0.18,
              fontWeight: FontWeight.w600,
            ),
          ),
          // Mini level bar
          Container(
            width: cellSize * 0.6,
            height: 3,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: target.color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(1.5),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: sendLevel.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: target.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ],
      );
    } else if (isMaster) {
      // Master output indicator
      return Center(
        child: Icon(
          Icons.speaker,
          size: cellSize * 0.4,
          color: source.color,
        ),
      );
    } else {
      // Simple checkmark for direct routes
      return Center(
        child: Icon(
          Icons.check,
          size: cellSize * 0.4,
          color: source.color,
        ),
      );
    }
  }

  void _handleCellTap(
    MixerChannel source,
    MixerChannel target,
    bool currentlyConnected,
    MixerProvider mixer,
  ) {
    final isAux = target.type == ChannelType.aux;
    final isMaster = target.type == ChannelType.master;

    if (isAux) {
      // Toggle aux send
      final existingSend = source.sends.where((s) => s.auxId == target.id).firstOrNull;
      if (existingSend != null) {
        mixer.toggleAuxSendEnabled(source.id, target.id);
      } else {
        mixer.setAuxSendLevel(source.id, target.id, 0.7); // Default level
      }
      widget.onRouteToggle?.call(source.id, target.id, existingSend == null);
    } else if (!isMaster) {
      // Toggle direct output routing
      final newOutput = currentlyConnected ? 'master' : target.id;
      mixer.setChannelOutput(source.id, newOutput);
      widget.onRouteToggle?.call(source.id, target.id, !currentlyConnected);
    }
    // Master is always the final destination, don't toggle
  }

  void _showSendLevelDialog(
    MixerChannel source,
    MixerChannel target,
    double currentLevel,
    bool currentPreFader,
  ) {
    double tempLevel = currentLevel;
    bool tempPreFader = currentPreFader;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 24,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: source.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Text(
                '${source.name} -> ${target.name}',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Send level
              const Text(
                'SEND LEVEL',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        activeTrackColor: target.color,
                        inactiveTrackColor: target.color.withValues(alpha: 0.3),
                        thumbColor: target.color,
                      ),
                      child: Slider(
                        value: tempLevel,
                        onChanged: (v) => setDialogState(() => tempLevel = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(tempLevel * 100).toInt()}%',
                      style: TextStyle(
                        color: target.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Pre/Post fader toggle
              const Text(
                'FADER POSITION',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildFaderToggle(
                    'PRE',
                    Icons.arrow_upward,
                    tempPreFader,
                    () => setDialogState(() => tempPreFader = true),
                    target.color,
                  ),
                  const SizedBox(width: 8),
                  _buildFaderToggle(
                    'POST',
                    Icons.arrow_forward,
                    !tempPreFader,
                    () => setDialogState(() => tempPreFader = false),
                    target.color,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final mixer = context.read<MixerProvider>();
              mixer.setAuxSendLevel(source.id, target.id, tempLevel);
              if (tempPreFader != currentPreFader) {
                mixer.toggleAuxSendPreFader(source.id, target.id);
              }
              widget.onSendLevelChange?.call(source.id, target.id, tempLevel);
              widget.onPreFaderToggle?.call(source.id, target.id, tempPreFader);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: target.color,
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildFaderToggle(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color : FluxForgeTheme.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? color : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _performBulkOperation(BulkRoutingOperation operation, MixerProvider mixer) {
    if (_selectedSources.isEmpty || _selectedTarget == null) return;

    for (final sourceId in _selectedSources) {
      switch (operation) {
        case BulkRoutingOperation.connectAll:
          final channel = mixer.getChannel(sourceId);
          if (channel != null) {
            final target = mixer.getBus(_selectedTarget!);
            if (target?.type == ChannelType.aux) {
              mixer.setAuxSendLevel(sourceId, _selectedTarget!, 0.7);
            } else if (target != null) {
              mixer.setChannelOutput(sourceId, _selectedTarget!);
            }
          }
          break;

        case BulkRoutingOperation.disconnectAll:
          final channel = mixer.getChannel(sourceId);
          if (channel != null) {
            final target = mixer.getBus(_selectedTarget!);
            if (target?.type == ChannelType.aux) {
              final send = channel.sends.where((s) => s.auxId == _selectedTarget).firstOrNull;
              if (send != null) {
                mixer.toggleAuxSendEnabled(sourceId, _selectedTarget!);
              }
            } else if (channel.outputBus == _selectedTarget) {
              mixer.setChannelOutput(sourceId, 'master');
            }
          }
          break;

        case BulkRoutingOperation.setAllLevels:
          // Would need level parameter
          break;

        case BulkRoutingOperation.setAllPreFader:
          final channel = mixer.getChannel(sourceId);
          if (channel != null) {
            final send = channel.sends.where((s) => s.auxId == _selectedTarget).firstOrNull;
            if (send != null && !send.preFader) {
              mixer.toggleAuxSendPreFader(sourceId, _selectedTarget!);
            }
          }
          break;

        case BulkRoutingOperation.setAllPostFader:
          final channel = mixer.getChannel(sourceId);
          if (channel != null) {
            final send = channel.sends.where((s) => s.auxId == _selectedTarget).firstOrNull;
            if (send != null && send.preFader) {
              mixer.toggleAuxSendPreFader(sourceId, _selectedTarget!);
            }
          }
          break;
      }
    }
  }

  // ===========================================================================
  // STATUS BAR
  // ===========================================================================

  Widget _buildStatusBar(List<MixerChannel> channels, List<MixerChannel> buses) {
    int connectionCount = 0;
    for (final channel in channels) {
      if (channel.outputBus != null && channel.outputBus != 'master') {
        connectionCount++;
      }
      connectionCount += channel.sends.where((s) => s.enabled).length;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(Icons.check, 'Direct', FluxForgeTheme.accentGreen),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.arrow_forward, 'Post-Fader', FluxForgeTheme.accentCyan),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.arrow_upward, 'Pre-Fader', FluxForgeTheme.accentOrange),
          const SizedBox(width: 24),
          Text(
            '${channels.length} sources | ${buses.length + 1} targets | $connectionCount routes',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
          if (_selectedSources.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_selectedSources.length} selected',
                style: const TextStyle(
                  color: FluxForgeTheme.accentBlue,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
