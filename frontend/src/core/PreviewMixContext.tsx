/**
 * ReelForge M7.1 Preview Mix Context
 *
 * React context that manages the preview mix state and provides
 * integration with AudioEngine for voice tracking and bus gain updates.
 */

import { createContext, useContext, useCallback, useRef, useMemo, type ReactNode } from 'react';
import { useSyncExternalStore } from 'react';
import type { BusId } from './types';
import {
  type PreviewMixSnapshot,
  createInitialPreviewMixState,
  setBusGain,
  incrementVoiceCount,
  decrementVoiceCount,
  setVoiceCount,
  resetPreviewMixState,
  fullResetPreviewMixState,
  calculateVoiceOutputGain,
  getTotalActiveVoices,
  getVoicesByBus,
} from './previewMixState';

/** Context value interface */
interface PreviewMixContextValue {
  /** Current snapshot of preview mix state */
  snapshot: PreviewMixSnapshot;
  /** Set gain for a bus (including master) */
  setBusGain: (busId: BusId, gain: number) => void;
  /** Increment voice count when a sound starts */
  onVoiceStart: (busId: BusId) => void;
  /** Decrement voice count when a sound ends */
  onVoiceEnd: (busId: BusId) => void;
  /** Sync voice counts from external source (e.g., AudioEngine) */
  syncVoiceCounts: (counts: Record<BusId, number>) => void;
  /** Reset on StopAll (clears voices, resets ducking) */
  onStopAll: () => void;
  /** Full reset (project load, session reset) */
  fullReset: () => void;
  /** Calculate output gain for a voice */
  calculateOutputGain: (actionGain: number, busId: BusId) => number;
  /** Get total active voice count */
  getTotalVoices: () => number;
  /** Get voice counts by bus */
  getVoicesByBus: () => Record<BusId, number>;
}

const PreviewMixContext = createContext<PreviewMixContextValue | null>(null);

/** Store for external store pattern (efficient updates) */
class PreviewMixStore {
  private state: PreviewMixSnapshot;
  private listeners: Set<() => void> = new Set();

  constructor() {
    this.state = createInitialPreviewMixState();
  }

  getSnapshot = (): PreviewMixSnapshot => {
    return this.state;
  };

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private emit() {
    this.listeners.forEach(listener => listener());
  }

  setBusGain(busId: BusId, gain: number) {
    this.state = setBusGain(this.state, busId, gain);
    this.emit();
  }

  incrementVoice(busId: BusId) {
    this.state = incrementVoiceCount(this.state, busId);
    this.emit();
  }

  decrementVoice(busId: BusId) {
    this.state = decrementVoiceCount(this.state, busId);
    this.emit();
  }

  syncVoiceCounts(counts: Record<BusId, number>) {
    let newState = this.state;
    for (const [busId, count] of Object.entries(counts) as [BusId, number][]) {
      newState = setVoiceCount(newState, busId, count);
    }
    this.state = newState;
    this.emit();
  }

  stopAll() {
    this.state = resetPreviewMixState(this.state);
    this.emit();
  }

  fullReset() {
    this.state = fullResetPreviewMixState();
    this.emit();
  }
}

interface PreviewMixProviderProps {
  children: ReactNode;
}

export function PreviewMixProvider({ children }: PreviewMixProviderProps) {
  const storeRef = useRef<PreviewMixStore | null>(null);
  if (!storeRef.current) {
    storeRef.current = new PreviewMixStore();
  }
  const store = storeRef.current;

  const snapshot = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot
  );

  const handleSetBusGain = useCallback((busId: BusId, gain: number) => {
    store.setBusGain(busId, gain);
  }, [store]);

  const handleVoiceStart = useCallback((busId: BusId) => {
    store.incrementVoice(busId);
  }, [store]);

  const handleVoiceEnd = useCallback((busId: BusId) => {
    store.decrementVoice(busId);
  }, [store]);

  const handleSyncVoiceCounts = useCallback((counts: Record<BusId, number>) => {
    store.syncVoiceCounts(counts);
  }, [store]);

  const handleStopAll = useCallback(() => {
    store.stopAll();
  }, [store]);

  const handleFullReset = useCallback(() => {
    store.fullReset();
  }, [store]);

  const calculateOutputGain = useCallback((actionGain: number, busId: BusId): number => {
    return calculateVoiceOutputGain(store.getSnapshot(), actionGain, busId);
  }, [store]);

  const getTotalVoices = useCallback((): number => {
    return getTotalActiveVoices(store.getSnapshot());
  }, [store]);

  const getVoicesByBusCallback = useCallback((): Record<BusId, number> => {
    return getVoicesByBus(store.getSnapshot());
  }, [store]);

  const value = useMemo<PreviewMixContextValue>(() => ({
    snapshot,
    setBusGain: handleSetBusGain,
    onVoiceStart: handleVoiceStart,
    onVoiceEnd: handleVoiceEnd,
    syncVoiceCounts: handleSyncVoiceCounts,
    onStopAll: handleStopAll,
    fullReset: handleFullReset,
    calculateOutputGain,
    getTotalVoices,
    getVoicesByBus: getVoicesByBusCallback,
  }), [
    snapshot,
    handleSetBusGain,
    handleVoiceStart,
    handleVoiceEnd,
    handleSyncVoiceCounts,
    handleStopAll,
    handleFullReset,
    calculateOutputGain,
    getTotalVoices,
    getVoicesByBusCallback,
  ]);

  return (
    <PreviewMixContext.Provider value={value}>
      {children}
    </PreviewMixContext.Provider>
  );
}

export function usePreviewMix(): PreviewMixContextValue {
  const context = useContext(PreviewMixContext);
  if (!context) {
    throw new Error('usePreviewMix must be used within PreviewMixProvider');
  }
  return context;
}

/**
 * Hook that returns only the snapshot for components that just need to read state.
 * Returns a default snapshot if context is not available (graceful fallback).
 */
export function usePreviewMixSnapshot(): PreviewMixSnapshot {
  const context = useContext(PreviewMixContext);
  if (!context) {
    // Return default snapshot for components outside provider
    return createInitialPreviewMixState();
  }
  return context.snapshot;
}
