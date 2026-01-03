/**
 * ReelForge M7.0 Project Storage Tests
 */

import { describe, it, expect } from 'vitest';
import { stringifyProject } from '../projectStorage';
import type { ProjectFileV1 } from '../projectTypes';

describe('stringifyProject', () => {
  const baseProject: ProjectFileV1 = {
    projectVersion: 1,
    name: 'Test Project',
    createdAt: '2024-01-01T00:00:00.000Z',
    updatedAt: '2024-01-02T00:00:00.000Z',
    paths: {
      manifestPath: '/path/to/manifest.json',
    },
    routes: {
      embed: true,
      data: {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [],
      },
    },
  };

  it('should produce 2-space indented JSON', () => {
    const result = stringifyProject(baseProject);
    // Check that it uses 2-space indentation
    expect(result).toContain('  "projectVersion"');
    expect(result).toContain('  "name"');
  });

  it('should end with a newline', () => {
    const result = stringifyProject(baseProject);
    expect(result.endsWith('\n')).toBe(true);
  });

  it('should sort top-level keys in order', () => {
    const result = stringifyProject(baseProject);
    const lines = result.split('\n');

    // projectVersion should come first (after opening brace)
    expect(lines[1]).toContain('projectVersion');
    // name should come second
    expect(lines[2]).toContain('name');
    // createdAt should come third
    expect(lines[3]).toContain('createdAt');
  });

  it('should be deterministic (same input = same output)', () => {
    const result1 = stringifyProject(baseProject);
    const result2 = stringifyProject(baseProject);
    expect(result1).toBe(result2);
  });

  it('should sort nested objects in paths', () => {
    const projectWithRoutes: ProjectFileV1 = {
      ...baseProject,
      paths: {
        routesPath: '/routes.json',
        manifestPath: '/manifest.json',
      },
      routes: { embed: false },
    };

    const result = stringifyProject(projectWithRoutes);
    const pathsStart = result.indexOf('"paths"');
    const manifestIdx = result.indexOf('"manifestPath"', pathsStart);
    const routesIdx = result.indexOf('"routesPath"', pathsStart);

    // manifestPath should come before routesPath
    expect(manifestIdx).toBeLessThan(routesIdx);
  });

  it('should sort routes.data keys correctly', () => {
    const result = stringifyProject(baseProject);
    const dataStart = result.indexOf('"data"');

    // routesVersion should come before defaultBus
    const routesVersionIdx = result.indexOf('"routesVersion"', dataStart);
    const defaultBusIdx = result.indexOf('"defaultBus"', dataStart);
    const eventsIdx = result.indexOf('"events"', dataStart);

    expect(routesVersionIdx).toBeLessThan(defaultBusIdx);
    expect(defaultBusIdx).toBeLessThan(eventsIdx);
  });

  it('should produce valid JSON', () => {
    const result = stringifyProject(baseProject);
    expect(() => JSON.parse(result)).not.toThrow();
  });

  it('should preserve all data through round-trip', () => {
    const result = stringifyProject(baseProject);
    const parsed = JSON.parse(result);

    expect(parsed.projectVersion).toBe(baseProject.projectVersion);
    expect(parsed.name).toBe(baseProject.name);
    expect(parsed.createdAt).toBe(baseProject.createdAt);
    expect(parsed.updatedAt).toBe(baseProject.updatedAt);
    expect(parsed.paths.manifestPath).toBe(baseProject.paths.manifestPath);
    expect(parsed.routes.embed).toBe(baseProject.routes.embed);
    expect(parsed.routes.data.routesVersion).toBe(baseProject.routes.data?.routesVersion);
  });

  it('should handle complex routes data', () => {
    const projectWithEvents: ProjectFileV1 = {
      ...baseProject,
      routes: {
        embed: true,
        data: {
          routesVersion: 1,
          defaultBus: 'SFX',
          events: [
            {
              name: 'onTest',
              actions: [
                { type: 'Play', assetId: 'test_sound', bus: 'SFX', gain: 0.8 },
                { type: 'SetBusGain', bus: 'Music', gain: 0.5 },
              ],
            },
          ],
        },
      },
    };

    const result = stringifyProject(projectWithEvents);
    expect(() => JSON.parse(result)).not.toThrow();

    const parsed = JSON.parse(result);
    expect(parsed.routes.data.events).toHaveLength(1);
    expect(parsed.routes.data.events[0].name).toBe('onTest');
    expect(parsed.routes.data.events[0].actions).toHaveLength(2);
  });

  it('should handle studio preferences', () => {
    const projectWithStudio: ProjectFileV1 = {
      ...baseProject,
      studio: {
        selectedTab: 'Routes',
        routesUi: {
          selectedEventName: 'onTest',
          searchQuery: 'test',
        },
      },
    };

    const result = stringifyProject(projectWithStudio);
    const parsed = JSON.parse(result);

    expect(parsed.studio.selectedTab).toBe('Routes');
    expect(parsed.studio.routesUi.selectedEventName).toBe('onTest');
    expect(parsed.studio.routesUi.searchQuery).toBe('test');
  });
});
