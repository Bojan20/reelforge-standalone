/**
 * Switch Container System
 *
 * Wwise-style switch containers for state-driven audio:
 * - Switch groups with named states
 * - Containers that respond to switch changes
 * - Smooth transitions between switch values
 * - Default values and fallbacks
 * - Nested switch containers
 */

import type { BusId } from './types';

// ============ TYPES ============

export type SwitchTransitionMode = 'immediate' | 'crossfade' | 'wait-end' | 'next-beat' | 'next-bar';

export interface SwitchValue {
  /** Switch value name */
  name: string;
  /** Display label */
  label?: string;
  /** Description */
  description?: string;
}

export interface SwitchGroup {
  /** Unique ID */
  id: string;
  /** Display name */
  name: string;
  /** Available switch values */
  values: SwitchValue[];
  /** Default value */
  defaultValue: string;
  /** Current value */
  currentValue: string;
}

export interface SwitchContainerChild {
  /** Associated switch value */
  switchValue: string;
  /** Asset ID to play */
  assetId: string;
  /** Volume (0-1) */
  volume: number;
  /** Pitch adjustment (semitones) */
  pitch: number;
  /** Loop */
  loop: boolean;
  /** Play offset (seconds) */
  startOffset: number;
  /** Fade in time (ms) */
  fadeInMs: number;
  /** Fade out time (ms) */
  fadeOutMs: number;
}

export interface SwitchContainerConfig {
  /** Unique ID */
  id: string;
  /** Display name */
  name: string;
  /** Switch group this container responds to */
  switchGroupId: string;
  /** Default switch value (overrides group default) */
  defaultSwitch?: string;
  /** Children mapped to switch values */
  children: SwitchContainerChild[];
  /** Transition mode */
  transitionMode: SwitchTransitionMode;
  /** Crossfade time (ms) */
  crossfadeMs: number;
  /** Output bus */
  outputBus: BusId;
  /** Volume (0-1) */
  volume: number;
  /** Play at exit cue (if defined in audio) */
  playAtExitCue: boolean;
}

export interface ActiveSwitchVoice {
  /** Child being played */
  child: SwitchContainerChild;
  /** Voice ID from audio engine */
  voiceId: string;
  /** Is fading out */
  fadingOut: boolean;
}

export interface ActiveSwitchContainer {
  /** Configuration */
  config: SwitchContainerConfig;
  /** Currently playing voice */
  currentVoice: ActiveSwitchVoice | null;
  /** Voice being faded out */
  outgoingVoice: ActiveSwitchVoice | null;
  /** Is playing */
  isPlaying: boolean;
  /** Pending switch change (for beat-sync) */
  pendingSwitch: string | null;
}

// ============ SWITCH CONTAINER MANAGER ============

export class SwitchContainerManager {
  private switchGroups: Map<string, SwitchGroup> = new Map();
  private containers: Map<string, SwitchContainerConfig> = new Map();
  private activeContainers: Map<string, ActiveSwitchContainer> = new Map();

  // Callbacks for audio engine integration
  private playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null;
  private stopCallback: (voiceId: string, fadeMs?: number) => void;
  private setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void;
  private onSwitchChange?: (groupId: string, oldValue: string, newValue: string) => void;
  private onContainerTrigger?: (containerId: string, switchValue: string) => void;

  constructor(
    playCallback: (assetId: string, bus: BusId, volume: number, loop: boolean) => string | null,
    stopCallback: (voiceId: string, fadeMs?: number) => void,
    setVolumeCallback: (voiceId: string, volume: number, fadeMs?: number) => void,
    callbacks?: {
      onSwitchChange?: (groupId: string, oldValue: string, newValue: string) => void;
      onContainerTrigger?: (containerId: string, switchValue: string) => void;
    }
  ) {
    this.playCallback = playCallback;
    this.stopCallback = stopCallback;
    this.setVolumeCallback = setVolumeCallback;
    this.onSwitchChange = callbacks?.onSwitchChange;
    this.onContainerTrigger = callbacks?.onContainerTrigger;
  }

  // ============ SWITCH GROUP MANAGEMENT ============

  /**
   * Register a switch group
   */
  registerSwitchGroup(group: SwitchGroup): void {
    this.switchGroups.set(group.id, {
      ...group,
      currentValue: group.defaultValue,
    });
  }

  /**
   * Get switch group
   */
  getSwitchGroup(groupId: string): SwitchGroup | undefined {
    return this.switchGroups.get(groupId);
  }

  /**
   * Get all switch groups
   */
  getAllSwitchGroups(): SwitchGroup[] {
    return Array.from(this.switchGroups.values());
  }

  /**
   * Set switch value (triggers container updates)
   */
  setSwitch(groupId: string, value: string): void {
    const group = this.switchGroups.get(groupId);
    if (!group) {
      console.warn(`Switch group not found: ${groupId}`);
      return;
    }

    // Validate value exists in group
    if (!group.values.some(v => v.name === value)) {
      console.warn(`Invalid switch value: ${value} for group ${groupId}`);
      return;
    }

    const oldValue = group.currentValue;
    if (oldValue === value) return; // No change

    group.currentValue = value;
    this.onSwitchChange?.(groupId, oldValue, value);

    // Update all containers listening to this group
    this.activeContainers.forEach((active, containerId) => {
      if (active.config.switchGroupId === groupId) {
        this.handleSwitchChange(containerId, value);
      }
    });
  }

  /**
   * Get current switch value
   */
  getSwitch(groupId: string): string | undefined {
    return this.switchGroups.get(groupId)?.currentValue;
  }

  /**
   * Reset switch to default
   */
  resetSwitch(groupId: string): void {
    const group = this.switchGroups.get(groupId);
    if (group) {
      this.setSwitch(groupId, group.defaultValue);
    }
  }

  // ============ CONTAINER MANAGEMENT ============

  /**
   * Register a switch container
   */
  registerContainer(config: SwitchContainerConfig): void {
    this.containers.set(config.id, config);
  }

  /**
   * Get container config
   */
  getContainer(containerId: string): SwitchContainerConfig | undefined {
    return this.containers.get(containerId);
  }

  /**
   * Get all containers
   */
  getAllContainers(): SwitchContainerConfig[] {
    return Array.from(this.containers.values());
  }

  /**
   * Get containers for a switch group
   */
  getContainersForGroup(groupId: string): SwitchContainerConfig[] {
    return Array.from(this.containers.values())
      .filter(c => c.switchGroupId === groupId);
  }

  // ============ PLAYBACK ============

  /**
   * Start a switch container
   */
  play(containerId: string): void {
    const config = this.containers.get(containerId);
    if (!config) {
      console.warn(`Switch container not found: ${containerId}`);
      return;
    }

    // Get current switch value
    const group = this.switchGroups.get(config.switchGroupId);
    const switchValue = config.defaultSwitch ?? group?.currentValue ?? '';

    // Find matching child
    const child = config.children.find(c => c.switchValue === switchValue);
    if (!child) {
      console.warn(`No child for switch value: ${switchValue}`);
      return;
    }

    // Create active container
    const active: ActiveSwitchContainer = {
      config,
      currentVoice: null,
      outgoingVoice: null,
      isPlaying: true,
      pendingSwitch: null,
    };

    this.activeContainers.set(containerId, active);

    // Play the child
    this.playChild(containerId, child);
  }

  /**
   * Stop a switch container
   */
  stop(containerId: string, fadeMs?: number): void {
    const active = this.activeContainers.get(containerId);
    if (!active) return;

    // Stop current voice
    if (active.currentVoice) {
      const fade = fadeMs ?? active.currentVoice.child.fadeOutMs;
      this.stopCallback(active.currentVoice.voiceId, fade);
    }

    // Stop outgoing voice
    if (active.outgoingVoice) {
      this.stopCallback(active.outgoingVoice.voiceId, 0);
    }

    active.isPlaying = false;
    this.activeContainers.delete(containerId);
  }

  /**
   * Stop all containers
   */
  stopAll(fadeMs?: number): void {
    const containerIds = Array.from(this.activeContainers.keys());
    containerIds.forEach(id => this.stop(id, fadeMs));
  }

  /**
   * Play a specific child
   */
  private playChild(containerId: string, child: SwitchContainerChild): void {
    const active = this.activeContainers.get(containerId);
    if (!active) return;

    const volume = child.volume * active.config.volume;
    const voiceId = this.playCallback(
      child.assetId,
      active.config.outputBus,
      child.fadeInMs > 0 ? 0 : volume,
      child.loop
    );

    if (!voiceId) {
      console.warn(`Failed to play switch child: ${child.assetId}`);
      return;
    }

    // Fade in if needed
    if (child.fadeInMs > 0) {
      this.setVolumeCallback(voiceId, volume, child.fadeInMs);
    }

    active.currentVoice = {
      child,
      voiceId,
      fadingOut: false,
    };

    this.onContainerTrigger?.(containerId, child.switchValue);
  }

  /**
   * Handle switch value change for active container
   */
  private handleSwitchChange(containerId: string, newValue: string): void {
    const active = this.activeContainers.get(containerId);
    if (!active || !active.isPlaying) return;

    // Already on this switch value
    if (active.currentVoice?.child.switchValue === newValue) return;

    // Find new child
    const newChild = active.config.children.find(c => c.switchValue === newValue);
    if (!newChild) return;

    // Handle transition based on mode
    switch (active.config.transitionMode) {
      case 'immediate':
        this.transitionImmediate(containerId, newChild);
        break;

      case 'crossfade':
        this.transitionCrossfade(containerId, newChild);
        break;

      case 'wait-end':
        // Queue the switch for when current finishes
        active.pendingSwitch = newValue;
        break;

      case 'next-beat':
      case 'next-bar':
        // Queue for beat sync (would integrate with beat clock)
        active.pendingSwitch = newValue;
        break;
    }
  }

  /**
   * Immediate transition
   */
  private transitionImmediate(containerId: string, newChild: SwitchContainerChild): void {
    const active = this.activeContainers.get(containerId);
    if (!active) return;

    // Stop current
    if (active.currentVoice) {
      this.stopCallback(active.currentVoice.voiceId, 0);
    }

    // Play new
    this.playChild(containerId, newChild);
  }

  /**
   * Crossfade transition
   */
  private transitionCrossfade(containerId: string, newChild: SwitchContainerChild): void {
    const active = this.activeContainers.get(containerId);
    if (!active) return;

    const crossfadeMs = active.config.crossfadeMs;

    // Move current to outgoing
    if (active.currentVoice) {
      active.outgoingVoice = active.currentVoice;
      active.outgoingVoice.fadingOut = true;

      // Fade out
      this.setVolumeCallback(active.outgoingVoice.voiceId, 0, crossfadeMs);

      // Schedule stop
      setTimeout(() => {
        if (active.outgoingVoice) {
          this.stopCallback(active.outgoingVoice.voiceId, 0);
          active.outgoingVoice = null;
        }
      }, crossfadeMs);
    }

    // Play new with fade in
    const volume = newChild.volume * active.config.volume;
    const voiceId = this.playCallback(
      newChild.assetId,
      active.config.outputBus,
      0, // Start at 0
      newChild.loop
    );

    if (voiceId) {
      // Fade in
      this.setVolumeCallback(voiceId, volume, crossfadeMs);

      active.currentVoice = {
        child: newChild,
        voiceId,
        fadingOut: false,
      };

      this.onContainerTrigger?.(containerId, newChild.switchValue);
    }
  }

  /**
   * Process pending switches (call on beat/bar/end)
   */
  processPendingSwitch(containerId: string): void {
    const active = this.activeContainers.get(containerId);
    if (!active || !active.pendingSwitch) return;

    const newChild = active.config.children.find(c => c.switchValue === active.pendingSwitch);
    if (newChild) {
      active.pendingSwitch = null;
      this.transitionCrossfade(containerId, newChild);
    }
  }

  // ============ QUERIES ============

  /**
   * Check if container is playing
   */
  isPlaying(containerId: string): boolean {
    return this.activeContainers.get(containerId)?.isPlaying ?? false;
  }

  /**
   * Get current switch value for active container
   */
  getCurrentSwitchValue(containerId: string): string | null {
    const active = this.activeContainers.get(containerId);
    return active?.currentVoice?.child.switchValue ?? null;
  }

  /**
   * Get all active containers
   */
  getActiveContainers(): string[] {
    return Array.from(this.activeContainers.keys());
  }

  // ============ SERIALIZATION ============

  /**
   * Export configuration
   */
  exportConfig(): string {
    const data = {
      switchGroups: Array.from(this.switchGroups.values()),
      containers: Array.from(this.containers.values()),
    };
    return JSON.stringify(data, null, 2);
  }

  /**
   * Import configuration
   */
  importConfig(json: string): void {
    const data = JSON.parse(json) as {
      switchGroups: SwitchGroup[];
      containers: SwitchContainerConfig[];
    };

    data.switchGroups.forEach(g => this.registerSwitchGroup(g));
    data.containers.forEach(c => this.registerContainer(c));
  }

  // ============ DISPOSAL ============

  /**
   * Dispose manager
   */
  dispose(): void {
    this.stopAll(0);
    this.switchGroups.clear();
    this.containers.clear();
    this.activeContainers.clear();
  }
}

// ============ PRESET SWITCH GROUPS ============

export const PRESET_SWITCH_GROUPS: Record<string, Omit<SwitchGroup, 'currentValue'>> = {
  game_state: {
    id: 'game_state',
    name: 'Game State',
    values: [
      { name: 'idle', label: 'Idle', description: 'Player not spinning' },
      { name: 'spinning', label: 'Spinning', description: 'Reels are spinning' },
      { name: 'anticipation', label: 'Anticipation', description: 'Waiting for bonus' },
      { name: 'win', label: 'Win', description: 'Player won' },
      { name: 'big_win', label: 'Big Win', description: 'Big win celebration' },
      { name: 'bonus', label: 'Bonus', description: 'Bonus feature active' },
      { name: 'free_spins', label: 'Free Spins', description: 'Free spins mode' },
    ],
    defaultValue: 'idle',
  },
  music_intensity: {
    id: 'music_intensity',
    name: 'Music Intensity',
    values: [
      { name: 'low', label: 'Low', description: 'Calm background' },
      { name: 'medium', label: 'Medium', description: 'Normal gameplay' },
      { name: 'high', label: 'High', description: 'Exciting moments' },
      { name: 'max', label: 'Maximum', description: 'Peak intensity' },
    ],
    defaultValue: 'medium',
  },
  environment: {
    id: 'environment',
    name: 'Environment',
    values: [
      { name: 'default', label: 'Default', description: 'Standard environment' },
      { name: 'underwater', label: 'Underwater', description: 'Underwater theme' },
      { name: 'space', label: 'Space', description: 'Space theme' },
      { name: 'ancient', label: 'Ancient', description: 'Ancient theme' },
      { name: 'fantasy', label: 'Fantasy', description: 'Fantasy theme' },
    ],
    defaultValue: 'default',
  },
  time_of_day: {
    id: 'time_of_day',
    name: 'Time of Day',
    values: [
      { name: 'day', label: 'Day', description: 'Daytime' },
      { name: 'night', label: 'Night', description: 'Nighttime' },
      { name: 'dawn', label: 'Dawn', description: 'Dawn/Dusk' },
    ],
    defaultValue: 'day',
  },
  player_balance: {
    id: 'player_balance',
    name: 'Player Balance',
    values: [
      { name: 'low', label: 'Low Balance', description: 'Low balance warning' },
      { name: 'normal', label: 'Normal', description: 'Normal balance' },
      { name: 'high', label: 'High Balance', description: 'High balance' },
    ],
    defaultValue: 'normal',
  },
};
