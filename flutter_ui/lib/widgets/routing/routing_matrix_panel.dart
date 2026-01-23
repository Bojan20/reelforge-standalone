// Routing Matrix Panel (P3.14)
//
// Visual routing matrix for audio signal flow:
// - Tracks (rows) → Buses (columns)
// - Click to route/unroute
// - Volume faders at intersections
// - Bus sends visualization
// - Drag-to-connect interface

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// ROUTING DATA MODELS
// =============================================================================

/// Routing node type
enum RoutingNodeType {
  track,
  bus,
  aux,
  master,
}

/// A node in the routing graph
class RoutingNode {
  final int id;
  final String name;
  final RoutingNodeType type;
  final double volume;
  final double pan;
  final bool muted;
  final bool soloed;
  final Color color;

  const RoutingNode({
    required this.id,
    required this.name,
    required this.type,
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.color = const Color(0xFF4A9EFF),
  });

  RoutingNode copyWith({
    String? name,
    double? volume,
    double? pan,
    bool? muted,
    bool? soloed,
    Color? color,
  }) =>
      RoutingNode(
        id: id,
        name: name ?? this.name,
        type: type,
        volume: volume ?? this.volume,
        pan: pan ?? this.pan,
        muted: muted ?? this.muted,
        soloed: soloed ?? this.soloed,
        color: color ?? this.color,
      );

  String get typeLabel => switch (type) {
        RoutingNodeType.track => 'TRK',
        RoutingNodeType.bus => 'BUS',
        RoutingNodeType.aux => 'AUX',
        RoutingNodeType.master => 'MST',
      };
}

/// A connection between nodes
class RoutingConnection {
  final int sourceId;
  final int targetId;
  final double sendLevel;
  final bool preFader;
  final bool enabled;

  const RoutingConnection({
    required this.sourceId,
    required this.targetId,
    this.sendLevel = 1.0,
    this.preFader = false,
    this.enabled = true,
  });

  RoutingConnection copyWith({
    double? sendLevel,
    bool? preFader,
    bool? enabled,
  }) =>
      RoutingConnection(
        sourceId: sourceId,
        targetId: targetId,
        sendLevel: sendLevel ?? this.sendLevel,
        preFader: preFader ?? this.preFader,
        enabled: enabled ?? this.enabled,
      );
}

// =============================================================================
// ROUTING MATRIX PANEL
// =============================================================================

class RoutingMatrixPanel extends StatefulWidget {
  const RoutingMatrixPanel({super.key});

  @override
  State<RoutingMatrixPanel> createState() => _RoutingMatrixPanelState();
}

class _RoutingMatrixPanelState extends State<RoutingMatrixPanel> {
  // Demo data
  late List<RoutingNode> _tracks;
  late List<RoutingNode> _buses;
  late List<RoutingConnection> _connections;
  late RoutingNode _master;

  // UI state
  int? _hoveredTrackId;
  int? _hoveredBusId;
  int? _selectedTrackId;
  bool _showSendLevels = true;
  bool _compactMode = false;

  @override
  void initState() {
    super.initState();
    _initDemoData();
  }

  void _initDemoData() {
    // Create demo tracks
    _tracks = [
      const RoutingNode(id: 0, name: 'Kick', type: RoutingNodeType.track, color: Color(0xFFFF5252)),
      const RoutingNode(id: 1, name: 'Snare', type: RoutingNodeType.track, color: Color(0xFFFF9800)),
      const RoutingNode(id: 2, name: 'HiHat', type: RoutingNodeType.track, color: Color(0xFFFFEB3B)),
      const RoutingNode(id: 3, name: 'Bass', type: RoutingNodeType.track, color: Color(0xFF4CAF50)),
      const RoutingNode(id: 4, name: 'Synth', type: RoutingNodeType.track, color: Color(0xFF2196F3)),
      const RoutingNode(id: 5, name: 'Vocal', type: RoutingNodeType.track, color: Color(0xFF9C27B0)),
      const RoutingNode(id: 6, name: 'FX', type: RoutingNodeType.track, color: Color(0xFF00BCD4)),
      const RoutingNode(id: 7, name: 'Pad', type: RoutingNodeType.track, color: Color(0xFFE91E63)),
    ];

    // Create buses
    _buses = [
      const RoutingNode(id: 100, name: 'Drums', type: RoutingNodeType.bus, color: Color(0xFFFF9800)),
      const RoutingNode(id: 101, name: 'Music', type: RoutingNodeType.bus, color: Color(0xFF4CAF50)),
      const RoutingNode(id: 102, name: 'Voice', type: RoutingNodeType.bus, color: Color(0xFF9C27B0)),
      const RoutingNode(id: 103, name: 'Reverb', type: RoutingNodeType.aux, color: Color(0xFF00BCD4)),
      const RoutingNode(id: 104, name: 'Delay', type: RoutingNodeType.aux, color: Color(0xFF2196F3)),
    ];

    _master = const RoutingNode(
      id: 999,
      name: 'Master',
      type: RoutingNodeType.master,
      color: Color(0xFFFFFFFF),
    );

    // Create connections (track → bus)
    _connections = [
      const RoutingConnection(sourceId: 0, targetId: 100), // Kick → Drums
      const RoutingConnection(sourceId: 1, targetId: 100), // Snare → Drums
      const RoutingConnection(sourceId: 2, targetId: 100), // HiHat → Drums
      const RoutingConnection(sourceId: 3, targetId: 101), // Bass → Music
      const RoutingConnection(sourceId: 4, targetId: 101), // Synth → Music
      const RoutingConnection(sourceId: 5, targetId: 102), // Vocal → Voice
      const RoutingConnection(sourceId: 6, targetId: 101), // FX → Music
      const RoutingConnection(sourceId: 7, targetId: 101), // Pad → Music
      // Sends to aux
      const RoutingConnection(sourceId: 5, targetId: 103, sendLevel: 0.4, preFader: false), // Vocal → Reverb
      const RoutingConnection(sourceId: 4, targetId: 104, sendLevel: 0.3, preFader: false), // Synth → Delay
      const RoutingConnection(sourceId: 7, targetId: 103, sendLevel: 0.5, preFader: false), // Pad → Reverb
    ];
  }

  bool _hasConnection(int trackId, int busId) {
    return _connections.any((c) => c.sourceId == trackId && c.targetId == busId && c.enabled);
  }

  RoutingConnection? _getConnection(int trackId, int busId) {
    try {
      return _connections.firstWhere((c) => c.sourceId == trackId && c.targetId == busId);
    } catch (_) {
      return null;
    }
  }

  void _toggleConnection(int trackId, int busId) {
    setState(() {
      final existingIdx = _connections.indexWhere(
        (c) => c.sourceId == trackId && c.targetId == busId,
      );

      if (existingIdx >= 0) {
        // Toggle existing
        final existing = _connections[existingIdx];
        _connections[existingIdx] = existing.copyWith(enabled: !existing.enabled);
      } else {
        // Create new
        _connections.add(RoutingConnection(
          sourceId: trackId,
          targetId: busId,
        ));
      }
    });
  }

  void _updateSendLevel(int trackId, int busId, double level) {
    setState(() {
      final idx = _connections.indexWhere(
        (c) => c.sourceId == trackId && c.targetId == busId,
      );
      if (idx >= 0) {
        _connections[idx] = _connections[idx].copyWith(sendLevel: level);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildMatrix(),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
          Icon(Icons.route, color: FluxForgeTheme.accentBlue, size: 16),
          const SizedBox(width: 8),
          const Text(
            'ROUTING MATRIX',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Show send levels toggle
          _buildToggle(
            'Sends',
            _showSendLevels,
            (v) => setState(() => _showSendLevels = v),
          ),
          const SizedBox(width: 8),
          // Compact mode toggle
          _buildToggle(
            'Compact',
            _compactMode,
            (v) => setState(() => _compactMode = v),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
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

  Widget _buildMatrix() {
    final cellSize = _compactMode ? 32.0 : 48.0;
    final headerWidth = _compactMode ? 60.0 : 80.0;
    final headerHeight = _compactMode ? 24.0 : 32.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row (bus names)
              Row(
                children: [
                  // Corner cell
                  SizedBox(
                    width: headerWidth,
                    height: headerHeight,
                    child: Center(
                      child: Text(
                        'TRACK → BUS',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Bus headers
                  ..._buses.map((bus) => _buildBusHeader(bus, cellSize, headerHeight)),
                  // Master header
                  _buildBusHeader(_master, cellSize, headerHeight),
                ],
              ),

              // Track rows
              ..._tracks.map((track) => _buildTrackRow(track, cellSize, headerWidth)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusHeader(RoutingNode bus, double cellSize, double headerHeight) {
    final isHovered = _hoveredBusId == bus.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredBusId = bus.id),
      onExit: (_) => setState(() => _hoveredBusId = null),
      child: Container(
        width: cellSize,
        height: headerHeight,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isHovered
              ? bus.color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isHovered ? bus.color : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              bus.typeLabel,
              style: TextStyle(
                color: bus.color.withValues(alpha: 0.7),
                fontSize: 7,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              bus.name,
              style: TextStyle(
                color: isHovered ? bus.color : FluxForgeTheme.textPrimary,
                fontSize: _compactMode ? 8 : 9,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(RoutingNode track, double cellSize, double headerWidth) {
    final isHovered = _hoveredTrackId == track.id;
    final isSelected = _selectedTrackId == track.id;

    return Row(
      children: [
        // Track header
        MouseRegion(
          onEnter: (_) => setState(() => _hoveredTrackId = track.id),
          onExit: (_) => setState(() => _hoveredTrackId = null),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedTrackId = _selectedTrackId == track.id ? null : track.id;
            }),
            child: Container(
              width: headerWidth,
              height: cellSize,
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? track.color.withValues(alpha: 0.2)
                    : isHovered
                        ? FluxForgeTheme.bgMid
                        : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? track.color
                      : isHovered
                          ? track.color.withValues(alpha: 0.5)
                          : FluxForgeTheme.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  // Color bar
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: track.color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomLeft: Radius.circular(3),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        track.name,
                        style: TextStyle(
                          color: isSelected || isHovered
                              ? FluxForgeTheme.textPrimary
                              : FluxForgeTheme.textSecondary,
                          fontSize: _compactMode ? 9 : 10,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Connection cells
        ..._buses.map((bus) => _buildConnectionCell(track, bus, cellSize)),

        // Master connection
        _buildConnectionCell(track, _master, cellSize, isMasterBus: true),
      ],
    );
  }

  Widget _buildConnectionCell(RoutingNode track, RoutingNode bus, double cellSize,
      {bool isMasterBus = false}) {
    final connection = _getConnection(track.id, bus.id);
    final hasConnection = connection != null && connection.enabled;
    final isAux = bus.type == RoutingNodeType.aux;
    final isHovered = _hoveredTrackId == track.id || _hoveredBusId == bus.id;

    final connectionForDialog = connection; // Capture for closure
    return GestureDetector(
      onTap: () => _toggleConnection(track.id, bus.id),
      onLongPress: isAux && hasConnection && connectionForDialog != null
          ? () => _showSendLevelDialog(track, bus, connectionForDialog)
          : null,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredTrackId = track.id;
          _hoveredBusId = bus.id;
        }),
        onExit: (_) => setState(() {
          _hoveredTrackId = null;
          _hoveredBusId = null;
        }),
        child: Container(
          width: cellSize,
          height: cellSize,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: hasConnection
                ? (isAux ? bus.color.withValues(alpha: 0.3) : track.color.withValues(alpha: 0.3))
                : isHovered
                    ? FluxForgeTheme.bgMid
                    : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: hasConnection
                  ? (isAux ? bus.color : track.color)
                  : isHovered
                      ? FluxForgeTheme.textSecondary.withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle,
              width: hasConnection ? 2 : 1,
            ),
          ),
          child: hasConnection && connectionForDialog != null
              ? _buildConnectionContent(track, bus, connectionForDialog, cellSize, isAux)
              : null,
        ),
      ),
    );
  }

  Widget _buildConnectionContent(
    RoutingNode track,
    RoutingNode bus,
    RoutingConnection connection,
    double cellSize,
    bool isAux,
  ) {
    if (isAux && _showSendLevels) {
      // Show send level for aux buses
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            connection.preFader ? Icons.arrow_upward : Icons.arrow_forward,
            size: cellSize * 0.25,
            color: bus.color,
          ),
          Text(
            '${(connection.sendLevel * 100).toInt()}%',
            style: TextStyle(
              color: bus.color,
              fontSize: cellSize * 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    } else {
      // Show simple connection indicator
      return Center(
        child: Icon(
          Icons.check,
          size: cellSize * 0.4,
          color: track.color,
        ),
      );
    }
  }

  void _showSendLevelDialog(RoutingNode track, RoutingNode bus, RoutingConnection connection) {
    double tempLevel = connection.sendLevel;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        title: Text(
          '${track.name} → ${bus.name}',
          style: const TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Send Level',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            StatefulBuilder(
              builder: (context, setDialogState) => Column(
                children: [
                  Slider(
                    value: tempLevel,
                    onChanged: (v) => setDialogState(() => tempLevel = v),
                    activeColor: bus.color,
                    inactiveColor: bus.color.withValues(alpha: 0.3),
                  ),
                  Text(
                    '${(tempLevel * 100).toInt()}%',
                    style: TextStyle(
                      color: bus.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
              _updateSendLevel(track.id, bus.id, tempLevel);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: bus.color,
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
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
          _buildLegendItem(Icons.check, 'Direct Route', FluxForgeTheme.accentGreen),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.arrow_forward, 'Send (Post)', FluxForgeTheme.accentCyan),
          const SizedBox(width: 16),
          _buildLegendItem(Icons.arrow_upward, 'Send (Pre)', FluxForgeTheme.accentOrange),
          const SizedBox(width: 16),
          Text(
            '${_tracks.length} tracks · ${_buses.length} buses · ${_connections.where((c) => c.enabled).length} connections',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
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
