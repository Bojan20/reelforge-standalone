/**
 * ReelForge M6.9 Action Templates
 *
 * One-click presets for common route actions.
 * Templates are inserted at end of actions array.
 */

import { useState, useRef, useEffect, useCallback } from 'react';
import type { RouteAction } from '../core/routesTypes';
import './ActionTemplates.css';

export interface ActionTemplate {
  id: string;
  label: string;
  icon: string;
  description: string;
  action: RouteAction;
  /** Should focus Asset Picker after insert? */
  focusAssetPicker?: boolean;
}

/**
 * Built-in action templates (M6.9 spec).
 */
export const ACTION_TEMPLATES: ActionTemplate[] = [
  {
    id: 'play-sfx-oneshot',
    label: 'Play SFX One-shot',
    icon: '🔊',
    description: 'Play a one-shot SFX sound',
    action: {
      type: 'Play',
      assetId: '',
      bus: 'SFX',
      gain: 1.0,
      loop: false,
    },
    focusAssetPicker: true,
  },
  {
    id: 'play-sfx-loop',
    label: 'Play Loop (SFX)',
    icon: '🔁',
    description: 'Play a looping SFX sound',
    action: {
      type: 'Play',
      assetId: '',
      bus: 'SFX',
      gain: 1.0,
      loop: true,
    },
    focusAssetPicker: true,
  },
  {
    id: 'play-music-loop',
    label: 'Play Music Loop',
    icon: '🎵',
    description: 'Play looping music',
    action: {
      type: 'Play',
      assetId: '',
      bus: 'Music',
      gain: 1.0,
      loop: true,
    },
    focusAssetPicker: true,
  },
  {
    id: 'duck-music',
    label: 'Duck Music',
    icon: '🔉',
    description: 'Lower music volume (ducking)',
    action: {
      type: 'SetBusGain',
      bus: 'Music',
      gain: 0.35,
    },
    focusAssetPicker: false,
  },
  {
    id: 'stop-all',
    label: 'StopAll',
    icon: '⏹️',
    description: 'Stop all playing voices',
    action: {
      type: 'StopAll',
    },
    focusAssetPicker: false,
  },
];

interface ActionTemplatesProps {
  /** Callback when a template is selected */
  onSelect: (action: RouteAction, focusAssetPicker: boolean) => void;
  /** Disable the dropdown */
  disabled?: boolean;
}

export default function ActionTemplates({
  onSelect,
  disabled = false,
}: ActionTemplatesProps) {
  const [isOpen, setIsOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = useCallback(
    (template: ActionTemplate) => {
      // Deep clone the action to avoid mutation
      const actionClone = JSON.parse(JSON.stringify(template.action)) as RouteAction;
      onSelect(actionClone, template.focusAssetPicker ?? false);
      setIsOpen(false);
    },
    [onSelect]
  );

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') {
        setIsOpen(false);
      }
    },
    []
  );

  return (
    <div
      className={`rf-action-templates ${isOpen ? 'is-open' : ''}`}
      ref={containerRef}
      onKeyDown={handleKeyDown}
    >
      <button
        type="button"
        className="rf-action-templates-btn"
        onClick={() => setIsOpen(!isOpen)}
        disabled={disabled}
        title="Insert action from template"
      >
        <span className="rf-action-templates-icon">⚡</span>
        <span>Templates</span>
        <span className="rf-action-templates-arrow">{isOpen ? '▲' : '▼'}</span>
      </button>

      {isOpen && (
        <div className="rf-action-templates-dropdown">
          <div className="rf-action-templates-header">Action Templates</div>
          {ACTION_TEMPLATES.map((template) => (
            <button
              key={template.id}
              type="button"
              className="rf-action-templates-item"
              onClick={() => handleSelect(template)}
            >
              <span className="rf-action-templates-item-icon">{template.icon}</span>
              <div className="rf-action-templates-item-content">
                <span className="rf-action-templates-item-label">{template.label}</span>
                <span className="rf-action-templates-item-desc">{template.description}</span>
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
