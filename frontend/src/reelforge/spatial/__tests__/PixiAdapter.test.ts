/**
 * ReelForge Spatial System - PixiAdapter Tests
 * @module reelforge/spatial/__tests__/PixiAdapter
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  PixiAdapter,
  createPixiAdapter,
} from '../adapters/PixiAdapter';

// Mock PixiJS DisplayObject
interface MockPixiDisplayObject {
  name?: string;
  visible: boolean;
  worldVisible: boolean;
  worldAlpha: number;
  worldTransform: {
    tx: number;
    ty: number;
  };
  getBounds: () => {
    x: number;
    y: number;
    width: number;
    height: number;
  };
  getGlobalPosition?: (point?: { x: number; y: number }) => { x: number; y: number };
  children?: MockPixiDisplayObject[];
  getChildByName?: (name: string) => MockPixiDisplayObject | null;
}

// Mock PixiJS Container
interface MockPixiContainer extends MockPixiDisplayObject {
  children: MockPixiDisplayObject[];
  getChildByName?: (name: string) => MockPixiDisplayObject | null;
}

// Mock PixiJS Renderer
interface MockPixiRenderer {
  width: number;
  height: number;
  resolution: number;
  view: {
    getBoundingClientRect: () => DOMRect;
  };
}

function createMockDisplayObject(overrides: Partial<MockPixiDisplayObject> = {}): MockPixiDisplayObject {
  return {
    name: undefined,
    visible: true,
    worldVisible: true,
    worldAlpha: 1,
    worldTransform: { tx: 100, ty: 100 },
    getBounds: () => ({ x: 50, y: 50, width: 100, height: 80 }),
    ...overrides,
  };
}

function createMockContainer(children: MockPixiDisplayObject[] = []): MockPixiContainer {
  return {
    ...createMockDisplayObject(),
    children,
    getChildByName: vi.fn((name: string) => {
      return children.find(c => c.name === name) ?? null;
    }),
  };
}

function createMockRenderer(overrides: Partial<MockPixiRenderer> = {}): MockPixiRenderer {
  return {
    width: 1920,
    height: 1080,
    resolution: 1,
    view: {
      getBoundingClientRect: () => ({
        left: 0,
        top: 0,
        width: 1920,
        height: 1080,
        right: 1920,
        bottom: 1080,
        x: 0,
        y: 0,
        toJSON: () => ({}),
      }),
    },
    ...overrides,
  };
}

describe('PixiAdapter', () => {
  let adapter: PixiAdapter;
  let mockRenderer: MockPixiRenderer;
  let mockStage: MockPixiContainer;

  beforeEach(() => {
    vi.spyOn(performance, 'now').mockReturnValue(1000);

    mockRenderer = createMockRenderer();
    mockStage = createMockContainer();
    adapter = new PixiAdapter({
      stage: mockStage as any,
      renderer: mockRenderer as any,
    });
  });

  afterEach(() => {
    adapter.dispose();
    vi.restoreAllMocks();
  });

  describe('initialization', () => {
    it('creates adapter with type PIXI', () => {
      expect(adapter.type).toBe('PIXI');
    });

    it('creates adapter without options', () => {
      const emptyAdapter = new PixiAdapter();
      expect(emptyAdapter.type).toBe('PIXI');
      emptyAdapter.dispose();
    });

    it('uses renderer dimensions for viewport', () => {
      // Viewport is internal, but we can test via getFrame normalization
      const obj = createMockDisplayObject({
        name: 'centered',
        getBounds: () => ({ x: 910, y: 490, width: 100, height: 100 }),
      });
      adapter.registerAnchor('centered', obj as any);

      const frame = adapter.getFrame('centered', 0.016);
      expect(frame).not.toBeNull();
      // Center should be at (960, 540) -> normalized (0.5, 0.5)
      expect(frame!.xNorm).toBeCloseTo(0.5, 1);
      expect(frame!.yNorm).toBeCloseTo(0.5, 1);
    });

    it('handles high resolution displays', () => {
      const hiDpiRenderer = createMockRenderer({
        width: 3840,
        height: 2160,
        resolution: 2,
      });
      const hiDpiAdapter = new PixiAdapter({
        renderer: hiDpiRenderer as any,
      });

      // Viewport should be logical size (3840/2 = 1920)
      const obj = createMockDisplayObject({
        name: 'test',
        getBounds: () => ({ x: 910, y: 490, width: 100, height: 100 }),
      });
      hiDpiAdapter.registerAnchor('test', obj as any);

      const frame = hiDpiAdapter.getFrame('test', 0.016);
      expect(frame).not.toBeNull();
      hiDpiAdapter.dispose();
    });
  });

  describe('setStage', () => {
    it('sets stage and invalidates cache', () => {
      const newStage = createMockContainer();
      adapter.setStage(newStage as any);

      // Old registrations still work
      const obj = createMockDisplayObject({ name: 'test' });
      adapter.registerAnchor('test', obj as any);
      expect(adapter.resolve('test')).not.toBeNull();
    });
  });

  describe('setRenderer', () => {
    it('sets renderer and updates viewport', () => {
      const newRenderer = createMockRenderer({
        width: 2560,
        height: 1440,
        resolution: 1,
      });
      adapter.setRenderer(newRenderer as any);

      // Verify viewport updated via getFrame
      const obj = createMockDisplayObject({
        name: 'test',
        getBounds: () => ({ x: 1230, y: 670, width: 100, height: 100 }),
      });
      adapter.registerAnchor('test', obj as any);

      const frame = adapter.getFrame('test', 0.016);
      expect(frame).not.toBeNull();
      // Center at (1280, 720) / (2560, 1440) = (0.5, 0.5)
      expect(frame!.xNorm).toBeCloseTo(0.5, 1);
      expect(frame!.yNorm).toBeCloseTo(0.5, 1);
    });
  });

  describe('registerAnchor', () => {
    it('registers anchor by id', () => {
      const obj = createMockDisplayObject({ name: 'sprite1' });
      adapter.registerAnchor('sprite1', obj as any);

      const handle = adapter.resolve('sprite1');
      expect(handle).not.toBeNull();
      expect(handle!.id).toBe('sprite1');
      expect(handle!.adapterType).toBe('PIXI');
    });

    it('sets name on object if not already set', () => {
      const obj = createMockDisplayObject({ name: undefined });
      adapter.registerAnchor('mySprite', obj as any);

      expect(obj.name).toBe('mySprite');
    });

    it('does not override existing name', () => {
      const obj = createMockDisplayObject({ name: 'existingName' });
      adapter.registerAnchor('newId', obj as any);

      expect(obj.name).toBe('existingName');
    });

    it('returns all registered anchor ids', () => {
      adapter.registerAnchor('a', createMockDisplayObject() as any);
      adapter.registerAnchor('b', createMockDisplayObject() as any);
      adapter.registerAnchor('c', createMockDisplayObject() as any);

      const ids = adapter.getAllAnchorIds();
      expect(ids).toContain('a');
      expect(ids).toContain('b');
      expect(ids).toContain('c');
      expect(ids.length).toBe(3);
    });
  });

  describe('unregisterAnchor', () => {
    it('unregisters anchor by id', () => {
      const obj = createMockDisplayObject();
      adapter.registerAnchor('toRemove', obj as any);

      expect(adapter.resolve('toRemove')).not.toBeNull();

      adapter.unregisterAnchor('toRemove');

      expect(adapter.resolve('toRemove')).toBeNull();
    });

    it('removes from getAllAnchorIds', () => {
      adapter.registerAnchor('keep', createMockDisplayObject() as any);
      adapter.registerAnchor('remove', createMockDisplayObject() as any);

      adapter.unregisterAnchor('remove');

      const ids = adapter.getAllAnchorIds();
      expect(ids).toContain('keep');
      expect(ids).not.toContain('remove');
    });
  });

  describe('resolve', () => {
    it('resolves registered anchor', () => {
      const obj = createMockDisplayObject();
      adapter.registerAnchor('registered', obj as any);

      const handle = adapter.resolve('registered');
      expect(handle).not.toBeNull();
      expect(handle!.element).toBe(obj);
    });

    it('resolves by name from stage children', () => {
      const child = createMockDisplayObject({ name: 'childSprite' });
      mockStage.children = [child];

      const handle = adapter.resolve('childSprite');
      expect(handle).not.toBeNull();
      expect(handle!.element).toBe(child);
    });

    it('resolves using getChildByName if available', () => {
      const child = createMockDisplayObject({ name: 'namedChild' });
      mockStage.getChildByName = vi.fn(() => child);

      const handle = adapter.resolve('namedChild');
      expect(handle).not.toBeNull();
      expect(mockStage.getChildByName).toHaveBeenCalledWith('namedChild');
    });

    it('searches recursively in nested containers', () => {
      const deepChild = createMockDisplayObject({ name: 'deepSprite' });
      const nestedContainer = createMockContainer([deepChild]);
      nestedContainer.name = 'container';
      mockStage.children = [nestedContainer as any];

      const handle = adapter.resolve('deepSprite');
      expect(handle).not.toBeNull();
      expect(handle!.element).toBe(deepChild);
    });

    it('returns null for unknown anchor', () => {
      const handle = adapter.resolve('nonexistent');
      expect(handle).toBeNull();
    });

    it('prefers registered anchor over stage search', () => {
      const registered = createMockDisplayObject({ name: 'mySprite' });
      const stageChild = createMockDisplayObject({ name: 'mySprite' });
      mockStage.children = [stageChild];

      adapter.registerAnchor('mySprite', registered as any);

      const handle = adapter.resolve('mySprite');
      expect(handle!.element).toBe(registered);
    });

    it('caches resolved anchors', () => {
      const child = createMockDisplayObject({ name: 'cached' });
      mockStage.children = [child];
      mockStage.getChildByName = vi.fn(() => child);

      adapter.resolve('cached');
      adapter.resolve('cached');
      adapter.resolve('cached');

      // Should only search once due to cache
      expect(mockStage.getChildByName).toHaveBeenCalledTimes(1);
    });
  });

  describe('getFrame', () => {
    it('returns frame with normalized coordinates', () => {
      const obj = createMockDisplayObject({
        name: 'test',
        getBounds: () => ({ x: 460, y: 240, width: 100, height: 100 }),
      });
      adapter.registerAnchor('test', obj as any);

      const frame = adapter.getFrame('test', 0.016);
      expect(frame).not.toBeNull();

      // Center at (510, 290) / (1920, 1080)
      expect(frame!.xNorm).toBeCloseTo(510 / 1920, 2);
      expect(frame!.yNorm).toBeCloseTo(290 / 1080, 2);
      expect(frame!.wNorm).toBeCloseTo(100 / 1920, 3);
      expect(frame!.hNorm).toBeCloseTo(100 / 1080, 3);
    });

    it('returns null for unknown anchor', () => {
      const frame = adapter.getFrame('nonexistent', 0.016);
      expect(frame).toBeNull();
    });

    it('calculates velocity from previous frame', () => {
      const obj = createMockDisplayObject({
        name: 'moving',
        getBounds: () => ({ x: 100, y: 100, width: 50, height: 50 }),
      });
      adapter.registerAnchor('moving', obj as any);

      // First frame
      const frame1 = adapter.getFrame('moving', 0.016);
      expect(frame1!.vxNormPerS).toBe(0);
      expect(frame1!.vyNormPerS).toBe(0);

      // Move object
      obj.getBounds = () => ({ x: 200, y: 100, width: 50, height: 50 });
      vi.spyOn(performance, 'now').mockReturnValue(1016);

      // Second frame with dt = 0.016
      const frame2 = adapter.getFrame('moving', 0.016, frame1!);
      expect(frame2!.vxNormPerS).toBeGreaterThan(0);
    });

    it('includes timestamp', () => {
      const obj = createMockDisplayObject({ name: 'test' });
      adapter.registerAnchor('test', obj as any);

      const frame = adapter.getFrame('test', 0.016);
      expect(frame!.timestamp).toBe(1000);
    });
  });

  describe('visibility detection', () => {
    it('detects visible objects', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        worldAlpha: 1,
      });
      adapter.registerAnchor('visible', obj as any);

      const frame = adapter.getFrame('visible', 0.016);
      expect(frame!.visible).toBe(true);
    });

    it('detects invisible objects (visible=false)', () => {
      const obj = createMockDisplayObject({
        visible: false,
        worldVisible: false,
      });
      adapter.registerAnchor('invisible', obj as any);

      const frame = adapter.getFrame('invisible', 0.016);
      expect(frame!.visible).toBe(false);
    });

    it('detects invisible objects (worldVisible=false)', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: false,
      });
      adapter.registerAnchor('parentHidden', obj as any);

      const frame = adapter.getFrame('parentHidden', 0.016);
      expect(frame!.visible).toBe(false);
    });

    it('detects invisible objects (worldAlpha=0)', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        worldAlpha: 0,
      });
      adapter.registerAnchor('transparent', obj as any);

      const frame = adapter.getFrame('transparent', 0.016);
      expect(frame!.visible).toBe(false);
    });

    it('detects objects outside viewport', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        worldAlpha: 1,
        getBounds: () => ({ x: -200, y: -200, width: 100, height: 100 }),
      });
      adapter.registerAnchor('offscreen', obj as any);

      const frame = adapter.getFrame('offscreen', 0.016);
      expect(frame!.visible).toBe(false);
    });
  });

  describe('bounds handling', () => {
    it('handles invalid bounds gracefully', () => {
      const obj = createMockDisplayObject({
        name: 'invalid',
        getBounds: () => ({ x: NaN, y: 0, width: 100, height: 100 }),
      });
      adapter.registerAnchor('invalid', obj as any);

      const frame = adapter.getFrame('invalid', 0.016);
      expect(frame).toBeNull();
    });

    it('handles zero-size bounds', () => {
      const obj = createMockDisplayObject({
        name: 'empty',
        getBounds: () => ({ x: 100, y: 100, width: 0, height: 0 }),
      });
      adapter.registerAnchor('empty', obj as any);

      const frame = adapter.getFrame('empty', 0.016);
      expect(frame).toBeNull();
    });

    it('handles getBounds throwing', () => {
      const obj = createMockDisplayObject({
        name: 'throws',
        getBounds: () => { throw new Error('Bounds error'); },
      });
      adapter.registerAnchor('throws', obj as any);

      const frame = adapter.getFrame('throws', 0.016);
      expect(frame).toBeNull();
    });
  });

  describe('getGlobalPosition', () => {
    it('uses getGlobalPosition if available', () => {
      const obj = createMockDisplayObject({
        name: 'withGlobal',
        getGlobalPosition: () => ({ x: 500, y: 300 }),
      });
      adapter.registerAnchor('withGlobal', obj as any);

      const pos = adapter.getGlobalPosition('withGlobal');
      expect(pos).toEqual({ x: 500, y: 300 });
    });

    it('falls back to bounds center', () => {
      const obj = createMockDisplayObject({
        name: 'noBlobal',
        getBounds: () => ({ x: 400, y: 200, width: 200, height: 100 }),
      });
      adapter.registerAnchor('noGlobal', obj as any);

      const pos = adapter.getGlobalPosition('noGlobal');
      expect(pos).toEqual({ x: 500, y: 250 });
    });

    it('returns null for unknown anchor', () => {
      const pos = adapter.getGlobalPosition('nonexistent');
      expect(pos).toBeNull();
    });
  });

  describe('pixiToPage', () => {
    it('converts pixi coords to page coords', () => {
      const renderer = createMockRenderer();
      renderer.view.getBoundingClientRect = () => ({
        left: 100,
        top: 50,
        width: 1920,
        height: 1080,
        right: 2020,
        bottom: 1130,
        x: 100,
        y: 50,
        toJSON: () => ({}),
      });

      const offsetAdapter = new PixiAdapter({
        renderer: renderer as any,
      });

      const page = offsetAdapter.pixiToPage(500, 300);
      expect(page).toEqual({ x: 600, y: 350 });

      offsetAdapter.dispose();
    });
  });

  describe('confidence calculation', () => {
    it('high confidence for visible, large objects', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        worldAlpha: 1,
        getBounds: () => ({ x: 0, y: 0, width: 500, height: 400 }),
      });
      adapter.registerAnchor('large', obj as any);

      const frame = adapter.getFrame('large', 0.016);
      expect(frame!.confidence).toBeGreaterThan(0.7);
    });

    it('lower confidence for small objects', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        worldAlpha: 1,
        getBounds: () => ({ x: 100, y: 100, width: 10, height: 10 }),
      });
      adapter.registerAnchor('small', obj as any);

      const frame = adapter.getFrame('small', 0.016);
      expect(frame!.confidence).toBeLessThan(0.8);
    });

    it('stability bonus from previous frame', () => {
      const obj = createMockDisplayObject({
        visible: true,
        worldVisible: true,
        getBounds: () => ({ x: 100, y: 100, width: 100, height: 100 }),
      });
      adapter.registerAnchor('stable', obj as any);

      const frame1 = adapter.getFrame('stable', 0.016);
      const frame2 = adapter.getFrame('stable', 0.016, frame1!);

      expect(frame2!.confidence).toBeGreaterThan(frame1!.confidence);
    });
  });

  describe('dispose', () => {
    it('clears registry', () => {
      adapter.registerAnchor('a', createMockDisplayObject() as any);
      adapter.registerAnchor('b', createMockDisplayObject() as any);

      adapter.dispose();

      expect(adapter.getAllAnchorIds()).toHaveLength(0);
    });

    it('clears cache', () => {
      adapter.registerAnchor('cached', createMockDisplayObject() as any);
      adapter.resolve('cached');

      adapter.dispose();

      expect(adapter.resolve('cached')).toBeNull();
    });
  });
});

describe('createPixiAdapter', () => {
  it('creates adapter with defaults', () => {
    const adapter = createPixiAdapter();
    expect(adapter).toBeInstanceOf(PixiAdapter);
    expect(adapter.type).toBe('PIXI');
    adapter.dispose();
  });

  it('creates adapter with options', () => {
    const stage = createMockContainer();
    const renderer = createMockRenderer();

    const adapter = createPixiAdapter({
      stage: stage as any,
      renderer: renderer as any,
      cacheTTL: 50,
    });

    expect(adapter).toBeInstanceOf(PixiAdapter);
    adapter.dispose();
  });
});
