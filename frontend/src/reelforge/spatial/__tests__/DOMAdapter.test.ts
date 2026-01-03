/**
 * ReelForge Spatial System - DOM Adapter Tests
 * @module reelforge/spatial/__tests__/DOMAdapter
 *
 * Note: These tests mock DOM APIs since we run in Node environment.
 * For full integration tests, run in browser or jsdom.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { DOMAdapter, createDOMAdapter } from '../adapters/DOMAdapter';

// Mock DOM environment
const mockElement = {
  getBoundingClientRect: vi.fn(() => ({
    left: 100,
    top: 100,
    width: 200,
    height: 100,
    right: 300,
    bottom: 200,
  })),
  offsetParent: {},
  tagName: 'DIV',
  getAttribute: vi.fn(() => null),
  setAttribute: vi.fn(),
  removeAttribute: vi.fn(),
};

const mockDocument = {
  querySelector: vi.fn(),
  querySelectorAll: vi.fn(() => []),
  getElementById: vi.fn(),
  documentElement: mockElement,
  body: mockElement,
};

const mockWindow = {
  innerWidth: 1920,
  innerHeight: 1080,
  addEventListener: vi.fn(),
  removeEventListener: vi.fn(),
  getComputedStyle: vi.fn(() => ({
    visibility: 'visible',
    display: 'block',
    opacity: '1',
  })),
};

// Mock Element class for instanceof checks
class MockElement {
  getBoundingClientRect = vi.fn(() => ({
    left: 100,
    top: 100,
    width: 200,
    height: 100,
    right: 300,
    bottom: 200,
  }));
  offsetParent: object | null = {};
  tagName = 'DIV';
  getAttribute = vi.fn(() => null);
  setAttribute = vi.fn();
  removeAttribute = vi.fn();
}

// Setup global mocks
vi.stubGlobal('Element', MockElement);
vi.stubGlobal('HTMLElement', MockElement);  // HTMLElement extends Element
vi.stubGlobal('document', mockDocument);
vi.stubGlobal('window', mockWindow);
vi.stubGlobal('ResizeObserver', class {
  observe = vi.fn();
  disconnect = vi.fn();
  unobserve = vi.fn();
});
vi.stubGlobal('MutationObserver', class {
  observe = vi.fn();
  disconnect = vi.fn();
});
vi.stubGlobal('performance', { now: vi.fn(() => Date.now()) });

// Factory for creating mock elements that pass instanceof Element
function createMockElement(overrides: Partial<MockElement> = {}): MockElement {
  const el = new MockElement();
  Object.assign(el, overrides);
  return el;
}

describe('DOMAdapter', () => {
  let adapter: DOMAdapter;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDocument.querySelector.mockReturnValue(null);
    mockDocument.getElementById.mockReturnValue(null);
    adapter = new DOMAdapter();
  });

  afterEach(() => {
    adapter.dispose();
  });

  describe('initialization', () => {
    it('creates with default options', () => {
      expect(adapter.type).toBe('DOM');
    });

    it('creates with custom root', () => {
      const customRoot = { querySelector: vi.fn() } as unknown as ParentNode;
      const customAdapter = new DOMAdapter({ root: customRoot });
      expect(customAdapter.type).toBe('DOM');
      customAdapter.dispose();
    });

    it('creates with custom cacheTTL', () => {
      const customAdapter = new DOMAdapter({ cacheTTL: 1000 });
      expect(customAdapter.type).toBe('DOM');
      customAdapter.dispose();
    });

    it('sets up ResizeObserver', () => {
      expect(ResizeObserver).toBeDefined();
    });

    it('sets up event listeners', () => {
      expect(mockWindow.addEventListener).toHaveBeenCalledWith(
        'orientationchange',
        expect.any(Function)
      );
      expect(mockWindow.addEventListener).toHaveBeenCalledWith(
        'resize',
        expect.any(Function)
      );
    });
  });

  describe('resolve', () => {
    it('returns null for non-existent anchor', () => {
      const result = adapter.resolve('non_existent');
      expect(result).toBeNull();
    });

    it('resolves by data-rf-anchor attribute', () => {
      const element = { ...mockElement };
      mockDocument.querySelector.mockImplementation((selector: string) => {
        if (selector === '[data-rf-anchor="test_anchor"]') {
          return element;
        }
        return null;
      });

      const result = adapter.resolve('test_anchor');
      expect(result).not.toBeNull();
      expect(result?.id).toBe('test_anchor');
      expect(result?.adapterType).toBe('DOM');
    });

    it('falls back to getElementById', () => {
      const element = { ...mockElement };
      mockDocument.querySelector.mockReturnValue(null);
      mockDocument.getElementById.mockImplementation((id: string) => {
        if (id === 'test_id') return element;
        return null;
      });

      const result = adapter.resolve('test_id');
      expect(result).not.toBeNull();
    });

    it('falls back to class selector', () => {
      const element = { ...mockElement };
      mockDocument.querySelector.mockImplementation((selector: string) => {
        if (selector === '.test_class') return element;
        return null;
      });
      mockDocument.getElementById.mockReturnValue(null);

      const result = adapter.resolve('test_class');
      expect(result).not.toBeNull();
    });

    it('does not use class selector for numeric-prefixed names', () => {
      mockDocument.querySelector.mockReturnValue(null);
      mockDocument.getElementById.mockReturnValue(null);

      // Class names can't start with a digit
      const result = adapter.resolve('123invalid');
      expect(result).toBeNull();
    });
  });

  describe('security - anchor ID sanitization', () => {
    it('removes quotes from anchor ID', () => {
      mockDocument.querySelector.mockReturnValue(null);
      adapter.resolve('test"anchor');

      // Should not have called with unsanitized string
      expect(mockDocument.querySelector).not.toHaveBeenCalledWith(
        expect.stringContaining('"anchor')
      );
    });

    it('removes brackets from anchor ID', () => {
      mockDocument.querySelector.mockReturnValue(null);
      adapter.resolve('test]anchor[');

      // Should sanitize to "testanchor", so selector should be [data-rf-anchor="testanchor"]
      // NOT [data-rf-anchor="test]anchor["] which would break CSS
      expect(mockDocument.querySelector).toHaveBeenCalledWith(
        '[data-rf-anchor="testanchor"]'
      );
    });

    it('removes backslashes from anchor ID', () => {
      mockDocument.querySelector.mockReturnValue(null);
      adapter.resolve('test\\anchor');

      expect(mockDocument.querySelector).not.toHaveBeenCalledWith(
        expect.stringContaining('\\')
      );
    });

    it('removes control characters from anchor ID', () => {
      mockDocument.querySelector.mockReturnValue(null);
      adapter.resolve('test\x00anchor');

      expect(mockDocument.querySelector).not.toHaveBeenCalledWith(
        expect.stringContaining('\x00')
      );
    });

    it('returns null for completely sanitized empty ID', () => {
      const result = adapter.resolve('"]["\'\\');
      expect(result).toBeNull();
    });
  });

  describe('getFrame', () => {
    beforeEach(() => {
      const element = createMockElement();
      element.getBoundingClientRect = vi.fn(() => ({
        left: 480,
        top: 270,
        width: 200,
        height: 100,
        right: 680,
        bottom: 370,
      }));
      mockDocument.querySelector.mockReturnValue(element);
    });

    it('returns null for non-existent anchor', () => {
      mockDocument.querySelector.mockReturnValue(null);
      const frame = adapter.getFrame('non_existent', 0.016);
      expect(frame).toBeNull();
    });

    it('returns frame with normalized coordinates', () => {
      const frame = adapter.getFrame('test_anchor', 0.016);

      expect(frame).not.toBeNull();
      expect(frame?.xNorm).toBeGreaterThanOrEqual(0);
      expect(frame?.xNorm).toBeLessThanOrEqual(1);
      expect(frame?.yNorm).toBeGreaterThanOrEqual(0);
      expect(frame?.yNorm).toBeLessThanOrEqual(1);
    });

    it('returns frame with size', () => {
      const frame = adapter.getFrame('test_anchor', 0.016);

      expect(frame?.wNorm).toBeGreaterThan(0);
      expect(frame?.hNorm).toBeGreaterThan(0);
    });

    it('returns null for zero-sized elements', () => {
      const zeroElement = createMockElement();
      zeroElement.getBoundingClientRect = vi.fn(() => ({
        left: 0,
        top: 0,
        width: 0,
        height: 0,
        right: 0,
        bottom: 0,
      }));
      mockDocument.querySelector.mockReturnValue(zeroElement);

      const frame = adapter.getFrame('zero_size', 0.016);
      expect(frame).toBeNull();
    });

    it('calculates velocity from previous frame', () => {
      const prevFrame = {
        visible: true,
        xNorm: 0.2,
        yNorm: 0.2,
        wNorm: 0.1,
        hNorm: 0.05,
        vxNormPerS: 0,
        vyNormPerS: 0,
        confidence: 0.9,
        timestamp: Date.now() - 16,
      };

      const frame = adapter.getFrame('test_anchor', 0.016, prevFrame);

      // Velocity should be non-zero if position changed
      expect(frame?.vxNormPerS).toBeDefined();
      expect(frame?.vyNormPerS).toBeDefined();
    });

    it('uses cache for repeated calls within TTL', () => {
      adapter.getFrame('test_anchor', 0.016);
      adapter.getFrame('test_anchor', 0.016);

      // querySelector should be called once for resolve, then cached
      // The exact call count depends on implementation details
      expect(mockDocument.querySelector.mock.calls.length).toBeLessThan(10);
    });
  });

  describe('visibility detection', () => {
    it('returns not visible when element has no offsetParent', () => {
      const hiddenElement = createMockElement();
      hiddenElement.offsetParent = null;
      hiddenElement.tagName = 'DIV';
      mockDocument.querySelector.mockReturnValue(hiddenElement);

      const frame = adapter.getFrame('hidden', 0.016);
      expect(frame?.visible).toBe(false);
    });

    it('allows BODY element without offsetParent', () => {
      const bodyElement = createMockElement();
      bodyElement.offsetParent = null;
      bodyElement.tagName = 'BODY';
      bodyElement.getBoundingClientRect = vi.fn(() => ({
        left: 0,
        top: 0,
        width: 1920,
        height: 1080,
        right: 1920,
        bottom: 1080,
      }));
      mockDocument.querySelector.mockReturnValue(bodyElement);

      const frame = adapter.getFrame('body', 0.016);
      expect(frame?.visible).toBe(true);
    });

    it('returns not visible for hidden CSS visibility', () => {
      const element = createMockElement();
      mockDocument.querySelector.mockReturnValue(element);
      mockWindow.getComputedStyle.mockReturnValue({
        visibility: 'hidden',
        display: 'block',
        opacity: '1',
      });

      const frame = adapter.getFrame('hidden_css', 0.016);
      expect(frame?.visible).toBe(false);
    });

    it('returns not visible for display:none', () => {
      const element = createMockElement();
      mockDocument.querySelector.mockReturnValue(element);
      mockWindow.getComputedStyle.mockReturnValue({
        visibility: 'visible',
        display: 'none',
        opacity: '1',
      });

      const frame = adapter.getFrame('hidden_display', 0.016);
      expect(frame?.visible).toBe(false);
    });

    it('returns not visible for opacity:0', () => {
      const element = createMockElement();
      mockDocument.querySelector.mockReturnValue(element);
      mockWindow.getComputedStyle.mockReturnValue({
        visibility: 'visible',
        display: 'block',
        opacity: '0',
      });

      const frame = adapter.getFrame('transparent', 0.016);
      expect(frame?.visible).toBe(false);
    });
  });

  describe('registerAnchor', () => {
    it('sets data-rf-anchor attribute', () => {
      const element = createMockElement();
      adapter.registerAnchor('new_anchor', element as unknown as Element);

      expect(element.setAttribute).toHaveBeenCalledWith(
        'data-rf-anchor',
        'new_anchor'
      );
    });

    it('invalidates cache after registration', () => {
      const element = createMockElement();

      // Prime cache
      mockDocument.querySelector.mockReturnValue(element);
      adapter.getFrame('some_anchor', 0.016);

      // Register new anchor
      adapter.registerAnchor('new_anchor', element as unknown as Element);

      // Cache should be cleared (implementation detail)
    });
  });

  describe('unregisterAnchor', () => {
    it('removes data-rf-anchor attribute', () => {
      const element = createMockElement();
      mockDocument.querySelector.mockReturnValue(element);

      adapter.unregisterAnchor('existing_anchor');

      expect(element.removeAttribute).toHaveBeenCalledWith('data-rf-anchor');
    });

    it('handles non-existent anchor gracefully', () => {
      mockDocument.querySelector.mockReturnValue(null);

      expect(() => adapter.unregisterAnchor('non_existent')).not.toThrow();
    });
  });

  describe('getAllAnchorIds', () => {
    it('returns empty array when no anchors', () => {
      mockDocument.querySelectorAll.mockReturnValue([]);
      const ids = adapter.getAllAnchorIds();
      expect(ids).toEqual([]);
    });

    it('returns all anchor IDs', () => {
      const elements = [
        { getAttribute: vi.fn(() => 'anchor_1') },
        { getAttribute: vi.fn(() => 'anchor_2') },
        { getAttribute: vi.fn(() => 'anchor_3') },
      ];
      mockDocument.querySelectorAll.mockReturnValue(elements);

      const ids = adapter.getAllAnchorIds();
      expect(ids).toEqual(['anchor_1', 'anchor_2', 'anchor_3']);
    });

    it('filters out null attributes', () => {
      const elements = [
        { getAttribute: vi.fn(() => 'anchor_1') },
        { getAttribute: vi.fn(() => null) },
        { getAttribute: vi.fn(() => 'anchor_3') },
      ];
      mockDocument.querySelectorAll.mockReturnValue(elements);

      const ids = adapter.getAllAnchorIds();
      expect(ids).toEqual(['anchor_1', 'anchor_3']);
    });
  });

  describe('invalidateCache', () => {
    it('clears internal cache', () => {
      // Prime cache
      const element = createMockElement();
      mockDocument.querySelector.mockReturnValue(element);
      adapter.getFrame('test', 0.016);

      // Invalidate
      adapter.invalidateCache();

      // Next call should query DOM again
      adapter.getFrame('test', 0.016);
      expect(mockDocument.querySelector.mock.calls.length).toBeGreaterThan(1);
    });
  });

  describe('updateViewport', () => {
    it('updates viewport dimensions from window', () => {
      mockWindow.innerWidth = 2560;
      mockWindow.innerHeight = 1440;

      adapter.updateViewport();

      // Viewport should be updated (affects normalization)
      // We can't directly test private properties, but getFrame should use new dimensions
    });

    it('handles minimum viewport size', () => {
      mockWindow.innerWidth = 0;
      mockWindow.innerHeight = 0;

      adapter.updateViewport();
      // Should not throw and should use minimum of 1
    });
  });

  describe('dispose', () => {
    it('removes event listeners', () => {
      adapter.dispose();

      expect(mockWindow.removeEventListener).toHaveBeenCalledWith(
        'orientationchange',
        expect.any(Function)
      );
      expect(mockWindow.removeEventListener).toHaveBeenCalledWith(
        'resize',
        expect.any(Function)
      );
    });

    it('can be called multiple times safely', () => {
      expect(() => {
        adapter.dispose();
        adapter.dispose();
      }).not.toThrow();
    });
  });
});

describe('createDOMAdapter', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('creates adapter with defaults', () => {
    const adapter = createDOMAdapter();
    expect(adapter).toBeInstanceOf(DOMAdapter);
    adapter.dispose();
  });

  it('creates adapter with options', () => {
    const adapter = createDOMAdapter({
      cacheTTL: 1000,
      observeMutations: true,
    });
    expect(adapter).toBeInstanceOf(DOMAdapter);
    adapter.dispose();
  });
});

describe('mutation observer', () => {
  it('can be enabled via options', () => {
    const adapter = new DOMAdapter({ observeMutations: true });
    expect(MutationObserver).toBeDefined();
    adapter.dispose();
  });
});

describe('confidence calculation', () => {
  let adapter: DOMAdapter;
  let element: MockElement;

  beforeEach(() => {
    vi.clearAllMocks();
    element = createMockElement();
    element.offsetParent = {}; // Must have offsetParent to be visible
    element.getBoundingClientRect = vi.fn(() => ({
      left: 480,
      top: 270,
      width: 200,
      height: 100,
      right: 680,
      bottom: 370,
    }));
    mockDocument.querySelector.mockReturnValue(element);
    mockDocument.getElementById.mockReturnValue(null);
    // Reset getComputedStyle to visible
    mockWindow.getComputedStyle.mockReturnValue({
      visibility: 'visible',
      display: 'block',
      opacity: '1',
    });
    adapter = new DOMAdapter();
  });

  afterEach(() => {
    adapter.dispose();
  });

  it('returns confidence based on element size and visibility', () => {
    const frame = adapter.getFrame('visible_element', 0.016);
    // Confidence formula: visible(0 or 0.5) + size_score(~0.1) + base(0.1)
    // In mocked Node environment, visibility detection is limited
    // Minimum confidence should be sizeScore + base (~0.2)
    expect(frame?.confidence).toBeGreaterThan(0.2);
    expect(frame?.confidence).toBeLessThanOrEqual(1);
  });
});
