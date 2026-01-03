/**
 * ReelForge M8.6 Diagnostics HUD
 *
 * Floating panel that displays real-time latency, PDC state, ducking,
 * and voice health diagnostics. Read-only observability layer.
 *
 * Sections:
 * 1. Latency Stack - Asset → Bus → Master
 * 2. PDC State - enabled/clamped per bus + master
 * 3. Ducking Panel - policy, current state, gains
 * 4. Voice Health - counts, warnings, limits
 * 5. Warnings Summary - aggregated issues
 */

import { useState, useCallback } from 'react';
import {
  useDiagnosticsSnapshot,
  formatLatency,
  INSERTABLE_BUS_IDS,
  type DiagnosticsSnapshot,
  type BusLatencySnapshot,
} from '../core/useDiagnosticsSnapshot';
import {
  copySnapshotToClipboard,
  downloadSnapshot,
  copyTextSummaryToClipboard,
  type ExportContext,
} from '../core/diagnosticsExport';
import './DiagnosticsHUD.css';

interface DiagnosticsHUDProps {
  /** Whether HUD is visible */
  visible: boolean;
  /** Toggle visibility callback */
  onToggle: () => void;
  /** Optional export context for metadata */
  exportContext?: ExportContext;
}

export default function DiagnosticsHUD({ visible, onToggle, exportContext }: DiagnosticsHUDProps) {
  const snapshot = useDiagnosticsSnapshot();

  const [collapsedSections, setCollapsedSections] = useState<Set<string>>(new Set());
  const [feedbackMessage, setFeedbackMessage] = useState<string | null>(null);

  const toggleSection = useCallback((section: string) => {
    setCollapsedSections((prev) => {
      const next = new Set(prev);
      if (next.has(section)) {
        next.delete(section);
      } else {
        next.add(section);
      }
      return next;
    });
  }, []);

  const showFeedback = useCallback((message: string) => {
    setFeedbackMessage(message);
    setTimeout(() => setFeedbackMessage(null), 2000);
  }, []);

  const handleCopyJson = useCallback(async () => {
    const result = await copySnapshotToClipboard(snapshot, exportContext);
    if (result.success) {
      showFeedback('Copied!');
    } else {
      showFeedback(`Error: ${result.error}`);
    }
  }, [snapshot, exportContext, showFeedback]);

  const handleDownload = useCallback(() => {
    const result = downloadSnapshot(snapshot, exportContext);
    if (result.success) {
      showFeedback('Saved!');
    } else {
      showFeedback(`Error: ${result.error}`);
    }
  }, [snapshot, exportContext, showFeedback]);

  const handleCopyText = useCallback(async () => {
    const result = await copyTextSummaryToClipboard(snapshot, exportContext);
    if (result.success) {
      showFeedback('Copied!');
    } else {
      showFeedback(`Error: ${result.error}`);
    }
  }, [snapshot, exportContext, showFeedback]);

  if (!visible) {
    return (
      <button className="rf-hud-toggle-btn" onClick={onToggle} title="Show Diagnostics HUD">
        📊
      </button>
    );
  }

  return (
    <div className="rf-diagnostics-hud">
      <div className="rf-hud-header">
        <span className="rf-hud-title">Diagnostics</span>
        <div className="rf-hud-toolbar">
          <button
            className="rf-hud-tool-btn"
            onClick={handleCopyJson}
            title="Copy JSON to clipboard"
          >
            {'{}'}
          </button>
          <button
            className="rf-hud-tool-btn"
            onClick={handleDownload}
            title="Download snapshot file"
          >
            DL
          </button>
          <button
            className="rf-hud-tool-btn"
            onClick={handleCopyText}
            title="Copy text summary"
          >
            TXT
          </button>
        </div>
        <button className="rf-hud-close-btn" onClick={onToggle} title="Hide HUD">
          X
        </button>
      </div>
      {feedbackMessage && (
        <div className="rf-hud-feedback">{feedbackMessage}</div>
      )}

      <div className="rf-hud-content">
        {/* Warnings Summary (always visible at top if any) */}
        {snapshot.warnings.length > 0 && (
          <WarningsSummary warnings={snapshot.warnings} />
        )}

        {/* Latency Stack */}
        <HUDSection
          title="LATENCY"
          collapsed={collapsedSections.has('latency')}
          onToggle={() => toggleSection('latency')}
        >
          <LatencyPanel snapshot={snapshot} />
        </HUDSection>

        {/* PDC State */}
        <HUDSection
          title="PDC"
          collapsed={collapsedSections.has('pdc')}
          onToggle={() => toggleSection('pdc')}
        >
          <PDCPanel snapshot={snapshot} />
        </HUDSection>

        {/* Ducking */}
        <HUDSection
          title="DUCKING"
          collapsed={collapsedSections.has('ducking')}
          onToggle={() => toggleSection('ducking')}
        >
          <DuckingPanel snapshot={snapshot} />
        </HUDSection>

        {/* Voice Health */}
        <HUDSection
          title="VOICES"
          collapsed={collapsedSections.has('voices')}
          onToggle={() => toggleSection('voices')}
        >
          <VoiceHealthPanel snapshot={snapshot} />
        </HUDSection>
      </div>
    </div>
  );
}

// ============ Section Wrapper ============

interface HUDSectionProps {
  title: string;
  collapsed: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}

function HUDSection({ title, collapsed, onToggle, children }: HUDSectionProps) {
  return (
    <div className="rf-hud-section">
      <div className="rf-hud-section-header" onClick={onToggle}>
        <span className="rf-hud-section-title">{title}</span>
        <span className={`rf-hud-section-chevron ${collapsed ? 'collapsed' : ''}`}>▼</span>
      </div>
      {!collapsed && <div className="rf-hud-section-content">{children}</div>}
    </div>
  );
}

// ============ Warnings Summary ============

interface WarningsSummaryProps {
  warnings: DiagnosticsSnapshot['warnings'];
}

function WarningsSummary({ warnings }: WarningsSummaryProps) {
  return (
    <div className="rf-hud-warnings">
      <div className="rf-hud-warnings-header">
        ⚠ WARNINGS ({warnings.length})
      </div>
      <div className="rf-hud-warnings-list">
        {warnings.map((warning) => (
          <div
            key={warning.id}
            className={`rf-hud-warning-item ${warning.severity === 'error' ? 'error' : ''}`}
          >
            - {warning.message}
          </div>
        ))}
      </div>
    </div>
  );
}

// ============ Latency Panel ============

interface LatencyPanelProps {
  snapshot: DiagnosticsSnapshot;
}

function LatencyPanel({ snapshot }: LatencyPanelProps) {
  // Find the maximum total latency for display
  const maxTotalLatency = Math.max(
    ...Object.values(snapshot.totalLatencyByBus),
    0
  );

  return (
    <div className="rf-hud-latency">
      {/* Asset row */}
      <div className="rf-hud-latency-row">
        <span className="rf-hud-latency-label">ASSET (avg):</span>
        <span className="rf-hud-latency-value">{formatLatency(snapshot.assetLatencyMs)}</span>
        <span className="rf-hud-latency-badges"></span>
      </div>

      {/* Bus rows */}
      {snapshot.busLatencies.map((bus) => (
        <LatencyRow key={bus.busId} bus={bus} />
      ))}

      {/* Master row */}
      <div className="rf-hud-latency-row">
        <span className="rf-hud-latency-label">MASTER:</span>
        <span className="rf-hud-latency-value">{formatLatency(snapshot.masterLatencyMs)}</span>
        <span className="rf-hud-latency-badges">
          <PDCBadge enabled={snapshot.masterPdcEnabled} clamped={snapshot.masterPdcClamped} />
        </span>
      </div>

      {/* Separator */}
      <div className="rf-hud-latency-separator">─────────────────────────</div>

      {/* Total row */}
      <div className="rf-hud-latency-row rf-hud-latency-total">
        <span className="rf-hud-latency-label">TOTAL (max):</span>
        <span className="rf-hud-latency-value">{formatLatency(maxTotalLatency)}</span>
        <span className="rf-hud-latency-badges"></span>
      </div>
    </div>
  );
}

interface LatencyRowProps {
  bus: BusLatencySnapshot;
}

function LatencyRow({ bus }: LatencyRowProps) {
  const label = `BUS ${bus.busId}:`;
  return (
    <div className="rf-hud-latency-row">
      <span className="rf-hud-latency-label">{label}</span>
      <span className="rf-hud-latency-value">{formatLatency(bus.latencyMs)}</span>
      <span className="rf-hud-latency-badges">
        <PDCBadge enabled={bus.pdcEnabled} clamped={bus.pdcClamped} />
      </span>
    </div>
  );
}

interface PDCBadgeProps {
  enabled: boolean;
  clamped: boolean;
}

function PDCBadge({ enabled, clamped }: PDCBadgeProps) {
  if (!enabled) {
    return null;
  }
  const className = clamped ? 'rf-hud-badge rf-hud-badge-error' : 'rf-hud-badge rf-hud-badge-ok';
  const text = clamped ? 'PDC!' : 'PDC';
  return <span className={className}>{text}</span>;
}

// ============ PDC Panel ============

interface PDCPanelProps {
  snapshot: DiagnosticsSnapshot;
}

function PDCPanel({ snapshot }: PDCPanelProps) {
  return (
    <div className="rf-hud-pdc">
      <div className="rf-hud-pdc-header">
        <span className="rf-hud-pdc-col">BUS</span>
        <span className="rf-hud-pdc-col">STATE</span>
        <span className="rf-hud-pdc-col">DELAY</span>
        <span className="rf-hud-pdc-col">STATUS</span>
      </div>

      {snapshot.busLatencies.map((bus) => (
        <PDCRow key={bus.busId} bus={bus} />
      ))}

      {/* Master row */}
      <div className={`rf-hud-pdc-row ${snapshot.masterPdcClamped && snapshot.masterPdcEnabled ? 'clamped' : ''}`}>
        <span className="rf-hud-pdc-col">master</span>
        <span className={`rf-hud-pdc-col ${snapshot.masterPdcEnabled ? 'on' : 'off'}`}>
          {snapshot.masterPdcEnabled ? 'ON' : 'OFF'}
        </span>
        <span className="rf-hud-pdc-col">
          {snapshot.masterPdcDelayMs.toFixed(1)} / {snapshot.masterPdcMaxMs}
        </span>
        <span className={`rf-hud-pdc-col ${snapshot.masterPdcClamped && snapshot.masterPdcEnabled ? 'error' : ''}`}>
          {snapshot.masterPdcEnabled && snapshot.masterPdcClamped ? 'CLAMPED!' : ''}
        </span>
      </div>
    </div>
  );
}

interface PDCRowProps {
  bus: BusLatencySnapshot;
}

function PDCRow({ bus }: PDCRowProps) {
  const isClamped = bus.pdcEnabled && bus.pdcClamped;
  return (
    <div className={`rf-hud-pdc-row ${isClamped ? 'clamped' : ''}`}>
      <span className="rf-hud-pdc-col">{bus.busId}</span>
      <span className={`rf-hud-pdc-col ${bus.pdcEnabled ? 'on' : 'off'}`}>
        {bus.pdcEnabled ? 'ON' : 'OFF'}
      </span>
      <span className="rf-hud-pdc-col">
        {bus.pdcDelayMs.toFixed(1)} / {bus.pdcMaxMs}
      </span>
      <span className={`rf-hud-pdc-col ${isClamped ? 'error' : ''}`}>
        {isClamped ? 'CLAMPED!' : ''}
      </span>
    </div>
  );
}

// ============ Ducking Panel ============

interface DuckingPanelProps {
  snapshot: DiagnosticsSnapshot;
}

function DuckingPanel({ snapshot }: DuckingPanelProps) {
  const { ducking } = snapshot;

  return (
    <div className="rf-hud-ducking">
      <div className="rf-hud-ducking-row">
        <span className="rf-hud-ducking-label">Policy:</span>
        <span className="rf-hud-ducking-value">
          {ducking.duckerBus} → {ducking.duckedBus} ({ducking.duckRatio})
        </span>
      </div>

      <div className="rf-hud-ducking-row">
        <span className="rf-hud-ducking-label">Active:</span>
        <span className={`rf-hud-ducking-value ${ducking.isDucking ? 'active' : ''}`}>
          {ducking.isDucking ? 'YES' : 'NO'}
        </span>
      </div>

      <div className="rf-hud-ducking-row">
        <span className="rf-hud-ducking-label">Duck Gain:</span>
        <span className="rf-hud-ducking-value">
          {ducking.currentDuckGain.toFixed(2)}
        </span>
      </div>

      <div className="rf-hud-ducking-row">
        <span className="rf-hud-ducking-label">Ducker Voices:</span>
        <span className="rf-hud-ducking-value">
          {ducking.duckerVoiceCount}
        </span>
      </div>
    </div>
  );
}

// ============ Voice Health Panel ============

interface VoiceHealthPanelProps {
  snapshot: DiagnosticsSnapshot;
}

function VoiceHealthPanel({ snapshot }: VoiceHealthPanelProps) {
  const { voiceHealth } = snapshot;

  return (
    <div className="rf-hud-voices">
      <div className="rf-hud-voices-row">
        <span className="rf-hud-voices-label">total:</span>
        <span className="rf-hud-voices-value">{voiceHealth.totalVoices}</span>
      </div>

      {INSERTABLE_BUS_IDS.map((busId) => (
        <div key={busId} className="rf-hud-voices-row">
          <span className="rf-hud-voices-label">{busId}:</span>
          <span className="rf-hud-voices-value">{voiceHealth.voicesByBus[busId] ?? 0}</span>
        </div>
      ))}

      <div className={`rf-hud-voices-row ${voiceHealth.chainThresholdExceeded ? 'warning' : ''}`}>
        <span className="rf-hud-voices-label">asset chains:</span>
        <span className="rf-hud-voices-value">
          {voiceHealth.activeAssetChains}
          {voiceHealth.chainThresholdExceeded && ' ⚠'}
        </span>
      </div>
    </div>
  );
}
