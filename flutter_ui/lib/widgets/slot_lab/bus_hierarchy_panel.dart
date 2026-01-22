/// Bus Hierarchy Panel for Slot Lab
///
/// Tree view of audio bus hierarchy with:
/// - Expandable tree structure
/// - Per-bus volume faders
/// - Per-bus meters
/// - Mute/Solo controls
/// - Effects chain preview

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/slot_audio_events.dart';
import '../../src/rust/native_ffi.dart';

/// Bus node in the hierarchy
class _BusNode {
  final int id;
  final String name;
  final int? parentId;
  double volume;
  bool isMuted;
  bool isSolo;
  double meterLevel; // 0.0 - 1.0
  double meterPeak;
  List<String> effects;
  bool isExpanded;

  _BusNode({
    required this.id,
    required this.name,
    this.parentId,
    this.volume = 1.0,
    this.isMuted = false,
    this.isSolo = false,
    this.meterLevel = 0.0,
    this.meterPeak = 0.0,
    this.effects = const [],
    this.isExpanded = true,
  });
}

/// Bus Hierarchy Panel Widget
class BusHierarchyPanel extends StatefulWidget {
  final double height;

  const BusHierarchyPanel({
    super.key,
    this.height = 250,
  });

  @override
  State<BusHierarchyPanel> createState() => _BusHierarchyPanelState();
}

class _BusHierarchyPanelState extends State<BusHierarchyPanel> with SingleTickerProviderStateMixin {
  late AnimationController _meterController;
  int? _selectedBusId;

  // Bus hierarchy based on SlotBusIds
  final List<_BusNode> _buses = [
    _BusNode(
      id: SlotBusIds.master,
      name: 'Master',
      volume: 1.0,
      effects: ['Limiter', 'True Peak'],
    ),
    _BusNode(
      id: SlotBusIds.music,
      name: 'Music',
      parentId: SlotBusIds.master,
      volume: 0.8,
      effects: ['EQ', 'Comp'],
    ),
    _BusNode(
      id: SlotBusIds.sfx,
      name: 'SFX',
      parentId: SlotBusIds.master,
      volume: 1.0,
      effects: ['EQ'],
    ),
    _BusNode(
      id: SlotBusIds.voice,
      name: 'Voice',
      parentId: SlotBusIds.master,
      volume: 1.0,
      effects: ['DeEsser', 'Comp'],
    ),
    _BusNode(
      id: SlotBusIds.ui,
      name: 'UI',
      parentId: SlotBusIds.master,
      volume: 0.9,
    ),
    _BusNode(
      id: SlotBusIds.reels,
      name: 'Reels',
      parentId: SlotBusIds.sfx,
      volume: 1.0,
    ),
    _BusNode(
      id: SlotBusIds.wins,
      name: 'Wins',
      parentId: SlotBusIds.sfx,
      volume: 1.0,
      effects: ['Comp'],
    ),
    _BusNode(
      id: SlotBusIds.anticipation,
      name: 'Anticipation',
      parentId: SlotBusIds.sfx,
      volume: 0.8,
      effects: ['LPF'],
    ),
  ];

  final _ffi = NativeFFI.instance;

  @override
  void initState() {
    super.initState();
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();

    // Update meters from real engine data
    _meterController.addListener(_updateMeters);
  }

  @override
  void dispose() {
    _meterController.removeListener(_updateMeters);
    _meterController.dispose();
    super.dispose();
  }

  void _updateMeters() {
    if (!_ffi.isLoaded) {
      // FFI not loaded - show zeros (no fake data)
      setState(() {
        for (final bus in _buses) {
          bus.meterLevel = 0.0;
          bus.meterPeak = (bus.meterPeak - 0.02).clamp(0.0, 1.0); // Decay peak
        }
      });
      return;
    }

    setState(() {
      // Get real peak meters from engine (master bus)
      final (peakL, peakR) = _ffi.getPeakMeters();
      final masterLevel = ((peakL.abs() + peakR.abs()) / 2.0).clamp(0.0, 1.0);

      for (final bus in _buses) {
        // Master bus gets actual level, others get proportional based on their volume
        if (bus.id == SlotBusIds.master) {
          bus.meterLevel = masterLevel;
        } else {
          // Sub-buses show proportional level (real per-bus metering would need dedicated FFI)
          // When no audio, show 0; when audio playing, show scaled level
          bus.meterLevel = masterLevel > 0.001
              ? (masterLevel * bus.volume * 0.8).clamp(0.0, 1.0)
              : 0.0;
        }

        // Update peak hold
        if (bus.meterLevel > bus.meterPeak) {
          bus.meterPeak = bus.meterLevel;
        } else {
          bus.meterPeak = (bus.meterPeak - 0.01).clamp(0.0, 1.0); // Natural decay
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Left: Bus tree
          Expanded(
            flex: 2,
            child: _buildBusTree(),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Selected bus details
          Expanded(
            flex: 3,
            child: _buildBusDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildBusTree() {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: const Row(
            children: [
              Icon(Icons.account_tree, size: 14, color: FluxForgeTheme.accentGreen),
              SizedBox(width: 8),
              Text(
                'BUS HIERARCHY',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        // Tree view
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: _buildBusNodeTree(null, 0),
          ),
        ),
      ],
    );
  }

  Widget _buildBusNodeTree(int? parentId, int depth) {
    final children = _buses.where((b) => b.parentId == parentId).toList();
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((bus) {
        final hasChildren = _buses.any((b) => b.parentId == bus.id);
        return _buildBusNodeItem(bus, depth, hasChildren);
      }).toList(),
    );
  }

  Widget _buildBusNodeItem(_BusNode bus, int depth, bool hasChildren) {
    final isSelected = _selectedBusId == bus.id;
    final indent = depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedBusId = bus.id),
          child: Container(
            margin: EdgeInsets.only(left: indent, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accentBlue.withOpacity(0.15)
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() => bus.isExpanded = !bus.isExpanded),
                    child: Icon(
                      bus.isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: Colors.white54,
                    ),
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 4),
                // Bus name
                Expanded(
                  child: Text(
                    bus.name,
                    style: TextStyle(
                      color: bus.isMuted ? Colors.white38 : Colors.white,
                      fontSize: 11,
                      fontWeight: bus.parentId == null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                // Mini meter
                Container(
                  width: 50,
                  height: 10,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Stack(
                    children: [
                      // Level
                      FractionallySizedBox(
                        widthFactor: bus.meterLevel * bus.volume,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                FluxForgeTheme.accentGreen,
                                bus.meterLevel > 0.7 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                                bus.meterLevel > 0.9 ? const Color(0xFFFF4040) : FluxForgeTheme.accentGreen,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Peak
                      Positioned(
                        left: bus.meterPeak * bus.volume * 48,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: bus.meterPeak > 0.9 ? const Color(0xFFFF4040) : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Mute
                GestureDetector(
                  onTap: () => setState(() => bus.isMuted = !bus.isMuted),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: bus.isMuted ? const Color(0xFFFF4040) : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: bus.isMuted ? const Color(0xFFFF4040) : Colors.white24,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: bus.isMuted ? Colors.white : Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Solo
                GestureDetector(
                  onTap: () => setState(() => bus.isSolo = !bus.isSolo),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: bus.isSolo ? FluxForgeTheme.accentOrange : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: bus.isSolo ? FluxForgeTheme.accentOrange : Colors.white24,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          color: bus.isSolo ? Colors.black : Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Children
        if (bus.isExpanded) _buildBusNodeTree(bus.id, depth + 1),
      ],
    );
  }

  Widget _buildBusDetails() {
    final selectedBus = _selectedBusId != null
        ? _buses.firstWhere((b) => b.id == _selectedBusId, orElse: () => _buses[0])
        : null;

    if (selectedBus == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speaker, size: 40, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 8),
            const Text(
              'Select a bus to view details',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.speaker, size: 14, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 8),
              Text(
                selectedBus.name.toUpperCase(),
                style: const TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Volume fader
                _buildVolumeFader(selectedBus),
                const SizedBox(width: 16),
                // Meter + details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Large meter
                      _buildLargeMeter(selectedBus),
                      const SizedBox(height: 12),
                      // Effects chain
                      const Text(
                        'EFFECTS CHAIN',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildEffectsChain(selectedBus),
                      const Spacer(),
                      // Output routing
                      _buildOutputRouting(selectedBus),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeFader(_BusNode bus) {
    return Column(
      children: [
        const Text(
          'VOL',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: FluxForgeTheme.accentCyan,
                inactiveTrackColor: FluxForgeTheme.bgDeep,
                thumbColor: FluxForgeTheme.accentCyan,
              ),
              child: Slider(
                value: bus.volume,
                min: 0.0,
                max: 1.0,
                onChanged: (value) => setState(() => bus.volume = value),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            '${(bus.volume * 100).toInt()}%',
            style: const TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLargeMeter(_BusNode bus) {
    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Stack(
        children: [
          // Level
          FractionallySizedBox(
            widthFactor: bus.meterLevel * bus.volume,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FluxForgeTheme.accentGreen,
                    if (bus.meterLevel > 0.7) FluxForgeTheme.accentOrange,
                    if (bus.meterLevel > 0.9) const Color(0xFFFF4040),
                  ].take(bus.meterLevel > 0.9 ? 3 : (bus.meterLevel > 0.7 ? 2 : 1)).toList(),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Peak indicator
          Positioned(
            left: bus.meterPeak * bus.volume * (280 - 4),
            top: 2,
            bottom: 2,
            child: Container(
              width: 2,
              color: bus.meterPeak > 0.9 ? const Color(0xFFFF4040) : Colors.white,
            ),
          ),
          // Scale markers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 4),
              ...List.generate(10, (i) => Container(
                width: 1,
                height: i % 5 == 0 ? 12 : 6,
                color: Colors.white.withOpacity(0.2),
              )),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEffectsChain(_BusNode bus) {
    if (bus.effects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: const Center(
          child: Text(
            'No effects',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: bus.effects.map((fx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: FluxForgeTheme.accentGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                fx,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOutputRouting(_BusNode bus) {
    final parent = bus.parentId != null
        ? _buses.firstWhere((b) => b.id == bus.parentId, orElse: () => _buses[0])
        : null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward, size: 12, color: Colors.white54),
          const SizedBox(width: 8),
          const Text(
            'Output:',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 8),
          Text(
            parent?.name ?? 'Hardware Out',
            style: const TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
