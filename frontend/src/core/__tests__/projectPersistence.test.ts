/**
 * Project Persistence Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ProjectPersistence, type ProjectData } from '../projectPersistence';

// Mock localStorage
const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: (key: string) => store[key] || null,
    setItem: (key: string, value: string) => { store[key] = value; },
    removeItem: (key: string) => { delete store[key]; },
    clear: () => { store = {}; },
  };
})();

vi.stubGlobal('localStorage', localStorageMock);

describe('ProjectPersistence', () => {
  beforeEach(() => {
    localStorageMock.clear();
    ProjectPersistence.clearAllAutoSaves();
    ProjectPersistence.clearRecentProjects();
  });

  describe('project creation', () => {
    it('should create new project with defaults', () => {
      const project = ProjectPersistence.createNewProject('Test Project', 'Author');

      expect(project.metadata.name).toBe('Test Project');
      expect(project.metadata.author).toBe('Author');
      expect(project.metadata.id).toBeTruthy();
      expect(project.metadata.version).toBe('1.0.0');
      expect(project.buses.length).toBeGreaterThan(0);
      expect(project.events).toEqual([]);
      expect(project.audioFiles).toEqual([]);
    });

    it('should mark new project as dirty', () => {
      ProjectPersistence.createNewProject('Test');
      expect(ProjectPersistence.hasDirtyChanges()).toBe(true);
    });
  });

  describe('serialization', () => {
    it('should serialize project to JSON', () => {
      const project = ProjectPersistence.createNewProject('Test');
      const json = ProjectPersistence.serialize(project);

      expect(typeof json).toBe('string');
      const parsed = JSON.parse(json);
      expect(parsed.metadata.name).toBe('Test');
    });

    it('should deserialize valid JSON', () => {
      const original = ProjectPersistence.createNewProject('Test');
      const json = ProjectPersistence.serialize(original);
      const restored = ProjectPersistence.deserialize(json);

      expect(restored.metadata.name).toBe('Test');
      expect(restored.metadata.id).toBe(original.metadata.id);
    });

    it('should throw on invalid JSON', () => {
      expect(() => {
        ProjectPersistence.deserialize('{ invalid json }');
      }).toThrow();
    });

    it('should throw on missing metadata', () => {
      expect(() => {
        ProjectPersistence.deserialize('{}');
      }).toThrow(/missing metadata/i);
    });
  });

  describe('localStorage persistence', () => {
    it('should save to localStorage', () => {
      const project = ProjectPersistence.createNewProject('Test');
      ProjectPersistence.saveToLocalStorage(project);

      const stored = localStorageMock.getItem(`reelforge-project-${project.metadata.id}`);
      expect(stored).toBeTruthy();
    });

    it('should load from localStorage', () => {
      const project = ProjectPersistence.createNewProject('Test');
      ProjectPersistence.saveToLocalStorage(project);

      const loaded = ProjectPersistence.loadFromLocalStorage(project.metadata.id);
      expect(loaded).toBeTruthy();
      expect(loaded!.metadata.name).toBe('Test');
    });

    it('should return null for non-existent project', () => {
      const loaded = ProjectPersistence.loadFromLocalStorage('non-existent-id');
      expect(loaded).toBeNull();
    });
  });

  describe('recent projects', () => {
    it('should track recent projects', () => {
      ProjectPersistence.addToRecentProjects({
        id: 'proj-1',
        name: 'Project 1',
        lastOpened: new Date().toISOString(),
      });

      const recent = ProjectPersistence.getRecentProjects();
      expect(recent.length).toBe(1);
      expect(recent[0].name).toBe('Project 1');
    });

    it('should move existing project to front', () => {
      ProjectPersistence.addToRecentProjects({
        id: 'proj-1',
        name: 'Project 1',
        lastOpened: new Date().toISOString(),
      });
      ProjectPersistence.addToRecentProjects({
        id: 'proj-2',
        name: 'Project 2',
        lastOpened: new Date().toISOString(),
      });
      ProjectPersistence.addToRecentProjects({
        id: 'proj-1',
        name: 'Project 1 Updated',
        lastOpened: new Date().toISOString(),
      });

      const recent = ProjectPersistence.getRecentProjects();
      expect(recent.length).toBe(2);
      expect(recent[0].id).toBe('proj-1');
    });

    it('should limit to 10 recent projects', () => {
      for (let i = 0; i < 15; i++) {
        ProjectPersistence.addToRecentProjects({
          id: `proj-${i}`,
          name: `Project ${i}`,
          lastOpened: new Date().toISOString(),
        });
      }

      const recent = ProjectPersistence.getRecentProjects();
      expect(recent.length).toBe(10);
    });

    it('should remove from recent', () => {
      ProjectPersistence.addToRecentProjects({
        id: 'proj-1',
        name: 'Project 1',
        lastOpened: new Date().toISOString(),
      });

      ProjectPersistence.removeFromRecentProjects('proj-1');
      const recent = ProjectPersistence.getRecentProjects();
      expect(recent.length).toBe(0);
    });
  });

  describe('dirty state', () => {
    it('should track dirty state', () => {
      expect(ProjectPersistence.hasDirtyChanges()).toBe(false);

      ProjectPersistence.markDirty();
      expect(ProjectPersistence.hasDirtyChanges()).toBe(true);

      ProjectPersistence.markClean();
      expect(ProjectPersistence.hasDirtyChanges()).toBe(false);
    });

    it('should mark clean after save', () => {
      const project = ProjectPersistence.createNewProject('Test');
      expect(ProjectPersistence.hasDirtyChanges()).toBe(true);

      ProjectPersistence.saveToLocalStorage(project);
      expect(ProjectPersistence.hasDirtyChanges()).toBe(false);
    });
  });

  describe('export formats', () => {
    it('should export as JSON', () => {
      const project = ProjectPersistence.createNewProject('Test');
      const json = ProjectPersistence.exportAs(project, 'json');

      const parsed = JSON.parse(json);
      expect(parsed.metadata).toBeDefined();
      expect(parsed.events).toBeDefined();
    });

    it('should export as minimal', () => {
      const project = ProjectPersistence.createNewProject('Test');
      const minimal = ProjectPersistence.exportAs(project, 'minimal');

      const parsed = JSON.parse(minimal);
      expect(parsed.name).toBe('Test');
      expect(parsed.metadata).toBeUndefined();
    });
  });
});
