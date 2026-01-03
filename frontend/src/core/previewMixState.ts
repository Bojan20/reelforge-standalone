/**
 * ReelForge M7.1 Preview Mix State
 *
 * Studio-side preview signal model that mirrors RuntimeCore routing behavior.
 * Signal chain: Asset -> Action Gain -> Bus Gain -> Ducking -> Master -> Output
 *
 * This is a pure state model with no DSP. DSP will be inserted later.
 */

import type { BusId } from './types';

/** Bus state in the preview mix */
export interface PreviewBusState {
  /** Current gain level (0-1) */
  gain: number;
  /** Base gain before ducking is applied */
  baseGain: number;
  /** Number of active voices on this bus */
  activeVoices: number;
  /** Whether this bus is currently being ducked */
  isDucked: boolean;
}

/** Full preview mix state */
export interface PreviewMixSnapshot {
  /** Per-bus state */
  buses: Record<BusId, PreviewBusState>;
  /** Master gain (0-1) */
  masterGain: number;
  /** Whether ducking is currently active (VO over Music) */
  duckingActive: boolean;
  /** Timestamp of last update */
  lastUpdated: number;
}

/** Ducking configuration (matches RuntimeCore) */
export const DUCKING_CONFIG = {
  /** Ducking ratio applied to Music when VO is active */
  DUCK_RATIO: 0.35,
  /** Bus that triggers ducking */
  DUCKER_BUS: 'voice' as BusId,
  /** Bus that gets ducked */
  DUCKED_BUS: 'music' as BusId,
} as const;

/** Maximum voices per bus (bounded state) */
const MAX_VOICES_PER_BUS = 64;

/** All supported bus IDs */
const ALL_BUSES: BusId[] = ['master', 'music', 'sfx', 'ambience', 'voice'];

/**
 * Creates a fresh preview mix state with default values.
 */
export function createInitialPreviewMixState(): PreviewMixSnapshot {
  const buses: Record<BusId, PreviewBusState> = {} as Record<BusId, PreviewBusState>;

  for (const busId of ALL_BUSES) {
    buses[busId] = {
      gain: 1,
      baseGain: 1,
      activeVoices: 0,
      isDucked: false,
    };
  }

  return {
    buses,
    masterGain: 1,
    duckingActive: false,
    lastUpdated: Date.now(),
  };
}

/**
 * Calculates effective gain for a bus (base gain with ducking applied).
 */
export function calculateEffectiveBusGain(state: PreviewMixSnapshot, busId: BusId): number {
  const bus = state.buses[busId];
  if (!bus) return 1;

  let gain = bus.baseGain;

  // Apply ducking if this is the ducked bus and ducking is active
  if (busId === DUCKING_CONFIG.DUCKED_BUS && state.duckingActive) {
    gain *= DUCKING_CONFIG.DUCK_RATIO;
  }

  return gain;
}

/**
 * Calculates full signal chain gain for a voice.
 * Asset -> Action Gain -> Bus Gain -> Ducking -> Master
 */
export function calculateVoiceOutputGain(
  state: PreviewMixSnapshot,
  actionGain: number,
  busId: BusId
): number {
  const busGain = calculateEffectiveBusGain(state, busId);
  return actionGain * busGain * state.masterGain;
}

/**
 * Updates bus gain (SetBusGain action).
 */
export function setBusGain(
  state: PreviewMixSnapshot,
  busId: BusId,
  gain: number
): PreviewMixSnapshot {
  const clampedGain = Math.max(0, Math.min(1, gain));

  if (busId === 'master') {
    return {
      ...state,
      masterGain: clampedGain,
      lastUpdated: Date.now(),
    };
  }

  const bus = state.buses[busId];
  if (!bus) return state;

  const newBus: PreviewBusState = {
    ...bus,
    baseGain: clampedGain,
    gain: calculateEffectiveBusGain({ ...state, buses: { ...state.buses, [busId]: { ...bus, baseGain: clampedGain } } }, busId),
  };

  return {
    ...state,
    buses: {
      ...state.buses,
      [busId]: newBus,
    },
    lastUpdated: Date.now(),
  };
}

/**
 * Increments voice count on a bus (when a Play starts).
 */
export function incrementVoiceCount(
  state: PreviewMixSnapshot,
  busId: BusId
): PreviewMixSnapshot {
  const bus = state.buses[busId];
  if (!bus) return state;

  // Bounded: don't exceed max
  const newCount = Math.min(bus.activeVoices + 1, MAX_VOICES_PER_BUS);
  const wasVOActive = state.buses.voice.activeVoices > 0;

  const newBus: PreviewBusState = {
    ...bus,
    activeVoices: newCount,
  };

  let newState: PreviewMixSnapshot = {
    ...state,
    buses: {
      ...state.buses,
      [busId]: newBus,
    },
    lastUpdated: Date.now(),
  };

  // Check if we need to apply ducking (VO started)
  if (busId === DUCKING_CONFIG.DUCKER_BUS && !wasVOActive && newCount > 0) {
    newState = applyDucking(newState, true);
  }

  return newState;
}

/**
 * Decrements voice count on a bus (when a sound ends or is stopped).
 */
export function decrementVoiceCount(
  state: PreviewMixSnapshot,
  busId: BusId
): PreviewMixSnapshot {
  const bus = state.buses[busId];
  if (!bus) return state;

  const newCount = Math.max(bus.activeVoices - 1, 0);

  const newBus: PreviewBusState = {
    ...bus,
    activeVoices: newCount,
  };

  let newState: PreviewMixSnapshot = {
    ...state,
    buses: {
      ...state.buses,
      [busId]: newBus,
    },
    lastUpdated: Date.now(),
  };

  // Check if we need to release ducking (last VO stopped)
  if (busId === DUCKING_CONFIG.DUCKER_BUS && newCount === 0) {
    newState = applyDucking(newState, false);
  }

  return newState;
}

/**
 * Sets voice count directly for a bus.
 */
export function setVoiceCount(
  state: PreviewMixSnapshot,
  busId: BusId,
  count: number
): PreviewMixSnapshot {
  const bus = state.buses[busId];
  if (!bus) return state;

  const clampedCount = Math.max(0, Math.min(count, MAX_VOICES_PER_BUS));
  const wasVOActive = state.buses.voice.activeVoices > 0;

  const newBus: PreviewBusState = {
    ...bus,
    activeVoices: clampedCount,
  };

  let newState: PreviewMixSnapshot = {
    ...state,
    buses: {
      ...state.buses,
      [busId]: newBus,
    },
    lastUpdated: Date.now(),
  };

  // Handle ducking state changes
  if (busId === DUCKING_CONFIG.DUCKER_BUS) {
    const isVONowActive = clampedCount > 0;
    if (wasVOActive !== isVONowActive) {
      newState = applyDucking(newState, isVONowActive);
    }
  }

  return newState;
}

/**
 * Applies or releases ducking on the Music bus.
 */
function applyDucking(state: PreviewMixSnapshot, active: boolean): PreviewMixSnapshot {
  const musicBus = state.buses[DUCKING_CONFIG.DUCKED_BUS];
  if (!musicBus) return state;

  const effectiveGain = active
    ? musicBus.baseGain * DUCKING_CONFIG.DUCK_RATIO
    : musicBus.baseGain;

  return {
    ...state,
    duckingActive: active,
    buses: {
      ...state.buses,
      [DUCKING_CONFIG.DUCKED_BUS]: {
        ...musicBus,
        gain: effectiveGain,
        isDucked: active,
      },
    },
    lastUpdated: Date.now(),
  };
}

/**
 * Resets the preview mix state (StopAll behavior).
 * - Clears all voices
 * - Resets ducking
 * - Restores Music gain to base
 */
export function resetPreviewMixState(state: PreviewMixSnapshot): PreviewMixSnapshot {
  const buses: Record<BusId, PreviewBusState> = {} as Record<BusId, PreviewBusState>;

  for (const busId of ALL_BUSES) {
    const currentBus = state.buses[busId];
    buses[busId] = {
      gain: currentBus?.baseGain ?? 1,
      baseGain: currentBus?.baseGain ?? 1,
      activeVoices: 0,
      isDucked: false,
    };
  }

  return {
    ...state,
    buses,
    duckingActive: false,
    lastUpdated: Date.now(),
  };
}

/**
 * Completely resets to initial state (project load, session reset).
 */
export function fullResetPreviewMixState(): PreviewMixSnapshot {
  return createInitialPreviewMixState();
}

/**
 * Gets total active voice count across all buses.
 */
export function getTotalActiveVoices(state: PreviewMixSnapshot): number {
  return Object.values(state.buses).reduce((sum, bus) => sum + bus.activeVoices, 0);
}

/**
 * Gets voice counts by bus.
 */
export function getVoicesByBus(state: PreviewMixSnapshot): Record<BusId, number> {
  const result: Record<BusId, number> = {} as Record<BusId, number>;
  for (const busId of ALL_BUSES) {
    result[busId] = state.buses[busId]?.activeVoices ?? 0;
  }
  return result;
}
