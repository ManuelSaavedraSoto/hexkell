# Hex Node Design

The visual language for v3 (hex-grid editor over the v2 lazy
language — see `LANG.md` for syntax + semantics, `TODO.md` for the
versioning legend and project status). Visual hexes are syntactic
UI over the language's AST; tree traversal produces canonical
textual programs, which are what gets evaluated.

This document is the *current* (second) iteration of the visual
design. An earlier canvas-based draft was scrapped before any code
shipped, so this is what's built.

## Core dichotomy

Two distinct transmission mechanisms:

| Mechanism | Carries | Visual form | Role |
|---|---|---|---|
| **Wires** | values | physical connections between hex sides | Application, piping precedence, execution flow. Connects anonymous nodes. |
| **Emissions** | identifiers | wireless, ambient within enclosing scope | Named references. Identifiers in scope can be inscribed onto any compatible hex side. |

Wires carry computation; emissions carry names. The dichotomy makes lets, definitions, lambdas, match, apply, and compose all coherent under one model.

## Universal rules

1. **One connection per side**: any hex side is wired, inscribed, or empty — never two at once. Wiring a side clears its inscription and vice versa.
2. **Inscriptions are identifiers only**: literals are dedicated hex nodes, not inscribed on input sides.
3. **Levels = scopes**: pressing `Q` descends into a node's inner level, `E` ascends. Outer-level emissions are ambient within inner levels (lexical scoping = depth).
4. **Hex geometry**: six sides per hex. Typical arrangement: 5 input sides + 1 output side. Hexes are placed Factorio/Shapez-style — selected from a palette, previewed as a blueprint following the cursor, rotated in 60° increments, then committed by clicking. Rotation only affects spatial orientation of sides, not semantics.
5. **Soft enforcement**: malformed hexes show a visual alert (red outline, `!` icon) and block program submission, but don't crash the editor. Acts as a soft validity check.

## Level 0 (top)

The top level has no anchor. Inhabited by:

- **Main `do` hex**: a single main-expression input, approachable from any of the six sides (one wire total — wiring a new side moves it). The textual `do` or `$` separator from the EBNF marks the start of the main expression.
- **Definition hexes**: float alongside the main hex, wirelessly emit their identifiers into level 0's scope.

Definitions and the main hex are not wired to each other at level 0 — they communicate via emission.

## Node reference

| Node                                | Type         | Outer face                                                                                   | Inner level                                                      | Notes                                                                                                 |
| ----------------------------------- | ------------ | -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Main `do`**                       | Core         | 1 main-expression input (any of 6 sides, one wire)                                           | program body                                                     | Level 0 entry point. Exactly one.                                                                     |
| **Definition** (Universal injector) | injector     | inscribed name + N inputs (configurable arity 1–5, each with a pattern inscribed) + 1 output | body region + anchor emitting pattern bindings                   | One equation per hex. Multi-equation = multiple hexes with same identifier. Output never wired at L0. |
| **Let** (one-way injector)          | injector     | inscribed name + 1 wired value input + 1 output                                              | body + anchor emitting the inscribed name                        | Injects wired value into inner scope as the name.                                                     |
| **Let rec** (two-way injector)      | injector     | same as let                                                                                  | same, plus inscribed name is also emitted into the value's level | Enables self-reference.                                                                               |
| **Lambda** (anonymous level)        | producer     | 1–5 wired inputs + 1 output                                                                  | body + anchor emitting the inputs as identifiers                 | No name. Output is the function value.                                                                |
| **Match**                           | flow control | 1 input (scrutinee) + 1 output                                                               | anchor with pattern-inscribed sides + branch regions             | Pattern bindings emitted into each branch region. No wire splitters.                                  |
| **Apply** (wireless)                | operator     | inscribed function identifier + 1–5 wired argument inputs + 1 output                         | none                                                             | Bridge from wireless identifiers to wired application. Only way to use top-level functions.           |
| **Compose**                         | operator     | 2 wired function inputs (`f` NW, `g` SW) + 1 output                                          | none                                                             | Produces a composed function *value* from any wired expressions. Day-to-day composition is just wiring chains. |
| **If** (multiplexer)                | flow control | condition input + 1 output                                                                   | anchor with `then` (NW) / `else` (SW) slots; no emissions        | Bodies live one level down, same shape as let/match. Could be built from filters, but too common to force as composition. |
| **Binary op**                       | operator     | operator on hex face + 0–2 wired/inscribed inputs + 1 output                                 | none                                                             | Partial wiring → output is a partially-applied function (section).                                    |
| **Negation**                        | operator     | operator (`-` or `!`) on face + 1 input + 1 output                                           | none                                                             |                                                                                                       |
| **Integer literal**                 | producer     | value displayed (slider/spinbox) + 1 output                                                  | none                                                             | Dedicated node — no inscription.                                                                      |
| **Boolean literal**                 | producer     | true/false toggle + 1 output                                                                 | none                                                             | Dedicated node.                                                                                       |
| **Tuple**                           | container    | 1 output only (arity 2–5 via sidebar)                                                        | anchor with one ordinal-branded slot per element; no emissions   | Fixed, known shape. Changing arity purges the inner level (match-style).                              |
| **List literal**                    | container    | 1 output only                                                                                | anchor with 5 optional ordinal slots; itself descendable into a continuation anchor once full | Unbounded: full blocks chain indefinitely. No wiring = `[]`. Emission flattens the chain to `[a, b, …]`. |
| **Range**                           | container    | start (wired) + optional end (wired) + 1 output                                              | none                                                             | Unwired end produces infinite range `[start..]`.                                                      |

## Definitions in detail

A definition hex represents **one equation**. Multi-equation pattern matching uses multiple definition hexes inscribed with the same identifier.

- **Arity**: configurable on the first definition hex created for an identifier (1–5). Subsequent hexes with the same identifier default to that arity; changing it raises a soft-enforcement alert.
- **Argument patterns**: each input side has a pattern inscribed (variable name = "anything"; literal; tuple; cons `(h:t)`; etc.).
- **Order**: spatial position on canvas determines evaluation order (top-to-bottom, then left-to-right). A small number badge on each hex updates as the user drags hexes around — making the implicit ordering visible.
- **Visual linking**: when a definition hex is selected, all hexes with the same identifier get a subtle visual indicator (outline glow, faint dotted line). Helps find all cases of a function.
- **Inner level**: anchor emits each pattern's bindings as identifiers in scope. Body region wires through transformations to the anchor's return slot — approachable from any free side, one wire total (wiring a new side moves it). An emission side may double as the wired return.
- **Optional guard**: each definition hex may carry a guard predicate alongside its patterns. Emits as `id pat | guard = body` instead of `id pat = body`.

## Match in detail

A match hex's inner level is structurally similar to a definition's inner level:

- Anchor at (0,0) has up to 5 pattern-inscribed sides + 1 output side
- Each pattern side emits its bindings into a "branch region" of the canvas
- Branch wiring at this level connects from each pattern side's emissions back to the output side
- At runtime, the branch whose pattern matches the scrutinee is the one whose result reaches the output

Branches aren't sub-nodes — they're regions of canvas at this level, naturally separated by which pattern-side their wiring originates from.

## Lets vs Lambdas — semantically equivalent, visually distinct

`let x = v in body` is `(\x -> body) v`. The visual mode keeps both because the **wired vs inscribed** distinction gives them different ergonomic roles:

- **Lambdas**: parameters arrive via **wires** (positional, anonymous). Good for one-off function values, partial application, higher-order arguments.
- **Lets**: the name is inscribed (broadcast, ambient). Good for naming intermediate values, threading state through a long body, recursive definitions.

Use a lambda when the function is anonymous and applied immediately; use a let when the name will be referenced multiple times or recursively.

## Text generation

Walk from terminal outputs (main hex's output; each definition hex's output):

| Source | Emission |
|---|---|
| Hex with all inputs satisfied (wired or inscribed) | `(hex_form) arg1 arg2 ...` |
| Hex with some inputs unsatisfied | `\u1 u2 -> (hex_form) ... u1 ... u2` (eta-abstraction) |
| Let | `let id = value in body` |
| Let rec | `let rec id = value in body` |
| Definition | `id pat1 pat2 ... = body` (or with guards) |
| Match | `match scrutinee with | pat1 = body1 | pat2 = body2 ...` |
| Lambda | `\p1 p2 -> body` |
| Apply | `name arg1 arg2 ...` |
| Compose | `(f . g)` (both wired) |
| If | `if cond then body1 else body2` (bodies from the inner anchor's slots) |
| Tuple | `(a, b, c)` (elements from the inner anchor's slots) |
| List literal | `[a, b, c]` (continuation chain flattened into one flat literal) |
| Range | `[start..end]` or `[start..]` |
| Inscribed identifier | the identifier text |
| Literal | the literal text |
| Binary op | `(left OP right)` |

Top-level walk emits all definitions first (sorted by their spatial order per identifier), then the `do` / `$` separator, then the main hex's body. Parenthesization is conservative (parenthesize every binary op), then a post-emission cleanup pass (`HexTextFormatter.clean`) strips atom-wraps and double-parens to fixpoint — precedence-safe transforms, never changes the AST.

## Worked example: `factorial`

```
factorial n | n == 0 = 1
            | n > 0  = n * factorial (n - 1)
do
factorial 5
```

**Level 0:**
- Main `do` hex with one input wired through an `apply` hex (inscribed `factorial`) whose argument is a literal `5`
- Two `factorial` definition hexes (arity 1, input pattern `n` on both), visually linked, ordered top-to-bottom
- First hex carries guard `n == 0`, body returns literal `1`
- Second hex carries guard `n > 0`, body returns `n * factorial (n - 1)`

**Q into the second `factorial` definition:**
- Anchor emits `n`
- `*` hex with `n` inscribed on left input + `apply` hex on right input
- The right `apply` is inscribed `factorial`, its argument wired from a `-` hex (`n` inscribed, literal `1` wired)
- `*` output wired to anchor's return

Because `factorial` is wirelessly emitted into level 0's scope, the inner `apply factorial` just inscribes the identifier — no special recursion handling needed.

## What's explicitly out of scope

- **List comprehensions** — Haskell-specific sugar, not core to teaching functional concepts.
- **Wire splitters / filter wires** — pattern destructuring is via emission, not wiring.
- **Filter hexes** — guards are absorbed into definition hex's optional guard slot.
- **Literal inscription** on hex sides — literals are dedicated hex nodes.
- **Static typing** — language doesn't yet support it (per EBNF notes).
- **Magic-circle aesthetic skin** — the hex grid stays plain for now; visual reskin is a later layer.

## What this design buys

- **No apply node for anonymous functions**: wires *are* application.
- **No wire splitters**: pattern destructuring via emission.
- **No collapse/explode mechanism**: it's just Q/E level navigation.
- **Scope = depth**: lexical scoping is literally the level stack.
- **Currying and partial application**: free, from unwired-input → eta-abstraction.
- **Mutual recursion at top level**: free, from wireless emissions.
- **Sections**: free, from binary op partial wiring with literal hex inputs.
- **Production-line aesthetic**: every level is a sub-factory with a loading bay (the anchor).
- **Pedagogical clarity**: each visual primitive maps cleanly to one functional concept.
