/**
 * ReelForge M7.0 Project Migration Tests
 */

import { describe, it, expect } from 'vitest';
import { migrateProject, needsMigration, getProjectVersion } from '../migrateProject';

describe('migrateProject', () => {
  describe('version 1 (current)', () => {
    it('should accept valid v1 project', () => {
      const project = {
        projectVersion: 1,
        name: 'Test',
        createdAt: '2024-01-01T00:00:00.000Z',
        updatedAt: '2024-01-01T00:00:00.000Z',
        paths: { manifestPath: '/test' },
        routes: { embed: true, data: { routesVersion: 1, defaultBus: 'SFX', events: [] } },
      };

      const result = migrateProject(project);
      expect(result.success).toBe(true);
      expect(result.project).toBe(project); // Identity for v1
      expect(result.migratedFrom).toBe(1);
    });
  });

  describe('invalid input', () => {
    it('should reject null', () => {
      const result = migrateProject(null);
      expect(result.success).toBe(false);
      expect(result.project).toBeNull();
      expect(result.error).toContain('JSON object');
    });

    it('should reject non-object', () => {
      const result = migrateProject('string');
      expect(result.success).toBe(false);
    });

    it('should reject missing projectVersion', () => {
      const result = migrateProject({ name: 'Test' });
      expect(result.success).toBe(false);
      expect(result.error).toContain('projectVersion');
    });

    it('should reject non-number projectVersion', () => {
      const result = migrateProject({ projectVersion: '1', name: 'Test' });
      expect(result.success).toBe(false);
    });
  });

  describe('future versions', () => {
    it('should reject newer versions', () => {
      const result = migrateProject({
        projectVersion: 99,
        name: 'Test',
      });
      expect(result.success).toBe(false);
      expect(result.migratedFrom).toBe(99);
      expect(result.error).toContain('newer than supported');
    });
  });

  describe('unknown versions', () => {
    it('should reject unknown versions', () => {
      const result = migrateProject({
        projectVersion: 0,
        name: 'Test',
      });
      expect(result.success).toBe(false);
      expect(result.error).toContain('Unknown');
    });
  });
});

describe('needsMigration', () => {
  it('should return false for current version', () => {
    expect(needsMigration({ projectVersion: 1 })).toBe(false);
  });

  it('should return false for invalid input', () => {
    expect(needsMigration(null)).toBe(false);
    expect(needsMigration(undefined)).toBe(false);
    expect(needsMigration({})).toBe(false);
    expect(needsMigration({ projectVersion: 'string' })).toBe(false);
  });

  // When v2 exists:
  // it('should return true for older versions', () => {
  //   expect(needsMigration({ projectVersion: 1 })).toBe(true);
  // });
});

describe('getProjectVersion', () => {
  it('should return version number', () => {
    expect(getProjectVersion({ projectVersion: 1 })).toBe(1);
    expect(getProjectVersion({ projectVersion: 99 })).toBe(99);
  });

  it('should return null for invalid input', () => {
    expect(getProjectVersion(null)).toBeNull();
    expect(getProjectVersion(undefined)).toBeNull();
    expect(getProjectVersion({})).toBeNull();
    expect(getProjectVersion({ projectVersion: 'string' })).toBeNull();
  });
});
