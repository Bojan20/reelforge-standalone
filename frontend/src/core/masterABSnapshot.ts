/**
 * ReelForge M8.3 Master A/B Snapshot
 *
 * Provides A/B comparison feature for master insert chain.
 * Two slots (A and B) store full chain state + PDC flag.
 * Instant switching with click-free transitions.
 *
 * IMPORTANT: Master-only feature. Bus insert chains do not have A/B.
 */

import type { MasterInsertChain } from './masterInsertTypes';
import { createEmptyChain } from './masterInsertTypes';
import { cloneChain } from './insertChainClipboard';

// ============ Types ============

/** Which snapshot slot is active */
export type SnapshotSlot = 'A' | 'B';

/** Full snapshot state for one slot */
export interface MasterSnapshot {
  /** Insert chain configuration */
  chain: MasterInsertChain;
  /** PDC enabled state */
  pdcEnabled: boolean;
  /** Timestamp of last capture (0 = never captured) */
  capturedAt: number;
}

/** A/B state container */
export interface MasterABState {
  /** Slot A snapshot */
  slotA: MasterSnapshot;
  /** Slot B snapshot */
  slotB: MasterSnapshot;
  /** Currently active slot */
  activeSlot: SnapshotSlot;
}

/** Callback for state changes */
export type ABStateListener = (state: MasterABState) => void;

// ============ Default State ============

function createEmptySnapshot(): MasterSnapshot {
  return {
    chain: createEmptyChain(),
    pdcEnabled: false,
    capturedAt: 0,
  };
}

function createDefaultABState(): MasterABState {
  return {
    slotA: createEmptySnapshot(),
    slotB: createEmptySnapshot(),
    activeSlot: 'A',
  };
}

// ============ A/B Snapshot Manager ============

/**
 * MasterABSnapshotManager
 *
 * Manages A/B snapshot state for master insert chain.
 * Session-only storage (not persisted to project file).
 */
class MasterABSnapshotManager {
  private state: MasterABState;
  private listeners: Set<ABStateListener> = new Set();

  constructor() {
    this.state = createDefaultABState();
  }

  /**
   * Get current A/B state.
   */
  getState(): MasterABState {
    return this.state;
  }

  /**
   * Get active slot identifier.
   */
  getActiveSlot(): SnapshotSlot {
    return this.state.activeSlot;
  }

  /**
   * Get snapshot for a specific slot.
   */
  getSnapshot(slot: SnapshotSlot): MasterSnapshot {
    return slot === 'A' ? this.state.slotA : this.state.slotB;
  }

  /**
   * Get active snapshot.
   */
  getActiveSnapshot(): MasterSnapshot {
    return this.getSnapshot(this.state.activeSlot);
  }

  /**
   * Check if a slot has been captured.
   */
  hasCapture(slot: SnapshotSlot): boolean {
    return this.getSnapshot(slot).capturedAt > 0;
  }

  /**
   * Capture current chain state to a slot.
   * Creates a deep clone of the chain.
   */
  captureToSlot(
    slot: SnapshotSlot,
    chain: MasterInsertChain,
    pdcEnabled: boolean
  ): void {
    const snapshot: MasterSnapshot = {
      chain: cloneChain(chain),
      pdcEnabled,
      capturedAt: Date.now(),
    };

    if (slot === 'A') {
      this.state = { ...this.state, slotA: snapshot };
    } else {
      this.state = { ...this.state, slotB: snapshot };
    }

    this.emit();
  }

  /**
   * Switch to a different slot.
   * Returns the new active snapshot or null if slot is empty.
   */
  switchToSlot(slot: SnapshotSlot): MasterSnapshot | null {
    if (this.state.activeSlot === slot) {
      // Already active, return current snapshot
      return this.getSnapshot(slot);
    }

    const snapshot = this.getSnapshot(slot);

    // Only switch if slot has been captured
    if (snapshot.capturedAt === 0) {
      return null;
    }

    this.state = { ...this.state, activeSlot: slot };
    this.emit();

    return snapshot;
  }

  /**
   * Toggle between A and B slots.
   * Returns the new active snapshot or null if target slot is empty.
   */
  toggleSlot(): MasterSnapshot | null {
    const targetSlot: SnapshotSlot = this.state.activeSlot === 'A' ? 'B' : 'A';
    return this.switchToSlot(targetSlot);
  }

  /**
   * Clear a specific slot.
   */
  clearSlot(slot: SnapshotSlot): void {
    const emptySnapshot = createEmptySnapshot();

    if (slot === 'A') {
      this.state = { ...this.state, slotA: emptySnapshot };
    } else {
      this.state = { ...this.state, slotB: emptySnapshot };
    }

    // If clearing active slot, switch to other if available
    if (this.state.activeSlot === slot) {
      const otherSlot: SnapshotSlot = slot === 'A' ? 'B' : 'A';
      const otherSnapshot = this.getSnapshot(otherSlot);
      if (otherSnapshot.capturedAt > 0) {
        this.state = { ...this.state, activeSlot: otherSlot };
      }
    }

    this.emit();
  }

  /**
   * Reset entire A/B state.
   */
  reset(): void {
    this.state = createDefaultABState();
    this.emit();
  }

  /**
   * Initialize with current chain as slot A.
   * Typically called when opening mixer or on project load.
   */
  initializeWithChain(chain: MasterInsertChain, pdcEnabled: boolean): void {
    // Only initialize if not already captured
    if (this.state.slotA.capturedAt === 0) {
      this.captureToSlot('A', chain, pdcEnabled);
    }
  }

  /**
   * Subscribe to state changes.
   */
  subscribe(listener: ABStateListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /**
   * Notify all listeners of state change.
   */
  private emit(): void {
    for (const listener of this.listeners) {
      listener(this.state);
    }
  }
}

// ============ Singleton Instance ============

/**
 * Singleton instance of A/B snapshot manager.
 */
export const masterABSnapshot = new MasterABSnapshotManager();

// ============ Convenience Functions ============

/**
 * Capture current chain to slot A.
 */
export function captureToA(
  chain: MasterInsertChain,
  pdcEnabled: boolean
): void {
  masterABSnapshot.captureToSlot('A', chain, pdcEnabled);
}

/**
 * Capture current chain to slot B.
 */
export function captureToB(
  chain: MasterInsertChain,
  pdcEnabled: boolean
): void {
  masterABSnapshot.captureToSlot('B', chain, pdcEnabled);
}

/**
 * Switch to slot A.
 * Returns snapshot or null if slot is empty.
 */
export function switchToA(): MasterSnapshot | null {
  return masterABSnapshot.switchToSlot('A');
}

/**
 * Switch to slot B.
 * Returns snapshot or null if slot is empty.
 */
export function switchToB(): MasterSnapshot | null {
  return masterABSnapshot.switchToSlot('B');
}

/**
 * Toggle between A and B.
 * Returns new snapshot or null if target is empty.
 */
export function toggleAB(): MasterSnapshot | null {
  return masterABSnapshot.toggleSlot();
}

/**
 * Get current active slot.
 */
export function getActiveSlot(): SnapshotSlot {
  return masterABSnapshot.getActiveSlot();
}

/**
 * Check if slot A has a capture.
 */
export function hasSlotA(): boolean {
  return masterABSnapshot.hasCapture('A');
}

/**
 * Check if slot B has a capture.
 */
export function hasSlotB(): boolean {
  return masterABSnapshot.hasCapture('B');
}

/**
 * Check if A/B comparison is available (both slots captured).
 */
export function canCompareAB(): boolean {
  return hasSlotA() && hasSlotB();
}
