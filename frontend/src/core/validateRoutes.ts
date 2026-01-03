/**
 * ReelForge M6.7 Routes Validation
 *
 * Strict validation matching C++ RuntimeCore behavior.
 * All validation rules must match routes.cpp exactly.
 */

import type {
  RoutesConfig,
  EventRoute,
  RouteAction,
  RouteValidationError,
  RouteValidationResult,
  RouteBus,
  RouteActionType,
} from './routesTypes';
import {
  ROUTE_BUSES,
  ROUTE_ACTION_TYPES,
} from './routesTypes';

// Re-export types for consumers
export type { RouteValidationError, RouteValidationResult } from './routesTypes';

/**
 * Validate a complete routes configuration.
 *
 * @param config Routes configuration to validate
 * @param assetIds Optional set of valid asset IDs for Play action validation
 * @returns Validation result with errors and warnings
 */
export function validateRoutes(
  config: RoutesConfig,
  assetIds?: Set<string>
): RouteValidationResult {
  const errors: RouteValidationError[] = [];
  const warnings: RouteValidationError[] = [];

  // Validate routesVersion
  if (config.routesVersion !== 1) {
    errors.push({
      type: 'error',
      message: `Invalid routesVersion: ${config.routesVersion}. Must be 1.`,
      field: 'routesVersion',
    });
  }

  // Validate defaultBus
  if (!isValidBus(config.defaultBus)) {
    errors.push({
      type: 'error',
      message: `Invalid defaultBus: "${config.defaultBus}". Must be one of: ${ROUTE_BUSES.join(', ')}`,
      field: 'defaultBus',
    });
  }

  // Validate events array
  if (!Array.isArray(config.events)) {
    errors.push({
      type: 'error',
      message: 'events must be an array',
      field: 'events',
    });
    return { valid: false, errors, warnings };
  }

  // Track event names for duplicate detection
  const seenEventNames = new Set<string>();

  // Validate each event
  config.events.forEach((event, eventIndex) => {
    const eventErrors = validateEventRoute(
      event,
      eventIndex,
      config.defaultBus,
      assetIds,
      seenEventNames
    );
    errors.push(...eventErrors.errors);
    warnings.push(...eventErrors.warnings);
    seenEventNames.add(event.name);
  });

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Validate a single event route.
 */
function validateEventRoute(
  event: EventRoute,
  eventIndex: number,
  defaultBus: RouteBus,
  assetIds?: Set<string>,
  seenEventNames?: Set<string>
): { errors: RouteValidationError[]; warnings: RouteValidationError[] } {
  const errors: RouteValidationError[] = [];
  const warnings: RouteValidationError[] = [];

  // Validate event name
  if (!event.name || typeof event.name !== 'string') {
    errors.push({
      type: 'error',
      message: 'Event name is required and must be a string',
      eventIndex,
      field: 'name',
    });
  } else {
    // Check for empty name
    if (event.name.trim() === '') {
      errors.push({
        type: 'error',
        message: 'Event name cannot be empty',
        eventName: event.name,
        eventIndex,
        field: 'name',
      });
    }

    // Check for duplicate event names
    if (seenEventNames?.has(event.name)) {
      errors.push({
        type: 'error',
        message: `Duplicate event name: "${event.name}"`,
        eventName: event.name,
        eventIndex,
        field: 'name',
      });
    }

    // Warn about non-standard naming conventions
    if (event.name && !event.name.startsWith('on')) {
      warnings.push({
        type: 'warning',
        message: `Event name "${event.name}" doesn't follow convention (should start with "on")`,
        eventName: event.name,
        eventIndex,
        field: 'name',
      });
    }
  }

  // Validate actions array
  if (!Array.isArray(event.actions)) {
    errors.push({
      type: 'error',
      message: 'Event actions must be an array',
      eventName: event.name,
      eventIndex,
      field: 'actions',
    });
    return { errors, warnings };
  }

  // Warn about empty actions
  if (event.actions.length === 0) {
    warnings.push({
      type: 'warning',
      message: 'Event has no actions',
      eventName: event.name,
      eventIndex,
      field: 'actions',
    });
  }

  // Validate each action
  event.actions.forEach((action, actionIndex) => {
    const actionErrors = validateAction(
      action,
      event.name,
      eventIndex,
      actionIndex,
      defaultBus,
      assetIds
    );
    errors.push(...actionErrors.errors);
    warnings.push(...actionErrors.warnings);
  });

  return { errors, warnings };
}

/**
 * Validate a single action.
 */
function validateAction(
  action: RouteAction,
  eventName: string,
  eventIndex: number,
  actionIndex: number,
  defaultBus: RouteBus,
  assetIds?: Set<string>
): { errors: RouteValidationError[]; warnings: RouteValidationError[] } {
  const errors: RouteValidationError[] = [];
  const warnings: RouteValidationError[] = [];

  // Validate action type
  if (!action.type || !isValidActionType(action.type)) {
    errors.push({
      type: 'error',
      message: `Invalid action type: "${action.type}". Must be one of: ${ROUTE_ACTION_TYPES.join(', ')}`,
      eventName,
      eventIndex,
      actionIndex,
      field: 'type',
    });
    return { errors, warnings };
  }

  // Type-specific validation
  switch (action.type) {
    case 'Play':
      validatePlayAction(action, eventName, eventIndex, actionIndex, defaultBus, assetIds, errors, warnings);
      break;
    case 'Stop':
      // Stop actions are valid with no additional fields in routes file
      // voiceId is runtime-only
      break;
    case 'StopAll':
      // StopAll has no additional fields
      break;
    case 'SetBusGain':
      validateSetBusGainAction(action, eventName, eventIndex, actionIndex, errors, warnings);
      break;
  }

  return { errors, warnings };
}

/**
 * Validate a Play action.
 */
function validatePlayAction(
  action: RouteAction & { type: 'Play' },
  eventName: string,
  eventIndex: number,
  actionIndex: number,
  _defaultBus: RouteBus,
  assetIds: Set<string> | undefined,
  errors: RouteValidationError[],
  _warnings: RouteValidationError[]
): void {
  // Validate assetId (required)
  if (!action.assetId || typeof action.assetId !== 'string' || action.assetId.trim() === '') {
    errors.push({
      type: 'error',
      message: 'Play action requires a non-empty assetId',
      eventName,
      eventIndex,
      actionIndex,
      field: 'assetId',
    });
  } else if (assetIds && !assetIds.has(action.assetId)) {
    errors.push({
      type: 'error',
      message: `Unknown assetId: "${action.assetId}"`,
      eventName,
      eventIndex,
      actionIndex,
      field: 'assetId',
    });
  }

  // Validate bus (optional, uses defaultBus if not specified)
  if (action.bus !== undefined) {
    if (!isValidBus(action.bus)) {
      errors.push({
        type: 'error',
        message: `Invalid bus: "${action.bus}". Must be one of: ${ROUTE_BUSES.join(', ')}`,
        eventName,
        eventIndex,
        actionIndex,
        field: 'bus',
      });
    }
  }

  // Validate gain (optional, defaults to 1.0)
  if (action.gain !== undefined) {
    if (typeof action.gain !== 'number' || isNaN(action.gain)) {
      errors.push({
        type: 'error',
        message: 'gain must be a number',
        eventName,
        eventIndex,
        actionIndex,
        field: 'gain',
      });
    } else if (action.gain < 0 || action.gain > 1) {
      errors.push({
        type: 'error',
        message: `gain must be between 0.0 and 1.0, got ${action.gain}`,
        eventName,
        eventIndex,
        actionIndex,
        field: 'gain',
      });
    }
  }

  // Validate loop (optional, defaults to false)
  if (action.loop !== undefined && typeof action.loop !== 'boolean') {
    errors.push({
      type: 'error',
      message: 'loop must be a boolean',
      eventName,
      eventIndex,
      actionIndex,
      field: 'loop',
    });
  }
}

/**
 * Validate a SetBusGain action.
 */
function validateSetBusGainAction(
  action: RouteAction & { type: 'SetBusGain' },
  eventName: string,
  eventIndex: number,
  actionIndex: number,
  errors: RouteValidationError[],
  _warnings: RouteValidationError[]
): void {
  // Validate bus (required)
  if (!action.bus || typeof action.bus !== 'string') {
    errors.push({
      type: 'error',
      message: 'SetBusGain action requires a bus',
      eventName,
      eventIndex,
      actionIndex,
      field: 'bus',
    });
  } else if (!isValidBus(action.bus)) {
    errors.push({
      type: 'error',
      message: `Invalid bus: "${action.bus}". Must be one of: ${ROUTE_BUSES.join(', ')}`,
      eventName,
      eventIndex,
      actionIndex,
      field: 'bus',
    });
  }

  // Validate gain (required)
  if (action.gain === undefined || action.gain === null) {
    errors.push({
      type: 'error',
      message: 'SetBusGain action requires a gain value',
      eventName,
      eventIndex,
      actionIndex,
      field: 'gain',
    });
  } else if (typeof action.gain !== 'number' || isNaN(action.gain)) {
    errors.push({
      type: 'error',
      message: 'gain must be a number',
      eventName,
      eventIndex,
      actionIndex,
      field: 'gain',
    });
  } else if (action.gain < 0 || action.gain > 1) {
    errors.push({
      type: 'error',
      message: `gain must be between 0.0 and 1.0, got ${action.gain}`,
      eventName,
      eventIndex,
      actionIndex,
      field: 'gain',
    });
  }
}

/**
 * Check if a bus name is valid.
 */
function isValidBus(bus: string): bus is RouteBus {
  return ROUTE_BUSES.includes(bus as RouteBus);
}

/**
 * Check if an action type is valid.
 */
function isValidActionType(type: string): type is RouteActionType {
  return ROUTE_ACTION_TYPES.includes(type as RouteActionType);
}

/**
 * Parse a JSON string into a RoutesConfig with validation.
 *
 * @param json JSON string to parse
 * @param assetIds Optional set of valid asset IDs
 * @returns Parsed config and validation result
 */
export function parseRoutesJson(
  json: string,
  assetIds?: Set<string>
): { config: RoutesConfig | null; validation: RouteValidationResult } {
  let parsed: unknown;

  try {
    parsed = JSON.parse(json);
  } catch (e) {
    const error = e as Error;
    return {
      config: null,
      validation: {
        valid: false,
        errors: [
          {
            type: 'error',
            message: `Invalid JSON: ${error.message}`,
          },
        ],
        warnings: [],
      },
    };
  }

  // Basic type check
  if (!parsed || typeof parsed !== 'object') {
    return {
      config: null,
      validation: {
        valid: false,
        errors: [
          {
            type: 'error',
            message: 'Routes config must be an object',
          },
        ],
        warnings: [],
      },
    };
  }

  const config = parsed as RoutesConfig;
  const validation = validateRoutes(config, assetIds);

  return {
    config: validation.valid ? config : null,
    validation,
  };
}

/**
 * Serialize a routes config to JSON string with pretty formatting.
 */
export function stringifyRoutes(config: RoutesConfig): string {
  return JSON.stringify(config, null, 2);
}

/**
 * Get a human-readable error location string.
 */
export function formatErrorLocation(error: RouteValidationError): string {
  const parts: string[] = [];

  if (error.eventName) {
    parts.push(`event "${error.eventName}"`);
  } else if (error.eventIndex !== undefined) {
    parts.push(`event[${error.eventIndex}]`);
  }

  if (error.actionIndex !== undefined) {
    parts.push(`action[${error.actionIndex}]`);
  }

  if (error.field) {
    parts.push(error.field);
  }

  return parts.length > 0 ? parts.join(' > ') : 'root';
}
