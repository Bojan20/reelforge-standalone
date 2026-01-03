/**
 * ReelForge Unified Store (Zustand)
 *
 * Centralized state management replacing:
 * - MixerContext
 * - ProjectContext
 * - MasterInsertContext
 * - BusInsertContext
 *
 * Uses slices pattern for modularity.
 */

import { create } from 'zustand';
import { subscribeWithSelector } from 'zustand/middleware';
import { useShallow } from 'zustand/shallow';
import type { ReelForgeProject, BusId } from '../core/types';
import type { ProjectFileV1, StudioPreferences, RoutesUiState } from '../project/projectTypes';
import { createDefaultProject, DEFAULT_STUDIO_PREFERENCES } from '../project/projectTypes';
import type { RoutesConfig } from '../core/routesTypes';
import type {
  MasterInsertChain,
  MasterInsert,
  InsertChain,
  Insert,
  PluginId,
  InsertId,
} from '../core/masterInsertTypes';
import { createEmptyChain, createDefaultInsert, calculateChainLatencyMs } from '../core/masterInsertTypes';
import { masterInsertDSP } from '../core/masterInsertDSP';
import type { InsertableBusId } from '../project/projectTypes';
import { AssetIndex } from '../core/assetIndex';

// ============ Types ============

interface BusState {
  volume: number;
  muted: boolean;
}

export interface BusPdcState {
  enabled: boolean;
  delayMs: number;
  clamped: boolean;
}

// ============ Mixer Slice ============

interface MixerSlice {
  // State
  isDetached: boolean;
  isVisible: boolean;
  detachedWindow: Window | null;
  busVolumes: Partial<Record<BusId, BusState>>;

  // Actions
  setDetached: (detached: boolean) => void;
  setVisible: (visible: boolean) => void;
  setDetachedWindow: (window: Window | null) => void;
  updateBus: (busId: BusId, volume: number, muted?: boolean) => void;
  getBusState: (busId: BusId) => BusState;
  initBusVolumes: (project: ReelForgeProject) => void;
}

// ============ Project Slice ============

interface ProjectSlice {
  // State
  project: ProjectFileV1;
  workingRoutes: RoutesConfig | null;
  assetIds: Set<string> | null;
  assetIndex: AssetIndex | null;
  isDirty: boolean;
  isLoading: boolean;
  projectError: string | null;
  lastSavedJson: string | null;

  // Actions
  setProject: (project: ProjectFileV1) => void;
  setWorkingRoutes: (routes: RoutesConfig) => void;
  setAssetIds: (ids: Set<string>) => void;
  setAssetIndex: (index: AssetIndex) => void;
  setIsDirty: (dirty: boolean) => void;
  setIsLoading: (loading: boolean) => void;
  setProjectError: (error: string | null) => void;
  setLastSavedJson: (json: string | null) => void;
  setProjectName: (name: string) => void;
  setStudioPreferences: (prefs: Partial<StudioPreferences>) => void;
  setRoutesUiState: (state: Partial<RoutesUiState>) => void;
  markSaved: () => void;
  isEmbedded: () => boolean;
}

// ============ Master Insert Slice ============

interface MasterInsertSlice {
  // State
  masterChain: MasterInsertChain;
  masterPdcEnabled: boolean;

  // Actions
  setMasterChain: (chain: MasterInsertChain) => void;
  addMasterInsert: (pluginId: PluginId) => void;
  removeMasterInsert: (insertId: InsertId) => void;
  moveMasterInsert: (insertId: InsertId, newIndex: number) => void;
  toggleMasterBypass: (insertId: InsertId) => void;
  setMasterInsertEnabled: (insertId: InsertId, enabled: boolean) => void;
  updateMasterParams: (insertId: InsertId, params: MasterInsert['params']) => void;
  setMasterPdcEnabled: (enabled: boolean) => void;
  getMasterLatencyMs: () => number;
}

// ============ Bus Insert Slice ============

interface BusInsertSlice {
  // State
  busChains: Partial<Record<InsertableBusId, InsertChain>>;
  busPdcEnabled: Partial<Record<InsertableBusId, boolean>>;

  // Actions
  setBusChains: (chains: Partial<Record<InsertableBusId, InsertChain>>) => void;
  setBusChain: (busId: InsertableBusId, chain: InsertChain) => void;
  addBusInsert: (busId: InsertableBusId, pluginId: PluginId) => void;
  removeBusInsert: (busId: InsertableBusId, insertId: InsertId) => void;
  moveBusInsert: (busId: InsertableBusId, insertId: InsertId, newIndex: number) => void;
  toggleBusInsertBypass: (busId: InsertableBusId, insertId: InsertId) => void;
  updateBusInsertParams: (busId: InsertableBusId, insertId: InsertId, params: Insert['params']) => void;
  getBusChain: (busId: InsertableBusId) => InsertChain;
  setBusPdcEnabled: (busId: InsertableBusId, enabled: boolean) => void;
  applyAllBusPdc: (pdcEnabled: Partial<Record<InsertableBusId, boolean>>) => void;
}

// ============ Combined Store Type ============

export type ReelForgeStore = MixerSlice & ProjectSlice & MasterInsertSlice & BusInsertSlice;

// ============ Empty Chain Constant ============

const EMPTY_CHAIN: InsertChain = { inserts: [] };

// ============ Store Creation ============

export const useReelForgeStore = create<ReelForgeStore>()(
  subscribeWithSelector((set, get) => ({
    // ============ Mixer Slice ============
    isDetached: false,
    isVisible: false,
    detachedWindow: null,
    busVolumes: {},

    setDetached: (detached) => set({ isDetached: detached }),
    setVisible: (visible) => set({ isVisible: visible }),
    setDetachedWindow: (window) => set({ detachedWindow: window }),

    updateBus: (busId, volume, muted) => {
      const current = get().busVolumes[busId];
      set({
        busVolumes: {
          ...get().busVolumes,
          [busId]: {
            volume,
            muted: muted ?? current?.muted ?? false,
          },
        },
      });
    },

    getBusState: (busId) => {
      return get().busVolumes[busId] || { volume: 1, muted: false };
    },

    initBusVolumes: (project) => {
      const busVolumes: Partial<Record<BusId, BusState>> = {};
      project.buses.forEach((bus) => {
        busVolumes[bus.id] = {
          volume: bus.volume,
          muted: bus.muted ?? false,
        };
      });
      set({ busVolumes });
    },

    // ============ Project Slice ============
    project: createDefaultProject(),
    workingRoutes: null,
    assetIds: null,
    assetIndex: null,
    isDirty: false,
    isLoading: true,
    projectError: null,
    lastSavedJson: null,

    setProject: (project) => set({ project }),
    setWorkingRoutes: (routes) => set({ workingRoutes: routes, isDirty: true }),
    setAssetIds: (ids) => set({ assetIds: ids }),
    setAssetIndex: (index) => set({ assetIndex: index }),
    setIsDirty: (dirty) => set({ isDirty: dirty }),
    setIsLoading: (loading) => set({ isLoading: loading }),
    setProjectError: (error) => set({ projectError: error }),
    setLastSavedJson: (json) => set({ lastSavedJson: json }),

    setProjectName: (name) => {
      set((state) => ({
        project: { ...state.project, name },
        isDirty: true,
      }));
    },

    setStudioPreferences: (prefs) => {
      set((state) => ({
        project: {
          ...state.project,
          studio: {
            ...DEFAULT_STUDIO_PREFERENCES,
            ...state.project.studio,
            ...prefs,
          },
        },
      }));
    },

    setRoutesUiState: (uiState) => {
      set((state) => ({
        project: {
          ...state.project,
          studio: {
            ...DEFAULT_STUDIO_PREFERENCES,
            ...state.project.studio,
            routesUi: {
              ...state.project.studio?.routesUi,
              ...uiState,
            },
          },
        },
      }));
    },

    markSaved: () => set({ isDirty: false }),

    isEmbedded: () => get().project.routes.embed,

    // ============ Master Insert Slice ============
    masterChain: createEmptyChain(),
    masterPdcEnabled: false,

    setMasterChain: (chain) => set({ masterChain: chain }),

    addMasterInsert: (pluginId) => {
      const insert = createDefaultInsert(pluginId);
      set((state) => ({
        masterChain: {
          inserts: [...state.masterChain.inserts, insert],
        },
      }));

      // CUBASE-STYLE: Synchronously create DSP graph immediately after state update
      // This ensures DSP is ready before any UI tries to access it
      const newChain = get().masterChain;
      if (masterInsertDSP.isInitialized()) {
        console.log('[reelforgeStore] Syncing chain to DSP after addMasterInsert:', {
          insertCount: newChain.inserts.length,
          newInsertId: insert.id,
        });
        masterInsertDSP.applyChain(newChain);
      } else {
        console.warn('[reelforgeStore] DSP not initialized, insert will be synced later');
      }
    },

    removeMasterInsert: (insertId) => {
      set((state) => ({
        masterChain: {
          inserts: state.masterChain.inserts.filter((ins) => ins.id !== insertId),
        },
      }));
      // Sync DSP after remove
      if (masterInsertDSP.isInitialized()) {
        masterInsertDSP.applyChain(get().masterChain);
      }
    },

    moveMasterInsert: (insertId, newIndex) => {
      set((state) => {
        const inserts = [...state.masterChain.inserts];
        const currentIndex = inserts.findIndex((ins) => ins.id === insertId);
        if (currentIndex === -1 || currentIndex === newIndex) return state;

        const [insert] = inserts.splice(currentIndex, 1);
        inserts.splice(newIndex, 0, insert);
        return { masterChain: { inserts } };
      });
      // Sync DSP after move
      if (masterInsertDSP.isInitialized()) {
        masterInsertDSP.applyChain(get().masterChain);
      }
    },

    toggleMasterBypass: (insertId) => {
      set((state) => ({
        masterChain: {
          inserts: state.masterChain.inserts.map((ins) =>
            ins.id === insertId ? { ...ins, enabled: !ins.enabled } : ins
          ),
        },
      }));
      // Sync DSP after bypass toggle
      if (masterInsertDSP.isInitialized()) {
        masterInsertDSP.applyChain(get().masterChain);
      }
    },

    setMasterInsertEnabled: (insertId, enabled) => {
      set((state) => ({
        masterChain: {
          inserts: state.masterChain.inserts.map((ins) =>
            ins.id === insertId ? { ...ins, enabled } : ins
          ),
        },
      }));
      // Sync DSP after enable change
      if (masterInsertDSP.isInitialized()) {
        masterInsertDSP.applyChain(get().masterChain);
      }
    },

    updateMasterParams: (insertId, params) => {
      console.debug('[zustand] updateMasterParams called:', {
        insertId,
        paramCount: Object.keys(params).length,
        sampleParams: Object.entries(params).slice(0, 3),
      });
      set((state) => ({
        masterChain: {
          inserts: state.masterChain.inserts.map((ins) =>
            ins.id === insertId
              ? { ...ins, params: { ...ins.params, ...params } as any }  // MERGE params, not replace
              : ins
          ),
        },
      }));
      // Sync DSP after param update
      if (masterInsertDSP.isInitialized()) {
        masterInsertDSP.applyChain(get().masterChain);
      }
      // Log updated state
      const updatedInsert = get().masterChain.inserts.find(ins => ins.id === insertId);
      console.debug('[zustand] After updateMasterParams:', {
        insertId,
        found: !!updatedInsert,
        newParamCount: updatedInsert ? Object.keys(updatedInsert.params).length : 0,
      });
    },

    setMasterPdcEnabled: (enabled) => set({ masterPdcEnabled: enabled }),

    getMasterLatencyMs: () => calculateChainLatencyMs(get().masterChain),

    // ============ Bus Insert Slice ============
    busChains: {},
    busPdcEnabled: {},

    setBusChains: (chains) => set({ busChains: { ...chains } }),

    setBusChain: (busId, chain) => {
      set((state) => ({
        busChains: {
          ...state.busChains,
          [busId]: chain,
        },
      }));
    },

    addBusInsert: (busId, pluginId) => {
      const insert = createDefaultInsert(pluginId);
      set((state) => {
        const currentChain = state.busChains[busId] ?? EMPTY_CHAIN;
        return {
          busChains: {
            ...state.busChains,
            [busId]: {
              inserts: [...currentChain.inserts, insert],
            },
          },
        };
      });
    },

    removeBusInsert: (busId, insertId) => {
      set((state) => {
        const currentChain = state.busChains[busId];
        if (!currentChain) return state;
        return {
          busChains: {
            ...state.busChains,
            [busId]: {
              inserts: currentChain.inserts.filter((ins) => ins.id !== insertId),
            },
          },
        };
      });
    },

    moveBusInsert: (busId, insertId, newIndex) => {
      set((state) => {
        const currentChain = state.busChains[busId];
        if (!currentChain) return state;

        const inserts = [...currentChain.inserts];
        const currentIndex = inserts.findIndex((ins) => ins.id === insertId);
        if (currentIndex === -1 || currentIndex === newIndex) return state;

        const [insert] = inserts.splice(currentIndex, 1);
        inserts.splice(newIndex, 0, insert);
        return {
          busChains: {
            ...state.busChains,
            [busId]: { inserts },
          },
        };
      });
    },

    toggleBusInsertBypass: (busId, insertId) => {
      set((state) => {
        const currentChain = state.busChains[busId];
        if (!currentChain) return state;
        return {
          busChains: {
            ...state.busChains,
            [busId]: {
              inserts: currentChain.inserts.map((ins) =>
                ins.id === insertId ? { ...ins, enabled: !ins.enabled } : ins
              ),
            },
          },
        };
      });
    },

    updateBusInsertParams: (busId, insertId, params) => {
      set((state) => {
        const currentChain = state.busChains[busId];
        if (!currentChain) return state;
        return {
          busChains: {
            ...state.busChains,
            [busId]: {
              inserts: currentChain.inserts.map((ins) =>
                ins.id === insertId
                  ? { ...ins, params: { ...ins.params, ...params } as any }  // MERGE params
                  : ins
              ),
            },
          },
        };
      });
    },

    getBusChain: (busId) => {
      return get().busChains[busId] ?? EMPTY_CHAIN;
    },

    setBusPdcEnabled: (busId, enabled) => {
      set((state) => ({
        busPdcEnabled: {
          ...state.busPdcEnabled,
          [busId]: enabled,
        },
      }));
    },

    applyAllBusPdc: (pdcEnabled) => {
      set({ busPdcEnabled: { ...pdcEnabled } });
    },
  }))
);

// ============ Selector Hooks (for performance) ============
// Note: useShallow prevents infinite loops by doing shallow comparison
// instead of reference equality on the returned object.

export const useMixerState = () =>
  useReelForgeStore(
    useShallow((state) => ({
      isDetached: state.isDetached,
      isVisible: state.isVisible,
      busVolumes: state.busVolumes,
    }))
  );

export const useProjectState = () =>
  useReelForgeStore(
    useShallow((state) => ({
      project: state.project,
      workingRoutes: state.workingRoutes,
      assetIds: state.assetIds,
      assetIndex: state.assetIndex,
      isDirty: state.isDirty,
      isLoading: state.isLoading,
      projectError: state.projectError,
    }))
  );

export const useMasterInsertState = () =>
  useReelForgeStore(
    useShallow((state) => ({
      chain: state.masterChain,
      pdcEnabled: state.masterPdcEnabled,
    }))
  );

export const useBusInsertState = () =>
  useReelForgeStore(
    useShallow((state) => ({
      chains: state.busChains,
      pdcEnabled: state.busPdcEnabled,
    }))
  );

// ============ Action Hooks ============
// Note: Actions are stable functions, but we still use useShallow
// to prevent new object creation triggering re-renders.

export const useMixerActions = () =>
  useReelForgeStore(
    useShallow((state) => ({
      setDetached: state.setDetached,
      setVisible: state.setVisible,
      setDetachedWindow: state.setDetachedWindow,
      updateBus: state.updateBus,
      getBusState: state.getBusState,
      initBusVolumes: state.initBusVolumes,
    }))
  );

export const useProjectActions = () =>
  useReelForgeStore(
    useShallow((state) => ({
      setProject: state.setProject,
      setWorkingRoutes: state.setWorkingRoutes,
      setAssetIds: state.setAssetIds,
      setAssetIndex: state.setAssetIndex,
      setIsDirty: state.setIsDirty,
      setIsLoading: state.setIsLoading,
      setProjectError: state.setProjectError,
      setLastSavedJson: state.setLastSavedJson,
      setProjectName: state.setProjectName,
      setStudioPreferences: state.setStudioPreferences,
      setRoutesUiState: state.setRoutesUiState,
      markSaved: state.markSaved,
      isEmbedded: state.isEmbedded,
    }))
  );

export const useMasterInsertActions = () =>
  useReelForgeStore(
    useShallow((state) => ({
      setMasterChain: state.setMasterChain,
      addMasterInsert: state.addMasterInsert,
      removeMasterInsert: state.removeMasterInsert,
      moveMasterInsert: state.moveMasterInsert,
      toggleMasterBypass: state.toggleMasterBypass,
      setMasterInsertEnabled: state.setMasterInsertEnabled,
      updateMasterParams: state.updateMasterParams,
      setMasterPdcEnabled: state.setMasterPdcEnabled,
      getMasterLatencyMs: state.getMasterLatencyMs,
    }))
  );

export const useBusInsertActions = () =>
  useReelForgeStore(
    useShallow((state) => ({
      setBusChains: state.setBusChains,
      setBusChain: state.setBusChain,
      addBusInsert: state.addBusInsert,
      removeBusInsert: state.removeBusInsert,
      moveBusInsert: state.moveBusInsert,
      toggleBusInsertBypass: state.toggleBusInsertBypass,
      updateBusInsertParams: state.updateBusInsertParams,
      getBusChain: state.getBusChain,
      setBusPdcEnabled: state.setBusPdcEnabled,
      applyAllBusPdc: state.applyAllBusPdc,
    }))
  );
