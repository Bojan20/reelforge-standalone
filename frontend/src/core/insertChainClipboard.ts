/**
 * ReelForge M8.3 Insert Chain Clipboard & Utilities
 *
 * Provides copy/paste functionality for insert chains and individual inserts.
 * All operations create deep copies with regenerated IDs.
 */

import type {
  Insert,
  InsertChain,
  PluginId,
} from './masterInsertTypes';
import {
  generateInsertId,
} from './masterInsertTypes';
import {
  DEFAULT_VANEQ_PARAMS,
  flattenVanEqParams,
} from '../plugin/vaneqTypes';
import { getVanCompDefaultParams } from '../plugin/vancomp-pro/vancompDescriptors';
import { getVanLimitDefaultParams } from '../plugin/vanlimit-pro/vanlimitDescriptors';

// ============ Clone Utilities ============

/**
 * Deep clone an insert with a new unique ID.
 * Preserves all params exactly.
 */
export function cloneInsert(insert: Insert): Insert {
  const newId = generateInsertId();

  switch (insert.pluginId) {
    case 'vaneq':
      return {
        id: newId,
        pluginId: 'vaneq',
        enabled: insert.enabled,
        params: { ...(insert.params as Record<string, number>) },
      };
    case 'vancomp':
      return {
        id: newId,
        pluginId: 'vancomp',
        enabled: insert.enabled,
        params: { ...(insert.params as Record<string, number>) },
      };
    case 'vanlimit':
      return {
        id: newId,
        pluginId: 'vanlimit',
        enabled: insert.enabled,
        params: { ...(insert.params as Record<string, number>) },
      };
  }
}

/**
 * Deep clone an entire insert chain with all new IDs.
 * Order is preserved exactly.
 */
export function cloneChain(chain: InsertChain): InsertChain {
  return {
    inserts: chain.inserts.map(cloneInsert),
  };
}

/**
 * Regenerate all IDs in a chain (mutates in place for efficiency).
 * Returns the same chain reference with new IDs.
 */
export function regenerateChainIds(chain: InsertChain): InsertChain {
  for (const insert of chain.inserts) {
    (insert as { id: string }).id = generateInsertId();
  }
  return chain;
}

// ============ Default Parameter Getters ============

/**
 * Get default params for a plugin type.
 */
export function getDefaultParams(pluginId: PluginId): Insert['params'] {
  switch (pluginId) {
    case 'vaneq':
      return flattenVanEqParams(structuredClone(DEFAULT_VANEQ_PARAMS));
    case 'vancomp':
      return getVanCompDefaultParams();
    case 'vanlimit':
      return getVanLimitDefaultParams();
  }
}

// ============ Clipboard Types ============

/** Type of content in clipboard */
export type ClipboardContentType = 'chain' | 'insert';

/** Clipboard content for a full chain */
export interface ChainClipboardContent {
  type: 'chain';
  /** Source identifier (for UI hints) */
  source: 'master' | string; // string for bus ID
  /** The copied chain data */
  chain: InsertChain;
  /** Timestamp of copy */
  timestamp: number;
}

/** Clipboard content for a single insert */
export interface InsertClipboardContent {
  type: 'insert';
  /** Source identifier */
  source: 'master' | string;
  /** The copied insert data */
  insert: Insert;
  /** Timestamp of copy */
  timestamp: number;
}

/** Union of clipboard content types */
export type ClipboardContent = ChainClipboardContent | InsertClipboardContent;

// ============ Clipboard State ============

/** In-memory clipboard state (session-only) */
let clipboardContent: ClipboardContent | null = null;

/**
 * Copy a full chain to clipboard.
 */
export function copyChainToClipboard(
  chain: InsertChain,
  source: 'master' | string
): void {
  clipboardContent = {
    type: 'chain',
    source,
    chain: cloneChain(chain),
    timestamp: Date.now(),
  };
}

/**
 * Copy a single insert to clipboard.
 */
export function copyInsertToClipboard(
  insert: Insert,
  source: 'master' | string
): void {
  clipboardContent = {
    type: 'insert',
    source,
    insert: cloneInsert(insert),
    timestamp: Date.now(),
  };
}

/**
 * Get current clipboard content (or null if empty).
 */
export function getClipboardContent(): ClipboardContent | null {
  return clipboardContent;
}

/**
 * Check if clipboard has a chain.
 */
export function hasChainInClipboard(): boolean {
  return clipboardContent?.type === 'chain';
}

/**
 * Check if clipboard has an insert.
 */
export function hasInsertInClipboard(): boolean {
  return clipboardContent?.type === 'insert';
}

/**
 * Check if clipboard has any content.
 */
export function hasClipboardContent(): boolean {
  return clipboardContent !== null;
}

/**
 * Paste chain from clipboard (creates new copy with new IDs).
 * Returns null if clipboard is empty or wrong type.
 */
export function pasteChainFromClipboard(): InsertChain | null {
  if (clipboardContent?.type !== 'chain') {
    return null;
  }
  // Always create a fresh clone with new IDs
  return cloneChain(clipboardContent.chain);
}

/**
 * Paste insert from clipboard (creates new copy with new ID).
 * Returns null if clipboard is empty or wrong type.
 */
export function pasteInsertFromClipboard(): Insert | null {
  if (clipboardContent?.type !== 'insert') {
    return null;
  }
  // Always create a fresh clone with new ID
  return cloneInsert(clipboardContent.insert);
}

/**
 * Clear clipboard.
 */
export function clearClipboard(): void {
  clipboardContent = null;
}

/**
 * Get clipboard source hint (for UI).
 */
export function getClipboardSourceHint(): string | null {
  if (!clipboardContent) return null;
  return clipboardContent.source === 'master'
    ? 'Master'
    : clipboardContent.source.toUpperCase();
}
