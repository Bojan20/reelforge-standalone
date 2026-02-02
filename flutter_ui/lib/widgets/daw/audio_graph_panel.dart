// audio_graph_panel.dart — Audio Graph Visualization Panel
// Part of P10.1.7 — Interactive node-based audio routing view

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/audio_graph_models.dart';
import '../../services/audio_graph_layout_engine.dart';
import '../../providers/mixer_provider.dart';
import 'audio_graph_painter.dart';

/// Interactive audio graph visualization panel
///
/// Features:
/// - Node-based visual routing (tracks, buses, inserts)
/// - Real-time PDC indicators
/// - Zoom/pan gestures (mouse wheel, drag)
/// - Multiple layout algorithms (hierarchical, force-directed, circular)
/// - Live metering on nodes
/// - Click to select, drag to move, right-click context menu
class AudioGraphPanel extends StatefulWidget {
  const AudioGraphPanel({super.key});

  @override
  State<AudioGraphPanel> createState() => _AudioGraphPanelState();
}

class _AudioGraphPanelState extends State<AudioGraphPanel> with SingleTickerProviderStateMixin {
  // Graph state
  AudioGraphState _graphState = const AudioGraphState();

  // Interaction state
  AudioGraphInteractionMode _interactionMode = AudioGraphInteractionMode.select;
  String? _draggedNodeId;
  Offset? _dragStartPosition;
  Offset? _panStartOffset;

  // Animation controller for smooth transitions
  late AnimationController _animationController;

  // Layout update timer
  DateTime _lastLayoutUpdate = DateTime.now();
  static const _layoutThrottleMs = 100;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Initial graph build will happen in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildGraph();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Rebuild graph from mixer provider
  void _rebuildGraph() {
    final mixerProvider = context.read<MixerProvider>();

    final nodes = <AudioGraphNode>[];
    final edges = <AudioGraphEdge>[];

    // Build audio track nodes
    for (final channel in mixerProvider.channels) {
      if (channel.type == ChannelType.audio) {
        nodes.add(AudioGraphNode(
          id: 'track_${channel.id}',
          label: channel.name,
          type: AudioGraphNodeType.audioTrack,
          position: Offset.zero,  // Will be positioned by layout
          isMuted: channel.muted,
          isSoloed: channel.soloed,
          outputLevel: channel.volume,
        ));

        // Add insert nodes for plugins (if track has non-empty inserts)
        final activeInserts = <int>[];
        for (int i = 0; i < channel.inserts.length; i++) {
          final insert = channel.inserts[i];
          if (insert.type != 'empty') {
            activeInserts.add(i);
            final insertNodeId = 'insert_${channel.id}_$i';

            nodes.add(AudioGraphNode(
              id: insertNodeId,
              label: insert.name,
              type: AudioGraphNodeType.insert,
              position: Offset.zero,
              isBypassed: insert.bypassed,
              pdcSamples: 0,  // TODO: Get from plugin metadata when available
            ));

            // Edge from previous (track or insert) to this insert
            final sourceId = activeInserts.length == 1
                ? 'track_${channel.id}'
                : 'insert_${channel.id}_${activeInserts[activeInserts.length - 2]}';
            edges.add(AudioGraphEdge(
              id: 'edge_${sourceId}_to_$insertNodeId',
              sourceNodeId: sourceId,
              targetNodeId: insertNodeId,
            ));
          }
        }

        // Add aux send edges
        for (final send in channel.sends) {
          if (send.enabled && send.level > 0.001) {
            final lastInsertId = channel.inserts.isEmpty
                ? 'track_${channel.id}'
                : 'insert_${channel.id}_${channel.inserts.length - 1}';

            edges.add(AudioGraphEdge(
              id: 'send_${channel.id}_to_${send.auxId}',
              sourceNodeId: lastInsertId,
              targetNodeId: 'bus_${send.auxId}',
              gain: send.level,
              isPreFader: send.preFader,
            ));
          }
        }

        // Main output routing
        final outputBusId = channel.outputBus ?? 'master';
        final lastNodeId = channel.inserts.isEmpty
            ? 'track_${channel.id}'
            : 'insert_${channel.id}_${channel.inserts.length - 1}';

        edges.add(AudioGraphEdge(
          id: 'output_${channel.id}_to_$outputBusId',
          sourceNodeId: lastNodeId,
          targetNodeId: 'bus_$outputBusId',
        ));
      }
    }

    // Build bus nodes
    for (final channel in mixerProvider.channels) {
      if (channel.type == ChannelType.bus || channel.type == ChannelType.aux || channel.type == ChannelType.master) {
        final nodeType = channel.type == ChannelType.master
            ? AudioGraphNodeType.master
            : channel.type == ChannelType.aux
                ? AudioGraphNodeType.aux
                : AudioGraphNodeType.bus;

        nodes.add(AudioGraphNode(
          id: 'bus_${channel.id}',
          label: channel.name,
          type: nodeType,
          position: Offset.zero,
          isMuted: channel.muted,
          isSoloed: channel.soloed,
          outputLevel: channel.volume,
        ));
      }
    }

    // Apply layout algorithm if auto-layout is enabled
    List<AudioGraphNode> layoutNodes = nodes;
    if (_graphState.autoLayout) {
      final now = DateTime.now();
      if (now.difference(_lastLayoutUpdate).inMilliseconds > _layoutThrottleMs) {
        layoutNodes = AudioGraphLayoutEngine.applyLayout(
          mode: _graphState.layoutMode,
          nodes: nodes,
          edges: edges,
          canvasSize: context.size ?? const Size(1200, 800),
        );
        _lastLayoutUpdate = now;
      }
    }

    setState(() {
      _graphState = _graphState.copyWith(
        nodes: layoutNodes,
        edges: edges,
      );
    });
  }

  /// Handle mouse wheel zoom
  void _handleScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta.dy;
    final zoomFactor = delta > 0 ? 0.9 : 1.1;
    final newZoom = (_graphState.zoomLevel * zoomFactor).clamp(0.25, 4.0);

    setState(() {
      _graphState = _graphState.copyWith(zoomLevel: newZoom);
    });
  }

  /// Handle pan gesture start
  void _handlePanStart(DragStartDetails details) {
    if (_interactionMode == AudioGraphInteractionMode.pan) {
      _panStartOffset = _graphState.panOffset;
    } else if (_interactionMode == AudioGraphInteractionMode.select) {
      // Check if clicking on a node
      final localPosition = details.localPosition;
      final graphPosition = _screenToGraphPosition(localPosition);

      final node = AudioGraphLayoutEngine.findNodeAtPoint(
        point: graphPosition,
        nodes: _graphState.nodes,
      );

      if (node != null) {
        _draggedNodeId = node.id;
        _dragStartPosition = graphPosition;

        // Select node
        setState(() {
          _graphState = _graphState.copyWith(
            nodes: _graphState.nodes.map((n) =>
              n.copyWith(isSelected: n.id == node.id)
            ).toList(),
          );
        });
      } else {
        // Clear selection
        setState(() {
          _graphState = _graphState.copyWith(
            nodes: _graphState.nodes.map((n) =>
              n.copyWith(isSelected: false)
            ).toList(),
            edges: _graphState.edges.map((e) =>
              e.copyWith(isSelected: false)
            ).toList(),
          );
        });
      }
    }
  }

  /// Handle pan gesture update
  void _handlePanUpdate(DragUpdateDetails details) {
    if (_interactionMode == AudioGraphInteractionMode.pan && _panStartOffset != null) {
      setState(() {
        _graphState = _graphState.copyWith(
          panOffset: _panStartOffset! + details.localPosition - details.globalPosition + details.globalPosition,
        );
      });
    } else if (_draggedNodeId != null && _dragStartPosition != null) {
      // Drag node
      final delta = details.delta / _graphState.zoomLevel;

      setState(() {
        _graphState = _graphState.copyWith(
          nodes: _graphState.nodes.map((n) {
            if (n.id == _draggedNodeId) {
              return n.copyWith(position: n.position + delta);
            }
            return n;
          }).toList(),
          autoLayout: false,  // Disable auto-layout when manually dragging
        );
      });
    }
  }

  /// Handle pan gesture end
  void _handlePanEnd(DragEndDetails details) {
    _panStartOffset = null;
    _draggedNodeId = null;
    _dragStartPosition = null;
  }

  /// Convert screen position to graph space
  Offset _screenToGraphPosition(Offset screenPos) {
    return (screenPos - _graphState.panOffset) / _graphState.zoomLevel;
  }

  /// Handle keyboard shortcuts
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Space: Toggle between select and pan modes
    if (event.logicalKey == LogicalKeyboardKey.space) {
      setState(() {
        _interactionMode = _interactionMode == AudioGraphInteractionMode.pan
            ? AudioGraphInteractionMode.select
            : AudioGraphInteractionMode.pan;
      });
      return KeyEventResult.handled;
    }

    // L: Change layout mode
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      final modes = AudioGraphLayoutMode.values;
      final currentIndex = modes.indexOf(_graphState.layoutMode);
      final nextMode = modes[(currentIndex + 1) % modes.length];

      setState(() {
        _graphState = _graphState.copyWith(
          layoutMode: nextMode,
          autoLayout: true,
        );
      });
      _rebuildGraph();
      return KeyEventResult.handled;
    }

    // Delete: Remove selected nodes
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final selectedIds = _graphState.nodes
          .where((n) => n.isSelected)
          .map((n) => n.id)
          .toSet();

      if (selectedIds.isNotEmpty) {
        setState(() {
          _graphState = _graphState.copyWith(
            nodes: _graphState.nodes.where((n) => !selectedIds.contains(n.id)).toList(),
            edges: _graphState.edges.where((e) =>
              !selectedIds.contains(e.sourceNodeId) && !selectedIds.contains(e.targetNodeId)
            ).toList(),
          );
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate PDC map
    final pdcMap = _graphState.calculatePDC();

    return Container(
      color: const Color(0xFF0a0a0c),
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: Stack(
          children: [
            // Main graph canvas
            Listener(
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent) {
                  _handleScroll(signal);
                }
              },
              child: GestureDetector(
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                child: CustomPaint(
                  painter: AudioGraphPainter(
                    graphState: _graphState,
                    pdcMap: pdcMap,
                    showPDCIndicators: true,
                    showMeters: true,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),

            // Top toolbar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildToolbar(),
            ),

            // Status bar (bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildStatusBar(),
            ),
          ],
        ),
      ),
    );
  }

  /// Build top toolbar with controls
  Widget _buildToolbar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withOpacity(0.95),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF242430), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Layout mode selector
          _buildLayoutModeButton(),

          const SizedBox(width: 16),

          // Auto-layout toggle
          _buildToggleButton(
            label: 'Auto Layout',
            value: _graphState.autoLayout,
            onChanged: (value) {
              setState(() {
                _graphState = _graphState.copyWith(autoLayout: value);
              });
              if (value) _rebuildGraph();
            },
          ),

          const SizedBox(width: 16),

          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white70, size: 20),
            onPressed: () {
              setState(() {
                _graphState = _graphState.copyWith(
                  zoomLevel: (_graphState.zoomLevel * 0.8).clamp(0.25, 4.0),
                );
              });
            },
            tooltip: 'Zoom Out',
          ),

          Text(
            '${(_graphState.zoomLevel * 100).round()}%',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),

          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
            onPressed: () {
              setState(() {
                _graphState = _graphState.copyWith(
                  zoomLevel: (_graphState.zoomLevel * 1.25).clamp(0.25, 4.0),
                );
              });
            },
            tooltip: 'Zoom In',
          ),

          const Spacer(),

          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
            onPressed: _rebuildGraph,
            tooltip: 'Rebuild Graph',
          ),
        ],
      ),
    );
  }

  /// Build layout mode dropdown button
  Widget _buildLayoutModeButton() {
    final modeNames = {
      AudioGraphLayoutMode.hierarchical: 'Hierarchical',
      AudioGraphLayoutMode.forceDirected: 'Force-Directed',
      AudioGraphLayoutMode.circular: 'Circular',
      AudioGraphLayoutMode.manual: 'Manual',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AudioGraphLayoutMode>(
          value: _graphState.layoutMode,
          dropdownColor: const Color(0xFF1a1a20),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: AudioGraphLayoutMode.values.map((mode) {
            return DropdownMenuItem(
              value: mode,
              child: Text(modeNames[mode] ?? mode.toString()),
            );
          }).toList(),
          onChanged: (mode) {
            if (mode != null) {
              setState(() {
                _graphState = _graphState.copyWith(
                  layoutMode: mode,
                  autoLayout: true,
                );
              });
              _rebuildGraph();
            }
          },
        ),
      ),
    );
  }

  /// Build toggle button widget
  Widget _buildToggleButton({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? const Color(0xFF4A9EFF) : const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Build status bar with info
  Widget _buildStatusBar() {
    final nodeCount = _graphState.nodes.length;
    final edgeCount = _graphState.edges.length;
    final selectedCount = _graphState.nodes.where((n) => n.isSelected).length;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF121216).withOpacity(0.95),
        border: const Border(
          top: BorderSide(color: Color(0xFF242430), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '$nodeCount nodes, $edgeCount edges',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),

          if (selectedCount > 0) ...[
            const SizedBox(width: 16),
            Text(
              '$selectedCount selected',
              style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 11),
            ),
          ],

          const Spacer(),

          Text(
            'Mode: ${_interactionMode.name}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),

          const SizedBox(width: 16),

          const Text(
            'Space: Pan | L: Layout | Delete: Remove',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
