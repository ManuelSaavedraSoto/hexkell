# Tree

Tree diagram of project structure

```bash
.
├── assets
│   ├── audio
│   │   ├── bgm
│   │   │   └── Warmth.ogg
│   │   └── sfx
│   │       ├── confirmation_004.ogg
│   │       └── error_006.ogg
│   ├── fonts
│   │   └── Mork Dungeon.ttf
│   ├── icons
│   │   ├── buttons
│   │   │   ├── check_mark.tres
│   │   │   ├── closed_trash.tres
│   │   │   ├── codex_icon.tres
│   │   │   ├── copy.tres
│   │   │   ├── cross.tres
│   │   │   ├── export.tres
│   │   │   ├── goal.tres
│   │   │   ├── import.tres
│   │   │   ├── keyboard.tres
│   │   │   ├── library.tres
│   │   │   ├── locked.tres
│   │   │   ├── menu_icon.tres
│   │   │   ├── minus_icon.tres
│   │   │   ├── next_icon.tres
│   │   │   ├── open_trash.tres
│   │   │   ├── plus_icon.tres
│   │   │   ├── prev_icon.tres
│   │   │   ├── question_mark.tres
│   │   │   ├── redo.tres
│   │   │   ├── reload.tres
│   │   │   ├── save.tres
│   │   │   ├── undo.tres
│   │   │   └── unlocked.tres
│   │   ├── hexagons
│   │   │   ├── change_hex.tres
│   │   │   ├── filled_hex.tres
│   │   │   ├── hex_in_hand.tres
│   │   │   ├── hex_stack.tres
│   │   │   ├── hollow_hex.tres
│   │   │   ├── question_hex.tres
│   │   │   ├── swap_in_hex.tres
│   │   │   └── swap_out_hex.tres
│   │   ├── input
│   │   │   ├── keyboard
│   │   │   │   ├── letters
│   │   │   │   │   ├── a.tres
│   │   │   │   │   ├── b.tres
│   │   │   │   │   ├── c.tres
│   │   │   │   │   ├── d.tres
│   │   │   │   │   ├── e.tres
│   │   │   │   │   ├── f.tres
│   │   │   │   │   ├── g.tres
│   │   │   │   │   ├── q.tres
│   │   │   │   │   ├── r.tres
│   │   │   │   │   ├── s.tres
│   │   │   │   │   ├── t.tres
│   │   │   │   │   └── w.tres
│   │   │   │   ├── numbers
│   │   │   │   │   ├── 0.tres
│   │   │   │   │   ├── 1.tres
│   │   │   │   │   ├── 2.tres
│   │   │   │   │   ├── 3.tres
│   │   │   │   │   ├── 4.tres
│   │   │   │   │   ├── 5.tres
│   │   │   │   │   ├── 6.tres
│   │   │   │   │   ├── 7.tres
│   │   │   │   │   ├── 8.tres
│   │   │   │   │   └── 9.tres
│   │   │   │   └── special
│   │   │   │       ├── control.tres
│   │   │   │       ├── enter.tres
│   │   │   │       ├── shift_text.tres
│   │   │   │       ├── shift.tres
│   │   │   │       ├── space_text.tres
│   │   │   │       ├── space.tres
│   │   │   │       ├── tab_text.tres
│   │   │   │       └── tab.tres
│   │   │   └── mouse
│   │   │       ├── all_directions.tres
│   │   │       ├── left_mb.tres
│   │   │       ├── middle_mb.tres
│   │   │       ├── right_mb.tres
│   │   │       └── scroll_wheel.tres
│   │   └── icon.svg
│   ├── particles
│   │   └── circle_02.png
│   ├── resources
│   │   ├── button_groups
│   │   │   └── tab_button_group.tres
│   │   ├── styleboxes
│   │   │   └── hud_styleboxes
│   │   │       ├── button
│   │   │       │   ├── disabled.tres
│   │   │       │   ├── hover_pressed.tres
│   │   │       │   ├── hover.tres
│   │   │       │   ├── normal.tres
│   │   │       │   └── pressed.tres
│   │   │       ├── foldable
│   │   │       │   ├── panel.tres
│   │   │       │   ├── title_collapsed.tres
│   │   │       │   ├── tittle_collapsed_hover.tres
│   │   │       │   ├── tittle_expanded_hover.tres
│   │   │       │   └── tittle_expanded.tres
│   │   │       └── panel
│   │   │           └── panel.tres
│   │   ├── themes
│   │   │   ├── hex_palette_themes
│   │   │   │   ├── boolean_theme.tres
│   │   │   │   ├── function_theme.tres
│   │   │   │   ├── integer_theme.tres
│   │   │   │   ├── naming_theme.tres
│   │   │   │   └── structure_theme.tres
│   │   │   ├── hud_theme.tres
│   │   │   └── tab_button_theme.tres
│   │   ├── colour_palette.tres
│   │   └── hexkell_code_highlighter.tres
│   ├── screenshots
│   │   └── chapters
│   │       └── README.md
│   ├── shaders
│   │   ├── blur.gdshader
│   │   ├── hex_grid.gdshader
│   │   ├── repeat.gdshader
│   │   └── wire_flow.gdshader
│   ├── spritesheets
│   │   ├── iconsDefault.png
│   │   ├── icon_sheet.png
│   │   ├── input_sprite_sheet.png
│   │   ├── ui_sprite_sheet.png
│   │   ├── ui_sprite_sheet.png~
│   │   └── ui_sprite_sheet.svg
│   └── textures
│       ├── conveyor_belt.png
│       └── white_pixel.png
├── data
│   ├── example_templates.json
│   ├── legacy_playground.json
│   ├── static_data.json
│   └── static_data.schema.json
├── docs
│   ├── BLUEPRINT_FORMAT.md
│   ├── CANVAS.canvas
│   ├── HEX_DESIGN.md
│   ├── LANG.md
│   ├── STATIC_DATA_FORMAT.md
│   ├── TODO.md
│   └── TREE.md
├── scenes
│   └── gui
│       ├── blueprint_library
│       │   ├── mini_canvas
│       │   │   ├── blueprint_mini_canvas.gd
│       │   │   └── blueprint_mini_canvas.tscn
│       │   ├── blueprint_library_dialog.gd
│       │   ├── blueprint_library_dialog.tscn
│       │   ├── blueprint_row.gd
│       │   └── blueprint_row.tscn
│       ├── common
│       │   ├── chapter_intro_dialog.gd
│       │   ├── chapter_intro_dialog.tscn
│       │   ├── quick_repl_dialog.gd
│       │   ├── quick_repl_dialog.tscn
│       │   ├── template_accept_dialog.gd
│       │   ├── template_accept_dialog.tscn
│       │   ├── template_hint_toast.gd
│       │   └── template_hint_toast.tscn
│       ├── editor
│       │   ├── code_editor.gd
│       │   ├── editor.gd
│       │   └── editor.tscn
│       ├── hex_editor
│       │   ├── dialogs
│       │   │   ├── codex_dialog.gd
│       │   │   ├── codex_dialog.tscn
│       │   │   ├── keybindings_dialog.gd
│       │   │   └── keybindings_dialog.tscn
│       │   ├── ui
│       │   │   ├── breadcrumb.gd
│       │   │   ├── config_sidebar.gd
│       │   │   ├── job_header.gd
│       │   │   ├── jobs_panel.gd
│       │   │   ├── match_pattern_tree.gd
│       │   │   ├── output_panel.gd
│       │   │   ├── palette_bar.gd
│       │   │   ├── tab_strip.gd
│       │   │   └── top_buttons.gd
│       │   ├── background.gd
│       │   ├── canvas_input_controller.gd
│       │   ├── hex_camera_controller.gd
│       │   ├── hex_editor.gd
│       │   ├── hex_editor.tscn
│       │   ├── hex_level.gd
│       │   ├── hex_toolbar_button.gd
│       │   ├── hex_wire.gd
│       │   ├── identifier_palette.gd
│       │   ├── wire_chain_overlay.gd
│       │   ├── workspace_tab.gd
│       │   └── workspace_tab.tscn
│       ├── main_menu
│       │   ├── main_menu.gd
│       │   └── main_menu.tscn
│       ├── pause_menu
│       │   ├── pause_menu.gd
│       │   └── pause_menu.tscn
│       ├── settings_menu
│       │   ├── settings_menu.gd
│       │   └── settings_menu.tscn
│       └── tutorial
│           ├── highlight_rect.gd
│           ├── tile_marker.gd
│           └── tutorial_hud.gd
├── src
│   ├── classes
│   │   ├── hex_nodes
│   │   │   ├── control
│   │   │   │   ├── definition_hex.gd
│   │   │   │   ├── definition_hex.tscn
│   │   │   │   ├── if_hex.gd
│   │   │   │   ├── if_hex.tscn
│   │   │   │   ├── let_hex.gd
│   │   │   │   ├── let_hex.tscn
│   │   │   │   ├── let_rec_hex.gd
│   │   │   │   ├── let_rec_hex.tscn
│   │   │   │   ├── match_hex.gd
│   │   │   │   └── match_hex.tscn
│   │   │   ├── fixtures
│   │   │   │   ├── anchor_hex.gd
│   │   │   │   ├── anchor_hex.tscn
│   │   │   │   ├── do_hex.gd
│   │   │   │   ├── do_hex.tscn
│   │   │   │   ├── if_anchor.gd
│   │   │   │   ├── if_anchor.tscn
│   │   │   │   ├── list_anchor.gd
│   │   │   │   ├── list_anchor.tscn
│   │   │   │   ├── match_anchor.gd
│   │   │   │   ├── match_anchor.tscn
│   │   │   │   ├── tuple_anchor.gd
│   │   │   │   └── tuple_anchor.tscn
│   │   │   ├── literals
│   │   │   │   ├── booleans
│   │   │   │   │   ├── false_hex.gd
│   │   │   │   │   ├── false_hex.tscn
│   │   │   │   │   ├── true_hex.gd
│   │   │   │   │   └── true_hex.tscn
│   │   │   │   ├── identifier
│   │   │   │   │   ├── ident_ref_hex.gd
│   │   │   │   │   └── ident_ref_hex.tscn
│   │   │   │   ├── integer
│   │   │   │   │   ├── int_literal_hex.gd
│   │   │   │   │   └── int_literal_hex.tscn
│   │   │   │   ├── lambdas
│   │   │   │   │   ├── lambda_hex.gd
│   │   │   │   │   └── lambda_hex.tscn
│   │   │   │   ├── list
│   │   │   │   │   ├── list_literal_hex.gd
│   │   │   │   │   └── list_literal_hex.tscn
│   │   │   │   └── tuple
│   │   │   │       ├── tuple_hex.gd
│   │   │   │       └── tuple_hex.tscn
│   │   │   ├── operators
│   │   │   │   ├── arithmetic
│   │   │   │   │   ├── add_hex.gd
│   │   │   │   │   ├── add_hex.tscn
│   │   │   │   │   ├── div_hex.gd
│   │   │   │   │   ├── div_hex.tscn
│   │   │   │   │   ├── mod_hex.gd
│   │   │   │   │   ├── mod_hex.tscn
│   │   │   │   │   ├── mul_hex.gd
│   │   │   │   │   ├── mul_hex.tscn
│   │   │   │   │   ├── neg_hex.gd
│   │   │   │   │   ├── neg_hex.tscn
│   │   │   │   │   ├── sub_hex.gd
│   │   │   │   │   └── sub_hex.tscn
│   │   │   │   ├── functional
│   │   │   │   │   ├── apply_hex.gd
│   │   │   │   │   ├── apply_hex.tscn
│   │   │   │   │   ├── compose_hex.gd
│   │   │   │   │   └── compose_hex.tscn
│   │   │   │   ├── list
│   │   │   │   │   ├── concat_hex.gd
│   │   │   │   │   ├── concat_hex.tscn
│   │   │   │   │   ├── cons_hex.gd
│   │   │   │   │   ├── cons_hex.tscn
│   │   │   │   │   ├── range_hex.gd
│   │   │   │   │   └── range_hex.tscn
│   │   │   │   ├── logical
│   │   │   │   │   ├── and_hex.gd
│   │   │   │   │   ├── and_hex.tscn
│   │   │   │   │   ├── eq_hex.gd
│   │   │   │   │   ├── eq_hex.tscn
│   │   │   │   │   ├── gte_hex.gd
│   │   │   │   │   ├── gte_hex.tscn
│   │   │   │   │   ├── lt_hex.gd
│   │   │   │   │   ├── lt_hex.tscn
│   │   │   │   │   ├── neq_hex.gd
│   │   │   │   │   ├── neq_hex.tscn
│   │   │   │   │   ├── not_hex.gd
│   │   │   │   │   ├── not_hex.tscn
│   │   │   │   │   ├── or_hex.gd
│   │   │   │   │   └── or_hex.tscn
│   │   │   │   ├── binary_op_hex.gd
│   │   │   │   ├── binary_op_hex.tscn
│   │   │   │   ├── unary_op_hex.gd
│   │   │   │   └── unary_op_hex.tscn
│   │   │   ├── hex_node.gd
│   │   │   └── hex_node.tscn
│   │   ├── interpreter
│   │   │   ├── expressions
│   │   │   │   ├── control.gd
│   │   │   │   ├── expr.gd
│   │   │   │   └── operator.gd
│   │   │   ├── env.gd
│   │   │   ├── pattern.gd
│   │   │   ├── prelude.gd
│   │   │   └── value.gd
│   │   ├── parser
│   │   │   ├── lexer
│   │   │   │   ├── lexer.gd
│   │   │   │   └── token.gd
│   │   │   └── parser.gd
│   │   ├── checker.gd
│   │   └── draggable_button.gd
│   ├── singletons
│   │   ├── sound
│   │   │   ├── bgm_manager.gd
│   │   │   └── sfx_manager.gd
│   │   ├── chapter_manager.gd
│   │   ├── save_manager.gd
│   │   ├── scene_manager.gd
│   │   ├── static_data.gd
│   │   ├── template_manager.gd
│   │   └── tutorial_manager.gd
│   └── statics
│       ├── blueprint_codec.gd
│       ├── blueprint_loader.gd
│       ├── hex_math.gd
│       ├── hex_palette.gd
│       ├── hex_text_formatter.gd
│       ├── identifier_scope.gd
│       ├── input_display.gd
│       ├── input_gates.gd
│       ├── modal_stack.gd
│       ├── pattern_tree.gd
│       ├── pattern_variables.gd
│       ├── tab_store.gd
│       └── text_utils.gd
├── test
│   └── unit
│       ├── data
│       │   └── test_static_data_format.gd
│       ├── hex_editor
│       │   ├── test_arity_incremental.gd
│       │   ├── test_blueprint_codec.gd
│       │   ├── test_blueprint_mini_canvas.gd
│       │   ├── test_canvas_input_controller.gd
│       │   ├── test_chapter_intro_dialog.gd
│       │   ├── test_chapter_manager.gd
│       │   ├── test_chapter_progression.gd
│       │   ├── test_codex_dialog.gd
│       │   ├── test_config_sidebar.gd
│       │   ├── test_dialog_smoke.gd
│       │   ├── test_do_display_value.gd
│       │   ├── test_edge_role_labels.gd
│       │   ├── test_editor_qol.gd
│       │   ├── test_editor_smoke.gd
│       │   ├── test_free_identifier_failsafe.gd
│       │   ├── test_hex_palette.gd
│       │   ├── test_identifier_palette_exposure.gd
│       │   ├── test_identifier_scope.gd
│       │   ├── test_input_display.gd
│       │   ├── test_jobs_data.gd
│       │   ├── test_jobs_panel_tooltip.gd
│       │   ├── test_match_pattern_tree.gd
│       │   ├── test_modal_input_gate.gd
│       │   ├── test_node_feedback_fx.gd
│       │   ├── test_output_panel.gd
│       │   ├── test_panel_outcome_colors.gd
│       │   ├── test_pattern_tree.gd
│       │   ├── test_pattern_variables.gd
│       │   ├── test_placement_connect_fx.gd
│       │   ├── test_rmb_cancel_guard.gd
│       │   ├── test_save_manager_hex.gd
│       │   ├── test_single_slot_fixtures.gd
│       │   ├── test_tab_store.gd
│       │   ├── test_tab_strip.gd
│       │   ├── test_text_emission.gd
│       │   ├── test_text_utils.gd
│       │   ├── test_tutorial_manager.gd
│       │   ├── test_validator_edge_indices.gd
│       │   ├── test_wire_chain_lock.gd
│       │   ├── test_wire_chain_overlay.gd
│       │   ├── test_wire_finalize_truncate.gd
│       │   ├── test_wire_legality.gd
│       │   ├── test_wire_routing.gd
│       │   └── test_workspace_tab.gd
│       ├── interpreter
│       │   ├── test_arithmetic.gd
│       │   ├── test_checker_structures.gd
│       │   ├── test_comparison_and_equality.gd
│       │   ├── test_control_flow.gd
│       │   ├── test_force_engine.gd
│       │   ├── test_lambda_closure.gd
│       │   ├── test_letrec_let.gd
│       │   ├── test_list_ops.gd
│       │   ├── test_literals.gd
│       │   ├── test_logical.gd
│       │   ├── test_negation.gd
│       │   ├── test_pattern_matching.gd
│       │   ├── test_runtime_errors.gd
│       │   └── test_stdlib.gd
│       ├── lexer
│       │   └── test_lexer.gd
│       ├── parser
│       │   └── test_parser.gd
│       └── sound
│           ├── test_bgm_manager.gd
│           └── test_sfx_manager.gd
├── CREDITS.md
├── export_presets.cfg
├── justfile
├── project.godot
└── README.md
```
