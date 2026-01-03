/**
 * ReelForge Plugin Window Manager
 *
 * Manages plugin UI windows - floating, docked, and embedded.
 * Handles window positioning, z-order, and focus.
 *
 * @module plugin-system/PluginWindowManager
 */

// ============ Types ============

export type WindowMode = 'floating' | 'docked' | 'embedded';
export type DockPosition = 'left' | 'right' | 'bottom' | 'center';

export interface WindowBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PluginWindow {
  id: string;
  instanceId: string;
  pluginName: string;
  mode: WindowMode;
  bounds: WindowBounds;
  dockPosition?: DockPosition;
  isVisible: boolean;
  isFocused: boolean;
  isMinimized: boolean;
  zIndex: number;
  containerId?: string; // DOM element ID for rendering
}

export interface WindowLayoutPreset {
  id: string;
  name: string;
  windows: Array<{
    instanceId: string;
    mode: WindowMode;
    bounds: WindowBounds;
    dockPosition?: DockPosition;
  }>;
}

// ============ Constants ============

const MIN_WINDOW_WIDTH = 200;
const MIN_WINDOW_HEIGHT = 100;
const SNAP_THRESHOLD = 20;

// ============ Plugin Window Manager ============

class PluginWindowManagerImpl {
  private windows = new Map<string, PluginWindow>();
  private focusOrder: string[] = []; // Window IDs in focus order (last = top)
  private baseZIndex = 1000;
  private listeners = new Set<(event: WindowEvent) => void>();

  // Layout constraints
  private viewportBounds: WindowBounds = { x: 0, y: 0, width: 1920, height: 1080 };

  // Snap targets
  private snapTargets: WindowBounds[] = [];

  // ============ Window Lifecycle ============

  /**
   * Open plugin window.
   */
  openWindow(
    instanceId: string,
    pluginName: string,
    options?: {
      mode?: WindowMode;
      bounds?: Partial<WindowBounds>;
      dockPosition?: DockPosition;
    }
  ): PluginWindow {
    // Check if window already exists
    const existing = this.getWindowForInstance(instanceId);
    if (existing) {
      this.focusWindow(existing.id);
      return existing;
    }

    const mode = options?.mode ?? 'floating';
    const defaultBounds = this.getDefaultBounds(mode, options?.dockPosition);

    const window: PluginWindow = {
      id: `window_${instanceId}`,
      instanceId,
      pluginName,
      mode,
      bounds: { ...defaultBounds, ...options?.bounds },
      dockPosition: options?.dockPosition,
      isVisible: true,
      isFocused: true,
      isMinimized: false,
      zIndex: this.getNextZIndex(),
      containerId: `plugin-container-${instanceId}`,
    };

    this.windows.set(window.id, window);
    this.focusOrder.push(window.id);
    this.updateFocus(window.id);

    this.emit({ type: 'opened', window });
    return window;
  }

  /**
   * Close plugin window.
   */
  closeWindow(windowId: string): boolean {
    const window = this.windows.get(windowId);
    if (!window) return false;

    this.windows.delete(windowId);
    this.focusOrder = this.focusOrder.filter(id => id !== windowId);

    // Focus next window
    if (this.focusOrder.length > 0) {
      const nextFocusId = this.focusOrder[this.focusOrder.length - 1];
      this.updateFocus(nextFocusId);
    }

    this.emit({ type: 'closed', windowId });
    return true;
  }

  /**
   * Get window by ID.
   */
  getWindow(windowId: string): PluginWindow | undefined {
    return this.windows.get(windowId);
  }

  /**
   * Get window for plugin instance.
   */
  getWindowForInstance(instanceId: string): PluginWindow | undefined {
    for (const window of this.windows.values()) {
      if (window.instanceId === instanceId) {
        return window;
      }
    }
    return undefined;
  }

  /**
   * Get all windows.
   */
  getAllWindows(): PluginWindow[] {
    return Array.from(this.windows.values());
  }

  /**
   * Get visible windows in z-order.
   */
  getVisibleWindows(): PluginWindow[] {
    return this.focusOrder
      .map(id => this.windows.get(id))
      .filter((w): w is PluginWindow => w !== undefined && w.isVisible && !w.isMinimized);
  }

  // ============ Visibility ============

  /**
   * Show window.
   */
  showWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.isVisible = true;
    window.isMinimized = false;
    this.focusWindow(windowId);

    this.emit({ type: 'shown', windowId });
  }

  /**
   * Hide window.
   */
  hideWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.isVisible = false;
    window.isFocused = false;

    this.emit({ type: 'hidden', windowId });
  }

  /**
   * Toggle window visibility.
   */
  toggleWindow(windowId: string): boolean {
    const window = this.windows.get(windowId);
    if (!window) return false;

    if (window.isVisible) {
      this.hideWindow(windowId);
    } else {
      this.showWindow(windowId);
    }

    return window.isVisible;
  }

  /**
   * Minimize window.
   */
  minimizeWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.isMinimized = true;
    window.isFocused = false;

    this.emit({ type: 'minimized', windowId });
  }

  /**
   * Restore minimized window.
   */
  restoreWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.isMinimized = false;
    this.focusWindow(windowId);

    this.emit({ type: 'restored', windowId });
  }

  // ============ Focus ============

  /**
   * Focus window.
   */
  focusWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window || !window.isVisible || window.isMinimized) return;

    // Move to top of focus order
    this.focusOrder = this.focusOrder.filter(id => id !== windowId);
    this.focusOrder.push(windowId);

    this.updateFocus(windowId);
    this.emit({ type: 'focused', windowId });
  }

  private updateFocus(focusedId: string): void {
    for (const [id, window] of this.windows) {
      window.isFocused = id === focusedId;
      window.zIndex = this.baseZIndex + this.focusOrder.indexOf(id);
    }
  }

  /**
   * Get focused window.
   */
  getFocusedWindow(): PluginWindow | undefined {
    if (this.focusOrder.length === 0) return undefined;
    return this.windows.get(this.focusOrder[this.focusOrder.length - 1]);
  }

  /**
   * Focus next window.
   */
  focusNextWindow(): void {
    if (this.focusOrder.length < 2) return;

    const currentIndex = this.focusOrder.length - 1;
    const nextIndex = (currentIndex + 1) % this.focusOrder.length;
    this.focusWindow(this.focusOrder[nextIndex]);
  }

  /**
   * Focus previous window.
   */
  focusPreviousWindow(): void {
    if (this.focusOrder.length < 2) return;

    const currentIndex = this.focusOrder.length - 1;
    const prevIndex = (currentIndex - 1 + this.focusOrder.length) % this.focusOrder.length;
    this.focusWindow(this.focusOrder[prevIndex]);
  }

  // ============ Position & Size ============

  /**
   * Move window.
   */
  moveWindow(windowId: string, x: number, y: number, snap: boolean = true): void {
    const window = this.windows.get(windowId);
    if (!window || window.mode !== 'floating') return;

    let newX = x;
    let newY = y;

    // Snap to edges
    if (snap) {
      const snapped = this.snapToEdges(newX, newY, window.bounds.width, window.bounds.height);
      newX = snapped.x;
      newY = snapped.y;
    }

    // Constrain to viewport
    newX = Math.max(0, Math.min(newX, this.viewportBounds.width - window.bounds.width));
    newY = Math.max(0, Math.min(newY, this.viewportBounds.height - window.bounds.height));

    window.bounds.x = newX;
    window.bounds.y = newY;

    this.emit({ type: 'moved', windowId, bounds: window.bounds });
  }

  /**
   * Resize window.
   */
  resizeWindow(windowId: string, width: number, height: number): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.bounds.width = Math.max(MIN_WINDOW_WIDTH, width);
    window.bounds.height = Math.max(MIN_WINDOW_HEIGHT, height);

    // Constrain to viewport
    if (window.bounds.x + window.bounds.width > this.viewportBounds.width) {
      window.bounds.x = Math.max(0, this.viewportBounds.width - window.bounds.width);
    }
    if (window.bounds.y + window.bounds.height > this.viewportBounds.height) {
      window.bounds.y = Math.max(0, this.viewportBounds.height - window.bounds.height);
    }

    this.emit({ type: 'resized', windowId, bounds: window.bounds });
  }

  /**
   * Set window bounds.
   */
  setBounds(windowId: string, bounds: Partial<WindowBounds>): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    Object.assign(window.bounds, bounds);
    this.emit({ type: 'boundsChanged', windowId, bounds: window.bounds });
  }

  /**
   * Center window in viewport.
   */
  centerWindow(windowId: string): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.bounds.x = (this.viewportBounds.width - window.bounds.width) / 2;
    window.bounds.y = (this.viewportBounds.height - window.bounds.height) / 2;

    this.emit({ type: 'moved', windowId, bounds: window.bounds });
  }

  // ============ Window Mode ============

  /**
   * Set window mode.
   */
  setMode(windowId: string, mode: WindowMode, dockPosition?: DockPosition): void {
    const window = this.windows.get(windowId);
    if (!window) return;

    window.mode = mode;
    window.dockPosition = dockPosition;

    // Update bounds for mode
    if (mode === 'docked' && dockPosition) {
      window.bounds = this.getDockedBounds(dockPosition);
    }

    this.emit({ type: 'modeChanged', windowId, mode, dockPosition });
  }

  /**
   * Float docked window.
   */
  floatWindow(windowId: string): void {
    this.setMode(windowId, 'floating');
  }

  /**
   * Dock floating window.
   */
  dockWindow(windowId: string, position: DockPosition): void {
    this.setMode(windowId, 'docked', position);
  }

  // ============ Layout ============

  /**
   * Set viewport bounds.
   */
  setViewportBounds(bounds: WindowBounds): void {
    this.viewportBounds = bounds;

    // Constrain all windows
    for (const window of this.windows.values()) {
      if (window.mode === 'floating') {
        this.moveWindow(window.id, window.bounds.x, window.bounds.y, false);
      }
    }
  }

  /**
   * Tile windows.
   */
  tileWindows(mode: 'horizontal' | 'vertical' | 'grid'): void {
    const visibleWindows = this.getVisibleWindows();
    if (visibleWindows.length === 0) return;

    const { width, height } = this.viewportBounds;
    const count = visibleWindows.length;

    switch (mode) {
      case 'horizontal':
        const hWidth = width / count;
        visibleWindows.forEach((w, i) => {
          w.bounds = { x: i * hWidth, y: 0, width: hWidth, height };
        });
        break;

      case 'vertical':
        const vHeight = height / count;
        visibleWindows.forEach((w, i) => {
          w.bounds = { x: 0, y: i * vHeight, width, height: vHeight };
        });
        break;

      case 'grid':
        const cols = Math.ceil(Math.sqrt(count));
        const rows = Math.ceil(count / cols);
        const cellWidth = width / cols;
        const cellHeight = height / rows;

        visibleWindows.forEach((w, i) => {
          const col = i % cols;
          const row = Math.floor(i / cols);
          w.bounds = {
            x: col * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight,
          };
        });
        break;
    }

    this.emit({ type: 'tiled', mode });
  }

  /**
   * Cascade windows.
   */
  cascadeWindows(): void {
    const visibleWindows = this.getVisibleWindows();
    const offset = 30;

    visibleWindows.forEach((w, i) => {
      w.bounds.x = offset * i;
      w.bounds.y = offset * i;
    });

    this.emit({ type: 'cascaded' });
  }

  /**
   * Save layout preset.
   */
  saveLayoutPreset(name: string): WindowLayoutPreset {
    const preset: WindowLayoutPreset = {
      id: `preset_${Date.now()}`,
      name,
      windows: Array.from(this.windows.values()).map(w => ({
        instanceId: w.instanceId,
        mode: w.mode,
        bounds: { ...w.bounds },
        dockPosition: w.dockPosition,
      })),
    };

    return preset;
  }

  /**
   * Restore layout preset.
   */
  restoreLayoutPreset(preset: WindowLayoutPreset): void {
    for (const windowPreset of preset.windows) {
      const window = this.getWindowForInstance(windowPreset.instanceId);
      if (window) {
        window.mode = windowPreset.mode;
        window.bounds = { ...windowPreset.bounds };
        window.dockPosition = windowPreset.dockPosition;
      }
    }

    this.emit({ type: 'layoutRestored', presetId: preset.id });
  }

  // ============ Helpers ============

  private getNextZIndex(): number {
    return this.baseZIndex + this.focusOrder.length;
  }

  private getDefaultBounds(mode: WindowMode, dockPosition?: DockPosition): WindowBounds {
    if (mode === 'docked' && dockPosition) {
      return this.getDockedBounds(dockPosition);
    }

    // Cascade from last window
    const lastWindow = this.getFocusedWindow();
    const offset = lastWindow ? 30 : 0;

    return {
      x: 100 + offset,
      y: 100 + offset,
      width: 600,
      height: 400,
    };
  }

  private getDockedBounds(position: DockPosition): WindowBounds {
    const { width, height } = this.viewportBounds;

    switch (position) {
      case 'left':
        return { x: 0, y: 0, width: width * 0.3, height };
      case 'right':
        return { x: width * 0.7, y: 0, width: width * 0.3, height };
      case 'bottom':
        return { x: 0, y: height * 0.7, width, height: height * 0.3 };
      case 'center':
        return { x: width * 0.1, y: height * 0.1, width: width * 0.8, height: height * 0.8 };
    }
  }

  private snapToEdges(x: number, y: number, width: number, height: number): { x: number; y: number } {
    let newX = x;
    let newY = y;

    // Viewport edges
    if (Math.abs(x) < SNAP_THRESHOLD) newX = 0;
    if (Math.abs(y) < SNAP_THRESHOLD) newY = 0;
    if (Math.abs(x + width - this.viewportBounds.width) < SNAP_THRESHOLD) {
      newX = this.viewportBounds.width - width;
    }
    if (Math.abs(y + height - this.viewportBounds.height) < SNAP_THRESHOLD) {
      newY = this.viewportBounds.height - height;
    }

    // Other windows
    for (const target of this.snapTargets) {
      // Snap to left edge of target
      if (Math.abs(x + width - target.x) < SNAP_THRESHOLD) {
        newX = target.x - width;
      }
      // Snap to right edge of target
      if (Math.abs(x - (target.x + target.width)) < SNAP_THRESHOLD) {
        newX = target.x + target.width;
      }
    }

    return { x: newX, y: newY };
  }

  // ============ Events ============

  subscribe(callback: (event: WindowEvent) => void): () => void {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  private emit(event: WindowEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // ============ Utilities ============

  /**
   * Close all windows.
   */
  closeAllWindows(): void {
    const windowIds = Array.from(this.windows.keys());
    for (const id of windowIds) {
      this.closeWindow(id);
    }
  }

  /**
   * Minimize all windows.
   */
  minimizeAllWindows(): void {
    for (const window of this.windows.values()) {
      this.minimizeWindow(window.id);
    }
  }

  /**
   * Show all windows.
   */
  showAllWindows(): void {
    for (const window of this.windows.values()) {
      this.showWindow(window.id);
    }
  }
}

// ============ Event Types ============

export type WindowEvent =
  | { type: 'opened'; window: PluginWindow }
  | { type: 'closed'; windowId: string }
  | { type: 'shown'; windowId: string }
  | { type: 'hidden'; windowId: string }
  | { type: 'minimized'; windowId: string }
  | { type: 'restored'; windowId: string }
  | { type: 'focused'; windowId: string }
  | { type: 'moved'; windowId: string; bounds: WindowBounds }
  | { type: 'resized'; windowId: string; bounds: WindowBounds }
  | { type: 'boundsChanged'; windowId: string; bounds: WindowBounds }
  | { type: 'modeChanged'; windowId: string; mode: WindowMode; dockPosition?: DockPosition }
  | { type: 'tiled'; mode: string }
  | { type: 'cascaded' }
  | { type: 'layoutRestored'; presetId: string };

// ============ Singleton Instance ============

export const PluginWindowManager = new PluginWindowManagerImpl();
