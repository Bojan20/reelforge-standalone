/**
 * ImportOptionsDialog Component
 *
 * Cubase-style import options dialog with:
 * - Copy to Project vs Reference mode
 * - Sample rate conversion options
 * - Mono/Stereo conversion
 * - Bit depth options
 *
 * @module components/ImportOptionsDialog
 */

import { useState, useCallback, useMemo } from 'react';
import './ImportOptionsDialog.css';

// ============ Types ============

export type ImportMode = 'copy' | 'reference';
export type SampleRateMode = 'keep' | 'convert';
export type ChannelMode = 'keep' | 'mono' | 'stereo';
export type TrackCreationMode = 'none' | 'one-track' | 'separate-tracks' | 'stacked';

export interface ImportOptions {
  /** Copy files to project folder or keep as external reference */
  mode: ImportMode;
  /** Sample rate handling */
  sampleRate: SampleRateMode;
  /** Target sample rate if converting */
  targetSampleRate: number;
  /** Channel mode */
  channelMode: ChannelMode;
  /** Normalize audio on import */
  normalize: boolean;
  /** Remember this choice */
  rememberChoice: boolean;
  /** Track creation mode (Cubase-style) */
  trackCreation: TrackCreationMode;
  /** Snap to grid on placement */
  snapToGrid: boolean;
}

export interface FileToImport {
  name: string;
  size: number;
  duration: number;
  sampleRate: number;
  channels: number;
  format: string;
}

export interface ImportOptionsDialogProps {
  /** Files being imported */
  files: FileToImport[];
  /** Project sample rate for conversion reference */
  projectSampleRate?: number;
  /** Default options */
  defaultOptions?: Partial<ImportOptions>;
  /** Called when user confirms import */
  onImport: (options: ImportOptions) => void;
  /** Called when user cancels */
  onCancel: () => void;
  /** Is dialog open */
  isOpen: boolean;
}

// ============ Utilities ============

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

function formatSampleRate(sr: number): string {
  return `${(sr / 1000).toFixed(1)} kHz`;
}

// ============ Default Options ============

const DEFAULT_OPTIONS: ImportOptions = {
  mode: 'copy',
  sampleRate: 'convert', // Always convert to project rate by default
  targetSampleRate: 48000,
  channelMode: 'keep',
  normalize: false,
  rememberChoice: false,
  trackCreation: 'separate-tracks', // Cubase default: each file gets its own track
  snapToGrid: true,
};

// ============ Component ============

export function ImportOptionsDialog({
  files,
  projectSampleRate = 48000,
  defaultOptions,
  onImport,
  onCancel,
  isOpen,
}: ImportOptionsDialogProps) {
  // Merge defaults with provided options
  const initialOptions: ImportOptions = {
    ...DEFAULT_OPTIONS,
    targetSampleRate: projectSampleRate,
    ...defaultOptions,
  };

  const [options, setOptions] = useState<ImportOptions>(initialOptions);

  // Calculate totals
  const summary = useMemo(() => {
    const totalSize = files.reduce((sum, f) => sum + f.size, 0);
    const totalDuration = files.reduce((sum, f) => sum + f.duration, 0);
    const needsSRConversion = files.some(f => f.sampleRate !== projectSampleRate);
    const hasMixed = new Set(files.map(f => f.channels)).size > 1;

    return {
      count: files.length,
      totalSize,
      totalDuration,
      needsSRConversion,
      hasMixed,
    };
  }, [files, projectSampleRate]);

  // Update option
  const updateOption = useCallback(<K extends keyof ImportOptions>(
    key: K,
    value: ImportOptions[K]
  ) => {
    setOptions(prev => ({ ...prev, [key]: value }));
  }, []);

  // Handle import
  const handleImport = useCallback(() => {
    onImport(options);
  }, [options, onImport]);

  if (!isOpen) return null;

  return (
    <div className="rf-import-dialog-overlay" onClick={onCancel}>
      <div className="rf-import-dialog" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="rf-import-dialog__header">
          <div className="rf-import-dialog__title">Import Audio Options</div>
          <button className="rf-import-dialog__close" onClick={onCancel}>
            ×
          </button>
        </div>

        {/* Content */}
        <div className="rf-import-dialog__content">
          {/* File summary */}
          <div className="rf-import-dialog__summary">
            <div className="rf-import-dialog__summary-icon">🎵</div>
            <div className="rf-import-dialog__summary-info">
              <div className="rf-import-dialog__summary-name">
                {summary.count === 1 ? files[0].name : `${summary.count} files selected`}
              </div>
              <div className="rf-import-dialog__summary-meta">
                {formatFileSize(summary.totalSize)} • {formatDuration(summary.totalDuration)}
                {summary.count === 1 && (
                  <> • {formatSampleRate(files[0].sampleRate)} • {files[0].channels === 1 ? 'Mono' : 'Stereo'}</>
                )}
              </div>
            </div>
          </div>

          {/* Import mode */}
          <div className="rf-import-dialog__section">
            <div className="rf-import-dialog__section-title">Import Mode</div>

            <div
              className={`rf-import-dialog__option ${options.mode === 'copy' ? 'selected' : ''}`}
              onClick={() => updateOption('mode', 'copy')}
            >
              <div className="rf-import-dialog__option-radio" />
              <div className="rf-import-dialog__option-content">
                <div className="rf-import-dialog__option-label">Copy to Project (Recommended)</div>
                <div className="rf-import-dialog__option-desc">
                  Files are copied into the project folder. Project remains self-contained and portable.
                </div>
              </div>
            </div>

            <div
              className={`rf-import-dialog__option ${options.mode === 'reference' ? 'selected' : ''}`}
              onClick={() => updateOption('mode', 'reference')}
            >
              <div className="rf-import-dialog__option-radio" />
              <div className="rf-import-dialog__option-content">
                <div className="rf-import-dialog__option-label">Reference Original</div>
                <div className="rf-import-dialog__option-desc">
                  Keep files in their original location. Smaller project size but files must remain accessible.
                </div>
              </div>
            </div>
          </div>

          {/* Sample rate conversion */}
          {summary.needsSRConversion && (
            <div className="rf-import-dialog__section">
              <div className="rf-import-dialog__section-title">Sample Rate</div>

              <div className="rf-import-dialog__select-group">
                <span className="rf-import-dialog__select-label">Conversion</span>
                <select
                  className="rf-import-dialog__select"
                  value={options.sampleRate}
                  onChange={e => updateOption('sampleRate', e.target.value as SampleRateMode)}
                >
                  <option value="keep">Keep Original</option>
                  <option value="convert">Convert to Project Rate</option>
                </select>
              </div>

              {options.sampleRate === 'convert' && (
                <div className="rf-import-dialog__select-group">
                  <span className="rf-import-dialog__select-label">Target Rate</span>
                  <select
                    className="rf-import-dialog__select"
                    value={options.targetSampleRate}
                    onChange={e => updateOption('targetSampleRate', parseInt(e.target.value))}
                  >
                    <option value={44100}>44.1 kHz</option>
                    <option value={48000}>48 kHz</option>
                    <option value={88200}>88.2 kHz</option>
                    <option value={96000}>96 kHz</option>
                  </select>
                </div>
              )}
            </div>
          )}

          {/* Channel conversion */}
          <div className="rf-import-dialog__section">
            <div className="rf-import-dialog__section-title">Channels</div>

            <div className="rf-import-dialog__select-group">
              <span className="rf-import-dialog__select-label">Channel Mode</span>
              <select
                className="rf-import-dialog__select"
                value={options.channelMode}
                onChange={e => updateOption('channelMode', e.target.value as ChannelMode)}
              >
                <option value="keep">Keep Original</option>
                <option value="mono">Convert to Mono</option>
                <option value="stereo">Convert to Stereo</option>
              </select>
            </div>
          </div>

          {/* Track Creation (Cubase-style) */}
          <div className="rf-import-dialog__section">
            <div className="rf-import-dialog__section-title">Track Creation</div>

            <div className="rf-import-dialog__select-group">
              <span className="rf-import-dialog__select-label">Create Tracks</span>
              <select
                className="rf-import-dialog__select"
                value={options.trackCreation}
                onChange={e => updateOption('trackCreation', e.target.value as TrackCreationMode)}
              >
                <option value="none">Pool Only (No Tracks)</option>
                <option value="one-track">One Track (Sequential)</option>
                <option value="separate-tracks">Separate Tracks (Recommended)</option>
                <option value="stacked">Stacked on Same Track</option>
              </select>
            </div>

            <div className="rf-import-dialog__option-hint">
              {options.trackCreation === 'none' && 'Files added to Pool only. Drag to timeline manually.'}
              {options.trackCreation === 'one-track' && 'All files on one track, placed sequentially.'}
              {options.trackCreation === 'separate-tracks' && 'Each file gets its own track at cursor position.'}
              {options.trackCreation === 'stacked' && 'All files stacked at cursor (for layering/comping).'}
            </div>

            <div
              className={`rf-import-dialog__checkbox ${options.snapToGrid ? 'checked' : ''}`}
              onClick={() => updateOption('snapToGrid', !options.snapToGrid)}
              style={{ marginTop: 8 }}
            >
              <div className="rf-import-dialog__checkbox-box" />
              <span className="rf-import-dialog__checkbox-label">
                Snap to grid on placement
              </span>
            </div>
          </div>

          {/* Additional options */}
          <div className="rf-import-dialog__section">
            <div className="rf-import-dialog__section-title">Processing</div>

            <div
              className={`rf-import-dialog__checkbox ${options.normalize ? 'checked' : ''}`}
              onClick={() => updateOption('normalize', !options.normalize)}
            >
              <div className="rf-import-dialog__checkbox-box" />
              <span className="rf-import-dialog__checkbox-label">
                Normalize audio (peak normalize to -1 dB)
              </span>
            </div>
          </div>

          {/* File list for multi-file imports */}
          {summary.count > 1 && (
            <div className="rf-import-dialog__section">
              <div className="rf-import-dialog__section-title">Files ({summary.count})</div>
              <div className="rf-import-dialog__file-list">
                {files.slice(0, 10).map((file, idx) => (
                  <div key={idx} className="rf-import-dialog__file-item">
                    <span className="rf-import-dialog__file-name">{file.name}</span>
                    <span className="rf-import-dialog__file-meta">
                      {formatDuration(file.duration)} • {formatSampleRate(file.sampleRate)}
                      {file.sampleRate !== projectSampleRate && (
                        <span className="rf-import-dialog__file-warning"> ⚠️</span>
                      )}
                    </span>
                  </div>
                ))}
                {files.length > 10 && (
                  <div className="rf-import-dialog__file-more">
                    ...and {files.length - 10} more files
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Warning for reference mode */}
          {options.mode === 'reference' && (
            <div className="rf-import-dialog__warning">
              <span className="rf-import-dialog__warning-icon">⚠️</span>
              <span className="rf-import-dialog__warning-text">
                Referenced files must remain in their original location. Moving or deleting them will break the project.
                Use "Consolidate" later to copy all referenced files into the project.
              </span>
            </div>
          )}
        </div>

        {/* Remember choice */}
        <div className="rf-import-dialog__remember">
          <input
            type="checkbox"
            id="remember-choice"
            className="rf-import-dialog__remember-checkbox"
            checked={options.rememberChoice}
            onChange={e => updateOption('rememberChoice', e.target.checked)}
          />
          <label htmlFor="remember-choice" className="rf-import-dialog__remember-label">
            Remember my choice and don't ask again
          </label>
        </div>

        {/* Footer */}
        <div className="rf-import-dialog__footer">
          <button className="rf-import-dialog__btn rf-import-dialog__btn--cancel" onClick={onCancel}>
            Cancel
          </button>
          <button className="rf-import-dialog__btn rf-import-dialog__btn--import" onClick={handleImport}>
            Import {summary.count > 1 ? `${summary.count} Files` : ''}
          </button>
        </div>
      </div>
    </div>
  );
}

export default ImportOptionsDialog;
