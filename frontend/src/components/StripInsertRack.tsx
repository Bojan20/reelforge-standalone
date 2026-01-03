/**
 * ReelForge M9.2.2b Strip Insert Rack
 *
 * Inline insert rack for mixer strips. Displays in each bus strip
 * with registry-driven add menu (portal), bypass toggle, and opens editor drawer.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 * All plugins use flat params (Record<string, number>) and have their own editors.
 *
 * Features:
 * - Portal-based menu for reliable z-index stacking
 * - Auto-open editor on insert add (uses insertId tracking, not length)
 * - Click-outside and ESC close with proper cleanup
 * - Edge-aware positioning
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { useMasterInserts, useBusInserts, useBusInsertChain } from '../store';
import {
  getAllPluginDefinitions,
  useInsertSelection,
  type InsertSelection,
  type PluginDefinition,
} from '../plugin';
import type { MasterInsert, Insert, PluginId } from '../core/masterInsertTypes';
import type { InsertableBusId } from '../project/projectTypes';
import './StripInsertRack.css';

/** Z-index token for overlay elements */
const RF_Z_OVERLAY = 20000;

/** Insert scope type */
type InsertScope = 'master' | 'bus';

interface StripInsertRackProps {
  /** Whether this is the master strip or a bus strip */
  scope: InsertScope;
  /** Bus ID when scope is 'bus' */
  scopeId?: InsertableBusId;
  /** Strip color for border accent */
  stripColor?: string;
}

/**
 * Inline insert rack for mixer strips.
 * Collapsed by default, expands to show insert slots.
 */
export function StripInsertRack({ scope, scopeId, stripColor }: StripInsertRackProps) {
  const [collapsed, setCollapsed] = useState(true);

  const handleToggleCollapsed = useCallback(() => {
    setCollapsed((prev) => !prev);
  }, []);

  // Render based on scope
  if (scope === 'master') {
    return (
      <MasterStripInsertRack
        collapsed={collapsed}
        onToggleCollapsed={handleToggleCollapsed}
        stripColor={stripColor}
      />
    );
  }

  if (!scopeId) {
    return null;
  }

  return (
    <BusStripInsertRack
      busId={scopeId}
      collapsed={collapsed}
      onToggleCollapsed={handleToggleCollapsed}
      stripColor={stripColor}
    />
  );
}

// ============ Portal Menu Component ============

interface PortalMenuProps {
  anchorRef: React.RefObject<HTMLButtonElement | null>;
  plugins: PluginDefinition[];
  onSelect: (pluginId: string) => void;
  onClose: () => void;
}

function StripInsertAddMenuPortal({ anchorRef, plugins, onSelect, onClose }: PortalMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ top: 0, left: 0, width: 120 });
  const mountedRef = useRef(true);

  // Track mounted state
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Calculate position based on anchor
  const updatePosition = useCallback(() => {
    if (!mountedRef.current || !anchorRef.current) return;

    const rect = anchorRef.current.getBoundingClientRect();
    const menuHeight = 40 * plugins.length + 16;
    const menuWidth = 140;

    let top = rect.bottom + 4;
    let left = rect.left;

    // Flip up if near bottom edge
    if (top + menuHeight > window.innerHeight - 20) {
      top = rect.top - menuHeight - 4;
    }

    // Flip left if near right edge
    if (left + menuWidth > window.innerWidth - 20) {
      left = rect.right - menuWidth;
    }

    if (left < 10) {
      left = 10;
    }

    setPosition({ top, left, width: Math.max(rect.width, menuWidth) });
  }, [anchorRef, plugins.length]);

  // Update position on mount and resize/scroll
  useEffect(() => {
    updatePosition();

    const handleUpdate = () => {
      if (mountedRef.current) {
        updatePosition();
      }
    };

    window.addEventListener('resize', handleUpdate);
    window.addEventListener('scroll', handleUpdate, true);

    return () => {
      window.removeEventListener('resize', handleUpdate);
      window.removeEventListener('scroll', handleUpdate, true);
    };
  }, [updatePosition]);

  // Click outside to close - immediate, no timeout
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (!mountedRef.current) return;

      const target = e.target as Node;
      const clickedMenu = menuRef.current?.contains(target);
      const clickedAnchor = anchorRef.current?.contains(target);

      if (!clickedMenu && !clickedAnchor) {
        onClose();
      }
    };

    // Add listener immediately on capture phase to avoid missing clicks
    document.addEventListener('mousedown', handleClickOutside, true);

    return () => {
      document.removeEventListener('mousedown', handleClickOutside, true);
    };
  }, [anchorRef, onClose]);

  // ESC to close
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && mountedRef.current) {
        onClose();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  const handleSelect = useCallback((pluginId: string) => {
    onSelect(pluginId);
    // Don't call onClose here - onSelect will close menu
  }, [onSelect]);

  return createPortal(
    <div
      ref={menuRef}
      className="rf-strip-portal-menu"
      style={{
        position: 'fixed',
        top: position.top,
        left: position.left,
        minWidth: position.width,
        zIndex: RF_Z_OVERLAY,
      }}
    >
      {plugins.map((plugin) => (
        <button
          key={plugin.id}
          className="rf-strip-portal-menu-item"
          onClick={() => handleSelect(plugin.id)}
        >
          <span className="rf-strip-portal-menu-icon">{plugin.icon}</span>
          <span className="rf-strip-portal-menu-label">
            {plugin.shortName || plugin.displayName}
          </span>
        </button>
      ))}
    </div>,
    document.body
  );
}

// ============ Master Strip Insert Rack ============

interface MasterStripInsertRackProps {
  collapsed: boolean;
  onToggleCollapsed: () => void;
  stripColor?: string;
}

function MasterStripInsertRack({
  collapsed,
  onToggleCollapsed,
  stripColor,
}: MasterStripInsertRackProps) {
  const [showAddMenu, setShowAddMenu] = useState(false);
  const addBtnRef = useRef<HTMLButtonElement>(null);
  const plugins = getAllPluginDefinitions();

  // Track which insert IDs we've seen - for detecting new inserts
  const knownInsertIdsRef = useRef<Set<string>>(new Set());
  // Track if we just added an insert (to trigger auto-open)
  const pendingAutoOpenRef = useRef<string | null>(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const {
    chain,
    addInsert,
    removeInsert,
    toggleBypass,
    updateParams,
  } = useMasterInserts();

  const { selectInsert, setCallbacks } = useInsertSelection();

  // Initialize known IDs on first render
  useEffect(() => {
    chain.inserts.forEach((ins) => knownInsertIdsRef.current.add(ins.id));
  }, []); // Only on mount

  // Open editor for an insert
  const openEditorForInsert = useCallback(
    (insert: MasterInsert) => {
      if (!mountedRef.current) return;

      console.debug('[StripInsertRack] Opening editor for insert:', {
        id: insert.id,
        pluginId: insert.pluginId,
      });

      // Van* plugins use flat params directly
      const flatParams = insert.params as Record<string, number>;

      const selection: InsertSelection = {
        scope: 'master',
        insertId: insert.id,
        pluginId: insert.pluginId,
        params: flatParams,
        bypassed: !insert.enabled,
      };

      const handleParamChange = (paramId: string, value: number) => {
        if (!mountedRef.current) return;
        const currentInsert = chain.inserts.find((ins) => ins.id === insert.id);
        if (!currentInsert) return;
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, [paramId]: value };
        updateParams(insert.id, newParams);
      };

      const handleParamReset = (_paramId: string) => {
        // Reset handled by drawer
      };

      const handleBypassChange = () => {
        if (!mountedRef.current) return;
        toggleBypass(insert.id);
      };

      selectInsert(selection);
      setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
    },
    [chain.inserts, selectInsert, setCallbacks, toggleBypass, updateParams]
  );

  // Detect new inserts and auto-open if we triggered the add
  useEffect(() => {
    if (!mountedRef.current) return;

    // Find new insert (one that's not in our known set)
    const newInsert = chain.inserts.find((ins) => !knownInsertIdsRef.current.has(ins.id));

    if (newInsert && pendingAutoOpenRef.current === 'pending') {
      // We added this insert - open editor
      pendingAutoOpenRef.current = null;
      openEditorForInsert(newInsert);
    }

    // Update known IDs
    chain.inserts.forEach((ins) => knownInsertIdsRef.current.add(ins.id));
  }, [chain.inserts, openEditorForInsert]);

  // Add insert and mark for auto-open
  const handleAddInsert = useCallback(
    (pluginId: string) => {
      pendingAutoOpenRef.current = 'pending';
      addInsert(pluginId as PluginId);
      setShowAddMenu(false);
    },
    [addInsert]
  );

  const handleToggleAddMenu = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowAddMenu((prev) => !prev);
  }, []);

  const handleCloseMenu = useCallback(() => {
    setShowAddMenu(false);
  }, []);

  const insertCount = chain.inserts.length;
  const activeCount = chain.inserts.filter((ins) => ins.enabled).length;

  return (
    <div className="rf-strip-rack" style={stripColor ? { borderLeftColor: stripColor } : undefined}>
      <div className="rf-strip-rack-header" onClick={onToggleCollapsed}>
        <span className="rf-strip-rack-title">INS</span>
        {insertCount > 0 && (
          <span className="rf-strip-rack-count">
            {activeCount}/{insertCount}
          </span>
        )}
        <span className={`rf-strip-rack-chevron ${collapsed ? 'collapsed' : ''}`}>▼</span>
      </div>

      {!collapsed && (
        <div className="rf-strip-rack-content">
          {chain.inserts.map((insert) => (
            <StripInsertSlot
              key={insert.id}
              pluginId={insert.pluginId}
              enabled={insert.enabled}
              onOpenEditor={() => openEditorForInsert(insert)}
              onToggleBypass={() => toggleBypass(insert.id)}
              onChangePlugin={(newPluginId) => {
                // Remove old, add new at same position (simple replace)
                removeInsert(insert.id);
                addInsert(newPluginId as PluginId);
              }}
              onRemove={() => removeInsert(insert.id)}
            />
          ))}

          <button
            ref={addBtnRef}
            className="rf-strip-rack-add-btn"
            onClick={handleToggleAddMenu}
            title="Add insert"
          >
            + Add
          </button>

          {showAddMenu && (
            <StripInsertAddMenuPortal
              anchorRef={addBtnRef}
              plugins={plugins}
              onSelect={handleAddInsert}
              onClose={handleCloseMenu}
            />
          )}
        </div>
      )}
    </div>
  );
}

// ============ Bus Strip Insert Rack ============

interface BusStripInsertRackProps {
  busId: InsertableBusId;
  collapsed: boolean;
  onToggleCollapsed: () => void;
  stripColor?: string;
}

function BusStripInsertRack({
  busId,
  collapsed,
  onToggleCollapsed,
  stripColor,
}: BusStripInsertRackProps) {
  const [showAddMenu, setShowAddMenu] = useState(false);
  const addBtnRef = useRef<HTMLButtonElement>(null);
  const plugins = getAllPluginDefinitions();

  // Track which insert IDs we've seen - for detecting new inserts
  const knownInsertIdsRef = useRef<Set<string>>(new Set());
  // Track if we just added an insert (to trigger auto-open)
  const pendingAutoOpenRef = useRef<string | null>(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const { addInsert, removeInsert, toggleBypass, updateParams } = useBusInserts();
  const chain = useBusInsertChain(busId);
  const { selectInsert, setCallbacks } = useInsertSelection();

  // Initialize known IDs on first render
  useEffect(() => {
    chain.inserts.forEach((ins) => knownInsertIdsRef.current.add(ins.id));
  }, []); // Only on mount

  // Open editor for an insert
  const openEditorForInsert = useCallback(
    (insert: Insert) => {
      if (!mountedRef.current) return;

      // Van* plugins use flat params directly
      const flatParams = insert.params as Record<string, number>;

      const selection: InsertSelection = {
        scope: 'bus',
        busId,
        insertId: insert.id,
        pluginId: insert.pluginId,
        params: flatParams,
        bypassed: !insert.enabled,
      };

      const handleParamChange = (paramId: string, value: number) => {
        if (!mountedRef.current) return;
        const currentInsert = chain.inserts.find((ins) => ins.id === insert.id);
        if (!currentInsert) return;
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, [paramId]: value };
        updateParams(busId, insert.id, newParams);
      };

      const handleParamReset = (_paramId: string) => {
        // Reset handled by drawer
      };

      const handleBypassChange = () => {
        if (!mountedRef.current) return;
        toggleBypass(busId, insert.id);
      };

      selectInsert(selection);
      setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
    },
    [busId, chain.inserts, selectInsert, setCallbacks, toggleBypass, updateParams]
  );

  // Detect new inserts and auto-open if we triggered the add
  useEffect(() => {
    if (!mountedRef.current) return;

    // Find new insert (one that's not in our known set)
    const newInsert = chain.inserts.find((ins) => !knownInsertIdsRef.current.has(ins.id));

    if (newInsert && pendingAutoOpenRef.current === 'pending') {
      // We added this insert - open editor
      pendingAutoOpenRef.current = null;
      openEditorForInsert(newInsert);
    }

    // Update known IDs
    chain.inserts.forEach((ins) => knownInsertIdsRef.current.add(ins.id));
  }, [chain.inserts, openEditorForInsert]);

  // Add insert and mark for auto-open
  const handleAddInsert = useCallback(
    (pluginId: string) => {
      pendingAutoOpenRef.current = 'pending';
      addInsert(busId, pluginId as PluginId);
      setShowAddMenu(false);
    },
    [addInsert, busId]
  );

  const handleToggleAddMenu = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowAddMenu((prev) => !prev);
  }, []);

  const handleCloseMenu = useCallback(() => {
    setShowAddMenu(false);
  }, []);

  const insertCount = chain.inserts.length;
  const activeCount = chain.inserts.filter((ins) => ins.enabled).length;

  return (
    <div className="rf-strip-rack" style={stripColor ? { borderLeftColor: stripColor } : undefined}>
      <div className="rf-strip-rack-header" onClick={onToggleCollapsed}>
        <span className="rf-strip-rack-title">INS</span>
        {insertCount > 0 && (
          <span className="rf-strip-rack-count">
            {activeCount}/{insertCount}
          </span>
        )}
        <span className={`rf-strip-rack-chevron ${collapsed ? 'collapsed' : ''}`}>▼</span>
      </div>

      {!collapsed && (
        <div className="rf-strip-rack-content">
          {chain.inserts.map((insert) => (
            <StripInsertSlot
              key={insert.id}
              pluginId={insert.pluginId}
              enabled={insert.enabled}
              onOpenEditor={() => openEditorForInsert(insert)}
              onToggleBypass={() => toggleBypass(busId, insert.id)}
              onChangePlugin={(newPluginId) => {
                removeInsert(busId, insert.id);
                addInsert(busId, newPluginId as PluginId);
              }}
              onRemove={() => removeInsert(busId, insert.id)}
            />
          ))}

          <button
            ref={addBtnRef}
            className="rf-strip-rack-add-btn"
            onClick={handleToggleAddMenu}
            title="Add insert"
          >
            + Add
          </button>

          {showAddMenu && (
            <StripInsertAddMenuPortal
              anchorRef={addBtnRef}
              plugins={plugins}
              onSelect={handleAddInsert}
              onClose={handleCloseMenu}
            />
          )}
        </div>
      )}
    </div>
  );
}

// ============ Insert Slot Component ============

interface StripInsertSlotProps {
  pluginId: string;
  enabled: boolean;
  onOpenEditor: () => void;
  onToggleBypass: () => void;
  onChangePlugin: (newPluginId: string) => void;
  onRemove: () => void;
}

function StripInsertSlot({
  pluginId,
  enabled,
  onOpenEditor,
  onToggleBypass,
  onChangePlugin,
  onRemove,
}: StripInsertSlotProps) {
  const plugins = getAllPluginDefinitions();
  const plugin = plugins.find((p) => p.id === pluginId);
  const displayName = plugin?.shortName || plugin?.displayName || pluginId;
  const icon = plugin?.icon || '🔌';

  // Dropdown state
  const [showDropdown, setShowDropdown] = useState(false);
  const dropdownBtnRef = useRef<HTMLButtonElement>(null);

  // Close dropdown on click outside
  useEffect(() => {
    if (!showDropdown) return;
    const handleClick = (e: MouseEvent) => {
      if (dropdownBtnRef.current && !dropdownBtnRef.current.contains(e.target as Node)) {
        setShowDropdown(false);
      }
    };
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setShowDropdown(false);
    };
    document.addEventListener('mousedown', handleClick);
    document.addEventListener('keydown', handleEsc);
    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleEsc);
    };
  }, [showDropdown]);

  return (
    <div className={`rf-strip-slot ${!enabled ? 'bypassed' : ''}`}>
      <button
        className={`rf-strip-slot-bypass ${enabled ? 'active' : ''}`}
        onClick={(e) => {
          e.stopPropagation();
          onToggleBypass();
        }}
        title={enabled ? 'Bypass' : 'Enable'}
      >
        {enabled ? '●' : '○'}
      </button>
      <button
        className="rf-strip-slot-name"
        onClick={() => {
          console.debug('[StripInsertSlot] Button clicked for:', displayName);
          onOpenEditor();
        }}
        title={`Edit ${displayName}`}
      >
        <span className="rf-strip-slot-icon">{icon}</span>
        <span className="rf-strip-slot-label">{displayName}</span>
      </button>
      <button
        ref={dropdownBtnRef}
        className={`rf-strip-slot-dropdown ${showDropdown ? 'open' : ''}`}
        onClick={(e) => {
          e.stopPropagation();
          setShowDropdown(!showDropdown);
        }}
        title="Change or remove plugin"
      >
        ▼
      </button>

      {/* Dropdown menu portal */}
      {showDropdown && dropdownBtnRef.current && createPortal(
        <StripSlotDropdownMenu
          anchorRef={dropdownBtnRef}
          plugins={plugins}
          currentPluginId={pluginId}
          onSelect={(newPluginId) => {
            onChangePlugin(newPluginId);
            setShowDropdown(false);
          }}
          onRemove={() => {
            onRemove();
            setShowDropdown(false);
          }}
          onClose={() => setShowDropdown(false)}
        />,
        document.body
      )}
    </div>
  );
}

// ============ Slot Dropdown Menu Portal ============

interface StripSlotDropdownMenuProps {
  anchorRef: React.RefObject<HTMLButtonElement | null>;
  plugins: PluginDefinition[];
  currentPluginId: string;
  onSelect: (pluginId: string) => void;
  onRemove: () => void;
  onClose: () => void;
}

function StripSlotDropdownMenu({
  anchorRef,
  plugins,
  currentPluginId,
  onSelect,
  onRemove,
  onClose,
}: StripSlotDropdownMenuProps) {
  const [position, setPosition] = useState({ top: 0, left: 0 });

  useEffect(() => {
    if (!anchorRef.current) return;
    const rect = anchorRef.current.getBoundingClientRect();
    const menuWidth = 180;
    const menuHeight = Math.min(300, (plugins.length + 1) * 36 + 8);

    let top = rect.bottom + 4;
    let left = rect.left;

    // Edge awareness
    if (left + menuWidth > window.innerWidth - 8) {
      left = rect.right - menuWidth;
    }
    if (top + menuHeight > window.innerHeight - 8) {
      top = rect.top - menuHeight - 4;
    }

    setPosition({ top, left });
  }, [anchorRef, plugins.length]);

  return (
    <>
      {/* Backdrop */}
      <div
        style={{
          position: 'fixed',
          inset: 0,
          zIndex: RF_Z_OVERLAY - 1,
        }}
        onClick={onClose}
      />
      {/* Menu */}
      <div
        className="rf-strip-portal-menu rf-strip-slot-dropdown-menu"
        style={{
          position: 'fixed',
          top: position.top,
          left: position.left,
          zIndex: RF_Z_OVERLAY,
          minWidth: 180,
          maxHeight: 300,
          overflowY: 'auto',
        }}
      >
        {plugins.map((p) => (
          <button
            key={p.id}
            className={`rf-strip-portal-menu-item ${p.id === currentPluginId ? 'current' : ''}`}
            onClick={() => onSelect(p.id)}
            disabled={p.id === currentPluginId}
          >
            <span className="rf-strip-portal-menu-icon">{p.icon}</span>
            <span className="rf-strip-portal-menu-label">{p.shortName || p.displayName}</span>
            {p.id === currentPluginId && <span className="rf-strip-slot-current-mark">✓</span>}
          </button>
        ))}
        <div className="rf-strip-slot-dropdown-divider" />
        <button
          className="rf-strip-portal-menu-item rf-strip-slot-remove"
          onClick={onRemove}
        >
          <span className="rf-strip-portal-menu-icon">🗑️</span>
          <span className="rf-strip-portal-menu-label">Remove</span>
        </button>
      </div>
    </>
  );
}

export default StripInsertRack;
