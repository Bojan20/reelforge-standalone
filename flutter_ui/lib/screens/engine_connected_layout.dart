/// Engine Connected Layout
///
/// Connects MainLayout to the Rust EngineProvider.
/// Bridges UI callbacks to engine API calls.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/engine_provider.dart';
import '../providers/meter_provider.dart';
import '../models/layout_models.dart';
import '../theme/reelforge_theme.dart';
import 'main_layout.dart';

class EngineConnectedLayout extends StatefulWidget {
  const EngineConnectedLayout({super.key});

  @override
  State<EngineConnectedLayout> createState() => _EngineConnectedLayoutState();
}

class _EngineConnectedLayoutState extends State<EngineConnectedLayout> {
  // Zone state
  bool _leftVisible = true;
  bool _rightVisible = true;
  bool _lowerVisible = false;
  String _activeLowerTab = 'mixer';
  LeftZoneTab _activeLeftTab = LeftZoneTab.project;

  // Local UI state
  EditorMode _editorMode = EditorMode.daw;
  TimeDisplayMode _timeDisplayMode = TimeDisplayMode.bars;
  bool _metronomeEnabled = false;
  bool _snapEnabled = true;
  double _snapValue = 1;

  // Project tree demo data
  final List<ProjectTreeNode> _projectTree = [
    ProjectTreeNode(
      id: 'audio',
      type: TreeItemType.folder,
      label: 'Audio',
      children: [
        ProjectTreeNode(
          id: 'drums',
          type: TreeItemType.folder,
          label: 'Drums',
          children: [
            const ProjectTreeNode(
                id: 'kick', type: TreeItemType.sound, label: 'Kick.wav'),
            const ProjectTreeNode(
                id: 'snare', type: TreeItemType.sound, label: 'Snare.wav'),
          ],
        ),
        const ProjectTreeNode(
            id: 'bass', type: TreeItemType.sound, label: 'Bass.wav'),
      ],
    ),
    ProjectTreeNode(
      id: 'events',
      type: TreeItemType.folder,
      label: 'Events',
      children: [
        const ProjectTreeNode(
            id: 'play_music', type: TreeItemType.event, label: 'Play_Music'),
        const ProjectTreeNode(
            id: 'stop_all', type: TreeItemType.event, label: 'Stop_All'),
      ],
    ),
    ProjectTreeNode(
      id: 'buses',
      type: TreeItemType.folder,
      label: 'Buses',
      children: [
        const ProjectTreeNode(
            id: 'master', type: TreeItemType.bus, label: 'Master'),
        const ProjectTreeNode(
            id: 'music', type: TreeItemType.bus, label: 'Music'),
        const ProjectTreeNode(id: 'sfx', type: TreeItemType.bus, label: 'SFX'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Register meters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final meters = context.read<MeterProvider>();
      meters.registerMeter('master');
      meters.registerMeter('sfx');
      meters.registerMeter('music');
      meters.registerMeter('voice');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EngineProvider>(
      builder: (context, engine, _) {
        final transport = engine.transport;
        final metering = engine.metering;

        return MainLayout(
          // Control bar - connected to engine
          editorMode: _editorMode,
          onEditorModeChange: (mode) => setState(() => _editorMode = mode),
          isPlaying: transport.isPlaying,
          isRecording: transport.isRecording,
          onPlay: () {
            if (transport.isPlaying) {
              engine.pause();
            } else {
              engine.play();
            }
          },
          onStop: () => engine.stop(),
          onRecord: () => engine.toggleRecord(),
          onRewind: () => engine.seek(0),
          onForward: () => engine.seek(transport.positionSeconds + 10),
          tempo: transport.tempo,
          onTempoChange: (t) => engine.setTempo(t),
          timeSignature:
              TimeSignature(transport.timeSigNum, transport.timeSigDenom),
          currentTime: transport.positionSeconds,
          timeDisplayMode: _timeDisplayMode,
          onTimeDisplayModeChange: () => setState(() {
            switch (_timeDisplayMode) {
              case TimeDisplayMode.bars:
                _timeDisplayMode = TimeDisplayMode.timecode;
              case TimeDisplayMode.timecode:
                _timeDisplayMode = TimeDisplayMode.samples;
              case TimeDisplayMode.samples:
                _timeDisplayMode = TimeDisplayMode.bars;
            }
          }),
          loopEnabled: transport.loopEnabled,
          onLoopToggle: () => engine.toggleLoop(),
          snapEnabled: _snapEnabled,
          snapValue: _snapValue,
          onSnapToggle: () => setState(() => _snapEnabled = !_snapEnabled),
          onSnapValueChange: (v) => setState(() => _snapValue = v),
          metronomeEnabled: _metronomeEnabled,
          onMetronomeToggle: () =>
              setState(() => _metronomeEnabled = !_metronomeEnabled),
          cpuUsage: metering.cpuUsage,
          memoryUsage: 35, // TODO: Get from engine
          projectName: engine.project.name,
          menuCallbacks: MenuCallbacks(
            onNewProject: () => engine.newProject('New Project'),
            onSaveProject: () => engine.saveProject('project.rfp'),
            onUndo: engine.canUndo ? () => engine.undo() : null,
            onRedo: engine.canRedo ? () => engine.redo() : null,
          ),

          // Left zone
          projectTree: _projectTree,
          activeLeftTab: _activeLeftTab,
          onLeftTabChange: (tab) => setState(() => _activeLeftTab = tab),

          // Center zone
          child: _buildCenterContent(transport, metering),

          // Inspector (for middleware mode)
          inspectorType: InspectedObjectType.event,
          inspectorName: 'Play_Music',
          inspectorSections: [
            InspectorSection(
              id: 'general',
              title: 'General',
              content: const Text(
                'Event settings will appear here',
                style:
                    TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
              ),
            ),
          ],

          // Lower zone
          lowerTabs: [
            LowerZoneTab(
              id: 'mixer',
              label: 'Mixer',
              icon: Icons.tune,
              content: _buildMixerContent(metering),
            ),
            LowerZoneTab(
              id: 'editor',
              label: 'Editor',
              icon: Icons.edit,
              content: const Center(
                child: Text('Editor View',
                    style: TextStyle(color: ReelForgeTheme.textSecondary)),
              ),
            ),
            LowerZoneTab(
              id: 'browser',
              label: 'Browser',
              icon: Icons.folder,
              content: const Center(
                child: Text('Browser View',
                    style: TextStyle(color: ReelForgeTheme.textSecondary)),
              ),
            ),
          ],
          activeLowerTabId: _activeLowerTab,
          onLowerTabChange: (id) => setState(() => _activeLowerTab = id),

          // Zone visibility
          leftZoneVisible: _leftVisible,
          rightZoneVisible: _rightVisible,
          lowerZoneVisible: _lowerVisible,
          onLeftZoneToggle: () => setState(() => _leftVisible = !_leftVisible),
          onRightZoneToggle: () =>
              setState(() => _rightVisible = !_rightVisible),
          onLowerZoneToggle: () =>
              setState(() => _lowerVisible = !_lowerVisible),
        );
      },
    );
  }

  Widget _buildCenterContent(dynamic transport, dynamic metering) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ReelForge DAW', style: ReelForgeTheme.h1),
            const SizedBox(height: 8),
            Text(
              'Engine Connected',
              style: TextStyle(
                  color: ReelForgeTheme.accentGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),

            // Real-time metering display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  _MeterRow(
                      label: 'Peak L',
                      value: metering.masterPeakL.toStringAsFixed(1),
                      unit: 'dB'),
                  _MeterRow(
                      label: 'Peak R',
                      value: metering.masterPeakR.toStringAsFixed(1),
                      unit: 'dB'),
                  _MeterRow(
                      label: 'LUFS M',
                      value: metering.masterLufsM.toStringAsFixed(1),
                      unit: 'LUFS'),
                  _MeterRow(
                      label: 'LUFS S',
                      value: metering.masterLufsS.toStringAsFixed(1),
                      unit: 'LUFS'),
                  _MeterRow(
                      label: 'CPU',
                      value: metering.cpuUsage.toStringAsFixed(1),
                      unit: '%'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Transport status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusIndicator(
                  label: 'Playing',
                  active: transport.isPlaying,
                  color: ReelForgeTheme.accentGreen,
                ),
                const SizedBox(width: 16),
                _StatusIndicator(
                  label: 'Recording',
                  active: transport.isRecording,
                  color: ReelForgeTheme.errorRed,
                ),
                const SizedBox(width: 16),
                _StatusIndicator(
                  label: 'Loop',
                  active: transport.loopEnabled,
                  color: ReelForgeTheme.accentBlue,
                ),
              ],
            ),
            const SizedBox(height: 32),

            Text(
              'Press Ctrl+L/R/B to toggle zones',
              style: TextStyle(
                  color: ReelForgeTheme.textTertiary, fontSize: 12),
            ),
            Text(
              'Space to play/pause, R to record',
              style: TextStyle(
                  color: ReelForgeTheme.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixerContent(dynamic metering) {
    return Row(
      children: [
        MixerStrip(
          id: 'sfx',
          name: 'SFX',
          volume: 1.0,
          meterLevel: _dbToLinear(metering.masterPeakL) * 0.6,
          meterLevelR: _dbToLinear(metering.masterPeakR) * 0.55,
          inserts: const [
            InsertSlot(id: '1', name: 'EQ', type: 'eq'),
            InsertSlot(id: '2', name: 'Comp', type: 'comp'),
          ],
        ),
        MixerStrip(
          id: 'music',
          name: 'Music',
          volume: 0.8,
          meterLevel: _dbToLinear(metering.masterPeakL) * 0.8,
          meterLevelR: _dbToLinear(metering.masterPeakR) * 0.75,
        ),
        MixerStrip(
          id: 'voice',
          name: 'Voice',
          volume: 1.0,
          meterLevel: _dbToLinear(metering.masterPeakL) * 0.4,
          meterLevelR: _dbToLinear(metering.masterPeakR) * 0.35,
        ),
        MixerStrip(
          id: 'master',
          name: 'Master',
          isMaster: true,
          volume: 1.0,
          meterLevel: _dbToLinear(metering.masterPeakL),
          meterLevelR: _dbToLinear(metering.masterPeakR),
          inserts: const [
            InsertSlot(id: 'm1', name: 'Limiter', type: 'comp'),
          ],
        ),
      ],
    );
  }

  double _dbToLinear(double db) {
    if (db <= -60) return 0;
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }
}

class _MeterRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MeterRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                  color: ReelForgeTheme.textSecondary, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: ReelForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(
                color: ReelForgeTheme.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _StatusIndicator({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : ReelForgeTheme.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? color : ReelForgeTheme.textTertiary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
