// Provider Exports
//
// Re-exports all state management providers for easy import.
// Migrated from React hooks to Flutter ChangeNotifier providers.

// Rust Engine
export 'engine_provider.dart';

// Playback & Timeline
export 'timeline_playback_provider.dart';

// Mixer & DSP
export 'mixer_dsp_provider.dart' hide linearToDb, dbToLinear;

// Metering
export 'meter_provider.dart';

// Editor Mode
export 'editor_mode_provider.dart';

// Keyboard Shortcuts
export 'global_shortcuts_provider.dart';

// Pro Tools-Style Keyboard Focus Mode
export 'keyboard_focus_provider.dart';

// Pro Tools-Style Edit Modes (Shuffle/Slip/Spot/Grid)
export 'edit_mode_pro_provider.dart';

// Smart Tool (Context-Aware Tool Selection)
export 'smart_tool_provider.dart';

// Razor Editing (Cubase-style range selection)
export 'razor_edit_provider.dart';

// Direct Offline Processing (non-destructive clip processing)
export 'direct_offline_processing_provider.dart';

// Parameter Modulators (LFO, Envelope Follower, Step, Random)
export 'modulator_provider.dart';

// Arranger Track (Cubase-style section-based arrangement)
export 'arranger_track_provider.dart';

// Chord Track (Cubase-style chord intelligence)
export 'chord_track_provider.dart';

// Expression Maps (Cubase-style MIDI articulation switching)
export 'expression_map_provider.dart';

// Macro Controls (Multi-parameter control knobs)
export 'macro_control_provider.dart';

// Track Versions (Cubase-style track playlists)
export 'track_versions_provider.dart';

// Clip Gain Envelope (Per-clip gain automation)
export 'clip_gain_envelope_provider.dart';

// Logical Editor (Cubase-style batch operations)
export 'logical_editor_provider.dart';

// Groove Quantize (Humanization and groove templates)
export 'groove_quantize_provider.dart';

// Audio Alignment (VocAlign-style alignment)
export 'audio_alignment_provider.dart';

// Scale Assistant (Cubase-style key/scale helper)
// Hide ScaleType and ChordQuality to avoid conflict with chord_track_provider.dart
export 'scale_assistant_provider.dart' hide ScaleType, ChordQuality;

// History & Undo
export 'project_history_provider.dart';

// Auto-save
export 'auto_save_provider.dart';

// Recent Projects
export 'recent_projects_provider.dart';

// Audio Export
export 'audio_export_provider.dart';

// Session Persistence
export 'session_persistence_provider.dart';

// Error Handling
export 'error_provider.dart';

// Plugin Browser (hide PluginInfo to avoid conflict with mixer_dsp_provider.dart)
export 'plugin_provider.dart' hide PluginInfo;

// AI Mastering
export 'mastering_provider.dart';

// Audio Restoration
export 'restoration_provider.dart';

// ML/AI Processing
export 'ml_provider.dart';

// Lua Scripting
export 'script_provider.dart';
