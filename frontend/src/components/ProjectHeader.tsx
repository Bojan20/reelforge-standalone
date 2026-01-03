/**
 * ReelForge M7.0 Project Header
 *
 * Project controls: Open, Save, Save As.
 * Shows project name and dirty indicator.
 */

import { useCallback, useEffect, useState } from 'react';
import { useProject } from '../project/ProjectContext';
import './ProjectHeader.css';

interface ProjectHeaderProps {
  /** Callback when routes change (for native core reload) */
  onRoutesChanged?: () => void;
}

export default function ProjectHeader({ onRoutesChanged }: ProjectHeaderProps) {
  const {
    project,
    isDirty,
    isLoading,
    error,
    openProject,
    saveProject,
    saveProjectAs,
    setProjectName,
  } = useProject();

  const [isEditing, setIsEditing] = useState(false);
  const [editName, setEditName] = useState('');

  const handleOpen = useCallback(async () => {
    const success = await openProject();
    if (success) {
      onRoutesChanged?.();
    }
  }, [openProject, onRoutesChanged]);

  const handleSave = useCallback(async () => {
    await saveProject();
  }, [saveProject]);

  const handleSaveAs = useCallback(async () => {
    await saveProjectAs();
  }, [saveProjectAs]);

  const handleNameClick = useCallback(() => {
    setEditName(project.name);
    setIsEditing(true);
  }, [project.name]);

  const handleNameBlur = useCallback(() => {
    if (editName.trim() && editName !== project.name) {
      setProjectName(editName.trim());
    }
    setIsEditing(false);
  }, [editName, project.name, setProjectName]);

  const handleNameKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleNameBlur();
    } else if (e.key === 'Escape') {
      setIsEditing(false);
    }
  }, [handleNameBlur]);

  // Global keyboard shortcuts for Save (Ctrl+S) and Open (Ctrl+O)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
      const modifier = isMac ? e.metaKey : e.ctrlKey;

      if (modifier && e.key === 's') {
        e.preventDefault();
        if (e.shiftKey) {
          // Ctrl+Shift+S = Save As
          saveProjectAs();
        } else {
          // Ctrl+S = Save
          saveProject();
        }
      } else if (modifier && e.key === 'o') {
        e.preventDefault();
        handleOpen();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [saveProject, saveProjectAs, handleOpen]);

  if (isLoading) {
    return (
      <div className="rf-project-header rf-project-header-loading">
        <div className="rf-project-loading">Loading project...</div>
      </div>
    );
  }

  return (
    <div className="rf-project-header">
      <div className="rf-project-info">
        <div className="rf-project-icon">📁</div>
        {isEditing ? (
          <input
            type="text"
            className="rf-project-name-input"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            onBlur={handleNameBlur}
            onKeyDown={handleNameKeyDown}
            autoFocus
          />
        ) : (
          <div
            className="rf-project-name"
            onClick={handleNameClick}
            title="Click to rename"
          >
            {project.name}
            {isDirty && <span className="rf-project-dirty">*</span>}
          </div>
        )}
        {project.routes.embed ? (
          <span className="rf-project-mode rf-project-mode-embed" title="Routes embedded in project">
            embedded
          </span>
        ) : (
          <span className="rf-project-mode rf-project-mode-external" title="Routes loaded from external file">
            external
          </span>
        )}
      </div>

      {error && (
        <div className="rf-project-error" title={error}>
          {error}
        </div>
      )}

      <div className="rf-project-controls">
        <button
          className="rf-project-btn"
          onClick={handleOpen}
          title="Opens a ReelForge project file (.json)"
        >
          <span className="rf-project-btn-icon">📂</span>
          <span className="rf-project-btn-text">Open</span>
        </button>
        <button
          className="rf-project-btn"
          onClick={handleSave}
          disabled={!isDirty}
          title="Saves reelforge_project.json (and external routes if configured)"
        >
          <span className="rf-project-btn-icon">💾</span>
          <span className="rf-project-btn-text">Save</span>
        </button>
        <button
          className="rf-project-btn"
          onClick={handleSaveAs}
          title="Saves project with a new filename"
        >
          <span className="rf-project-btn-icon">📄</span>
          <span className="rf-project-btn-text">Save As</span>
        </button>
      </div>
    </div>
  );
}
