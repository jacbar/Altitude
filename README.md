# Altitude

![Altitude](docs/branding/altitude-full.png)

Menu bar agent for macOS with three independent modules: desktops, Command-Tab, and window management. A module that is off does nothing. The status item stays visible either way.

**Version:** 0.1.0 · **License:** MIT

## Features

### Desktop

Switch Mission Control desktops and move the focused window with digit hotkeys. The menu bar shows numbered desktop boxes with the current Space highlighted, and the status menu lists desktops when this module is on.

- **Switch** — default `⌥` + `1`…`N` jumps to desktop N
- **Move focused window** — default `⌥⇧` + `1`…`N` moves the frontmost window to desktop N
- **`enabled = false`** — no digit bindings; the menu does not list desktops; Space-motion suppression for this module is off
- **`disable_motion`** — applies only while desktop is enabled. Makes these instant (no slide, no edge bounce): hotkey space switches, trackpad space swipes, Control-Left/Right, and activating an app that already has a window on another space of the same display
- **`max_space`** — highest desktop number that gets a hotkey (default 9); clamped to 1…9 and to the number of Spaces

### Command-Tab

- **`enabled = false` (default)** — leave the system app switcher alone
- **`enabled = true`** — Altitude window switcher: a still row of open windows (including windows on other Spaces). Tab / Shift-Tab / arrows move the highlight; Command-Q quits and Command-H hides the highlighted app; Escape cancels; release Command to land
- **`disable_motion`** — applies only while Command-Tab is enabled, and only skips the slide when landing on the highlighted window. It does not change trackpad, Control-arrow, or hotkey motion

Both `disable_motion` flags may be on together.

### Window management

Arrange windows on the desktop under the pointer.

- **Maximize** — default `⌃⌥` + `F` maximizes every included window to the same inset visible frame
- **Equal split** — default `⌃⌥` + `A` tiles them in equal columns (full height, left to right)
- **`enabled = false`** — neither chord is registered and nothing is arranged
- **`margin`** — outer inset and gap between columns (default 8, clamped 0…256)

### Always available

- **Settings…** — Cmd+comma opens a Settings window (General, Desktop, Command-Tab, Windows) that edits every current knob and writes `config.toml` immediately. Desktop Switch/Move and Windows Maximize/Equal Split use press-to-record controls (plus **Use Default**); same-tab sibling conflicts show a red **already in use** message and do not save
- **Menu actions** — Settings…; Reload Config; Open Config…; Launch at Login; open Accessibility settings
- **Launch at Login** — checkable menu item and General tab switch (and `[app] launch_at_login` in TOML) register via `SMAppService`; reload/relaunch reconciles the service to config
- **Accessibility-aware** — prompts once for Accessibility; later launches use the menu if permission is missing

## Requirements

- macOS (built as an `LSUIElement` accessory app)
- Xcode / `xcodebuild`
- **Accessibility** permission for Space switching, window moves, and window arrangement
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
make test    # unsigned Domain XCTest suite (no SIGN_ID)
make build   # Debug build into ./build, then codesign
make run     # build and open Altitude.app
make install # force-quit running Altitude, Release-build, install to /Applications, open
make clean   # remove ./build
```

`make install` force-quits every running Altitude instance (AppleScript quit, then `pkill` if needed), builds **Release**, codesigns with `SIGN_ID`, replaces `/Applications/Altitude.app`, and opens it. It does **not** fetch or check out git — you own the working tree before running it.

You can also override without a file: `make SIGN_ID="Apple Development: …" run`.

You can also open `Altitude.xcodeproj` in Xcode and run the **Altitude** scheme (Product → Test exercises `AltitudeTests`).

## Testing

`make test` runs the Altitude scheme’s XCTest target with `CODE_SIGNING_ALLOWED=NO` (no Apple Development identity required). Domain types are compiled into the test bundle; the suite does **not** launch the menu-bar agent, so it does not write `~/.config/altitude/config.toml`, change Login Items, or install event taps. Pull requests targeting `main` run the same unsigned build+test path (plus SwiftLint and coverage) in GitHub Actions (`.github/workflows/ci.yml`).

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

A missing or empty shortcut uses the default chord. A missing modifier flag keeps that flag's default. If either desktop modifier set has no modifiers, or the two sets are equal, both defaults are used. A missing, empty, or invalid window key uses that chord's default key; if the two resolved window chords are equal, both defaults are used. Unquoted key letters are case-insensitive; a quoted key is invalid. Invalid bools/ints keep the field default. Unknown keys are ignored. Old `[spaces]`, `[hotkeys]`, and `[arrange]` keys are not read.

**Settings…** (Cmd+comma) in the status menu — or Cmd+comma while an Altitude window is key — opens the Settings window. Changes there write `~/.config/altitude/config.toml` immediately and reapply hotkeys and motion. On the **Desktop** tab, Switch and Move use the same press-to-record control as Windows (modifiers only — e.g. ⌥ or ⌥⇧ — with digits 1–9 still fixed at runtime); each row has **Use Default** (⌥ / ⌥⇧) and “Followed by 1–9” help. On the **Windows** tab, Maximize and Equal Split record a letter chord the same way, with **Use Default** restoring ⌃⌥F / ⌃⌥A. If a recorded shortcut matches its same-tab sibling (Switch vs Move, or Maximize vs Equal Split), Altitude beeps, reverts the control, and shows a red **already in use** message under that row; the message clears on a successful change or when the window redisplays. TOML schema is unchanged — Desktop still stores modifiers only. **Open Config…** and **Reload Config** remain for hand edits; Reload refreshes an open Settings window from disk. Toggling **Launch at Login** (menu or General tab) writes `launch_at_login` immediately. If that write fails, Altitude beeps, leaves the file unchanged, and puts the Login Item back. Reload and relaunch reconcile the Login Item to the config value, including a registration still waiting for approval: the pending item stays while `launch_at_login` is true, and is removed when it is false. While macOS is waiting for approval in System Settings → General → Login Items, the menu item and General switch stay unchecked; clicking the menu item cancels that pending registration.

## Permissions

1. Grant **Accessibility** to Altitude in System Settings → Privacy & Security → Accessibility.
2. Prefer a stable codesign identity (`make` default) so macOS keeps the same trust entry across rebuilds.
3. If hotkeys beep and nothing happens, open the status menu and use the Accessibility item.

## Good to know

- Desktops are numbered 1–9 in Mission Control order.
- Hotkeys and window arrangement need Accessibility.
- Window arrangement affects the desktop under the pointer and skips minimized, fullscreen, and other-desktop windows.
- Mission Control itself is unchanged when motion is turned off.

## License

MIT — see [LICENSE](LICENSE).
