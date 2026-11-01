# Contributing

Thanks for helping with Schiesstagebuch! Pull requests are welcome: bug fixes,
features, translations, new calibres or icons.

## License in short

- The code is **source-available** under the
  [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may read, build, change
  and use it for yourself, your club or any other noncommercial purpose, and share
  your changes under the same terms.
- **Commercial use is not allowed**, including selling the app or a copy of it in
  the App Store, or making money from it in other ways. Only the project owner may
  publish the app commercially.

## Contributor License Agreement

Before your first pull request can be merged, you need to agree to the
[Contributor License Agreement](CLA.md). You keep the copyright in your work, but
grant the project owner the right to use it in any way, including in a paid App
Store release. This keeps the project in one hand so it can be published at all.

To agree, tick the CLA checkbox in the pull request description.

## Building

See the [README](README.md#building). In short: `brew install xcodegen`,
`xcodegen generate`, open the project and choose your own signing team and bundle id.

## Guidelines

- Write UI text in German and add English, French and Italian to
  `tools/translations.py`, then run `python3 tools/localize.py`.
- New calibres go into `tools/cartridges.py`, icons into `tools/weapon_icons.py`;
  run `python3 tools/generate_assets.py` and commit the generated JSON.
- Keep pull requests focused, and describe what you changed and how you tested it.
