import { createContext, useContext, useReducer, useCallback, type ReactNode } from 'react';
import type { ReelForgeProject, BusId } from './core/types';

interface BusState {
  volume: number;
  muted: boolean;
}

interface MixerState {
  project: ReelForgeProject | null;
  isDetached: boolean;
  isVisible: boolean;
  detachedWindow: Window | null;
  busVolumes: Partial<Record<BusId, BusState>>;
}

type MixerAction =
  | { type: 'SET_PROJECT'; payload: ReelForgeProject | null }
  | { type: 'SET_DETACHED'; payload: boolean }
  | { type: 'SET_VISIBLE'; payload: boolean }
  | { type: 'SET_DETACHED_WINDOW'; payload: Window | null }
  | { type: 'UPDATE_BUS'; payload: { busId: BusId; volume: number; muted?: boolean } };

interface MixerContextType {
  state: MixerState;
  setProject: (project: ReelForgeProject | null) => void;
  setDetached: (detached: boolean) => void;
  setVisible: (visible: boolean) => void;
  setDetachedWindow: (window: Window | null) => void;
  updateBus: (busId: BusId, volume: number, muted?: boolean) => void;
  getBusState: (busId: BusId) => BusState;
}

const MixerContext = createContext<MixerContextType | null>(null);

const mixerReducer = (state: MixerState, action: MixerAction): MixerState => {
  switch (action.type) {
    case 'SET_PROJECT':
      if (!action.payload) {
        return { ...state, project: null, busVolumes: {} };
      }
      const busVolumes: Partial<Record<BusId, BusState>> = {};
      action.payload.buses.forEach(bus => {
        busVolumes[bus.id] = {
          volume: bus.volume,
          muted: bus.muted ?? false
        };
      });
      return { ...state, project: action.payload, busVolumes };
    case 'SET_DETACHED':
      return { ...state, isDetached: action.payload };
    case 'SET_VISIBLE':
      return { ...state, isVisible: action.payload };
    case 'SET_DETACHED_WINDOW':
      return { ...state, detachedWindow: action.payload };
    case 'UPDATE_BUS':
      const newBusVolumes = {
        ...state.busVolumes,
        [action.payload.busId]: {
          volume: action.payload.volume,
          muted: action.payload.muted ?? state.busVolumes[action.payload.busId]?.muted ?? false
        }
      };

      if (!state.project) return { ...state, busVolumes: newBusVolumes };

      return {
        ...state,
        busVolumes: newBusVolumes,
        project: {
          ...state.project,
          buses: state.project.buses.map(b =>
            b.id === action.payload.busId
              ? { ...b, volume: action.payload.volume, muted: action.payload.muted ?? b.muted }
              : b
          )
        }
      };
    default:
      return state;
  }
};

export function MixerProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(mixerReducer, {
    project: null,
    isDetached: false,
    isVisible: false,
    detachedWindow: null,
    busVolumes: {}
  });

  const setProject = useCallback((project: ReelForgeProject | null) => {
    dispatch({ type: 'SET_PROJECT', payload: project });
  }, []);

  const setDetached = useCallback((detached: boolean) => {
    dispatch({ type: 'SET_DETACHED', payload: detached });
  }, []);

  const setVisible = useCallback((visible: boolean) => {
    dispatch({ type: 'SET_VISIBLE', payload: visible });
  }, []);

  const setDetachedWindow = useCallback((window: Window | null) => {
    dispatch({ type: 'SET_DETACHED_WINDOW', payload: window });
  }, []);

  const updateBus = useCallback((busId: BusId, volume: number, muted?: boolean) => {
    dispatch({ type: 'UPDATE_BUS', payload: { busId, volume, muted } });
  }, []);

  const getBusState = useCallback((busId: BusId): BusState => {
    return state.busVolumes[busId] || { volume: 1, muted: false };
  }, [state.busVolumes]);

  return (
    <MixerContext.Provider value={{ state, setProject, setDetached, setVisible, setDetachedWindow, updateBus, getBusState }}>
      {children}
    </MixerContext.Provider>
  );
}

export function useMixer() {
  const context = useContext(MixerContext);
  if (!context) {
    throw new Error('useMixer must be used within MixerProvider');
  }
  return context;
}
