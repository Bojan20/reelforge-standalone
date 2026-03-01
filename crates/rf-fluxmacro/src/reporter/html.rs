// ============================================================================
// rf-fluxmacro — HTML Reporter
// ============================================================================
// FM-17: Self-contained HTML report (inline CSS, XSS-safe escaping).
// ============================================================================

use crate::context::{MacroContext, ReportFormat};
use crate::error::FluxMacroError;
use crate::reporter::Reporter;
use crate::security::html_escape;

/// HTML report generator — produces self-contained HTML with inline CSS.
pub struct HtmlReporter;

impl Reporter for HtmlReporter {
    fn format(&self) -> ReportFormat {
        ReportFormat::Html
    }

    fn generate(&self, ctx: &MacroContext) -> Result<Vec<u8>, FluxMacroError> {
        let mut html = String::with_capacity(8192);

        let status = if ctx.is_success() { "PASS" } else { "FAIL" };
        let status_color = if ctx.is_success() { "#40FF90" } else { "#FF4444" };
        let game_id = html_escape(&ctx.game_id);

        // Document header
        html.push_str("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n");
        html.push_str("<meta charset=\"UTF-8\">\n");
        html.push_str("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
        html.push_str(&format!(
            "<title>FluxMacro Report — {game_id}</title>\n"
        ));
        html.push_str("<style>\n");
        html.push_str(CSS);
        html.push_str("</style>\n");
        html.push_str("</head>\n<body>\n");

        // Header section
        html.push_str("<div class=\"header\">\n");
        html.push_str(&format!(
            "<h1>FluxMacro Report — {game_id}</h1>\n"
        ));
        html.push_str(&format!(
            "<span class=\"status\" style=\"color: {status_color}\">{status}</span>\n"
        ));
        html.push_str(&format!(
            "<div class=\"meta\">Duration: {:.1}s | Seed: {} | Hash: {}</div>\n",
            ctx.duration().as_secs_f64(),
            ctx.seed,
            if ctx.run_hash.len() >= 16 {
                &ctx.run_hash[..16]
            } else {
                &ctx.run_hash
            }
        ));
        html.push_str("</div>\n");

        // QA Results
        if !ctx.qa_results.is_empty() {
            html.push_str("<div class=\"section\">\n");
            html.push_str("<h2>QA Results</h2>\n");
            html.push_str("<table>\n");
            html.push_str("<tr><th>Test</th><th>Status</th><th>Duration</th><th>Details</th></tr>\n");
            for qa in &ctx.qa_results {
                let status_class = if qa.passed { "pass" } else { "fail" };
                let status_text = if qa.passed { "PASS" } else { "FAIL" };
                html.push_str(&format!(
                    "<tr><td>{}</td><td class=\"{status_class}\">{status_text}</td><td>{}ms</td><td>{}</td></tr>\n",
                    html_escape(&qa.test_name),
                    qa.duration_ms,
                    html_escape(&qa.details),
                ));
            }
            html.push_str("</table>\n");
            html.push_str("</div>\n");
        }

        // Artifacts
        if !ctx.artifacts.is_empty() {
            html.push_str("<div class=\"section\">\n");
            html.push_str("<h2>Artifacts</h2>\n");
            html.push_str("<ul>\n");
            let mut sorted: Vec<_> = ctx.artifacts.iter().collect();
            sorted.sort_by_key(|(name, _)| (*name).clone());
            for (name, path) in sorted {
                html.push_str(&format!(
                    "<li><strong>{}</strong>: <code>{}</code></li>\n",
                    html_escape(name),
                    html_escape(&path.display().to_string()),
                ));
            }
            html.push_str("</ul>\n");
            html.push_str("</div>\n");
        }

        // Warnings
        if !ctx.warnings.is_empty() {
            html.push_str("<div class=\"section warnings\">\n");
            html.push_str("<h2>Warnings</h2>\n");
            html.push_str("<ul>\n");
            for w in &ctx.warnings {
                html.push_str(&format!("<li>{}</li>\n", html_escape(w)));
            }
            html.push_str("</ul>\n");
            html.push_str("</div>\n");
        }

        // Errors
        if !ctx.errors.is_empty() {
            html.push_str("<div class=\"section errors\">\n");
            html.push_str("<h2>Errors</h2>\n");
            html.push_str("<ul>\n");
            for e in &ctx.errors {
                html.push_str(&format!("<li>{}</li>\n", html_escape(e)));
            }
            html.push_str("</ul>\n");
            html.push_str("</div>\n");
        }

        // Summary
        html.push_str("<div class=\"section summary\">\n");
        html.push_str("<h2>Summary</h2>\n");
        html.push_str("<table>\n");
        html.push_str(&format!(
            "<tr><td>Total Logs</td><td>{}</td></tr>\n",
            ctx.logs.len()
        ));
        html.push_str(&format!(
            "<tr><td>Warnings</td><td>{}</td></tr>\n",
            ctx.warnings.len()
        ));
        html.push_str(&format!(
            "<tr><td>Errors</td><td>{}</td></tr>\n",
            ctx.errors.len()
        ));
        html.push_str(&format!(
            "<tr><td>QA Passed</td><td>{}</td></tr>\n",
            ctx.qa_passed_count()
        ));
        html.push_str(&format!(
            "<tr><td>QA Failed</td><td>{}</td></tr>\n",
            ctx.qa_failed_count()
        ));
        html.push_str(&format!(
            "<tr><td>Artifacts</td><td>{}</td></tr>\n",
            ctx.artifacts.len()
        ));
        html.push_str("</table>\n");
        html.push_str("</div>\n");

        // Log stream (collapsible)
        if !ctx.logs.is_empty() {
            html.push_str("<div class=\"section\">\n");
            html.push_str("<details>\n");
            html.push_str("<summary><h2 style=\"display:inline\">Execution Log</h2></summary>\n");
            html.push_str("<pre class=\"log\">\n");
            for entry in &ctx.logs {
                let level_class = match entry.level {
                    crate::context::LogLevel::Debug => "log-debug",
                    crate::context::LogLevel::Info => "log-info",
                    crate::context::LogLevel::Warning => "log-warn",
                    crate::context::LogLevel::Error => "log-error",
                };
                let level = match entry.level {
                    crate::context::LogLevel::Debug => "DEBUG",
                    crate::context::LogLevel::Info => "INFO ",
                    crate::context::LogLevel::Warning => "WARN ",
                    crate::context::LogLevel::Error => "ERROR",
                };
                html.push_str(&format!(
                    "<span class=\"{level_class}\">[{:>8}ms] [{level}] [{}] {}</span>\n",
                    entry.elapsed.as_millis(),
                    html_escape(&entry.step),
                    html_escape(&entry.message),
                ));
            }
            html.push_str("</pre>\n");
            html.push_str("</details>\n");
            html.push_str("</div>\n");
        }

        // Footer
        html.push_str("<div class=\"footer\">\n");
        html.push_str("Generated by <strong>FluxMacro Engine</strong> — FluxForge Studio\n");
        html.push_str("</div>\n");
        html.push_str("</body>\n</html>\n");

        Ok(html.into_bytes())
    }

    fn file_extension(&self) -> &'static str {
        "html"
    }
}

const CSS: &str = r#"
:root { --bg: #1a1a2e; --fg: #e0e0e0; --accent: #4A9EFF; --pass: #40FF90; --fail: #FF4444; --warn: #FFD700; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--fg); padding: 2rem; max-width: 1200px; margin: 0 auto; }
h1 { color: var(--accent); font-size: 1.5rem; }
h2 { color: var(--fg); font-size: 1.1rem; margin-bottom: 0.5rem; }
.header { border-bottom: 2px solid var(--accent); padding-bottom: 1rem; margin-bottom: 1.5rem; }
.status { font-size: 2rem; font-weight: bold; }
.meta { color: #888; font-size: 0.85rem; margin-top: 0.5rem; }
.section { margin-bottom: 1.5rem; padding: 1rem; background: rgba(255,255,255,0.03); border-radius: 8px; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 0.5rem; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
th { color: var(--accent); font-weight: 500; }
.pass { color: var(--pass); font-weight: bold; }
.fail { color: var(--fail); font-weight: bold; }
.warnings h2 { color: var(--warn); }
.errors h2 { color: var(--fail); }
ul { list-style: none; padding-left: 1rem; }
li { padding: 0.2rem 0; }
li:before { content: "→ "; color: var(--accent); }
code { background: rgba(255,255,255,0.1); padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.85rem; }
.log { font-family: 'JetBrains Mono', 'Fira Code', monospace; font-size: 0.8rem; line-height: 1.5; background: rgba(0,0,0,0.3); padding: 1rem; border-radius: 4px; overflow-x: auto; max-height: 500px; overflow-y: auto; }
.log-debug { color: #666; }
.log-info { color: #8cb4ff; }
.log-warn { color: var(--warn); }
.log-error { color: var(--fail); }
details summary { cursor: pointer; user-select: none; }
details summary:hover { color: var(--accent); }
.footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); color: #666; font-size: 0.8rem; text-align: center; }
"#;
