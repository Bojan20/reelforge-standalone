/**
 * ReelForge M8.5 Asset Insert Panel
 *
 * UI for managing per-asset insert chains.
 * Displayed in Asset Inspector when an asset is selected.
 *
 * Van* series plugins only (VanEQ Pro, VanComp Pro, VanLimit Pro).
 * All plugins use flat params (Record<string, number>) and have their own editors.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useAssetInserts, useAssetInsertChain } from '../core/AssetInsertContext';
import { useInsertSelection, type InsertSelection } from '../plugin';
import {
  copyChainToClipboard,
  pasteChainFromClipboard,
  hasChainInClipboard,
  pasteInsertFromClipboard,
  hasInsertInClipboard,
  getClipboardSourceHint,
} from '../core/insertChainClipboard';
import {
  getAllPresets,
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
import type { AssetId } from '../project/projectTypes';
import './AssetInsertPanel.css';

// Use shared config
const PLUGIN_CONFIG = PLUGIN_DISPLAY_CONFIG;

interface AssetInsertPanelProps {
  /** Asset ID to show inserts for */
  assetId: AssetId;
  /** Asset display name */
  assetName: string;
}

export default function AssetInsertPanel({
  assetId,
  assetName,
}: AssetInsertPanelProps) {
  const {
    addInsert,
    removeInsert,
    toggleBypass,
    updateParams,
    setChain,
    getActiveVoiceChainCount,
  } = useAssetInserts();

  const chain = useAssetInsertChain(assetId);

  // Insert selection for opening editor drawer
  const { selectInsert, setCallbacks } = useInsertSelection();

  // Ref to always access current chain in callbacks (avoids stale closure issues)
  const chainRef = useRef(chain);
  chainRef.current = chain;

  const [collapsed, setCollapsed] = useState(false);
  const [showPresetDropdown, setShowPresetDropdown] = useState(false);
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
    setCollapsed((prev) => !prev);
  }, []);

  // Open editor drawer for an insert
  const handleOpenEditor = useCallback(
    (insert: Insert) => {
      // Van* plugins use flat params directly
      const flatParams = insert.params as Record<string, number>;

      const selection: InsertSelection = {
        scope: 'asset',
        assetId,
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
          console.warn(`[AssetInsertPanel] handleParamChange: insert ${insert.id} not found in current chain`);
          return;
        }

        // Van* plugins - flat params update
        const currentParams = currentInsert.params as Record<string, number>;
        const newParams = { ...currentParams, [paramId]: value };
        updateParams(assetId, insert.id, newParams);
      };

      const handleParamReset = (_paramId: string) => {
        // Reset handled by plugin editor component
      };

      const handleBypassChange = () => {
        toggleBypass(assetId, insert.id);
      };

      selectInsert(selection);
      setCallbacks(handleParamChange, handleParamReset, handleBypassChange);
    },
    [assetId, selectInsert, setCallbacks, toggleBypass, updateParams]
  );

  const handleAddInsert = useCallback(
    (pluginId: PluginId) => {
      addInsert(assetId, pluginId);
    },
    [addInsert, assetId]
  );

  // ============ Copy/Paste Handlers ============

  const handleCopyChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      copyChainToClipboard(chain, assetId);
      setClipboardHint(assetId);
    },
    [chain, assetId]
  );

  const handlePasteChain = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      const pasted = pasteChainFromClipboard();
      if (pasted) {
        setChain(assetId, pasted);
      } else {
        setErrorMessage('RF_ERR: No chain in clipboard');
      }
    },
    [assetId, setChain]
  );

  const handlePasteInsert = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      const pasted = pasteInsertFromClipboard();
      if (pasted) {
        // Add to end of chain
        const newInserts = [...chain.inserts, pasted];
        setChain(assetId, { inserts: newInserts });
      } else {
        setErrorMessage('RF_ERR: No insert in clipboard');
      }
    },
    [assetId, chain.inserts, setChain]
  );

  // ============ Preset Handlers ============

  const handleLoadPreset = useCallback(
    (preset: InsertChainPreset) => {
      if (chain.inserts.length > 0) {
        setConfirmReplace(preset);
      } else {
        const loadedChain = loadPresetChain(preset.id);
        if (loadedChain) {
          setChain(assetId, loadedChain);
        } else {
          setErrorMessage('RF_ERR: Failed to load preset');
        }
      }
      setShowPresetDropdown(false);
    },
    [assetId, chain.inserts.length, setChain]
  );

  const handleConfirmReplace = useCallback(() => {
    if (confirmReplace) {
      const loadedChain = loadPresetChain(confirmReplace.id);
      if (loadedChain) {
        setChain(assetId, loadedChain);
      } else {
        setErrorMessage('RF_ERR: Failed to load preset');
      }
    }
    setConfirmReplace(null);
  }, [assetId, confirmReplace, setChain]);

  const insertCount = chain.inserts.length;
  const activeCount = chain.inserts.filter((ins) => ins.enabled).length;
  const voiceCount = getActiveVoiceChainCount();
  const presets = getAllPresets();

  return (
    <div className="rf-asset-inserts">
      {/* Error Message */}
      {errorMessage && (
        <div className="rf-asset-inserts-error">{errorMessage}</div>
      )}

      {/* Confirm Replace Dialog */}
      {confirmReplace && (
        <div className="rf-asset-inserts-dialog">
          <div className="rf-asset-inserts-dialog-content">
            <p>Replace "{assetName}" chain with "{confirmReplace.name}"?</p>
            <div className="rf-asset-inserts-dialog-buttons">
              <button onClick={() => setConfirmReplace(null)}>Cancel</button>
              <button onClick={handleConfirmReplace}>Replace</button>
            </div>
          </div>
        </div>
      )}

      <div
        className="rf-asset-inserts-header"
        onClick={handleToggleCollapsed}
      >
        <span className="rf-asset-inserts-icon">🔌</span>
        <span className="rf-asset-inserts-title">Asset Inserts</span>
        {insertCount > 0 && (
          <span className="rf-asset-inserts-count">
            {activeCount}/{insertCount}
          </span>
        )}
        {voiceCount > 0 && (
          <span className="rf-asset-inserts-voices" title={`${voiceCount} active voice chain(s)`}>
            🎤{voiceCount}
          </span>
        )}
        <button
          className={`rf-asset-inserts-collapse-btn ${collapsed ? 'collapsed' : ''}`}
          title={collapsed ? 'Expand' : 'Collapse'}
        >
          ▼
        </button>
      </div>

      {!collapsed && (
        <div className="rf-asset-inserts-content">
          {/* Toolbar: Copy/Paste/Presets */}
          <div className="rf-asset-inserts-toolbar">
            <button
              className="rf-asset-inserts-tool-btn"
              onClick={handleCopyChain}
              title="Copy chain to clipboard"
            >
              📋
            </button>
            <button
              className="rf-asset-inserts-tool-btn"
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
              className="rf-asset-inserts-tool-btn"
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
            <div className="rf-asset-inserts-preset-wrapper" ref={dropdownRef}>
              <button
                className="rf-asset-inserts-tool-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  setShowPresetDropdown(!showPresetDropdown);
                }}
                title="Presets"
              >
                📁▾
              </button>
              {showPresetDropdown && (
                <div className="rf-asset-inserts-preset-dropdown">
                  <div className="rf-asset-inserts-preset-section">
                    <div className="rf-asset-inserts-preset-section-label">Built-in</div>
                    {presets
                      .filter((p) => p.builtIn)
                      .map((preset) => (
                        <button
                          key={preset.id}
                          className="rf-asset-inserts-preset-item"
                          onClick={() => handleLoadPreset(preset)}
                          title={preset.description}
                        >
                          {preset.name}
                        </button>
                      ))}
                  </div>
                  {presets.some((p) => !p.builtIn) && (
                    <div className="rf-asset-inserts-preset-section">
                      <div className="rf-asset-inserts-preset-section-label">User</div>
                      {presets
                        .filter((p) => !p.builtIn)
                        .map((preset) => (
                          <button
                            key={preset.id}
                            className="rf-asset-inserts-preset-item"
                            onClick={() => handleLoadPreset(preset)}
                            title={preset.description}
                          >
                            {preset.name}
                          </button>
                        ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          {chain.inserts.length === 0 ? (
            <div className="rf-asset-inserts-empty">
              No inserts for "{assetName}"
            </div>
          ) : (
            chain.inserts.map((insert, index) => (
              <AssetInsertSlot
                key={insert.id}
                insert={insert}
                index={index}
                onOpenEditor={() => handleOpenEditor(insert)}
                onToggleBypass={() => toggleBypass(assetId, insert.id)}
                onRemove={() => removeInsert(assetId, insert.id)}
              />
            ))
          )}

          <div className="rf-asset-inserts-add">
            <button
              className="rf-asset-inserts-add-btn"
              onClick={() => handleAddInsert('vaneq')}
            >
              +VanEQ
            </button>
            <button
              className="rf-asset-inserts-add-btn"
              onClick={() => handleAddInsert('vancomp')}
            >
              +VanComp
            </button>
            <button
              className="rf-asset-inserts-add-btn"
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

interface AssetInsertSlotProps {
  insert: Insert;
  index: number;
  onOpenEditor: () => void;
  onToggleBypass: () => void;
  onRemove: () => void;
}

function AssetInsertSlot({
  insert,
  index,
  onOpenEditor,
  onToggleBypass,
  onRemove,
}: AssetInsertSlotProps) {
  const config = PLUGIN_CONFIG[insert.pluginId];

  return (
    <div className={`rf-asset-insert-slot ${!insert.enabled ? 'bypassed' : ''}`}>
      <div className="rf-asset-insert-slot-header" onClick={onOpenEditor}>
        <span className="rf-asset-insert-slot-index">{index + 1}</span>
        <span className="rf-asset-insert-slot-icon">{config.icon}</span>
        <span className="rf-asset-insert-slot-name">{config.label}</span>
        <button
          className={`rf-asset-insert-slot-bypass ${insert.enabled ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onToggleBypass();
          }}
          title={insert.enabled ? 'Bypass' : 'Enable'}
        >
          {insert.enabled ? 'ON' : 'OFF'}
        </button>
        <button
          className="rf-asset-insert-slot-remove"
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
