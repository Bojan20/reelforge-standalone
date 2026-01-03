/**
 * ReelForge M8.3.1 Bus Insert Panel
 *
 * UI for managing per-bus insert chains.
 * Features: Copy/Paste, Presets, per-insert slot menu, per-bus PDC toggle.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 * All plugins use flat params (Record<string, number>) and have their own editors.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useBusInserts, useBusInsertChain } from '../store';
import { useInsertSelection, type InsertSelection } from '../plugin';
import {
  copyChainToClipboard,
  pasteChainFromClipboard,
  hasChainInClipboard,
  copyInsertToClipboard,
  pasteInsertFromClipboard,
  hasInsertInClipboard,
  getClipboardSourceHint,
} from '../core/insertChainClipboard';
import {
  getAllPresets,
  saveChainAsPreset,
  loadPresetChain,
  type InsertChainPreset,
} from '../core/insertChainPresets';
import type {
  Insert,
  PluginId,
} from '../core/masterInsertTypes';
import {
  PLUGIN_DISPLAY_CONFIG,
} from '../core/masterInsertTypes';
import type { InsertableBusId } from '../project/projectTypes';
import './BusInsertPanel.css';

// Use shared config
const PLUGIN_CONFIG = PLUGIN_DISPLAY_CONFIG;

interface BusInsertPanelProps {
  /** Bus ID to show inserts for */
  busId: InsertableBusId;
  /** Bus display label */
  busLabel: string;
  /** Bus color */
  busColor: string;
}

export default function BusInsertPanel({
  busId,
  busLabel,
  busColor,
}: BusInsertPanelProps) {
  const {
    addInsert,
    removeInsert,
    toggleBypass,
    updateParams,
    getLatencyMs,
    setChain,
    setBusPdcEnabled,
    isBusPdcEnabled,
    isBusPdcClamped,
    getBusPdcDelayMs,
    getBusPdcMaxMs,
  } = useBusInserts();

  const chain = useBusInsertChain(busId);
  const latencyMs = getLatencyMs(busId);
  const pdcEnabled = isBusPdcEnabled(busId);
  const pdcClamped = isBusPdcClamped(busId);
  const pdcDelayMs = getBusPdcDelayMs(busId);
  const pdcMaxMs = getBusPdcMaxMs();

  // Insert selection for opening editor drawer
  const { selectInsert, setCallbacks } = useInsertSelection();

  // Ref to always access current chain in callbacks (avoids stale closure issues)
  const chainRef = useRef(chain);
  chainRef.current = chain;

  const [collapsed, setCollapsed] = useState(true);
  const [showPresetDropdown, setShowPresetDropdown] = useState(false);
  const [showSavePresetDialog, setShowSavePresetDialog] = useState(false);
  const [presetName, setPresetName] = useState('');
  const [presetDescription, setPresetDescription] = useState('');
  const [confirmReplace, setConfirmReplace] = useState<InsertChainPreset | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [clipboardHint, setClipboardHint] = useState<string | null>(null);
  const [pdcClampPulse, setPdcClampPulse] = useState(false);

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

  // Trigger pulse animation when clamped
  useEffect(() => {
    if (pdcClamped && pdcEnabled) {
      setPdcClampPulse(true);
      const timer = setTimeout(() => setPdcClampPulse(false), 500);
      return () => clearTimeout(timer);
    }
  }, [pdcClamped, pdcEnabled, pdcDelayMs]);

  const handleTogglePdc = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      setBusPdcEnabled(busId, !pdcEnabled);
    },
    [setBusPdcEnabled, busId, pdcEnabled]
  );

  const handleToggleCollapsed = useCallback(() => {
    setCollapsed((prev) => !prev);
  }, []);

  // Open editor drawer for an insert
  const handleOpenEditor = useCallback(
    (insert: Insert) => {
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
        // CRITICAL: Use chainRef.current to get the CURRENT chain state, not the stale closure
        const currentChain = chainRef.current;
        if (!currentChain) return;
        const currentInsert = currentChain.inserts.find((ins) => ins.id === insert.id);
        if (!currentInsert) {
          console.warn(`[BusInsertPanel] handleParamChange: insert ${insert.id} not found in current chain`);
          return;
        }

        // Van* plugins - flat params update
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, [paramId]: value };
        updateParams(busId, insert.id, newParams);
      };

      const handleParamReset = (_paramId: string) => {
        // Reset handled by plugin editor component
      };

      const handleBypassChange = () => {
        toggleBypass(busId, insert.id);
      };

      selectInsert(selection);
      setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
    },
    [busId, selectInsert, setCallbacks, toggleBypass, updateParams]
  );

  const handleAddInsert = useCallback(
    (pluginId: PluginId) => {
      addInsert(busId, pluginId);
    },
    [addInsert, busId]
  );

  // ============ Copy/Paste Handlers ============

  const handleCopyChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      copyChainToClipboard(chain, busId);
      setClipboardHint(busId.toUpperCase());
    },
    [chain, busId]
  );

  const handlePasteChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      const pasted = pasteChainFromClipboard();
      if (pasted) {
        setChain(busId, pasted);
      } else {
        setErrorMessage('RF_ERR: No chain in clipboard');
      }
    },
    [busId, setChain]
  );

  const handlePasteInsert = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      const pasted = pasteInsertFromClipboard();
      if (pasted) {
        // Add to end of chain
        const newInserts = [...chain.inserts, pasted];
        setChain(busId, { inserts: newInserts });
      } else {
        setErrorMessage('RF_ERR: No insert in clipboard');
      }
    },
    [busId, chain.inserts, setChain]
  );

  // ============ Preset Handlers ============

  const handleLoadPreset = useCallback(
    (preset: InsertChainPreset) => {
      if (chain.inserts.length > 0) {
        setConfirmReplace(preset);
      } else {
        const loadedChain = loadPresetChain(preset.id);
        if (loadedChain) {
          setChain(busId, loadedChain);
        } else {
          setErrorMessage('RF_ERR: Failed to load preset');
        }
      }
      setShowPresetDropdown(false);
    },
    [busId, chain.inserts.length, setChain]
  );

  const handleConfirmReplace = useCallback(() => {
    if (confirmReplace) {
      const loadedChain = loadPresetChain(confirmReplace.id);
      if (loadedChain) {
        setChain(busId, loadedChain);
      } else {
        setErrorMessage('RF_ERR: Failed to load preset');
      }
    }
    setConfirmReplace(null);
  }, [busId, confirmReplace, setChain]);

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

  const insertCount = chain.inserts.length;
  const activeCount = chain.inserts.filter((ins) => ins.enabled).length;
  const presets = getAllPresets();

  return (
    <div className="rf-bus-inserts">
      {/* Error Message */}
      {errorMessage && (
        <div className="rf-bus-inserts-error">{errorMessage}</div>
      )}

      {/* Confirm Replace Dialog */}
      {confirmReplace && (
        <div className="rf-bus-inserts-dialog">
          <div className="rf-bus-inserts-dialog-content">
            <p>Replace {busLabel} chain with "{confirmReplace.name}"?</p>
            <div className="rf-bus-inserts-dialog-buttons">
              <button onClick={() => setConfirmReplace(null)}>Cancel</button>
              <button onClick={handleConfirmReplace}>Replace</button>
            </div>
          </div>
        </div>
      )}

      {/* Save Preset Dialog */}
      {showSavePresetDialog && (
        <div className="rf-bus-inserts-dialog">
          <div className="rf-bus-inserts-dialog-content">
            <p>Save {busLabel} Preset</p>
            <input
              type="text"
              placeholder="Preset name"
              value={presetName}
              onChange={(e) => setPresetName(e.target.value)}
              className="rf-bus-inserts-dialog-input"
              autoFocus
            />
            <input
              type="text"
              placeholder="Description (optional)"
              value={presetDescription}
              onChange={(e) => setPresetDescription(e.target.value)}
              className="rf-bus-inserts-dialog-input"
            />
            <div className="rf-bus-inserts-dialog-buttons">
              <button onClick={() => setShowSavePresetDialog(false)}>Cancel</button>
              <button onClick={handleSavePreset} disabled={!presetName.trim()}>
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      <div
        className="rf-bus-inserts-header"
        onClick={handleToggleCollapsed}
        style={{ borderLeftColor: busColor }}
      >
        <span className="rf-bus-inserts-icon">🔌</span>
        <span className="rf-bus-inserts-title">{busLabel} Inserts</span>
        {insertCount > 0 && (
          <span className="rf-bus-inserts-count">
            {activeCount}/{insertCount}
          </span>
        )}
        {latencyMs > 0 && (
          <span className="rf-bus-inserts-latency">
            {latencyMs.toFixed(1)}ms
          </span>
        )}
        {/* PDC Toggle Button */}
        <button
          className={`rf-bus-inserts-pdc-btn ${pdcEnabled ? 'active' : ''} ${pdcClamped && pdcEnabled ? 'clamped' : ''} ${pdcClampPulse ? 'pulse' : ''}`}
          onClick={handleTogglePdc}
          title={
            pdcClamped && pdcEnabled
              ? `PDC: ${pdcDelayMs.toFixed(1)}ms (clamped, max ${pdcMaxMs}ms)`
              : pdcEnabled
                ? `PDC: ${pdcDelayMs.toFixed(1)}ms delay compensation`
                : 'Enable delay compensation'
          }
        >
          {pdcClamped && pdcEnabled ? 'PDC!' : 'PDC'}
        </button>
        <button
          className={`rf-bus-inserts-collapse-btn ${collapsed ? 'collapsed' : ''}`}
          title={collapsed ? 'Expand' : 'Collapse'}
        >
          ▼
        </button>
      </div>

      {!collapsed && (
        <div className="rf-bus-inserts-content">
          {/* Toolbar: Copy/Paste/Presets */}
          <div className="rf-bus-inserts-toolbar">
            <button
              className="rf-bus-inserts-tool-btn"
              onClick={handleCopyChain}
              title="Copy chain to clipboard"
            >
              📋
            </button>
            <button
              className="rf-bus-inserts-tool-btn"
              onClick={handlePasteChain}
              disabled={!hasChainInClipboard()}
              title={
                hasChainInClipboard()
                  ? `Paste chain from ${clipboardHint}`
                  : 'Clipboard empty'
              }
            >
              📥
            </button>
            <button
              className="rf-bus-inserts-tool-btn"
              onClick={handlePasteInsert}
              disabled={!hasInsertInClipboard()}
              title={
                hasInsertInClipboard()
                  ? `Paste insert from ${clipboardHint}`
                  : 'No insert in clipboard'
              }
            >
              +📥
            </button>

            {/* Presets Dropdown */}
            <div className="rf-bus-inserts-preset-wrapper" ref={dropdownRef}>
              <button
                className="rf-bus-inserts-tool-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  setShowPresetDropdown(!showPresetDropdown);
                }}
                title="Presets"
              >
                📁▾
              </button>
              {showPresetDropdown && (
                <div className="rf-bus-inserts-preset-dropdown">
                  <div className="rf-bus-inserts-preset-section">
                    <div className="rf-bus-inserts-preset-section-label">Built-in</div>
                    {presets
                      .filter((p) => p.builtIn)
                      .map((preset) => (
                        <button
                          key={preset.id}
                          className="rf-bus-inserts-preset-item"
                          onClick={() => handleLoadPreset(preset)}
                          title={preset.description}
                        >
                          {preset.name}
                        </button>
                      ))}
                  </div>
                  {presets.some((p) => !p.builtIn) && (
                    <div className="rf-bus-inserts-preset-section">
                      <div className="rf-bus-inserts-preset-section-label">User</div>
                      {presets
                        .filter((p) => !p.builtIn)
                        .map((preset) => (
                          <button
                            key={preset.id}
                            className="rf-bus-inserts-preset-item"
                            onClick={() => handleLoadPreset(preset)}
                            title={preset.description}
                          >
                            {preset.name}
                          </button>
                        ))}
                    </div>
                  )}
                  <div className="rf-bus-inserts-preset-divider" />
                  <button
                    className="rf-bus-inserts-preset-item rf-bus-inserts-preset-save"
                    onClick={(e) => {
                      e.stopPropagation();
                      setShowPresetDropdown(false);
                      setShowSavePresetDialog(true);
                    }}
                    disabled={chain.inserts.length === 0}
                  >
                    💾 Save…
                  </button>
                </div>
              )}
            </div>
          </div>

          {chain.inserts.length === 0 ? (
            <div className="rf-bus-inserts-empty">
              No inserts on {busLabel} bus
            </div>
          ) : (
            chain.inserts.map((insert, index) => (
              <BusInsertSlot
                key={insert.id}
                insert={insert}
                index={index}
                busId={busId}
                onOpenEditor={() => handleOpenEditor(insert)}
                onToggleBypass={() => toggleBypass(busId, insert.id)}
                onRemove={() => removeInsert(busId, insert.id)}
              />
            ))
          )}

          <div className="rf-bus-inserts-add">
            <button
              className="rf-bus-inserts-add-btn"
              onClick={() => handleAddInsert('vaneq')}
            >
              +VanEQ
            </button>
            <button
              className="rf-bus-inserts-add-btn"
              onClick={() => handleAddInsert('vancomp')}
            >
              +VanComp
            </button>
            <button
              className="rf-bus-inserts-add-btn"
              onClick={() => handleAddInsert('vanlimit')}
            >
              +VanLimit
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ============ Insert Slot Component ============

interface BusInsertSlotProps {
  insert: Insert;
  index: number;
  busId: InsertableBusId;
  onOpenEditor: () => void;
  onToggleBypass: () => void;
  onRemove: () => void;
}

function BusInsertSlot({
  insert,
  index,
  busId,
  onOpenEditor,
  onToggleBypass,
  onRemove,
}: BusInsertSlotProps) {
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
      copyInsertToClipboard(insert, busId);
      setShowMenu(false);
    },
    [insert, busId]
  );

  const handleMenuToggle = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    setShowMenu((prev) => !prev);
  }, []);

  return (
    <div className={`rf-bus-insert-slot ${!insert.enabled ? 'bypassed' : ''}`}>
      <div className="rf-bus-insert-slot-header" onClick={onOpenEditor}>
        <span className="rf-bus-insert-slot-index">{index + 1}</span>
        <span className="rf-bus-insert-slot-icon">{config.icon}</span>
        <span className="rf-bus-insert-slot-name">{config.label}</span>
        <button
          className={`rf-bus-insert-slot-bypass ${insert.enabled ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onToggleBypass();
          }}
          title={insert.enabled ? 'Bypass' : 'Enable'}
        >
          {insert.enabled ? 'ON' : 'OFF'}
        </button>
        <div className="rf-bus-insert-slot-menu-wrapper" ref={menuRef}>
          <button
            className="rf-bus-insert-slot-menu-btn"
            onClick={handleMenuToggle}
            title="Insert options"
          >
            ⋮
          </button>
          {showMenu && (
            <div className="rf-bus-insert-slot-menu">
              <button onClick={handleCopyInsert}>📋 Copy</button>
            </div>
          )}
        </div>
        <button
          className="rf-bus-insert-slot-remove"
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
