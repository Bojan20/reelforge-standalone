/**
 * ReelForge M8.0 Master Insert Context
 *
 * React context that manages the master insert chain state and provides
 * integration with MasterInsertDSP for real-time audio processing.
 */

import {
  createContext,
  useContext,
  useCallback,
  useRef,
  useMemo,
  type ReactNode,
} from 'react';
import { useSyncExternalStore } from 'react';
import type {
  MasterInsertChain,
  MasterInsert,
  PluginId,
  InsertId,
} from './masterInsertTypes';
import {
  createEmptyChain,
  createDefaultInsert,
  calculateChainLatencyMs,
} from './masterInsertTypes';
import { MasterInsertDSP, masterInsertDSP } from './masterInsertDSP';
import { useReelForgeStore } from '../store/reelforgeStore';

/** Context value interface */
interface MasterInsertContextValue {
  /** Current insert chain */
  chain: MasterInsertChain;
  /** Current chain latency in ms */
  latencyMs: number;
  /** PDC (Preview Delay Compensation) enabled */
  pdcEnabled: boolean;
  /** Current compensation delay in ms (when PDC enabled) */
  compensationDelayMs: number;
  /** True if compensation delay is clamped to max (latency exceeds limit) */
  pdcClamped: boolean;
  /** AudioContext sample rate (for UI/DSP frequency matching) */
  sampleRate: number;
  /** Add a new insert to the chain */
  addInsert: (pluginId: PluginId) => void;
  /** Remove an insert from the chain */
  removeInsert: (insertId: InsertId) => void;
  /** Move an insert within the chain */
  moveInsert: (insertId: InsertId, newIndex: number) => void;
  /** Toggle insert bypass */
  toggleBypass: (insertId: InsertId) => void;
  /** Update insert parameters */
  updateParams: (insertId: InsertId, params: MasterInsert['params']) => void;
  /** Replace entire chain (e.g., on project load) */
  setChain: (chain: MasterInsertChain) => void;
  /** Toggle PDC on/off */
  setPdcEnabled: (enabled: boolean) => void;
  /** Get the DSP instance for advanced operations */
  getDSP: () => MasterInsertDSP;
}

const MasterInsertContext = createContext<MasterInsertContextValue | null>(null);

/** Combined state for external store pattern */
interface MasterInsertState {
  chain: MasterInsertChain;
  pdcEnabled: boolean;
}

/** Store for external store pattern (efficient updates) */
class MasterInsertStore {
  private state: MasterInsertState;
  private listeners: Set<() => void> = new Set();
  private dsp: MasterInsertDSP;

  constructor(dsp: MasterInsertDSP) {
    this.state = {
      chain: createEmptyChain(),
      pdcEnabled: false,
    };
    this.dsp = dsp;
  }

  getSnapshot = (): MasterInsertState => {
    return this.state;
  };

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private emit() {
    this.listeners.forEach((listener) => listener());
  }

  private syncDSP() {
    this.dsp.applyChain(this.state.chain);
  }

  setChain(chain: MasterInsertChain) {
    // Chain should already be validated by validateProjectFile before reaching here.
    // NO clamping on load - invalid config must fail validation, not be silently fixed.
    this.state = { ...this.state, chain };
    this.syncDSP();
    this.emit();
  }

  setPdcEnabled(enabled: boolean) {
    if (this.state.pdcEnabled === enabled) return;
    this.state = { ...this.state, pdcEnabled: enabled };
    this.dsp.setPdcEnabled(enabled);
    this.emit();
  }

  addInsert(pluginId: PluginId) {
    const insert = createDefaultInsert(pluginId);
    this.state = {
      ...this.state,
      chain: {
        inserts: [...this.state.chain.inserts, insert],
      },
    };
    this.syncDSP();
    this.emit();
  }

  removeInsert(insertId: InsertId) {
    this.state = {
      ...this.state,
      chain: {
        inserts: this.state.chain.inserts.filter((ins) => ins.id !== insertId),
      },
    };
    this.syncDSP();
    this.emit();
  }

  moveInsert(insertId: InsertId, newIndex: number) {
    const inserts = [...this.state.chain.inserts];
    const currentIndex = inserts.findIndex((ins) => ins.id === insertId);
    if (currentIndex === -1 || currentIndex === newIndex) return;

    // Remove from current position
    const [insert] = inserts.splice(currentIndex, 1);
    // Insert at new position
    inserts.splice(newIndex, 0, insert);

    this.state = { ...this.state, chain: { inserts } };
    this.syncDSP();
    this.emit();
  }

  toggleBypass(insertId: InsertId) {
    // Delegate to zustand store (single source of truth for DSP sync)
    // Zustand action will call masterInsertDSP.applyChain()
    useReelForgeStore.getState().toggleMasterBypass(insertId);

    // Also update local state to keep UI in sync
    const zustandChain = useReelForgeStore.getState().masterChain;
    this.state = { ...this.state, chain: zustandChain };
    this.emit();
  }

  updateParams(insertId: InsertId, params: MasterInsert['params']) {
    const targetInsert = this.state.chain.inserts.find(ins => ins.id === insertId);
    if (!targetInsert) {
      return;
    }
    this.state = {
      ...this.state,
      chain: {
        inserts: this.state.chain.inserts.map((ins) =>
          ins.id === insertId
            ? { ...ins, params: { ...ins.params, ...params } as any }  // MERGE params
            : ins
        ),
      },
    };
    this.syncDSP();
    this.emit();
  }

  getLatencyMs(): number {
    return calculateChainLatencyMs(this.state.chain);
  }

  getCompensationDelayMs(): number {
    return this.dsp.getCompensationDelayMs();
  }

  isCompensationClamped(): boolean {
    return this.dsp.isCompensationClamped();
  }

  getDSP(): MasterInsertDSP {
    return this.dsp;
  }
}

interface MasterInsertProviderProps {
  children: ReactNode;
  /** AudioContext for DSP initialization (required, must be created before mounting) */
  audioContext: AudioContext;
  /** Master gain node for DSP wiring (required, must be created before mounting) */
  masterGain: GainNode;
  /** Initial chain to load (e.g., from project) */
  initialChain?: MasterInsertChain;
  /** Initial PDC enabled state (e.g., from project) */
  initialPdcEnabled?: boolean;
}

export function MasterInsertProvider({
  children,
  audioContext,
  masterGain,
  initialChain,
  initialPdcEnabled,
}: MasterInsertProviderProps) {
  // Debug log removed - was causing console spam during re-renders

  const storeRef = useRef<MasterInsertStore | null>(null);
  if (!storeRef.current) {
    storeRef.current = new MasterInsertStore(masterInsertDSP);
    if (initialChain) {
      storeRef.current.setChain(initialChain);
    }
    if (initialPdcEnabled !== undefined) {
      storeRef.current.setPdcEnabled(initialPdcEnabled);
    }
  }
  const store = storeRef.current;

  // Initialize DSP SYNCHRONOUSLY in component body (not in useEffect)
  // This ensures DSP is ready before any children render
  if (!masterInsertDSP.isInitialized() && audioContext && masterGain) {
    // Resume AudioContext if suspended (browser autoplay policy)
    if (audioContext.state === 'suspended') {
      audioContext.resume().catch(() => {
        // Ignore - user interaction will resume it later
      });
    }
    masterInsertDSP.initialize(audioContext, masterGain);

    // IMPORTANT: Sync with BOTH context store AND zustand store
    // Components may use either store, so we need to ensure DSP has the latest chain
    const contextChain = store.getSnapshot().chain;
    const zustandChain = useReelForgeStore.getState().masterChain;

    // Prefer zustand chain if it has inserts (it's the primary store now)
    const chainToApply = zustandChain.inserts.length > 0 ? zustandChain : contextChain;
    masterInsertDSP.applyChain(chainToApply);
    masterInsertDSP.setPdcEnabled(store.getSnapshot().pdcEnabled);
  }

  // NOTE: We intentionally DO NOT dispose masterInsertDSP on unmount.
  // It's a singleton that persists for the app lifetime.
  // React 18 StrictMode double-mounts components, which would cause:
  // 1. Mount → initialize DSP
  // 2. Unmount (StrictMode) → dispose DSP
  // 3. Mount again → re-initialize DSP (duplicate logs, wasted work)
  //
  // The DSP will be garbage collected when the page unloads.
  // For explicit cleanup, call masterInsertDSP.dispose() manually.

  // NOTE: DSP sync is now handled directly in zustand store actions (Cubase-style)
  // See reelforgeStore.ts - each action (addMasterInsert, updateMasterParams, etc.)
  // immediately calls masterInsertDSP.applyChain() after state update.
  // This avoids the double-sync issue where both store actions AND this subscriber
  // would call applyChain, causing infinite loops during rapid param updates.

  const state = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot
  );

  const { chain, pdcEnabled } = state;
  const latencyMs = useMemo(() => store.getLatencyMs(), [chain]);
  const compensationDelayMs = useMemo(() => store.getCompensationDelayMs(), [chain, pdcEnabled]);
  const pdcClamped = useMemo(() => store.isCompensationClamped(), [chain, pdcEnabled]);

  const handleAddInsert = useCallback(
    (pluginId: PluginId) => {
      store.addInsert(pluginId);
    },
    [store]
  );

  const handleRemoveInsert = useCallback(
    (insertId: InsertId) => {
      store.removeInsert(insertId);
    },
    [store]
  );

  const handleMoveInsert = useCallback(
    (insertId: InsertId, newIndex: number) => {
      store.moveInsert(insertId, newIndex);
    },
    [store]
  );

  const handleToggleBypass = useCallback(
    (insertId: InsertId) => {
      store.toggleBypass(insertId);
    },
    [store]
  );

  const handleUpdateParams = useCallback(
    (insertId: InsertId, params: MasterInsert['params']) => {
      store.updateParams(insertId, params);
    },
    [store]
  );

  const handleSetChain = useCallback(
    (newChain: MasterInsertChain) => {
      store.setChain(newChain);
    },
    [store]
  );

  const handleSetPdcEnabled = useCallback(
    (enabled: boolean) => {
      store.setPdcEnabled(enabled);
    },
    [store]
  );

  const handleGetDSP = useCallback(() => {
    return store.getDSP();
  }, [store]);

  // Get sample rate from DSP (stable reference, only changes on context recreation)
  const sampleRate = useMemo(() => store.getDSP().getSampleRate(), [store]);

  const value = useMemo<MasterInsertContextValue>(
    () => ({
      chain,
      latencyMs,
      pdcEnabled,
      compensationDelayMs,
      pdcClamped,
      sampleRate,
      addInsert: handleAddInsert,
      removeInsert: handleRemoveInsert,
      moveInsert: handleMoveInsert,
      toggleBypass: handleToggleBypass,
      updateParams: handleUpdateParams,
      setChain: handleSetChain,
      setPdcEnabled: handleSetPdcEnabled,
      getDSP: handleGetDSP,
    }),
    [
      chain,
      latencyMs,
      pdcEnabled,
      compensationDelayMs,
      pdcClamped,
      sampleRate,
      handleAddInsert,
      handleRemoveInsert,
      handleMoveInsert,
      handleToggleBypass,
      handleUpdateParams,
      handleSetChain,
      handleSetPdcEnabled,
      handleGetDSP,
    ]
  );

  return (
    <MasterInsertContext.Provider value={value}>
      {children}
    </MasterInsertContext.Provider>
  );
}

export function useMasterInserts(): MasterInsertContextValue {
  const context = useContext(MasterInsertContext);
  if (!context) {
    throw new Error('useMasterInserts must be used within MasterInsertProvider');
  }
  return context;
}

/**
 * Hook that returns only the chain for components that just need to read state.
 * Returns an empty chain if context is not available (graceful fallback).
 */
export function useMasterInsertChain(): MasterInsertChain {
  const context = useContext(MasterInsertContext);
  if (!context) {
    return createEmptyChain();
  }
  return context.chain;
}

/**
 * Hook that returns current latency in milliseconds.
 */
export function useMasterInsertLatency(): number {
  const context = useContext(MasterInsertContext);
  if (!context) {
    return 0;
  }
  return context.latencyMs;
}

/**
 * Hook that returns PDC (Preview Delay Compensation) state.
 */
export function usePdcState(): { enabled: boolean; compensationMs: number } {
  const context = useContext(MasterInsertContext);
  if (!context) {
    return { enabled: false, compensationMs: 0 };
  }
  return {
    enabled: context.pdcEnabled,
    compensationMs: context.compensationDelayMs,
  };
}

/**
 * Hook that returns sample rate with graceful fallback.
 * Safe to use outside MasterInsertProvider (returns 48000 as default).
 */
export function useMasterInsertSampleRate(): number {
  const context = useContext(MasterInsertContext);
  if (!context) {
    return 48000; // Standard fallback sample rate
  }
  return context.sampleRate;
}
