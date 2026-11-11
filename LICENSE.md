# Licence

© 2026 Simon Giotta. All rights reserved.

Schiesstagebuch is closed source. No licence is granted to use, copy, change or distribute the code,
texts, icons or other files in this repository, except for the parts listed below or where Simon
Giotta agrees in writing. When the app is offered in the App Store, it comes with Apple's standard
licence agreement (EULA) for App Store apps.

Copies of the versions up to 10 November 2026 that were published under the PolyForm Noncommercial
License 1.0.0 keep that licence; it does not cover any later version.

## Parts with their own licence

- `calibre-data/`: the shared calibre catalogue, a git submodule with its own licence (see its
  `LICENSE.md`). `Schiesstagebuch/Resources/Calibers.json` is made from it and falls under that
  licence too.
- `Schiesstagebuch/Resources/SwissRanges.json`: the outdoor ranges and street addresses come from
  swisstopo's swissTLM3D and official building address directory, © swisstopo (open government
  data, commercial use allowed with credit); the app shows «© swisstopo» wherever it lists these
  ranges. The indoor ranges in it come from `data/indoor-ranges.json`, which is kept by hand here.
- `.claude/skills/ponytail/`: a skill for Claude Code by another author, under the MIT licence in its
  own `LICENSE` file.
