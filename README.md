# ⬡ Hexkell

A Godot 4 project that pairs a small ML-family functional language
(lazy evaluation, pattern matching, first-class functions, list /
tuple / range literals) with a visual hex-grid editor that compiles
to that language's text form. Players solve programming "jobs" by
building hex graphs.

## Repository layout

```
src/
  classes/
    parser/        # lexer + parser → AST (Ctrl.Program, Expr.*, Pattern.*)
    interpreter/   # Env, Value, Expr, Ctrl, Pattern, prelude (std lib)
    hex_nodes/     # one .gd + .tscn pair per hex type, grouped by
                   #   fixtures/ literals/ operators/ control/
                   #   (Int, AddHex, …, LambdaHex, MatchHex, anchors, …)
    checker.gd    # exercise / job validator: parse + structure checks +
                  #   env var injection + per-test run + result diff
  singletons/      # autoloads: StaticData, SceneManager, TemplateManager,
                   #   SaveManager (chapters, exercises, renown, unlocks)
  statics/         # class_name utilities: HexMath, BlueprintCodec,
                   #   BlueprintLoader, HexPalette, HexTextFormatter, …
scenes/
  gui/
    editor/        # legacy text-based code editor (CodeEdit) —
                   #   "Classic Editor" from the main menu
    hex_editor/    # visual hex-grid editor — the main gameplay loop
      hex_editor.gd / .tscn   # editor scene (Phase 19: tabs + jobs panel)
      hex_level.gd            # one canvas per level (push/pop on Q/E)
      workspace_tab.gd        # per-tab state container (level stack,
                              #   undo/redo, DoHex fixture)
      hex_wire.gd             # belt-style polyline with anchored cells
      hex_camera_controller.gd # camera pan / zoom
      hex_toolbar_button.gd   # custom toolbar button: centered label +
                              #   slot-number badge + CK3-style tooltip
      identifier_palette.gd   # RGB-CMY (+ reserved white/black) signal
                              #   colors, glyphs, and emojis
      ui/          # script-only panel components: palette_bar, jobs_panel,
                   #   output_panel, config_sidebar, breadcrumb, top_buttons,
                   #   job_header
      dialogs/     # blueprint_library_dialog (+ blueprint_row),
                   #   codex_dialog, keybindings_dialog
    common/        # shared dialogs: chapter_intro_dialog, quick_repl_dialog,
                   #   template_accept_dialog, template_hint_toast,
                   #   pause_menu, blueprint_mini_canvas (read-only
                   #   SubViewport blueprint preview)
    main_menu/ settings_menu/  # other scenes
data/
  static_data.json           # ships chapters / exercises / templates /
                             #   examples; gets merged with user uploads
test/unit/
  lexer/ parser/ interpreter/  # language tests (Gut)
  hex_editor/                  # hex editor round-trip tests (MockCanvas)
docs/
  HEX_DESIGN.md           # v3 hex design — what each hex is and means
  BLUEPRINT_FORMAT.md     # blueprint serializer + wire format
  LANG.md                 # language design notes (EBNF, semantics)
  TODO.md                 # unified v1 / v2 / v3 TODO list
  TREE.md                 # auto-generated project tree
addons/gut/                # Gut testing framework
.claude/                   # claude code on the web setup-hook + settings
```

`~/bin/godot` is installed by `.claude/hooks/session-start.sh` on
every fresh container.

---

## Running and testing

Inside this repo, with Godot 4.6 available on `PATH`:

```bash
# Import assets (one-time per fresh container)
godot --headless --import

# Boot a scene (Ctrl+C to quit)
godot --headless res://scenes/gui/hex_editor/hex_editor.tscn
godot --headless res://scenes/gui/editor/editor.tscn

# Run the full test suite
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Use `just tree` to regenerate `docs/TREE.md`.

---

## The hex editor at a glance

Open `scenes/gui/hex_editor/hex_editor.tscn`.

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

### Key bindings

| Group | Bindings |
|---|---|
| Palette | `Shift+1..5` select category; `1..9, 0` pick the Nth hex; `Tab` cycles within a category |
| Canvas | `WASD` or middle-drag = pan; wheel = zoom; `Q` / `E` descend / ascend levels |
| Hex | `R` / `Shift+R` rotate (cw / ccw); `C` clone the hex under cursor / anchor a wire mid-drag; `X` delete under cursor |
| Wire | Drag from slot; release on slot / hex body / empty cell / open-wire tail. Adjacent hexes with matching slot directions auto-connect with no wire. |
| Modes | Right-click = blueprint cancel → wire cancel → close panel → delete (priority chain) |
| Undo | `Ctrl+Z` / `Ctrl+Y` for place/delete hex, place/delete wire, rotate |
| Help | `?` opens the keymap overlay |

### What the editor produces

- Per-tab program text via `_build_program_text()` — definitions, a
  `do` separator, then the Do hex's main expression.
- Display variant via `_display_text(code)`: strips redundant parens
  (single-atom wraps + double-paren collapse, iterated to fixpoint)
  and substitutes palette identifiers with their color emojis
  (🟥 🟩 🟦 💠 🟪 🟨 ⬜ ⬛). The parser receives the plain text.
- Soft enforcement: per-hex `validate(canvas) → {status, message}`;
  the `Run` button lists every malformed hex in the output panel
  before refusing to evaluate.

### Hex types currently in the palette

| Category | Hexes |
|---|---|
| Integer | `Int`, `+`, `−`, `*`, `/`, `%`, unary `neg` |
| Boolean | `true`, `false`, `&&`, `‖`, `!`, `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Functions | `λ` (arity 1–5), `if`, `match` (arity 1–5), `apply`, `compose` |
| Structures | `tuple` (2–5), `list` (any length), `range`, `:`, `++` |
| Naming | `id` (`IdentRef`), `let`, `let rec`, `def` (arity 1–5) |

The `Do` hex sits at level-0 (0,0) as a fixture — six slot dots, one
logical input. `Anchor`, `MatchAnchor`, `IfAnchor`, `TupleAnchor`, and
`ListAnchor` are fixtures at (0,0) of non-level-0 levels.

### Identifier palette (`IdentifierPalette.gd`)

8 entries; `user_count() = 6` hides the last two from sidebar
pickers:

| Index | Name | Glyph | Color | Emoji | Notes |
|---|---|---|---|---|---|
| 0 | red | ● | red | 🟥 | user-pickable |
| 1 | green | ◆ | green | 🟩 | user-pickable |
| 2 | blue | ★ | blue | 🟦 | user-pickable |
| 3 | cyan | ◉ | cyan | 💠 | user-pickable |
| 4 | magenta | ♥ | magenta | 🟪 | user-pickable |
| 5 | yellow | ▲ | yellow | 🟨 | user-pickable |
| 6 | white | □ | white | ⬜ | **reserved** — checker injection only |
| 7 | black | ■ | black | ⬛ | **reserved** — checker injection only |

---

## Architecture deep-dive

### Levels (`hex_level.gd`)

A `HexLevel` owns its hexes, wires, anchor, parent_hex, and per-level
pan/zoom. The editor keeps a stack — index 0 is the program's main
canvas, top of stack is what renders. Descending (`Q` over a hex
with an inner level) lazily creates the inner level + anchor;
ascending (`E`) pops. Switching levels hides the old level's hexes
+ wires (visible = false + set_pickable(false)) and shows the new
level's.

The breadcrumb at the top is an `HBoxContainer` of flat buttons;
clicking a segment pops the stack back to that level.

### Wires (`hex_wire.gd`)

Each wire is a sequence of axial cells. Each cell has an enter edge
and an exit edge (or −1 to dangle). The polyline pivots through
each cell's center, Factorio-belt style. Wires can be:
- **Finalized** with both endpoints bound.
- **Open** with one endpoint bound (the player can stamp these as
  cable-management placeholders).
- **Stuck** — when greedy routing can't reach the target, the last
  cell renders red on a second Line2D overlay.

Routing is greedy with cube-distance heuristic, recompute-from-anchor
on `C` mid-drag, re-route on hex rotation.

### Hex types (`src/classes/hex_nodes/`)

`HexNode` is the base. Each subclass sets in `_init`:
- `input_edges` / `output_edges` — logical edges (rotation-invariant).
- `input_role_names` / `output_role_names` — `{logical: "role"}` for
  the rotation-aware Slots section in the sidebar.
- `optional_input_edges` — slots whose absence isn't a validation
  error (Lambda's args, Range's end, List's slots, DoHex's spares).

Subclasses override `to_source(canvas)`, `get_config_title()`,
`build_config_ui()`, optionally `validate(canvas)`, `_copy_state_to`
(for the `C` clone), and (for inner-level hexes) `has_inner_level`,
`level_label`, `create_inner_anchor`.

Two structural signals on `HexNode`:
- `inner_level_invalidated(node)` — `MatchHex` / `LambdaHex` /
  `DefinitionHex` arity change. Editor purges the inner level and
  clears undo/redo (parked refs would be stale).
- `structure_invalidated(node)` — outer-face slot layout changes
  (`Lambda` / `Tuple` / `List` arity). Editor disposes wires
  touching the hex, calls `rebuild_slots()`, clears undo/redo, and
  reopens the sidebar.

### Checker pipeline (`src/classes/checker.gd`)

`Checker.check_answer(exercise, code_text) → {correct, results, message}`:
1. Parse `code_text` → `Array[Expr]`.
2. Validate forbidden / required AST structures.
3. Build `Env` with injected `variables` (`white` / `black` slots).
4. Interpret each test case (with arg currying if `input` is an
   array), compare to `expected` (+ optional `expected_type`).

The hex editor's `_build_program_text()` produces plain text the
Checker can consume — no parser-side changes needed for migration.

### SaveManager (`src/singletons/save_manager.gd`)

Tracks: renown, completed exercises, unlocked templates, seen
chapter intros. Phase 19 adds a `hex` section with
`unlocked_hex_scripts`, `tabs`, `current_tab_id`, `blueprints`, and
`solved_jobs`. Tab contents themselves (hex graphs + wires) are not
yet round-tripped — Phase 19.8 open item.

---

## Roadmap — see `docs/TODO.md` for the full state

### Prototype phases 1–18: complete

Foundation (levels, anchor, hex base, placement, wires, palette),
the hex types themselves, validation, text emission, and UI polish
all landed. The TODO calls out what's checked vs deferred for each
phase with brief reasons. Unchecked items are either cosmetic
polish (animation, glow alerts, area-select, right-click menu) or
wait on the emission registry (scope sidebar, scope-filtered
inscription pickers, eta-abstraction). **None of those block the
gameplay-loop migration.**

### Phase 19: gameplay-loop migration (the actual remaining work)

The gameplay loop is being **re-designed** rather than ported. The
new model:

- **Tabs replace per-exercise files.** ~6 persistent workspace
  tabs that the player builds programs in freely.
- **Jobs replace exercises.** A jobs panel lists pending jobs; the
  player picks one and submits the *currently open tab's program*
  against it. Solving a job moves it to the completed-jobs archive
  with the submitted program text preserved + copy-to-clipboard.
- **Blueprints replace templates.** User-captured snippets stamped
  from a library, Shapez 2 / Factorio style.
- **Progression gates hex types, not snippets.** Renown unlocks
  new hex types in the palette; locked entries hidden / grayed out.

The Checker / SaveManager / TemplateManager singletons stay — only
the data they consume gets renamed and re-shaped, and the hex
editor calls them through new entry points.

Sub-phases 19.1 through 19.10 in the TODO cover: tabbed editor,
jobs panel + submit, completed-jobs archive, blueprints library,
progression-locked palette, parameter injection via white/black,
the new UI structure, the JSON save format, chapter intros +
encyclopedia, and main-menu wiring + Quick REPL.

**Suggested implementation order**:
1. Tabbed editor (everything else depends on multiple workspaces).
2. Jobs panel + submit + Checker integration (proves the model
   end-to-end).
3. Completed-jobs archive + SaveManager extensions.
4. Progression-locked palette.
5. Blueprints library (capture-current-tab first; drag-rect later).
6. JSON save format.
7. Chapter intros + encyclopedia + main-menu switch + Quick REPL.

---

## Handoff context for a new agent

If you're picking this up cold:

1. **Read `docs/HEX_DESIGN.md`** first — the visual language semantics
   (wires vs emissions, levels = scopes, anchors, the inscription
   model). One page.
2. **Read `docs/TODO.md`** — every section has accurate
   status + brief notes on deferred items. Phase 19 is the only
   open phase by area, but it's a big one.
3. **Open `scenes/gui/hex_editor/hex_editor.tscn`** in the Godot
   editor (or run it headless) and play with it for ten minutes —
   place hexes, descend into a Let body, rotate things, submit a
   factorial. The keymap overlay (`?`) is your friend.
4. The editor is **one big script** at
   `scenes/gui/hex_editor/hex_editor.gd` (~1850 lines, sectioned
   by `# ── …` headers). Per-hex behavior lives in
   `src/classes/hex_nodes/` — one short file per hex type.
5. The text-based `Editor` (`scenes/gui/editor/editor.gd`) is the
   reference for what Phase 19 needs to surface — exercise pane,
   per-test result rendering, chapter intros, encyclopedia, quick
   REPL, save / renown plumbing.

Whatever the next iteration is, start by **reading the relevant
section of `docs/TODO.md`** — every unchecked box carries a note
explaining its current state and what unblocks it.

---

## Legacy: authoring exercises for the text editor

Until Phase 19 lands, the shipping gameplay loop is the text editor
(`scenes/gui/editor/`). Its exercise / chapter / template / example
schema is described below — the same data file (`data/static_data.json`)
will be repurposed for the new jobs model in Phase 19, with
`unlocks_templates` becoming `unlocks_hexes` and `exercises`
becoming `jobs`.

### Exercises

Exercises live in JSON. The shipped content is in `data/static_data.json`;
players can also upload their own JSON files via the editor, which are stored
under `user://uploaded_exercises/` and merged on top of the defaults by
`TemplateManager` (see `src/singletons/template_manager.gd`).

A complete custom file may contain four top-level dictionaries — `chapters`,
`exercises`, `templates`, and `examples`. Only the sections you provide are
merged; existing entries with the same key are overwritten.

```jsonc
{
  "chapters":  { "...": "..." },
  "exercises": { "...": "..." },
  "templates": { "...": "..." },
  "examples":  { "...": "..." }
}
```

Each entry under `exercises` is keyed by a stable exercise id (e.g.
`"exercise_1"`). Buttons in the sidebar are sorted alphabetically by id, so
prefer zero-padded or otherwise sortable ids if order matters.

```jsonc
"exercise_4": {
  "name": "Sum of List",
  "description": "Return the sum of a list of integers.",
  "renown_required": 30,
  "renown_reward": 25,
  "template_hints": ["let_rec", "match", "case"],
  "tests": [
    { "input": [[1, 2, 3, 4]], "expected": 10 },
    { "input": [[]],           "expected": 0 },
    { "input": [[5, 5, 5]],    "expected": 15 }
  ],

  // Optional advanced fields:
  "variables": {
    "my_constant": 42
  },
  "required_structures":  ["lambda"],
  "forbidden_structures": ["if"]
}
```

Field reference:

| Field                  | Type            | Required | Description                                                                                                                                                            |
| ---------------------- | --------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`                 | string          | yes      | Label shown on the exercise button and in popups.                                                                                                                      |
| `description`          | string          | yes      | Inserted as a `--` comment header in the editor when the exercise is selected.                                                                                         |
| `renown_required`      | int             | yes      | The button stays hidden until the player has at least this much renown.                                                                                                |
| `renown_reward`        | int             | yes      | Renown granted on first successful solve. Subsequent solves of the same exercise award nothing.                                                                        |
| `tests`                | array           | yes      | Test cases. See below.                                                                                                                                                 |
| `template_hints`       | array of string | no       | Template names (matching keys in `templates`) reminded via a non-focus toast in the top-right when the exercise is selected. Only templates the player has actually unlocked are shown; the toast auto-hides and never grabs keyboard focus. Omit the field (or leave it empty) for exercises that need no nudge. |
| `starter_code`         | string          | no       | Appended after the description header in the editor when the exercise is selected. Useful for exercises like "uncomment the line" where the player should start from a specific snippet.                                                                                                                       |
| `variables`            | object          | no       | Extra bindings injected into the answer's environment. Values are wrapped automatically.                                                                               |
| `required_structures`  | array of string | no       | If set, the answer must contain at least one of each named AST structure. Valid names: `lambda`, `application`, `let`, `letrec`, `if`, `match`, `list`, `range`, `tuple`, `int`, `bool`, `variable`, `native_call`. |
| `forbidden_structures` | array of string | no       | Same vocabulary as `required_structures`; the answer fails if any of these appear.                                                                                     |

#### Test cases

Each entry in `tests` is an object with `input` and `expected`. The checker
(`src/classes/checker.gd`) wraps these values into interpreter `Value`s and
runs them against the player's code.

```jsonc
{ "input": 5,           "expected": 10 }            // single argument
{ "input": [2, 3],      "expected": 5 }             // two arguments (array = arg list)
{ "input": [[1, 2, 3]], "expected": 6 }             // one list argument
{ "expected": 42 }                                  // no arguments; answer is a value, not a function
{ "input": 4, "expected": 16, "expected_type": 0 }  // optional Value.Type enum check (0 = INT)
{ "expected_type": 3 }                              // "any list" — value match is skipped
```

Rules:

- If the test has an `input` (or the legacy alias `args`), the player's code
  must evaluate to a function; the inputs are applied to it.
- A bare scalar/`int`/`bool` is passed as a single argument.
- An `Array` is treated as the **argument list**, so `[1, 2]` means two
  arguments. To pass a single list argument, wrap it: `[[1, 2]]`.
- Omit `input` to evaluate the player's code as a plain expression and compare
  the result directly to `expected`.
- Supported value types in `input`/`expected`: `int`, `bool`, `Array` (nested
  for lists of lists), or `null` (treated as the empty list).
- `expected` is optional. When omitted, the value comparison is skipped, so a
  test with only `expected_type` accepts any value of that kind — useful for
  "return any number / any tuple / any list" exercises.
- `expected_type` is the integer value of `Value.Type` (`0 = INT`, `1 = BOOL`,
  `2 = TUPLE`, `3 = LIST`, `4 = CLOSURE`, `5 = THUNK`).

### Chapters

`chapters` groups exercises into pedagogical units. The chapter is **only**
surfaced once — as a modal that appears the first time the player selects an
exercise belonging to that chapter. Dismissing the modal unlocks any
`unlocks_templates` listed for that chapter.

```jsonc
"chapter_1": {
  "name": "Chapter 1 — Lambdas & Application",
  "description": "Welcome to Hexkell! ...",
  "example_code": "let inc = \\x -> x + 1\nin inc 41",
  "unlocks_templates": ["lambda"],
  "exercises": ["exercise_1", "exercise_2"]
}
```

| Field               | Type            | Required | Description                                                                                                |
| ------------------- | --------------- | -------- | ---------------------------------------------------------------------------------------------------------- |
| `name`              | string          | yes      | Modal title and chapter heading.                                                                           |
| `description`       | string          | yes      | Body text shown in the modal (RichTextLabel; BBCode is enabled).                                           |
| `example_code`      | string          | yes      | Non-interactive code sample displayed in a syntax-highlighted, read-only editor area.                      |
| `unlocks_templates` | array of string | no       | Template ids (keys of `templates`) granted to the player when the intro is dismissed.                      |
| `exercises`         | array of string | yes      | Ordered list of exercise ids that belong to this chapter. Used only to map exercises back to the chapter.  |

If an exercise id appears in no chapter, no intro modal will trigger; the
exercise still works.

### Templates and examples

```jsonc
"templates": {
  "lambda": "\\{- params -} -> {- body -}",
  "let":    "let {- name -} = {- value -} in {- body -}"
},
"examples": {
  "Factorial": "let factorial x = ..."
}
```

- `templates` are short snippets inserted at the cursor. The `{- name -}`
  markers become placeholders the player can Tab/Shift-Tab through after
  inserting. Default templates ship locked and become available only as
  chapters unlock them; user-saved templates (created via the in-editor
  "Save" button) are always available.
- `examples` are full code samples loaded into the editor from the menu.
