/**
 * ReelForge M8.3 Master A/B Snapshot Hook
 *
 * React hook for integrating A/B snapshot functionality with
 * MasterInsertContext. Provides capture and switch operations
 * that automatically sync with DSP.
 */

import { useCallback, useEffect, useState } from 'react';
import { useMasterInserts } from '../core/MasterInsertContext';
import {
  masterABSnapshot,
  type SnapshotSlot,
  type MasterABState,
  type MasterSnapshot,
} from '../core/masterABSnapshot';

/**
 * Hook return value
 */
interface UseMasterABSnapshotReturn {
  /** Current A/B state */
  abState: MasterABState;
  /** Currently active slot */
  activeSlot: SnapshotSlot;
  /** Whether slot A has a capture */
  hasSlotA: boolean;
  /** Whether slot B has a capture */
  hasSlotB: boolean;
  /** Whether A/B comparison is available */
  canCompare: boolean;
  /** Capture current chain to slot A */
  captureToA: () => void;
  /** Capture current chain to slot B */
  captureToB: () => void;
  /** Switch to slot A (applies snapshot to chain) */
  switchToA: () => boolean;
  /** Switch to slot B (applies snapshot to chain) */
  switchToB: () => boolean;
  /** Toggle between A and B */
  toggleAB: () => boolean;
  /** Clear a specific slot */
  clearSlot: (slot: SnapshotSlot) => void;
  /** Reset entire A/B state */
  resetAB: () => void;
}

/**
 * useMasterABSnapshot
 *
 * Provides A/B snapshot functionality integrated with MasterInsertContext.
 * Automatically applies snapshots to the chain when switching slots.
 */
export function useMasterABSnapshot(): UseMasterABSnapshotReturn {
  const { chain, pdcEnabled, setChain, setPdcEnabled } = useMasterInserts();
  const [abState, setABState] = useState<MasterABState>(
    masterABSnapshot.getState()
  );

  // Subscribe to A/B state changes
  useEffect(() => {
    const unsubscribe = masterABSnapshot.subscribe((state) => {
      setABState(state);
    });
    return unsubscribe;
  }, []);

  // Initialize slot A with current chain on first mount
  useEffect(() => {
    masterABSnapshot.initializeWithChain(chain, pdcEnabled);
    // Only run once
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /**
   * Apply a snapshot to the current chain (with click-free transition via DSP).
   */
  const applySnapshot = useCallback(
    (snapshot: MasterSnapshot) => {
      // setChain will sync with DSP automatically
      setChain(snapshot.chain);
      setPdcEnabled(snapshot.pdcEnabled);
    },
    [setChain, setPdcEnabled]
  );

  /**
   * Capture current chain to slot A.
   */
  const captureToA = useCallback(() => {
    masterABSnapshot.captureToSlot('A', chain, pdcEnabled);
  }, [chain, pdcEnabled]);

  /**
   * Capture current chain to slot B.
   */
  const captureToB = useCallback(() => {
    masterABSnapshot.captureToSlot('B', chain, pdcEnabled);
  }, [chain, pdcEnabled]);

  /**
   * Switch to slot A and apply its snapshot.
   * Returns true if switch was successful.
   */
  const switchToA = useCallback((): boolean => {
    const snapshot = masterABSnapshot.switchToSlot('A');
    if (snapshot) {
      applySnapshot(snapshot);
      return true;
    }
    return false;
  }, [applySnapshot]);

  /**
   * Switch to slot B and apply its snapshot.
   * Returns true if switch was successful.
   */
  const switchToB = useCallback((): boolean => {
    const snapshot = masterABSnapshot.switchToSlot('B');
    if (snapshot) {
      applySnapshot(snapshot);
      return true;
    }
    return false;
  }, [applySnapshot]);

  /**
   * Toggle between A and B and apply the new snapshot.
   * Returns true if toggle was successful.
   */
  const toggleAB = useCallback((): boolean => {
    const snapshot = masterABSnapshot.toggleSlot();
    if (snapshot) {
      applySnapshot(snapshot);
      return true;
    }
    return false;
  }, [applySnapshot]);

  /**
   * Clear a specific slot.
   */
  const clearSlot = useCallback((slot: SnapshotSlot) => {
    masterABSnapshot.clearSlot(slot);
  }, []);

  /**
   * Reset entire A/B state.
   */
  const resetAB = useCallback(() => {
    masterABSnapshot.reset();
  }, []);

  return {
    abState,
    activeSlot: abState.activeSlot,
    hasSlotA: abState.slotA.capturedAt > 0,
    hasSlotB: abState.slotB.capturedAt > 0,
    canCompare: abState.slotA.capturedAt > 0 && abState.slotB.capturedAt > 0,
    captureToA,
    captureToB,
    switchToA,
    switchToB,
    toggleAB,
    clearSlot,
    resetAB,
  };
}
