/**
 * ReelForge M8.0 Project File Validation
 *
 * Strict validation for project files.
 * Validates structure, paths, embedded routes, and master insert chain.
 */

import type {
  ProjectFileV1,
  ProjectValidationResult,
  ProjectValidationError,
} from './projectTypes';
import { CURRENT_PROJECT_VERSION } from './projectTypes';
import type { RoutesConfig } from '../core/routesTypes';
import { validateRoutes } from '../core/validateRoutes';
import { validateMasterInsertChain } from '../core/validateMasterInserts';

/**
 * Context for validation that includes asset IDs from manifest.
 */
interface ValidationContext {
  assetIds?: Set<string>;
}

/**
 * Validate a project file.
 *
 * @param project The project file to validate (unknown type for raw JSON)
 * @param assetIds Optional set of valid asset IDs for routes validation
 * @returns Validation result with errors and warnings
 */
export function validateProjectFile(
  project: unknown,
  assetIds?: Set<string>
): ProjectValidationResult {
  const context: ValidationContext = { assetIds };
  const errors: ProjectValidationError[] = [];
  const warnings: ProjectValidationError[] = [];

  // Check if project is an object
  if (!project || typeof project !== 'object') {
    errors.push({
      type: 'error',
      message: 'Project file must be a JSON object',
    });
    return { valid: false, errors, warnings };
  }

  const p = project as Record<string, unknown>;

  // Validate projectVersion
  if (!('projectVersion' in p)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: projectVersion',
      field: 'projectVersion',
    });
  } else if (typeof p.projectVersion !== 'number') {
    errors.push({
      type: 'error',
      message: 'projectVersion must be a number',
      field: 'projectVersion',
    });
  } else if (p.projectVersion !== CURRENT_PROJECT_VERSION) {
    errors.push({
      type: 'error',
      message: `Unsupported projectVersion: ${p.projectVersion}. Expected ${CURRENT_PROJECT_VERSION}`,
      field: 'projectVersion',
    });
  }

  // Validate name
  if (!('name' in p)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: name',
      field: 'name',
    });
  } else if (typeof p.name !== 'string') {
    errors.push({
      type: 'error',
      message: 'name must be a string',
      field: 'name',
    });
  } else if (p.name.trim() === '') {
    errors.push({
      type: 'error',
      message: 'name cannot be empty',
      field: 'name',
    });
  }

  // Validate timestamps
  validateTimestamp(p, 'createdAt', errors);
  validateTimestamp(p, 'updatedAt', errors);

  // Validate paths
  if (!('paths' in p)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: paths',
      field: 'paths',
    });
  } else if (!p.paths || typeof p.paths !== 'object') {
    errors.push({
      type: 'error',
      message: 'paths must be an object',
      field: 'paths',
    });
  } else {
    validatePaths(p.paths as Record<string, unknown>, errors);
  }

  // Validate routes
  if (!('routes' in p)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: routes',
      field: 'routes',
    });
  } else if (!p.routes || typeof p.routes !== 'object') {
    errors.push({
      type: 'error',
      message: 'routes must be an object',
      field: 'routes',
    });
  } else {
    validateRoutesConfig(
      p.routes as Record<string, unknown>,
      p.paths as Record<string, unknown> | undefined,
      assetIds,
      errors,
      warnings
    );
  }

  // Validate studio (optional)
  if ('studio' in p && p.studio !== undefined) {
    if (typeof p.studio !== 'object' || p.studio === null) {
      errors.push({
        type: 'error',
        message: 'studio must be an object if provided',
        field: 'studio',
      });
    } else {
      validateStudio(p.studio as Record<string, unknown>, context, errors, warnings);
    }
  }

  return {
    valid: errors.length === 0,
    errors,
    warnings,
  };
}

/**
 * Validate a timestamp field.
 */
function validateTimestamp(
  obj: Record<string, unknown>,
  field: string,
  errors: ProjectValidationError[]
): void {
  if (!(field in obj)) {
    errors.push({
      type: 'error',
      message: `Missing required field: ${field}`,
      field,
    });
  } else if (typeof obj[field] !== 'string') {
    errors.push({
      type: 'error',
      message: `${field} must be a string`,
      field,
    });
  } else {
    // Validate ISO 8601 format
    const date = new Date(obj[field] as string);
    if (isNaN(date.getTime())) {
      errors.push({
        type: 'error',
        message: `${field} must be a valid ISO 8601 date`,
        field,
      });
    }
  }
}

/**
 * Validate paths configuration.
 */
function validatePaths(
  paths: Record<string, unknown>,
  errors: ProjectValidationError[]
): void {
  // manifestPath is required
  if (!('manifestPath' in paths)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: paths.manifestPath',
      field: 'paths.manifestPath',
    });
  } else if (typeof paths.manifestPath !== 'string') {
    errors.push({
      type: 'error',
      message: 'paths.manifestPath must be a string',
      field: 'paths.manifestPath',
    });
  } else if ((paths.manifestPath as string).trim() === '') {
    errors.push({
      type: 'error',
      message: 'paths.manifestPath cannot be empty',
      field: 'paths.manifestPath',
    });
  }

  // routesPath is optional but must be string if present
  if ('routesPath' in paths && paths.routesPath !== undefined) {
    if (typeof paths.routesPath !== 'string') {
      errors.push({
        type: 'error',
        message: 'paths.routesPath must be a string if provided',
        field: 'paths.routesPath',
      });
    }
  }
}

/**
 * Validate routes configuration.
 */
function validateRoutesConfig(
  routes: Record<string, unknown>,
  paths: Record<string, unknown> | undefined,
  assetIds: Set<string> | undefined,
  errors: ProjectValidationError[],
  warnings: ProjectValidationError[]
): void {
  // embed is required
  if (!('embed' in routes)) {
    errors.push({
      type: 'error',
      message: 'Missing required field: routes.embed',
      field: 'routes.embed',
    });
    return;
  }

  if (typeof routes.embed !== 'boolean') {
    errors.push({
      type: 'error',
      message: 'routes.embed must be a boolean',
      field: 'routes.embed',
    });
    return;
  }

  if (routes.embed === true) {
    // Embedded mode: data is required
    if (!('data' in routes) || routes.data === undefined) {
      errors.push({
        type: 'error',
        message: 'routes.data is required when routes.embed is true',
        field: 'routes.data',
      });
    } else if (typeof routes.data !== 'object' || routes.data === null) {
      errors.push({
        type: 'error',
        message: 'routes.data must be an object',
        field: 'routes.data',
      });
    } else {
      // Validate embedded routes using existing validator
      // Cast to RoutesConfig - validateRoutes will catch any schema issues
      const routesResult = validateRoutes(routes.data as unknown as RoutesConfig, assetIds);

      // Prefix errors with routes.data
      for (const err of routesResult.errors) {
        errors.push({
          type: 'error',
          message: `routes.data: ${err.message}`,
          field: err.field ? `routes.data.${err.field}` : 'routes.data',
        });
      }
      for (const warn of routesResult.warnings) {
        warnings.push({
          type: 'warning',
          message: `routes.data: ${warn.message}`,
          field: warn.field ? `routes.data.${warn.field}` : 'routes.data',
        });
      }
    }
  } else {
    // External mode: routesPath is required
    if (!paths || !('routesPath' in paths) || !paths.routesPath) {
      errors.push({
        type: 'error',
        message: 'paths.routesPath is required when routes.embed is false',
        field: 'paths.routesPath',
      });
    }
  }
}

/**
 * Validate studio preferences.
 */
function validateStudio(
  studio: Record<string, unknown>,
  context: ValidationContext,
  errors: ProjectValidationError[],
  warnings: ProjectValidationError[]
): void {
  // selectedTab validation
  if ('selectedTab' in studio && studio.selectedTab !== undefined) {
    const validTabs = ['Monitor', 'Routes'];
    if (typeof studio.selectedTab !== 'string' || !validTabs.includes(studio.selectedTab)) {
      warnings.push({
        type: 'warning',
        message: `Invalid studio.selectedTab: "${studio.selectedTab}". Using default.`,
        field: 'studio.selectedTab',
      });
    }
  }

  // routesUi validation
  if ('routesUi' in studio && studio.routesUi !== undefined) {
    if (typeof studio.routesUi !== 'object' || studio.routesUi === null) {
      warnings.push({
        type: 'warning',
        message: 'studio.routesUi should be an object. Using default.',
        field: 'studio.routesUi',
      });
    }
  }

  // masterInsertChain validation (hard-fail on errors)
  if ('masterInsertChain' in studio && studio.masterInsertChain !== undefined) {
    const chainResult = validateMasterInsertChain(studio.masterInsertChain);
    if (!chainResult.valid) {
      for (const err of chainResult.errors) {
        errors.push({
          type: 'error',
          message: `studio.masterInsertChain: ${err.message}`,
          field: err.field ? `studio.masterInsertChain.${err.field}` : 'studio.masterInsertChain',
        });
      }
    }
  }

  // pdcEnabled validation (hard-fail on invalid type)
  if ('pdcEnabled' in studio && studio.pdcEnabled !== undefined) {
    if (typeof studio.pdcEnabled !== 'boolean') {
      errors.push({
        type: 'error',
        message: `studio.pdcEnabled must be a boolean, got ${typeof studio.pdcEnabled}`,
        field: 'studio.pdcEnabled',
      });
    }
  }

  // busInsertChains validation (hard-fail on errors)
  if ('busInsertChains' in studio && studio.busInsertChains !== undefined) {
    if (typeof studio.busInsertChains !== 'object' || studio.busInsertChains === null) {
      errors.push({
        type: 'error',
        message: 'studio.busInsertChains must be an object',
        field: 'studio.busInsertChains',
      });
    } else {
      validateBusInsertChains(
        studio.busInsertChains as Record<string, unknown>,
        errors
      );
    }
  }

  // busPdcEnabled validation (hard-fail on invalid type or unknown busId)
  if ('busPdcEnabled' in studio && studio.busPdcEnabled !== undefined) {
    if (typeof studio.busPdcEnabled !== 'object' || studio.busPdcEnabled === null) {
      errors.push({
        type: 'error',
        message: 'studio.busPdcEnabled must be an object',
        field: 'studio.busPdcEnabled',
      });
    } else {
      validateBusPdcEnabled(
        studio.busPdcEnabled as Record<string, unknown>,
        errors
      );
    }
  }

  // assetInsertChains validation (hard-fail on errors)
  if ('assetInsertChains' in studio && studio.assetInsertChains !== undefined) {
    if (typeof studio.assetInsertChains !== 'object' || studio.assetInsertChains === null) {
      errors.push({
        type: 'error',
        message: 'studio.assetInsertChains must be an object',
        field: 'studio.assetInsertChains',
      });
    } else {
      validateAssetInsertChains(
        studio.assetInsertChains as Record<string, unknown>,
        context,
        errors
      );
    }
  }
}

/**
 * Valid bus IDs for insert chains (all except 'master').
 */
const VALID_INSERTABLE_BUS_IDS = ['music', 'sfx', 'ambience', 'voice'] as const;

/**
 * Validate bus insert chains.
 */
function validateBusInsertChains(
  busInsertChains: Record<string, unknown>,
  errors: ProjectValidationError[]
): void {
  for (const [busId, chain] of Object.entries(busInsertChains)) {
    // Validate busId is valid (not 'master')
    if (!VALID_INSERTABLE_BUS_IDS.includes(busId as typeof VALID_INSERTABLE_BUS_IDS[number])) {
      errors.push({
        type: 'error',
        message: `studio.busInsertChains: Invalid bus ID "${busId}". Must be one of: ${VALID_INSERTABLE_BUS_IDS.join(', ')}`,
        field: `studio.busInsertChains.${busId}`,
      });
      continue;
    }

    // Validate the insert chain using the same validation as master insert chain
    const chainResult = validateMasterInsertChain(chain);
    if (!chainResult.valid) {
      for (const err of chainResult.errors) {
        errors.push({
          type: 'error',
          message: `studio.busInsertChains.${busId}: ${err.message}`,
          field: err.field
            ? `studio.busInsertChains.${busId}.${err.field}`
            : `studio.busInsertChains.${busId}`,
        });
      }
    }
  }
}

/**
 * Validate busPdcEnabled settings.
 * Hard-fail on unknown busId or non-boolean values.
 */
function validateBusPdcEnabled(
  busPdcEnabled: Record<string, unknown>,
  errors: ProjectValidationError[]
): void {
  for (const [busId, enabled] of Object.entries(busPdcEnabled)) {
    // Validate busId is valid (not 'master')
    if (!VALID_INSERTABLE_BUS_IDS.includes(busId as typeof VALID_INSERTABLE_BUS_IDS[number])) {
      errors.push({
        type: 'error',
        message: `studio.busPdcEnabled: Invalid bus ID "${busId}". Must be one of: ${VALID_INSERTABLE_BUS_IDS.join(', ')}`,
        field: `studio.busPdcEnabled.${busId}`,
      });
      continue;
    }

    // Validate value is boolean
    if (typeof enabled !== 'boolean') {
      errors.push({
        type: 'error',
        message: `studio.busPdcEnabled.${busId} must be a boolean, got ${typeof enabled}`,
        field: `studio.busPdcEnabled.${busId}`,
      });
    }
  }
}

/**
 * Validate asset insert chains.
 * Hard-fail on invalid assetId (when manifest is available), pluginId, params, or duplicate IDs.
 */
function validateAssetInsertChains(
  assetInsertChains: Record<string, unknown>,
  context: ValidationContext,
  errors: ProjectValidationError[]
): void {
  // Collect all insert IDs across all asset chains for duplicate detection
  const allInsertIds = new Set<string>();

  for (const [assetId, chain] of Object.entries(assetInsertChains)) {
    // If we have asset IDs from manifest, validate that the asset exists
    if (context.assetIds && !context.assetIds.has(assetId)) {
      errors.push({
        type: 'error',
        message: `studio.assetInsertChains: Unknown asset ID "${assetId}". Asset not found in manifest.`,
        field: `studio.assetInsertChains.${assetId}`,
      });
      continue;
    }

    // Validate asset ID format (basic sanity check)
    if (typeof assetId !== 'string' || assetId.trim() === '') {
      errors.push({
        type: 'error',
        message: `studio.assetInsertChains: Invalid asset ID (empty or non-string)`,
        field: `studio.assetInsertChains`,
      });
      continue;
    }

    // Validate the insert chain using the same validation as master/bus insert chains
    const chainResult = validateMasterInsertChain(chain);
    if (!chainResult.valid) {
      for (const err of chainResult.errors) {
        errors.push({
          type: 'error',
          message: `studio.assetInsertChains.${assetId}: ${err.message}`,
          field: err.field
            ? `studio.assetInsertChains.${assetId}.${err.field}`
            : `studio.assetInsertChains.${assetId}`,
        });
      }
    }

    // Check for duplicate insert IDs across all asset chains
    if (chain && typeof chain === 'object' && 'inserts' in chain) {
      const chainObj = chain as { inserts: unknown[] };
      if (Array.isArray(chainObj.inserts)) {
        for (const insert of chainObj.inserts) {
          if (insert && typeof insert === 'object' && 'id' in insert) {
            const insertId = (insert as { id: string }).id;
            if (allInsertIds.has(insertId)) {
              errors.push({
                type: 'error',
                message: `studio.assetInsertChains: Duplicate insert ID "${insertId}" found across asset chains`,
                field: `studio.assetInsertChains.${assetId}`,
              });
            }
            allInsertIds.add(insertId);
          }
        }
      }
    }
  }
}

/**
 * Type guard to check if a validated project is ProjectFileV1.
 */
export function isValidProjectFileV1(project: unknown): project is ProjectFileV1 {
  const result = validateProjectFile(project);
  return result.valid;
}

/**
 * Parse and validate a project file from JSON string.
 *
 * @param json JSON string to parse
 * @param assetIds Optional set of valid asset IDs
 * @returns Parsed project and validation result
 */
export function parseProjectFile(
  json: string,
  assetIds?: Set<string>
): { project: ProjectFileV1 | null; validation: ProjectValidationResult } {
  let parsed: unknown;

  try {
    parsed = JSON.parse(json);
  } catch (e) {
    return {
      project: null,
      validation: {
        valid: false,
        errors: [{
          type: 'error',
          message: `Invalid JSON: ${e instanceof Error ? e.message : String(e)}`,
        }],
        warnings: [],
      },
    };
  }

  const validation = validateProjectFile(parsed, assetIds);

  return {
    project: validation.valid ? parsed as ProjectFileV1 : null,
    validation,
  };
}
