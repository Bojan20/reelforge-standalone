/**
 * ReelForge History Panel
 *
 * Visual history browser:
 * - Action list
 * - Click to jump to state
 * - Undo/redo buttons
 * - Clear history
 *
 * @module history/HistoryPanel
 */

import { useCallback } from 'react';
import './HistoryPanel.css';

// ============ Types ============

export interface HistoryAction {
  id: string;
  type: string;
  description: string;
  timestamp: number;
  groupId?: string;
}

export interface HistoryPanelProps {
  /** Past actions */
  past: HistoryAction[];
  /** Future actions */
  future: HistoryAction[];
  /** Current index */
  currentIndex: number;
  /** Can undo */
  canUndo: boolean;
  /** Can redo */
  canRedo: boolean;
  /** On undo */
  onUndo: () => void;
  /** On redo */
  onRedo: () => void;
  /** On jump to action */
  onJumpTo: (actionId: string, isFuture: boolean) => void;
  /** On clear */
  onClear?: () => void;
  /** On close */
  onClose?: () => void;
}

// ============ Helpers ============

function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;

  if (diff < 1000) return 'just now';
  if (diff < 60000) return `${Math.floor(diff / 1000)}s ago`;
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
  return formatTime(timestamp);
}

const ACTION_ICONS: Record<string, string> = {
  'clip.move': '↔',
  'clip.trim': '✂',
  'clip.delete': '×',
  'clip.add': '+',
  'track.add': '▤',
  'track.delete': '▤',
  'marker.add': '⚑',
  'marker.delete': '⚑',
  'automation.edit': '〰',
  'parameter.change': '◉',
  'default': '•',
};

function getActionIcon(type: string): string {
  return ACTION_ICONS[type] || ACTION_ICONS['default'];
}

// ============ Component ============

export function HistoryPanel({
  past,
  future,
  currentIndex,
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  onJumpTo,
  onClear,
  onClose,
}: HistoryPanelProps) {
  // Handle action click
  const handleActionClick = useCallback(
    (action: HistoryAction, isFuture: boolean) => {
      onJumpTo(action.id, isFuture);
    },
    [onJumpTo]
  );

  // Keyboard shortcuts
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'z' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        if (e.shiftKey) {
          onRedo();
        } else {
          onUndo();
        }
      }
    },
    [onUndo, onRedo]
  );

  return (
    <div className="history-panel" onKeyDown={handleKeyDown} tabIndex={0}>
      {/* Header */}
      <div className="history-panel__header">
        <h3>History</h3>
        <div className="history-panel__actions">
          <button
            className="history-panel__btn"
            onClick={onUndo}
            disabled={!canUndo}
            title="Undo (Cmd+Z)"
          >
            ↶
          </button>
          <button
            className="history-panel__btn"
            onClick={onRedo}
            disabled={!canRedo}
            title="Redo (Cmd+Shift+Z)"
          >
            ↷
          </button>
          {onClear && (
            <button
              className="history-panel__btn history-panel__btn--danger"
              onClick={onClear}
              title="Clear history"
            >
              ⌫
            </button>
          )}
          {onClose && (
            <button className="history-panel__close" onClick={onClose}>
              ×
            </button>
          )}
        </div>
      </div>

      {/* Action list */}
      <div className="history-panel__list">
        {/* Initial state */}
        <div
          className={`history-panel__item history-panel__item--initial ${
            currentIndex === -1 ? 'history-panel__item--current' : ''
          }`}
        >
          <span className="history-panel__item-icon">◯</span>
          <span className="history-panel__item-desc">Initial State</span>
        </div>

        {/* Past actions */}
        {past.map((action, index) => (
          <div
            key={action.id}
            className={`history-panel__item ${
              index === currentIndex ? 'history-panel__item--current' : ''
            } ${action.groupId ? 'history-panel__item--grouped' : ''}`}
            onClick={() => handleActionClick(action, false)}
          >
            <span className="history-panel__item-icon">
              {getActionIcon(action.type)}
            </span>
            <span className="history-panel__item-desc">{action.description}</span>
            <span className="history-panel__item-time">
              {formatRelativeTime(action.timestamp)}
            </span>
          </div>
        ))}

        {/* Divider if there are future actions */}
        {future.length > 0 && (
          <div className="history-panel__divider">
            <span>Future ({future.length})</span>
          </div>
        )}

        {/* Future actions */}
        {future.map((action) => (
          <div
            key={action.id}
            className={`history-panel__item history-panel__item--future ${
              action.groupId ? 'history-panel__item--grouped' : ''
            }`}
            onClick={() => handleActionClick(action, true)}
          >
            <span className="history-panel__item-icon">
              {getActionIcon(action.type)}
            </span>
            <span className="history-panel__item-desc">{action.description}</span>
            <span className="history-panel__item-time">
              {formatRelativeTime(action.timestamp)}
            </span>
          </div>
        ))}

        {/* Empty state */}
        {past.length === 0 && future.length === 0 && (
          <div className="history-panel__empty">
            No history yet
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="history-panel__footer">
        <span>{past.length} actions</span>
        {future.length > 0 && <span>{future.length} redoable</span>}
      </div>
    </div>
  );
}

export default HistoryPanel;
