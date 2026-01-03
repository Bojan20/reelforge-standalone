/**
 * ReelForge M7.0 Project Routes Editor
 *
 * Wrapper around RoutesEditor that integrates with ProjectContext.
 * Handles embedded vs external routes modes.
 */

import { useCallback } from 'react';
import { useProject } from '../project/ProjectContext';
import RoutesEditor from './RoutesEditor';
import type { RoutesConfig } from '../core/routesTypes';
import type { NativeRuntimeCoreWrapper } from '../core/nativeRuntimeCore';
import './ProjectRoutesEditor.css';

interface ProjectRoutesEditorProps {
  /** Native core instance for simulation and reload */
  nativeCore?: NativeRuntimeCoreWrapper | null;
  /** Show simulation panel */
  showSimulation?: boolean;
}

/**
 * Project-aware Routes Editor.
 *
 * - For embedded mode: edits update project.routes.data directly
 * - For external mode: edits update working copy, save writes to routesPath
 */
export default function ProjectRoutesEditor({
  nativeCore,
  showSimulation = false,
}: ProjectRoutesEditorProps) {
  const {
    project,
    workingRoutes,
    assetIds,
    assetIndex,
    isLoading,
    error,
    reloadExternalRoutes,
    isEmbedded,
  } = useProject();

  // Handle core reload (native core hot-reload)
  const handleReloadCore = useCallback(async (config: RoutesConfig): Promise<boolean> => {
    if (!nativeCore) {
      console.warn('[ProjectRoutesEditor] No native core available for reload');
      return false;
    }

    try {
      // Serialize config to JSON and reload via wrapper
      const json = JSON.stringify(config);
      nativeCore.reloadRoutesFromString(json);
      console.log('[ProjectRoutesEditor] Core reloaded with new routes');
      return true;
    } catch (err) {
      console.error('[ProjectRoutesEditor] Core reload failed:', err);
      return false;
    }
  }, [nativeCore]);

  // Handle refresh for external routes
  const handleRefresh = useCallback(async () => {
    if (!isEmbedded()) {
      await reloadExternalRoutes();
    }
  }, [isEmbedded, reloadExternalRoutes]);

  if (isLoading) {
    return (
      <div className="rf-project-routes-editor rf-project-routes-loading">
        <div className="rf-project-routes-spinner" />
        <div>Loading routes...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rf-project-routes-editor rf-project-routes-error">
        <div className="rf-project-routes-error-icon">!</div>
        <div className="rf-project-routes-error-message">{error}</div>
        {!isEmbedded() && (
          <button
            className="rf-project-routes-retry-btn"
            onClick={handleRefresh}
          >
            Retry
          </button>
        )}
      </div>
    );
  }

  if (!workingRoutes) {
    return (
      <div className="rf-project-routes-editor rf-project-routes-empty">
        <div className="rf-project-routes-empty-icon">!</div>
        <div>No routes loaded</div>
      </div>
    );
  }

  // Determine the path to show based on mode
  const displayPath = isEmbedded()
    ? `${project.name} (embedded)`
    : project.paths.routesPath || 'Unknown path';

  return (
    <div className="rf-project-routes-editor">
      {/* Mode indicator */}
      <div className="rf-project-routes-mode-bar">
        <span className={`rf-project-routes-mode ${isEmbedded() ? 'embedded' : 'external'}`}>
          {isEmbedded() ? 'Embedded Routes' : 'External Routes'}
        </span>
        {isEmbedded() ? (
          <span className="rf-project-routes-hint">
            Source: Project file — Use "Reload Core" after edits
          </span>
        ) : (
          <>
            <span className="rf-project-routes-path" title={project.paths.routesPath}>
              {project.paths.routesPath}
            </span>
            <button
              className="rf-project-routes-refresh-btn"
              onClick={handleRefresh}
              title="Reload from external file"
            >
              Refresh
            </button>
          </>
        )}
      </div>

      {/* RoutesEditor with project integration */}
      {/* NOTE: For now RoutesEditor still loads from path. In a future iteration,
          we could refactor it to accept controlled routes state from project context
          using handleRoutesChange for updates. */}
      <RoutesEditor
        routesPath={displayPath}
        assetIds={assetIds ?? undefined}
        assetIndex={assetIndex ?? undefined}
        nativeCore={nativeCore}
        onReloadCore={handleReloadCore}
        showSimulation={showSimulation}
      />
    </div>
  );
}
