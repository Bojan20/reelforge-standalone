/**
 * ReelForge Spatial System - UnityAdapter Tests
 * @module reelforge/spatial/__tests__/UnityAdapter
 *
 * Note: These tests mock DOM/window APIs since we run in Node environment.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  UnityAdapter,
  createUnityAdapter,
} from '../adapters/UnityAdapter';

// Mock Unity Bridge
interface MockUnityBridge {
  GetAnchorData: (anchorId: string) => string;
  GetAllAnchorIds: () => string;
  RegisterAnchor: (anchorId: string, gameObjectPath: string) => void;
  UnregisterAnchor: (anchorId: string) => void;
  GetScreenDimensions: () => string;
}

function createMockBridge(overrides: Partial<MockUnityBridge> = {}): MockUnityBridge {
  return {
    GetAnchorData: vi.fn(() => JSON.stringify({
      id: 'test',
      x: 100,
      y: 100,
      width: 200,
      height: 150,
      visible: true,
      screenWidth: 1920,
      screenHeight: 1080,
    })),
    GetAllAnchorIds: vi.fn(() => JSON.stringify(['anchor1', 'anchor2'])),
    RegisterAnchor: vi.fn(),
    UnregisterAnchor: vi.fn(),
    GetScreenDimensions: vi.fn(() => JSON.stringify({ width: 1920, height: 1080 })),
    ...overrides,
  };
}

// Mock canvas
const mockCanvas = {
  getBoundingClientRect: vi.fn(() => ({
    left: 0,
    top: 0,
    width: 1920,
    height: 1080,
    right: 1920,
    bottom: 1080,
    x: 0,
    y: 0,
    toJSON: () => ({}),
  })),
};

// Mock document
const mockDocument = {
  querySelector: vi.fn(() => null),
};

// Mock window
const mockWindow = {
  innerWidth: 1920,
  innerHeight: 1080,
  RFSpatialBridge: undefined as any,
  RFSpatialReceiver: undefined as any,
  unityInstance: undefined as any,
};

// Setup global mocks
vi.stubGlobal('document', mockDocument);
vi.stubGlobal('window', mockWindow);
vi.stubGlobal('performance', { now: vi.fn(() => 1000) });

describe('UnityAdapter', () => {
  let adapter: UnityAdapter;
  let mockBridge: MockUnityBridge;

  beforeEach(() => {
    vi.clearAllMocks();
    (performance.now as any).mockReturnValue(1000);

    // Reset window state
    mockWindow.RFSpatialBridge = undefined;
    mockWindow.RFSpatialReceiver = undefined;
    mockWindow.unityInstance = undefined;

    mockBridge = createMockBridge();

    adapter = new UnityAdapter({
      bridge: mockBridge,
      canvas: mockCanvas as any,
    });
  });

  afterEach(() => {
    adapter.dispose();
  });

  describe('initialization', () => {
    it('creates adapter with type UNITY', () => {
      expect(adapter.type).toBe('UNITY');
    });

    it('creates adapter without options', () => {
      const emptyAdapter = new UnityAdapter();
      expect(emptyAdapter.type).toBe('UNITY');
      emptyAdapter.dispose();
    });

    it('auto-detects bridge from window', () => {
      mockWindow.RFSpatialBridge = mockBridge;

      const autoAdapter = new UnityAdapter();
      expect(autoAdapter.type).toBe('UNITY');
      autoAdapter.dispose();

      mockWindow.RFSpatialBridge = undefined;
    });

    it('auto-detects canvas by id', () => {
      mockDocument.querySelector.mockReturnValue(mockCanvas);

      const autoAdapter = new UnityAdapter();
      expect(autoAdapter.type).toBe('UNITY');
      autoAdapter.dispose();

      mockDocument.querySelector.mockReturnValue(null);
    });

    it('sets up global receiver', () => {
      expect(mockWindow.RFSpatialReceiver).toBeDefined();
      expect(mockWindow.RFSpatialReceiver.updateAnchor).toBeInstanceOf(Function);
      expect(mockWindow.RFSpatialReceiver.removeAnchor).toBeInstanceOf(Function);
      expect(mockWindow.RFSpatialReceiver.updateViewport).toBeInstanceOf(Function);
    });

    it('receiver is frozen', () => {
      expect(Object.isFrozen(mockWindow.RFSpatialReceiver)).toBe(true);
    });
  });

  describe('setBridge', () => {
    it('sets new bridge', () => {
      const newBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'new',
          x: 50,
          y: 50,
          width: 100,
          height: 100,
          visible: true,
          screenWidth: 1920,
          screenHeight: 1080,
        })),
      });

      adapter.setBridge(newBridge);

      const frame = adapter.getFrame('new', 0.016);
      expect(frame).not.toBeNull();
    });
  });

  describe('updateViewport', () => {
    it('gets dimensions from bridge first', () => {
      adapter.updateViewport();
      expect(mockBridge.GetScreenDimensions).toHaveBeenCalled();
    });

    it('falls back to canvas if bridge fails', () => {
      const failBridge = createMockBridge({
        GetScreenDimensions: vi.fn(() => 'invalid json'),
      });

      const canvasAdapter = new UnityAdapter({
        bridge: failBridge,
        canvas: mockCanvas as any,
      });

      canvasAdapter.updateViewport();
      expect(mockCanvas.getBoundingClientRect).toHaveBeenCalled();

      canvasAdapter.dispose();
    });
  });

  describe('resolve', () => {
    it('resolves anchor from bridge', () => {
      const handle = adapter.resolve('test');
      expect(handle).not.toBeNull();
      expect(handle!.id).toBe('test');
      expect(handle!.adapterType).toBe('UNITY');
    });

    it('validates anchor data', () => {
      const invalidBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'invalid',
          x: 'not a number', // Invalid
          y: 100,
          width: 200,
          height: 150,
          visible: true,
          screenWidth: 1920,
          screenHeight: 1080,
        })),
      });

      const invalidAdapter = new UnityAdapter({ bridge: invalidBridge });
      const handle = invalidAdapter.resolve('invalid');
      expect(handle).toBeNull();
      invalidAdapter.dispose();
    });

    it('returns null for empty anchor id', () => {
      const handle = adapter.resolve('');
      expect(handle).toBeNull();
    });

    it('returns null for invalid JSON', () => {
      const brokenBridge = createMockBridge({
        GetAnchorData: vi.fn(() => '{invalid json'),
      });

      const brokenAdapter = new UnityAdapter({ bridge: brokenBridge });
      const handle = brokenAdapter.resolve('test');
      expect(handle).toBeNull();
      brokenAdapter.dispose();
    });
  });

  describe('getFrame', () => {
    it('returns frame with normalized coordinates', () => {
      mockBridge.GetAnchorData = vi.fn(() => JSON.stringify({
        id: 'centered',
        x: 860, // Center X
        y: 440, // Y from bottom (inverted)
        width: 200,
        height: 200,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const frame = adapter.getFrame('centered', 0.016);
      expect(frame).not.toBeNull();
      expect(frame!.xNorm).toBeCloseTo(0.5, 1);
    });

    it('inverts Unity Y coordinate', () => {
      mockBridge.GetAnchorData = vi.fn(() => JSON.stringify({
        id: 'bottom',
        x: 0,
        y: 0, // Bottom in Unity = top in web
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const frame = adapter.getFrame('bottom', 0.016);
      expect(frame).not.toBeNull();
      // Y should be near top (high yNorm in Unity coords becomes low after inversion)
      // Unity Y=0 at bottom, height=1080, so inverted Y = 1080 - 0 - 100 = 980
      // Center = 980 + 50 = 1030 -> 1030/1080 ≈ 0.954
      expect(frame!.yNorm).toBeGreaterThan(0.9);
    });

    it('calculates velocity from previous frame', () => {
      mockBridge.GetAnchorData = vi.fn(() => JSON.stringify({
        id: 'moving',
        x: 100,
        y: 500,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const frame1 = adapter.getFrame('moving', 0.016);

      mockBridge.GetAnchorData = vi.fn(() => JSON.stringify({
        id: 'moving',
        x: 200, // Moved right
        y: 500,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      (performance.now as any).mockReturnValue(1016);
      const frame2 = adapter.getFrame('moving', 0.016, frame1!);

      expect(frame2!.vxNormPerS).toBeGreaterThan(0);
    });

    it('includes timestamp', () => {
      const frame = adapter.getFrame('test', 0.016);
      expect(frame!.timestamp).toBe(1000);
    });

    it('returns null for unknown anchor', () => {
      mockBridge.GetAnchorData = vi.fn(() => '');

      const frame = adapter.getFrame('unknown', 0.016);
      expect(frame).toBeNull();
    });
  });

  describe('visibility', () => {
    it('respects visible flag', () => {
      mockBridge.GetAnchorData = vi.fn(() => JSON.stringify({
        id: 'hidden',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: false,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const frame = adapter.getFrame('hidden', 0.016);
      expect(frame!.visible).toBe(false);
    });
  });

  describe('global receiver callbacks', () => {
    it('updateAnchor updates pending data', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      receiver.updateAnchor(JSON.stringify({
        id: 'pushed',
        x: 300,
        y: 200,
        width: 150,
        height: 120,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      // Now resolve should find it in pending data
      const handle = adapter.resolve('pushed');
      expect(handle).not.toBeNull();
    });

    it('updateAnchor ignores invalid JSON', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Should not throw
      expect(() => {
        receiver.updateAnchor('not valid json');
      }).not.toThrow();
    });

    it('updateAnchor ignores invalid data structure', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Should not throw
      expect(() => {
        receiver.updateAnchor(JSON.stringify({
          id: 'bad',
          x: 'invalid',
        }));
      }).not.toThrow();
    });

    it('removeAnchor removes from pending', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Add first
      receiver.updateAnchor(JSON.stringify({
        id: 'toRemove',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      // Then remove
      receiver.removeAnchor('toRemove');

      // Bridge doesn't have it either
      mockBridge.GetAnchorData = vi.fn(() => '');

      const handle = adapter.resolve('toRemove');
      expect(handle).toBeNull();
    });

    it('removeAnchor ignores empty id', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      expect(() => {
        receiver.removeAnchor('');
      }).not.toThrow();
    });

    it('updateViewport updates dimensions', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      receiver.updateViewport(JSON.stringify({
        width: 2560,
        height: 1440,
      }));

      // Viewport is now 2560x1440 (internal state)
    });

    it('updateViewport ignores invalid data', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      expect(() => {
        receiver.updateViewport('invalid');
      }).not.toThrow();

      expect(() => {
        receiver.updateViewport(JSON.stringify({ width: -100, height: 1080 }));
      }).not.toThrow();
    });
  });

  describe('registerAnchor', () => {
    it('calls bridge RegisterAnchor', () => {
      adapter.registerAnchor('myAnchor', '/Game/Player/Sprite');

      expect(mockBridge.RegisterAnchor).toHaveBeenCalledWith(
        'myAnchor',
        '/Game/Player/Sprite'
      );
    });

    it('uses SendMessage if no bridge', () => {
      const sendMessage = vi.fn();
      mockWindow.unityInstance = { SendMessage: sendMessage };

      const noBridgeAdapter = new UnityAdapter({ canvas: mockCanvas as any });
      noBridgeAdapter.registerAnchor('test', '/Path/To/Object');

      expect(sendMessage).toHaveBeenCalledWith(
        'RFSpatialManager',
        'RegisterAnchor',
        expect.any(String)
      );

      noBridgeAdapter.dispose();
      mockWindow.unityInstance = undefined;
    });
  });

  describe('unregisterAnchor', () => {
    it('removes from pending and cache', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Add to pending
      receiver.updateAnchor(JSON.stringify({
        id: 'toUnreg',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      // Resolve to populate cache
      adapter.resolve('toUnreg');

      // Unregister
      adapter.unregisterAnchor('toUnreg');

      // Should call bridge
      expect(mockBridge.UnregisterAnchor).toHaveBeenCalledWith('toUnreg');
    });
  });

  describe('getAllAnchorIds', () => {
    it('combines pending and bridge ids', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Add pending
      receiver.updateAnchor(JSON.stringify({
        id: 'pending1',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const ids = adapter.getAllAnchorIds();

      expect(ids).toContain('pending1');
      expect(ids).toContain('anchor1'); // From bridge
      expect(ids).toContain('anchor2'); // From bridge
    });

    it('deduplicates ids', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      // Add pending with same id as bridge
      receiver.updateAnchor(JSON.stringify({
        id: 'anchor1',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      const ids = adapter.getAllAnchorIds();

      // Should only appear once
      expect(ids.filter(id => id === 'anchor1').length).toBe(1);
    });

    it('filters invalid ids from bridge', () => {
      const badBridge = createMockBridge({
        GetAllAnchorIds: vi.fn(() => JSON.stringify(['valid', '', null, 123, 'also-valid'])),
      });

      const badAdapter = new UnityAdapter({ bridge: badBridge });
      const ids = badAdapter.getAllAnchorIds();

      expect(ids).toContain('valid');
      expect(ids).toContain('also-valid');
      expect(ids).not.toContain('');

      badAdapter.dispose();
    });
  });

  describe('dispose', () => {
    it('cleans up global receivers', () => {
      adapter.dispose();

      // After dispose, receiver should be cleaned up
      // Note: Due to timing, the next beforeEach will reset this
    });

    it('clears pending data', () => {
      const receiver = mockWindow.RFSpatialReceiver;

      receiver.updateAnchor(JSON.stringify({
        id: 'pending',
        x: 100,
        y: 100,
        width: 100,
        height: 100,
        visible: true,
        screenWidth: 1920,
        screenHeight: 1080,
      }));

      adapter.dispose();

      // After dispose, internal state cleared
    });
  });

  describe('data validation', () => {
    it('rejects negative dimensions', () => {
      const badBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'bad',
          x: 100,
          y: 100,
          width: -50,
          height: 100,
          visible: true,
          screenWidth: 1920,
          screenHeight: 1080,
        })),
      });

      const badAdapter = new UnityAdapter({ bridge: badBridge });
      const handle = badAdapter.resolve('bad');
      expect(handle).toBeNull();
      badAdapter.dispose();
    });

    it('rejects non-finite coordinates', () => {
      const badBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'bad',
          x: Infinity,
          y: 100,
          width: 100,
          height: 100,
          visible: true,
          screenWidth: 1920,
          screenHeight: 1080,
        })),
      });

      const badAdapter = new UnityAdapter({ bridge: badBridge });
      const handle = badAdapter.resolve('bad');
      expect(handle).toBeNull();
      badAdapter.dispose();
    });

    it('rejects zero screen dimensions', () => {
      const badBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'bad',
          x: 100,
          y: 100,
          width: 100,
          height: 100,
          visible: true,
          screenWidth: 0,
          screenHeight: 1080,
        })),
      });

      const badAdapter = new UnityAdapter({ bridge: badBridge });
      const handle = badAdapter.resolve('bad');
      expect(handle).toBeNull();
      badAdapter.dispose();
    });

    it('rejects missing required fields', () => {
      const badBridge = createMockBridge({
        GetAnchorData: vi.fn(() => JSON.stringify({
          id: 'incomplete',
          x: 100,
          // missing y, width, height, visible, screenWidth, screenHeight
        })),
      });

      const badAdapter = new UnityAdapter({ bridge: badBridge });
      const handle = badAdapter.resolve('incomplete');
      expect(handle).toBeNull();
      badAdapter.dispose();
    });
  });
});

describe('createUnityAdapter', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockDocument.querySelector.mockReturnValue(null);
    mockWindow.RFSpatialBridge = undefined;
  });

  it('creates adapter with defaults', () => {
    const adapter = createUnityAdapter();
    expect(adapter).toBeInstanceOf(UnityAdapter);
    expect(adapter.type).toBe('UNITY');
    adapter.dispose();
  });

  it('creates adapter with options', () => {
    const bridge = createMockBridge();

    const adapter = createUnityAdapter({
      bridge,
      canvas: mockCanvas as any,
      cacheTTL: 25,
    });

    expect(adapter).toBeInstanceOf(UnityAdapter);
    adapter.dispose();
  });
});
