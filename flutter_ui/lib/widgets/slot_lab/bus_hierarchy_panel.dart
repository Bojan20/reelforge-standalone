/// Bus Hierarchy Panel for Slot Lab
///
/// Tree view of audio bus hierarchy with:
/// - Expandable tree structure
/// - Per-bus volume faders synced to MixerDSPProvider + Rust FFI
/// - Per-bus meters from SharedMeterReader (real FFI, 60fps)
/// - Mute/Solo controls synced to MixerDSPProvider + Rust FFI
/// - Effects chain preview from MixerDSPProvider inserts

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/mixer_dsp_provider.dart';
import '../../services/shared_meter_reader.dart';

/// Bus node in the hierarchy
class _BusNode {
  final int id;
  final String name;
  final String? mixerBusId; // Maps to MixerDSPProvider bus ID
  final int? parentId;
  final int channelIndex; // SharedMeterReader channel index (-1 = derived)
  double volume;
  bool isMuted;
  bool isSolo;
  double meterLevelL; // 0.0 - 1.0
  double meterLevelR;
  double meterPeakL;
  double meterPeakR;
  List<String> effects;
  bool isExpanded;

  _BusNode({
    required this.id,
    required this.name,
    this.mixerBusId,
    this.parentId,
    this.channelIndex = -1,
    this.volume = 1.0,
    this.isMuted = false,
    this.isSolo = false,
    this.meterLevelL = 0.0,
    this.meterLevelR = 0.0,
    this.meterPeakL = 0.0,
    this.meterPeakR = 0.0,
    this.effects = const [],
    this.isExpanded = true,
  });
}

/// Bus Hierarchy Panel Widget
class BusHierarchyPanel extends StatefulWidget {
  const BusHierarchyPanel({super.key});

  @override
  State<BusHierarchyPanel> createState() => _BusHierarchyPanelState();
}

class _BusHierarchyPanelState extends State<BusHierarchyPanel>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  int? _selectedBusId;
  bool _meterInitialized = false;
  SharedMeterSnapshot _snapshot = SharedMeterSnapshot.empty;

  // Peak hold state
  final Map<int, double> _peakHoldL = {};
  final Map<int, double> _peakHoldR = {};
  final Map<int, int> _peakHoldTimeL = {};
  final Map<int, int> _peakHoldTimeR = {};

  // Bus hierarchy based on SlotBusIds
  // channelIndex maps to SharedMeterReader.channelPeaks (6ch × 2 L/R)
  // Engine buses: 0=SFX, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master
  final List<_BusNode> _buses = [
    _BusNode(
      id: SlotBusIds.master,
      name: 'Master',
      mixerBusId: 'master',
      volume: 1.0,
      channelIndex: 5,
      effects: ['Limiter', 'True Peak'],
    ),
    _BusNode(
      id: SlotBusIds.music,
      name: 'Music',
      mixerBusId: 'music',
      parentId: SlotBusIds.master,
      volume: 0.8,
      channelIndex: 1,
      effects: ['EQ', 'Comp'],
    ),
    _BusNode(
      id: SlotBusIds.sfx,
      name: 'SFX',
      mixerBusId: 'sfx',
      parentId: SlotBusIds.master,
      volume: 1.0,
      channelIndex: 0,
      effects: ['EQ'],
    ),
    _BusNode(
      id: SlotBusIds.voice,
      name: 'Voice',
      mixerBusId: 'voice',
      parentId: SlotBusIds.master,
      volume: 1.0,
      channelIndex: 2,
      effects: ['DeEsser', 'Comp'],
    ),
    _BusNode(
      id: SlotBusIds.ui,
      name: 'UI',
      parentId: SlotBusIds.master,
      volume: 0.9,
      channelIndex: -1, // No dedicated channel — derived from master
    ),
    _BusNode(
      id: SlotBusIds.reels,
      name: 'Reels',
      parentId: SlotBusIds.sfx,
      volume: 1.0,
      channelIndex: -1, // Sub-bus of SFX — derived
    ),
    _BusNode(
      id: SlotBusIds.wins,
      name: 'Wins',
      parentId: SlotBusIds.sfx,
      volume: 1.0,
      channelIndex: -1,
      effects: ['Comp'],
    ),
    _BusNode(
      id: SlotBusIds.anticipation,
      name: 'Anticipation',
      parentId: SlotBusIds.sfx,
      volume: 0.8,
      channelIndex: -1,
      effects: ['LPF'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initMetering();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _initMetering() async {
    final success = await SharedMeterReader.instance.initialize();
    if (mounted) {
      setState(() => _meterInitialized = success);
    }
  }

  /// Sync initial state from MixerDSPProvider
  void _syncFromProvider(MixerDSPProvider provider) {
    for (final bus in _buses) {
      if (bus.mixerBusId == null) continue;
      final mixBus = provider.getBus(bus.mixerBusId!);
      if (mixBus != null) {
        bus.volume = mixBus.volume;
        bus.isMuted = mixBus.muted;
        bus.isSolo = mixBus.solo;
        // Sync effects from inserts
        if (mixBus.inserts.isNotEmpty) {
          bus.effects = mixBus.inserts.map((i) => i.name).toList();
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!_meterInitialized) return;

    final reader = SharedMeterReader.instance;
    if (!reader.hasChanged) {
      // Still decay peak hold
      if (_decayPeakHold()) setState(() {});
      return;
    }

    final snap = reader.readMeters();
    final now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _snapshot = snap;
      for (final bus in _buses) {
        double levelL, levelR;

        if (bus.channelIndex >= 0 &&
            bus.channelIndex * 2 + 1 < snap.channelPeaks.length) {
          // Real per-channel metering from SharedMeterReader
          levelL = snap.channelPeaks[bus.channelIndex * 2].clamp(0.0, 1.0);
          levelR = snap.channelPeaks[bus.channelIndex * 2 + 1].clamp(0.0, 1.0);
        } else if (bus.parentId != null) {
          // Derived sub-bus — use parent channel scaled by volume
          final parent = _buses.firstWhere(
            (b) => b.id == bus.parentId,
            orElse: () => _buses[0],
          );
          levelL = parent.meterLevelL * bus.volume * 0.8;
          levelR = parent.meterLevelR * bus.volume * 0.8;
        } else {
          levelL = 0;
          levelR = 0;
        }

        bus.meterLevelL = levelL;
        bus.meterLevelR = levelR;

        // Peak hold (L)
        if (levelL >= (_peakHoldL[bus.id] ?? 0.0)) {
          _peakHoldL[bus.id] = levelL;
          _peakHoldTimeL[bus.id] = now;
        }
        bus.meterPeakL = _peakHoldL[bus.id] ?? 0.0;

        // Peak hold (R)
        if (levelR >= (_peakHoldR[bus.id] ?? 0.0)) {
          _peakHoldR[bus.id] = levelR;
          _peakHoldTimeR[bus.id] = now;
        }
        bus.meterPeakR = _peakHoldR[bus.id] ?? 0.0;
      }
    });
  }

  bool _decayPeakHold() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    const holdMs = 1500;
    const decay = 0.02;

    for (final bus in _buses) {
      // L channel
      final holdTimeL = _peakHoldTimeL[bus.id] ?? 0;
      if (now - holdTimeL > holdMs) {
        final newPeak = (_peakHoldL[bus.id] ?? 0.0) - decay;
        if (newPeak > 0) {
          _peakHoldL[bus.id] = newPeak;
          bus.meterPeakL = newPeak;
          changed = true;
        } else if (_peakHoldL.containsKey(bus.id)) {
          _peakHoldL.remove(bus.id);
          _peakHoldTimeL.remove(bus.id);
          bus.meterPeakL = 0;
          changed = true;
        }
      }
      // R channel
      final holdTimeR = _peakHoldTimeR[bus.id] ?? 0;
      if (now - holdTimeR > holdMs) {
        final newPeak = (_peakHoldR[bus.id] ?? 0.0) - decay;
        if (newPeak > 0) {
          _peakHoldR[bus.id] = newPeak;
          bus.meterPeakR = newPeak;
          changed = true;
        } else if (_peakHoldR.containsKey(bus.id)) {
          _peakHoldR.remove(bus.id);
          _peakHoldTimeR.remove(bus.id);
          bus.meterPeakR = 0;
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Set bus volume — syncs to MixerDSPProvider + Rust FFI
  void _setBusVolume(_BusNode bus, double value) {
    setState(() => bus.volume = value);
    if (bus.mixerBusId != null) {
      final provider = context.read<MixerDSPProvider>();
      provider.setBusVolume(bus.mixerBusId!, value);
    }
  }

  /// Toggle mute — syncs to MixerDSPProvider + Rust FFI
  void _toggleMute(_BusNode bus) {
    setState(() => bus.isMuted = !bus.isMuted);
    if (bus.mixerBusId != null) {
      final provider = context.read<MixerDSPProvider>();
      provider.toggleMute(bus.mixerBusId!);
    }
  }

  /// Toggle solo — syncs to MixerDSPProvider + Rust FFI
  void _toggleSolo(_BusNode bus) {
    setState(() => bus.isSolo = !bus.isSolo);
    if (bus.mixerBusId != null) {
      final provider = context.read<MixerDSPProvider>();
      provider.toggleSolo(bus.mixerBusId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sync state from provider on each build
    final mixerProvider = context.watch<MixerDSPProvider>();
    _syncFromProvider(mixerProvider);

    return Container(
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
          child: Row(
            children: [
              const Icon(Icons.account_tree, size: 14, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 8),
              const Text(
                'BUS HIERARCHY',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // FFI status indicator
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _meterInitialized
                      ? FluxForgeTheme.accentGreen
                      : const Color(0xFFFF4040),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _meterInitialized ? 'FFI' : 'OFF',
                style: TextStyle(
                  color: _meterInitialized
                      ? FluxForgeTheme.accentGreen
                      : const Color(0xFFFF4040),
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
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
    final monoLevel = ((bus.meterLevelL + bus.meterLevelR) / 2.0).clamp(0.0, 1.0);
    final monoPeak = ((bus.meterPeakL + bus.meterPeakR) / 2.0).clamp(0.0, 1.0);

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
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
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
                // Stereo mini meter
                SizedBox(
                  width: 50,
                  height: 12,
                  child: Row(
                    children: [
                      // L meter
                      Expanded(
                        child: _buildMiniMeterBar(bus.meterLevelL, bus.meterPeakL),
                      ),
                      const SizedBox(width: 1),
                      // R meter
                      Expanded(
                        child: _buildMiniMeterBar(bus.meterLevelR, bus.meterPeakR),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Mute
                GestureDetector(
                  onTap: () => _toggleMute(bus),
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
                  onTap: () => _toggleSolo(bus),
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

  /// Mini meter bar for tree node (horizontal, gradient)
  Widget _buildMiniMeterBar(double level, double peak) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              // Level
              Container(
                width: (level * width).clamp(0.0, width),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FluxForgeTheme.accentGreen,
                      level > 0.7
                          ? FluxForgeTheme.accentOrange
                          : FluxForgeTheme.accentGreen,
                      level > 0.9
                          ? const Color(0xFFFF4040)
                          : FluxForgeTheme.accentGreen,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              // Peak hold
              if (peak > 0.01)
                Positioned(
                  left: (peak * width - 1).clamp(0.0, width - 2),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: peak > 0.9 ? const Color(0xFFFF4040) : Colors.white54,
                  ),
                ),
            ],
          );
        },
      ),
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
            Icon(Icons.speaker, size: 40, color: Colors.white.withValues(alpha: 0.2)),
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
              const Spacer(),
              // dB readout
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _formatDb(selectedBus.meterLevelL, selectedBus.meterLevelR),
                  style: TextStyle(
                    color: (selectedBus.meterLevelL > 0.9 || selectedBus.meterLevelR > 0.9)
                        ? const Color(0xFFFF4040)
                        : FluxForgeTheme.accentCyan,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
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
                      // Large stereo meter
                      _buildLargeStereoMeter(selectedBus),
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
                onChanged: (value) => _setBusVolume(bus, value),
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

  /// Large stereo meter with L/R bars + peak hold + dB scale
  Widget _buildLargeStereoMeter(_BusNode bus) {
    return SizedBox(
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // L label
          const SizedBox(
            width: 12,
            child: Center(
              child: Text('L', style: TextStyle(color: Colors.white38, fontSize: 8)),
            ),
          ),
          // L bar
          Expanded(child: _buildHorizontalMeterBar(bus.meterLevelL, bus.meterPeakL)),
          const SizedBox(height: 2),
          // R label
          const SizedBox(
            width: 12,
            child: Center(
              child: Text('R', style: TextStyle(color: Colors.white38, fontSize: 8)),
            ),
          ),
          // R bar
          Expanded(child: _buildHorizontalMeterBar(bus.meterLevelR, bus.meterPeakR)),
        ],
      ),
    );
  }

  Widget _buildHorizontalMeterBar(double level, double peak) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              // Level gradient
              Container(
                width: (level * width).clamp(0.0, width),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      FluxForgeTheme.accentGreen,
                      if (level > 0.7) FluxForgeTheme.accentOrange,
                      if (level > 0.9) const Color(0xFFFF4040),
                    ].take(level > 0.9 ? 3 : (level > 0.7 ? 2 : 1)).toList(),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Peak hold indicator
              if (peak > 0.01)
                Positioned(
                  left: (peak * width - 1).clamp(0.0, width - 2),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: peak > 0.9 ? const Color(0xFFFF4040) : Colors.white,
                  ),
                ),
              // Scale markers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 4),
                  ...List.generate(10, (i) => Container(
                    width: 1,
                    height: i % 5 == 0 ? 10 : 4,
                    color: Colors.white.withValues(alpha: 0.15),
                  )),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          );
        },
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
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
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

  String _formatDb(double levelL, double levelR) {
    final maxLevel = levelL > levelR ? levelL : levelR;
    if (maxLevel <= 0.001) return '-inf dB';
    // 20 * log10(level)
    final db = 20.0 * _log10(maxLevel);
    return '${db.toStringAsFixed(1)} dB';
  }

  static double _log10(double x) {
    if (x <= 0) return -60;
    // ln(x) / ln(10) using series expansion
    double result = 0;
    double y = (x - 1) / (x + 1);
    double y2 = y * y;
    double term = y;
    for (int i = 1; i < 20; i += 2) {
      result += term / i;
      term *= y2;
    }
    return 2 * result / 2.302585092994046; // ln(10)
  }
}
