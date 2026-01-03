/**
 * PluginVersionManager - Plugin Versioning and Hot Reload
 *
 * Manages plugin versions with:
 * - Semantic versioning comparison
 * - Hot reload support for development
 * - Plugin state migration between versions
 * - Compatibility checking
 *
 * @module plugin/PluginVersionManager
 */

import type { PluginDefinition } from './PluginDefinition';

// ============ Types ============

export interface SemanticVersion {
  major: number;
  minor: number;
  patch: number;
  prerelease?: string;
}

export interface PluginVersionInfo {
  id: string;
  version: string;
  parsedVersion: SemanticVersion;
  installedAt: number;
  updatedAt: number;
  loadCount: number;
}

export interface VersionCompatibility {
  compatible: boolean;
  reason?: string;
  migrationRequired?: boolean;
  migrationPath?: string[];
}

export interface PluginMigration {
  fromVersion: string;
  toVersion: string;
  migrate: (oldState: Record<string, unknown>) => Record<string, unknown>;
}

export interface HotReloadEvent {
  type: 'registered' | 'updated' | 'removed';
  pluginId: string;
  oldVersion?: string;
  newVersion?: string;
}

// ============ Semantic Version Parser ============

export function parseVersion(version: string): SemanticVersion {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/);
  if (!match) {
    return { major: 0, minor: 0, patch: 0 };
  }
  return {
    major: parseInt(match[1], 10),
    minor: parseInt(match[2], 10),
    patch: parseInt(match[3], 10),
    prerelease: match[4],
  };
}

export function versionToString(v: SemanticVersion): string {
  let str = `${v.major}.${v.minor}.${v.patch}`;
  if (v.prerelease) str += `-${v.prerelease}`;
  return str;
}

export function compareVersions(a: SemanticVersion, b: SemanticVersion): number {
  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  if (a.patch !== b.patch) return a.patch - b.patch;

  // Prerelease versions are lower than release versions
  if (a.prerelease && !b.prerelease) return -1;
  if (!a.prerelease && b.prerelease) return 1;
  if (a.prerelease && b.prerelease) {
    return a.prerelease.localeCompare(b.prerelease);
  }
  return 0;
}

export function isVersionCompatible(
  required: string,
  installed: string
): VersionCompatibility {
  const req = parseVersion(required);
  const inst = parseVersion(installed);

  // Major version mismatch = breaking change
  if (req.major !== inst.major) {
    return {
      compatible: false,
      reason: `Major version mismatch: required ${required}, installed ${installed}`,
      migrationRequired: true,
    };
  }

  // Installed version older than required
  if (compareVersions(inst, req) < 0) {
    return {
      compatible: false,
      reason: `Installed version ${installed} is older than required ${required}`,
      migrationRequired: false,
    };
  }

  return { compatible: true };
}

// ============ Plugin Version Manager ============

export class PluginVersionManager {
  private versions: Map<string, PluginVersionInfo> = new Map();
  private migrations: Map<string, PluginMigration[]> = new Map();
  private hotReloadListeners: Set<(event: HotReloadEvent) => void> = new Set();
  private debug = process.env.NODE_ENV === 'development';

  /**
   * Register a plugin version.
   */
  registerVersion(plugin: PluginDefinition): PluginVersionInfo {
    const existing = this.versions.get(plugin.id);
    const now = Date.now();

    if (existing) {
      // Update existing
      const oldVersion = existing.version;
      const newVersion = plugin.version;

      existing.version = newVersion;
      existing.parsedVersion = parseVersion(newVersion);
      existing.updatedAt = now;
      existing.loadCount++;

      // Notify hot reload listeners
      if (oldVersion !== newVersion) {
        this.notifyHotReload({
          type: 'updated',
          pluginId: plugin.id,
          oldVersion,
          newVersion,
        });
        this.log(`Plugin ${plugin.id} updated: ${oldVersion} -> ${newVersion}`);
      }

      return existing;
    }

    // Register new
    const info: PluginVersionInfo = {
      id: plugin.id,
      version: plugin.version,
      parsedVersion: parseVersion(plugin.version),
      installedAt: now,
      updatedAt: now,
      loadCount: 1,
    };

    this.versions.set(plugin.id, info);

    this.notifyHotReload({
      type: 'registered',
      pluginId: plugin.id,
      newVersion: plugin.version,
    });

    this.log(`Plugin ${plugin.id} registered: v${plugin.version}`);
    return info;
  }

  /**
   * Unregister a plugin.
   */
  unregisterVersion(pluginId: string): void {
    const info = this.versions.get(pluginId);
    if (!info) return;

    this.versions.delete(pluginId);

    this.notifyHotReload({
      type: 'removed',
      pluginId,
      oldVersion: info.version,
    });

    this.log(`Plugin ${pluginId} removed`);
  }

  /**
   * Get version info for a plugin.
   */
  getVersionInfo(pluginId: string): PluginVersionInfo | undefined {
    return this.versions.get(pluginId);
  }

  /**
   * Check if a plugin version is compatible with a requirement.
   */
  checkCompatibility(pluginId: string, requiredVersion: string): VersionCompatibility {
    const info = this.versions.get(pluginId);
    if (!info) {
      return {
        compatible: false,
        reason: `Plugin ${pluginId} not installed`,
      };
    }

    return isVersionCompatible(requiredVersion, info.version);
  }

  /**
   * Register a migration path between versions.
   */
  registerMigration(pluginId: string, migration: PluginMigration): void {
    if (!this.migrations.has(pluginId)) {
      this.migrations.set(pluginId, []);
    }
    this.migrations.get(pluginId)!.push(migration);
    this.log(`Migration registered for ${pluginId}: ${migration.fromVersion} -> ${migration.toVersion}`);
  }

  /**
   * Migrate plugin state from one version to another.
   */
  migrateState(
    pluginId: string,
    state: Record<string, unknown>,
    fromVersion: string,
    toVersion: string
  ): Record<string, unknown> {
    const migrations = this.migrations.get(pluginId);
    if (!migrations) {
      this.log(`No migrations for ${pluginId}, returning original state`);
      return state;
    }

    // Build migration path
    const path = this.findMigrationPath(migrations, fromVersion, toVersion);
    if (!path || path.length === 0) {
      this.log(`No migration path from ${fromVersion} to ${toVersion}`);
      return state;
    }

    // Apply migrations in order
    let currentState = state;
    for (const migration of path) {
      this.log(`Applying migration: ${migration.fromVersion} -> ${migration.toVersion}`);
      currentState = migration.migrate(currentState);
    }

    return currentState;
  }

  /**
   * Subscribe to hot reload events.
   */
  onHotReload(listener: (event: HotReloadEvent) => void): () => void {
    this.hotReloadListeners.add(listener);
    return () => this.hotReloadListeners.delete(listener);
  }

  /**
   * Get all registered versions.
   */
  getAllVersions(): PluginVersionInfo[] {
    return Array.from(this.versions.values());
  }

  /**
   * Check for updates (placeholder for future remote update checking).
   */
  async checkForUpdates(): Promise<Map<string, string>> {
    // In a real implementation, this would check a remote server
    // For now, return empty map (no updates)
    return new Map();
  }

  // ============ Private Methods ============

  private findMigrationPath(
    migrations: PluginMigration[],
    from: string,
    to: string
  ): PluginMigration[] | null {
    // Simple BFS to find migration path
    const fromParsed = parseVersion(from);
    const toParsed = parseVersion(to);

    if (compareVersions(fromParsed, toParsed) >= 0) {
      return []; // Already at or ahead of target version
    }

    const visited = new Set<string>();
    const queue: { version: string; path: PluginMigration[] }[] = [
      { version: from, path: [] },
    ];

    while (queue.length > 0) {
      const { version, path } = queue.shift()!;
      if (visited.has(version)) continue;
      visited.add(version);

      for (const migration of migrations) {
        if (migration.fromVersion === version) {
          const newPath = [...path, migration];
          if (migration.toVersion === to) {
            return newPath;
          }
          queue.push({ version: migration.toVersion, path: newPath });
        }
      }
    }

    return null;
  }

  private notifyHotReload(event: HotReloadEvent): void {
    for (const listener of this.hotReloadListeners) {
      try {
        listener(event);
      } catch (error) {
        console.error('[PluginVersionManager] Listener error:', error);
      }
    }
  }

  private log(message: string): void {
    if (this.debug) {
      console.log(`[PluginVersionManager] ${message}`);
    }
  }
}

// ============ Singleton Instance ============

let globalVersionManager: PluginVersionManager | null = null;

export function getPluginVersionManager(): PluginVersionManager {
  if (!globalVersionManager) {
    globalVersionManager = new PluginVersionManager();
  }
  return globalVersionManager;
}

export default PluginVersionManager;
