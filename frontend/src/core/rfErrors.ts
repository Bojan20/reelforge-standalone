/**
 * ReelForge M8.9 Centralized Error Types
 *
 * Human-readable error codes with titles and hints for UI surfacing.
 * Stack traces remain in console (dev only), UI shows clean messages.
 */

/** Error severity levels */
export type RFErrorSeverity = 'warning' | 'error' | 'fatal';

/** RF_ERR error codes */
export type RFErrorCode =
  // Clipboard errors
  | 'RF_ERR_CLIPBOARD_EMPTY'
  | 'RF_ERR_CLIPBOARD_NO_CHAIN'
  | 'RF_ERR_CLIPBOARD_NO_INSERT'
  // Preset errors
  | 'RF_ERR_PRESET_LOAD_FAILED'
  | 'RF_ERR_PRESET_SAVE_FAILED'
  | 'RF_ERR_PRESET_INVALID'
  // Validation errors
  | 'RF_ERR_INVALID_INSERT_PARAM'
  | 'RF_ERR_INVALID_CHAIN'
  | 'RF_ERR_DUPLICATE_INSERT_ID'
  | 'RF_ERR_UNKNOWN_PLUGIN'
  // Storage errors
  | 'RF_ERR_STORAGE_UNAVAILABLE'
  | 'RF_ERR_PROJECT_LOAD_FAILED'
  | 'RF_ERR_PROJECT_SAVE_FAILED'
  // DSP errors
  | 'RF_ERR_DSP_INIT_FAILED'
  | 'RF_ERR_DSP_LEAK_DETECTED'
  | 'RF_ERR_DSP_ANOMALY'
  // Context errors
  | 'RF_ERR_MISSING_CONTEXT'
  // Runtime errors
  | 'RF_ERR_RUNTIME_NOT_ENABLED'
  | 'RF_ERR_CORE_RELOAD_FAILED'
  // Asset errors
  | 'RF_ERR_ASSET_FETCH_FAILED'
  | 'RF_ERR_MANIFEST_LOAD_FAILED';

/** Error definition with human-readable messages */
export interface RFErrorDef {
  code: RFErrorCode;
  title: string;
  body: string;
  hint?: string;
  severity: RFErrorSeverity;
}

/** Error catalog mapping codes to definitions */
export const RF_ERROR_CATALOG: Record<RFErrorCode, Omit<RFErrorDef, 'code'>> = {
  // Clipboard errors
  RF_ERR_CLIPBOARD_EMPTY: {
    title: 'Clipboard Empty',
    body: 'Nothing to paste. Copy an insert chain or preset first.',
    hint: 'Use the Copy button on any insert panel to copy its chain.',
    severity: 'warning',
  },
  RF_ERR_CLIPBOARD_NO_CHAIN: {
    title: 'No Chain in Clipboard',
    body: 'The clipboard does not contain an insert chain.',
    hint: 'Copy a chain from another bus or master inserts.',
    severity: 'warning',
  },
  RF_ERR_CLIPBOARD_NO_INSERT: {
    title: 'No Insert in Clipboard',
    body: 'The clipboard does not contain a single insert.',
    hint: 'Copy an individual insert using the insert menu (⋮).',
    severity: 'warning',
  },

  // Preset errors
  RF_ERR_PRESET_LOAD_FAILED: {
    title: 'Preset Load Failed',
    body: 'Could not load the selected preset.',
    hint: 'The preset may be corrupted. Try a different preset.',
    severity: 'error',
  },
  RF_ERR_PRESET_SAVE_FAILED: {
    title: 'Preset Save Failed',
    body: 'Could not save the preset.',
    hint: 'Check that browser storage is available.',
    severity: 'error',
  },
  RF_ERR_PRESET_INVALID: {
    title: 'Invalid Preset',
    body: 'The chain contains invalid parameters and cannot be saved.',
    hint: 'Reset parameters to valid ranges before saving.',
    severity: 'error',
  },

  // Validation errors
  RF_ERR_INVALID_INSERT_PARAM: {
    title: 'Invalid Insert Parameter',
    body: 'One or more insert parameters are out of valid range.',
    hint: 'Check parameter constraints in the insert editor.',
    severity: 'error',
  },
  RF_ERR_INVALID_CHAIN: {
    title: 'Invalid Insert Chain',
    body: 'The insert chain structure is invalid.',
    hint: 'This may indicate file corruption. Try loading a backup.',
    severity: 'error',
  },
  RF_ERR_DUPLICATE_INSERT_ID: {
    title: 'Duplicate Insert ID',
    body: 'Multiple inserts have the same ID.',
    hint: 'This usually indicates file corruption.',
    severity: 'error',
  },
  RF_ERR_UNKNOWN_PLUGIN: {
    title: 'Unknown Plugin',
    body: 'The insert references an unknown plugin type.',
    hint: 'This project may have been created with a newer version.',
    severity: 'error',
  },

  // Storage errors
  RF_ERR_STORAGE_UNAVAILABLE: {
    title: 'Storage Unavailable',
    body: 'Browser storage is not available.',
    hint: 'Check browser settings or try a different browser.',
    severity: 'fatal',
  },
  RF_ERR_PROJECT_LOAD_FAILED: {
    title: 'Project Load Failed',
    body: 'Could not load the project file.',
    hint: 'The file may be corrupted or from an incompatible version.',
    severity: 'fatal',
  },
  RF_ERR_PROJECT_SAVE_FAILED: {
    title: 'Project Save Failed',
    body: 'Could not save the project.',
    hint: 'Check disk space and file permissions.',
    severity: 'error',
  },

  // DSP errors
  RF_ERR_DSP_INIT_FAILED: {
    title: 'Audio Init Failed',
    body: 'Could not initialize audio processing.',
    hint: 'Check that your browser supports Web Audio.',
    severity: 'fatal',
  },
  RF_ERR_DSP_LEAK_DETECTED: {
    title: 'Audio Resource Leak',
    body: 'Some audio resources were not properly disposed.',
    hint: 'This is a bug. Please report it.',
    severity: 'warning',
  },
  RF_ERR_DSP_ANOMALY: {
    title: 'Audio Anomaly Detected',
    body: 'Unexpected audio processing state detected.',
    hint: 'Check console for details. This may affect audio quality.',
    severity: 'warning',
  },

  // Context errors
  RF_ERR_MISSING_CONTEXT: {
    title: 'Missing Context',
    body: 'A required context provider is missing.',
    hint: 'This is a bug. Please report it.',
    severity: 'fatal',
  },

  // Runtime errors
  RF_ERR_RUNTIME_NOT_ENABLED: {
    title: 'Runtime Not Enabled',
    body: 'Native runtime is not available.',
    hint: 'This feature requires native runtime support.',
    severity: 'error',
  },
  RF_ERR_CORE_RELOAD_FAILED: {
    title: 'Core Reload Failed',
    body: 'Could not reload the core runtime.',
    hint: 'Try refreshing the page.',
    severity: 'error',
  },

  // Asset errors
  RF_ERR_ASSET_FETCH_FAILED: {
    title: 'Asset Load Failed',
    body: 'Could not load the requested asset.',
    hint: 'Check your network connection.',
    severity: 'error',
  },
  RF_ERR_MANIFEST_LOAD_FAILED: {
    title: 'Manifest Load Failed',
    body: 'Could not load the asset manifest.',
    hint: 'Check that the manifest file exists and is valid JSON.',
    severity: 'error',
  },
};

/**
 * Get full error definition by code
 */
export function getErrorDef(code: RFErrorCode): RFErrorDef {
  const def = RF_ERROR_CATALOG[code];
  return { code, ...def };
}

/**
 * Create an RF error object for throwing/displaying
 */
export function createRFError(
  code: RFErrorCode,
  details?: string
): RFError {
  const def = getErrorDef(code);
  return new RFError(code, def.title, def.body, def.hint, def.severity, details);
}

/**
 * RFError class - extends Error with structured info
 */
export class RFError extends Error {
  readonly code: RFErrorCode;
  readonly title: string;
  readonly body: string;
  readonly hint?: string;
  readonly severity: RFErrorSeverity;
  readonly details?: string;

  constructor(
    code: RFErrorCode,
    title: string,
    body: string,
    hint?: string,
    severity: RFErrorSeverity = 'error',
    details?: string
  ) {
    super(`${code}: ${title}`);
    this.name = 'RFError';
    this.code = code;
    this.title = title;
    this.body = body;
    this.hint = hint;
    this.severity = severity;
    this.details = details;
  }

  /**
   * Get formatted message for UI display (no stack trace)
   */
  toUIMessage(): string {
    return this.body + (this.hint ? ` ${this.hint}` : '');
  }

  /**
   * Get formatted message for console (with code)
   */
  toConsoleMessage(): string {
    let msg = `[${this.code}] ${this.title}: ${this.body}`;
    if (this.details) msg += ` (${this.details})`;
    if (this.hint) msg += ` Hint: ${this.hint}`;
    return msg;
  }
}

/**
 * Log RF error to console (dev only)
 */
export function logRFError(error: RFError | RFErrorCode, details?: string): void {
  const rfError = typeof error === 'string'
    ? createRFError(error, details)
    : error;

  if (rfError.severity === 'fatal') {
    console.error(rfError.toConsoleMessage(), rfError);
  } else if (rfError.severity === 'error') {
    console.error(rfError.toConsoleMessage());
  } else {
    console.warn(rfError.toConsoleMessage());
  }
}

/**
 * Convert legacy RF_ERR string to code (for migration)
 */
export function legacyToCode(legacyMsg: string): RFErrorCode | null {
  // Handle old format like "RF_ERR: No chain in clipboard"
  if (legacyMsg.includes('No chain in clipboard')) return 'RF_ERR_CLIPBOARD_NO_CHAIN';
  if (legacyMsg.includes('No insert in clipboard')) return 'RF_ERR_CLIPBOARD_NO_INSERT';
  if (legacyMsg.includes('Failed to load preset')) return 'RF_ERR_PRESET_LOAD_FAILED';
  if (legacyMsg.includes('Invalid chain')) return 'RF_ERR_PRESET_INVALID';
  return null;
}
