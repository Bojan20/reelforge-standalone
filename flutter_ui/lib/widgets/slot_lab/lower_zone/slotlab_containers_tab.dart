/// SlotLab CONTAINERS Tab — Blend, Random, Sequence
///
/// Unified container tools from middleware into SlotLab lower zone.

import 'package:flutter/material.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/blend_container_panel.dart';
import '../../middleware/random_container_panel.dart';
import '../../middleware/sequence_container_panel.dart';

class SlotLabContainersTabContent extends StatelessWidget {
  final SlotLabContainersSubTab subTab;

  const SlotLabContainersTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabContainersSubTab.blend => const BlendContainerPanel(),
      SlotLabContainersSubTab.random => const RandomContainerPanel(),
      SlotLabContainersSubTab.sequence => const SequenceContainerPanel(),
    };
  }
}
