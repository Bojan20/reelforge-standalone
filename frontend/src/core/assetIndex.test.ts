/**
 * AssetIndex unit tests
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  AssetIndex,
  searchAssets,
  createDebouncedSearch,
  type AssetMeta,
  type RuntimeManifest,
} from './assetIndex';

// Sample test data
const sampleAssets: AssetMeta[] = [
  { id: 'spin_loop', path: 'audio/spin_loop.mp3' },
  { id: 'reel_stop', path: 'audio/reel_stop.ogg' },
  { id: 'win_small', path: 'audio/win_small.mp3' },
  { id: 'win_medium', path: 'audio/win_medium.mp3' },
  { id: 'win_big', path: 'audio/win_big.mp3' },
  { id: 'ui_click', path: 'audio/ui_click.wav' },
  { id: 'ui_hover', path: 'audio/ui_hover.wav' },
  { id: 'bonus_intro', path: 'audio/bonus_intro.mp3' },
  { id: 'bonus_ambient', path: 'audio/bonus_ambient.ogg' },
  { id: 'base_music', path: 'audio/base_music.ogg' },
];

const sampleManifest: RuntimeManifest = {
  manifestVersion: '1.0.0',
  assets: sampleAssets,
};

describe('AssetIndex', () => {
  describe('constructor', () => {
    it('creates empty index when no assets provided', () => {
      const index = new AssetIndex();
      expect(index.count).toBe(0);
      expect(index.getAll()).toEqual([]);
    });

    it('creates index from assets array', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.count).toBe(10);
    });

    it('creates defensive copy of assets array', () => {
      const assets = [...sampleAssets];
      const index = new AssetIndex(assets);
      assets.push({ id: 'new_asset' });
      expect(index.count).toBe(10); // Should not include new_asset
    });
  });

  describe('fromManifest', () => {
    it('creates index from manifest object', () => {
      const index = AssetIndex.fromManifest(sampleManifest);
      expect(index.count).toBe(10);
      expect(index.get('spin_loop')).toEqual({ id: 'spin_loop', path: 'audio/spin_loop.mp3' });
    });
  });

  describe('fromJson', () => {
    it('creates index from JSON string', () => {
      const json = JSON.stringify(sampleManifest);
      const index = AssetIndex.fromJson(json);
      expect(index.count).toBe(10);
    });

    it('throws on invalid JSON', () => {
      expect(() => AssetIndex.fromJson('not json')).toThrow();
    });
  });

  describe('get', () => {
    it('returns asset by ID', () => {
      const index = new AssetIndex(sampleAssets);
      const asset = index.get('spin_loop');
      expect(asset).toEqual({ id: 'spin_loop', path: 'audio/spin_loop.mp3' });
    });

    it('returns undefined for unknown ID', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.get('unknown')).toBeUndefined();
    });
  });

  describe('has', () => {
    it('returns true for existing asset', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.has('spin_loop')).toBe(true);
    });

    it('returns false for unknown asset', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.has('unknown')).toBe(false);
    });
  });

  describe('getIdSet', () => {
    it('returns Set of all asset IDs', () => {
      const index = new AssetIndex(sampleAssets);
      const idSet = index.getIdSet();
      expect(idSet.size).toBe(10);
      expect(idSet.has('spin_loop')).toBe(true);
      expect(idSet.has('win_big')).toBe(true);
      expect(idSet.has('unknown')).toBe(false);
    });
  });

  describe('search', () => {
    it('returns all assets when query is empty', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.search('')).toHaveLength(10);
    });

    it('searches by ID (case-insensitive)', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.search('SPIN')).toEqual([{ id: 'spin_loop', path: 'audio/spin_loop.mp3' }]);
    });

    it('searches by path (case-insensitive)', () => {
      const index = new AssetIndex(sampleAssets);
      const results = index.search('.ogg');
      expect(results).toHaveLength(3); // reel_stop, bonus_ambient, base_music
      expect(results.map((a) => a.id)).toContain('reel_stop');
    });

    it('respects limit parameter', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.search('win', 2)).toHaveLength(2);
    });

    it('matches partial strings', () => {
      const index = new AssetIndex(sampleAssets);
      expect(index.search('ui_')).toHaveLength(2);
    });
  });
});

describe('searchAssets', () => {
  it('returns all assets for empty query', () => {
    expect(searchAssets(sampleAssets, '')).toHaveLength(10);
    expect(searchAssets(sampleAssets, '   ')).toHaveLength(10);
  });

  it('searches case-insensitively', () => {
    expect(searchAssets(sampleAssets, 'WIN')).toEqual([
      { id: 'win_small', path: 'audio/win_small.mp3' },
      { id: 'win_medium', path: 'audio/win_medium.mp3' },
      { id: 'win_big', path: 'audio/win_big.mp3' },
    ]);
  });

  it('handles assets without path', () => {
    const assetsNoPath: AssetMeta[] = [{ id: 'test_asset' }];
    expect(searchAssets(assetsNoPath, 'test')).toEqual([{ id: 'test_asset' }]);
    expect(searchAssets(assetsNoPath, 'path')).toEqual([]);
  });

  it('respects limit', () => {
    const results = searchAssets(sampleAssets, 'win', 1);
    expect(results).toHaveLength(1);
    expect(results[0].id).toBe('win_small');
  });

  it('does not match same asset twice', () => {
    // Asset id contains 'bonus' and path also contains 'bonus'
    const results = searchAssets(sampleAssets, 'bonus');
    expect(results).toHaveLength(2); // bonus_intro and bonus_ambient, not doubled
  });
});

describe('createDebouncedSearch', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('delays search by specified delay', async () => {
    const index = new AssetIndex(sampleAssets);
    const debouncedSearch = createDebouncedSearch(index, 100);

    const resultPromise = debouncedSearch('spin');

    // Should not have results yet
    vi.advanceTimersByTime(50);

    // Now advance past the delay
    vi.advanceTimersByTime(60);
    const results = await resultPromise;

    expect(results).toEqual([{ id: 'spin_loop', path: 'audio/spin_loop.mp3' }]);
  });

  it('cancels previous search when new query arrives', async () => {
    const index = new AssetIndex(sampleAssets);
    const debouncedSearch = createDebouncedSearch(index, 100);

    // Start first search
    const promise1 = debouncedSearch('spin');

    // Start second search before first completes
    vi.advanceTimersByTime(50);
    const promise2 = debouncedSearch('win');

    // Advance time to complete
    vi.advanceTimersByTime(150);

    // First search should resolve with empty (cancelled)
    const results1 = await promise1;
    expect(results1).toEqual([]);

    // Second search should have actual results
    const results2 = await promise2;
    expect(results2).toHaveLength(3);
  });

  it('respects limit parameter', async () => {
    const index = new AssetIndex(sampleAssets);
    const debouncedSearch = createDebouncedSearch(index, 100, 2);

    const resultPromise = debouncedSearch('win');
    vi.advanceTimersByTime(150);
    const results = await resultPromise;

    expect(results).toHaveLength(2);
  });

  it('uses default delay of 100ms', async () => {
    const index = new AssetIndex(sampleAssets);
    const debouncedSearch = createDebouncedSearch(index);

    const resultPromise = debouncedSearch('spin');

    // At 99ms, should not be resolved
    vi.advanceTimersByTime(99);

    // At 100ms+, should resolve
    vi.advanceTimersByTime(2);
    const results = await resultPromise;

    expect(results).toHaveLength(1);
  });
});
