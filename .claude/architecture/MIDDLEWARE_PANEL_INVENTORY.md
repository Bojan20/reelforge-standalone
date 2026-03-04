# Middleware Panel Inventory — SlotLab Integration Status

> Generated: 2026-03-04
> Context: Middleware UI section removed, all functionality migrated to unified SlotLab

---

## Status Legend

- **IN SLOTLAB** — Already integrated into SlotLab lower zone tabs
- **AVAILABLE** — Panel exists in `widgets/middleware/`, ready for SlotLab integration
- **DEAD** — No longer imported anywhere, candidate for deletion

---

## INTEGRATED INTO SLOTLAB (18 panels)

| # | Panel File | SlotLab Tab | Sub-Tab |
|---|-----------|-------------|---------|
| 1 | `blend_container_panel.dart` | CONTAINERS | Blend |
| 2 | `random_container_panel.dart` | CONTAINERS | Random |
| 3 | `sequence_container_panel.dart` | CONTAINERS | Sequence |
| 4 | `music_system_panel.dart` | MUSIC | Segments |
| 5 | `stinger_preview_panel.dart` | MUSIC | Stingers |
| 6 | `music_transition_preview_panel.dart` | MUSIC | Transitions |
| 7 | `rtpc_curve_template_panel.dart` | RTPC | Curves |
| 8 | `rtpc_macro_editor_panel.dart` | RTPC | Macros |
| 9 | `rtpc_dsp_binding_editor.dart` | RTPC | DSP Binding |
| 10 | `rtpc_debugger_panel.dart` | RTPC | Debugger |
| 11 | `mwui_build_view.dart` | INTEL | Build |
| 12 | `mwui_flow_view.dart` | INTEL | Flow |
| 13 | `mwui_simulation_view.dart` | INTEL | Sim |
| 14 | `mwui_diagnostic_view.dart` | INTEL | Diagnostic |
| 15 | `mwui_template_gallery.dart` | INTEL | Templates |
| 16 | `mwui_export_panel.dart` | INTEL | Export |
| 17 | `mwui_coverage_viz.dart` | INTEL | Coverage |
| 18 | `mwui_inspector_panel.dart` | INTEL | Inspector |

---

## NOT YET IN SLOTLAB (36 panels) — Candidates for Future Integration

### Event System (7)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 1 | `event_editor_panel.dart` | EVENTS | Event property editor |
| 2 | `event_profiler_panel.dart` | MONITOR | Event performance profiler |
| 3 | `event_profiler_advanced.dart` | MONITOR | Advanced event profiling |
| 4 | `event_debugger_panel.dart` | MONITOR | Event execution debugger |
| 5 | `event_templates_panel.dart` | EVENTS | Event template browser |
| 6 | `event_dependency_graph_panel.dart` | LOGIC | Event dependency visualization |
| 7 | `events_folder_panel.dart` | EVENTS | Event folder tree browser |

### Container Advanced (12)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 8 | `container_ab_comparison_panel.dart` | CONTAINERS | A/B container comparison |
| 9 | `container_crossfade_preview_panel.dart` | CONTAINERS | Crossfade curve preview |
| 10 | `container_evaluation_debug_panel.dart` | MONITOR | Container eval debugger |
| 11 | `container_groups_panel.dart` | CONTAINERS | Container group manager |
| 12 | `container_import_export_dialog.dart` | BAKE | Container import/export |
| 13 | `container_metrics_panel.dart` | MONITOR | Container metrics dashboard |
| 14 | `container_performance_panel.dart` | MONITOR | Container perf stats |
| 15 | `container_preset_browser.dart` | CONTAINERS | Preset browser |
| 16 | `container_preset_library_panel.dart` | CONTAINERS | Preset library manager |
| 17 | `container_storage_metrics.dart` | MONITOR | Storage usage metrics |
| 18 | `container_timeline_zoom.dart` | CONTAINERS | Timeline zoom view |
| 19 | `container_visualization_widgets.dart` | CONTAINERS | Shared visualization widgets |

### Bus/Routing (2)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 20 | `bus_hierarchy_panel.dart` | MIX | Bus hierarchy tree view |
| 21 | `ducking_matrix_panel.dart` | MIX | Ducking priority matrix |

### DSP/Audio (6)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 22 | `attenuation_curve_panel.dart` | DSP | Attenuation curve editor |
| 23 | `audio_signatures_panel.dart` | DSP | Audio signature analyzer |
| 24 | `dsp_profiler_panel.dart` | MONITOR | DSP CPU profiler |
| 25 | `dsp_load_badge.dart` | MONITOR | DSP load indicator widget |
| 26 | `layer_dsp_chain.dart` | DSP | Per-layer DSP chain editor |
| 27 | `advanced_middleware_panel.dart` | — | Legacy advanced panel |

### Music System (1)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 28 | `music_segment_looping_panel.dart` | MUSIC | Segment loop point editor |

### Editors (4)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 29 | `action_editor_widget.dart` | EVENTS | Action layer inline editor |
| 30 | `automation_lane_editor.dart` | EVENTS | Automation curve editor |
| 31 | `aux_send_panel.dart` | MIX | Aux send routing panel |
| 32 | `beat_grid_editor.dart` | MUSIC | Beat grid / tempo editor |

### Monitoring/Debug (6)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 33 | `priority_tier_preset_panel.dart` | LOGIC | Priority tier configuration |
| 34 | `resource_dashboard_panel.dart` | MONITOR | Resource usage dashboard |
| 35 | `state_machine_graph.dart` | LOGIC | State machine graph data |
| 36 | `state_machine_graph_widget.dart` | LOGIC | State machine visualizer |
| 37 | `state_transition_history_panel.dart` | LOGIC | State transition log |
| 38 | `voice_pool_stats_panel.dart` | MONITOR | Voice pool statistics |

### Other (3)
| # | Panel File | Potential SlotLab Tab | Description |
|---|-----------|----------------------|-------------|
| 39 | `intensity_crossfade_wizard.dart` | CONTAINERS | Intensity crossfade wizard |
| 40 | `preset_morph_editor_panel.dart` | DSP | Preset morphing editor |
| 41 | `spatial_designer_widget.dart` | DSP | 3D spatial audio designer |

### Utility (3)
| # | Panel File | Notes |
|---|-----------|-------|
| 42 | `middleware_exports.dart` | Barrel export file |
| 43 | `layer_timeline_panel.dart` | Layer timeline view |
| 44 | `slot_audio_panel.dart` | SlotLab audio assignment panel |

---

## REMOVED (Middleware UI Infrastructure)

| File | Status |
|------|--------|
| `middleware_lower_zone_widget.dart` | **DELETED** |
| `middleware_lower_zone_controller.dart` | **DELETED** |
| `middleware_hub_screen.dart` | **DEAD** (import removed, file remains) |
| `EditorMode.middleware` | **REMOVED** from enum |
| `AppMode.middleware` | **REMOVED** from enum |
| `MiddlewareSuperTab` + sub-tab enums | **REMOVED** from lower_zone_types.dart |
| `MiddlewareLowerZoneState` | **REMOVED** from lower_zone_types.dart |
| Middleware persistence methods | **REMOVED** from persistence service |

---

## SlotLab Super-Tabs (Current)

```
STAGES | EVENTS | MIX | DSP | RTPC | CONTAINERS | MUSIC | LOGIC | INTEL | MONITOR | BAKE
```

Each tab has sub-tabs with dedicated panel content. The middleware panels listed above
can be integrated into appropriate sub-tabs as needed.
