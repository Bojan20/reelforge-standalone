/**
 * Game Sync Manager
 *
 * Wwise-style game state synchronization.
 * Manages discrete game states, switches, and triggers.
 *
 * State Groups: Mutually exclusive states (game_mode, feature_type)
 * Switches: Per-object state selection (symbol_type, reel_id)
 * Triggers: One-shot events (spin_start, win_landed)
 */

import type { BusId } from './types';

// ============ TYPES ============

export type GameSyncType = 'state' | 'switch' | 'trigger';

export interface StateAction {
  /** Action type */
  type: 'play' | 'stop' | 'pause' | 'resume' | 'set-rtpc' | 'set-volume';
  /** Target sound/bus ID */
  targetId?: string;
  /** Target type */
  targetType?: 'sound' | 'bus';
  /** For set-rtpc */
  rtpcName?: string;
  rtpcValue?: number;
  /** For set-volume */
  volume?: number;
  /** Fade time in ms */
  fadeMs?: number;
  /** Delay before action */
  delayMs?: number;
}

export interface StateDefinition {
  /** State name */
  name: string;
  /** Display name */
  displayName?: string;
  /** Actions when entering this state */
  onEnter?: StateAction[];
  /** Actions when exiting this state */
  onExit?: StateAction[];
}

export interface StateGroup {
  /** Group name (e.g., 'game_mode', 'feature_type') */
  name: string;
  /** Display name */
  displayName: string;
  /** Description */
  description?: string;
  /** Default state */
  defaultState: string;
  /** Available states */
  states: StateDefinition[];
  /** Transition time between states (ms) */
  transitionMs?: number;
}

export interface SwitchValue {
  /** Switch value name */
  name: string;
  /** Sound to play for this switch value */
  soundId: string;
  /** Volume modifier */
  volume?: number;
  /** Pitch modifier */
  pitch?: number;
}

export interface SwitchGroup {
  /** Switch name */
  name: string;
  /** Display name */
  displayName: string;
  /** Description */
  description?: string;
  /** Default value */
  defaultValue: string;
  /** Switch values */
  values: SwitchValue[];
}

export interface TriggerAction {
  /** Action type */
  type: 'play' | 'stop' | 'stop-all' | 'set-state' | 'set-rtpc';
  /** Target ID */
  targetId?: string;
  /** Bus for play action */
  bus?: BusId;
  /** Volume for play action */
  volume?: number;
  /** State group for set-state */
  stateGroup?: string;
  /** State name for set-state */
  stateName?: string;
  /** RTPC name for set-rtpc */
  rtpcName?: string;
  /** RTPC value for set-rtpc */
  rtpcValue?: number;
  /** Delay before action */
  delayMs?: number;
}

export interface Trigger {
  /** Trigger name */
  name: string;
  /** Display name */
  displayName: string;
  /** Description */
  description?: string;
  /** Actions to execute */
  actions: TriggerAction[];
}

export interface ActiveState {
  groupName: string;
  currentState: string;
  previousState: string | null;
  transitionStartTime: number;
  isTransitioning: boolean;
}

// ============ GAME SYNC MANAGER ============

export class GameSyncManager {
  private stateGroups: Map<string, StateGroup> = new Map();
  private switchGroups: Map<string, SwitchGroup> = new Map();
  private triggers: Map<string, Trigger> = new Map();

  private activeStates: Map<string, ActiveState> = new Map();
  private activeSwitches: Map<string, string> = new Map(); // groupName → currentValue

  private pendingTimers: number[] = [];

  // Callbacks
  private playCallback: (assetId: string, bus: BusId, volume: number) => string | null;
  private stopCallback: (assetId: string, fadeMs?: number) => void;
  private stopAllCallback: (bus?: BusId, fadeMs?: number) => void;
  private setVolumeCallback: (targetId: string, targetType: 'sound' | 'bus', volume: number, fadeMs?: number) => void;
  private setRTPCCallback: (name: string, value: number) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number) => string | null,
    stopCallback: (assetId: string, fadeMs?: number) => void,
    stopAllCallback: (bus?: BusId, fadeMs?: number) => void,
    setVolumeCallback: (targetId: string, targetType: 'sound' | 'bus', volume: number, fadeMs?: number) => void,
    setRTPCCallback: (name: string, value: number) => void,
    stateGroups?: StateGroup[],
    switchGroups?: SwitchGroup[],
    triggers?: Trigger[]
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.stopAllCallback = stopAllCallback;
    this.setVolumeCallback = setVolumeCallback;
    this.setRTPCCallback = setRTPCCallback;

    // Register defaults
    DEFAULT_STATE_GROUPS.forEach(g => this.registerStateGroup(g));
    DEFAULT_SWITCH_GROUPS.forEach(g => this.registerSwitchGroup(g));
    DEFAULT_TRIGGERS.forEach(t => this.registerTrigger(t));

    // Register custom
    stateGroups?.forEach(g => this.registerStateGroup(g));
    switchGroups?.forEach(g => this.registerSwitchGroup(g));
    triggers?.forEach(t => this.registerTrigger(t));
  }

  // ============ STATE GROUPS ============

  /**
   * Register a state group
   */
  registerStateGroup(group: StateGroup): void {
    this.stateGroups.set(group.name, group);

    // Initialize to default state
    this.activeStates.set(group.name, {
      groupName: group.name,
      currentState: group.defaultState,
      previousState: null,
      transitionStartTime: 0,
      isTransitioning: false,
    });
  }

  /**
   * Set state in a group
   */
  setState(groupName: string, stateName: string): boolean {
    const group = this.stateGroups.get(groupName);
    if (!group) return false;

    const newState = group.states.find(s => s.name === stateName);
    if (!newState) return false;

    const active = this.activeStates.get(groupName);
    if (!active) return false;

    // Already in this state
    if (active.currentState === stateName && !active.isTransitioning) {
      return true;
    }

    const oldState = group.states.find(s => s.name === active.currentState);

    // Execute exit actions for old state
    if (oldState?.onExit) {
      this.executeStateActions(oldState.onExit);
    }

    // Update active state
    active.previousState = active.currentState;
    active.currentState = stateName;
    active.transitionStartTime = performance.now();
    active.isTransitioning = group.transitionMs ? true : false;

    // Execute enter actions for new state
    if (newState.onEnter) {
      this.executeStateActions(newState.onEnter);
    }

    // Clear transition flag after transition time
    if (group.transitionMs) {
      const timer = window.setTimeout(() => {
        active.isTransitioning = false;
      }, group.transitionMs);
      this.pendingTimers.push(timer);
    }

    return true;
  }

  /**
   * Get current state of a group
   */
  getState(groupName: string): string | null {
    return this.activeStates.get(groupName)?.currentState ?? null;
  }

  /**
   * Execute state actions
   */
  private executeStateActions(actions: StateAction[]): void {
    for (const action of actions) {
      const execute = () => {
        switch (action.type) {
          case 'play':
            if (action.targetId) {
              this.playCallback(action.targetId, 'sfx', action.volume ?? 1);
            }
            break;

          case 'stop':
            if (action.targetId) {
              this.stopCallback(action.targetId, action.fadeMs);
            }
            break;

          case 'pause':
          case 'resume':
            // Would need additional callbacks
            break;

          case 'set-rtpc':
            if (action.rtpcName !== undefined && action.rtpcValue !== undefined) {
              this.setRTPCCallback(action.rtpcName, action.rtpcValue);
            }
            break;

          case 'set-volume':
            if (action.targetId && action.targetType && action.volume !== undefined) {
              this.setVolumeCallback(action.targetId, action.targetType, action.volume, action.fadeMs);
            }
            break;
        }
      };

      if (action.delayMs) {
        const timer = window.setTimeout(execute, action.delayMs);
        this.pendingTimers.push(timer);
      } else {
        execute();
      }
    }
  }

  // ============ SWITCHES ============

  /**
   * Register a switch group
   */
  registerSwitchGroup(group: SwitchGroup): void {
    this.switchGroups.set(group.name, group);
    this.activeSwitches.set(group.name, group.defaultValue);
  }

  /**
   * Set switch value
   */
  setSwitch(groupName: string, valueName: string): boolean {
    const group = this.switchGroups.get(groupName);
    if (!group) return false;

    const value = group.values.find(v => v.name === valueName);
    if (!value) return false;

    this.activeSwitches.set(groupName, valueName);
    return true;
  }

  /**
   * Get current switch value
   */
  getSwitch(groupName: string): string | null {
    return this.activeSwitches.get(groupName) ?? null;
  }

  /**
   * Play sound based on current switch value
   */
  playSwitched(groupName: string, bus: BusId, baseVolume: number = 1): string | null {
    const group = this.switchGroups.get(groupName);
    if (!group) return null;

    const currentValue = this.activeSwitches.get(groupName);
    if (!currentValue) return null;

    const switchValue = group.values.find(v => v.name === currentValue);
    if (!switchValue) return null;

    const volume = baseVolume * (switchValue.volume ?? 1);
    return this.playCallback(switchValue.soundId, bus, volume);
  }

  // ============ TRIGGERS ============

  /**
   * Register a trigger
   */
  registerTrigger(trigger: Trigger): void {
    this.triggers.set(trigger.name, trigger);
  }

  /**
   * Post a trigger
   */
  postTrigger(name: string): boolean {
    const trigger = this.triggers.get(name);
    if (!trigger) return false;

    for (const action of trigger.actions) {
      const execute = () => {
        switch (action.type) {
          case 'play':
            if (action.targetId) {
              this.playCallback(action.targetId, action.bus ?? 'sfx', action.volume ?? 1);
            }
            break;

          case 'stop':
            if (action.targetId) {
              this.stopCallback(action.targetId);
            }
            break;

          case 'stop-all':
            this.stopAllCallback(action.bus);
            break;

          case 'set-state':
            if (action.stateGroup && action.stateName) {
              this.setState(action.stateGroup, action.stateName);
            }
            break;

          case 'set-rtpc':
            if (action.rtpcName !== undefined && action.rtpcValue !== undefined) {
              this.setRTPCCallback(action.rtpcName, action.rtpcValue);
            }
            break;
        }
      };

      if (action.delayMs) {
        const timer = window.setTimeout(execute, action.delayMs);
        this.pendingTimers.push(timer);
      } else {
        execute();
      }
    }

    return true;
  }

  // ============ UTILITIES ============

  /**
   * Get all state groups
   */
  getStateGroups(): StateGroup[] {
    return Array.from(this.stateGroups.values());
  }

  /**
   * Get all switch groups
   */
  getSwitchGroups(): SwitchGroup[] {
    return Array.from(this.switchGroups.values());
  }

  /**
   * Get all triggers
   */
  getTriggers(): Trigger[] {
    return Array.from(this.triggers.values());
  }

  /**
   * Get full sync state snapshot
   */
  getSnapshot(): {
    states: Record<string, string>;
    switches: Record<string, string>;
  } {
    const states: Record<string, string> = {};
    const switches: Record<string, string> = {};

    this.activeStates.forEach((active, name) => {
      states[name] = active.currentState;
    });

    this.activeSwitches.forEach((value, name) => {
      switches[name] = value;
    });

    return { states, switches };
  }

  /**
   * Restore sync state from snapshot
   */
  restoreSnapshot(snapshot: { states: Record<string, string>; switches: Record<string, string> }): void {
    Object.entries(snapshot.states).forEach(([group, state]) => {
      this.setState(group, state);
    });

    Object.entries(snapshot.switches).forEach(([group, value]) => {
      this.setSwitch(group, value);
    });
  }

  /**
   * Dispose manager
   */
  dispose(): void {
    // Clear pending timers
    this.pendingTimers.forEach(timer => clearTimeout(timer));
    this.pendingTimers = [];

    this.stateGroups.clear();
    this.switchGroups.clear();
    this.triggers.clear();
    this.activeStates.clear();
    this.activeSwitches.clear();
  }
}

// ============ DEFAULT STATE GROUPS ============

export const DEFAULT_STATE_GROUPS: StateGroup[] = [
  {
    name: 'game_mode',
    displayName: 'Game Mode',
    description: 'Main game mode state',
    defaultState: 'idle',
    transitionMs: 500,
    states: [
      {
        name: 'idle',
        displayName: 'Idle',
        onEnter: [
          { type: 'set-rtpc', rtpcName: 'anticipation_level', rtpcValue: 0 },
          { type: 'set-volume', targetId: 'music', targetType: 'bus', volume: 0.8, fadeMs: 1000 },
        ],
      },
      {
        name: 'spinning',
        displayName: 'Spinning',
        onEnter: [
          { type: 'play', targetId: 'reel_spin_start' },
          { type: 'set-rtpc', rtpcName: 'spin_speed', rtpcValue: 1 },
        ],
        onExit: [
          { type: 'set-rtpc', rtpcName: 'spin_speed', rtpcValue: 0 },
        ],
      },
      {
        name: 'turbo_spinning',
        displayName: 'Turbo Spinning',
        onEnter: [
          { type: 'play', targetId: 'reel_spin_turbo' },
          { type: 'set-rtpc', rtpcName: 'spin_speed', rtpcValue: 2 },
        ],
        onExit: [
          { type: 'set-rtpc', rtpcName: 'spin_speed', rtpcValue: 0 },
        ],
      },
      {
        name: 'evaluating',
        displayName: 'Evaluating Wins',
      },
      {
        name: 'celebrating',
        displayName: 'Win Celebration',
        onEnter: [
          { type: 'set-volume', targetId: 'music', targetType: 'bus', volume: 0.4, fadeMs: 200 },
        ],
        onExit: [
          { type: 'set-volume', targetId: 'music', targetType: 'bus', volume: 0.8, fadeMs: 500 },
        ],
      },
    ],
  },
  {
    name: 'feature_type',
    displayName: 'Feature Type',
    description: 'Active bonus feature',
    defaultState: 'none',
    transitionMs: 1000,
    states: [
      {
        name: 'none',
        displayName: 'Base Game',
      },
      {
        name: 'free_spins',
        displayName: 'Free Spins',
        onEnter: [
          { type: 'stop', targetId: 'music_base', fadeMs: 500 },
          { type: 'play', targetId: 'music_freespins', delayMs: 500 },
          { type: 'set-rtpc', rtpcName: 'feature_progress', rtpcValue: 0 },
        ],
        onExit: [
          { type: 'stop', targetId: 'music_freespins', fadeMs: 1000 },
          { type: 'play', targetId: 'music_base', delayMs: 1000 },
        ],
      },
      {
        name: 'bonus',
        displayName: 'Bonus Game',
        onEnter: [
          { type: 'stop', targetId: 'music_base', fadeMs: 500 },
          { type: 'play', targetId: 'music_bonus', delayMs: 500 },
        ],
        onExit: [
          { type: 'stop', targetId: 'music_bonus', fadeMs: 1000 },
          { type: 'play', targetId: 'music_base', delayMs: 1000 },
        ],
      },
      {
        name: 'hold_and_win',
        displayName: 'Hold & Win',
        onEnter: [
          { type: 'stop', targetId: 'music_base', fadeMs: 300 },
          { type: 'play', targetId: 'music_hold_win', delayMs: 300 },
        ],
        onExit: [
          { type: 'stop', targetId: 'music_hold_win', fadeMs: 500 },
          { type: 'play', targetId: 'music_base', delayMs: 500 },
        ],
      },
    ],
  },
  {
    name: 'anticipation_state',
    displayName: 'Anticipation State',
    description: 'Near-win anticipation level',
    defaultState: 'none',
    states: [
      {
        name: 'none',
        onEnter: [{ type: 'set-rtpc', rtpcName: 'anticipation_level', rtpcValue: 0 }],
      },
      {
        name: 'low',
        onEnter: [
          { type: 'set-rtpc', rtpcName: 'anticipation_level', rtpcValue: 0.3 },
          { type: 'play', targetId: 'anticipation_low' },
        ],
      },
      {
        name: 'medium',
        onEnter: [
          { type: 'set-rtpc', rtpcName: 'anticipation_level', rtpcValue: 0.6 },
          { type: 'play', targetId: 'anticipation_medium' },
        ],
      },
      {
        name: 'high',
        onEnter: [
          { type: 'set-rtpc', rtpcName: 'anticipation_level', rtpcValue: 1.0 },
          { type: 'play', targetId: 'anticipation_high' },
        ],
      },
    ],
  },
];

// ============ DEFAULT SWITCH GROUPS ============

export const DEFAULT_SWITCH_GROUPS: SwitchGroup[] = [
  {
    name: 'symbol_type',
    displayName: 'Symbol Type',
    description: 'Current symbol for contextual sounds',
    defaultValue: 'low',
    values: [
      { name: 'low', soundId: 'symbol_land_low', volume: 0.8 },
      { name: 'medium', soundId: 'symbol_land_medium', volume: 0.9 },
      { name: 'high', soundId: 'symbol_land_high', volume: 1.0 },
      { name: 'wild', soundId: 'symbol_land_wild', volume: 1.0 },
      { name: 'scatter', soundId: 'symbol_land_scatter', volume: 1.0 },
      { name: 'bonus', soundId: 'symbol_land_bonus', volume: 1.0 },
    ],
  },
  {
    name: 'reel_position',
    displayName: 'Reel Position',
    description: 'Which reel for positional audio',
    defaultValue: 'reel_3',
    values: [
      { name: 'reel_1', soundId: 'reel_stop', volume: 1.0 },
      { name: 'reel_2', soundId: 'reel_stop', volume: 1.0 },
      { name: 'reel_3', soundId: 'reel_stop', volume: 1.0 },
      { name: 'reel_4', soundId: 'reel_stop', volume: 1.0 },
      { name: 'reel_5', soundId: 'reel_stop', volume: 1.0 },
    ],
  },
  {
    name: 'win_tier',
    displayName: 'Win Tier',
    description: 'Win size for celebration sounds',
    defaultValue: 'none',
    values: [
      { name: 'none', soundId: 'silence', volume: 0 },
      { name: 'small', soundId: 'win_small', volume: 0.8 },
      { name: 'medium', soundId: 'win_medium', volume: 0.9 },
      { name: 'big', soundId: 'win_big', volume: 1.0 },
      { name: 'mega', soundId: 'win_mega', volume: 1.0 },
      { name: 'epic', soundId: 'win_epic', volume: 1.0 },
    ],
  },
];

// ============ DEFAULT TRIGGERS ============

export const DEFAULT_TRIGGERS: Trigger[] = [
  {
    name: 'spin_start',
    displayName: 'Spin Start',
    description: 'Triggered when spin button pressed',
    actions: [
      { type: 'set-state', stateGroup: 'game_mode', stateName: 'spinning' },
      { type: 'play', targetId: 'button_spin', bus: 'sfx', volume: 1 },
    ],
  },
  {
    name: 'spin_end',
    displayName: 'Spin End',
    description: 'Triggered when all reels stopped',
    actions: [
      { type: 'set-state', stateGroup: 'game_mode', stateName: 'evaluating' },
      { type: 'set-state', stateGroup: 'anticipation_state', stateName: 'none' },
    ],
  },
  {
    name: 'win_start',
    displayName: 'Win Start',
    description: 'Triggered when win celebration begins',
    actions: [
      { type: 'set-state', stateGroup: 'game_mode', stateName: 'celebrating' },
    ],
  },
  {
    name: 'win_end',
    displayName: 'Win End',
    description: 'Triggered when win celebration ends',
    actions: [
      { type: 'set-state', stateGroup: 'game_mode', stateName: 'idle' },
      { type: 'set-rtpc', rtpcName: 'win_tier', rtpcValue: 0 },
    ],
  },
  {
    name: 'feature_trigger',
    displayName: 'Feature Trigger',
    description: 'Triggered when bonus feature starts',
    actions: [
      { type: 'play', targetId: 'feature_trigger_sfx', bus: 'sfx', volume: 1 },
      { type: 'stop-all', bus: 'sfx', delayMs: 100 },
    ],
  },
  {
    name: 'scatter_land',
    displayName: 'Scatter Land',
    description: 'Triggered when scatter symbol lands',
    actions: [
      { type: 'play', targetId: 'scatter_land', bus: 'sfx', volume: 1 },
    ],
  },
  {
    name: 'wild_expand',
    displayName: 'Wild Expand',
    description: 'Triggered when wild expands',
    actions: [
      { type: 'play', targetId: 'wild_expand', bus: 'sfx', volume: 1 },
    ],
  },
];
