/// SlotLab-specific node types for the Hook Graph System.
///
/// These nodes are unique to FluxForge — no other audio middleware has them.
/// They encode slot game domain knowledge: win tiers, reel analysis,
/// feature states, near-miss detection, cascade mechanics.

import 'graph_ports.dart';
import 'graph_definition.dart';
import 'node_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WIN TIER NODE — Routes audio based on win multiplier
// ═══════════════════════════════════════════════════════════════════════════

final winTierNode = NodeTypeDefinition(
  typeId: 'WinTier',
  displayName: 'Win Tier Router',
  description: 'Routes to different outputs based on win/bet multiplier tier',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'trigger', label: 'Trigger',
      type: PortType.trigger, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'winAmount', label: 'Win Amount',
      type: PortType.float, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'betAmount', label: 'Bet Amount',
      type: PortType.float, direction: PortDirection.input, required: true,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'noWin', label: 'No Win', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'win1', label: 'WIN 1', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'win2', label: 'WIN 2', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'win3', label: 'WIN 3', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'win4', label: 'WIN 4', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'win5', label: 'WIN 5', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'bigWin', label: 'Big Win', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'multiplier', label: 'Multiplier', type: PortType.float, direction: PortDirection.output),
    GraphPort(id: 'tierIndex', label: 'Tier Index', type: PortType.integer, direction: PortDirection.output),
  ],
  defaultParameters: {
    'tier1Threshold': 1.0,
    'tier2Threshold': 3.0,
    'tier3Threshold': 5.0,
    'tier4Threshold': 10.0,
    'tier5Threshold': 15.0,
    'bigWinThreshold': 20.0,
  },
  tags: ['slot', 'win', 'tier', 'multiplier', 'celebration'],
);

// ═══════════════════════════════════════════════════════════════════════════
// REEL ANALYZER NODE — Extracts reel stop data
// ═══════════════════════════════════════════════════════════════════════════

final reelAnalyzerNode = NodeTypeDefinition(
  typeId: 'ReelAnalyzer',
  displayName: 'Reel Analyzer',
  description: 'Analyzes reel stop positions for near-miss, scatter count, wild positions',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'reelData', label: 'Reel Data',
      type: PortType.any, direction: PortDirection.input, required: true,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'nearMiss', label: 'Near Miss', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'scatterCount', label: 'Scatter Count', type: PortType.integer, direction: PortDirection.output),
    GraphPort(id: 'wildCount', label: 'Wild Count', type: PortType.integer, direction: PortDirection.output),
    GraphPort(id: 'winLineCount', label: 'Win Lines', type: PortType.integer, direction: PortDirection.output),
    GraphPort(id: 'anticipation', label: 'Anticipation', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'reelStopIndex', label: 'Last Reel', type: PortType.integer, direction: PortDirection.output),
  ],
  defaultParameters: {
    'nearMissThreshold': 2,
    'scatterSymbolId': 'SCATTER',
    'wildSymbolId': 'WILD',
  },
  tags: ['slot', 'reel', 'analyze', 'near-miss', 'scatter', 'wild'],
);

// ═══════════════════════════════════════════════════════════════════════════
// FEATURE STATE NODE — Checks current game feature state
// ═══════════════════════════════════════════════════════════════════════════

final featureStateNode = NodeTypeDefinition(
  typeId: 'FeatureState',
  displayName: 'Feature State',
  description: 'Outputs current game state — base game, free spins, bonus, cascade',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'trigger', label: 'Trigger',
      type: PortType.trigger, direction: PortDirection.input,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'isBaseGame', label: 'Base Game', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'isFreeSpins', label: 'Free Spins', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'isBonus', label: 'Bonus', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'isCascade', label: 'Cascade', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'isRespin', label: 'Respin', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'stateId', label: 'State ID', type: PortType.string, direction: PortDirection.output),
    GraphPort(id: 'spinsRemaining', label: 'Spins Left', type: PortType.integer, direction: PortDirection.output),
  ],
  tags: ['slot', 'feature', 'state', 'free-spins', 'bonus', 'cascade'],
);

// ═══════════════════════════════════════════════════════════════════════════
// CASCADE STEP NODE — Controls cascade audio sequence
// ═══════════════════════════════════════════════════════════════════════════

final cascadeStepNode = NodeTypeDefinition(
  typeId: 'CascadeStep',
  displayName: 'Cascade Step',
  description: 'Emits cascade step events with depth and multiplier tracking',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'trigger', label: 'Trigger',
      type: PortType.trigger, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'depth', label: 'Cascade Depth',
      type: PortType.integer, direction: PortDirection.input,
    ),
    GraphPort(
      id: 'multiplier', label: 'Current Multiplier',
      type: PortType.float, direction: PortDirection.input,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'removal', label: 'Removal', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'drop', label: 'Drop', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'fill', label: 'Fill', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'reEvaluate', label: 'Re-evaluate', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'complete', label: 'Complete', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'intensity', label: 'Intensity', type: PortType.float, direction: PortDirection.output),
    GraphPort(id: 'isMegaChain', label: 'Mega Chain', type: PortType.boolean, direction: PortDirection.output),
  ],
  defaultParameters: {
    'megaChainThreshold': 5,
    'removalDelayMs': 300,
    'fillDelayMs': 250,
    'intensityScale': 'linear',
  },
  tags: ['slot', 'cascade', 'tumble', 'avalanche', 'chain'],
);

// ═══════════════════════════════════════════════════════════════════════════
// ANTICIPATION NODE — Builds tension before reel stop
// ═══════════════════════════════════════════════════════════════════════════

final anticipationNode = NodeTypeDefinition(
  typeId: 'Anticipation',
  displayName: 'Anticipation Builder',
  description: 'Ramps audio tension as reels approach potential big win',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'trigger', label: 'Start',
      type: PortType.trigger, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'reelIndex', label: 'Reel Index',
      type: PortType.integer, direction: PortDirection.input,
    ),
    GraphPort(
      id: 'scattersSoFar', label: 'Scatters So Far',
      type: PortType.integer, direction: PortDirection.input,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'tension', label: 'Tension', type: PortType.float, direction: PortDirection.output),
    GraphPort(id: 'shouldAnticipate', label: 'Should Play', type: PortType.boolean, direction: PortDirection.output),
    GraphPort(id: 'climax', label: 'Climax', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'release', label: 'Release', type: PortType.trigger, direction: PortDirection.output),
  ],
  defaultParameters: {
    'minScattersForAnticipation': 2,
    'tensionCurve': 'exponential',
    'climaxReelIndex': 4,
  },
  tags: ['slot', 'anticipation', 'tension', 'near-miss', 'scatter'],
);

// ═══════════════════════════════════════════════════════════════════════════
// ROLLUP NODE — Controls win amount counting animation audio
// ═══════════════════════════════════════════════════════════════════════════

final rollupNode = NodeTypeDefinition(
  typeId: 'Rollup',
  displayName: 'Win Rollup',
  description: 'Controls audio for win amount counting animation with acceleration',
  category: NodeCategory.slot,
  inputPorts: [
    GraphPort(
      id: 'trigger', label: 'Start',
      type: PortType.trigger, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'winAmount', label: 'Win Amount',
      type: PortType.float, direction: PortDirection.input, required: true,
    ),
    GraphPort(
      id: 'durationMs', label: 'Duration (ms)',
      type: PortType.float, direction: PortDirection.input,
    ),
  ],
  outputPorts: [
    GraphPort(id: 'tick', label: 'Tick', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'progress', label: 'Progress', type: PortType.float, direction: PortDirection.output),
    GraphPort(id: 'complete', label: 'Complete', type: PortType.trigger, direction: PortDirection.output),
    GraphPort(id: 'tickRate', label: 'Tick Rate', type: PortType.float, direction: PortDirection.output),
  ],
  defaultParameters: {
    'durationMs': 2000.0,
    'acceleration': 'easeOut',
    'minTickIntervalMs': 30.0,
    'maxTickIntervalMs': 200.0,
  },
  tags: ['slot', 'rollup', 'count', 'win', 'animation'],
);

/// All SlotLab-specific node types
final slotLabNodeTypes = [
  winTierNode,
  reelAnalyzerNode,
  featureStateNode,
  cascadeStepNode,
  anticipationNode,
  rollupNode,
];
