// ============================================================================
// rf-fluxmacro — Reporter Module
// ============================================================================
// FM-14: Reporter trait + format registry.
// ============================================================================

pub mod html;
pub mod json;
pub mod markdown;
pub mod svg;

use crate::context::{MacroContext, ReportFormat};
use crate::error::FluxMacroError;

/// Reporter trait — generates output reports from completed macro runs.
pub trait Reporter: Send + Sync {
    /// Output format this reporter produces.
    fn format(&self) -> ReportFormat;

    /// Generate the report as bytes.
    fn generate(&self, ctx: &MacroContext) -> Result<Vec<u8>, FluxMacroError>;

    /// File extension for the generated report.
    fn file_extension(&self) -> &'static str;
}

/// Generate reports for the specified format(s) and write to disk.
pub fn generate_reports(
    ctx: &MacroContext,
    output_dir: &std::path::Path,
    game_id: &str,
) -> Result<Vec<std::path::PathBuf>, FluxMacroError> {
    let reporters: Vec<Box<dyn Reporter>> = match ctx.report_format {
        ReportFormat::Html => vec![Box::new(html::HtmlReporter)],
        ReportFormat::Json => vec![Box::new(json::JsonReporter)],
        ReportFormat::Markdown => vec![Box::new(markdown::MarkdownReporter)],
        ReportFormat::All => vec![
            Box::new(html::HtmlReporter),
            Box::new(json::JsonReporter),
            Box::new(markdown::MarkdownReporter),
        ],
    };

    std::fs::create_dir_all(output_dir)
        .map_err(|e| FluxMacroError::DirectoryCreate(output_dir.to_path_buf(), e))?;

    let mut paths = Vec::new();
    let timestamp = chrono::Local::now().format("%Y%m%d_%H%M%S");

    for reporter in &reporters {
        let filename = format!("{}_{}.{}", game_id, timestamp, reporter.file_extension());
        let path = output_dir.join(filename);
        let content = reporter.generate(ctx)?;
        std::fs::write(&path, &content).map_err(|e| FluxMacroError::FileWrite(path.clone(), e))?;
        paths.push(path);
    }

    Ok(paths)
}
