/**
 * useBusState - Bus/Mixer State Hook
 *
 * Manages mixer bus state:
 * - Volume, pan, mute, solo for each bus
 * - Insert slots
 * - Syncs with AudioGraph
 *
 * @module layout/editor/hooks/useBusState
 */

import { useState, useCallback, useMemo } from 'react';
import { DEMO_BUSES } from '../constants';
import type { BusState, BusInsertSlot } from '../types';

// ============ Types ============

export interface UseBusStateReturn {
  /** Current bus states */
  busStates: BusState[];
  /** Update bus volume */
  setBusVolume: (busId: string, volume: number) => void;
  /** Update bus pan */
  setBusPan: (busId: string, pan: number) => void;
  /** Toggle bus mute */
  toggleBusMute: (busId: string) => void;
  /** Toggle bus solo */
  toggleBusSolo: (busId: string) => void;
  /** Add insert to bus */
  addBusInsert: (busId: string, insert: BusInsertSlot) => void;
  /** Remove insert from bus */
  removeBusInsert: (busId: string, slotIndex: number) => void;
  /** Toggle insert bypass */
  toggleInsertBypass: (busId: string, slotIndex: number) => void;
  /** Update insert */
  updateBusInsert: (busId: string, slotIndex: number, updates: Partial<BusInsertSlot>) => void;
  /** Get bus by ID */
  getBus: (busId: string) => BusState | undefined;
  /** Is any bus soloed */
  hasAnySolo: boolean;
  /** Get effective mute state (considering solo) */
  isEffectivelyMuted: (busId: string) => boolean;
}

// ============ Hook ============

export function useBusState(
  onVolumeChange?: (busId: string, volume: number) => void,
  onPanChange?: (busId: string, pan: number) => void
): UseBusStateReturn {
  const [busStates, setBusStates] = useState<BusState[]>(() =>
    DEMO_BUSES.map(bus => ({ ...bus }))
  );

  // Check if any bus is soloed
  const hasAnySolo = useMemo(() =>
    busStates.some(bus => bus.soloed),
    [busStates]
  );

  // Get effective mute state
  const isEffectivelyMuted = useCallback((busId: string): boolean => {
    const bus = busStates.find(b => b.id === busId);
    if (!bus) return true;
    if (bus.muted) return true;
    if (hasAnySolo && !bus.soloed) return true;
    return false;
  }, [busStates, hasAnySolo]);

  // Set bus volume
  const setBusVolume = useCallback((busId: string, volume: number) => {
    setBusStates(prev => prev.map(bus =>
      bus.id === busId ? { ...bus, volume } : bus
    ));
    onVolumeChange?.(busId, volume);
  }, [onVolumeChange]);

  // Set bus pan
  const setBusPan = useCallback((busId: string, pan: number) => {
    setBusStates(prev => prev.map(bus =>
      bus.id === busId ? { ...bus, pan } : bus
    ));
    onPanChange?.(busId, pan);
  }, [onPanChange]);

  // Toggle bus mute
  const toggleBusMute = useCallback((busId: string) => {
    setBusStates(prev => prev.map(bus =>
      bus.id === busId ? { ...bus, muted: !bus.muted } : bus
    ));
  }, []);

  // Toggle bus solo
  const toggleBusSolo = useCallback((busId: string) => {
    setBusStates(prev => prev.map(bus =>
      bus.id === busId ? { ...bus, soloed: !bus.soloed } : bus
    ));
  }, []);

  // Add insert to bus
  const addBusInsert = useCallback((busId: string, insert: BusInsertSlot) => {
    setBusStates(prev => prev.map(bus => {
      if (bus.id !== busId) return bus;
      return {
        ...bus,
        inserts: [...bus.inserts, insert],
      };
    }));
  }, []);

  // Remove insert from bus
  const removeBusInsert = useCallback((busId: string, slotIndex: number) => {
    setBusStates(prev => prev.map(bus => {
      if (bus.id !== busId) return bus;
      return {
        ...bus,
        inserts: bus.inserts.filter((_, i) => i !== slotIndex),
      };
    }));
  }, []);

  // Toggle insert bypass
  const toggleInsertBypass = useCallback((busId: string, slotIndex: number) => {
    setBusStates(prev => prev.map(bus => {
      if (bus.id !== busId) return bus;
      return {
        ...bus,
        inserts: bus.inserts.map((insert, i) =>
          i === slotIndex ? { ...insert, bypassed: !insert.bypassed } : insert
        ),
      };
    }));
  }, []);

  // Update insert
  const updateBusInsert = useCallback((busId: string, slotIndex: number, updates: Partial<BusInsertSlot>) => {
    setBusStates(prev => prev.map(bus => {
      if (bus.id !== busId) return bus;
      return {
        ...bus,
        inserts: bus.inserts.map((insert, i) =>
          i === slotIndex ? { ...insert, ...updates } : insert
        ),
      };
    }));
  }, []);

  // Get bus by ID
  const getBus = useCallback((busId: string): BusState | undefined => {
    return busStates.find(bus => bus.id === busId);
  }, [busStates]);

  return {
    busStates,
    setBusVolume,
    setBusPan,
    toggleBusMute,
    toggleBusSolo,
    addBusInsert,
    removeBusInsert,
    toggleInsertBypass,
    updateBusInsert,
    getBus,
    hasAnySolo,
    isEffectivelyMuted,
  };
}

export default useBusState;
