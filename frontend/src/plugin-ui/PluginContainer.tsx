/**
 * Plugin Container Component
 *
 * Root container for plugin UIs with theme and preset bar.
 *
 * @module plugin-ui/PluginContainer
 */

import { memo, type ReactNode } from 'react';
import { usePluginTheme } from './usePluginTheme';
import { PresetBar, type PresetBarProps } from './preset/PresetBar';
import './PluginContainer.css';

export interface PluginContainerProps {
  /** Plugin content */
  children: ReactNode;
  /** Plugin name */
  pluginName: string;
  /** Plugin version */
  version?: string;
  /** Width */
  width?: number | string;
  /** Height */
  height?: number | string;
  /** Min width */
  minWidth?: number;
  /** Min height */
  minHeight?: number;
  /** Show preset bar */
  showPresetBar?: boolean;
  /** Preset bar props */
  presetBarProps?: Partial<PresetBarProps>;
  /** Custom class */
  className?: string;
}

function PluginContainerInner({
  children,
  pluginName,
  version,
  width = '100%',
  height = '100%',
  minWidth = 400,
  minHeight = 300,
  showPresetBar = true,
  presetBarProps,
  className,
}: PluginContainerProps) {
  const theme = usePluginTheme();

  return (
    <div
      className={`plugin-container ${className ?? ''}`}
      style={{
        width,
        height,
        minWidth,
        minHeight,
        background: theme.bgPrimary,
        color: theme.textPrimary,
      }}
      data-plugin={pluginName}
    >
      {/* Header */}
      <div
        className="plugin-container__header"
        style={{
          background: theme.bgSecondary,
          borderColor: theme.border,
        }}
      >
        <div className="plugin-container__title">
          <span className="plugin-container__name" style={{ color: theme.textPrimary }}>
            {pluginName}
          </span>
          {version && (
            <span className="plugin-container__version" style={{ color: theme.textMuted }}>
              v{version}
            </span>
          )}
        </div>
      </div>

      {/* Preset bar */}
      {showPresetBar && (
        <PresetBar
          presetName={presetBarProps?.presetName ?? 'Default'}
          {...presetBarProps}
        />
      )}

      {/* Content */}
      <div className="plugin-container__content">
        {children}
      </div>
    </div>
  );
}

export const PluginContainer = memo(PluginContainerInner);
export default PluginContainer;
