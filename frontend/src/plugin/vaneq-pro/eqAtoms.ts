/**
 * VanEQ Pro - Jotai Atoms for Fine-Grained State
 *
 * Each EQ band is an independent atom - components only re-render
 * when their specific band changes. This eliminates unnecessary
 * re-renders that plague traditional state management.
 *
 * Benefits:
 * - Surgical precision: Only affected components re-render
 * - No selector boilerplate needed
 * - Derived atoms compute automatically
 * - Perfect for real-time audio UI
 *
 * @module plugin/vaneq-pro/eqAtoms
 */

import { atom } from 'jotai';
import { atomFamily } from 'jotai/utils';

// ============ Types ============

export type BandType =
  | 'highpass'
  | 'lowshelf'
  | 'bell'
  | 'highshelf'
  | 'lowpass'
  | 'notch'
  | 'bandpass'
  | 'tilt';

export interface BandState {
  id: number;
  freq: number;
  gain: number;
  q: number;
  type: BandType;
  active: boolean;
}

export interface EQState {
  enabled: boolean;
  analyzerEnabled: boolean;
  autoGain: boolean;
  outputGain: number;
  soloedBandId: number | null;
  abState: 'A' | 'B';
}

// ============ Default Values ============

const DEFAULT_BANDS: BandState[] = [
  { id: 1, freq: 30, gain: 0, q: 0.71, type: 'highpass', active: true },
  { id: 2, freq: 100, gain: 0, q: 1.0, type: 'lowshelf', active: true },
  { id: 3, freq: 400, gain: 0, q: 1.0, type: 'bell', active: true },
  { id: 4, freq: 1000, gain: 0, q: 1.0, type: 'bell', active: true },
  { id: 5, freq: 2500, gain: 0, q: 1.0, type: 'bell', active: true },
  { id: 6, freq: 6000, gain: 0, q: 1.0, type: 'bell', active: true },
  { id: 7, freq: 12000, gain: 0, q: 1.0, type: 'highshelf', active: true },
  { id: 8, freq: 16000, gain: 0, q: 0.71, type: 'lowpass', active: true },
];

const DEFAULT_EQ_STATE: EQState = {
  enabled: true,
  analyzerEnabled: true,
  autoGain: false,
  outputGain: 0,
  soloedBandId: null,
  abState: 'A',
};

// ============ Band Atoms (atomFamily for each band) ============

/**
 * atomFamily creates a separate atom for each band ID.
 * When band 3 changes, only components using band 3 re-render.
 */
export const bandAtomFamily = atomFamily((id: number) =>
  atom<BandState>(
    DEFAULT_BANDS.find((b) => b.id === id) ?? {
      id,
      freq: 1000,
      gain: 0,
      q: 1.0,
      type: 'bell',
      active: true,
    }
  )
);

// ============ Global EQ State Atom ============

export const eqStateAtom = atom<EQState>(DEFAULT_EQ_STATE);

// ============ Derived Atoms ============

/**
 * All bands as array - for components that need the full list.
 * Recomputes only when any individual band changes.
 */
export const allBandsAtom = atom((get) => {
  const bands: BandState[] = [];
  for (let i = 1; i <= 8; i++) {
    bands.push(get(bandAtomFamily(i)));
  }
  return bands;
});

/**
 * Active bands only - for curve calculation.
 */
export const activeBandsAtom = atom((get) => {
  const all = get(allBandsAtom);
  return all.filter((b) => b.active);
});

/**
 * Currently soloed band (if any).
 */
export const soloedBandAtom = atom((get) => {
  const state = get(eqStateAtom);
  if (state.soloedBandId === null) return null;
  return get(bandAtomFamily(state.soloedBandId));
});

/**
 * Whether any band has non-zero gain.
 */
export const hasAnyGainAtom = atom((get) => {
  const bands = get(allBandsAtom);
  return bands.some((b) => b.active && Math.abs(b.gain) > 0.1);
});

// ============ Action Atoms (write-only) ============

/**
 * Update a single band property.
 */
export const updateBandAtom = atom(
  null,
  (get, set, update: { id: number; updates: Partial<BandState> }) => {
    const bandAtom = bandAtomFamily(update.id);
    const current = get(bandAtom);
    set(bandAtom, { ...current, ...update.updates });
  }
);

/**
 * Reset a band to defaults.
 */
export const resetBandAtom = atom(null, (_get, set, id: number) => {
  const defaultBand = DEFAULT_BANDS.find((b) => b.id === id);
  if (defaultBand) {
    set(bandAtomFamily(id), defaultBand);
  }
});

/**
 * Toggle band active state.
 */
export const toggleBandActiveAtom = atom(null, (get, set, id: number) => {
  const bandAtom = bandAtomFamily(id);
  const current = get(bandAtom);
  set(bandAtom, { ...current, active: !current.active });
});

/**
 * Solo a specific band (unsolo others).
 */
export const soloBandAtom = atom(null, (get, set, id: number | null) => {
  const state = get(eqStateAtom);
  // Toggle: if already soloed, unsolo
  const newSoloId = state.soloedBandId === id ? null : id;
  set(eqStateAtom, { ...state, soloedBandId: newSoloId });
});

/**
 * Reset all bands to defaults.
 */
export const resetAllBandsAtom = atom(null, (_get, set) => {
  for (const band of DEFAULT_BANDS) {
    set(bandAtomFamily(band.id), band);
  }
  set(eqStateAtom, DEFAULT_EQ_STATE);
});

/**
 * Toggle EQ enabled.
 */
export const toggleEQEnabledAtom = atom(null, (get, set) => {
  const state = get(eqStateAtom);
  set(eqStateAtom, { ...state, enabled: !state.enabled });
});

/**
 * Toggle analyzer.
 */
export const toggleAnalyzerAtom = atom(null, (get, set) => {
  const state = get(eqStateAtom);
  set(eqStateAtom, { ...state, analyzerEnabled: !state.analyzerEnabled });
});

/**
 * Set output gain.
 */
export const setOutputGainAtom = atom(null, (get, set, gain: number) => {
  const state = get(eqStateAtom);
  set(eqStateAtom, { ...state, outputGain: gain });
});

/**
 * Switch A/B state.
 */
export const switchABAtom = atom(null, (get, set, abState: 'A' | 'B') => {
  const state = get(eqStateAtom);
  set(eqStateAtom, { ...state, abState });
});

// ============ Preset Storage ============

interface EQPreset {
  name: string;
  bands: BandState[];
  state: EQState;
}

const presetsAtom = atom<Map<string, EQPreset>>(new Map());

export const savePresetAtom = atom(null, (get, set, name: string) => {
  const bands = get(allBandsAtom);
  const state = get(eqStateAtom);
  const presets = new Map(get(presetsAtom));
  presets.set(name, { name, bands: [...bands], state: { ...state } });
  set(presetsAtom, presets);
});

export const loadPresetAtom = atom(null, (get, set, name: string) => {
  const presets = get(presetsAtom);
  const preset = presets.get(name);
  if (!preset) return;

  for (const band of preset.bands) {
    set(bandAtomFamily(band.id), band);
  }
  set(eqStateAtom, preset.state);
});

export const getPresetsAtom = atom((get) => {
  return Array.from(get(presetsAtom).keys());
});
