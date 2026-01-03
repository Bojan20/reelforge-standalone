/**
 * Welcome Screen
 *
 * Initial landing screen for ReelForge Editor:
 * - Recent projects list
 * - New/Open project actions
 * - Drag & drop audio import
 * - Quick start guide
 *
 * @module components/WelcomeScreen
 */

import { memo, useState, useCallback, useRef } from 'react';
import './WelcomeScreen.css';
import reelforgeLogo from '../assets/reelforge-logo.png';

// ============ TYPES ============

export interface RecentProject {
  id: string;
  name: string;
  path: string;
  lastOpened: Date;
  thumbnail?: string;
}

export interface WelcomeScreenProps {
  /** List of recent projects */
  recentProjects?: RecentProject[];
  /** When new project is requested */
  onNewProject?: () => void;
  /** When project is opened */
  onOpenProject?: (path?: string) => void;
  /** When recent project is selected */
  onSelectRecentProject?: (project: RecentProject) => void;
  /** When audio files are imported */
  onImportAudioFiles?: (files: File[]) => void;
  /** When user wants to skip to main editor */
  onEnterEditor?: () => void;
  /** App version */
  version?: string;
}

// ============ WELCOME SCREEN ============

export const WelcomeScreen = memo(function WelcomeScreen({
  recentProjects = [],
  onNewProject,
  onOpenProject,
  onSelectRecentProject,
  onImportAudioFiles,
  onEnterEditor,
  version = '1.0.0-preview',
}: WelcomeScreenProps) {
  const [isDragOver, setIsDragOver] = useState(false);
  const [importedCount, setImportedCount] = useState(0);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Handle drag events
  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);

    const files = Array.from(e.dataTransfer.files).filter(
      (file) => file.type.startsWith('audio/') ||
                file.name.endsWith('.wav') ||
                file.name.endsWith('.mp3') ||
                file.name.endsWith('.ogg') ||
                file.name.endsWith('.flac')
    );

    if (files.length > 0) {
      setImportedCount(files.length);
      onImportAudioFiles?.(files);
    }
  }, [onImportAudioFiles]);

  // Handle file input
  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length > 0) {
      setImportedCount(files.length);
      onImportAudioFiles?.(files);
    }
  }, [onImportAudioFiles]);

  const handleBrowseClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  // Format date
  const formatDate = (date: Date) => {
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    return date.toLocaleDateString();
  };

  return (
    <div className="rf-welcome">
      {/* Background Pattern */}
      <div className="rf-welcome__bg" />

      {/* Main Content */}
      <div className="rf-welcome__content">
        {/* Header */}
        <header className="rf-welcome__header">
          <div className="rf-welcome__logo">
            <img
              src={reelforgeLogo}
              alt="ReelForge"
              className="rf-welcome__logo-img"
            />
            <div className="rf-welcome__logo-text">
              <h1>ReelForge</h1>
              <span className="rf-welcome__subtitle">Audio Middleware Editor</span>
            </div>
          </div>
          <span className="rf-welcome__version">v{version}</span>
        </header>

        {/* Main Grid */}
        <div className="rf-welcome__grid">
          {/* Left Column - Actions */}
          <div className="rf-welcome__actions">
            <h2>Start</h2>

            <button
              className="rf-welcome__action rf-welcome__action--primary"
              onClick={onNewProject}
            >
              <span className="rf-welcome__action-icon">+</span>
              <div className="rf-welcome__action-text">
                <span className="rf-welcome__action-title">New Project</span>
                <span className="rf-welcome__action-desc">Create a new audio project</span>
              </div>
            </button>

            <button
              className="rf-welcome__action"
              onClick={() => onOpenProject?.()}
            >
              <span className="rf-welcome__action-icon">📂</span>
              <div className="rf-welcome__action-text">
                <span className="rf-welcome__action-title">Open Project</span>
                <span className="rf-welcome__action-desc">Open an existing .rfproj file</span>
              </div>
            </button>

            <button
              className="rf-welcome__action"
              onClick={onEnterEditor}
            >
              <span className="rf-welcome__action-icon">🎛️</span>
              <div className="rf-welcome__action-text">
                <span className="rf-welcome__action-title">Enter Editor</span>
                <span className="rf-welcome__action-desc">Skip to main workspace</span>
              </div>
            </button>

            {/* Import Drop Zone */}
            <div
              className={`rf-welcome__dropzone ${isDragOver ? 'rf-welcome__dropzone--active' : ''} ${importedCount > 0 ? 'rf-welcome__dropzone--success' : ''}`}
              onDragEnter={handleDragEnter}
              onDragLeave={handleDragLeave}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
              onClick={handleBrowseClick}
            >
              <input
                ref={fileInputRef}
                type="file"
                accept="audio/*,.wav,.mp3,.ogg,.flac"
                multiple
                onChange={handleFileSelect}
                style={{ display: 'none' }}
              />

              {importedCount > 0 ? (
                <>
                  <span className="rf-welcome__dropzone-icon">✓</span>
                  <span className="rf-welcome__dropzone-text">
                    {importedCount} file{importedCount > 1 ? 's' : ''} imported
                  </span>
                </>
              ) : (
                <>
                  <span className="rf-welcome__dropzone-icon">🎵</span>
                  <span className="rf-welcome__dropzone-text">
                    {isDragOver ? 'Drop audio files here' : 'Drag audio files or click to browse'}
                  </span>
                  <span className="rf-welcome__dropzone-hint">
                    Supports WAV, MP3, OGG, FLAC
                  </span>
                </>
              )}
            </div>
          </div>

          {/* Right Column - Recent Projects */}
          <div className="rf-welcome__recent">
            <h2>Recent Projects</h2>

            {recentProjects.length === 0 ? (
              <div className="rf-welcome__empty">
                <span className="rf-welcome__empty-icon">📁</span>
                <p>No recent projects</p>
                <span className="rf-welcome__empty-hint">
                  Your recently opened projects will appear here
                </span>
              </div>
            ) : (
              <div className="rf-welcome__projects">
                {recentProjects.map((project) => (
                  <button
                    key={project.id}
                    className="rf-welcome__project"
                    onClick={() => onSelectRecentProject?.(project)}
                  >
                    <div className="rf-welcome__project-thumb">
                      {project.thumbnail ? (
                        <img src={project.thumbnail} alt="" />
                      ) : (
                        <span>🎚️</span>
                      )}
                    </div>
                    <div className="rf-welcome__project-info">
                      <span className="rf-welcome__project-name">{project.name}</span>
                      <span className="rf-welcome__project-path">{project.path}</span>
                      <span className="rf-welcome__project-date">
                        {formatDate(project.lastOpened)}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <footer className="rf-welcome__footer">
          <div className="rf-welcome__footer-links">
            <a href="#docs">Documentation</a>
            <a href="#tutorials">Tutorials</a>
            <a href="#support">Support</a>
          </div>
          <span className="rf-welcome__copyright">
            ReelForge Audio Middleware
          </span>
        </footer>
      </div>
    </div>
  );
});

export default WelcomeScreen;
