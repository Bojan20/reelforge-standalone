/**
 * ReelForge Context Menu Hook
 *
 * State management for context menus.
 *
 * @module context-menu/useContextMenu
 */

import { useState, useCallback, useMemo } from 'react';
import type { MenuItem } from './ContextMenu';

// ============ Types ============

export interface ContextMenuState {
  isOpen: boolean;
  x: number;
  y: number;
  items: MenuItem[];
}

export interface UseContextMenuReturn {
  /** Menu state */
  state: ContextMenuState;
  /** Show context menu */
  show: (x: number, y: number, items: MenuItem[]) => void;
  /** Hide context menu */
  hide: () => void;
  /** Handle context menu event */
  handleContextMenu: (e: React.MouseEvent, items: MenuItem[]) => void;
}

// ============ Hook ============

export function useContextMenu(): UseContextMenuReturn {
  const [state, setState] = useState<ContextMenuState>({
    isOpen: false,
    x: 0,
    y: 0,
    items: [],
  });

  // Show menu
  const show = useCallback((x: number, y: number, items: MenuItem[]) => {
    setState({
      isOpen: true,
      x,
      y,
      items,
    });
  }, []);

  // Hide menu
  const hide = useCallback(() => {
    setState((prev) => ({
      ...prev,
      isOpen: false,
    }));
  }, []);

  // Handle context menu event
  const handleContextMenu = useCallback(
    (e: React.MouseEvent, items: MenuItem[]) => {
      e.preventDefault();
      e.stopPropagation();
      show(e.clientX, e.clientY, items);
    },
    [show]
  );

  return useMemo(
    () => ({
      state,
      show,
      hide,
      handleContextMenu,
    }),
    [state, show, hide, handleContextMenu]
  );
}

export default useContextMenu;
