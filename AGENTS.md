# Agent instructions — Altitude

Guidance for AI coding agents working in this repository.

## Documentation is required

**Every new feature must be documented in `README.md`.**

When you add, change, or remove user-facing behavior:

1. Update `README.md` in the same change (Features, Configuration, Permissions, Limitations, or layout as needed).
2. Keep README examples and config keys in sync with `config/config.example.toml` and the real config schema.
3. Do not leave undocumented knobs, hotkeys, menu items, or setup steps for a follow-up.

Treat an incomplete README as incomplete work — same bar as unfinished code.

## Testing (soft expectation)

New features should include or update tests for testable logic (especially Domain parsers, pure helpers, and config round-trips). Accessibility, SkyLight/CGS SPI, Dock swipe, CGEvent taps, and UI may stay manual. Run `make test` locally; PRs to `main` also run unsigned build+test in GitHub Actions. This is guidance, not the hard “incomplete work” bar used for README documentation.

## Project notes

- Native macOS menu bar app (Swift / AppKit), not a SwiftUI or SPM package app.
- Prefer matching existing patterns in `Altitude/` (Backend / Domain / Hotkeys / UI).
- After adding Swift source files, keep `scripts/generate_pbxproj.py` and the Xcode project in sync if that is how sources are registered.
- Do not commit secrets, local signing overrides that are personal-only, or build artifacts under `build/`.
