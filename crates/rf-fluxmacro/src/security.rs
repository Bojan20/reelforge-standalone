// ============================================================================
// rf-fluxmacro — Security Module
// ============================================================================
// FM-8: Path sandboxing, input sanitization, HTML content escaping.
// Prevents path traversal, injection, and XSS in generated reports.
// ============================================================================

use std::path::{Path, PathBuf};

use regex::Regex;
use std::sync::LazyLock;

use crate::error::FluxMacroError;

// ─── Game ID Validation ──────────────────────────────────────────────────────

static GAME_ID_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-zA-Z0-9_-]{1,64}$").unwrap());

/// Validate that a game ID matches the allowed pattern: [a-zA-Z0-9_-]{1,64}.
pub fn validate_game_id(game_id: &str) -> Result<(), FluxMacroError> {
    if GAME_ID_REGEX.is_match(game_id) {
        Ok(())
    } else {
        Err(FluxMacroError::InvalidGameId(game_id.to_string()))
    }
}

// ─── Path Sandboxing ─────────────────────────────────────────────────────────

/// Ensure a path is contained within a sandbox directory.
/// Canonicalizes both paths and checks containment.
/// Returns the canonicalized path on success.
pub fn sandbox_path(path: &Path, sandbox: &Path) -> Result<PathBuf, FluxMacroError> {
    // Canonicalize sandbox (must exist)
    let canonical_sandbox = sandbox
        .canonicalize()
        .map_err(|_| FluxMacroError::PathTraversal {
            path: path.to_path_buf(),
            sandbox: sandbox.to_path_buf(),
        })?;

    // For paths that don't exist yet, resolve what we can
    let canonical_path = if path.exists() {
        path.canonicalize()
            .map_err(|_| FluxMacroError::PathTraversal {
                path: path.to_path_buf(),
                sandbox: sandbox.to_path_buf(),
            })?
    } else {
        // Resolve parent + append filename
        resolve_nonexistent_path(path, &canonical_sandbox)?
    };

    // Check containment
    if canonical_path.starts_with(&canonical_sandbox) {
        Ok(canonical_path)
    } else {
        Err(FluxMacroError::PathTraversal {
            path: path.to_path_buf(),
            sandbox: sandbox.to_path_buf(),
        })
    }
}

/// Resolve a path that may not exist yet by canonicalizing the deepest existing ancestor.
fn resolve_nonexistent_path(path: &Path, sandbox: &Path) -> Result<PathBuf, FluxMacroError> {
    let mut components: Vec<&std::ffi::OsStr> = Vec::new();
    let mut current = path;

    // Walk up until we find an existing directory
    loop {
        if current.exists() {
            let base = current
                .canonicalize()
                .map_err(|_| FluxMacroError::PathTraversal {
                    path: path.to_path_buf(),
                    sandbox: sandbox.to_path_buf(),
                })?;
            // Re-append the non-existent components
            let mut result = base;
            for component in components.into_iter().rev() {
                result = result.join(component);
            }
            return Ok(result);
        }

        match current.file_name() {
            Some(name) => {
                components.push(name);
                current = current
                    .parent()
                    .ok_or_else(|| FluxMacroError::PathTraversal {
                        path: path.to_path_buf(),
                        sandbox: sandbox.to_path_buf(),
                    })?;
            }
            None => {
                return Err(FluxMacroError::PathTraversal {
                    path: path.to_path_buf(),
                    sandbox: sandbox.to_path_buf(),
                });
            }
        }
    }
}

// ─── Input Sanitization ──────────────────────────────────────────────────────

static SAFE_FILENAME_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-zA-Z0-9._-]{1,255}$").unwrap());

/// Validate a filename is safe for filesystem use.
pub fn validate_filename(name: &str) -> Result<(), FluxMacroError> {
    if SAFE_FILENAME_REGEX.is_match(name) {
        Ok(())
    } else {
        Err(FluxMacroError::InvalidInput(format!(
            "unsafe filename: '{name}'"
        )))
    }
}

/// Sanitize a string for use as a filename.
/// Replaces unsafe characters with underscores, truncates to 255 chars.
pub fn sanitize_filename(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();

    if sanitized.len() > 255 {
        sanitized[..255].to_string()
    } else if sanitized.is_empty() {
        "unnamed".to_string()
    } else {
        sanitized
    }
}

// ─── HTML Escaping ───────────────────────────────────────────────────────────

/// Escape a string for safe inclusion in HTML content.
/// Prevents XSS in generated HTML reports.
pub fn html_escape(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => result.push_str("&amp;"),
            '<' => result.push_str("&lt;"),
            '>' => result.push_str("&gt;"),
            '"' => result.push_str("&quot;"),
            '\'' => result.push_str("&#x27;"),
            '/' => result.push_str("&#x2F;"),
            _ => result.push(c),
        }
    }
    result
}

/// Escape a string for safe inclusion in an HTML attribute value (double-quoted).
pub fn html_attr_escape(s: &str) -> String {
    // Same as html_escape — covers all attribute injection vectors
    html_escape(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_game_ids() {
        assert!(validate_game_id("GoldenPantheon").is_ok());
        assert!(validate_game_id("fortune-fury").is_ok());
        assert!(validate_game_id("game_v2").is_ok());
        assert!(validate_game_id("a").is_ok());
        assert!(validate_game_id("A123-B_c").is_ok());
    }

    #[test]
    fn invalid_game_ids() {
        assert!(validate_game_id("").is_err());
        assert!(validate_game_id("has space").is_err());
        assert!(validate_game_id("has.dot").is_err());
        assert!(validate_game_id("a".repeat(65).as_str()).is_err());
        assert!(validate_game_id("../traversal").is_err());
        assert!(validate_game_id("<script>").is_err());
    }

    #[test]
    fn html_escape_xss() {
        assert_eq!(
            html_escape("<script>alert('xss')</script>"),
            "&lt;script&gt;alert(&#x27;xss&#x27;)&lt;&#x2F;script&gt;"
        );
    }

    #[test]
    fn html_escape_normal_text() {
        assert_eq!(html_escape("Hello World"), "Hello World");
        assert_eq!(html_escape("Game: GoldenPantheon"), "Game: GoldenPantheon");
    }

    #[test]
    fn html_escape_entities() {
        assert_eq!(html_escape("A & B"), "A &amp; B");
        assert_eq!(html_escape("1 < 2 > 0"), "1 &lt; 2 &gt; 0");
    }

    #[test]
    fn sanitize_filename_basic() {
        assert_eq!(sanitize_filename("hello.txt"), "hello.txt");
        assert_eq!(sanitize_filename("my file.txt"), "my_file.txt");
        assert_eq!(
            sanitize_filename("../../../etc/passwd"),
            ".._.._.._etc_passwd"
        );
    }

    #[test]
    fn sanitize_filename_empty() {
        assert_eq!(sanitize_filename(""), "unnamed");
    }

    #[test]
    fn validate_filename_valid() {
        assert!(validate_filename("report.html").is_ok());
        assert!(validate_filename("QA_EventStorm_2026.json").is_ok());
    }

    #[test]
    fn validate_filename_invalid() {
        assert!(validate_filename("file name.txt").is_err());
        assert!(validate_filename("../bad").is_err());
        assert!(validate_filename("").is_err());
    }
}
