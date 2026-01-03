/**
 * ReelForge Plugin Window Entry Point
 *
 * Standalone entry for plugin windows opened via window.open().
 * Reads insertId and pluginId from URL params and mounts the appropriate editor.
 *
 * @module plugin-window/plugin-window-entry
 */

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { PluginWindowApp } from './PluginWindowApp';
import '../index.css';

// Parse URL parameters
const params = new URLSearchParams(window.location.search);
const insertId = params.get('insertId');
const pluginId = params.get('pluginId');

// Validate required params
if (!insertId || !pluginId) {
  document.body.innerHTML = `
    <div style="
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      color: #ff6b6b;
      font-family: system-ui, sans-serif;
      background: #1a1a2e;
    ">
      <div style="text-align: center;">
        <h1>Plugin Window Error</h1>
        <p>Missing required parameters: insertId and pluginId</p>
      </div>
    </div>
  `;
} else {
  // Mount the plugin window app
  const container = document.getElementById('plugin-root');
  if (container) {
    const root = createRoot(container);
    root.render(
      <StrictMode>
        <PluginWindowApp insertId={insertId} pluginId={pluginId} />
      </StrictMode>
    );
  }
}
