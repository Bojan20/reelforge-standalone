/**
 * ReelForge M8.0 Master Insert Validation
 *
 * Strict validation for master insert chain.
 * Hard-fail on invalid config (RF_ERR style).
 */

import type {
  MasterInsertChain,
  MasterInsert,
  PluginId,
  VanEqInsert,
} from './masterInsertTypes';
import {
  VALID_PLUGIN_IDS,
} from './masterInsertTypes';
import { VANEQ_CONSTRAINTS } from '../plugin/vaneqTypes';

export interface InsertValidationError {
  type: 'error';
  message: string;
  field?: string;
  insertId?: string;
}

export interface InsertValidationResult {
  valid: boolean;
  errors: InsertValidationError[];
}

/**
 * Validate master insert chain.
 * Returns errors array - empty means valid.
 */
export function validateMasterInsertChain(
  chain: unknown
): InsertValidationResult {
  const errors: InsertValidationError[] = [];

  if (!chain || typeof chain !== 'object') {
    errors.push({
      type: 'error',
      message: 'masterInsertChain must be an object',
    });
    return { valid: false, errors };
  }

  const c = chain as Record<string, unknown>;

  if (!('inserts' in c)) {
    errors.push({
      type: 'error',
      message: 'masterInsertChain.inserts is required',
      field: 'inserts',
    });
    return { valid: false, errors };
  }

  if (!Array.isArray(c.inserts)) {
    errors.push({
      type: 'error',
      message: 'masterInsertChain.inserts must be an array',
      field: 'inserts',
    });
    return { valid: false, errors };
  }

  // Validate each insert
  const seenIds = new Set<string>();

  c.inserts.forEach((insert, index) => {
    const insertErrors = validateInsert(insert, index, seenIds);
    errors.push(...insertErrors);
  });

  return {
    valid: errors.length === 0,
    errors,
  };
}

function validateInsert(
  insert: unknown,
  index: number,
  seenIds: Set<string>
): InsertValidationError[] {
  const errors: InsertValidationError[] = [];
  const prefix = `inserts[${index}]`;

  if (!insert || typeof insert !== 'object') {
    errors.push({
      type: 'error',
      message: `${prefix} must be an object`,
      field: prefix,
    });
    return errors;
  }

  const ins = insert as Record<string, unknown>;

  // Validate ID
  if (typeof ins.id !== 'string' || ins.id.trim() === '') {
    errors.push({
      type: 'error',
      message: `${prefix}.id must be a non-empty string`,
      field: `${prefix}.id`,
    });
  } else if (seenIds.has(ins.id)) {
    errors.push({
      type: 'error',
      message: `${prefix}.id '${ins.id}' is duplicate`,
      field: `${prefix}.id`,
      insertId: ins.id as string,
    });
  } else {
    seenIds.add(ins.id as string);
  }

  // Validate pluginId
  if (!VALID_PLUGIN_IDS.includes(ins.pluginId as PluginId)) {
    errors.push({
      type: 'error',
      message: `${prefix}.pluginId must be one of: ${VALID_PLUGIN_IDS.join(', ')}`,
      field: `${prefix}.pluginId`,
      insertId: ins.id as string,
    });
    return errors; // Can't validate params without valid pluginId
  }

  // Validate enabled
  if (typeof ins.enabled !== 'boolean') {
    errors.push({
      type: 'error',
      message: `${prefix}.enabled must be a boolean`,
      field: `${prefix}.enabled`,
      insertId: ins.id as string,
    });
  }

  // Validate params based on pluginId
  if (!ins.params || typeof ins.params !== 'object') {
    errors.push({
      type: 'error',
      message: `${prefix}.params is required`,
      field: `${prefix}.params`,
      insertId: ins.id as string,
    });
    return errors;
  }

  // Van* plugins use flat params - basic validation only
  // Detailed validation happens via plugin descriptors at runtime
  switch (ins.pluginId) {
    case 'vaneq':
    case 'vancomp':
    case 'vanlimit':
      // Flat params format - just verify it's an object (already done above)
      break;
  }

  return errors;
}

// ============ Param Clamping ============

/**
 * Clamp insert parameters to valid ranges.
 * Used when loading to fix minor out-of-range values.
 */
export function clampInsertParams(insert: MasterInsert): MasterInsert {
  switch (insert.pluginId) {
    case 'vaneq':
      return clampVanEqInsert(insert);
    case 'vancomp':
    case 'vanlimit':
      // VanComp and VanLimit use flat params, clamping handled by descriptors
      return insert;
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function clampVanEqInsert(insert: VanEqInsert): VanEqInsert {
  const c = VANEQ_CONSTRAINTS;
  const params = { ...insert.params };

  // Clamp output gain
  if (typeof params.outputGainDb === 'number') {
    params.outputGainDb = clamp(params.outputGainDb, c.outputGainDb.min, c.outputGainDb.max);
  }

  // Clamp each band's params
  for (let i = 0; i < 6; i++) {
    const freqKey = `band${i}_freqHz`;
    const gainKey = `band${i}_gainDb`;
    const qKey = `band${i}_q`;

    if (typeof params[freqKey] === 'number') {
      params[freqKey] = clamp(params[freqKey], c.freqHz.min, c.freqHz.max);
    }
    if (typeof params[gainKey] === 'number') {
      params[gainKey] = clamp(params[gainKey], c.gainDb.min, c.gainDb.max);
    }
    if (typeof params[qKey] === 'number') {
      params[qKey] = clamp(params[qKey], c.q.min, c.q.max);
    }
  }

  return {
    ...insert,
    params,
  };
}

/**
 * Clamp all inserts in a chain.
 */
export function clampChainParams(chain: MasterInsertChain): MasterInsertChain {
  return {
    inserts: chain.inserts.map(clampInsertParams),
  };
}
