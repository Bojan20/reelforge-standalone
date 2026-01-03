/**
 * ReelForge M7.0 Project Migration
 *
 * Handles migration between project file versions.
 * Currently v1 is the only version, so migration is identity.
 */

import type { ProjectFileV1 } from './projectTypes';
import { CURRENT_PROJECT_VERSION } from './projectTypes';

/**
 * Migration result.
 */
export interface MigrationResult {
  success: boolean;
  project: ProjectFileV1 | null;
  migratedFrom: number | null;
  error?: string;
}

/**
 * Migrate a project file to the current version.
 *
 * @param project Raw project data (unknown version)
 * @returns Migration result with migrated project
 */
export function migrateProject(project: unknown): MigrationResult {
  // Check if project is an object
  if (!project || typeof project !== 'object') {
    return {
      success: false,
      project: null,
      migratedFrom: null,
      error: 'Project must be a JSON object',
    };
  }

  const p = project as Record<string, unknown>;

  // Get version
  const version = p.projectVersion;
  if (typeof version !== 'number') {
    return {
      success: false,
      project: null,
      migratedFrom: null,
      error: 'Project file missing projectVersion',
    };
  }

  // Handle version-specific migrations
  switch (version) {
    case 1:
      // v1 is current, no migration needed
      return {
        success: true,
        project: project as ProjectFileV1,
        migratedFrom: 1,
      };

    default:
      // Unknown version
      if (version > CURRENT_PROJECT_VERSION) {
        return {
          success: false,
          project: null,
          migratedFrom: version,
          error: `Project file version ${version} is newer than supported version ${CURRENT_PROJECT_VERSION}. Please update ReelForge Studio.`,
        };
      } else {
        return {
          success: false,
          project: null,
          migratedFrom: version,
          error: `Unknown project file version: ${version}`,
        };
      }
  }
}

/**
 * Check if a project needs migration.
 *
 * @param project Raw project data
 * @returns true if migration is needed
 */
export function needsMigration(project: unknown): boolean {
  if (!project || typeof project !== 'object') {
    return false;
  }

  const p = project as Record<string, unknown>;
  const version = p.projectVersion;

  if (typeof version !== 'number') {
    return false;
  }

  return version < CURRENT_PROJECT_VERSION;
}

/**
 * Get the version of a project file.
 *
 * @param project Raw project data
 * @returns Version number or null if invalid
 */
export function getProjectVersion(project: unknown): number | null {
  if (!project || typeof project !== 'object') {
    return null;
  }

  const p = project as Record<string, unknown>;
  const version = p.projectVersion;

  if (typeof version !== 'number') {
    return null;
  }

  return version;
}

// Future migration functions would be added here:
// function migrateV1ToV2(project: ProjectFileV1): ProjectFileV2 { ... }
// function migrateV2ToV3(project: ProjectFileV2): ProjectFileV3 { ... }
