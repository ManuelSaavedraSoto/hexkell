Roadmap

Where Hexkell stands and where it goes next. This is a direction document, not a task tracker: each section describes a goal and what "done" should feel like for the player, and leaves the implementation to whoever picks it up. For the visual language see HEX_DESIGN.md, for the blueprint wire format BLUEPRINT_FORMAT.md, and for the language grammar LANG.md.
Current state

Hexkell is a working proof of concept. Players build programs in a lazy functional language by placing and wiring hexes on a grid instead of typing code. The full gameplay loop is in place:

    A complete language runtime (lazy evaluation, recursion, pattern matching, lists and tuples, a standard prelude).
    The hex-grid editor: nested levels as scopes, wires and emissions, rotation, undo/redo, live program preview, and run/validate.
    Persistent workspace tabs, a jobs panel to submit solutions against, renown that unlocks new hex types, and a blueprint library for reusing snippets.
    Chapter intros, a codex, and a guided tutorial for the first steps.

A usability study with first-time players confirmed that the core idea works: nobody wrote a syntactically invalid program, nobody got stuck for good, and players enjoyed the visual and audio feedback. It also mapped where the friction is. That map drives most of what follows.
1. Refine the UX from usability-test findings

The concept holds up; the next step is making it comfortable for a first-time player who may not know how to program yet.

    Spanish localization. English was a barrier for several testers. The whole interface, the tutorial, chapter texts and exercises should be available in Spanish, with room for more languages later.
    Direct manipulation. Players instinctively tried to drag hexes to move them, struggled to grab hex borders to start a wire, and lost track of which side of a non-commutative hex goes where. Moving hexes should work by dragging, wiring should have generous hit areas and clear feedback while dragging, and asymmetric hexes should make their sides obvious (and be easy to flip).
    Teach how the hexes work. The biggest gaps were explaining scope, identifiers, lambdas and parameter binding, and making nested levels visible (most players never noticed the breadcrumb). This calls for designed answers rather than more text: a way to see the structure of the whole program at a glance, clearer cues for inputs, outputs and the active level, and errors that point the player to where the problem actually is.
    Smoother onboarding. The tutorial should introduce every core tool (moving the camera, undo, the output panel, the codex, the config panel) and the difficulty curve before lambdas should be gentler, with more intermediate exercises.

2. Accessibility and settings

A proper settings menu that covers the basics players expect:

    Separate volume controls for music and sound effects.
    Brightness, text size and camera/mouse sensitivity.
    Rebindable controls.
    Colorblind-friendly palettes, so no information is carried by colour alone.

3. Exercise import/export that fits the tutorial system

Exercises, chapters and the tutorial grew separately. The import and export system should be revised so that new exercise sets, including ones authored by teachers or the community, can be packaged and shared, and plug straight into chapters, the tutorial flow and progression without manual wiring.
4. Bespoke art and sound

Replace stock UI icons and sound effects with assets made for Hexkell, in a consistent style that supports the magic metaphor. This also fills the silent editing cues (placing, connecting, deleting, picking up and rotating hexes) left empty in the open-source version, whose original sounds can't be redistributed. All new assets should be licensed so they can live in this repository.
5. Expanded storyline and exercises

Give the jobs a world to live in: a storyline that frames exercises as commissions for in-world clients, and a longer exercise list that covers more of functional programming (higher-order functions, recursion over lists, folds, laziness) with a gradual curve between them.
6. Static typing and elemental magic

Introduce static types to the language and present them through the game's metaphor as elements: each value carries an element, wires and hex slots only accept compatible elements, and mismatches show up while building rather than at run time. The goal is to teach types as a natural rule of the magic system, reinforce the metaphor overall, and catch mistakes earlier.
