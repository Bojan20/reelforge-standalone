/**
 * ReelForge M8.5 Asset Insert Context
 *
 * React context that manages per-asset insert chain state and provides
 * integration with VoiceInsertDSP for real-time audio processing.
 * Each playing voice/channel gets its own DSP chain instance.
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
import { VoiceInsertDSP, voiceInsertDSP } from './voiceInsertDSP';
import type { AssetId } from '../project/projectTypes';

/** Context value interface */
interface AssetInsertContextValue {
  /** Current insert chains for all assets */
  chains: Record<AssetId, InsertChain>;
  /** Get chain for a specific asset */
  getChain: (assetId: AssetId) => InsertChain;
  /** Check if an asset has inserts */
  hasInserts: (assetId: AssetId) => boolean;
  /** Add a new insert to an asset chain */
  addInsert: (assetId: AssetId, pluginId: PluginId) => void;
  /** Remove an insert from an asset chain */
  removeInsert: (assetId: AssetId, insertId: InsertId) => void;
  /** Move an insert within an asset chain */
  moveInsert: (assetId: AssetId, insertId: InsertId, newIndex: number) => void;
  /** Toggle insert bypass */
  toggleBypass: (assetId: AssetId, insertId: InsertId) => void;
  /** Update insert parameters */
  updateParams: (assetId: AssetId, insertId: InsertId, params: Insert['params']) => void;
  /** Replace all chains (e.g., on project load) */
  setAllChains: (chains: Record<AssetId, InsertChain>) => void;
  /** Replace a single asset chain */
  setChain: (assetId: AssetId, chain: InsertChain) => void;
  /** Remove an entire asset chain */
  removeChain: (assetId: AssetId) => void;
  /** Get the DSP instance for advanced operations */
  getDSP: () => VoiceInsertDSP;
  /** Get count of active voice chains */
  getActiveVoiceChainCount: () => number;
  /** Get list of assets with chains defined */
  getAssetsWithChains: () => AssetId[];
}

const AssetInsertContext = createContext<AssetInsertContextValue | null>(null);

/** Combined state for external store pattern */
interface AssetInsertState {
  chains: Record<AssetId, InsertChain>;
}

/** Empty chain constant */
const EMPTY_CHAIN: InsertChain = { inserts: [] };

/** Store for external store pattern (efficient updates) */
class AssetInsertStore {
  private state: AssetInsertState;
  private listeners: Set<() => void> = new Set();
  private dsp: VoiceInsertDSP;

  constructor(dsp: VoiceInsertDSP) {
    this.state = {
      chains: {},
    };
    this.dsp = dsp;
  }

  getSnapshot = (): AssetInsertState => {
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
    this.dsp.setAssetInsertChains(this.state.chains);
  }

  getChain(assetId: AssetId): InsertChain {
    return this.state.chains[assetId] ?? EMPTY_CHAIN;
  }

  hasInserts(assetId: AssetId): boolean {
    const chain = this.state.chains[assetId];
    return chain !== undefined && chain.inserts.length > 0;
  }

  setAllChains(chains: Record<AssetId, InsertChain>) {
    // Chains should already be validated by validateProjectFile before reaching here.
    // NO clamping on load - invalid config must fail validation, not be silently fixed.
    this.state = { chains: { ...chains } };
    this.syncDSP();
    this.emit();
  }

  setChain(assetId: AssetId, chain: InsertChain) {
    this.state = {
      chains: {
        ...this.state.chains,
        [assetId]: chain,
      },
    };
    this.syncDSP();
    this.emit();
  }

  removeChain(assetId: AssetId) {
    const { [assetId]: _, ...rest } = this.state.chains;
    this.state = { chains: rest };
    this.syncDSP();
    this.emit();
  }

  addInsert(assetId: AssetId, pluginId: PluginId) {
    const insert = createDefaultInsert(pluginId);
    const currentChain = this.state.chains[assetId] ?? EMPTY_CHAIN;
    this.state = {
      chains: {
        ...this.state.chains,
        [assetId]: {
          inserts: [...currentChain.inserts, insert],
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  removeInsert(assetId: AssetId, insertId: InsertId) {
    const currentChain = this.state.chains[assetId];
    if (!currentChain) return;

    const newInserts = currentChain.inserts.filter((ins) => ins.id !== insertId);

    // If no inserts left, remove the entire chain
    if (newInserts.length === 0) {
      this.removeChain(assetId);
      return;
    }

    this.state = {
      chains: {
        ...this.state.chains,
        [assetId]: {
          inserts: newInserts,
        },
      },
    };
    this.syncDSP();
    this.emit();
  }

  moveInsert(assetId: AssetId, insertId: InsertId, newIndex: number) {
    const currentChain = this.state.chains[assetId];
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
        [assetId]: { inserts },
      },
    };
    this.syncDSP();
    this.emit();
  }

  toggleBypass(assetId: AssetId, insertId: InsertId) {
    const currentChain = this.state.chains[assetId];
    if (!currentChain) return;

    const insert = currentChain.inserts.find((ins) => ins.id === insertId);
    if (!insert) return;

    const newEnabled = !insert.enabled;

    this.state = {
      chains: {
        ...this.state.chains,
        [assetId]: {
          inserts: currentChain.inserts.map((ins) =>
            ins.id === insertId ? { ...ins, enabled: newEnabled } : ins
          ),
        },
      },
    };

    // Update DSP for all active voice chains using this asset
    this.dsp.setInsertEnabledForAsset(assetId, insertId, newEnabled);

    this.syncDSP();
    this.emit();
  }

  updateParams(assetId: AssetId, insertId: InsertId, params: Insert['params']) {
    const currentChain = this.state.chains[assetId];
    if (!currentChain) return;

    const insert = currentChain.inserts.find((ins) => ins.id === insertId);
    if (!insert) return;

    // MERGE params, not replace
    const updatedInsert = { ...insert, params: { ...insert.params, ...params } as any };

    this.state = {
      chains: {
        ...this.state.chains,
        [assetId]: {
          inserts: currentChain.inserts.map((ins) =>
            ins.id === insertId ? updatedInsert : ins
          ),
        },
      },
    };

    // Update DSP for all active voice chains using this asset
    this.dsp.updateAllVoiceChainsForAsset(assetId, updatedInsert);

    this.syncDSP();
    this.emit();
  }

  getDSP(): VoiceInsertDSP {
    return this.dsp;
  }

  getActiveVoiceChainCount(): number {
    return this.dsp.getActiveVoiceChainCount();
  }

  getAssetsWithChains(): AssetId[] {
    return Object.keys(this.state.chains).filter(
      (assetId) => this.state.chains[assetId].inserts.length > 0
    );
  }
}

interface AssetInsertProviderProps {
  children: ReactNode;
  /** AudioContext ref for DSP initialization */
  audioContextRef: React.MutableRefObject<AudioContext | null>;
  /** Initial chains to load (e.g., from project) */
  initialChains?: Record<AssetId, InsertChain>;
}

export function AssetInsertProvider({
  children,
  audioContextRef,
  initialChains,
}: AssetInsertProviderProps) {
  const storeRef = useRef<AssetInsertStore | null>(null);
  if (!storeRef.current) {
    storeRef.current = new AssetInsertStore(voiceInsertDSP);
    if (initialChains) {
      storeRef.current.setAllChains(initialChains);
    }
  }
  const store = storeRef.current;

  // Initialize DSP when AudioContext becomes available
  useEffect(() => {
    const checkAndInit = () => {
      const ctx = audioContextRef.current;

      if (ctx) {
        voiceInsertDSP.setAudioContext(ctx);
        // Apply initial chains after DSP is ready
        voiceInsertDSP.setAssetInsertChains(store.getSnapshot().chains);
      }
    };

    // Check immediately
    checkAndInit();

    // Also check periodically in case context is created later
    const interval = setInterval(checkAndInit, 100);

    return () => {
      clearInterval(interval);
    };
  }, [audioContextRef, store]);

  // Cleanup DSP on unmount
  useEffect(() => {
    return () => {
      voiceInsertDSP.disposeAllVoiceChains();
    };
  }, []);

  const state = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot
  );

  const { chains } = state;

  const handleGetChain = useCallback(
    (assetId: AssetId) => {
      return store.getChain(assetId);
    },
    [store]
  );

  const handleHasInserts = useCallback(
    (assetId: AssetId) => {
      return store.hasInserts(assetId);
    },
    [store]
  );

  const handleAddInsert = useCallback(
    (assetId: AssetId, pluginId: PluginId) => {
      store.addInsert(assetId, pluginId);
    },
    [store]
  );

  const handleRemoveInsert = useCallback(
    (assetId: AssetId, insertId: InsertId) => {
      store.removeInsert(assetId, insertId);
    },
    [store]
  );

  const handleMoveInsert = useCallback(
    (assetId: AssetId, insertId: InsertId, newIndex: number) => {
      store.moveInsert(assetId, insertId, newIndex);
    },
    [store]
  );

  const handleToggleBypass = useCallback(
    (assetId: AssetId, insertId: InsertId) => {
      store.toggleBypass(assetId, insertId);
    },
    [store]
  );

  const handleUpdateParams = useCallback(
    (assetId: AssetId, insertId: InsertId, params: Insert['params']) => {
      store.updateParams(assetId, insertId, params);
    },
    [store]
  );

  const handleSetAllChains = useCallback(
    (newChains: Record<AssetId, InsertChain>) => {
      store.setAllChains(newChains);
    },
    [store]
  );

  const handleSetChain = useCallback(
    (assetId: AssetId, chain: InsertChain) => {
      store.setChain(assetId, chain);
    },
    [store]
  );

  const handleRemoveChain = useCallback(
    (assetId: AssetId) => {
      store.removeChain(assetId);
    },
    [store]
  );

  const handleGetDSP = useCallback(() => {
    return store.getDSP();
  }, [store]);

  const handleGetActiveVoiceChainCount = useCallback(() => {
    return store.getActiveVoiceChainCount();
  }, [store]);

  const handleGetAssetsWithChains = useCallback(() => {
    return store.getAssetsWithChains();
  }, [store]);

  const value = useMemo<AssetInsertContextValue>(
    () => ({
      chains,
      getChain: handleGetChain,
      hasInserts: handleHasInserts,
      addInsert: handleAddInsert,
      removeInsert: handleRemoveInsert,
      moveInsert: handleMoveInsert,
      toggleBypass: handleToggleBypass,
      updateParams: handleUpdateParams,
      setAllChains: handleSetAllChains,
      setChain: handleSetChain,
      removeChain: handleRemoveChain,
      getDSP: handleGetDSP,
      getActiveVoiceChainCount: handleGetActiveVoiceChainCount,
      getAssetsWithChains: handleGetAssetsWithChains,
    }),
    [
      chains,
      handleGetChain,
      handleHasInserts,
      handleAddInsert,
      handleRemoveInsert,
      handleMoveInsert,
      handleToggleBypass,
      handleUpdateParams,
      handleSetAllChains,
      handleSetChain,
      handleRemoveChain,
      handleGetDSP,
      handleGetActiveVoiceChainCount,
      handleGetAssetsWithChains,
    ]
  );

  return (
    <AssetInsertContext.Provider value={value}>
      {children}
    </AssetInsertContext.Provider>
  );
}

export function useAssetInserts(): AssetInsertContextValue {
  const context = useContext(AssetInsertContext);
  if (!context) {
    throw new Error('useAssetInserts must be used within AssetInsertProvider');
  }
  return context;
}

/**
 * Hook that returns the chain for a specific asset.
 * Returns an empty chain if context is not available (graceful fallback).
 */
export function useAssetInsertChain(assetId: AssetId): InsertChain {
  const context = useContext(AssetInsertContext);
  if (!context) {
    return EMPTY_CHAIN;
  }
  return context.chains[assetId] ?? EMPTY_CHAIN;
}

/**
 * Hook that returns whether an asset has inserts defined.
 */
export function useAssetHasInserts(assetId: AssetId): boolean {
  const context = useContext(AssetInsertContext);
  if (!context) {
    return false;
  }
  const chain = context.chains[assetId];
  return chain !== undefined && chain.inserts.length > 0;
}
