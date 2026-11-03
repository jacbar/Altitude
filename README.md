# Altitude

<p align="center">
  <img src="docs/branding/altitude-full.png" alt="Altitude" width="560" />
</p>

Opinionated macOS automation inspired by [Space Rabbit](https://space-rabbit.app) and [Spaceman](https://github.com/Jaysce/Spaceman). Altitude is a modular menu-bar agent: desktops, Command-Tab, and window management. Turn a module off and it does nothing; the status item stays either way.

**Version:** 0.1.0 · **License:** MIT

## What it does

### Desktop

Switch Mission Control desktops and move the focused window with digit hotkeys. The menu bar shows numbered desktop boxes (current Space highlighted); the status menu lists desktops when this module is on.

- Switch — default `⌥` + `1`…`N`
- Move focused window — default `⌥⇧` + `1`…`N`
- `disable_motion` — while enabled, skips Space slides for hotkeys, trackpad swipes, Control-Left/Right, and same-display app activation
- `max_space` — highest desktop number with a hotkey (default 9; clamped to 1…9 and existing Spaces)

### Command-Tab

Off by default (system switcher). When on, Altitude shows a still row of open windows — including other Spaces. The row can appear just after the key so the tap stays responsive. Untitled Electron helpers (ChatGPT, Teams, …) collapse to the largest real window. Tab / Shift-Tab / arrows move; ⌘Q quits and ⌘H hides the highlighted app; Escape cancels; releasing Command lands on the highlight. Ten seconds without input cancels; a disabled event tap also cancels. `disable_motion` only skips the slide when landing.

### Window management

Arrange windows on the desktop under the pointer.

- Maximize — default `⌃⌥` + `F`
- Equal split — default `⌃⌥` + `A` (equal columns, left to right)
- `margin` — outer inset and column gap (default 8; clamped 0…256)

## Always on

- **Settings…** — Cmd+comma; General / Desktop / Command-Tab / Windows; writes `config.toml` immediately. Desktop Switch/Move and Windows Maximize/Equal Split use press-to-record (plus **Use Default**); same-tab sibling conflicts show a red **already in use** message and do not save
- **Menu** — Settings…; Reload Config; Open Config…; Launch at Login; open Accessibility settings
- **Launch at Login** — menu item and General switch (and `[app] launch_at_login`) via `SMAppService`; reload/relaunch reconciles to config
- **Accessibility** — prompts once; later launches use the menu if permission is missing

## Requirements

- macOS (`LSUIElement` accessory app)
- Xcode / `xcodebuild`
- **Accessibility** for Space switching, window moves, and arrangement
- Apple Development identity for `make` codesigning (keeps Accessibility grant stable across rebuilds)

## Build & run

```bash
cp .env.example .env
# Edit .env → set SIGN_ID, e.g. Apple Development: you@example.com (TEAMID)
# List identities: security find-identity -v -p codesigning
```

`.env` is gitignored — do not commit it.

```bash
make test    # unsigned hostless Domain XCTest suite (no SIGN_ID)
make build   # Debug → ./build, then codesign
make run     # build and open Altitude.app
make install # force-quit, Release-build, install to /Applications, open
make clean   # remove ./build
```

- `make test` runs **hostless** `AltitudeTests` (`CODE_SIGNING_ALLOWED=NO`): it does not launch `Altitude.app`, write `~/.config/altitude`, touch Login Items, or install event taps. PRs and pushes to `main` run the same unsigned build+test path in GitHub Actions on **macos-14** and **macos-latest**.
- `make install` force-quits running Altitude, builds **Release**, codesigns with `SIGN_ID`, replaces `/Applications/Altitude.app`, and opens it. It does not fetch or check out git.
- Override without a file: `make SIGN_ID="Apple Development: …" run`
- Or open `Altitude.xcodeproj` and run the **Altitude** scheme (Product → Test runs `AltitudeTests`)

## Configuration

On first launch, if no config exists, Altitude copies the bundled example to:

```text
~/.config/altitude/config.toml
```

Example (`config/config.example.toml`):

```toml
version = 2

[app]
# When true, Altitude registers with macOS Login Items and starts at login.
# The menu bar "Launch at Login" item toggles this and writes it back to this file.
launch_at_login = false

[desktop]
# Switch and move desktops with digit hotkeys; optionally skip Space slides.
enabled = true
# When true (and desktop is enabled), hotkey switches, trackpad Space swipes,
# Control-Left/Right, and activating an app already on another same-display Space
# jump with no slide and no edge bounce.
disable_motion = false
# Highest desktop number that gets a hotkey (1...max). Clamped to existing Spaces at runtime.
max_space = 9

[desktop.switch]
# Default: Option+digit.
alt = true
shift = false
ctrl = false
cmd = false

[desktop.move]
# Default: Option+Shift+digit.
alt = true
shift = true
ctrl = false
cmd = false

[command_tab]
# When false, macOS keeps the system app switcher. When true, Altitude shows a
# still row of open windows (Tab / Shift-Tab / arrows, Command-Q, Command-H, Escape).
enabled = false
# When true (and Command-Tab is enabled), landing on the highlighted window skips the slide.
disable_motion = false

[window_management]
# Maximize and equal-split chords for windows on the desktop under the pointer.
enabled = true
# Outer inset and gap between equal-split columns (points).
margin = 8

[window_management.maximize]
# Default: Control+Option+F.
alt = true
shift = false
ctrl = true
cmd = false
key = f

[window_management.equal_split]
# Default: Control+Option+A.
alt = true
shift = false
ctrl = true
cmd = false
key = a
```

### Parsing & safety

- Files larger than **64 KB** of resolved bytes are rejected; Altitude falls back to defaults (the limit applies to the real file behind a symlink, not the symlink node size)
- Stow-style symlinks are allowed only when the resolved target stays under `$HOME`; Settings / menu saves write through the symlink to that target and leave the link in place
- Bools accept `true` / `false` / `yes` / `no` / `1` / `0`
- `#` starts a comment to end of line
- A missing or empty shortcut uses the default chord; a missing modifier flag keeps that flag's default
- If either desktop modifier set has no modifiers, or the two sets are equal, both defaults are used (`⌥` / `⌥⇧`)
- A missing, empty, or invalid window key uses that chord's default key; if the two resolved window chords are equal, both defaults are used (`⌃⌥F` / `⌃⌥A`)
- Unquoted key letters are case-insensitive; a quoted key is invalid. The stored letter is resolved through the active keyboard layout when the hotkey is registered; if that layout has no such key, the chord stays unregistered until the next apply
- Invalid bools/ints keep the field default; unknown keys are ignored
- Old `[spaces]`, `[hotkeys]`, and `[arrange]` sections are ignored

### Settings & menu

- **Settings…** (Cmd+comma) writes `~/.config/altitude/config.toml` immediately and reapplies hotkeys and motion
- **Desktop** tab — Switch/Move record modifiers only (digits 1–9 stay fixed); **Use Default** restores `⌥` / `⌥⇧`
- **Windows** tab — Maximize/Equal Split record a letter chord; **Use Default** restores `⌃⌥F` / `⌃⌥A`
- Same-tab sibling conflicts beep, revert the control, and show a red **already in use** message (clears on a successful change or when the window redisplays)
- **Open Config…** / **Reload Config** for hand edits; Reload refreshes an open Settings window from disk
- **Launch at Login** (menu or General) writes `launch_at_login` immediately; a failed write beeps, leaves the file unchanged, and restores the Login Item
- Reload and relaunch reconcile the Login Item to config (pending approval stays while true, removed when false)
- While macOS waits for Login Items approval, the menu item and General switch stay unchecked; clicking the menu item cancels that pending registration

## Permissions

1. Grant **Accessibility** to Altitude in System Settings → Privacy & Security → Accessibility.
2. Prefer a stable codesign identity (`make` default) so macOS keeps the same trust entry across rebuilds.
3. If hotkeys beep and nothing happens, open the status menu and use the Accessibility item.

## Good to know

- Desktops are numbered 1–9 in Mission Control order.
- A hotkey that failed to register is tried again on the next reload or Settings save.
- Hotkeys and window arrangement need Accessibility.
- If a private SkyLight or Accessibility symbol is missing, Altitude skips that operation instead of crashing at launch.
- Window arrangement affects the desktop under the pointer and skips minimized, fullscreen, and other-desktop windows.
- Window arrangement uses the primary (menu-bar) display as the vertical origin, so a display above that screen stays aligned.
- Mission Control itself is unchanged when motion is turned off.

## License

MIT — see [LICENSE](LICENSE).
