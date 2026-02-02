/// Win Celebration Designer — P12.1.16
///
/// Visual editor for designing win celebration audio sequences.
/// Allows designers to create and preview win tier timelines with
/// audio layer placement.
///
/// Features:
/// - Visual editor for win sequences
/// - Tier timeline (Small→Big→Mega→Epic→Ultra)
/// - Audio layer placement via drag-drop
/// - Preview playback with timing
/// - Export/import configuration
library;

import 'package:flutter/material.dart';
import '../../models/win_tier_config.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// WIN LAYER DEFINITION
// =============================================================================

/// An audio layer in the win celebration timeline
class WinAudioLayer {
  final String id;
  final String audioPath;
  final String label;
  final int startMs;
  final int durationMs;
  final double volume;
  final bool loop;

  const WinAudioLayer({
    required this.id,
    required this.audioPath,
    required this.label,
    required this.startMs,
    required this.durationMs,
    this.volume = 1.0,
    this.loop = false,
  });

  WinAudioLayer copyWith({
    String? id,
    String? audioPath,
    String? label,
    int? startMs,
    int? durationMs,
    double? volume,
    bool? loop,
  }) {
    return WinAudioLayer(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      label: label ?? this.label,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      loop: loop ?? this.loop,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'label': label,
    'startMs': startMs,
    'durationMs': durationMs,
    'volume': volume,
    'loop': loop,
  };

  factory WinAudioLayer.fromJson(Map<String, dynamic> json) => WinAudioLayer(
    id: json['id'] as String,
    audioPath: json['audioPath'] as String,
    label: json['label'] as String,
    startMs: json['startMs'] as int,
    durationMs: json['durationMs'] as int,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    loop: json['loop'] as bool? ?? false,
  );
}

/// Configuration for a win tier celebration
class WinTierCelebration {
  final int tierId;
  final String tierName;
  final int totalDurationMs;
  final List<WinAudioLayer> layers;

  const WinTierCelebration({
    required this.tierId,
    required this.tierName,
    required this.totalDurationMs,
    this.layers = const [],
  });

  WinTierCelebration copyWith({
    int? tierId,
    String? tierName,
    int? totalDurationMs,
    List<WinAudioLayer>? layers,
  }) {
    return WinTierCelebration(
      tierId: tierId ?? this.tierId,
      tierName: tierName ?? this.tierName,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      layers: layers ?? this.layers,
    );
  }
}

// =============================================================================
// WIN CELEBRATION DESIGNER WIDGET
// =============================================================================

/// Visual editor for win celebration sequences
class WinCelebrationDesigner extends StatefulWidget {
  /// Current win tier configuration
  final SlotWinConfiguration? winConfig;

  /// Initial celebration configurations
  final Map<int, WinTierCelebration>? initialCelebrations;

  /// Callback when celebration is updated
  final ValueChanged<WinTierCelebration>? onCelebrationChanged;

  /// Callback when audio drop is requested
  final Function(int tierId, String audioPath, int startMs)? onAudioDropped;

  /// Accent color
  final Color accentColor;

  const WinCelebrationDesigner({
    super.key,
    this.winConfig,
    this.initialCelebrations,
    this.onCelebrationChanged,
    this.onAudioDropped,
    this.accentColor = const Color(0xFFFFD700),
  });

  @override
  State<WinCelebrationDesigner> createState() => _WinCelebrationDesignerState();
}

class _WinCelebrationDesignerState extends State<WinCelebrationDesigner>
    with SingleTickerProviderStateMixin {
  // State
  int _selectedTierId = 1;
  late Map<int, WinTierCelebration> _celebrations;
  String? _selectedLayerId;
  bool _isPlaying = false;
  int _playheadMs = 0;

  // Animation
  late AnimationController _playbackController;

  // Layout constants
  static const double _tierSelectorHeight = 48.0;
  static const double _timelineHeight = 120.0;
  static const double _layerHeight = 32.0;
  static const double _pixelsPerMs = 0.08;

  // Default tier configurations
  static const List<({int id, String name, Color color, int durationMs})> _defaultTiers = [
    (id: 1, name: 'Small', color: Color(0xFF4A9EFF), durationMs: 1500),
    (id: 2, name: 'Big', color: Color(0xFF40FF90), durationMs: 2500),
    (id: 3, name: 'Super', color: Color(0xFFFFD700), durationMs: 4000),
    (id: 4, name: 'Mega', color: Color(0xFFFF9040), durationMs: 7000),
    (id: 5, name: 'Epic', color: Color(0xFFE040FB), durationMs: 12000),
    (id: 6, name: 'Ultra', color: Color(0xFFFF4040), durationMs: 20000),
  ];

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(vsync: this);
    _playbackController.addListener(_onPlaybackTick);
    _initializeCelebrations();
  }

  void _initializeCelebrations() {
    _celebrations = {};
    for (final tier in _defaultTiers) {
      _celebrations[tier.id] = widget.initialCelebrations?[tier.id] ??
          WinTierCelebration(
            tierId: tier.id,
            tierName: tier.name,
            totalDurationMs: tier.durationMs,
            layers: [],
          );
    }
  }

  @override
  void dispose() {
    _playbackController.dispose();
    super.dispose();
  }

  void _onPlaybackTick() {
    final celebration = _celebrations[_selectedTierId];
    if (celebration == null) return;

    setState(() {
      _playheadMs = (_playbackController.value * celebration.totalDurationMs).round();
    });
  }

  WinTierCelebration get _currentCelebration =>
      _celebrations[_selectedTierId] ?? _celebrations.values.first;

  ({int id, String name, Color color, int durationMs}) get _currentTierConfig =>
      _defaultTiers.firstWhere((t) => t.id == _selectedTierId);

  void _startPlayback() {
    final celebration = _celebrations[_selectedTierId];
    if (celebration == null) return;

    setState(() {
      _isPlaying = true;
      _playheadMs = 0;
    });

    _playbackController.duration = Duration(milliseconds: celebration.totalDurationMs);
    _playbackController.forward(from: 0.0).then((_) {
      setState(() {
        _isPlaying = false;
        _playheadMs = 0;
      });
    });

    // Trigger audio layers
    _playAudioLayers(celebration);
  }

  void _stopPlayback() {
    _playbackController.stop();
    setState(() {
      _isPlaying = false;
      _playheadMs = 0;
    });
    AudioPlaybackService.instance.stopAll();
  }

  void _playAudioLayers(WinTierCelebration celebration) {
    for (final layer in celebration.layers) {
      Future.delayed(Duration(milliseconds: layer.startMs), () {
        if (_isPlaying) {
          AudioPlaybackService.instance.playFileToBus(
            layer.audioPath,
            volume: layer.volume,
            busId: 0, // SFX bus
          );
        }
      });
    }
  }

  void _addLayer(String audioPath, int startMs) {
    final celebration = _celebrations[_selectedTierId];
    if (celebration == null) return;

    final fileName = audioPath.split('/').last;
    final newLayer = WinAudioLayer(
      id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
      audioPath: audioPath,
      label: fileName.length > 20 ? '${fileName.substring(0, 17)}...' : fileName,
      startMs: startMs,
      durationMs: 1000, // Default 1 second
    );

    final updatedCelebration = celebration.copyWith(
      layers: [...celebration.layers, newLayer],
    );

    setState(() {
      _celebrations[_selectedTierId] = updatedCelebration;
    });

    widget.onCelebrationChanged?.call(updatedCelebration);
  }

  void _removeLayer(String layerId) {
    final celebration = _celebrations[_selectedTierId];
    if (celebration == null) return;

    final updatedCelebration = celebration.copyWith(
      layers: celebration.layers.where((l) => l.id != layerId).toList(),
    );

    setState(() {
      _celebrations[_selectedTierId] = updatedCelebration;
      if (_selectedLayerId == layerId) _selectedLayerId = null;
    });

    widget.onCelebrationChanged?.call(updatedCelebration);
  }

  void _updateLayerPosition(String layerId, int newStartMs) {
    final celebration = _celebrations[_selectedTierId];
    if (celebration == null) return;

    final updatedLayers = celebration.layers.map((l) {
      if (l.id == layerId) {
        return l.copyWith(startMs: newStartMs.clamp(0, celebration.totalDurationMs - l.durationMs));
      }
      return l;
    }).toList();

    final updatedCelebration = celebration.copyWith(layers: updatedLayers);

    setState(() {
      _celebrations[_selectedTierId] = updatedCelebration;
    });

    widget.onCelebrationChanged?.call(updatedCelebration);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildTierSelector(),
          Expanded(
            child: _buildTimeline(),
          ),
          _buildControlBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration, size: 16, color: widget.accentColor),
          const SizedBox(width: 8),
          const Text(
            'Win Celebration Designer',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${_currentCelebration.layers.length} layers',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierSelector() {
    return Container(
      height: _tierSelectorHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: FluxForgeTheme.bgSurface,
      child: Row(
        children: [
          for (final tier in _defaultTiers)
            Expanded(
              child: _buildTierButton(tier),
            ),
        ],
      ),
    );
  }

  Widget _buildTierButton(({int id, String name, Color color, int durationMs}) tier) {
    final isSelected = tier.id == _selectedTierId;
    final layerCount = _celebrations[tier.id]?.layers.length ?? 0;

    return GestureDetector(
      onTap: () => setState(() => _selectedTierId = tier.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? tier.color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? tier.color : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tier.name,
              style: TextStyle(
                color: isSelected ? tier.color : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (layerCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tier.color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$layerCount',
                  style: TextStyle(
                    color: tier.color,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    final celebration = _currentCelebration;
    final tierConfig = _currentTierConfig;
    final timelineWidth = celebration.totalDurationMs * _pixelsPerMs;

    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        // Calculate drop position
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;

        final localPos = renderBox.globalToLocal(details.offset);
        final ms = (localPos.dx / _pixelsPerMs).round().clamp(0, celebration.totalDurationMs - 1000);
        _addLayer(details.data, ms);
        widget.onAudioDropped?.call(_selectedTierId, details.data, ms);
      },
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty;

        return Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDraggingOver
                ? tierConfig.color.withOpacity(0.1)
                : FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDraggingOver
                  ? tierConfig.color
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: timelineWidth + 100,
              child: CustomPaint(
                painter: _TimelinePainter(
                  totalDurationMs: celebration.totalDurationMs,
                  pixelsPerMs: _pixelsPerMs,
                  tierColor: tierConfig.color,
                  playheadMs: _isPlaying ? _playheadMs : null,
                ),
                child: Stack(
                  children: [
                    // Audio layers
                    for (final layer in celebration.layers)
                      _buildLayerWidget(layer, tierConfig.color),

                    // Drop hint
                    if (isDraggingOver)
                      Positioned.fill(
                        child: Center(
                          child: Text(
                            'Drop audio here',
                            style: TextStyle(
                              color: tierConfig.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayerWidget(WinAudioLayer layer, Color tierColor) {
    final isSelected = layer.id == _selectedLayerId;
    final x = layer.startMs * _pixelsPerMs;
    final width = layer.durationMs * _pixelsPerMs;

    return Positioned(
      left: x,
      top: 40 + (_currentCelebration.layers.indexOf(layer) % 3) * (_layerHeight + 4),
      child: GestureDetector(
        onTap: () => setState(() => _selectedLayerId = layer.id),
        onHorizontalDragUpdate: (details) {
          final newStartMs = layer.startMs + (details.delta.dx / _pixelsPerMs).round();
          _updateLayerPosition(layer.id, newStartMs);
        },
        child: Container(
          width: width.clamp(60.0, double.infinity),
          height: _layerHeight,
          decoration: BoxDecoration(
            color: tierColor.withOpacity(isSelected ? 0.4 : 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.white : tierColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              Icon(
                layer.loop ? Icons.loop : Icons.audiotrack,
                size: 12,
                color: tierColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  layer.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                IconButton(
                  icon: const Icon(Icons.close, size: 12),
                  onPressed: () => _removeLayer(layer.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    final celebration = _currentCelebration;
    final tierConfig = _currentTierConfig;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          // Play/Stop button
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.stop : Icons.play_arrow,
              color: tierConfig.color,
            ),
            onPressed: _isPlaying ? _stopPlayback : _startPlayback,
            tooltip: _isPlaying ? 'Stop' : 'Preview',
          ),
          const SizedBox(width: 8),

          // Playhead position
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(_playheadMs / 1000).toStringAsFixed(1)}s / ${(celebration.totalDurationMs / 1000).toStringAsFixed(1)}s',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),

          const Spacer(),

          // Tier badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tierConfig.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tierConfig.color.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events, size: 12, color: tierConfig.color),
                const SizedBox(width: 4),
                Text(
                  '${tierConfig.name} Win',
                  style: TextStyle(
                    color: tierConfig.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TIMELINE PAINTER
// =============================================================================

class _TimelinePainter extends CustomPainter {
  final int totalDurationMs;
  final double pixelsPerMs;
  final Color tierColor;
  final int? playheadMs;

  _TimelinePainter({
    required this.totalDurationMs,
    required this.pixelsPerMs,
    required this.tierColor,
    this.playheadMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw time ruler
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final tickPaint = Paint()
      ..color = FluxForgeTheme.textSecondary.withOpacity(0.3)
      ..strokeWidth = 1;

    // Calculate tick interval
    int tickIntervalMs = 1000;
    if (totalDurationMs > 10000) tickIntervalMs = 2000;
    if (totalDurationMs > 20000) tickIntervalMs = 5000;

    for (int ms = 0; ms <= totalDurationMs; ms += tickIntervalMs) {
      final x = ms * pixelsPerMs;

      // Tick line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, 24),
        tickPaint,
      );

      // Time label
      final label = '${(ms / 1000).toStringAsFixed(0)}s';
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 9,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 26));
    }

    // Draw playhead
    if (playheadMs != null) {
      final playheadX = playheadMs! * pixelsPerMs;
      final playheadPaint = Paint()
        ..color = tierColor
        ..strokeWidth = 2;

      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        playheadPaint,
      );

      // Playhead triangle
      final trianglePath = Path()
        ..moveTo(playheadX - 6, 0)
        ..lineTo(playheadX + 6, 0)
        ..lineTo(playheadX, 8)
        ..close();

      canvas.drawPath(
        trianglePath,
        Paint()..color = tierColor,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) {
    return totalDurationMs != oldDelegate.totalDurationMs ||
        playheadMs != oldDelegate.playheadMs ||
        tierColor != oldDelegate.tierColor;
  }
}
