/**
 * ReelForge M8.2.2 Bus Insert Context
 *
 * React context that manages per-bus insert chain state and provides
 * integration with BusInsertDSP for real-time audio processing.
 * Includes PDC (Plugin Delay Compensation) state management per bus.
 */

import {
  createContext,
  useContext,
  useCallback,
  useRef,
  useMemo,
  useEffect,
  type ReactNode,
} from 'react';
import { useSyncExternalStore } from 'react';
import type { InsertChain, Insert, PluginId, InsertId } from './masterInsertTypes';
import { createDefaultInsert } from './masterInsertTypes';
import { BusInsertDSP, busInsertDSP } from './busInsertDSP';
import type { BusId } from './types';
import type { InsertableBusId } from '../project/projectTypes';

/** PDC state for a single bus */
export interface BusPdcState {
  enabled: boolean;
  delayMs: number;
  clamped: boolean;
}

/** Context value interface */
interface BusInsertContextValue {
  /** Current insert chains for all buses */
  chains: Partial<Record<InsertableBusId, InsertChain>>;
  /** Get chain for a specific bus */
  getChain: (busId: InsertableBusId) => InsertChain;
  /** Get latency in ms for a specific bus */
  getLatencyMs: (busId: InsertableBusId) => number;
  /** Add a new insert to a bus chain */
  addInsert: (busId: InsertableBusId, pluginId: PluginId) => void;
  /** Remove an insert from a bus chain */
  removeInsert: (busId: InsertableBusId, insertId: InsertId) => void;
  /** Move an insert within a bus chain */
  moveInsert: (busId: InsertableBusId, insertId: InsertId, newIndex: number) => void;
  /** Toggle insert bypass */
  toggleBypass: (busId: InsertableBusId, insertId: InsertId) => void;
  /** Update insert parameters */
  updateParams: (busId: InsertableBusId, insertId: InsertId, params: Insert['params']) => void;
  /** Replace all chains (e.g., on project load) */
  setAllChains: (chains: Partial<Record<InsertableBusId, InsertChain>>) => void;
  /** Replace a single bus chain */
  setChain: (busId: InsertableBusId, chain: InsertChain) => void;
  /** Get the DSP instance for advanced operations */
  getDSP: () => BusInsertDSP;
  /** Called when a voice starts on the ducker bus (VO) */
  onDuckerVoiceStart: () => void;
  /** Called when a voice ends on the ducker bus (VO) */
  onDuckerVoiceEnd: () => void;
  /** Reset ducking state (called on StopAll) */
  resetDucking: () => void;
  /** Get current ducking state */
  getDuckingState: () => { isDucking: boolean; duckerVoiceCount: number };
  /** Get duck gain value for a bus */
  getDuckGainValue: (busId: InsertableBusId) => number;
  // PDC (Plugin Delay Compensation) methods
  /** Set PDC enabled state for a bus */
  setBusPdcEnabled: (busId: InsertableBusId, enabled: boolean) => void;
  /** Check if PDC is enabled for a bus */
  isBusPdcEnabled: (busId: InsertableBusId) => boolean;
  /** Check if PDC is clamped (exceeds max delay) for a bus */
  isBusPdcClamped: (busId: InsertableBusId) => boolean;
  /** Get current PDC delay in ms for a bus */
  getBusPdcDelayMs: (busId: InsertableBusId) => number;
  /** Get max PDC delay in ms */
  getBusPdcMaxMs: () => number;
  /** Apply all PDC states from project (on load) */
  applyAllBusPdc: (pdcEnabled: Partial<Record<InsertableBusId, boolean>>) => void;
  /** Get PDC state for all buses */
  getAllBusPdcState: () => Record<InsertableBusId, BusPdcState>;
}

const BusInsertContext = createContext<BusInsertContextValue | null>(null);

/** Combined state for external store pattern */
interface BusInsertState {
  chains: Partial<Record<InsertableBusId, InsertChain>>;
}

/** Empty chain constant */
const EMPTY_CHAIN: InsertChain = { inserts: [] };

/** Store for external store pattern (efficient updates) */
class BusInsertStore {
  private state: BusInsertState;
  private listeners: Set<() => void> = new Set();
  private dsp: BusInsertDSP;

  constructor(dsp: BusInsertDSP) {
    this.state = {
      chains: {},
    };
    this.dsp = dsp;
  }

  getSnapshot = (): BusInsertState => {
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
    this.dsp.applyAllChains(this.state.chains);
  }

  getChain(busId: InsertableBusId): InsertChain {
    return this.state.chains[busId] ?? EMPTY_CHAIN;
  }

  setAllChains(chains: Partial<Record<InsertableBusId, InsertChain>>) {
    // Chains should already be validated by validateProjectFile before reaching here.
    // NO clamping on load - invalid config must fail validation, not be silently fixed.
    this.state = { chains: { ...chains } };
    this.syncDSP();
    this.emit();
  }

  setChain(busId: InsertableBusId, chain: InsertChain) {
    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: chain,
      },
    };
    this.syncDSP();
    this.emit();
  }

  addInsert(busId: InsertableBusId, pluginId: PluginId) {
    const insert = createDefaultInsert(pluginId);
    const currentChain = this.state.chains[busId] ?? EMPTY_CHAIN;
    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: {
          inserts: [...currentChain.inserts, insert],
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  removeInsert(busId: InsertableBusId, insertId: InsertId) {
    const currentChain = this.state.chains[busId];
    if (!currentChain) return;

    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: {
          inserts: currentChain.inserts.filter((ins) => ins.id !== insertId),
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  moveInsert(busId: InsertableBusId, insertId: InsertId, newIndex: number) {
    const currentChain = this.state.chains[busId];
    if (!currentChain) return;

    const inserts = [...currentChain.inserts];
    const currentIndex = inserts.findIndex((ins) => ins.id === insertId);
    if (currentIndex === -1 || currentIndex === newIndex) return;

    // Remove from current position
    const [insert] = inserts.splice(currentIndex, 1);
    // Insert at new position
    inserts.splice(newIndex, 0, insert);

    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: { inserts },
      },
    };
    this.syncDSP();
    this.emit();
  }

  toggleBypass(busId: InsertableBusId, insertId: InsertId) {
    const currentChain = this.state.chains[busId];
    if (!currentChain) return;

    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: {
          inserts: currentChain.inserts.map((ins) =>
            ins.id === insertId ? { ...ins, enabled: !ins.enabled } : ins
          ),
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  updateParams(busId: InsertableBusId, insertId: InsertId, params: Insert['params']) {
    const currentChain = this.state.chains[busId];
    if (!currentChain) return;

    this.state = {
      chains: {
        ...this.state.chains,
        [busId]: {
          inserts: currentChain.inserts.map((ins) =>
            ins.id === insertId
              ? { ...ins, params: { ...ins.params, ...params } as any }  // MERGE params
              : ins
          ),
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  getLatencyMs(busId: InsertableBusId): number {
    return this.dsp.getLatencyMs(busId);
  }

  getDSP(): BusInsertDSP {
    return this.dsp;
  }
}

interface BusInsertProviderProps {
  children: ReactNode;
  /** AudioContext ref for DSP initialization */
  audioContextRef: React.MutableRefObject<AudioContext | null>;
  /** Bus gains ref for DSP wiring */
  busGainsRef: React.MutableRefObject<Record<BusId, GainNode> | null>;
  /** Master gain ref for DSP wiring */
  masterGainRef: React.MutableRefObject<GainNode | null>;
  /** Initial chains to load (e.g., from project) */
  initialChains?: Partial<Record<InsertableBusId, InsertChain>>;
  /** Initial PDC enabled state per bus (from project) */
  initialBusPdcEnabled?: Partial<Record<InsertableBusId, boolean>>;
}

export function BusInsertProvider({
  children,
  audioContextRef,
  busGainsRef,
  masterGainRef,
  initialChains,
  initialBusPdcEnabled,
}: BusInsertProviderProps) {
  const storeRef = useRef<BusInsertStore | null>(null);
  const initialPdcAppliedRef = useRef(false);
  if (!storeRef.current) {
    storeRef.current = new BusInsertStore(busInsertDSP);
    if (initialChains) {
      storeRef.current.setAllChains(initialChains);
    }
  }
  const store = storeRef.current;

  // Initialize DSP when AudioContext, busGains, and masterGain become available
  useEffect(() => {
    const checkAndInit = () => {
      const ctx = audioContextRef.current;
      const busGains = busGainsRef.current;
      const masterGain = masterGainRef.current;

      if (ctx && busGains && masterGain) {
        busInsertDSP.initialize(ctx, busGains, masterGain);
        // Apply initial chains after DSP is ready
        busInsertDSP.applyAllChains(store.getSnapshot().chains);
        // Apply initial PDC enabled state (only once)
        if (!initialPdcAppliedRef.current && initialBusPdcEnabled) {
          busInsertDSP.applyAllBusPdc(initialBusPdcEnabled);
          initialPdcAppliedRef.current = true;
        }
      }
    };

    // Check immediately
    checkAndInit();

    // Also check periodically in case context/gains are created later
    const interval = setInterval(checkAndInit, 100);

    return () => {
      clearInterval(interval);
    };
  }, [audioContextRef, busGainsRef, masterGainRef, store, initialBusPdcEnabled]);

  // Cleanup DSP on unmount
  useEffect(() => {
    return () => {
      busInsertDSP.dispose();
    };
  }, []);

  const state = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot
  );

  const { chains } = state;

  const handleGetChain = useCallback(
    (busId: InsertableBusId) => {
      return store.getChain(busId);
    },
    [store]
  );

  const handleGetLatencyMs = useCallback(
    (busId: InsertableBusId) => {
      return store.getLatencyMs(busId);
    },
    [store]
  );

  const handleAddInsert = useCallback(
    (busId: InsertableBusId, pluginId: PluginId) => {
      store.addInsert(busId, pluginId);
    },
    [store]
  );

  const handleRemoveInsert = useCallback(
    (busId: InsertableBusId, insertId: InsertId) => {
      store.removeInsert(busId, insertId);
    },
    [store]
  );

  const handleMoveInsert = useCallback(
    (busId: InsertableBusId, insertId: InsertId, newIndex: number) => {
      store.moveInsert(busId, insertId, newIndex);
    },
    [store]
  );

  const handleToggleBypass = useCallback(
    (busId: InsertableBusId, insertId: InsertId) => {
      store.toggleBypass(busId, insertId);
    },
    [store]
  );

  const handleUpdateParams = useCallback(
    (busId: InsertableBusId, insertId: InsertId, params: Insert['params']) => {
      store.updateParams(busId, insertId, params);
    },
    [store]
  );

  const handleSetAllChains = useCallback(
    (newChains: Partial<Record<InsertableBusId, InsertChain>>) => {
      store.setAllChains(newChains);
    },
    [store]
  );

  const handleSetChain = useCallback(
    (busId: InsertableBusId, chain: InsertChain) => {
      store.setChain(busId, chain);
    },
    [store]
  );

  const handleGetDSP = useCallback(() => {
    return store.getDSP();
  }, [store]);

  // Ducking handlers
  const handleDuckerVoiceStart = useCallback(() => {
    busInsertDSP.onDuckerVoiceStart();
  }, []);

  const handleDuckerVoiceEnd = useCallback(() => {
    busInsertDSP.onDuckerVoiceEnd();
  }, []);

  const handleResetDucking = useCallback(() => {
    busInsertDSP.resetDucking();
  }, []);

  const handleGetDuckingState = useCallback(() => {
    return busInsertDSP.getDuckingState();
  }, []);

  const handleGetDuckGainValue = useCallback((busId: InsertableBusId) => {
    return busInsertDSP.getDuckGainValue(busId);
  }, []);

  // PDC handlers
  const handleSetBusPdcEnabled = useCallback((busId: InsertableBusId, enabled: boolean) => {
    busInsertDSP.setBusPdcEnabled(busId, enabled);
  }, []);

  const handleIsBusPdcEnabled = useCallback((busId: InsertableBusId) => {
    return busInsertDSP.isBusPdcEnabled(busId);
  }, []);

  const handleIsBusPdcClamped = useCallback((busId: InsertableBusId) => {
    return busInsertDSP.isBusPdcClamped(busId);
  }, []);

  const handleGetBusPdcDelayMs = useCallback((busId: InsertableBusId) => {
    return busInsertDSP.getBusPdcDelayMs(busId);
  }, []);

  const handleGetBusPdcMaxMs = useCallback(() => {
    return busInsertDSP.getBusPdcMaxMs();
  }, []);

  const handleApplyAllBusPdc = useCallback((pdcEnabled: Partial<Record<InsertableBusId, boolean>>) => {
    busInsertDSP.applyAllBusPdc(pdcEnabled);
  }, []);

  const handleGetAllBusPdcState = useCallback(() => {
    return busInsertDSP.getAllBusPdcState();
  }, []);

  const value = useMemo<BusInsertContextValue>(
    () => ({
      chains,
      getChain: handleGetChain,
      getLatencyMs: handleGetLatencyMs,
      addInsert: handleAddInsert,
      removeInsert: handleRemoveInsert,
      moveInsert: handleMoveInsert,
      toggleBypass: handleToggleBypass,
      updateParams: handleUpdateParams,
      setAllChains: handleSetAllChains,
      setChain: handleSetChain,
      getDSP: handleGetDSP,
      onDuckerVoiceStart: handleDuckerVoiceStart,
      onDuckerVoiceEnd: handleDuckerVoiceEnd,
      resetDucking: handleResetDucking,
      getDuckingState: handleGetDuckingState,
      getDuckGainValue: handleGetDuckGainValue,
      // PDC methods
      setBusPdcEnabled: handleSetBusPdcEnabled,
      isBusPdcEnabled: handleIsBusPdcEnabled,
      isBusPdcClamped: handleIsBusPdcClamped,
      getBusPdcDelayMs: handleGetBusPdcDelayMs,
      getBusPdcMaxMs: handleGetBusPdcMaxMs,
      applyAllBusPdc: handleApplyAllBusPdc,
      getAllBusPdcState: handleGetAllBusPdcState,
    }),
    [
      chains,
      handleGetChain,
      handleGetLatencyMs,
      handleAddInsert,
      handleRemoveInsert,
      handleMoveInsert,
      handleToggleBypass,
      handleUpdateParams,
      handleSetAllChains,
      handleSetChain,
      handleGetDSP,
      handleDuckerVoiceStart,
      handleDuckerVoiceEnd,
      handleResetDucking,
      handleGetDuckingState,
      handleGetDuckGainValue,
      handleSetBusPdcEnabled,
      handleIsBusPdcEnabled,
      handleIsBusPdcClamped,
      handleGetBusPdcDelayMs,
      handleGetBusPdcMaxMs,
      handleApplyAllBusPdc,
      handleGetAllBusPdcState,
    ]
  );

  return (
    <BusInsertContext.Provider value={value}>
      {children}
    </BusInsertContext.Provider>
  );
}

export function useBusInserts(): BusInsertContextValue {
  const context = useContext(BusInsertContext);
  if (!context) {
    throw new Error('useBusInserts must be used within BusInsertProvider');
  }
  return context;
}

/**
 * Hook that returns the chain for a specific bus.
 * Returns an empty chain if context is not available (graceful fallback).
 */
export function useBusInsertChain(busId: InsertableBusId): InsertChain {
  const context = useContext(BusInsertContext);
  if (!context) {
    return EMPTY_CHAIN;
  }
  return context.chains[busId] ?? EMPTY_CHAIN;
}

/**
 * Hook that returns current latency in milliseconds for a specific bus.
 */
export function useBusInsertLatency(busId: InsertableBusId): number {
  const context = useContext(BusInsertContext);
  if (!context) {
    return 0;
  }
  return context.getLatencyMs(busId);
}
