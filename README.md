# Altitude

Menu bar agent for macOS that shows your Mission Control desktops and lets you jump between them (or move the focused window) with Option-digit hotkeys.

**Version:** 0.1.0 · **License:** MIT

## Features

- **Menu bar space indicator** — numbered desktop boxes with the current Space highlighted
- **Switch Spaces** — `⌥` + `1`…`N` jumps to desktop N
- **Move focused window** — `⌥⇧` + `1`…`N` moves the frontmost window to desktop N
- **Menu actions** — pick a desktop from the status menu; reload config; open config; open Accessibility settings
- **TOML config** — hotkeys and animation behavior under `~/.config/altitude/config.toml` (stow-friendly)
- **Optional instant switching** — skip the paced trackpad-like slide and jump as fast as the Dock allows
- **Accessibility-aware** — prompts once for Accessibility; later launches use the menu if permission is missing

## Requirements

- macOS (built as an `LSUIElement` accessory app)
- Xcode / `xcodebuild`
- **Accessibility** permission for Space switching and window moves (Dock-swipe / AX path)
- Apple Development identity for codesigning if you use `make` (keeps the Accessibility grant stable across rebuilds)

## Build & run

Copy the env example and set your signing identity (required for `make build` / `make run`):

```bash
cp .env.example .env
# Edit .env and set SIGN_ID, e.g. Apple Development: you@example.com (TEAMID)
# List identities with: security find-identity -v -p codesigning
```

`.env` is gitignored — do not commit it.

```bash
make build   # Debug build into ./build, then codesign
make run     # build and open Altitude.app
make clean   # remove ./build
```

You can also override without a file: `make SIGN_ID="Apple Development: …" run`.

You can also open `Altitude.xcodeproj` in Xcode and run the **Altitude** scheme.

## Configuration

On first launch, if no config exists, Altitude copies the bundled example to:

```text
~/.config/altitude/config.toml
```

Example (`config/config.example.toml`):

```toml
version = 1

[spaces]
# When true, switches jump as fast as the Dock allows instead of a slide per desktop.
disable_animations = false

[hotkeys]
# option+N switches to desktop N; option+shift+N moves the focused window.
switch_enabled = true
move_enabled = true
# Highest desktop number that gets a hotkey (1...max). Clamped to existing Spaces at runtime.
max_space = 9
```

Use **Reload Config** in the menu bar menu after editing, or **Open Config…** to edit the file.

## Permissions

1. Grant **Accessibility** to Altitude in System Settings → Privacy & Security → Accessibility.
2. Prefer a stable codesign identity (`make` default) so macOS keeps the same trust entry across rebuilds.
3. If hotkeys beep and nothing happens, open the status menu and use the Accessibility item.

## Limitations (v1)

- Desktops are flattened into a single 1-based list in Mission Control order.
- Switching to a Space on another display is not supported.
- Hotkeys are limited to digits `1`–`9` (further capped by `max_space` and the number of Spaces).

## Project layout

```text
Altitude/
├── Altitude/                 # App sources
│   ├── Backend/              # SkyLight / CGS / Dock-swipe switching
│   ├── Domain/               # Config, models, focus resolver
│   ├── Hotkeys/              # Carbon global hotkeys
│   └── UI/                   # Menu bar + space indicator
├── config/config.example.toml
├── scripts/generate_pbxproj.py
├── Makefile
├── .env.example              # Template for local SIGN_ID (copy to .env)
├── AGENTS.md                 # Instructions for coding agents
└── README.md
```


## License

MIT — see [LICENSE](LICENSE).
