# Contributing

Schiesstagebuch is closed source ([LICENSE.md](LICENSE.md)). Only people Simon Giotta
invites work on it, under a written agreement with Simon Giotta. These notes are for them.

## Building

See the [README](README.md#building). In short: `brew install xcodegen`,
`xcodegen generate`, open the project and choose your own signing team and bundle id.

## Guidelines

- Write UI text in German and add English, French and Italian to
  `tools/translations.py`, then run `python3 tools/localize.py`. A text that says
  «Waffe» also needs its «Sportgerät» variant (see the [README](README.md#languages)).
- New calibres go into [calibre-data](https://github.com/ravench/calibre-data) (a submodule
  here), icons into `tools/weapon_icons.py`; bump the submodule, run
  `python3 tools/generate_assets.py` and commit the generated JSON.
- Every change comes with unit tests; CI runs them and SwiftLint on every push.
- Keep pull requests small and focused, and describe what you changed and how you tested it.
- A pull request that changes the GUI shows screenshots. CI comments with the screens that
  changed, before and after; if your screen is missing, add it to the tour in
  `SchiesstagebuchUITests/PRScreensTests.swift`.
