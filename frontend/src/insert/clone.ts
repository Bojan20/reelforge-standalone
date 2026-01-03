/**
 * ReelForge M9.1 Insert Clone Utilities
 *
 * Deep clone helpers for insert chain data structures.
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 *
 * @module insert/clone
 */

import type { InsertChain, Insert } from './types';
import type { VanEqInsert, VanCompInsert, VanLimitInsert } from '../core/masterInsertTypes';
import { generateInsertId } from './types';

/**
 * Deep clone an insert chain.
 * Creates a fully independent copy of the chain.
 *
 * @param chain - The chain to clone
 * @returns A deep copy of the chain
 */
export function cloneChain(chain: InsertChain): InsertChain {
  return {
    inserts: chain.inserts.map(cloneInsert),
  };
}

/**
 * Deep clone an insert.
 * Creates a fully independent copy of the insert.
 *
 * @param insert - The insert to clone
 * @returns A deep copy of the insert
 */
export function cloneInsert(insert: Insert): Insert {
  switch (insert.pluginId) {
    case 'vaneq':
      return cloneVanEqInsert(insert as VanEqInsert);
    case 'vancomp':
      return cloneVanCompInsert(insert as VanCompInsert);
    case 'vanlimit':
      return cloneVanLimitInsert(insert as VanLimitInsert);
  }
}

/**
 * Deep clone an insert with a new ID.
 * Used when pasting/duplicating inserts.
 *
 * @param insert - The insert to clone
 * @returns A deep copy with a new unique ID
 */
export function cloneInsertWithNewId(insert: Insert): Insert {
  const cloned = cloneInsert(insert);
  return { ...cloned, id: generateInsertId() };
}

/**
 * Deep clone a chain with all new IDs.
 * Used when pasting/duplicating chains.
 *
 * @param chain - The chain to clone
 * @returns A deep copy with all new unique IDs
 */
export function cloneChainWithNewIds(chain: InsertChain): InsertChain {
  return {
    inserts: chain.inserts.map(cloneInsertWithNewId),
  };
}

// ============ Private Clone Functions ============

function cloneVanEqInsert(insert: VanEqInsert): VanEqInsert {
  return {
    id: insert.id,
    pluginId: 'vaneq',
    enabled: insert.enabled,
    params: { ...insert.params },
  };
}

function cloneVanCompInsert(insert: VanCompInsert): VanCompInsert {
  return {
    id: insert.id,
    pluginId: 'vancomp',
    enabled: insert.enabled,
    params: { ...insert.params },
  };
}

function cloneVanLimitInsert(insert: VanLimitInsert): VanLimitInsert {
  return {
    id: insert.id,
    pluginId: 'vanlimit',
    enabled: insert.enabled,
    params: { ...insert.params },
  };
}

/**
 * Check if two chains are equal (deep comparison).
 * Useful for A/B comparisons and change detection.
 *
 * @param a - First chain
 * @param b - Second chain
 * @returns True if chains are deeply equal
 */
export function chainsEqual(a: InsertChain, b: InsertChain): boolean {
  if (a.inserts.length !== b.inserts.length) return false;

  for (let i = 0; i < a.inserts.length; i++) {
    if (!insertsEqual(a.inserts[i], b.inserts[i])) return false;
  }

  return true;
}

/**
 * Check if two inserts are equal (deep comparison).
 *
 * @param a - First insert
 * @param b - Second insert
 * @returns True if inserts are deeply equal
 */
export function insertsEqual(a: Insert, b: Insert): boolean {
  if (a.id !== b.id) return false;
  if (a.pluginId !== b.pluginId) return false;
  if (a.enabled !== b.enabled) return false;

  return flatParamsEqual(
    a.params as Record<string, number>,
    b.params as Record<string, number>
  );
}

function flatParamsEqual(
  a: Record<string, number>,
  b: Record<string, number>
): boolean {
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  for (const key of keysA) {
    if (a[key] !== b[key]) return false;
  }
  return true;
}
