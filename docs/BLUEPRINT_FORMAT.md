# Blueprint serializer — design

Resolution of the open question for v3 blueprints (see `TODO.md`).

## Goals

1. **Players can share blueprints as a single text token** pasted into
   chat / Discord / a forum post — the same UX as Factorio's
   blueprint strings.
2. **Storage is dual**: embedded inside the main save file by default
   (no extra files to lose, single auto-save covers everything), and
   on-demand `Export` / `Import` writes / reads the same string from
   the clipboard or a sidecar file.
3. **The same writer/reader closes out 19.8's tab round-trip.** A
   workspace tab is just a top-level blueprint plus a name and an
   active-level pointer — re-using one serializer for both keeps the
   surface area small.
4. **Forward-compatible.** A leading version byte plus a schema
   `version` field lets future revisions add fields without breaking
   old saves.
5. **Graceful failure on missing hex types.** If a blueprint
   references a `script_path` the current build doesn't have (script
   renamed, blueprint authored on a newer build), we don't crash —
   we surface a load error and skip those hexes.

## Wire format

Modeled after Factorio's [blueprint string format][1]:

```
hxk1:<base64 of gzip(JSON(payload))>
```

- `hxk1` — magic + schema major version. Bumping the digit signals an
  incompatible format change; minor revisions stay backwards-compatible.
- Colon separator keeps the prefix human-distinguishable.
- gzip → base64 keeps the payload short enough to paste in chat.
  Godot exposes `PackedByteArray.compress(FileAccess.COMPRESSION_GZIP)`
  and `Marshalls.raw_to_base64` / `.base64_to_raw` for the round trip.

The embedded form in `user://saves/story_progress.json` stores the
*decoded JSON* directly under `hex.blueprints[i]` (no point base64-ing
when the save file itself is JSON). The string form is produced only
by `Export to clipboard` / `Export to file`.

[1]: https://wiki.factorio.com/Blueprint_string_format

## JSON schema

```jsonc
{
  "version": 1,                       // schema minor version
  "kind": "blueprint",                // "blueprint" | "tab"
  "label": "doubler",                 // user-facing name
  "description": "",                  // optional, user-authored
  "icon": "🟥",                       // optional, palette emoji for quick id
  "created_at": "2026-05-30T22:00",   // ISO8601, set at capture
  "origin": [0, 0],                   // axial offset of the "anchor" hex
                                      //   (used so stamps anchor at cursor)
  "hexes": [
    {
      "id": 0,                        // local-to-blueprint id (referenced by wires)
      "script": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
      "class": "IntLiteralHex",       // class_name for rename survival
      "axial": [1, 0],                // relative to `origin`
      "rotation": 0,
      "state": { "value": 7 }         // hex-specific (see below)
    },
    {
      "id": 1,
      "script": "res://src/classes/hex_nodes/control/let_hex.gd",
      "class": "LetHex",
      "axial": [3, -1],
      "rotation": 2,
      "state": { "palette_index": 0 },
      "inner": {                      // recursive — same schema for an inner level
        "kind": "level",
        "hexes": [ ... ],
        "wires": [ ... ]
      }
    }
  ],
  "wires": [
    {
      "output": [0, 0],               // [hex id, logical edge]
      "input":  [1, 4],
      "cells":  [                     // belt-style cell path
        { "axial": [2, 0], "enter": 3, "exit": 0 },
        ...
      ],
      "open": false                   // true for cable-planning stubs
    }
  ]
}
```

A `tab` payload is identical but adds `"active_level_path": [..]` for
restoring the user's current view across sessions.

### Hex-class identity

Two fields per hex:

- `script` — `res://…` path. Primary key when loading.
- `class` — `class_name` declared by the script (`IntLiteralHex`,
  `LetHex`, …) — used as a fallback when the script path has moved.
  Loader prefers `script`, then walks a class-registry to find a
  surviving match; if both fail, the hex is skipped and the player
  sees a "missing hex type" diagnostic.

The registry lives in `BlueprintLoader` and is built at startup by
walking the palette categories — no separate manual maintenance.

### Per-hex `state` keys

Captured by `HexNode.serialize_state(canvas) -> Dictionary` and
restored by `HexNode.restore_state(state, canvas) -> void`, both
overridable. The base returns `{}`. Known overrides:

| Hex                 | Keys                                |
| ------------------- | ----------------------------------- |
| `IntLiteralHex`     | `value: int`                        |
| `IdentRefHex`       | `palette_index: int`                |
| `LetHex` / `LetRecHex` | `palette_index: int` (bound name) |
| `LambdaHex`         | `arity: int`, `param_palette_indices: int[]` |
| `MatchHex`          | `arity: int`, `patterns: string[]`  |
| `DefinitionHex`     | `palette_index: int`, `arity: int`, `patterns: string[]` |
| `TupleHex`          | `arity: int`                        |
| `ListLiteralHex`    | `{}` — elements live in the inner level |
| `RangeHex`          | `end_optional: bool`                |
| `ComposeHex`        | `{}` — both functions arrive by wire |
| Pure operators (`AddHex`, etc.) | `{}`                    |
| `DoHex`             | `{}` — fixture; never serialized in a blueprint |

The inner-level anchors (`AnchorHex`, `MatchAnchor`, `IfAnchor`,
`TupleAnchor`, `ListAnchor`) don't appear in this table either — like
the Do hex they're fixtures, rebuilt from the parent's
`create_inner_anchor`, never emitted as `hexes` entries.

### Wires

Wires carry their full anchored cell sequence so a stamped blueprint
restores byte-identical to the captured one. The `id` in `output` /
`input` is the blueprint-local hex id, not the editor's runtime node
id — that's how a blueprint stays portable across sessions.

Adjacency-fallback connections (no explicit wire, neighbours feed
each other through `get_input_for`'s second branch) are NOT
serialized as wires — they re-establish naturally when both
neighbours are stamped at their captured relative axials.

### Anchor-owned inner levels (list continuations)

A level's anchor/fixture is never emitted in `hexes` (it's recreated
from the parent's `create_inner_anchor`), but it may own an inner
level of its own — a `ListAnchor`'s continuation block. That chain is
serialized as an optional `inner` key on the *level body itself*,
recursive:

```jsonc
"inner": {                 // the list hex's inner level
  "kind": "level",
  "fixture_id": 7,         // its ListAnchor
  "hexes": [ ... ],        // first five elements
  "wires": [ ... ],
  "inner": {               // the ListAnchor's OWN inner level —
    "kind": "level",       //   the continuation block, and so on
    ...
  }
}
```

The key is additive: root levels never emit it (the DoHex fixture has
no inner level), and readers that predate it simply drop
continuations.

## Loader contract

`BlueprintLoader.stamp(payload, anchor_axial, target_level, canvas)`:

1. Validate `version` ≤ supported; reject otherwise with a clear
   message.
2. Resolve every hex's script (preferring path, falling back to
   class). Build a local-id → new HexNode map.
3. Instantiate every hex, apply its `state`, place at
   `anchor_axial + axial`, rotate.
4. Walk inner levels recursively (LetHex / LambdaHex / MatchHex / IfHex /
   DefinitionHex / TupleHex / ListLiteralHex — including level-body
   `inner` keys for ListAnchor continuations).
5. Rebuild every wire's HexWire from `cells` + endpoints.
6. Bind everything into the target level's `hexes` / `wires` arrays
   and call `_wire_node_signals` for each.

Failure modes:

- **Collision with placed hexes**: stamping rejects the whole
  blueprint (atomic). The blueprint cursor preview shows red over
  occupied cells before commit, same as single-hex placement.
- **Locked hex inside a blueprint**: configurable. The recommended
  default is *blocked stamp until the player unlocks every hex
  type used* — see `LOCKED_BLUEPRINT_STAMP_POLICY` below.
- **Missing script + missing class**: skip the hex, drop any wires
  touching it, surface a per-hex warning in the output panel after
  the stamp completes.

## SaveManager surface

```gdscript
SaveManager.add_blueprint(name, payload_dict)        # existing — now stores
                                                     # the schema-shaped dict
SaveManager.export_blueprint_string(index) -> String # produces hxk1:…
SaveManager.import_blueprint_string(s) -> bool       # parses, validates,
                                                     # appends if OK
```

The existing `program_text` field on saved blueprints stays as a
backwards-compatibility shim — loaders that don't recognise the new
shape can still display the textual program.

## Editor UI surface (Phase 19.4 follow-up)

- **Capture**: top-bar `Capture` button (or right-click on a tab
  → "Save tab as blueprint"). Prompts for a name; serializes the
  current tab's root level (not the whole `_level_stack`).
- **Library panel**: a modal window that closes when selecting a blueprint, hot-keyed to "b", listing
  saved blueprints with rename / delete / `Export` (copies the
  string to clipboard) / `Import` (paste a string). The window has two columns, the left column has the
  scrollable list of blueprints and action buttons, the right side has a preview of the highest level of the blueprint. The live preview is deferred until UI touch-ups and revisions but the space must be reserved.
- **Stamp**: click a blueprint card → editor enters multi-hex
  blueprint cursor mode → the preview follows the mouse with
  relative axials preserved → click to commit, Esc to cancel.

## Locked-hex policy in stamps

`LOCKED_BLUEPRINT_STAMP_POLICY` (constant in `BlueprintLoader`):

| Mode                | Behaviour                                    |
| ------------------- | -------------------------------------------- |
| `REFUSE` *(default)*| Stamp button is disabled; tooltip lists locked hex types. Forces the player to earn the unlocks first — keeps the progression meaningful. |
| `STAMP_GRAY`        | Stamps anyway; locked hexes render grayed-out and refuse to evaluate at run time. |
| `OMIT`              | Stamps only the unlocked subset and any wires that touch removed hexes are dropped. |

We ship `REFUSE`; the other two are listed for posterity and
trivial to opt into per-blueprint via a `policy` field on the
payload.

## Out of scope (deferred)

- Encryption / signing of blueprint strings. The format is meant to
  be share-friendly; tamper-resistance is not a goal.
- Cross-version migrations. The version bump path is reserved but
  not yet wired up.
- Blueprint books (Factorio's "book of blueprints"). A single
  blueprint string per capture is the v1 scope.
