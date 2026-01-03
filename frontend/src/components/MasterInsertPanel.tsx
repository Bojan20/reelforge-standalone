/**
 * ReelForge M8.3 Master Insert Panel
 *
 * UI for managing master bus insert chain.
 * Features: Copy/Paste, Presets, A/B Snapshot, PDC toggle.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 * All plugins use flat params (Record<string, number>) and have their own editors.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useMasterInserts } from '../store';
import { useMasterABSnapshot } from '../hooks/useMasterABSnapshot';
import { useInsertSelection, type InsertSelection } from '../plugin';
import {
  copyChainToClipboard,
  pasteChainFromClipboard,
  hasChainInClipboard,
  copyInsertToClipboard,
  getClipboardSourceHint,
} from '../core/insertChainClipboard';
import {
  getAllPresets,
  saveChainAsPreset,
  loadPresetChain,
  type InsertChainPreset,
} from '../core/insertChainPresets';
import type {
  MasterInsert,
  PluginId,
} from '../core/masterInsertTypes';
import {
  PLUGIN_DISPLAY_CONFIG,
} from '../core/masterInsertTypes';
import './MasterInsertPanel.css';

// Use shared config, alias for backward compat
const PLUGIN_CONFIG = PLUGIN_DISPLAY_CONFIG;

interface MasterInsertPanelProps {
  /** Optional: collapsed state from parent */
  collapsed?: boolean;
  /** Optional: toggle collapsed callback */
  onToggleCollapsed?: () => void;
}

export default function MasterInsertPanel({
  collapsed: externalCollapsed,
  onToggleCollapsed,
}: MasterInsertPanelProps) {
  const {
    chain,
    latencyMs,
    pdcEnabled,
    compensationDelayMs,
    pdcClamped,
    addInsert,
    removeInsert,
    toggleBypass,
    setInsertEnabled,
    updateParams,
    setPdcEnabled,
    setChain,
  } = useMasterInserts();

  // A/B snapshot hook
  const {
    activeSlot,
    hasSlotA,
    hasSlotB,
    canCompare,
    captureToA,
    captureToB,
    toggleAB,
  } = useMasterABSnapshot();

  // Insert selection for opening editor drawer
  const { selectInsert, setCallbacks } = useInsertSelection();

  // Ref to always access current chain in callbacks (avoids stale closure issues)
  const chainRef = useRef(chain);
  chainRef.current = chain;

  const [internalCollapsed, setInternalCollapsed] = useState(false);
  const collapsed = externalCollapsed ?? internalCollapsed;

  const [showPresetDropdown, setShowPresetDropdown] = useState(false);
  const [showSavePresetDialog, setShowSavePresetDialog] = useState(false);
  const [presetName, setPresetName] = useState('');
  const [presetDescription, setPresetDescription] = useState('');
  const [confirmReplace, setConfirmReplace] = useState<InsertChainPreset | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [clipboardHint, setClipboardHint] = useState<string | null>(null);

  const dropdownRef = useRef<HTMLDivElement>(null);

  // Update clipboard hint periodically
  useEffect(() => {
    const updateHint = () => setClipboardHint(getClipboardSourceHint());
    updateHint();
    const interval = setInterval(updateHint, 500);
    return () => clearInterval(interval);
  }, []);

  // Close dropdown on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setShowPresetDropdown(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Clear error after 3 seconds
  useEffect(() => {
    if (errorMessage) {
      const timer = setTimeout(() => setErrorMessage(null), 3000);
      return () => clearTimeout(timer);
    }
  }, [errorMessage]);

  const handleToggleCollapsed = useCallback(() => {
    if (onToggleCollapsed) {
      onToggleCollapsed();
    } else {
      setInternalCollapsed((prev) => !prev);
    }
  }, [onToggleCollapsed]);

  // Open editor drawer for an insert
  const handleOpenEditor = useCallback(
    (insert: MasterInsert) => {
      // Van* plugins use flat params directly
      const flatParams = insert.params as Record<string, number>;

      // Create selection
      const selection: InsertSelection = {
        scope: 'master',
        insertId: insert.id,
        pluginId: insert.pluginId,
        params: flatParams,
        bypassed: !insert.enabled,
      };

      // Set up callbacks for the editor
      const handleParamChange = (paramId: string, value: number) => {
        // CRITICAL: Use chainRef.current to get the CURRENT chain state, not the stale closure
        // This is essential for plugin windows where the callback is stored and called later
        const currentInsert = chainRef.current.inserts.find((ins) => ins.id === insert.id);
        if (!currentInsert) {
          return;
        }

        // Van* plugins - flat params update
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, [paramId]: value };
        updateParams(insert.id, newParams);
      };

      const handleParamReset = (_paramId: string) => {
        // Reset handled by plugin editor component
      };

      const handleBypassChange = (bypassed: boolean) => {
        // Set the exact bypass state (not toggle) - important for sync from plugin window
        setInsertEnabled(insert.id, !bypassed);
      };

      // Handle batch param changes (atomic update to prevent race conditions)
      const handleParamBatch = (changes: Record<string, number>) => {
        // CRITICAL: Use chainRef.current to get the CURRENT chain state
        const currentInsert = chainRef.current.inserts.find((ins) => ins.id === insert.id);
        if (!currentInsert) {
          return;
        }

        // Van* plugins - apply all changes atomically
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, ...changes };
        updateParams(insert.id, newParams);
      };

      selectInsert(selection);
      setCallbacks(handleParamChange, handleParamReset, handleBypassChange, handleParamBatch);
    },
    [chain.inserts, selectInsert, setCallbacks, setInsertEnabled, updateParams]
  );

  const handleAddInsert = useCallback(
    (pluginId: PluginId) => {
      addInsert(pluginId);
    },
    [addInsert]
  );

  const handlePdcToggle = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      setPdcEnabled(!pdcEnabled);
    },
    [pdcEnabled, setPdcEnabled]
  );

  // ============ Copy/Paste Handlers ============

  const handleCopyChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      copyChainToClipboard(chain, 'master');
      setClipboardHint('Master');
    },
    [chain]
  );

  const handlePasteChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      const pasted = pasteChainFromClipboard();
      if (pasted) {
        setChain(pasted);
      } else {
        setErrorMessage('RF_ERR: No chain in clipboard');
      }
    },
    [setChain]
  );

  // ============ Preset Handlers ============

  const handleLoadPreset = useCallback(
    (preset: InsertChainPreset) => {
      if (chain.inserts.length > 0) {
        setConfirmReplace(preset);
      } else {
        const loadedChain = loadPresetChain(preset.id);
        if (loadedChain) {
          setChain(loadedChain);
        } else {
          setErrorMessage('RF_ERR: Failed to load preset');
        }
      }
      setShowPresetDropdown(false);
    },
    [chain.inserts.length, setChain]
  );

  const handleConfirmReplace = useCallback(() => {
    if (confirmReplace) {
      const loadedChain = loadPresetChain(confirmReplace.id);
      if (loadedChain) {
        setChain(loadedChain);
      } else {
        setErrorMessage('RF_ERR: Failed to load preset');
      }
    }
    setConfirmReplace(null);
  }, [confirmReplace, setChain]);

  const handleSavePreset = useCallback(() => {
    const saved = saveChainAsPreset(chain, presetName, presetDescription);
    if (saved) {
      setShowSavePresetDialog(false);
      setPresetName('');
      setPresetDescription('');
    } else {
      setErrorMessage('RF_ERR: Invalid chain - cannot save');
    }
  }, [chain, presetName, presetDescription]);

  // ============ A/B Handlers ============

  const handleCaptureA = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      captureToA();
    },
    [captureToA]
  );

  const handleCaptureB = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      captureToB();
    },
    [captureToB]
  );

  const handleToggleAB = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      if (canCompare) {
        toggleAB();
      }
    },
    [canCompare, toggleAB]
  );

  const presets = getAllPresets();

  return (
    <div className="rf-master-inserts">
      {/* Error Message */}
      {errorMessage && (
        <div className="rf-master-inserts-error">{errorMessage}</div>
      )}

      {/* Confirm Replace Dialog */}
      {confirmReplace && (
        <div className="rf-master-inserts-dialog">
          <div className="rf-master-inserts-dialog-content">
            <p>Replace current chain with "{confirmReplace.name}"?</p>
            <div className="rf-master-inserts-dialog-buttons">
              <button onClick={() => setConfirmReplace(null)}>Cancel</button>
              <button onClick={handleConfirmReplace}>Replace</button>
            </div>
          </div>
        </div>
      )}

      {/* Save Preset Dialog */}
      {showSavePresetDialog && (
        <div className="rf-master-inserts-dialog">
          <div className="rf-master-inserts-dialog-content">
            <p>Save Preset</p>
            <input
              type="text"
              placeholder="Preset name"
              value={presetName}
              onChange={(e) => setPresetName(e.target.value)}
              className="rf-master-inserts-dialog-input"
              autoFocus
            />
            <input
              type="text"
              placeholder="Description (optional)"
              value={presetDescription}
              onChange={(e) => setPresetDescription(e.target.value)}
              className="rf-master-inserts-dialog-input"
            />
            <div className="rf-master-inserts-dialog-buttons">
              <button onClick={() => setShowSavePresetDialog(false)}>Cancel</button>
              <button onClick={handleSavePreset} disabled={!presetName.trim()}>
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="rf-master-inserts-header" onClick={handleToggleCollapsed}>
        <span className="rf-master-inserts-icon">🎛️</span>
        <span className="rf-master-inserts-title">Master Inserts</span>
        {latencyMs > 0 && (
          <span className="rf-master-inserts-latency">
            {latencyMs.toFixed(1)}ms
          </span>
        )}
        <button
          className={`rf-master-inserts-pdc-btn ${pdcEnabled ? 'active' : ''} ${pdcClamped ? 'clamped' : ''}`}
          onClick={handlePdcToggle}
          title={
            pdcClamped
              ? `PDC CLAMPED: Latency exceeds max (${compensationDelayMs.toFixed(1)}ms applied)`
              : pdcEnabled
                ? `PDC ON (${compensationDelayMs.toFixed(1)}ms delay)`
                : 'PDC OFF - Enable to compensate for insert latency'
          }
        >
          PDC{pdcClamped ? '!' : ''}
        </button>
        <button
          className={`rf-master-inserts-collapse-btn ${collapsed ? 'collapsed' : ''}`}
          title={collapsed ? 'Expand' : 'Collapse'}
        >
          ▼
        </button>
      </div>

      {!collapsed && (
        <div className="rf-master-inserts-content">
          {/* Toolbar: Copy/Paste/Presets/A-B */}
          <div className="rf-master-inserts-toolbar">
            {/* Copy/Paste Group */}
            <div className="rf-master-inserts-toolbar-group">
              <button
                className="rf-master-inserts-tool-btn"
                onClick={handleCopyChain}
                title="Copy chain to clipboard"
              >
                📋 Copy
              </button>
              <button
                className="rf-master-inserts-tool-btn"
                onClick={handlePasteChain}
                disabled={!hasChainInClipboard()}
                title={
                  hasChainInClipboard()
                    ? `Paste chain from ${clipboardHint}`
                    : 'Clipboard empty'
                }
              >
                📥 Paste
              </button>
            </div>

            {/* Presets Group */}
            <div className="rf-master-inserts-toolbar-group" ref={dropdownRef}>
              <button
                className="rf-master-inserts-tool-btn rf-master-inserts-preset-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  setShowPresetDropdown(!showPresetDropdown);
                }}
                title="Load preset"
              >
                📁 Presets ▾
              </button>
              {showPresetDropdown && (
                <div className="rf-master-inserts-preset-dropdown">
                  <div className="rf-master-inserts-preset-section">
                    <div className="rf-master-inserts-preset-section-label">Built-in</div>
                    {presets
                      .filter((p) => p.builtIn)
                      .map((preset) => (
                        <button
                          key={preset.id}
                          className="rf-master-inserts-preset-item"
                          onClick={() => handleLoadPreset(preset)}
                          title={preset.description}
                        >
                          {preset.name}
                        </button>
                      ))}
                  </div>
                  {presets.some((p) => !p.builtIn) && (
                    <div className="rf-master-inserts-preset-section">
                      <div className="rf-master-inserts-preset-section-label">User</div>
                      {presets
                        .filter((p) => !p.builtIn)
                        .map((preset) => (
                          <button
                            key={preset.id}
                            className="rf-master-inserts-preset-item"
                            onClick={() => handleLoadPreset(preset)}
                            title={preset.description}
                          >
                            {preset.name}
                          </button>
                        ))}
                    </div>
                  )}
                  <div className="rf-master-inserts-preset-divider" />
                  <button
                    className="rf-master-inserts-preset-item rf-master-inserts-preset-save"
                    onClick={(e) => {
                      e.stopPropagation();
                      setShowPresetDropdown(false);
                      setShowSavePresetDialog(true);
                    }}
                    disabled={chain.inserts.length === 0}
                  >
                    💾 Save Preset…
                  </button>
                </div>
              )}
            </div>

            {/* A/B Group */}
            <div className="rf-master-inserts-toolbar-group rf-master-inserts-ab-group">
              <button
                className={`rf-master-inserts-ab-btn ${activeSlot === 'A' ? 'active' : ''} ${hasSlotA ? 'has-data' : ''}`}
                onClick={handleCaptureA}
                title={hasSlotA ? 'Slot A captured (click to recapture)' : 'Capture current to A'}
              >
                A
              </button>
              <button
                className={`rf-master-inserts-ab-toggle ${canCompare ? 'enabled' : ''}`}
                onClick={handleToggleAB}
                disabled={!canCompare}
                title={canCompare ? 'Toggle between A/B' : 'Capture both A and B first'}
              >
                ⇄
              </button>
              <button
                className={`rf-master-inserts-ab-btn ${activeSlot === 'B' ? 'active' : ''} ${hasSlotB ? 'has-data' : ''}`}
                onClick={handleCaptureB}
                title={hasSlotB ? 'Slot B captured (click to recapture)' : 'Capture current to B'}
              >
                B
              </button>
            </div>
          </div>

          {/* Insert Chain */}
          {chain.inserts.length === 0 ? (
            <div className="rf-master-inserts-empty">
              No inserts. Add VanEQ, VanComp, or VanLimit below.
            </div>
          ) : (
            chain.inserts.map((insert, index) => (
              <InsertSlot
                key={insert.id}
                insert={insert}
                index={index}
                onOpenEditor={() => handleOpenEditor(insert)}
                onToggleBypass={() => toggleBypass(insert.id)}
                onRemove={() => removeInsert(insert.id)}
              />
            ))
          )}

          <div className="rf-master-inserts-add">
            <button
              className="rf-master-inserts-add-btn rf-master-inserts-add-btn--pro"
              onClick={() => handleAddInsert('vaneq')}
              title="VanEQ Pro - 6-band parametric EQ"
            >
              + VanEQ
            </button>
            <button
              className="rf-master-inserts-add-btn rf-master-inserts-add-btn--pro"
              onClick={() => handleAddInsert('vancomp')}
              title="VanComp Pro - Professional compressor"
            >
              + VanComp
            </button>
            <button
              className="rf-master-inserts-add-btn rf-master-inserts-add-btn--pro"
              onClick={() => handleAddInsert('vanlimit')}
              title="VanLimit Pro - Brick-wall limiter"
            >
              + VanLimit
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ============ Insert Slot Component ============

interface InsertSlotProps {
  insert: MasterInsert;
  index: number;
  onOpenEditor: () => void;
  onToggleBypass: () => void;
  onRemove: () => void;
}

function InsertSlot({
  insert,
  index,
  onOpenEditor,
  onToggleBypass,
  onRemove,
}: InsertSlotProps) {
  const [showMenu, setShowMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const config = PLUGIN_CONFIG[insert.pluginId];

  // Close menu on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowMenu(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleCopyInsert = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      copyInsertToClipboard(insert, 'master');
      setShowMenu(false);
    },
    [insert]
  );

  const handleMenuToggle = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowMenu((prev) => !prev);
  }, []);

  return (
    <div className={`rf-insert-slot ${!insert.enabled ? 'bypassed' : ''}`}>
      <div className="rf-insert-slot-header" onClick={onOpenEditor}>
        <span className="rf-insert-slot-index">{index + 1}</span>
        <span className="rf-insert-slot-icon">{config.icon}</span>
        <span className="rf-insert-slot-name">{config.label}</span>
        <button
          className={`rf-insert-slot-bypass ${insert.enabled ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onToggleBypass();
          }}
          title={insert.enabled ? 'Bypass' : 'Enable'}
        >
          {insert.enabled ? 'ON' : 'OFF'}
        </button>
        <div className="rf-insert-slot-menu-wrapper" ref={menuRef}>
          <button
            className="rf-insert-slot-menu-btn"
            onClick={handleMenuToggle}
            title="Insert options"
          >
            ⋮
          </button>
          {showMenu && (
            <div className="rf-insert-slot-menu">
              <button onClick={handleCopyInsert}>📋 Copy Insert</button>
            </div>
          )}
        </div>
        <button
          className="rf-insert-slot-remove"
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
          title="Remove"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
