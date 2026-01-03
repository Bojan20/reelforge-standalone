/**
 * ReelForge Spatial System - DOM Anchor Adapter
 * Resolves anchors from DOM elements using data attributes.
 *
 * @module reelforge/spatial/adapters
 */

import type { AnchorAdapterType } from '../types';
import { BaseAnchorAdapter } from './BaseAnchorAdapter';

/**
 * DOM anchor attribute name.
 * Elements should have: data-rf-anchor="anchor_id"
 */
const ANCHOR_ATTR = 'data-rf-anchor';

/**
 * Sanitize anchor ID for safe use in CSS selectors.
 * Prevents CSS selector injection attacks.
 *
 * @param anchorId - Raw anchor ID from user/game
 * @returns Sanitized string safe for querySelector
 */
function sanitizeAnchorId(anchorId: string): string {
  // Remove or escape characters that could break CSS selectors:
  // - Quotes (", ') - could escape attribute selector
  // - Brackets (], [) - could break attribute selector
  // - Backslash (\) - escape character
  // - Null bytes and control characters
  return anchorId
    .replace(/[\x00-\x1f\x7f]/g, '')  // Control characters
    .replace(/["\\'[\]]/g, '');        // Selector-breaking chars
}

/**
 * DOM-based anchor adapter.
 * Resolves elements by data-rf-anchor attribute and tracks their positions.
 */
export class DOMAdapter extends BaseAnchorAdapter {
  readonly type: AnchorAdapterType = 'DOM';

  /** Optional root element (defaults to document) */
  private root: ParentNode;

  /** Resize observer for viewport tracking */
  private resizeObserver?: ResizeObserver;

  /** Mutation observer for dynamic elements */
  private mutationObserver?: MutationObserver;

  constructor(options: {
    root?: ParentNode;
    cacheTTL?: number;
    observeMutations?: boolean;
  } = {}) {
    super(options.cacheTTL ?? 500);
    this.root = options.root ?? document;

    // Setup resize observer
    if (typeof ResizeObserver !== 'undefined') {
      this.resizeObserver = new ResizeObserver(() => {
        this.updateViewport();
      });
      this.resizeObserver.observe(document.documentElement);
    }

    // Setup mutation observer for dynamic content
    if (options.observeMutations && typeof MutationObserver !== 'undefined') {
      this.mutationObserver = new MutationObserver((mutations) => {
        // Check if any mutations affect anchor elements
        for (const mutation of mutations) {
          if (mutation.type === 'childList' || mutation.type === 'attributes') {
            // Invalidate cache on structural changes
            this.invalidateCache();
            break;
          }
        }
      });

      this.mutationObserver.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: [ANCHOR_ATTR],
      });
    }

    // Listen for orientation change (mobile)
    if (typeof window !== 'undefined') {
      window.addEventListener('orientationchange', this.handleOrientationChange);
      window.addEventListener('resize', this.handleResize);
    }
  }

  /**
   * Update viewport dimensions.
   */
  updateViewport(): void {
    if (typeof window !== 'undefined') {
      this.viewportWidth = Math.max(1, window.innerWidth);
      this.viewportHeight = Math.max(1, window.innerHeight);
    }
  }

  /**
   * Resolve DOM element by anchor ID.
   * SECURITY: anchorId is sanitized to prevent CSS selector injection.
   */
  protected resolveElement(anchorId: string): Element | null {
    // Sanitize to prevent CSS selector injection
    const safeId = sanitizeAnchorId(anchorId);
    if (!safeId) return null;

    // Try data attribute first
    let element = this.root.querySelector(`[${ANCHOR_ATTR}="${safeId}"]`);

    // Fallback to ID (getElementById is safe, doesn't use CSS selectors)
    if (!element && this.root === document) {
      element = document.getElementById(safeId);
    }

    // Fallback to class (sanitized ID is safe for class selector)
    if (!element) {
      // Additional validation: class names can't start with digit
      const safeClass = /^[a-zA-Z_-]/.test(safeId) ? safeId : null;
      if (safeClass) {
        element = this.root.querySelector(`.${safeClass}`);
      }
    }

    return element;
  }

  /**
   * Get bounding rect for DOM element.
   */
  protected getElementBounds(element: unknown): {
    x: number;
    y: number;
    width: number;
    height: number;
  } | null {
    if (!(element instanceof Element)) return null;

    const rect = element.getBoundingClientRect();

    // Validate rect
    if (rect.width <= 0 || rect.height <= 0) {
      return null;
    }

    return {
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    };
  }

  /**
   * Check if DOM element is visible.
   */
  protected isElementVisible(element: unknown): boolean {
    if (!(element instanceof HTMLElement)) return false;

    // Check basic visibility
    if (element.offsetParent === null && element.tagName !== 'BODY') {
      return false;
    }

    const rect = element.getBoundingClientRect();

    // Check if in viewport
    const inViewport = (
      rect.bottom >= 0 &&
      rect.right >= 0 &&
      rect.left <= this.viewportWidth &&
      rect.top <= this.viewportHeight &&
      rect.width > 0 &&
      rect.height > 0
    );

    if (!inViewport) return false;

    // Check computed visibility
    const style = window.getComputedStyle(element);
    if (
      style.visibility === 'hidden' ||
      style.display === 'none' ||
      parseFloat(style.opacity) === 0
    ) {
      return false;
    }

    return true;
  }

  /**
   * Handle orientation change (mobile devices).
   */
  private handleOrientationChange = (): void => {
    // Delay to allow layout to settle
    setTimeout(() => {
      this.invalidateCache();
    }, 100);
  };

  /**
   * Handle window resize.
   */
  private handleResize = (): void => {
    this.updateViewport();
  };

  /**
   * Register anchor programmatically.
   * Adds data-rf-anchor attribute to element.
   */
  registerAnchor(anchorId: string, element: Element): void {
    element.setAttribute(ANCHOR_ATTR, anchorId);
    this.invalidateCache();
  }

  /**
   * Unregister anchor.
   */
  unregisterAnchor(anchorId: string): void {
    const element = this.resolveElement(anchorId);
    if (element) {
      element.removeAttribute(ANCHOR_ATTR);
    }
    this.cache.delete(anchorId);
  }

  /**
   * Get all registered anchor IDs in DOM.
   */
  getAllAnchorIds(): string[] {
    const elements = this.root.querySelectorAll(`[${ANCHOR_ATTR}]`);
    const ids: string[] = [];
    elements.forEach((el) => {
      const id = el.getAttribute(ANCHOR_ATTR);
      if (id) ids.push(id);
    });
    return ids;
  }

  /**
   * Dispose adapter and cleanup observers.
   */
  override dispose(): void {
    super.dispose();

    this.resizeObserver?.disconnect();
    this.mutationObserver?.disconnect();

    if (typeof window !== 'undefined') {
      window.removeEventListener('orientationchange', this.handleOrientationChange);
      window.removeEventListener('resize', this.handleResize);
    }
  }
}

/**
 * Create DOM adapter with default options.
 */
export function createDOMAdapter(options?: {
  root?: ParentNode;
  cacheTTL?: number;
  observeMutations?: boolean;
}): DOMAdapter {
  return new DOMAdapter(options);
}
