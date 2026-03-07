/// SlotLab MUSIC Tab — Segments, Stingers, Transitions
///
/// Unified interactive music system from middleware into SlotLab lower zone.

import 'package:flutter/material.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/music_system_panel.dart';
import '../../middleware/stinger_preview_panel.dart';
import '../../middleware/music_transition_preview_panel.dart';
import '../../middleware/music_segment_looping_panel.dart';
import '../../middleware/beat_grid_editor.dart';
import '../../middleware/tempo_state_panel.dart';

class SlotLabMusicTabContent extends StatelessWidget {
  final SlotLabMusicSubTab subTab;

  const SlotLabMusicTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabMusicSubTab.segments => const _SegmentsPanel(),
      SlotLabMusicSubTab.stingers => const _StingersPanel(),
      SlotLabMusicSubTab.transitions => const _TransitionsPanel(),
      SlotLabMusicSubTab.looping => const _LoopingPanel(),
      SlotLabMusicSubTab.beatGrid => const _BeatGridPanel(),
      SlotLabMusicSubTab.tempoStates => const _TempoStatesPanel(),
    };
  }
}

class _LoopingPanel extends StatelessWidget {
  const _LoopingPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MusicSegmentLoopingPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}

class _BeatGridPanel extends StatelessWidget {
  const _BeatGridPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => BeatGridEditor(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}

class _SegmentsPanel extends StatelessWidget {
  const _SegmentsPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
        child: const MusicSystemPanel(),
      ),
    );
  }
}

class _StingersPanel extends StatelessWidget {
  const _StingersPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => StingerPreviewPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}

class _TransitionsPanel extends StatelessWidget {
  const _TransitionsPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MusicTransitionPreviewPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}

class _TempoStatesPanel extends StatelessWidget {
  const _TempoStatesPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => TempoStatePanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}
