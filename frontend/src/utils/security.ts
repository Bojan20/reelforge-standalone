/**
 * Security Utilities
 *
 * Functions for sanitizing and escaping user input to prevent XSS and injection attacks.
 *
 * @module utils/security
 */

/**
 * HTML entity map for escaping special characters.
 */
const HTML_ENTITIES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
  '`': '&#96;',
};

/**
 * Escape HTML special characters to prevent XSS.
 *
 * Use this when inserting user-provided content into innerHTML.
 *
 * @param str - The string to escape
 * @returns The escaped string safe for innerHTML
 *
 * @example
 * ```ts
 * // Safe usage:
 * element.innerHTML = `<div>${escapeHtml(userInput)}</div>`;
 *
 * // NEVER do this without escaping:
 * // element.innerHTML = `<div>${userInput}</div>`; // XSS!
 * ```
 */
export function escapeHtml(str: string): string {
  if (typeof str !== 'string') return '';
  return str.replace(/[&<>"'`]/g, (char) => HTML_ENTITIES[char] || char);
}

/**
 * Sanitize a string for use in CSS selectors.
 *
 * Removes or escapes characters that could be used for selector injection.
 *
 * @param str - The string to sanitize
 * @returns A string safe for use in querySelector/querySelectorAll
 */
export function sanitizeSelector(str: string): string {
  if (typeof str !== 'string') return '';
  // Only allow alphanumeric, dash, underscore
  return str.replace(/[^a-zA-Z0-9_-]/g, '');
}

/**
 * Sanitize a string for use as a data attribute value.
 *
 * @param str - The string to sanitize
 * @returns A string safe for use in data-* attributes
 */
export function sanitizeDataAttribute(str: string): string {
  if (typeof str !== 'string') return '';
  // Escape quotes and special HTML chars
  return escapeHtml(str);
}

/**
 * Create safe HTML content using tagged template literals.
 *
 * Automatically escapes interpolated values.
 *
 * @example
 * ```ts
 * const safeHtml = html`<div class="name">${userName}</div>`;
 * element.innerHTML = safeHtml;
 * ```
 */
export function html(
  strings: TemplateStringsArray,
  ...values: unknown[]
): string {
  return strings.reduce((result, str, i) => {
    const value = values[i - 1];
    const escaped = value != null ? escapeHtml(String(value)) : '';
    return result + escaped + str;
  });
}

/**
 * Validate that a value is a safe BusId.
 *
 * Prevents injection through bus IDs.
 */
export function isValidBusId(id: unknown): id is string {
  if (typeof id !== 'string') return false;
  // BusIds should be: sfx, music, voice, ambient, ui, master
  return /^[a-z_][a-z0-9_]*$/i.test(id) && id.length <= 32;
}

/**
 * Validate URL for safe usage.
 *
 * Prevents javascript: and data: URL injection.
 */
export function isSafeUrl(url: string): boolean {
  if (typeof url !== 'string') return false;
  const lower = url.toLowerCase().trim();
  // Block dangerous protocols
  if (lower.startsWith('javascript:')) return false;
  if (lower.startsWith('data:') && !lower.startsWith('data:audio/')) return false;
  if (lower.startsWith('vbscript:')) return false;
  return true;
}
