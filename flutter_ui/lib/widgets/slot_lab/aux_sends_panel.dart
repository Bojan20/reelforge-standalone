/// Aux Sends Panel for Slot Lab
///
/// Auxiliary send/return routing:
/// - Matrix view (tracks × aux buses)
/// - Send levels per track
/// - Pre/Post fader selection
/// - Return level controls
/// - Aux bus effects preview

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Aux bus definition
class _AuxBus {
  final int id;
  final String name;
  final String effectType;
  double returnLevel;
  bool isMuted;
  final Color color;

  _AuxBus({
    required this.id,
    required this.name,
    required this.effectType,
    this.returnLevel = 1.0,
    this.isMuted = false,
    required this.color,
  });
}

/// Track send level
class _TrackSend {
  final String trackId;
  final String trackName;
  final Map<int, double> sendLevels; // auxBusId -> level
  final Map<int, bool> prePost; // auxBusId -> isPreFader

  _TrackSend({
    required this.trackId,
    required this.trackName,
    required this.sendLevels,
    required this.prePost,
  });
}

/// Aux Sends Panel Widget
class AuxSendsPanel extends StatefulWidget {
  final double height;

  const AuxSendsPanel({
    super.key,
    this.height = 250,
  });

  @override
  State<AuxSendsPanel> createState() => _AuxSendsPanelState();
}

class _AuxSendsPanelState extends State<AuxSendsPanel> {
  // Aux buses
  final List<_AuxBus> _auxBuses = [
    _AuxBus(id: 100, name: 'Reverb A', effectType: 'Hall', color: FluxForgeTheme.accentBlue),
    _AuxBus(id: 101, name: 'Reverb B', effectType: 'Plate', color: FluxForgeTheme.accentCyan),
    _AuxBus(id: 102, name: 'Delay', effectType: 'Stereo', color: FluxForgeTheme.accentGreen),
    _AuxBus(id: 103, name: 'Chorus', effectType: 'Ensemble', color: FluxForgeTheme.accentOrange),
  ];

  // Track sends
  final List<_TrackSend> _trackSends = [
    _TrackSend(
      trackId: 'track_1',
      trackName: 'SFX Main',
      sendLevels: {100: 0.3, 101: 0.0, 102: 0.2, 103: 0.0},
      prePost: {100: false, 101: false, 102: false, 103: false},
    ),
    _TrackSend(
      trackId: 'track_2',
      trackName: 'Music',
      sendLevels: {100: 0.5, 101: 0.2, 102: 0.0, 103: 0.1},
      prePost: {100: false, 101: false, 102: false, 103: false},
    ),
    _TrackSend(
      trackId: 'track_3',
      trackName: 'Ambience',
      sendLevels: {100: 0.4, 101: 0.3, 102: 0.1, 103: 0.0},
      prePost: {100: false, 101: false, 102: false, 103: false},
    ),
    _TrackSend(
      trackId: 'track_4',
      trackName: 'UI Sounds',
      sendLevels: {100: 0.1, 101: 0.0, 102: 0.0, 103: 0.0},
      prePost: {100: false, 101: false, 102: false, 103: false},
    ),
    _TrackSend(
      trackId: 'track_5',
      trackName: 'Wins',
      sendLevels: {100: 0.4, 101: 0.0, 102: 0.3, 103: 0.2},
      prePost: {100: false, 101: false, 102: false, 103: false},
    ),
  ];

  int? _selectedAuxId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Left: Send matrix
          Expanded(
            flex: 3,
            child: _buildSendMatrix(),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Aux bus details
          SizedBox(
            width: 180,
            child: _buildAuxBusDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildSendMatrix() {
    return Column(
      children: [
        // Header with aux bus names
        Container(
          height: 40,
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              // Track name column header
              Container(
                width: 100,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'TRACK',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              // Aux bus columns
              ..._auxBuses.map((aux) => _buildAuxColumnHeader(aux)),
            ],
          ),
        ),
        // Send matrix rows
        Expanded(
          child: ListView.builder(
            itemCount: _trackSends.length,
            itemBuilder: (context, index) {
              return _buildSendRow(_trackSends[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAuxColumnHeader(_AuxBus aux) {
    final isSelected = _selectedAuxId == aux.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedAuxId = aux.id),
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: isSelected ? aux.color.withOpacity(0.2) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? aux.color : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              aux.name,
              style: TextStyle(
                color: isSelected ? aux.color : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              aux.effectType,
              style: TextStyle(
                color: isSelected ? aux.color.withOpacity(0.7) : Colors.white38,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendRow(_TrackSend track) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // Track name
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              track.trackName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Send knobs
          ..._auxBuses.map((aux) {
            final level = track.sendLevels[aux.id] ?? 0.0;
            final isPreFader = track.prePost[aux.id] ?? false;
            return _buildSendKnob(track, aux, level, isPreFader);
          }),
        ],
      ),
    );
  }

  Widget _buildSendKnob(_TrackSend track, _AuxBus aux, double level, bool isPreFader) {
    return SizedBox(
      width: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pre/Post indicator
          GestureDetector(
            onTap: () {
              setState(() {
                track.prePost[aux.id] = !isPreFader;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: isPreFader ? aux.color.withOpacity(0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                isPreFader ? 'PRE' : 'PST',
                style: TextStyle(
                  color: isPreFader ? aux.color : Colors.white24,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Level indicator/slider
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final delta = details.delta.dx / 40;
                  track.sendLevels[aux.id] = (level + delta).clamp(0.0, 1.0);
                });
              },
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Stack(
                  children: [
                    // Level bar
                    FractionallySizedBox(
                      widthFactor: level,
                      child: Container(
                        decoration: BoxDecoration(
                          color: level > 0 ? aux.color.withOpacity(0.6) : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Value text
                    Center(
                      child: Text(
                        '${(level * 100).toInt()}',
                        style: TextStyle(
                          color: level > 0.5 ? Colors.white : Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuxBusDetails() {
    final selectedAux = _selectedAuxId != null
        ? _auxBuses.firstWhere((a) => a.id == _selectedAuxId, orElse: () => _auxBuses[0])
        : null;

    if (selectedAux == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 32, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 8),
            const Text(
              'Select aux bus',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selectedAux.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedAux.name,
                      style: TextStyle(
                        color: selectedAux.color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      selectedAux.effectType,
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
              // Mute button
              GestureDetector(
                onTap: () {
                  setState(() => selectedAux.isMuted = !selectedAux.isMuted);
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selectedAux.isMuted
                        ? const Color(0xFFFF4040)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selectedAux.isMuted
                          ? const Color(0xFFFF4040)
                          : FluxForgeTheme.borderSubtle,
                    ),
                  ),
                  child: Icon(
                    selectedAux.isMuted ? Icons.volume_off : Icons.volume_up,
                    size: 12,
                    color: selectedAux.isMuted ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Return level
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RETURN LEVEL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        activeTrackColor: selectedAux.color,
                        inactiveTrackColor: FluxForgeTheme.bgDeep,
                        thumbColor: selectedAux.color,
                      ),
                      child: Slider(
                        value: selectedAux.returnLevel,
                        onChanged: (value) {
                          setState(() => selectedAux.returnLevel = value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${(selectedAux.returnLevel * 100).toInt()}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selectedAux.color,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Effect preview
              const Text(
                'EFFECT',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selectedAux.color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getEffectIcon(selectedAux.effectType),
                      size: 20,
                      color: selectedAux.color,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedAux.effectType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'Tap to edit',
                          style: TextStyle(color: Colors.white38, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Total send indicator
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Active sends:',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    Text(
                      '${_getActiveSendCount(selectedAux.id)}',
                      style: TextStyle(
                        color: selectedAux.color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getEffectIcon(String effectType) {
    return switch (effectType.toLowerCase()) {
      'hall' || 'plate' || 'room' => Icons.waves,
      'delay' || 'stereo' => Icons.multiline_chart,
      'chorus' || 'ensemble' => Icons.graphic_eq,
      _ => Icons.tune,
    };
  }

  int _getActiveSendCount(int auxId) {
    return _trackSends.where((t) => (t.sendLevels[auxId] ?? 0) > 0).length;
  }
}
