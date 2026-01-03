/**
 * ReelForge Store Hooks
 *
 * Bridge hooks that provide backwards-compatible API
 * while using the new zustand store internally.
 *
 * These hooks maintain the same interface as the old contexts
 * so existing components don't need major refactoring.
 */

import { useCallback, useMemo } from 'react';
import {
  useReelForgeStore,
  useMixerState,
  useMixerActions,
  useProjectState,
  useProjectActions,
  useMasterInsertState,
  useMasterInsertActions,
  useBusInsertState,
  useBusInsertActions,
} from './reelforgeStore';
import type { ReelForgeProject } from '../core/types';
import type { MasterInsertChain, MasterInsert, InsertChain, Insert, PluginId, InsertId } from '../core/masterInsertTypes';
import type { InsertableBusId } from '../project/projectTypes';
import { validateRoutes } from '../core/validateRoutes';
import { masterInsertDSP } from '../core/masterInsertDSP';
import { busInsertDSP } from '../core/busInsertDSP';
import { calculateChainLatencyMs } from '../core/masterInsertTypes';

// Empty chain constant to avoid creating new objects on each render
const EMPTY_INSERT_CHAIN: InsertChain = { inserts: [] };

// ============ Mixer Hook (replaces useMixer) ============

export function useMixer() {
  const state = useMixerState();
  const actions = useMixerActions();
  const project = useReelForgeStore((s) => s.project);
  const detachedWindow = useReelForgeStore((s) => s.detachedWindow);

  const setProject = useCallback((proj: ReelForgeProject | null) => {
    if (proj) {
      actions.initBusVolumes(proj);
    }
  }, [actions]);

  // Memoize return object to prevent infinite loops
  return useMemo(() => ({
    state: {
      project: project as unknown as ReelForgeProject | null,
      isDetached: state.isDetached,
      isVisible: state.isVisible,
      detachedWindow,
      busVolumes: state.busVolumes,
    },
    setProject,
    setDetached: actions.setDetached,
    setVisible: actions.setVisible,
    setDetachedWindow: actions.setDetachedWindow,
    updateBus: actions.updateBus,
    getBusState: actions.getBusState,
  }), [state, actions, project, detachedWindow, setProject]);
}

// ============ Project Hook (replaces useProject) ============

export function useProject() {
  const state = useProjectState();
  const actions = useProjectActions();
  const lastSavedJson = useReelForgeStore((s) => s.lastSavedJson);

  const getRoutesConfig = useCallback(() => state.workingRoutes, [state.workingRoutes]);

  // Memoize return object to prevent infinite loops
  return useMemo(() => ({
    // State
    project: state.project,
    workingRoutes: state.workingRoutes,
    assetIds: state.assetIds,
    assetIndex: state.assetIndex,
    isDirty: state.isDirty,
    isLoading: state.isLoading,
    error: state.projectError,
    lastSavedJson,

    // Actions - these need to be implemented with actual storage logic
    // For now, provide the basic setters
    setProject: actions.setProject,
    setWorkingRoutes: actions.setWorkingRoutes,
    setProjectName: actions.setProjectName,
    setStudioPreferences: actions.setStudioPreferences,
    setRoutesUiState: actions.setRoutesUiState,
    markSaved: actions.markSaved,
    isEmbedded: actions.isEmbedded,
    getRoutesConfig,

    // Placeholder actions that need storage integration
    newProject: async (_name: string, _manifestPath: string) => {
      console.warn('[useProject] newProject not yet migrated to zustand');
    },
    openProject: async (): Promise<boolean> => {
      console.warn('[useProject] openProject not yet migrated to zustand');
      return false;
    },
    saveProject: async (_filename?: string) => {
      console.warn('[useProject] saveProject not yet migrated to zustand');
    },
    saveProjectAs: async () => {
      console.warn('[useProject] saveProjectAs not yet migrated to zustand');
    },
    reloadExternalRoutes: async () => {
      console.warn('[useProject] reloadExternalRoutes not yet migrated to zustand');
    },
    embedRoutes: () => {
      console.warn('[useProject] embedRoutes not yet migrated to zustand');
    },
  }), [state, actions, lastSavedJson, getRoutesConfig]);
}

// ============ Project Routes Hook (replaces useProjectRoutes) ============

export function useProjectRoutes() {
  const workingRoutes = useReelForgeStore((s) => s.workingRoutes);
  const assetIds = useReelForgeStore((s) => s.assetIds);

  const validation = useMemo(() => {
    if (!workingRoutes) {
      return { valid: false, errors: [], warnings: [] };
    }
    return validateRoutes(workingRoutes, assetIds ?? undefined);
  }, [workingRoutes, assetIds]);

  return { routes: workingRoutes, validation };
}

// ============ Master Inserts Hook (replaces useMasterInserts) ============

export function useMasterInserts() {
  const state = useMasterInsertState();
  const actions = useMasterInsertActions();

  // Calculate derived values
  const latencyMs = useMemo(
    () => calculateChainLatencyMs(state.chain),
    [state.chain]
  );

  const compensationDelayMs = useMemo(
    () => masterInsertDSP.getCompensationDelayMs(),
    [state.chain, state.pdcEnabled]
  );

  const pdcClamped = useMemo(
    () => masterInsertDSP.isCompensationClamped(),
    [state.chain, state.pdcEnabled]
  );

  const sampleRate = useMemo(
    () => masterInsertDSP.getSampleRate(),
    []
  );

  // DSP sync is now handled directly in zustand store actions (Cubase-style)
  // This ensures DSP is always in sync immediately after state changes

  // Sync DSP when chain changes (for bulk updates like project load)
  const setChain = useCallback((chain: MasterInsertChain) => {
    actions.setMasterChain(chain);
    if (masterInsertDSP.isInitialized()) {
      masterInsertDSP.applyChain(chain);
    }
  }, [actions]);

  // Simple pass-through to zustand actions - DSP sync is in the store
  const addInsert = useCallback((pluginId: PluginId) => {
    console.log('[useMasterInserts] addInsert called for:', pluginId);
    actions.addMasterInsert(pluginId);
  }, [actions]);

  const removeInsert = useCallback((insertId: InsertId) => {
    actions.removeMasterInsert(insertId);
  }, [actions]);

  const moveInsert = useCallback((insertId: InsertId, newIndex: number) => {
    actions.moveMasterInsert(insertId, newIndex);
  }, [actions]);

  const toggleBypass = useCallback((insertId: InsertId) => {
    actions.toggleMasterBypass(insertId);
  }, [actions]);

  const setInsertEnabled = useCallback((insertId: InsertId, enabled: boolean) => {
    actions.setMasterInsertEnabled(insertId, enabled);
  }, [actions]);

  const updateParams = useCallback((insertId: InsertId, params: MasterInsert['params']) => {
    actions.updateMasterParams(insertId, params);
  }, [actions]);

  const setPdcEnabled = useCallback((enabled: boolean) => {
    actions.setMasterPdcEnabled(enabled);
    masterInsertDSP.setPdcEnabled(enabled);
  }, [actions]);

  const getDSP = useCallback(() => masterInsertDSP, []);

  // Memoize return object to prevent infinite loops
  return useMemo(() => ({
    chain: state.chain,
    latencyMs,
    pdcEnabled: state.pdcEnabled,
    compensationDelayMs,
    pdcClamped,
    sampleRate,
    addInsert,
    removeInsert,
    moveInsert,
    toggleBypass,
    setInsertEnabled,
    updateParams,
    setChain,
    setPdcEnabled,
    getDSP,
  }), [
    state.chain, latencyMs, state.pdcEnabled, compensationDelayMs, pdcClamped, sampleRate,
    addInsert, removeInsert, moveInsert, toggleBypass, setInsertEnabled, updateParams, setChain, setPdcEnabled, getDSP
  ]);
}

// ============ Bus Inserts Hook (replaces useBusInserts) ============

export function useBusInserts() {
  const state = useBusInsertState();
  const actions = useBusInsertActions();

  const getChain = useCallback((busId: InsertableBusId): InsertChain => {
    return state.chains[busId] ?? EMPTY_INSERT_CHAIN;
  }, [state.chains]);

  const getLatencyMs = useCallback((busId: InsertableBusId): number => {
    return busInsertDSP.getLatencyMs(busId);
  }, []);

  // Actions with DSP sync
  const addInsert = useCallback((busId: InsertableBusId, pluginId: PluginId) => {
    actions.addBusInsert(busId, pluginId);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const removeInsert = useCallback((busId: InsertableBusId, insertId: InsertId) => {
    actions.removeBusInsert(busId, insertId);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const moveInsert = useCallback((busId: InsertableBusId, insertId: InsertId, newIndex: number) => {
    actions.moveBusInsert(busId, insertId, newIndex);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const toggleBypass = useCallback((busId: InsertableBusId, insertId: InsertId) => {
    actions.toggleBusInsertBypass(busId, insertId);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const updateParams = useCallback((busId: InsertableBusId, insertId: InsertId, params: Insert['params']) => {
    actions.updateBusInsertParams(busId, insertId, params);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const setAllChains = useCallback((chains: Partial<Record<InsertableBusId, InsertChain>>) => {
    actions.setBusChains(chains);
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const setChain = useCallback((busId: InsertableBusId, chain: InsertChain) => {
    actions.setBusChain(busId, chain);
    const chains = useReelForgeStore.getState().busChains;
    busInsertDSP.applyAllChains(chains);
  }, [actions]);

  const setBusPdcEnabled = useCallback((busId: InsertableBusId, enabled: boolean) => {
    actions.setBusPdcEnabled(busId, enabled);
    busInsertDSP.setBusPdcEnabled(busId, enabled);
  }, [actions]);

  // Memoize stable function references
  const getDSP = useCallback(() => busInsertDSP, []);
  const onDuckerVoiceStart = useCallback(() => busInsertDSP.onDuckerVoiceStart(), []);
  const onDuckerVoiceEnd = useCallback(() => busInsertDSP.onDuckerVoiceEnd(), []);
  const resetDucking = useCallback(() => busInsertDSP.resetDucking(), []);
  const getDuckingState = useCallback(() => busInsertDSP.getDuckingState(), []);
  const getDuckGainValue = useCallback((busId: InsertableBusId) => busInsertDSP.getDuckGainValue(busId), []);
  const isBusPdcEnabled = useCallback((busId: InsertableBusId) => busInsertDSP.isBusPdcEnabled(busId), []);
  const isBusPdcClamped = useCallback((busId: InsertableBusId) => busInsertDSP.isBusPdcClamped(busId), []);
  const getBusPdcDelayMs = useCallback((busId: InsertableBusId) => busInsertDSP.getBusPdcDelayMs(busId), []);
  const getBusPdcMaxMs = useCallback(() => busInsertDSP.getBusPdcMaxMs(), []);
  const applyAllBusPdc = useCallback((pdcEnabled: Partial<Record<InsertableBusId, boolean>>) => {
    actions.applyAllBusPdc(pdcEnabled);
    busInsertDSP.applyAllBusPdc(pdcEnabled);
  }, [actions]);
  const getAllBusPdcState = useCallback(() => busInsertDSP.getAllBusPdcState(), []);

  // Memoize return object to prevent infinite loops
  return useMemo(() => ({
    chains: state.chains,
    getChain,
    getLatencyMs,
    addInsert,
    removeInsert,
    moveInsert,
    toggleBypass,
    updateParams,
    setAllChains,
    setChain,
    getDSP,
    // Ducking methods
    onDuckerVoiceStart,
    onDuckerVoiceEnd,
    resetDucking,
    getDuckingState,
    getDuckGainValue,
    // PDC methods
    setBusPdcEnabled,
    isBusPdcEnabled,
    isBusPdcClamped,
    getBusPdcDelayMs,
    getBusPdcMaxMs,
    applyAllBusPdc,
    getAllBusPdcState,
  }), [
    state.chains, getChain, getLatencyMs,
    addInsert, removeInsert, moveInsert, toggleBypass, updateParams, setAllChains, setChain, getDSP,
    onDuckerVoiceStart, onDuckerVoiceEnd, resetDucking, getDuckingState, getDuckGainValue,
    setBusPdcEnabled, isBusPdcEnabled, isBusPdcClamped, getBusPdcDelayMs, getBusPdcMaxMs,
    applyAllBusPdc, getAllBusPdcState
  ]);
}

// ============ Convenience Hooks ============

export function useMasterInsertChain(): MasterInsertChain {
  return useReelForgeStore((s) => s.masterChain);
}

export function useMasterInsertLatency(): number {
  const chain = useReelForgeStore((s) => s.masterChain);
  return useMemo(() => calculateChainLatencyMs(chain), [chain]);
}

export function usePdcState() {
  const pdcEnabled = useReelForgeStore((s) => s.masterPdcEnabled);
  const chain = useReelForgeStore((s) => s.masterChain);

  return useMemo(() => ({
    enabled: pdcEnabled,
    compensationMs: masterInsertDSP.getCompensationDelayMs(),
  }), [pdcEnabled, chain]);
}

export function useMasterInsertSampleRate(): number {
  return masterInsertDSP.getSampleRate();
}

export function useBusInsertChain(busId: InsertableBusId): InsertChain {
  return useReelForgeStore((s) => s.busChains[busId] ?? EMPTY_INSERT_CHAIN);
}

export function useBusInsertLatency(busId: InsertableBusId): number {
  return busInsertDSP.getLatencyMs(busId);
}
