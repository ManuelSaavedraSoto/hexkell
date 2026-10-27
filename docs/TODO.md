# TODO

The single source of truth for what's done and what's left. For
visual-language semantics see `HEX_DESIGN.md`, for the wire format
see `BLUEPRINT_FORMAT.md`, for the language EBNF see `LANG.md`.

## Versioning

| Version | What | Status |
|---|---|---|
| **v1** | Old strict language | Feature complete, superseded by v2; will not be revived. |
| **v2** | Lazy language with text editor | Stable but rough. Language runtime complete; text editor remains as an "advanced mode" surface during the v3 transition. |
| **v3** | v2 language with the hex-grid editor | Active development. The main gameplay mode going forward. |

## Repo housekeeping

- [X] Come up with a name — _"Hexkell"_
- [X] Text editor for MVP (now being replaced by the hex editor)
- [ ] README.md content review — keep the project status section in
  sync with this TODO when major items land
- [ ] Client system (gameplay flavor layer that wraps jobs as
  in-fiction commissions)

---

## v1 — Completed

The strict-evaluation predecessor. Documented for historical record;
will not be revived.

---

## v2 — Completed

### Language runtime

- [X] Extend concrete syntax for v2
    - [X] Static typing (syntax only; runtime is dynamic)
    - [X] Multiple expression declaration
- [X] Implement lazy evaluation
    - [X] Add Thunks
- [X] Implement expressions
    - [X] Lambda expressions
    - [X] Applications
    - [X] Built-in operators
- [X] Support recursion (top-level + `let rec`)
- [X] Pattern matching (literals, tuples, lists, cons, wildcards)
- [X] Lists, tuples, ranges (incl. infinite ranges)
- [X] Standard prelude (`Prelude.load_std_lib`)
- [X] Implement parsing for v2
    - [X] Lexer (tokens)
    - [X] Parser (precedence-aware)
- [X] Tests (lexer, parser, interpreter — 165+ tests passing)
- [X] Update REPL to use v2 (Quick REPL bound to `Ctrl+R`)
- [X] Update documentation for v2

### Text editor — legacy surface

Stable; remains reachable from the main menu while v3 ramps up. No
new feature work planned — once v3 covers the full gameplay loop the
text editor can retire (or stay as a debug aid).

### Static typing — out of scope for now

Not blocking gameplay; the EBNF anticipates it but the runtime is
intentionally dynamic. Re-evaluate after v3 stabilizes.

- [ ] ~~Implement static types: Integers, Bools, Tuples, Lists~~
- [ ] ~~Subtype systems~~

---

## v3 — Hex-grid editor

The current gameplay surface. Replaces text-editor exercises with
canvas-based blueprint construction. Players keep persistent
workspace tabs, build programs as hex graphs, submit any tab against
a job to fulfill it, and earn renown that unlocks new hex types.

### v3 — Active work

#### Editor interaction QoL (friction pass)

Playtesting surfaced a cluster of editor-interaction friction points in
the core build loop (placing, re-orienting, repositioning hexes, level
navigation, configuring). High priority. Tackled one commit at a time.

- [X] Config panel no longer grows off-screen on the identifier hex
  (the picker's `OptionButton` no longer sizes to its longest item).
- [X] Opening the output foldable closes the config panel (mirror the
  existing config→output fold).
- [X] Right-click in stamp mode ONLY exits stamp mode — never deletes a
  hex under any circumstance.
- [X] Right-click only deletes a hex when neither stamp mode nor the
  config panel is active (unify the two RMB contextual-cancel paths).
- [X] Double-click a hex to "pick it up" for repositioning — preserves
  configuration (equivalent to Ctrl+X / pipette + delete original).
  Draggable hexes.
- [X] Stamping a same-type hex onto a placed one with a different
  rotation overwrites only the placed hex's rotation, keeping its config.
- [X] Ascend / descend buttons in the config panel (of both the inner
  fixture and the outer hex) so level navigation works mouse-only.
- [X] Animated (~200ms) camera zoom+pan + fade transition between hex
  levels (Q descend / E ascend).
- [X] Breadcrumb buttons lerp the camera toward the clicked fixture
  instead of snapping.
- [X] Match / Tuple / Def / Let / LetRec configurable from their inner
  fixture — shipped via `HexNode.config_delegate()`
  (`AnchorHex`/`TupleAnchor`/`MatchAnchor` → `level.parent_hex`).
- [X] Stamp commits no longer wipe undo/redo — a paste is a single
  undoable `place_stamp` bulk action (placed hexes/wires + their inner
  levels, reversed in one step) that preserves earlier history.
- [X] Same-type stamp re-orientation is undoable (and refreshes the
  config sidebar's Slots section when the re-oriented hex is open).
- [X] Wiring over an already-fed input parks (not disposes) the displaced
  wire, so undoing the replacement restores the original connection.
- [X] Breadcrumb moved into the top bar's center section (left-aligned,
  opposite the right-aligned undo/redo/clear buttons).
- [X] Codex chapter entries render a live `BlueprintMiniCanvas` preview of
  the chapter's first example blueprint in the detail pane.
- [X] Picking up a placed hex is a dedicated single-shot "move": a
  translucent ghost stays at the origin, LMB places once and exits (no
  repeat-stamp), RMB cancels and returns the hex, and a completed move is
  one undo entry. Parks the original via `_apply_delete_hex` (not
  `_delete_hex`) so it doesn't fire `hex_deleted` at the tutorial.

#### Editor refactor (signal-driven panel scripts)

The 3,800-line `hex_editor.gd` is being split into focused scripts
attached to scene nodes that emit semantic signals. Pattern proven
on six panels; the higher-coupling ones below remain inline.

- [X] `BlueprintCodec` / `BlueprintLoader` moved to `src/statics/`
- [X] `HexTextFormatter` extracted (paren-cleanup pipeline)
- [X] `HexMath` gains `axial_distance` + `step_direction`
- [X] Panel scripts: `top_buttons`, `output_panel`, `jobs_panel`,
  `job_header`, `breadcrumb`, `config_sidebar`
- [X] Panel script: `palette_bar` (palette + category buttons)
  owns CATEGORIES catalog + button row construction + lock paint;
  editor wires `palette_bar.hex_selected → _enter_blueprint_fresh`
  once at boot and forwards `cat_*` / `hex_*` keyboard actions
  through `palette_bar.{select_category,step_category,cycle_hex,
  pick_slot,highlight_active_hex,set_unlocked_scripts}`.
- [X] Panel script: `tab_strip` owns the strip view — builds its own
  tab buttons (`rebuild(names, active_idx)`), the right-click context
  menu, and the rename dialog, and emits switch/close/clear/copy/
  rename/new intents the editor answers. Per-tab logic (`clear_content`
  / `store_view` / `rename`) moved onto the `WorkspaceTab` node; the
  editor keeps `_tabs` / `_active_tab_idx` orchestration.
- [X] Panel script: `pause_menu` (Esc / menu button overlay)
- [X] Camera script: `hex_camera_controller` owns keyboard pan
  (`canvas_pan_*`), keyboard + mouse-wheel zoom (`canvas_zoom_in` /
  `canvas_zoom_out`), and middle-drag pan. Editor no longer carries
  pan/zoom state or input plumbing.
- [ ] Canvas controllers: `node_canvas` (placed-hex registry,
  marquee, selection, single-hex blueprint cursor, stamp previews)
- [ ] Canvas controllers: `wire_canvas` (wire visuals, drag state,
  routing, open-wire reactivation)
- [ ] Final pass: prune helpers that became single-use into their
  owners; target the editor at under 1,500 lines

#### Camera2D pan / zoom

The editor used to scale + translate the `World` Node2D directly for
pan/zoom. That's the wrong layer for a shader-driven grid background
(the shader wants the canvas → screen transform from a camera). The
move to `Camera2D` keeps `World` at the identity transform and
delegates view state to the camera.

- [X] Add `HexCamera` Camera2D under `World`; reset `World`'s
  legacy `(720, 360)` translation back to the origin
- [X] `_zoom_at(screen_pos, factor)` pivots `Camera2D.zoom` around
  the cursor (mouse-world position stays put across the zoom)
- [X] Middle-drag + WASD pan move `Camera2D.position` (opposite the
  drag, divided by zoom so a 1-screen-pixel drag is always 1 screen
  pixel regardless of zoom)
- [X] Per-level state: `HexLevel.world_position` / `world_scale`
  fields kept (save-format stable) but reinterpreted as camera
  position + zoom scalar
- [X] `_mouse_world()` reduced to `get_global_mouse_position()` —
  the camera handles the canvas-to-world transform
- [X] Shader-based grid background (`assets/shaders/hex_grid.gdshader`
  + `scenes/gui/hex_editor/background.gd`) samples the camera's
  position + zoom each frame to draw an infinite hex grid that
  stays in sync with placed hexes. Two fixes were needed:
  - Background ColorRect parked on a dedicated CanvasLayer
    (layer = -1) so the Camera2D doesn't translate the rect itself
    — only the shader's `world_pos` math reacts to the camera.
  - Shader uses `SCREEN_UV` (normalized 0–1 across the actual
    rendered screen) rather than `FRAGCOORD`. With
    `window/stretch/mode = "canvas_items"` the render target is
    the actual window pixels while canvas items are pre-scaled to
    the design viewport — so FRAGCOORD reported physical pixels
    and the `screen_size` uniform (the logical 1920×1080) didn't
    match, drifting the grid off the hexes whenever the window
    was resized. SCREEN_UV avoids the problem entirely.

#### Scene layout pass

Full-width top + bottom bars with the jobs panel floating between
them. Region heights follow the rule-of-thirds budget at the
1920×1080 baseline: TopBar fits within the top third of the top
third (~11.1% / 120px), PaletteBar within half of the bottom third
(~16.7% / 180px). All major regions anchor by fraction so
proportions stay constant under window scaling.

- [X] `TopBar` (0 – 0.111) full width with CornerLeft / CenterBar
  / CornerRight at 1:4:1 stretch ratios
- [X] `PaletteBar` (0.833 – 1.0) full width (OutputBox + hex row +
  category row stacked)
- [X] `MiddleArea` (0.111 – 0.833) hosts the canvas and the
  floating side panels
- [X] `JobsPanel` floats anchored to the left fraction of the
  middle area, over the hex canvas
- [X] `ConfigPanel` floats anchored to the right fraction of the
  middle area
- [X] CornerLeft holds `MenuButton`, `HelpButton`, `CodexButton`
  (disabled placeholder) + `RenownLabel`
- [X] CornerRight holds `GenerateButton`, `RunButton`,
  `LibraryButton` (Export retired — see below)
- [X] Run / Generate / Library buttons wear the `HexToolbarButton`
  chrome with their hotkey badge in the bottom-right corner
  (`Spc`, `⇧Spc`, `B`) and the CK3-style title + body tooltip
- [X] Job name + description moved back inside the JobsPanel
  (frees TopBar height back to the rule-of-thirds budget); the
  panel toggles between list view and description view on `Ctrl+F`
- [X] `CodexButton` wired to a `codex_requested` signal (no-op
  placeholder until the chapter / concepts library lands)
- [X] Job names use `autowrap_mode = WORD_SMART`
- [X] Removed `(+%d renown)` from job card labels (reward → tooltip)
- [X] Retired the `ExportButton` and its `_show_export_dialog`
  (deprecated by the blueprint export flow + `Ctrl+Space`
  program-text clipboard copy)
- [ ] Responsive breakpoints for narrow viewports (stack corner
  items vertically, collapse JobsPanel to a toggle) — deferred;
  the ratio layout holds proportions but very narrow windows still
  want the reflow
- [ ] Completed-jobs modal behind a CornerLeft button (currently
  the jobs panel lists completed jobs inline)
- [ ] Resizable divider between JobsPanel and the canvas (fixed
  20% width for now)
- [X] OutputPanel floats on the right edge of MiddleArea (mirror
  of JobsPanel), two views (Log / generated Text) togglable via
  header buttons, minimized by default (`O` toggles). Sibling
  order puts `ConfigPanel` after `OutputPanel` so the config
  view covers the output when both want the right slot — no
  hide/show plumbing needed.

#### Hex-node scenification

Every hex type currently builds its visuals in code: each subclass
of `HexNode` overrides `_setup_content()` to spawn `Label`s,
`Polygon2D`s, `OptionButton`s, etc. at runtime. That's fast to
iterate on as a programmer but actively hostile to theming and
art: there's no way to tweak a hex's look in the Godot editor,
swap a label font on one hex type, attach a shader to a single
slot, or preview the result without launching the game. The
in-engine `Theme` system can only style what's in a scene.

Goal: replace the procedural setup with one `.tscn` per hex type
under `scenes/hex_nodes/<type>.tscn`. The script stays the source
of truth for slot identity / connector geometry / `to_source`; the
scene owns the visual chrome (background polygon, title label,
inscription rows, status dot). Palette instancing becomes a
straight `PackedScene.instantiate()` — no more "build the visuals
on `_ready`" cycle.

- [X] One `.tscn` per concrete hex type (inherited from
  `src/classes/hex_nodes/hex_node.tscn`). All 35 subclass scripts
  moved alongside the base to `src/classes/hex_nodes/`.
- [X] Slot anchors live on Marker2D nodes inside the base scene's
  `EdgeRight` / `EdgeTopLeft` / … Area2Ds; `slot_world_position()`
  reads `_edge_nodes[phys].anchor.position` instead of recomputing
  via `HexMath`.
- [X] Single instantiation path: `HexNode.from_script(script)` on
  the base resolves the per-subclass `.tscn` from the script's
  `resource_path` and returns an instance with the scene chrome
  bound. `BlueprintLoader.instantiate`, the editor's blueprint
  preview, `clone()`, and inner-anchor creation all funnel through
  it.
- [X] Save-data migration in `SaveManager._migrate_legacy_unlock_paths`
  retargets the legacy `scenes/gui/hex_editor/nodes/…` unlock
  paths to the new directory on read.
- [ ] Audit `_setup_content()` across every hex subclass and
  factor out the shared pieces (badge / title label / inscription
  LineEdit row) into common sub-scenes the leaf scenes compose,
  letting `_setup_content` retire on each migrated type.
- [ ] Custom `Theme` types per hex category (`Hex/Literal`,
  `Hex/Operator`, …) so the palette + canvas can re-skin a whole
  category from the theme resource. Inherited subclass scenes
  unlock this — set theme overrides directly on each type's `.tscn`.
  - [ ] Set-up the new themes with the correct colour palettes.
- [X] "Do" hexes on tabs 2-... be undeletable
- [X] Compose hex → two wired function inputs (`f` NW / `g` SW), emits
  `(f . g)`; dropped the old wireless palette-pick state so any wired
  expression can be composed.
- [X] Rework the if hex to be structurally consistent with the
  lambda, let, and match hexes: condition on the outer face, then/else
  bodies one level down in an `IfAnchor` with branded slots.
- [X] Tuple / List rework — implemented as designed:
  - **Tuple**: outer hex = output only, arity 2–5 via a sidebar
    SpinBox. Inner `TupleAnchor` with one slot per element, branded
    `1st`…`5th` through `input_role_labels`. Fixed, known shape —
    mirrors how tuples pattern-match.
  - **List**: outer hex = output only. Inner `ListAnchor` with up to
    5 element slots — and the anchor itself can "go deeper": when the
    current level's slots are all wired, pressing Q over the anchor
    descends another level to a continuation anchor for more
    elements. Lists nest indefinitely, making "unknown length, built
    from cons cells" tangible in contrast to tuple's fixed shape.
  - Resolved open questions: empty list = no inner level (or nothing
    wired) → `[]`; the descend gate is a `can_descend(canvas)` virtual
    on `HexNode` (ListAnchor requires all 5 slots wired, but re-entry
    to an existing continuation stays open); continuation chains
    serialize as a level-body `inner` key (the fixture's own inner
    level — see BLUEPRINT_FORMAT.md); emission stays flat `[a, b, …]`
    sugar across the whole chain; no migration needed (no stored
    blueprints contained either hex).
- [X] Single-slot fixtures — the Do main-expression slot and the
  Let/LetRec/Lambda/Definition `AnchorHex` return slot expose all six
  sides as one logical input (approach from any side), taking one wire
  total. Marked by `HexNode.exclusive_input_group`; the editor's
  `_commit_active_wire` replaces across the whole group, and both
  fixtures' `validate` flag an adjacency double-feed via
  `wired_input_edges`.
  - [ ] Optional follow-up: a visual "occupied" state so the other
    five sides read as taken once one is wired (slot visuals don't
    track wiring today — would be a new repaint-on-commit system).
- [X] Non-destructive arity + inner-anchor config delegation — arity
  changes on Tuple / Match / Lambda / Definition no longer purge the
  inner level. Slot edges follow a prefix-stable clockwise-from-NE order
  (`HexMath.edges_for_arity`, `[5, 0, 1, 2, 3, 4]` — same as
  `ListAnchor`), so growing appends an empty slot and shrinking drops
  only the removed slot's wire (`arity_change_requested` →
  editor `_on_arity_change_requested`, an undoable `arity` action that
  preserves undo/redo). Clicking an inner anchor opens the owning hex's
  full config via `HexNode.config_delegate()`, so the player reconfigures
  from inside the body. The old `inner_level_invalidated` /
  `structure_invalidated` purge path was removed. (Pre-release: no
  blueprint migration — stored graphs with wired arity ≥1 tuples /
  matches / lambdas lose body wiring on reload; re-capture affected
  chapter examples.)

#### Per-tab hex-graph persistence (was 19.8)

- [X] `SaveManager.set_tabs(payloads, current_id)` — `payloads` are
  `{name, payload}` dicts; `payload` is what
  `BlueprintCodec.serialize_root(...)` returns
- [X] `SaveManager.get_tab_payloads()` — round-trip read
- [X] `_bootstrap_tabs` calls `BlueprintLoader.instantiate` per tab
  to rehydrate the canvas
- [X] One-shot migration in `SaveManager._migrate_legacy_tabs` for
  legacy `tabs: [String]` saves
- [X] Auto-save on every undoable action (debounced via Timer, 1s),
  plus a flush in `_exit_tree` so pending changes always reach disk
- [ ] Fix visual bug where hex levels/layers collapse on reloading or
  stamping a hex with multiple layers, showing all single layers on
  level 0

#### "Archmage" mode

- [X] Add a setting for "archmage" mode, where all hexes are unlocked
  from start (basically a debug mode in the meantime). Lives in the
  in-game settings modal (Pause → Settings); short-circuits
  `SaveManager.is_hex_unlocked` and the jobs panel's renown gate.

#### Settings & accessibility (follow-ups)

- [ ] Keybind customization UI — the pause menu's `Keybinds`
  button is a placeholder; wire it to a modal that lists every
  InputMap action (canvas pan/zoom, palette categories, jobs
  cycle, sys_*, hex_toggle_output, etc.) and lets the player
  rebind each one. Persist bindings via SaveManager.
- [ ] Hex category color coding — surface the per-category
  fill / border color in `palette_bar.CATEGORIES` as a theme
  resource so each category's hex buttons (and the inherited
  hex scenes once Phase B of hex-node scenification lands)
  re-skin from one resource. Settings exposes a swatch picker
  per category.
- [ ] Colorblind mode shaders —
  `assets/shaders/colorblind_*.gdshader` variants (protanopia /
  deuteranopia / tritanopia) wired to a full-screen CanvasLayer
  the editor + main menu route through. Toggle in settings
  picks the active variant (or "off").

#### Chapter intros + encyclopedia (was 19.9)

The chapter dialog itself is now v3-friendly: right column shows a
gallery of in-game screenshots (or a placeholder when the file
isn't on disk yet) instead of an editable code snippet. Chapter
data is broken down per concept: `chapter_0_tutorial` (placing a
hex) → `chapter_1_integer_operators` → `chapter_2_boolean_literals`
→ `chapter_3_boolean_operators` → `chapter_4_identifiers` →
`chapter_5_conditionals` → `chapter_6_lambdas` → `chapter_7_bindings`
→ `chapter_8_structures`.

- [X] Chapter intro dialog showcases screenshots instead of an
  editable code editor — graceful placeholder for pending captures
- [X] `chapters` section in `static_data.json` restructured per the
  canvas flow (tutorial → lambdas & structures)
- [X] Chapter examples render via `SubViewport`-hosted blueprint
  previews. The reusable `BlueprintMiniCanvas` scene
  (`scenes/gui/common/blueprint_mini_canvas.tscn`) decodes a
  `hxk1:...` blueprint string into a read-only canvas of
  `HexNode`s + wire `Line2D`s — same primitives, same wire-flow
  shader as the main editor. Authoring is the regular in-game
  flow: build the graph in the editor, Library → Capture →
  Export pushes the encoded string to the clipboard, paste it
  into the `examples[].blueprint` field on the chapter entry.
  `DoHex.display_value` (archmage-only config sidebar) round
  trips via the new `fixture_state` field on `BlueprintCodec.
  serialize_root`. First example shipped: `tutorial_numbers`
  (Int(5) → Do showing "5").
- [X] Author the remaining chapter example blueprints
  (tutorial_binary_ops, tutorial_booleans, tutorial_if,
  tutorial_identifiers, tutorial_let, tutorial_let_rec,
  tutorial_definitions; plus the
  chapter_1_lambdas_and_structures slides). Build each in the
  editor, capture + export, paste the string into the chapter
  entry's `blueprint` field.
- [X] Slot `BlueprintMiniCanvas` into the blueprint library
  modal's "Preview" pane (currently a placeholder Label at
  `hex_editor.gd:3008-3033`). The mini-canvas's public
  `load_blueprint_dict(payload)` matches what the library card
  has in memory — no new API needed.
- [X] One-click "Copy current tab as blueprint" button on the
  editor's top bar so the chapter-author flow becomes one
  click instead of Library → Capture → Export. The top-bar
  "Copy BP" button calls `BlueprintCodec.serialize_root` and
  pushes the encoded string to `DisplayServer.clipboard_set`.
- [X] Editor canvas auto-computes `DoHex.display_value` —
  when the wired chain into `Do` resolves to a literal-only
  static expression (literals + operators + `if`), the editor
  evaluates it via the interpreter and writes the result
  through `DoHex.set_display_value(...)`. Refreshes on undo
  pushes, undo/redo, tab loads, and config-sidebar closes.
  Covered by `test/unit/hex_editor/test_do_display_value.gd`.
- [X] Trigger the dialog when selecting a job from an unseen chapter,
  not immediately on entry and NOT on solve — popping the next
  chapter's intro the moment Run succeeded was jarring. (A fresh save
  still pops the tutorial intro on first entry — it's the player's
  first contact.) Chapter/job logic now lives on the `ChapterManager`
  autoload (`src/singletons/chapter_manager.gd`), signal-connected to
  the editor's thin UI handlers.
- [X] Further breakdown the current chapters, so that explaining
  hexes and placing a single integer hex and wiring it to the do hex
  is a chapter in of itself. Now a 10-job ladder, one concept per
  chapter: place Int (job_01) → addition on literals (job_02, bare 8
  rejected) → boolean literal (job_03) → literal comparison (job_04,
  bare true rejected) → a dedicated identifiers chapter (job_05 echo
  `white` with Int literals forbidden, job_06 double it, job_07
  compare white/black) → conditionals (job_08, requires `if`) →
  lambdas (job_09, job_10). Structural enforcement via
  required/forbidden_structures keeps FP-literate players from
  skipping the lesson. Remaining authoring gaps:
    + `chapter_3_boolean_operators` ships a placeholder slide —
      build a comparison example in-game and Copy BP (tab
      context menu) it into the entry's `blueprint` field.
    + Pre-renumber saves keep their renown but renamed jobs
      (job_05..job_10) reappear as pending — acceptable pre-release.
- [ ] Port the "Concepts" overlay (`menu_overlay` in `Editor`)
  recast as "Hex types I've unlocked" + their behavior tooltips.
  Plan: becomes the codex's "Hexes" section (below) — build it
  from the palette categories + `SaveManager.get_unlocked_hex_
  scripts()`, with each hex's slot tooltip + behavior copy ported
  from `scenes/gui/editor/editor.gd:115-134, 590-707`.
- [ ] Codex has three main sections: Unlocked chapter dialogues, Hexes
  and Advanced Concepts.
  Plan: restructure `scenes/gui/hex_editor/dialogs/codex_dialog.gd`
  (currently a stub with a working `set_concepts`/`show_concept`
  API) into a three-tab browser; content lives in a new `"codex"`
  section of `data/static_data.json`; `hex_editor._on_codex_
  requested` populates before `open()`. Un-disable the top-bar
  CodexButton (`hex_editor.tscn`, `disabled = true`) when this
  lands — the button + signal wiring are already in place.
- [ ] Add the unlocked chapter intros as a section to the codex.
  Plan: `TemplateManager.get_all_chapters()` filtered by
  `SaveManager.get_seen_chapter_intros()`; re-use the chapter
  intro dialog's carousel/`BlueprintMiniCanvas` rendering for
  the detail view.
- [ ] Chapter dialogue should focus on explaining how to use the hexes
  and a surface level approach of how they work. Computer theory and more
  thorough explanations of each computer science and functional concept
  left to the codex sections on hexes and concept. (The post-split
  chapter descriptions are already how-to-first; the theory copy
  for the codex still needs authoring.)

#### Tutorial focus system

Landed as the chapter-0 tutorial FSM: `TutorialManager` autoload
(`src/singletons/tutorial_manager.gd`) drives a 13-step declarative
machine — every editor progress signal funnels into one `_on_event`
entry point and only the current step's expected event advances it.
HUD strip + pulsing control highlighter + world-space tile/edge
markers live in `scenes/gui/tutorial/`; hard gating at five choke
points (category select, hex pick, placement, job select, run) keeps
the player on script. Completion persists via
`SaveManager.has_completed_tutorial`; "Replay tutorial" in settings
re-arms it.

- [x] Implement a system to highlight buttons and a tutorial script to
  scaffold interacting with the UI in the first chapter of "placing a
  hex" (camera steps added in front: WASD, then mouse pan/zoom; the
  congratulations popup rides a timer and yields to the chapter-1
  intro modal)
- [x] Progressive hex scaffolding: the starter unlock set shrinks to
  the Int literal; arithmetic + identifiers unlock via job_01,
  booleans + comparisons via job_02, `let` via job_04. Palette
  categories with no unlocked hexes hide their button entirely.
- [ ] Tutorial UX polish pass once playtested: cursor-side RMB hint
  icon, output-panel highlight on the final step, animated camera
  focus toward the target tile.

#### Authoring polish

- [ ] Dedicated "Copy solution to clipboard" button on each completed
  job card
- [ ] Expand text-emission tests with `\x -> x * 2`, `factorial`,
  `map`, `zip`, cons-match
- [ ] Full text → AST → hex graph → text round-trip (needs a
  text-to-graph builder)

### v3 — Deferred (waits on design)

#### User profiles / multiple save files

- [ ] `UserManager` singleton + a deferred `user` setting selecting
  among multiple save files (slots). Groundwork already landed: the
  blueprint library lives in its own per-install file
  (`user://blueprint_library.json`) that survives save deletion, and
  `has_completed_tutorial` travels inside each save's `story` section
  — both were designed to survive the per-user split. Remaining
  design: slot-selection UI in the main menu, per-slot
  `story_progress_<slot>.json` naming, and which preferences stay
  global vs per-user.

Sits behind the emission registry (an EmissionRegistry per level
tracking which identifiers are emitted into the level and from
where). Not blocking gameplay but unlocks several polish items.

- [ ] Emission registry per level
- [ ] Scope sidebar listing in-scope identifiers per level
- [ ] Scope filtering on inscription `OptionButton`s (only show
  in-scope identifiers)
- [ ] Visual distinction for inscriptions by home level (faded for
  outer-scope, bright for this-level)
- [ ] Eta-abstraction in `to_source` for unwired binary-op inputs
  (needs parser support for sections)
- [ ] Grammar-compatibility check on wire endpoints (expr-typed slots
  reject patterns, etc.)

### v3 — UI layout

```
┌──────────────────────────┬──────────────────────────────────────────────┬─────────────────────────┐
│ Menu | ? | Jobs | Codex  │ Tabs ❶ ❷ ❸ │ Breadcrumb │                    │ Gen | Run ● │ Blueprint |
| Completed jobs           | Job name                                     |                         |
| Renown progress bar      |     description                              |                         |
└──────────────────────────┴──────────────────────────────────────────────┴─────────────────────────┘
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ┌──────────────────────┐    Current Tab's Hex Canvas                                              │
│ │ (Jobs Panel)         │    (Background Layer)                                                    │
│ │                      │                                                                          │
│ │ Pending              │                                                                          │
│ │   Job A              │                                                                          │
│ │   Job B              │                                                                          │
│ │   ...                │                                                                          │
│ └──────────────────────┘                                                                          │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
│                                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Output Panel: Generated text + run output + error messages                                        │
├───────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Hex Row (filtered by SaveManager.unlocked_hex_scripts)  │ Category Tabs (⇧1 .. ⇧5)               │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

#### UI Layout Specification (Machine-Friendly)

**Coordinate System**: Top-left origin, y+ downward, x+ rightward. All anchors specified as 
`anchor_left`, `anchor_top`, `anchor_right`, `anchor_bottom` (0.0 = left/top, 1.0 = right/bottom).

##### TopBar (Full-Width Chrome)

- **Anchors**: `(0, 0, 1, 0)` — spans full viewport width, fixed height
- **Height**: ~12.5% (contains text + padding)
- **Layout**: HBoxContainer, left-to-right flow
- **Sections**:
  - **CornerPanel-Left** (left-anchored, fixed width ~180px)
    - Menu Button (Menu hamburger icon)
    - Help Button (`?` icon — Keybinds overlay)
    - Jobs Button (checklist icon)
    - Codex Button (Book icon, placeholder for chapter intros / concepts library)
    - Completed Jobs count label (e.g. `● 3 complete`)
    - Renown progress bar (visual + numeric label, e.g. `Renown: 42`)
  - **CenterBar** (grows horizontally)
    - TabStrip (list of workspace tabs, each clickable/draggable)
    - Breadcrumb (level navigation, e.g. `Main > Fn1 > Body`)
    - Job name label (synced to selected job in Jobs Panel)
    - Job description label (rich text, truncated for space)
  - **CornerPanel-Right** (right-anchored, fixed width ~180px)
    - Run button (`●` + status indicator)
    - Blueprint button (library / capture UI)
    - Generate button (emit program text)

**Interaction**: 
- TabStrip tabs emit `tab_switched(tab_id)` signal
- Breadcrumb emits `level_jumped(new_depth)`
- Menu/Help/Export buttons emit standard pressed signals
- Completed Jobs Button opens the modal panel with the list of completed jobs, each
  with a button to cope the solution, either as a string to clipboard for sharing
  or for using as a blueprint
- Codex button opens the encyclopedia
- Job name/description sync to `jobs_panel.selected_job_changed` signal

##### MiddlePanel (Split Layout)

- **Anchors**: `(0, 1, 1, 1)` in relation to TopBar; grows vertically to PaletteBar
- **Layout**: HSplitContainer (resizable divider at user preference)
- **Left Column: JobsPanel**
  - **Width**: ~16.67%
  - **Length**: Dynamic depending on the number of job items, no longer than
    the middle panel
  - **Content**:
    - Pending jobs (renown met, unsolved): clickable job cards
    - Each card shows: job name, status indicator
  - **Signals**: `job_selected(job_id)`, `job_deselected(job_id)`

- **Right Column: HexCanvas**
  - **Width**: remaining viewport width
  - **Content**: 
    - Node2D (World) with pan/zoom controlled by mouse
    - GridRenderer (background hex tiles, read-only visual aid)
      - To be replaced by a TileMap with appropriate settings for easier texture
        use
    - Connections layer (Line2D wires)
    - Nodes layer (HexNode instances, user-placed hexes)
    - Blueprint previews (translucent hex + wires, placement mode)
    - Marquee selection (blue box, Shift+LMB drag)
  - **Input Handling**: Mouse events route to Area2D children (slots, hex bodies); 
    unhandled events fall through to _unhandled_input for pan/zoom/hotkeys
  - **State**: Syncs to `_level_stack[_active_tab_idx]` for pan/zoom/content

**JobsPanel Behavior**:
  - Floats on top of the HexCanvas, visually the panel is on a higher z-index and the
    HexCanvas occupies the entire MiddlePanel

##### PaletteBar (Full-Width Chrome)

- **Anchors**: `(0, 1, 1, 1)` — bottom of viewport, full width
- **Height**: ~12.5% (hex row + category tabs + padding)
- **Layout**: VBoxContainer
- **Sections**:
  - **OutputPanel** (upper half, ~60px)
    - RichTextLabel for generated text, run output, error messages
    - Scrollable; auto-scroll-to-bottom on new output
    - Background: dark (contrast with light text)
  - **Divider**: HSeparator
  - **HexRow + CategoryTabs** (lower half, ~60px)
    - HBoxContainer: HexRow (left) + CategoryTabs (right)
    - **HexRow**: Horizontal scrolling row of locked/unlocked hex buttons
      - Filtered by `SaveManager.unlocked_hex_scripts`
      - Drag-enabled; initiates blueprint placement on release
      - Locked hexes appear grayed out (unclickable, show unlock requirement tooltip)
    - **CategoryTabs**: 5 buttons (⇧1 .. ⇧5) to filter HexRow by category
      - Categories: Literals, Operators, Logic, Structure, Advanced

**Interaction**:
- CategoryTabs filter HexRow contents (user pref persisted)
- OutputPanel output appended via `_append_output(text)` method

##### Z-Order & Overflow Handling

1. **CornerPanel-Right** (z-index +10): Wins over TabStrip when they overlap on narrow viewports
2. **JobsPanel** (z-index 0): Normal stacking
3. **HexCanvas** (z-index 0): Normal stacking (receives mouse events, manages internal layers)
4. **PaletteBar** (z-index +5): Floats above canvas, scroll events pass through
5. **Overlays** (z-index +100): Chapter intro dialog, menus, modals

**Responsive Breakpoints**:
- **Wide** (≥ 1080px): Full layout as specified
- **Medium** (1000–1079px): JobsPanel fixed at 200px, HexCanvas shrinks proportionally
- **Narrow** (< 1000px):
  - JobsPanel collapses to toggle-button (left edge) or slides under HexCanvas
  - CornerPanel-Left items stack vertically (Menu/Help, then Renown, then Completed)
  - TabStrip + Breadcrumb compress or wrap

---

- [X] Implement TopBar (CornerPanel-Left + CenterBar + CornerPanel-Right)
- [X] Implement MiddlePanel (HSplitContainer with JobsPanel + HexCanvas)
- [X] Implement PaletteBar (HexRow + CategoryTabs)
- [ ] Wire TopBar signals to canvas + panels
- [ ] Add responsive layout logic for narrow viewports
- [ ] Test z-order stacking with overlays

### v3 — Cosmetic / nice-to-have

- [X] Animated Q / E level transitions (~200ms zoom + fade)
- [ ] Visual alerts on malformed hexes (red outline / `!` icon)
- [X] Shader on wires to show a directional pulse in the direction
  from output towards input to mimic data flowing from producers
  to consumers — `assets/shaders/wire_flow.gdshader` bound per
  wire by `HexWire.attach_shader_to(line)`; `HexWire.paint()`
  pushes `pulse_enabled` + `flow_forward` uniforms each frame.
- [X] Right-click delete placed hexes as unhandled input fallback —
  RMB on a hex body delegates to the contextual-cancel chain first
  (clear selection / cancel wire / close sidebar) and only deletes
  the hex when none of those apply. RMB is also bound to the
  canonical `hex_delete` action alongside `X`.
- [ ] Slot-hover `Area2D` tooltip with logical role (current config
  sidebar's Slots section covers it post-click)
- [ ] Visual linking: selecting one Definition highlights its
  same-identifier siblings
- [ ] Spatial-ordering badge updating live as user drags Definitions
  around
- [ ] Optional guard predicate slot per Definition equation
- [ ] Arity consistency check across same-identifier Definitions
- [ ] Collapse / show toggles for the side panels
- [ ] Layer or "pancake" style breadcrumb in the bottom left corner of the
  canvas
- [ ] Tree-breadcrumb minimap: a compact panel visualising the *tree* of
  nested scopes in the current program (not the linear breadcrumb) so the
  player sees sibling branches and their current scope/position. Walk the
  level tree (`HexLevel.parent_hex` / `HexNode.inner_level`); highlight the
  top of `_level_stack`; click a node to navigate (reuse `_jump_to_level`
  for on-path ancestors). Refresh on the `_update_breadcrumb` hooks. Design
  draft only so far — start collapsed / toggleable to avoid clutter.
- [ ] Utilize proper assets to improve visuals

### v3 — Audio (planned)

Two new autoload singletons (alongside `ChapterManager` / `TutorialManager`
in `src/singletons/`, registered under `[autoload]` in `project.godot`).
Greenfield — no audio code or assets exist yet.

Shared idea: a centralised decoupling layer between call sites and audio
resources. Each manager owns a `Dictionary` of `{ key: AudioStream }`, so
emitters never name an asset — they emit a signal and the manager looks the
sound up by key. One **parameter-less** play function per sound/action, so
hooking one up is a plain `signal → method` connect with no payload.

- [X] **SFXManager** — sound effects for player + UI actions (wire connect,
  hex place / delete, button press, run / submit verdict, error, tab switch,
  level descend / ascend, …). Holds `{ key: AudioStream }`; one no-arg
  `play_*()` per action playing its mapped stream on a pooled
  `AudioStreamPlayer` so overlapping effects don't cut each other off.
- [X] **BGMManager** — background music. Holds `{ key: AudioStream }`
  (per-screen / per-mood tracks); one no-arg `play_*()` per track that swaps
  the looping music (short cross-fade), plus `stop()`. Single
  `AudioStreamPlayer` — only one track at a time.
- [ ] Emitters connect signals to the managers' play methods (e.g.
  `hex_editor.wire_committed → SFXManager.play_wire_connect`), so gameplay /
  UI code stays unaware of the audio assets.
- [X] Register both under `[autoload]`
  (`SFXManager` / `BGMManager` → `res://src/singletons/{sfx,bgm}_manager.gd`).
- [ ] Dedicated `SFX` / `Music` audio buses so the settings menu's
  accessibility volume / mute controls can target each independently.
- [X] Placeholder (or silent-stub) `AudioStream` assets so the dictionaries
  resolve before final sound design lands.

### v3 — Settings panel rework (planned)

The settings menu (`scenes/gui/settings_menu/`) already holds custom
templates / exercises, delete save / blueprints, replay tutorial, and the
archmage toggle, and more is queued (keybind UI, colorblind modes, category
colors — see "Settings & accessibility" above; audio below). The single flat
column is getting crowded.

- [ ] **Audio volume controls** — SFX + BGM volume sliders (plus mute
  toggles) wired to the `SFX` / `Music` audio buses the audio managers
  introduce; persist levels via `SaveManager`. Sliders map 0–100 % onto the
  bus `volume_db` (sensible curve, silent at 0).
- [ ] **Bigger footprint + grouping** — the panel needs more room. Rework the
  layout into grouped sections (tabs, or a scrollable category list: Audio /
  Accessibility / Data / Advanced) so new controls land in a category instead
  of lengthening one column. Keep both presentations working — main-menu
  full-screen and pause-menu modal/blurred via `set_modal(blur)`.

### v3 — Better error stack trace

- [ ] Replace returning null when errors occur with new dedicated RuntimeError class
- [ ] Add support for tracking the line that caused the error
- [ ] Add unit tests for new RuntimeError class

### v3 — Closing refactors

- [X] Evaluate if keeping text editor as advanced mode or deprecate
- [ ] If keeping as feature:
  - [ ] Refactor the old text editor to use jobs instead of exercises
  - [ ] Refactor templates to use the blueprint encoding system as a third type
  - [ ] Remove the chapter system from the text editor given that the player
    is intentionally using the advanced mode
- [ ] If deprecating:
  - [ ] Remove from project

### v3 — Done summary

Prototype phases 1–18 (hex types, wiring, placement, rotation, undo,
level navigation, config sidebar, generation pipeline, text-emission
tests) are complete. Gameplay-loop phases 19.1–19.7 + 19.10 are
complete: tabs, jobs panel, completed-jobs archive, blueprints
library (capture / stamp / library modal / Ctrl+S/C/V clipboard /
rotation / preview wires), progression-locked palette, parameter
injection at level 0, main-menu routing, Quick REPL.

### v3 — Out of scope (explicitly)

- Magic-circle aesthetic skin (later visual reskin layer)
- Static type checking (sits at the v2 language level)
- List comprehensions (Haskell-specific sugar)
- Filter hexes (absorbed into Definition's guard slot)
- Wire splitters (pattern destructuring via emission instead)
- Literal inscription on hex sides (literals are dedicated nodes)
- Drag-and-drop placement of hexes (replaced by blueprint placement)
- Free dragging of placed hexes (movement is `X` delete-and-replace
  or `C` pickup)
- Multiplayer / collaborative editing
- User-defined templates (superseded by blueprints)
