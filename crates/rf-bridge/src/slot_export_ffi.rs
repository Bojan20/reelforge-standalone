//! UCP Export™ FFI — Bridges rf-slot-export to Flutter.

use std::ffi::{c_char, CStr, CString};

use rf_slot_export::{FluxForgeExportProject, ExportBundle};

fn json_to_c(json: String) -> *mut c_char {
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// List available export formats. Output: JSON array of {"name": "...", "version": "..."}.
#[unsafe(no_mangle)]
pub extern "C" fn slot_export_formats_json() -> *mut c_char {
    let formats = rf_slot_export::available_formats();
    let arr: Vec<serde_json::Value> = formats.iter().map(|(name, ver)| {
        serde_json::json!({"name": name, "version": ver})
    }).collect();
    json_to_c(serde_json::to_string(&arr).unwrap_or_else(|_| "[]".to_string()))
}

/// Export to ALL formats. Input: FluxForgeExportProject JSON.
/// Output: JSON array of {"format": "...", "success": bool, "files": [...], "error": "..."}.
#[unsafe(no_mangle)]
pub extern "C" fn slot_export_all_json(project_json: *const c_char) -> *mut c_char {
    if project_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(project_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let project: FluxForgeExportProject = match serde_json::from_str(s) {
        Ok(p) => p,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let results = rf_slot_export::export_all(&project);
    let arr: Vec<serde_json::Value> = results.iter().map(|(format, result)| {
        match result {
            Ok(bundle) => serde_json::json!({
                "format": format,
                "success": true,
                "event_count": bundle.event_count,
                "file_count": bundle.files.len(),
                "files": bundle.files.iter().map(|f| &f.filename).collect::<Vec<_>>(),
            }),
            Err(e) => serde_json::json!({
                "format": format,
                "success": false,
                "error": format!("{}", e),
            }),
        }
    }).collect();
    json_to_c(serde_json::to_string(&arr).unwrap_or_else(|_| "[]".to_string()))
}

/// Export to a single specific format. Input: JSON {"project": {...}, "format": "howler"|"wwise"|"fmod"|"generic"}
#[unsafe(no_mangle)]
pub extern "C" fn slot_export_single_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return json_to_c(r#"{"error":"null input"}"#.to_string());
    }
    let s = match unsafe { CStr::from_ptr(request_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return json_to_c(r#"{"error":"invalid utf8"}"#.to_string()),
    };
    let v: serde_json::Value = match serde_json::from_str(s) {
        Ok(v) => v,
        Err(e) => return json_to_c(format!(r#"{{"error":"{}"}}"#, e)),
    };
    let project: FluxForgeExportProject = match serde_json::from_value(v["project"].clone()) {
        Ok(p) => p,
        Err(e) => return json_to_c(format!(r#"{{"error":"project: {}"}}"#, e)),
    };
    let format = v["format"].as_str().unwrap_or("generic");

    // Export to all and filter
    let results = rf_slot_export::export_all(&project);
    let target = results.iter().find(|(f, _)| f.to_lowercase().contains(format));
    match target {
        Some((name, Ok(bundle))) => json_to_c(serde_json::json!({
            "format": name,
            "success": true,
            "event_count": bundle.event_count,
            "file_count": bundle.files.len(),
        }).to_string()),
        Some((name, Err(e))) => json_to_c(format!(r#"{{"format":"{}","success":false,"error":"{}"}}"#, name, e)),
        None => json_to_c(format!(r#"{{"error":"unknown format: {}"}}"#, format)),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn slot_export_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}
