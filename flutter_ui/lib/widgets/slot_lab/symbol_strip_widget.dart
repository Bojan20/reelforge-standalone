/// Symbol Strip Widget
///
/// V6 Layout: Left panel showing:
/// - SYMBOLS section: expandable symbol items with context audio slots
/// - MUSIC LAYERS section: expandable contexts with L1-L5 layer slots
///
/// Supports drag-drop audio assignment from browser.

import 'package:flutter/material.dart';
import '../../models/auto_event_builder_models.dart';
import '../../models/slot_lab_models.dart';
import '../../theme/fluxforge_theme.dart';

/// Main Symbol Strip Widget
class SymbolStripWidget extends StatefulWidget {
  final List<SymbolDefinition> symbols;
  final List<ContextDefinition> contexts;
  final List<SymbolAudioAssignment> symbolAudio;
  final List<MusicLayerAssignment> musicLayers;
  final Function(String symbolId, String context, String audioPath)? onSymbolAudioDrop;
  final Function(String contextId, int layer, String audioPath)? onMusicLayerDrop;
  final Function(String symbolId, String context)? onSymbolAudioClear;
  final Function(String contextId, int layer)? onMusicLayerClear;
  final Function()? onAddSymbol;
  final Function()? onAddContext;

  const SymbolStripWidget({
    super.key,
    required this.symbols,
    required this.contexts,
    this.symbolAudio = const [],
    this.musicLayers = const [],
    this.onSymbolAudioDrop,
    this.onMusicLayerDrop,
    this.onSymbolAudioClear,
    this.onMusicLayerClear,
    this.onAddSymbol,
    this.onAddContext,
  });

  @override
  State<SymbolStripWidget> createState() => _SymbolStripWidgetState();
}

class _SymbolStripWidgetState extends State<SymbolStripWidget> {
  final Set<String> _expandedSymbols = {};
  final Set<String> _expandedContexts = {'base'}; // Base expanded by default

  String? _getSymbolAudioPath(String symbolId, String context) {
    final assignment = widget.symbolAudio.where(
      (a) => a.symbolId == symbolId && a.context == context,
    );
    return assignment.isNotEmpty ? assignment.first.audioPath : null;
  }

  String? _getMusicLayerPath(String contextId, int layer) {
    final assignment = widget.musicLayers.where(
      (a) => a.contextId == contextId && a.layer == layer,
    );
    return assignment.isNotEmpty ? assignment.first.audioPath : null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // SYMBOLS section
                  _buildSectionHeader('SYMBOLS', widget.onAddSymbol),
                  ...widget.symbols.map(_buildSymbolItem),
                  const SizedBox(height: 16),
                  // MUSIC LAYERS section
                  _buildSectionHeader('MUSIC LAYERS', widget.onAddContext),
                  ...widget.contexts.map(_buildContextItem),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.casino, size: 14, color: Colors.white54),
          SizedBox(width: 6),
          Text(
            'Symbol Strip',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onAdd) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF16161C),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white38,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              child: const Icon(Icons.add, size: 14, color: Colors.white38),
            ),
        ],
      ),
    );
  }

  Widget _buildSymbolItem(SymbolDefinition symbol) {
    final isExpanded = _expandedSymbols.contains(symbol.id);
    final hasAudio = widget.symbolAudio.any((a) => a.symbolId == symbol.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Symbol header row
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedSymbols.remove(symbol.id);
              } else {
                _expandedSymbols.add(symbol.id);
              }
            });
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                // Symbol emoji/icon
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _symbolTypeColor(symbol.type).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    symbol.emoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    symbol.name,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Audio indicator
                if (hasAudio)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Expanded context slots
        if (isExpanded)
          Container(
            color: const Color(0xFF0A0A0E),
            padding: const EdgeInsets.only(left: 24, right: 8, top: 4, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: symbol.contexts.map((ctx) {
                final audioPath = _getSymbolAudioPath(symbol.id, ctx);
                return _buildAudioSlot(
                  label: ctx.toUpperCase(),
                  audioPath: audioPath,
                  onDrop: (path) => widget.onSymbolAudioDrop?.call(symbol.id, ctx, path),
                  onClear: audioPath != null
                      ? () => widget.onSymbolAudioClear?.call(symbol.id, ctx)
                      : null,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildContextItem(ContextDefinition context) {
    final isExpanded = _expandedContexts.contains(context.id);
    final hasAudio = widget.musicLayers.any((a) => a.contextId == context.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Context header row
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedContexts.remove(context.id);
              } else {
                _expandedContexts.add(context.id);
              }
            });
          },
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                // Context icon
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _contextTypeColor(context.type).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.icon,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.displayName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Audio indicator
                if (hasAudio)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Expanded layer slots (L1-L5)
        if (isExpanded)
          Container(
            color: const Color(0xFF0A0A0E),
            padding: const EdgeInsets.only(left: 24, right: 8, top: 4, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(context.layerCount, (i) {
                final layer = i + 1;
                final audioPath = _getMusicLayerPath(context.id, layer);
                return _buildAudioSlot(
                  label: 'L$layer',
                  audioPath: audioPath,
                  onDrop: (path) => widget.onMusicLayerDrop?.call(context.id, layer, path),
                  onClear: audioPath != null
                      ? () => widget.onMusicLayerClear?.call(context.id, layer)
                      : null,
                  layerColor: _layerColor(layer),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioSlot({
    required String label,
    String? audioPath,
    Function(String)? onDrop,
    VoidCallback? onClear,
    Color? layerColor,
  }) {
    final hasAudio = audioPath != null;
    final fileName = hasAudio ? audioPath.split('/').last : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // Accept BOTH AudioAsset and String for backward compatibility
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (details) {
          // Accept AudioAsset, List<AudioAsset>, or String
          return details.data is AudioAsset ||
              details.data is List<AudioAsset> ||
              details.data is String;
        },
        onAcceptWithDetails: (details) {
          String? path;
          if (details.data is AudioAsset) {
            path = (details.data as AudioAsset).path;
          } else if (details.data is List<AudioAsset>) {
            final list = details.data as List<AudioAsset>;
            if (list.isNotEmpty) path = list.first.path;
          } else if (details.data is String) {
            path = details.data as String;
          }
          if (path != null) {
            onDrop?.call(path);
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return Container(
            height: 28,
            decoration: BoxDecoration(
              color: isHovering
                  ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                  : const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isHovering
                    ? FluxForgeTheme.accentBlue
                    : hasAudio
                        ? (layerColor ?? FluxForgeTheme.accentBlue).withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                // Layer label
                Container(
                  width: 32,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (layerColor ?? Colors.white).withOpacity(0.1),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: layerColor ?? Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Audio path or drop hint
                Expanded(
                  child: Text(
                    hasAudio ? fileName! : 'Drop audio...',
                    style: TextStyle(
                      fontSize: 10,
                      color: hasAudio ? Colors.white70 : Colors.white24,
                      fontStyle: hasAudio ? FontStyle.normal : FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Clear button
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    child: Container(
                      width: 24,
                      height: 28,
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, size: 12, color: Colors.white38),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _symbolTypeColor(SymbolType type) {
    switch (type) {
      case SymbolType.wild:
        return const Color(0xFFFFD700); // Gold
      case SymbolType.scatter:
        return const Color(0xFF00BFFF); // Cyan
      case SymbolType.bonus:
        return const Color(0xFFFF69B4); // Pink
      case SymbolType.high:
        return const Color(0xFF9370DB); // Purple
      case SymbolType.low:
        return const Color(0xFF98FB98); // Pale green
      case SymbolType.multiplier:
        return const Color(0xFFFF8C00); // Orange
      case SymbolType.collector:
        return const Color(0xFF20B2AA); // Teal
      case SymbolType.mystery:
        return const Color(0xFF778899); // Gray
    }
  }

  Color _contextTypeColor(ContextType type) {
    switch (type) {
      case ContextType.base:
        return const Color(0xFF4A9EFF); // Blue
      case ContextType.freeSpins:
        return const Color(0xFF40FF90); // Green
      case ContextType.holdWin:
        return const Color(0xFFFFD700); // Gold
      case ContextType.bonus:
        return const Color(0xFFFF69B4); // Pink
      case ContextType.bigWin:
        return const Color(0xFFFF9040); // Orange
      case ContextType.cascade:
        return const Color(0xFF00BFFF); // Cyan
      case ContextType.jackpot:
        return const Color(0xFFFF4040); // Red
      case ContextType.gamble:
        return const Color(0xFF9370DB); // Purple
    }
  }

  Color _layerColor(int layer) {
    switch (layer) {
      case 1:
        return const Color(0xFF4A9EFF); // Blue
      case 2:
        return const Color(0xFF40C8FF); // Cyan
      case 3:
        return const Color(0xFF40FF90); // Green
      case 4:
        return const Color(0xFFFFFF40); // Yellow
      case 5:
        return const Color(0xFFFF9040); // Orange
      default:
        return Colors.white54;
    }
  }
}
