# Static data format

`data/static_data.json` is the bundled, read-only content for the game's
**modern hex flow** (story chapters and jobs). It is loaded once at boot by the
`StaticData` autoload (`src/singletons/static_data.gd`) and surfaced to gameplay
through `TemplateManager` (`src/singletons/template_manager.gd`) and
`ChapterManager` (`src/singletons/chapter_manager.gd`).

The file is a single JSON object with three top-level keys:

| Key        | Type                | Used by                                            |
|------------|---------------------|----------------------------------------------------|
| `chapters` | `{ id → Chapter }`  | `ChapterManager`, hex editor, chapter intro dialog |
| `jobs`     | `{ id → Job }`      | `ChapterManager`, jobs panel, `Checker`            |
| `examples` | `{ name → String }` | reserved (sample source programs)                  |

> **History.** The pre-hex era also kept `templates` (code-snippet strings) and
> `exercises` (text-coding challenges) here. They are deprecated — superseded by
> blueprints and jobs respectively — and now live in
> `data/legacy_playground.json` (see [Legacy data](#legacy-data)).

---

## `chapters`

A map of `chapter_id → Chapter`. Chapters gate progression and drive the
chapter-intro carousel. Iteration order is the insertion order in the file.

```jsonc
"chapter_1_integer_operators": {
  "name": "Chapter 1 — Integer Operators",
  "description": "Operator [img …]…",   // BBCode (RichTextLabel); supports [b], [img], [color]
  "examples": [                          // carousel slides shown in the intro dialog
    {
      "name": "Binary ops",
      "blueprint": "hxk1:H4sIA…",        // blueprint string (see docs/BLUEPRINT_FORMAT.md)
      "screenshot": "res://assets/screenshots/chapters/tutorial_binary_ops.png",
      "caption": "Two [b]Int[/b] hexes feeding a [b]+[/b]…"   // BBCode
    }
  ],
  "jobs": ["job_02_add_crates"],         // job ids belonging to this chapter
  "unlocks_templates": [],               // pattern names unlocked when the intro closes
  "exercises": []                        // LEGACY — playground-only (see below)
}
```

| Field               | Type             | Required | Notes |
|---------------------|------------------|----------|-------|
| `name`              | String           | yes      | Display title. |
| `description`       | String (BBCode)  | yes      | Rendered in the intro dialog. |
| `examples`          | `[ExampleSlide]` | no       | Carousel slides; each is `{name, blueprint?, screenshot?, caption?}`. A slide may be screenshot-only. |
| `jobs`              | `[String]`       | no       | Job ids in this chapter; a chapter with no jobs is a pure-reference chapter. |
| `unlocks_templates` | `[String]`       | no       | Pattern names passed to `SaveManager.unlock_pattern` when the chapter intro closes (`ChapterManager.notify_intro_closed`). |
| `exercises`         | `[String]`       | no       | **Legacy.** Exercise ids (resolved against `legacy_playground.json`); only the Playground reads these. |

A chapter is considered *unlocked* once any of its jobs is reachable
(`ChapterManager.chapter_is_unlocked`).

### Icons in BBCode

`description` / `caption` BBCode may embed `[img]` icons. Size them in **em**
units (relative to the label font, via the `height=` attribute) rather than
fixed pixels, so they scale with the surrounding text — Godot's `[img]` supports
an `em` suffix (`height=1em` ≈ as tall as the surrounding text). Conventions:

| Icon kind | height | example |
|-----------|--------|---------|
| Inline content icon (e.g. `hexagons/hollow_hex`) | `1em` | `[img valign=center, height=1em]res://assets/icons/hexagons/hollow_hex.tres[/img]` |
| Single-sized input key / mouse button (`input/keyboard/letters/*`, `input/mouse/*_mb`, `scroll_wheel`) | `1.5em` | `[img valign=center, height=1.5em]res://assets/icons/input/keyboard/letters/r.tres[/img]` |
| Double-sized input key (wide keys; `input/mouse/all_directions`) | `2em` | `[img valign=center, height=2em]res://assets/icons/input/mouse/all_directions.tres[/img]` |

---

## `jobs`

A map of `job_id → Job`. Jobs are the modern, hex-editor challenges. The
solution graph is validated by `Checker` (`src/classes/checker.gd`) against the
job's `tests` and structure constraints.

```jsonc
"job_09_increment_fn": {
  "name": "Increment",
  "description": "Wire up a function that adds one…",   // BBCode
  "renown_required": 6,        // renown needed before the job is offered
  "renown_reward": 3,          // renown granted on solve
  "tests": [
    { "input": 5,  "expected": 6 },
    { "input": -1, "expected": 0 }
  ],
  "unlocks_hexes": ["hex_add"],          // hex ids (see Hex id registry)
  "required_structures": ["lambda"],     // optional
  "forbidden_structures": ["bool"],      // optional
  "variables": { "white": 7 }            // optional
}
```

| Field                  | Type            | Required | Notes |
|------------------------|-----------------|----------|-------|
| `name`                 | String          | yes      | Display title. |
| `description`          | String (BBCode) | yes      | Shown in the jobs panel. |
| `renown_required`      | int             | yes      | Gate; `0` = available from the start. |
| `renown_reward`        | int             | yes      | Renown granted on first solve. |
| `tests`                | `[Test]`        | yes      | Test cases (see [Test cases](#test-cases)). |
| `unlocks_hexes`        | `[String]`      | no       | Hex **ids** unlocked on solve, e.g. `["hex_add", "hex_lambda"]` (see [Hex id registry](#hex-id-registry)). |
| `required_structures`  | `[String]`      | no       | AST features the answer **must** contain, e.g. `["lambda", "binary_op", "variable", "if"]`. |
| `forbidden_structures` | `[String]`      | no       | AST features the answer **must not** contain, e.g. `["bool", "int"]`. |
| `variables`            | `{ name → value }` | no    | Free identifiers injected into the answer's environment, e.g. `{"white": 7}`. |

### Test cases

The test/validation shape is owned by `Checker` (`src/classes/checker.gd`).
Three forms are used in practice:

- `{ "expected_type": 0 }` — only assert the result's `Value.Type` (e.g. the
  answer is *some* Int). Used for open-ended jobs.
- `{ "expected": 8 }` — assert the program evaluates to a literal value.
- `{ "input": 5, "expected": 6 }` — call the answer (a function) with `input`
  and assert the result. `input` may be an array of positional arguments
  (`{"input": [[1,2,3,4]], "expected": 10}`); `args` is accepted as an alias.

### Hex id registry

`unlocks_hexes` references hexes by **id** rather than by hard `res://…` script
path. The mapping lives in `StaticData.HEX_REGISTRY`
(`src/singletons/static_data.gd`) and is resolved at the point of use via
`StaticData.hex_path(id)` (single value) / `StaticData.hex_paths(ids)` (list).

- Ids follow `hex_<stem>`, where `<stem>` is the script filename with the
  `_hex.gd` suffix removed: `add_hex.gd` → `hex_add`, `let_rec_hex.gd` →
  `hex_let_rec`, `list_literal_hex.gd` → `hex_list_literal`,
  `int_literal_hex.gd` → `hex_int_literal`.
- A raw `res://…/foo_hex.gd` path is still accepted (returned unchanged), so old
  data and one-off paths keep working.
- An unknown id resolves to `""` and logs an error; the unlock is skipped.
- To add a new unlockable hex, add its `hex_<stem>` → path entry to
  `HEX_REGISTRY` (kept in sync with `HexPalette.SCRIPT_FAMILY`, which a unit test
  cross-checks), then reference the id from `unlocks_hexes`.

---

## `examples`

A map of `display_name → source_code` (functional-language source strings, e.g.
`Factorial`, `Quick Sort`). This is sample-program data; it is currently not read
by live code (the modern intro carousel uses per-chapter `examples` slides
instead) but is retained as the canonical example set for future use.

```jsonc
"Map Double": "-- Map a function to double each element in a list.\nlet double = (*2)\nin map double [1..5]"
```

---

## Legacy data

Deprecated Playground content lives outside `static_data.json` so the modern file
stays focused. It is loaded by `TemplateManager._load_default_content` from
`data/legacy_playground.json` (`TemplateManager.LEGACY_PLAYGROUND_PATH`).

`data/legacy_playground.json`:

```jsonc
{
  "templates": {                 // code-snippet strings inserted in the text editor
    "lambda": "\\{- params -} -> {- body -}"
  },
  "exercises": {                 // text-coding challenges (pre-hex)
    "exercise_01": {
      "name": "Return a number",
      "description": "Write a single expression…",
      "renown_required": 0,
      "renown_reward": 2,
      "tests": [ { "expected_type": 0 } ],
      "starter_code": "",        // optional pre-filled editor text
      "template_hints": []       // optional template names hinted for this exercise
    }
  }
}
```

Exercises use the same `tests` shape as jobs. A chapter's legacy `exercises`
array (above) holds ids into this map.

`data/example_templates.json` is a separate sample file demonstrating the
user-import format (`{ "templates": {…}, "examples": {…} }`) for the settings
menu's "custom templates" feature — it is not loaded at boot.

---

## How to extend

**Add a job**
1. Add a `job_id → Job` entry under `jobs` (fill `name`, `description`,
   `renown_required`, `renown_reward`, `tests`; add `unlocks_hexes` /
   `required_structures` / `forbidden_structures` / `variables` as needed).
2. Add the `job_id` to the owning chapter's `jobs` array so it surfaces in that
   chapter.

**Add a chapter**
1. Add a `chapter_id → Chapter` entry under `chapters` in progression order
   (`name`, `description`, and `jobs`; add `examples` slides for the intro).
2. Provide any screenshot assets the slides reference under
   `res://assets/screenshots/chapters/`.

**Add an example program**
- Add a `display_name → source_code` entry under `examples`.

Validate structurally against `data/static_data.schema.json`, and confirm the
game still boots: `godot --headless --import` then the data-format spec
(`test/unit/data/test_static_data_format.gd`).
