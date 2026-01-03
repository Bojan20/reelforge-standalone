/**
 * Vitest Test Setup
 *
 * Minimal setup for tests - keeps it simple to avoid hangs.
 */

/// <reference types="node" />
import { afterEach, vi } from 'vitest';

// Cleanup after each test
afterEach(() => {
  vi.clearAllMocks();
});

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const g = globalThis as any;

// Mock requestAnimationFrame
g.requestAnimationFrame = vi.fn((cb: FrameRequestCallback) =>
  setTimeout(() => cb(Date.now()), 16) as unknown as number
);
g.cancelAnimationFrame = vi.fn((id: number) => clearTimeout(id));

// Mock ResizeObserver
g.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));

// Mock IntersectionObserver
g.IntersectionObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));
