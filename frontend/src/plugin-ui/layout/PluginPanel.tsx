/**
 * Plugin Panel Component
 *
 * Container panel for plugin UI sections.
 *
 * @module plugin-ui/layout/PluginPanel
 */

import { memo, type ReactNode } from 'react';
import { usePluginTheme } from '../usePluginTheme';
import './PluginPanel.css';

export interface PluginPanelProps {
  /** Panel content */
  children: ReactNode;
  /** Panel title */
  title?: string;
  /** Collapsible */
  collapsible?: boolean;
  /** Collapsed state (controlled) */
  collapsed?: boolean;
  /** Collapse toggle handler */
  onToggle?: () => void;
  /** Padding */
  padding?: 'none' | 'small' | 'medium' | 'large';
  /** Custom class */
  className?: string;
}

function PluginPanelInner({
  children,
  title,
  collapsible = false,
  collapsed = false,
  onToggle,
  padding = 'medium',
  className,
}: PluginPanelProps) {
  const theme = usePluginTheme();

  const handleHeaderClick = () => {
    if (collapsible && onToggle) {
      onToggle();
    }
  };

  return (
    <div
      className={`plugin-panel plugin-panel--padding-${padding} ${collapsed ? 'collapsed' : ''} ${className ?? ''}`}
      style={{
        background: theme.bgPanel,
        borderColor: theme.border,
      }}
    >
      {title && (
        <div
          className={`plugin-panel__header ${collapsible ? 'collapsible' : ''}`}
          onClick={handleHeaderClick}
          style={{ borderColor: theme.border }}
        >
          <span className="plugin-panel__title" style={{ color: theme.textSecondary }}>
            {title}
          </span>
          {collapsible && (
            <span className="plugin-panel__chevron" style={{ color: theme.textMuted }}>
              {collapsed ? '▶' : '▼'}
            </span>
          )}
        </div>
      )}
      {!collapsed && (
        <div className="plugin-panel__content">
          {children}
        </div>
      )}
    </div>
  );
}

export const PluginPanel = memo(PluginPanelInner);
export default PluginPanel;
