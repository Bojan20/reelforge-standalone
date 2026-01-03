/**
 * ReelForge M6.7 Routes Validation Tests
 *
 * Unit tests for validateRoutes matching C++ RuntimeCore behavior.
 */

import { describe, it, expect } from 'vitest';
import {
  validateRoutes,
  parseRoutesJson,
  formatErrorLocation,
} from './validateRoutes';
import type { RoutesConfig } from './routesTypes';

describe('validateRoutes', () => {
  describe('routesVersion validation', () => {
    it('accepts routesVersion 1', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
      expect(result.errors).toHaveLength(0);
    });

    it('rejects routesVersion 0', () => {
      const config: RoutesConfig = {
        routesVersion: 0,
        defaultBus: 'SFX',
        events: [],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          field: 'routesVersion',
          message: expect.stringContaining('Must be 1'),
        })
      );
    });

    it('rejects routesVersion 2', () => {
      const config: RoutesConfig = {
        routesVersion: 2,
        defaultBus: 'SFX',
        events: [],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
    });
  });

  describe('defaultBus validation', () => {
    it('accepts valid bus names', () => {
      const buses = ['Master', 'Music', 'SFX', 'UI', 'VO', 'Ambience'];
      for (const bus of buses) {
        const config: RoutesConfig = {
          routesVersion: 1,
          defaultBus: bus as any,
          events: [],
        };
        const result = validateRoutes(config);
        expect(result.valid).toBe(true);
      }
    });

    it('rejects invalid bus name', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'InvalidBus' as any,
        events: [],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          field: 'defaultBus',
          message: expect.stringContaining('Invalid defaultBus'),
        })
      );
    });
  });

  describe('event name validation', () => {
    it('accepts valid event names', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          { name: 'onBaseGameSpin', actions: [] },
          { name: 'onReelStop', actions: [] },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
    });

    it('rejects empty event name', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [{ name: '', actions: [] }],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      // Empty string fails the required check - any error on name field is acceptable
      expect(result.errors.some((e) => e.field === 'name')).toBe(true);
    });

    it('rejects duplicate event names', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          { name: 'onDuplicate', actions: [] },
          { name: 'onDuplicate', actions: [] },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          message: expect.stringContaining('Duplicate event name'),
        })
      );
    });

    it('warns about non-standard naming', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [{ name: 'badName', actions: [] }],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true); // Warning, not error
      expect(result.warnings).toContainEqual(
        expect.objectContaining({
          message: expect.stringContaining('should start with "on"'),
        })
      );
    });
  });

  describe('Play action validation', () => {
    it('accepts valid Play action', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [
              { type: 'Play', assetId: 'test_sound', bus: 'SFX', gain: 1.0, loop: false },
            ],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
    });

    it('rejects Play action without assetId', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'Play', assetId: '' } as any],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          field: 'assetId',
          actionIndex: 0,
        })
      );
    });

    it('validates assetId against catalog', () => {
      const assetIds = new Set(['valid_asset']);
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'Play', assetId: 'unknown_asset' }],
          },
        ],
      };
      const result = validateRoutes(config, assetIds);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          field: 'assetId',
          message: expect.stringContaining('Unknown assetId'),
        })
      );
    });

    it('rejects gain < 0', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'Play', assetId: 'test', gain: -0.5 }],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
      expect(result.errors).toContainEqual(
        expect.objectContaining({
          field: 'gain',
          message: expect.stringContaining('between 0.0 and 1.0'),
        })
      );
    });

    it('rejects gain > 1', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'Play', assetId: 'test', gain: 1.5 }],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
    });

    it('rejects invalid bus', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'Play', assetId: 'test', bus: 'BadBus' as any }],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
    });
  });

  describe('SetBusGain action validation', () => {
    it('accepts valid SetBusGain action', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'SetBusGain', bus: 'Music', gain: 0.5 }],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
    });

    it('rejects SetBusGain without bus', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'SetBusGain', gain: 0.5 } as any],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
    });

    it('rejects SetBusGain without gain', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'SetBusGain', bus: 'Music' } as any],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(false);
    });
  });

  describe('StopAll action validation', () => {
    it('accepts StopAll action', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [
          {
            name: 'onTest',
            actions: [{ type: 'StopAll' }],
          },
        ],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
    });
  });

  describe('empty actions warning', () => {
    it('warns about events with no actions', () => {
      const config: RoutesConfig = {
        routesVersion: 1,
        defaultBus: 'SFX',
        events: [{ name: 'onEmpty', actions: [] }],
      };
      const result = validateRoutes(config);
      expect(result.valid).toBe(true);
      expect(result.warnings).toContainEqual(
        expect.objectContaining({
          message: expect.stringContaining('no actions'),
        })
      );
    });
  });
});

describe('parseRoutesJson', () => {
  it('parses valid JSON', () => {
    const json = JSON.stringify({
      routesVersion: 1,
      defaultBus: 'SFX',
      events: [
        {
          name: 'onTest',
          actions: [{ type: 'StopAll' }],
        },
      ],
    });
    const { config, validation } = parseRoutesJson(json);
    expect(config).not.toBeNull();
    expect(validation.valid).toBe(true);
  });

  it('rejects invalid JSON', () => {
    const { config, validation } = parseRoutesJson('{ invalid json }');
    expect(config).toBeNull();
    expect(validation.valid).toBe(false);
    expect(validation.errors[0].message).toContain('Invalid JSON');
  });

  it('rejects non-object JSON', () => {
    const { config, validation } = parseRoutesJson('"string"');
    expect(config).toBeNull();
    expect(validation.valid).toBe(false);
  });
});

describe('formatErrorLocation', () => {
  it('formats root error', () => {
    const location = formatErrorLocation({ type: 'error', message: 'test' });
    expect(location).toBe('root');
  });

  it('formats event error', () => {
    const location = formatErrorLocation({
      type: 'error',
      message: 'test',
      eventName: 'onTest',
      eventIndex: 0,
    });
    expect(location).toBe('event "onTest"');
  });

  it('formats action error', () => {
    const location = formatErrorLocation({
      type: 'error',
      message: 'test',
      eventName: 'onTest',
      eventIndex: 0,
      actionIndex: 1,
      field: 'assetId',
    });
    expect(location).toBe('event "onTest" > action[1] > assetId');
  });
});
