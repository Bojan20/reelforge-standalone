/**
 * ReelForge M8.6 Diagnostics Export Tests
 *
 * Tests for stable stringify, export snapshot builder, and format helpers.
 */

import { describe, it, expect } from 'vitest';
import {
  sortObjectKeys,
  stringifyStable,
  buildExportSnapshot,
  generateFilename,
  generateTextSummary,
} from '../diagnosticsExport';
import type { DiagnosticsSnapshot } from '../useDiagnosticsSnapshot';

// Mock snapshot for testing
function createMockSnapshot(): DiagnosticsSnapshot {
  return {
    timestamp: 1703001600000, // 2023-12-19T12:00:00.000Z
    assetLatencyMs: 0,
    busLatencies: [
      { busId: 'music', latencyMs: 10.5, pdcEnabled: true, pdcDelayMs: 10.5, pdcClamped: false, pdcMaxMs: 500 },
      { busId: 'sfx', latencyMs: 5.2, pdcEnabled: false, pdcDelayMs: 0, pdcClamped: false, pdcMaxMs: 500 },
      { busId: 'ambience', latencyMs: 0, pdcEnabled: false, pdcDelayMs: 0, pdcClamped: false, pdcMaxMs: 500 },
      { busId: 'voice', latencyMs: 2.7, pdcEnabled: true, pdcDelayMs: 2.7, pdcClamped: false, pdcMaxMs: 500 },
    ],
    masterLatencyMs: 8.3,
    masterPdcEnabled: true,
    masterPdcDelayMs: 8.3,
    masterPdcClamped: false,
    masterPdcMaxMs: 500,
    totalLatencyByBus: {
      music: 18.8,
      sfx: 13.5,
      ambience: 8.3,
      voice: 11.0,
    },
    ducking: {
      isDucking: true,
      duckerVoiceCount: 2,
      duckerBus: 'voice',
      duckedBus: 'music',
      duckRatio: 0.35,
      currentDuckGain: 0.65,
    },
    voiceHealth: {
      totalVoices: 5,
      voicesByBus: {
        music: 2,
        sfx: 1,
        ambience: 0,
        voice: 2,
        master: 0,
      },
      activeAssetChains: 3,
      chainThresholdExceeded: false,
    },
    warnings: [
      { id: 'test-warning', message: 'Test warning', severity: 'warning' },
    ],
  };
}

describe('diagnosticsExport', () => {
  describe('sortObjectKeys', () => {
    it('should sort object keys alphabetically', () => {
      const input = { zebra: 1, apple: 2, mango: 3 };
      const result = sortObjectKeys(input);
      const keys = Object.keys(result);

      expect(keys).toEqual(['apple', 'mango', 'zebra']);
    });

    it('should handle nested objects', () => {
      const input = { outer: { zebra: 1, apple: 2 }, first: 'value' };
      const result = sortObjectKeys(input);
      const outerKeys = Object.keys(result);
      const innerKeys = Object.keys((result as Record<string, unknown>).outer as Record<string, unknown>);

      expect(outerKeys).toEqual(['first', 'outer']);
      expect(innerKeys).toEqual(['apple', 'zebra']);
    });

    it('should preserve array order', () => {
      const input = { items: [3, 1, 2] };
      const result = sortObjectKeys(input);

      expect((result as { items: number[] }).items).toEqual([3, 1, 2]);
    });

    it('should sort objects within arrays', () => {
      const input = { items: [{ z: 1, a: 2 }, { y: 3, b: 4 }] };
      const result = sortObjectKeys(input) as { items: Record<string, number>[] };

      expect(Object.keys(result.items[0])).toEqual(['a', 'z']);
      expect(Object.keys(result.items[1])).toEqual(['b', 'y']);
    });

    it('should handle null and undefined', () => {
      expect(sortObjectKeys(null)).toBe(null);
      expect(sortObjectKeys(undefined)).toBe(undefined);
    });

    it('should handle primitive values', () => {
      expect(sortObjectKeys(42)).toBe(42);
      expect(sortObjectKeys('string')).toBe('string');
      expect(sortObjectKeys(true)).toBe(true);
    });
  });

  describe('stringifyStable', () => {
    it('should produce deterministic output', () => {
      const obj1 = { b: 2, a: 1 };
      const obj2 = { a: 1, b: 2 };

      const str1 = stringifyStable(obj1);
      const str2 = stringifyStable(obj2);

      expect(str1).toBe(str2);
    });

    it('should produce valid JSON', () => {
      const obj = { nested: { value: [1, 2, 3] }, key: 'test' };
      const str = stringifyStable(obj);
      const parsed = JSON.parse(str);

      expect(parsed.key).toBe('test');
      expect(parsed.nested.value).toEqual([1, 2, 3]);
    });

    it('should format with indentation by default', () => {
      const obj = { a: 1 };
      const str = stringifyStable(obj);

      expect(str).toContain('\n');
    });

    it('should produce compact output when requested', () => {
      const obj = { a: 1, b: 2 };
      const str = stringifyStable(obj, false);

      expect(str).not.toContain('\n');
      expect(str).toBe('{"a":1,"b":2}');
    });

    it('should handle complex nested structures', () => {
      const snapshot = createMockSnapshot();
      const str = stringifyStable(snapshot);
      const parsed = JSON.parse(str);

      expect(parsed.timestamp).toBe(snapshot.timestamp);
      expect(parsed.masterLatencyMs).toBe(snapshot.masterLatencyMs);
    });
  });

  describe('buildExportSnapshot', () => {
    it('should build complete export snapshot', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.header).toBeDefined();
      expect(result.latency).toBeDefined();
      expect(result.pdc).toBeDefined();
      expect(result.ducking).toBeDefined();
      expect(result.voices).toBeDefined();
      expect(result.warnings).toBeDefined();
    });

    it('should include correct header fields', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot, {
        projectName: 'TestProject',
        projectId: 'proj-123',
        viewMode: 'events',
      });

      expect(result.header.timestampMs).toBe(snapshot.timestamp);
      // Verify ISO format (timezone-agnostic check)
      expect(result.header.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/);
      expect(result.header.projectName).toBe('TestProject');
      expect(result.header.projectId).toBe('proj-123');
      expect(result.header.viewMode).toBe('events');
      expect(result.header.appVersion).toBeDefined();
    });

    it('should calculate latency values correctly', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.latency.assetLatencyMs).toBe(0);
      expect(result.latency.masterLatencyMs).toBe(8.3);
      expect(result.latency.busLatencyMs.music).toBe(10.5);
      expect(result.latency.totalMusicPathMs).toBe(18.8);
      expect(result.latency.totalMaxPathMs).toBe(18.8);
    });

    it('should include PDC state for all buses', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.pdc.master.enabled).toBe(true);
      expect(result.pdc.master.appliedMs).toBe(8.3);
      expect(result.pdc.buses.music.enabled).toBe(true);
      expect(result.pdc.buses.sfx.enabled).toBe(false);
    });

    it('should include ducking state', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.ducking.policy.duckerBus).toBe('voice');
      expect(result.ducking.policy.duckedBus).toBe('music');
      expect(result.ducking.state.active).toBe(true);
      expect(result.ducking.state.currentDuckGain).toBe(0.65);
    });

    it('should include voice health data', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.voices.totalActiveVoices).toBe(5);
      expect(result.voices.activeAssetChains).toBe(3);
      expect(result.voices.chainThresholdExceeded).toBe(false);
      expect(result.voices.chainThreshold).toBe(16);
    });

    it('should preserve warnings', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.warnings).toHaveLength(1);
      expect(result.warnings[0].id).toBe('test-warning');
      expect(result.warnings[0].severity).toBe('warning');
    });

    it('should handle null context values', () => {
      const snapshot = createMockSnapshot();
      const result = buildExportSnapshot(snapshot);

      expect(result.header.projectName).toBe(null);
      expect(result.header.audioContextState).toBe(null);
      expect(result.header.sampleRate).toBe(null);
    });
  });

  describe('generateFilename', () => {
    it('should follow expected format', () => {
      const filename = generateFilename(1703001600000);

      expect(filename).toMatch(/^reelforge-diagnostics-\d{8}-\d{6}\.json$/);
    });

    it('should use provided timestamp in local timezone', () => {
      const timestamp = 1703001600000;
      const filename = generateFilename(timestamp);

      // The filename should contain date in YYYYMMDD format (local time)
      const d = new Date(timestamp);
      const expectedDate = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
      expect(filename).toContain(expectedDate);
    });

    it('should pad single-digit values', () => {
      // Use a specific timestamp and verify format
      const timestamp = Date.now();
      const filename = generateFilename(timestamp);

      // Verify the filename has properly padded format: YYYYMMDD-HHMMSS
      expect(filename).toMatch(/reelforge-diagnostics-\d{8}-\d{6}\.json/);
    });
  });

  describe('generateTextSummary', () => {
    it('should generate non-empty summary', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot);

      expect(summary.length).toBeGreaterThan(0);
    });

    it('should include section headers', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot);

      expect(summary).toContain('--- LATENCY ---');
      expect(summary).toContain('--- PDC STATE ---');
      expect(summary).toContain('--- DUCKING ---');
      expect(summary).toContain('--- VOICES ---');
    });

    it('should include warnings section when warnings exist', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot);

      expect(summary).toContain('--- WARNINGS ---');
      expect(summary).toContain('Test warning');
    });

    it('should include project name when provided', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot, { projectName: 'MyProject' });

      expect(summary).toContain('Project: MyProject');
    });

    it('should format latency values correctly', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot);

      expect(summary).toContain('Master: 8.3 ms');
      expect(summary).toContain('Bus music: 10.5 ms');
    });

    it('should indicate PDC state', () => {
      const snapshot = createMockSnapshot();
      const summary = generateTextSummary(snapshot);

      expect(summary).toContain('[PDC]');
    });
  });

  describe('deterministic output', () => {
    it('two snapshots with same data should produce identical JSON (except timestamp)', () => {
      const snapshot1 = createMockSnapshot();
      const snapshot2 = createMockSnapshot();

      // Same timestamp
      snapshot1.timestamp = 1000;
      snapshot2.timestamp = 1000;

      const json1 = stringifyStable(buildExportSnapshot(snapshot1));
      const json2 = stringifyStable(buildExportSnapshot(snapshot2));

      expect(json1).toBe(json2);
    });

    it('key order should not affect output', () => {
      const obj1 = { z: { c: 3, a: 1, b: 2 }, y: 4, x: 5 };
      const obj2 = { x: 5, y: 4, z: { b: 2, c: 3, a: 1 } };

      expect(stringifyStable(obj1)).toBe(stringifyStable(obj2));
    });
  });
});
