# Contributing to Kaste

Thanks for your interest in Kaste!

## Dev setup

```bash
brew install xcodegen
xcodegen generate
open Kaste.xcodeproj
```

Build & run with `⌘R` in Xcode (requires macOS 14+ and Xcode 15+).

## Project layout

- `Kaste/` — Swift source (App / Core / Features).
- `project.yml` — XcodeGen config. The `.xcodeproj` is generated and gitignored.
- `scripts/generate_icon.swift` — regenerates `AppIcon.appiconset` + `logo_1024.png`.
- `.github/workflows/release.yml` — tag-triggered DMG release pipeline.

## Releasing

Push a tag matching `v*` (e.g. `v0.1.0`). GitHub Actions builds an Apple-Silicon
DMG and attaches it to a release automatically.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Pull requests

- Keep PRs focused.
- Match existing code style (SwiftUI for views, AppKit only where SwiftUI can't
  reach — non-activating panel, CGEvent injection, Carbon hotkey).
- Update or add docs in the Vaptu Obsidian vault when the change is
  architectural; trivial fixes don't need doc updates.

## License

By contributing you agree your contributions are licensed under the MIT License.
