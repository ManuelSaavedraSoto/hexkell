# Chapter screenshots

Drop chapter screenshots here. Filenames are referenced from
`data/static_data.json` `chapters.<id>.examples[].screenshot`.

Naming convention:
- `tutorial_<concept>.png` for the Tutorial chapter
- `ch1_<concept>.png` for Chapter 1 (Lambdas & Structures)

The chapter-intro dialog (`scenes/gui/common/chapter_intro_dialog.gd`)
handles missing files gracefully: each tab whose `screenshot` path
doesn't resolve renders a "(screenshot pending — place a hex graph
and capture)" placeholder. This lets the data-side restructure ship
ahead of the screenshot capture pass.

When ready, capture in the hex editor at the size of the dialog's
right column (~280–360 px wide is fine; the TextureRect uses
`STRETCH_KEEP_ASPECT_CENTERED` so any aspect ratio works) and save
as PNG.
