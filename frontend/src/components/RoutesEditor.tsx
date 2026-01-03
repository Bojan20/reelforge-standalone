/**
 * ReelForge M6.7 Routes Editor + M6.9 UX Enhancements
 *
 * Wwise-like editor for runtime_routes.json.
 * 2-pane layout: event list (left) + action editor (right).
 *
 * M6.9: Added AssetPicker, ActionTemplates, and RouteSimulationPanel.
 */

import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import type {
  RoutesConfig,
  RouteAction,
  PlayAction,
  SetBusGainAction,
  RouteBus,
  RouteActionType,
} from '../core/routesTypes';
import {
  createEmptyRoutesConfig,
  createEmptyEventRoute,
  createDefaultPlayAction,
  createDefaultSetBusGainAction,
  createDefaultStopAllAction,
  ROUTE_ACTION_TYPES,
  PUBLIC_BUSES,
} from '../core/routesTypes';
import type {
  RouteValidationResult,
  RouteValidationError,
} from '../core/validateRoutes';
import {
  validateRoutes,
  formatErrorLocation,
} from '../core/validateRoutes';
import type { IRoutesStorage } from '../core/routesStorage';
import {
  createRoutesStorage,
  createRoutesBackup,
  restoreRoutesBackup,
} from '../core/routesStorage';
import { AssetIndex } from '../core/assetIndex';
import type { INativeRuntimeCore, NativeRuntimeCoreWrapper } from '../core/nativeRuntimeCore';
import AssetPicker from './AssetPicker';
import ActionTemplates from './ActionTemplates';
import RouteSimulationPanel from './RouteSimulationPanel';
import './RoutesEditor.css';

interface RoutesEditorProps {
  routesPath: string;
  /** Asset IDs for validation (backwards compatible) */
  assetIds?: Set<string>;
  /** M6.9: Full asset index for Asset Picker */
  assetIndex?: AssetIndex;
  /** M6.9: Native core for simulation panel */
  nativeCore?: INativeRuntimeCore | NativeRuntimeCoreWrapper | null;
  onReloadCore?: (config: RoutesConfig) => Promise<boolean>;
  /** M6.9: Show simulation panel */
  showSimulation?: boolean;
}

export default function RoutesEditor({
  routesPath,
  assetIds,
  assetIndex,
  nativeCore,
  onReloadCore,
  showSimulation = false,
}: RoutesEditorProps) {
  // State
  const [config, setConfig] = useState<RoutesConfig>(createEmptyRoutesConfig());
  const [validation, setValidation] = useState<RouteValidationResult>({
    valid: true,
    errors: [],
    warnings: [],
  });
  const [selectedEventIndex, setSelectedEventIndex] = useState<number | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [isDirty, setIsDirty] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [isReloading, setIsReloading] = useState(false);
  const [reloadError, setReloadError] = useState<string | null>(null);
  const [lastSavedBackup, setLastSavedBackup] = useState<string | null>(null);
  const [draggedActionIndex, setDraggedActionIndex] = useState<number | null>(null);
  const [pendingAssetPickerFocus, setPendingAssetPickerFocus] = useState<number | null>(null);

  // Refs
  const storageRef = useRef<IRoutesStorage | null>(null);
  // M6.9: Store mutable refs for asset pickers
  const assetPickerRefs = useRef<Map<number, { current: HTMLInputElement | null }>>(new Map());

  // M6.9: Create fallback asset index from assetIds if no assetIndex provided
  const effectiveAssetIndex = useMemo(() => {
    if (assetIndex) return assetIndex;
    if (assetIds) {
      return new AssetIndex(Array.from(assetIds).map((id) => ({ id })));
    }
    return new AssetIndex([]);
  }, [assetIndex, assetIds]);

  // M6.9: Get or create a ref for an asset picker
  const getAssetPickerRef = useCallback((actionIndex: number) => {
    if (!assetPickerRefs.current.has(actionIndex)) {
      assetPickerRefs.current.set(actionIndex, { current: null });
    }
    return assetPickerRefs.current.get(actionIndex)!;
  }, []);

  // Initialize storage and load routes
  useEffect(() => {
    const storage = createRoutesStorage(routesPath, assetIds);
    storageRef.current = storage;

    const loadRoutes = async () => {
      setIsLoading(true);
      const result = await storage.load();
      setConfig(result.config);
      setValidation(result.validation);
      setLastSavedBackup(createRoutesBackup(result.config));
      setIsLoading(false);
    };

    loadRoutes();
  }, [routesPath, assetIds]);

  // Re-validate when config changes
  useEffect(() => {
    const result = validateRoutes(config, assetIds);
    setValidation(result);
  }, [config, assetIds]);

  // Get selected event
  const selectedEvent = selectedEventIndex !== null ? config.events[selectedEventIndex] : null;

  // Filter events by search query
  const filteredEvents = config.events.filter((event) =>
    event.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  // Get errors/warnings for a specific event
  const getEventErrors = useCallback(
    (eventIndex: number): RouteValidationError[] => {
      return validation.errors.filter((err) => err.eventIndex === eventIndex);
    },
    [validation.errors]
  );

  const getEventWarnings = useCallback(
    (eventIndex: number): RouteValidationError[] => {
      return validation.warnings.filter((warn) => warn.eventIndex === eventIndex);
    },
    [validation.warnings]
  );

  // Update config helper
  const updateConfig = useCallback((updater: (prev: RoutesConfig) => RoutesConfig) => {
    setConfig((prev) => {
      const next = updater(prev);
      setIsDirty(true);
      return next;
    });
  }, []);

  // Event handlers
  const handleAddEvent = useCallback(() => {
    const baseName = 'onNewEvent';
    let name = baseName;
    let counter = 1;
    while (config.events.some((e) => e.name === name)) {
      name = `${baseName}${counter++}`;
    }

    updateConfig((prev) => ({
      ...prev,
      events: [...prev.events, createEmptyEventRoute(name)],
    }));
    setSelectedEventIndex(config.events.length);
  }, [config.events, updateConfig]);

  const handleDeleteEvent = useCallback(
    (index: number) => {
      updateConfig((prev) => ({
        ...prev,
        events: prev.events.filter((_, i) => i !== index),
      }));
      if (selectedEventIndex === index) {
        setSelectedEventIndex(null);
      } else if (selectedEventIndex !== null && selectedEventIndex > index) {
        setSelectedEventIndex(selectedEventIndex - 1);
      }
    },
    [selectedEventIndex, updateConfig]
  );

  const handleUpdateEventName = useCallback(
    (index: number, name: string) => {
      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) => (i === index ? { ...e, name } : e)),
      }));
    },
    [updateConfig]
  );

  // Action handlers
  const handleAddAction = useCallback(
    (type: RouteActionType) => {
      if (selectedEventIndex === null) return;

      let action: RouteAction;
      switch (type) {
        case 'Play':
          action = createDefaultPlayAction(config.defaultBus);
          break;
        case 'SetBusGain':
          action = createDefaultSetBusGainAction();
          break;
        case 'StopAll':
          action = createDefaultStopAllAction();
          break;
        case 'Stop':
          action = { type: 'Stop' };
          break;
        default:
          return;
      }

      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) =>
          i === selectedEventIndex ? { ...e, actions: [...e.actions, action] } : e
        ),
      }));
    },
    [selectedEventIndex, config.defaultBus, updateConfig]
  );

  // M6.9: Handle template selection
  const handleTemplateSelect = useCallback(
    (action: RouteAction, focusAssetPicker: boolean) => {
      if (selectedEventIndex === null) return;

      // Get the index the new action will have
      const newActionIndex = config.events[selectedEventIndex]?.actions.length ?? 0;

      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) =>
          i === selectedEventIndex ? { ...e, actions: [...e.actions, action] } : e
        ),
      }));

      // Schedule focus on the new asset picker after render
      if (focusAssetPicker) {
        setPendingAssetPickerFocus(newActionIndex);
      }
    },
    [selectedEventIndex, config.events, updateConfig]
  );

  // M6.9: Focus asset picker when pending
  useEffect(() => {
    if (pendingAssetPickerFocus !== null) {
      const ref = assetPickerRefs.current.get(pendingAssetPickerFocus);
      if (ref?.current) {
        ref.current.focus();
      }
      setPendingAssetPickerFocus(null);
    }
  }, [pendingAssetPickerFocus, config]);

  const handleDeleteAction = useCallback(
    (actionIndex: number) => {
      if (selectedEventIndex === null) return;

      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) =>
          i === selectedEventIndex
            ? { ...e, actions: e.actions.filter((_, ai) => ai !== actionIndex) }
            : e
        ),
      }));
    },
    [selectedEventIndex, updateConfig]
  );

  const handleUpdateAction = useCallback(
    (actionIndex: number, updates: Partial<RouteAction>) => {
      if (selectedEventIndex === null) return;

      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) =>
          i === selectedEventIndex
            ? {
                ...e,
                actions: e.actions.map((a, ai) =>
                  ai === actionIndex ? { ...a, ...updates } as RouteAction : a
                ),
              }
            : e
        ),
      }));
    },
    [selectedEventIndex, updateConfig]
  );

  // Drag and drop for action reordering
  const handleDragStart = useCallback((actionIndex: number) => {
    setDraggedActionIndex(actionIndex);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent, _targetIndex: number) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  }, []);

  const handleDrop = useCallback(
    (targetIndex: number) => {
      if (draggedActionIndex === null || selectedEventIndex === null) return;
      if (draggedActionIndex === targetIndex) return;

      updateConfig((prev) => ({
        ...prev,
        events: prev.events.map((e, i) => {
          if (i !== selectedEventIndex) return e;

          const actions = [...e.actions];
          const [dragged] = actions.splice(draggedActionIndex, 1);
          actions.splice(targetIndex, 0, dragged);
          return { ...e, actions };
        }),
      }));
      setDraggedActionIndex(null);
    },
    [draggedActionIndex, selectedEventIndex, updateConfig]
  );

  // Reload handler with rollback
  const handleReload = useCallback(async () => {
    if (!onReloadCore) return;

    setIsReloading(true);
    setReloadError(null);

    try {
      const success = await onReloadCore(config);
      if (!success) {
        throw new Error('Core reload failed');
      }
      setReloadError(null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setReloadError(message);

      // Rollback to last saved config
      if (lastSavedBackup) {
        const { config: restored } = restoreRoutesBackup(lastSavedBackup, assetIds);
        if (restored) {
          setConfig(restored);
          setIsDirty(false);
        }
      }
    } finally {
      setIsReloading(false);
    }
  }, [config, onReloadCore, lastSavedBackup, assetIds]);

  // Revert handler
  const handleRevert = useCallback(() => {
    if (!lastSavedBackup) return;

    const { config: restored } = restoreRoutesBackup(lastSavedBackup, assetIds);
    if (restored) {
      setConfig(restored);
      setIsDirty(false);
    }
  }, [lastSavedBackup, assetIds]);

  // Refresh from disk
  const handleRefresh = useCallback(async () => {
    if (!storageRef.current) return;

    setIsLoading(true);
    const result = await storageRef.current.load();
    setConfig(result.config);
    setValidation(result.validation);
    setLastSavedBackup(createRoutesBackup(result.config));
    setIsDirty(false);
    setIsLoading(false);
  }, []);

  if (isLoading) {
    return (
      <div className="rf-routes-editor rf-routes-loading">
        <div className="rf-routes-loading-spinner" />
        <div>Loading routes...</div>
      </div>
    );
  }

  return (
    <div className="rf-routes-editor">
      {/* Header */}
      <div className="rf-routes-header">
        <div className="rf-routes-title">
          <span className="rf-routes-title-icon">🔀</span>
          <span>Routes Editor</span>
          {isDirty && <span className="rf-routes-dirty-indicator">*</span>}
        </div>
        <div className="rf-routes-path" title={routesPath}>
          {routesPath}
        </div>
        <div className="rf-routes-controls">
          <button
            className="rf-routes-btn rf-routes-btn-refresh"
            onClick={handleRefresh}
            title="Reload from disk"
          >
            ⟳ Refresh
          </button>
          <button
            className="rf-routes-btn rf-routes-btn-revert"
            onClick={handleRevert}
            disabled={!isDirty}
            title="Revert to last saved"
          >
            ↩ Revert
          </button>
          {onReloadCore && (
            <button
              className="rf-routes-btn rf-routes-btn-reload"
              onClick={handleReload}
              disabled={!validation.valid || isReloading}
              title={!validation.valid ? 'Fix errors before reloading' : 'Reload native core'}
            >
              {isReloading ? '⏳ Reloading...' : '🔄 Reload Core'}
            </button>
          )}
        </div>
      </div>

      {/* Validation Summary */}
      {(validation.errors.length > 0 || validation.warnings.length > 0) && (
        <div className="rf-routes-validation">
          {validation.errors.length > 0 && (
            <div className="rf-routes-validation-errors">
              <span className="rf-routes-validation-icon">❌</span>
              <span>{validation.errors.length} error(s)</span>
            </div>
          )}
          {validation.warnings.length > 0 && (
            <div className="rf-routes-validation-warnings">
              <span className="rf-routes-validation-icon">⚠️</span>
              <span>{validation.warnings.length} warning(s)</span>
            </div>
          )}
        </div>
      )}

      {/* Reload Error */}
      {reloadError && (
        <div className="rf-routes-reload-error">
          <span className="rf-routes-reload-error-icon">⚠️</span>
          <span>Reload failed: {reloadError}. Reverted to last saved config.</span>
        </div>
      )}

      {/* Main Content - 2 Panes */}
      <div className="rf-routes-content">
        {/* Left Pane - Event List */}
        <div className="rf-routes-events-pane">
          <div className="rf-routes-events-header">
            <input
              type="text"
              className="rf-routes-search"
              placeholder="Search events..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            <button className="rf-routes-btn rf-routes-btn-add" onClick={handleAddEvent}>
              + Add Event
            </button>
          </div>
          <div className="rf-routes-events-list">
            {filteredEvents.map((event) => {
              const originalIndex = config.events.indexOf(event);
              const errors = getEventErrors(originalIndex);
              const warnings = getEventWarnings(originalIndex);
              const hasErrors = errors.length > 0;
              const hasWarnings = warnings.length > 0;

              return (
                <div
                  key={originalIndex}
                  className={`rf-routes-event-item ${selectedEventIndex === originalIndex ? 'selected' : ''} ${hasErrors ? 'has-errors' : ''} ${hasWarnings ? 'has-warnings' : ''}`}
                  onClick={() => setSelectedEventIndex(originalIndex)}
                >
                  <div className="rf-routes-event-status">
                    {hasErrors && <span className="rf-routes-status-error">●</span>}
                    {!hasErrors && hasWarnings && (
                      <span className="rf-routes-status-warning">●</span>
                    )}
                    {!hasErrors && !hasWarnings && (
                      <span className="rf-routes-status-ok">●</span>
                    )}
                  </div>
                  <div className="rf-routes-event-name">{event.name}</div>
                  <div className="rf-routes-event-actions-count">
                    {event.actions.length} action{event.actions.length !== 1 ? 's' : ''}
                  </div>
                  <button
                    className="rf-routes-event-delete"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDeleteEvent(originalIndex);
                    }}
                    title="Delete event"
                  >
                    ×
                  </button>
                </div>
              );
            })}
            {filteredEvents.length === 0 && (
              <div className="rf-routes-no-events">
                {searchQuery ? 'No matching events' : 'No events defined'}
              </div>
            )}
          </div>
        </div>

        {/* Right Pane - Action Editor */}
        <div className="rf-routes-actions-pane">
          {selectedEvent ? (
            <>
              <div className="rf-routes-actions-header">
                <div className="rf-routes-event-name-edit">
                  <label>Event Name:</label>
                  <input
                    type="text"
                    value={selectedEvent.name}
                    onChange={(e) =>
                      handleUpdateEventName(selectedEventIndex!, e.target.value)
                    }
                    className={
                      getEventErrors(selectedEventIndex!).some((e) => e.field === 'name')
                        ? 'has-error'
                        : ''
                    }
                  />
                </div>
                <div className="rf-routes-action-buttons">
                  {ROUTE_ACTION_TYPES.map((type) => (
                    <button
                      key={type}
                      className="rf-routes-btn rf-routes-btn-action-type"
                      onClick={() => handleAddAction(type)}
                      title={`Add ${type} action`}
                    >
                      + {type}
                    </button>
                  ))}
                  {/* M6.9: Action Templates */}
                  <ActionTemplates
                    onSelect={handleTemplateSelect}
                    disabled={selectedEventIndex === null}
                  />
                </div>
              </div>

              {/* Event Errors */}
              {getEventErrors(selectedEventIndex!).length > 0 && (
                <div className="rf-routes-event-errors">
                  {getEventErrors(selectedEventIndex!).map((error, i) => (
                    <div key={i} className="rf-routes-error-item">
                      <span className="rf-routes-error-location">
                        {formatErrorLocation(error)}:
                      </span>
                      <span className="rf-routes-error-message">{error.message}</span>
                    </div>
                  ))}
                </div>
              )}

              {/* Actions List */}
              <div className="rf-routes-actions-list">
                {selectedEvent.actions.map((action, actionIndex) => (
                  <div
                    key={actionIndex}
                    className={`rf-routes-action-item ${draggedActionIndex === actionIndex ? 'dragging' : ''}`}
                    draggable
                    onDragStart={() => handleDragStart(actionIndex)}
                    onDragOver={(e) => handleDragOver(e, actionIndex)}
                    onDrop={() => handleDrop(actionIndex)}
                    onDragEnd={() => setDraggedActionIndex(null)}
                  >
                    <div className="rf-routes-action-drag-handle">⋮⋮</div>
                    <div className="rf-routes-action-type-badge">{action.type}</div>
                    <div className="rf-routes-action-fields">
                      {renderActionFields(
                        action,
                        actionIndex,
                        config.defaultBus,
                        handleUpdateAction,
                        validation.errors.filter(
                          (err) =>
                            err.eventIndex === selectedEventIndex &&
                            err.actionIndex === actionIndex
                        ),
                        effectiveAssetIndex,
                        getAssetPickerRef(actionIndex)
                      )}
                    </div>
                    <button
                      className="rf-routes-action-delete"
                      onClick={() => handleDeleteAction(actionIndex)}
                      title="Delete action"
                    >
                      ×
                    </button>
                  </div>
                ))}
                {selectedEvent.actions.length === 0 && (
                  <div className="rf-routes-no-actions">
                    No actions. Click a button above to add one.
                  </div>
                )}
              </div>
            </>
          ) : (
            <div className="rf-routes-no-selection">
              Select an event to edit its actions
            </div>
          )}
        </div>
      </div>

      {/* M6.9: Simulation Panel */}
      {showSimulation && (
        <div className="rf-routes-simulation">
          <RouteSimulationPanel
            config={config}
            nativeCore={nativeCore}
            selectedEventName={selectedEvent?.name}
          />
        </div>
      )}

      {/* Footer Stats */}
      <div className="rf-routes-footer">
        <span>Version: {config.routesVersion}</span>
        <span>Default Bus: {config.defaultBus}</span>
        <span>Events: {config.events.length}</span>
        <span>
          Total Actions:{' '}
          {config.events.reduce((sum, e) => sum + e.actions.length, 0)}
        </span>
      </div>
    </div>
  );
}

/**
 * Render action fields based on type.
 * M6.9: Added assetIndex and inputRef for AssetPicker support.
 */
function renderActionFields(
  action: RouteAction,
  actionIndex: number,
  defaultBus: RouteBus,
  onUpdate: (index: number, updates: Partial<RouteAction>) => void,
  errors: RouteValidationError[],
  assetIndex: AssetIndex,
  inputRef: { current: HTMLInputElement | null }
): React.ReactNode {
  const getFieldError = (field: string) =>
    errors.find((e) => e.field === field)?.message;

  switch (action.type) {
    case 'Play': {
      const playAction = action as PlayAction;
      return (
        <>
          <div className="rf-routes-field rf-routes-field-asset">
            <label>Asset ID:</label>
            {/* M6.9: AssetPicker replaces text input */}
            <AssetPicker
              value={playAction.assetId}
              onChange={(assetId) => onUpdate(actionIndex, { assetId })}
              assetIndex={assetIndex}
              hasError={!!getFieldError('assetId')}
              placeholder="Search assets..."
              inputRef={inputRef}
            />
            {getFieldError('assetId') && (
              <span className="rf-routes-field-error">{getFieldError('assetId')}</span>
            )}
          </div>
          <div className="rf-routes-field">
            <label>Bus:</label>
            <select
              value={playAction.bus || defaultBus}
              onChange={(e) => onUpdate(actionIndex, { bus: e.target.value as RouteBus })}
              className={getFieldError('bus') ? 'has-error' : ''}
            >
              {PUBLIC_BUSES.map((bus) => (
                <option key={bus} value={bus}>
                  {bus}
                </option>
              ))}
            </select>
          </div>
          <div className="rf-routes-field">
            <label>Gain:</label>
            <input
              type="number"
              min={0}
              max={1}
              step={0.1}
              value={playAction.gain ?? 1.0}
              onChange={(e) => onUpdate(actionIndex, { gain: parseFloat(e.target.value) })}
              className={getFieldError('gain') ? 'has-error' : ''}
            />
          </div>
          <div className="rf-routes-field rf-routes-field-checkbox">
            <label>
              <input
                type="checkbox"
                checked={playAction.loop ?? false}
                onChange={(e) => onUpdate(actionIndex, { loop: e.target.checked })}
              />
              Loop
            </label>
          </div>
        </>
      );
    }

    case 'SetBusGain': {
      const busGainAction = action as SetBusGainAction;
      return (
        <>
          <div className="rf-routes-field">
            <label>Bus:</label>
            <select
              value={busGainAction.bus}
              onChange={(e) => onUpdate(actionIndex, { bus: e.target.value as RouteBus })}
              className={getFieldError('bus') ? 'has-error' : ''}
            >
              {PUBLIC_BUSES.map((bus) => (
                <option key={bus} value={bus}>
                  {bus}
                </option>
              ))}
            </select>
          </div>
          <div className="rf-routes-field">
            <label>Gain:</label>
            <input
              type="number"
              min={0}
              max={1}
              step={0.1}
              value={busGainAction.gain}
              onChange={(e) => onUpdate(actionIndex, { gain: parseFloat(e.target.value) })}
              className={getFieldError('gain') ? 'has-error' : ''}
            />
            {getFieldError('gain') && (
              <span className="rf-routes-field-error">{getFieldError('gain')}</span>
            )}
          </div>
        </>
      );
    }

    case 'StopAll':
      return <div className="rf-routes-action-info">Stops all playing voices</div>;

    case 'Stop':
      return <div className="rf-routes-action-info">Stop (voiceId set at runtime)</div>;

    default:
      return null;
  }
}
