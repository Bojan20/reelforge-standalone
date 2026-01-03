/**
 * Spin Cycle Editor
 *
 * State machine visualizer for slot spin audio:
 * IDLE → SPIN_START → REELS_SPINNING → REEL_STOP[1-5] → EVALUATION → WIN/LOSE → IDLE
 *
 * @module layout/slot/SpinCycleEditor
 */

import { memo, useState, useCallback, useRef } from 'react';

// ============ Types ============

export type SpinState =
  | 'idle'
  | 'spin_start'
  | 'reels_spinning'
  | 'reel_stop_1'
  | 'reel_stop_2'
  | 'reel_stop_3'
  | 'reel_stop_4'
  | 'reel_stop_5'
  | 'evaluation'
  | 'win'
  | 'lose'
  | 'anticipation';

export interface SpinStateAudio {
  stateId: SpinState;
  sounds: {
    id: string;
    name: string;
    type: 'oneshot' | 'loop' | 'sequence';
    delay?: number;
    fadeIn?: number;
    fadeOut?: number;
  }[];
  duration?: number; // ms, for timed states
  nextState?: SpinState;
  conditions?: {
    type: 'win_amount' | 'feature' | 'anticipation' | 'manual';
    value?: string | number;
    targetState: SpinState;
  }[];
}

export interface SpinCycleConfig {
  states: SpinStateAudio[];
  anticipationReels: number; // How many matching symbols trigger anticipation
  reelStopInterval: number; // ms between reel stops
}

export interface SpinCycleEditorProps {
  config: SpinCycleConfig;
  currentState?: SpinState;
  onStateChange?: (state: SpinState) => void;
  onConfigChange?: (config: SpinCycleConfig) => void;
  onSoundSelect?: (stateId: SpinState, soundId: string) => void;
  isSimulating?: boolean;
}

// ============ State Node Component ============

interface StateNodeProps {
  state: SpinStateAudio;
  isActive: boolean;
  isSelected: boolean;
  position: { x: number; y: number };
  onClick: () => void;
  onSoundClick?: (soundId: string) => void;
}

const STATE_COLORS: Record<SpinState, string> = {
  idle: '#6b7280',
  spin_start: '#3b82f6',
  reels_spinning: '#8b5cf6',
  reel_stop_1: '#ec4899',
  reel_stop_2: '#ec4899',
  reel_stop_3: '#ec4899',
  reel_stop_4: '#ec4899',
  reel_stop_5: '#ec4899',
  evaluation: '#f59e0b',
  win: '#22c55e',
  lose: '#ef4444',
  anticipation: '#f97316',
};

const STATE_LABELS: Record<SpinState, string> = {
  idle: 'IDLE',
  spin_start: 'SPIN START',
  reels_spinning: 'SPINNING',
  reel_stop_1: 'REEL 1',
  reel_stop_2: 'REEL 2',
  reel_stop_3: 'REEL 3',
  reel_stop_4: 'REEL 4',
  reel_stop_5: 'REEL 5',
  evaluation: 'EVALUATE',
  win: 'WIN',
  lose: 'NO WIN',
  anticipation: 'ANTICIPATION',
};

const StateNode = memo(function StateNode({
  state,
  isActive,
  isSelected,
  position,
  onClick,
  onSoundClick,
}: StateNodeProps) {
  const color = STATE_COLORS[state.stateId];

  return (
    <g
      transform={`translate(${position.x}, ${position.y})`}
      onClick={onClick}
      style={{ cursor: 'pointer' }}
    >
      {/* Glow effect when active */}
      {isActive && (
        <circle
          r={42}
          fill="none"
          stroke={color}
          strokeWidth={3}
          opacity={0.5}
          className="rf-spin-node-glow"
        />
      )}

      {/* Main circle */}
      <circle
        r={36}
        fill={isActive ? color : 'var(--rf-bg-2)'}
        stroke={isSelected ? 'var(--rf-accent-primary)' : color}
        strokeWidth={isSelected ? 3 : 2}
      />

      {/* State label */}
      <text
        y={-4}
        textAnchor="middle"
        fill={isActive ? 'white' : 'var(--rf-text-primary)'}
        fontSize={9}
        fontWeight={600}
      >
        {STATE_LABELS[state.stateId]}
      </text>

      {/* Sound count */}
      <text
        y={10}
        textAnchor="middle"
        fill={isActive ? 'rgba(255,255,255,0.7)' : 'var(--rf-text-tertiary)'}
        fontSize={8}
      >
        {state.sounds.length} sound{state.sounds.length !== 1 ? 's' : ''}
      </text>

      {/* Sound indicators */}
      {state.sounds.slice(0, 4).map((sound, i) => (
        <circle
          key={sound.id}
          cx={-12 + i * 8}
          cy={22}
          r={3}
          fill={isActive ? 'rgba(255,255,255,0.8)' : color}
          onClick={(e) => {
            e.stopPropagation();
            onSoundClick?.(sound.id);
          }}
        />
      ))}
    </g>
  );
});

// ============ Connection Arrow ============

interface ConnectionProps {
  from: { x: number; y: number };
  to: { x: number; y: number };
  label?: string;
  isActive?: boolean;
  color?: string;
}

const Connection = memo(function Connection({
  from,
  to,
  label,
  isActive,
  color = 'var(--rf-border)',
}: ConnectionProps) {
  // Calculate arrow path
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const len = Math.sqrt(dx * dx + dy * dy);
  const nx = dx / len;
  const ny = dy / len;

  // Offset from circle edge
  const startX = from.x + nx * 38;
  const startY = from.y + ny * 38;
  const endX = to.x - nx * 42;
  const endY = to.y - ny * 42;

  // Arrow head
  const arrowSize = 8;
  const arrowAngle = Math.atan2(dy, dx);
  const arrow1X = endX - arrowSize * Math.cos(arrowAngle - 0.4);
  const arrow1Y = endY - arrowSize * Math.sin(arrowAngle - 0.4);
  const arrow2X = endX - arrowSize * Math.cos(arrowAngle + 0.4);
  const arrow2Y = endY - arrowSize * Math.sin(arrowAngle + 0.4);

  return (
    <g>
      <line
        x1={startX}
        y1={startY}
        x2={endX}
        y2={endY}
        stroke={isActive ? 'var(--rf-accent-primary)' : color}
        strokeWidth={isActive ? 2 : 1}
        markerEnd="url(#arrowhead)"
      />
      <polygon
        points={`${endX},${endY} ${arrow1X},${arrow1Y} ${arrow2X},${arrow2Y}`}
        fill={isActive ? 'var(--rf-accent-primary)' : color}
      />
      {label && (
        <text
          x={(startX + endX) / 2}
          y={(startY + endY) / 2 - 6}
          textAnchor="middle"
          fill="var(--rf-text-tertiary)"
          fontSize={8}
        >
          {label}
        </text>
      )}
    </g>
  );
});

// ============ Sound List Panel ============

interface SoundListProps {
  state: SpinStateAudio | null;
  onSoundAdd?: () => void;
  onSoundRemove?: (soundId: string) => void;
  onSoundEdit?: (soundId: string) => void;
}

const SoundList = memo(function SoundList({
  state,
  onSoundAdd,
  onSoundRemove,
  onSoundEdit,
}: SoundListProps) {
  if (!state) {
    return (
      <div className="rf-spin-sounds rf-spin-sounds--empty">
        <p>Select a state to view sounds</p>
      </div>
    );
  }

  return (
    <div className="rf-spin-sounds">
      <div className="rf-spin-sounds__header">
        <span>{STATE_LABELS[state.stateId]} Sounds</span>
        {onSoundAdd && (
          <button onClick={onSoundAdd}>+ Add</button>
        )}
      </div>
      <div className="rf-spin-sounds__list">
        {state.sounds.map((sound) => (
          <div
            key={sound.id}
            className="rf-spin-sounds__item"
            onClick={() => onSoundEdit?.(sound.id)}
          >
            <span className={`rf-spin-sounds__type rf-spin-sounds__type--${sound.type}`}>
              {sound.type === 'loop' ? '🔁' : sound.type === 'sequence' ? '📋' : '▶'}
            </span>
            <span className="rf-spin-sounds__name">{sound.name}</span>
            {sound.delay !== undefined && sound.delay > 0 && (
              <span className="rf-spin-sounds__delay">+{sound.delay}ms</span>
            )}
            {onSoundRemove && (
              <button
                className="rf-spin-sounds__remove"
                onClick={(e) => {
                  e.stopPropagation();
                  onSoundRemove(sound.id);
                }}
              >
                ×
              </button>
            )}
          </div>
        ))}
        {state.sounds.length === 0 && (
          <div className="rf-spin-sounds__empty">No sounds assigned</div>
        )}
      </div>
    </div>
  );
});

// ============ State Machine Layout ============

const STATE_POSITIONS: Record<SpinState, { x: number; y: number }> = {
  idle: { x: 80, y: 150 },
  spin_start: { x: 200, y: 80 },
  reels_spinning: { x: 350, y: 80 },
  reel_stop_1: { x: 480, y: 50 },
  reel_stop_2: { x: 560, y: 90 },
  reel_stop_3: { x: 620, y: 150 },
  reel_stop_4: { x: 560, y: 210 },
  reel_stop_5: { x: 480, y: 250 },
  anticipation: { x: 350, y: 220 },
  evaluation: { x: 350, y: 150 },
  win: { x: 200, y: 220 },
  lose: { x: 200, y: 150 },
};

const CONNECTIONS: { from: SpinState; to: SpinState; label?: string }[] = [
  { from: 'idle', to: 'spin_start' },
  { from: 'spin_start', to: 'reels_spinning' },
  { from: 'reels_spinning', to: 'reel_stop_1' },
  { from: 'reel_stop_1', to: 'reel_stop_2' },
  { from: 'reel_stop_2', to: 'reel_stop_3' },
  { from: 'reel_stop_3', to: 'reel_stop_4' },
  { from: 'reel_stop_4', to: 'reel_stop_5' },
  { from: 'reel_stop_5', to: 'evaluation' },
  { from: 'reels_spinning', to: 'anticipation', label: 'near win' },
  { from: 'anticipation', to: 'reel_stop_3' },
  { from: 'evaluation', to: 'win', label: 'win > 0' },
  { from: 'evaluation', to: 'lose', label: 'no win' },
  { from: 'win', to: 'idle' },
  { from: 'lose', to: 'idle' },
];

// ============ Main Component ============

export const SpinCycleEditor = memo(function SpinCycleEditor({
  config,
  currentState = 'idle',
  onStateChange,
  onConfigChange,
  onSoundSelect,
  isSimulating = false,
}: SpinCycleEditorProps) {
  const [selectedState, setSelectedState] = useState<SpinState | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  // Find state config
  const getStateConfig = useCallback(
    (stateId: SpinState): SpinStateAudio => {
      return (
        config.states.find((s) => s.stateId === stateId) || {
          stateId,
          sounds: [],
        }
      );
    },
    [config.states]
  );

  // Handle state click
  const handleStateClick = useCallback(
    (stateId: SpinState) => {
      setSelectedState(stateId);
      if (isSimulating) {
        onStateChange?.(stateId);
      }
    },
    [isSimulating, onStateChange]
  );

  // Sound management handlers
  const handleSoundAdd = useCallback(() => {
    if (!selectedState) return;
    const newSound: SpinStateAudio['sounds'][0] = {
      id: `sound-${Date.now()}`,
      name: 'new_sound',
      type: 'oneshot',
      delay: 0,
    };
    const newStates = config.states.map((s) =>
      s.stateId === selectedState
        ? { ...s, sounds: [...s.sounds, newSound] }
        : s
    );
    // If state doesn't exist yet, add it
    if (!config.states.find((s) => s.stateId === selectedState)) {
      newStates.push({ stateId: selectedState, sounds: [newSound] });
    }
    onConfigChange?.({ ...config, states: newStates });
  }, [selectedState, config, onConfigChange]);

  const handleSoundRemove = useCallback(
    (soundId: string) => {
      if (!selectedState) return;
      const newStates = config.states.map((s) =>
        s.stateId === selectedState
          ? { ...s, sounds: s.sounds.filter((snd) => snd.id !== soundId) }
          : s
      );
      onConfigChange?.({ ...config, states: newStates });
    },
    [selectedState, config, onConfigChange]
  );

  const handleSoundEdit = useCallback(
    (soundId: string) => {
      if (!selectedState) return;
      onSoundSelect?.(selectedState, soundId);
    },
    [selectedState, onSoundSelect]
  );

  // Simulation controls - run a full spin cycle demo
  const handleSimulate = useCallback(() => {
    // Don't start if already simulating
    if (isSimulating) return;

    const sequence: SpinState[] = [
      'spin_start',
      'reels_spinning',
      'reel_stop_1',
      'reel_stop_2',
      'reel_stop_3',
      'reel_stop_4',
      'reel_stop_5',
      'evaluation',
      Math.random() > 0.3 ? 'win' : 'lose',
      'idle',
    ];

    let i = 0;
    const interval = setInterval(() => {
      if (i >= sequence.length) {
        clearInterval(interval);
        return;
      }
      onStateChange?.(sequence[i]);
      i++;
    }, config.reelStopInterval);

    // Start immediately with first state
    onStateChange?.(sequence[0]);
    i = 1;
  }, [isSimulating, onStateChange, config.reelStopInterval]);

  return (
    <div className="rf-spin-cycle-editor">
      {/* Header */}
      <div className="rf-spin-cycle-editor__header">
        <span className="rf-spin-cycle-editor__title">Spin Cycle State Machine</span>
        <div className="rf-spin-cycle-editor__controls">
          <span className="rf-spin-cycle-editor__status">
            Current: <strong>{STATE_LABELS[currentState]}</strong>
          </span>
          <button
            className="rf-spin-cycle-editor__btn"
            onClick={handleSimulate}
            disabled={isSimulating}
          >
            {isSimulating ? '⏳ Simulating...' : '▶ Simulate Spin'}
          </button>
        </div>
      </div>

      {/* State Machine Diagram */}
      <div className="rf-spin-cycle-editor__diagram">
        <svg
          ref={svgRef}
          viewBox="0 0 700 300"
          className="rf-spin-cycle-editor__svg"
        >
          {/* Connections */}
          {CONNECTIONS.map((conn, i) => (
            <Connection
              key={i}
              from={STATE_POSITIONS[conn.from]}
              to={STATE_POSITIONS[conn.to]}
              label={conn.label}
              isActive={currentState === conn.from}
            />
          ))}

          {/* State Nodes */}
          {Object.entries(STATE_POSITIONS).map(([stateId, pos]) => (
            <StateNode
              key={stateId}
              state={getStateConfig(stateId as SpinState)}
              position={pos}
              isActive={currentState === stateId}
              isSelected={selectedState === stateId}
              onClick={() => handleStateClick(stateId as SpinState)}
              onSoundClick={(soundId) => onSoundSelect?.(stateId as SpinState, soundId)}
            />
          ))}
        </svg>
      </div>

      {/* Sound List Panel */}
      <SoundList
        state={selectedState ? getStateConfig(selectedState) : null}
        onSoundAdd={handleSoundAdd}
        onSoundRemove={handleSoundRemove}
        onSoundEdit={handleSoundEdit}
      />

      {/* Settings */}
      <div className="rf-spin-cycle-editor__settings">
        <div className="rf-spin-cycle-editor__setting">
          <label>Reel Stop Interval</label>
          <input
            type="number"
            value={config.reelStopInterval}
            onChange={(e) =>
              onConfigChange?.({
                ...config,
                reelStopInterval: parseInt(e.target.value) || 300,
              })
            }
          />
          <span>ms</span>
        </div>
        <div className="rf-spin-cycle-editor__setting">
          <label>Anticipation Trigger</label>
          <input
            type="number"
            value={config.anticipationReels}
            min={2}
            max={4}
            onChange={(e) =>
              onConfigChange?.({
                ...config,
                anticipationReels: parseInt(e.target.value) || 2,
              })
            }
          />
          <span>matching symbols</span>
        </div>
      </div>
    </div>
  );
});

// ============ Demo Data ============

export function generateDemoSpinCycleConfig(): SpinCycleConfig {
  return {
    reelStopInterval: 300,
    anticipationReels: 2,
    states: [
      {
        stateId: 'idle',
        sounds: [
          { id: 'amb-idle', name: 'ambient_idle_loop', type: 'loop' },
        ],
      },
      {
        stateId: 'spin_start',
        sounds: [
          { id: 'spin-start', name: 'spin_button_click', type: 'oneshot' },
          { id: 'spin-whoosh', name: 'spin_whoosh', type: 'oneshot', delay: 50 },
        ],
        duration: 200,
        nextState: 'reels_spinning',
      },
      {
        stateId: 'reels_spinning',
        sounds: [
          { id: 'reel-spin', name: 'reel_spin_loop', type: 'loop' },
        ],
      },
      {
        stateId: 'reel_stop_1',
        sounds: [
          { id: 'stop-1', name: 'reel_stop_01', type: 'oneshot' },
          { id: 'thud-1', name: 'reel_thud_01', type: 'oneshot', delay: 20 },
        ],
      },
      {
        stateId: 'reel_stop_2',
        sounds: [
          { id: 'stop-2', name: 'reel_stop_02', type: 'oneshot' },
        ],
      },
      {
        stateId: 'reel_stop_3',
        sounds: [
          { id: 'stop-3', name: 'reel_stop_03', type: 'oneshot' },
        ],
      },
      {
        stateId: 'reel_stop_4',
        sounds: [
          { id: 'stop-4', name: 'reel_stop_04', type: 'oneshot' },
        ],
      },
      {
        stateId: 'reel_stop_5',
        sounds: [
          { id: 'stop-5', name: 'reel_stop_05', type: 'oneshot' },
          { id: 'stop-final', name: 'reel_stop_final', type: 'oneshot', delay: 50 },
        ],
      },
      {
        stateId: 'anticipation',
        sounds: [
          { id: 'antic-riser', name: 'anticipation_riser', type: 'oneshot' },
          { id: 'antic-loop', name: 'anticipation_tension_loop', type: 'loop', delay: 200 },
        ],
      },
      {
        stateId: 'evaluation',
        sounds: [],
        duration: 100,
      },
      {
        stateId: 'win',
        sounds: [
          { id: 'win-sting', name: 'win_sting_small', type: 'oneshot' },
        ],
        conditions: [
          { type: 'win_amount', value: 20, targetState: 'win' },
        ],
      },
      {
        stateId: 'lose',
        sounds: [
          { id: 'no-win', name: 'no_win_subtle', type: 'oneshot' },
        ],
      },
    ],
  };
}

export default SpinCycleEditor;
