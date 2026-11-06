# Altitude

<p align="center">
  <img src="docs/branding/altitude-full.png" alt="Altitude" width="560" />
</p>

Opinionated macOS automation inspired by [Space Rabbit](https://space-rabbit.app), [Spaceman](https://github.com/Jaysce/Spaceman), [Reef](https://github.com/gouwsxander/Reef), and [AltTab](https://github.com/lwouis/alt-tab-macos). Altitude is a modular menu-bar agent: desktops, Command-Tab, window management, and app shortcuts. Turn a module off and it does nothing; the status item stays either way.

**Version:** 0.1.0 · **License:** MIT

## What it does

### Desktop

Switch Mission Control desktops and move the focused window with digit hotkeys. The menu bar shows numbered desktop boxes (current Space highlighted); the status menu lists desktops when this module is on.

- Switch — default `⌥` + `1`…`N` (including desktops on other displays; focus moves there best-effort)
- Move focused window — default `⌥⇧` + `1`…`N`
- `disable_motion` — while enabled, skips Space slides for hotkeys, trackpad swipes, Control-Left/Right, and external app activation (Reef, Spotlight, Dock, …), including when the window lives on another display's Space
- `max_space` — highest desktop number with a hotkey (default 9; clamped to 1…9 and existing Spaces)

### Command-Tab

Off by default (system switcher). When on, Altitude shows a still row of open windows — including other Spaces. Accessibility window lists for every running app are collected together, and the switcher stops waiting after 50 ms. An app that has not answered by then is listed from the window server, same as an empty Accessibility result. The row can appear just after the key so the tap stays responsive. Untitled Electron helpers (ChatGPT, Teams, …) collapse to the largest real window; Mail-style CG/AX or weak-title twins collapse to one slot; titled AX floaters/dialogs (e.g. Outlook meeting reminders) can appear, while untitled or app-named ones and system/unknown dialogs stay omitted. Tab / Shift-Tab / arrows move; ⌘Q quits and ⌘H hides the highlighted app; Escape cancels; releasing Command raises and focuses the highlighted window (not the app’s main when that differs). Ten seconds without input cancels; a disabled event tap also cancels. `disable_motion` only skips the slide when landing.

### Window management

Arrange windows on the desktop under the pointer.

- Maximize — default `⌃⌥` + `F`
- Equal split — default `⌃⌥` + `A` (equal columns, left to right)
- `margin` — outer inset and column gap (default 8; clamped 0…256)

### App Shortcuts

Off by default. Map letter or digit chords to apps by bundle ID (as many entries as you configure, capped at 32). On press: if the app is not running, launch it then focus; if it is not frontmost, hop instantly (no Mission Control slide, including other displays/desktops) to that app's current window and focus it; if it is already frontmost, each press focuses the next window of that app and wraps, including windows on other Spaces (same instant hop). A single window stays put. Does not hide-on-refocus, move windows onto the current Space, or replace Command-Tab / Dock / Spotlight. Hops use `switchInstantly` independently of `desktop.disable_motion`. Digit chords that reuse Desktop Switch/Move modifiers (e.g. default `⌥1`) conflict and will not save.

## Always on

- **Settings…** — Cmd+comma; General / Desktop / Command-Tab / Windows / App Shortcuts; writes `config.toml` immediately. Desktop Switch/Move and Windows Maximize/Equal Split use press-to-record (plus **Use Default**); App Shortcuts rows pick an app from `/Applications` + press-to-record; same-tab / cross-module letter-chord conflicts show a red **already in use** message and do not save
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

- `make test` runs **hostless** `AltitudeTests` (`CODE_SIGNING_ALLOWED=NO`): it does not launch `Altitude.app`, write `~/.config/altitude`, touch Login Items, or install event taps. PRs and pushes to `main` run the same unsigned build+test path in GitHub Actions on the arm64 images **macos-26** (macOS 26) and **xcode-27** (macOS 27).
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
# Control-Left/Right, and external activators (Reef, Spotlight, Dock, …) focusing
# an app on another Space — including on another display — jump with no slide
# and no edge bounce. Digit hotkeys also switch desktops on other displays
# (best-effort focus that display, then a dock-swipe on its Space strip).
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

[app_shortcuts]
# When false, no app-jump hotkeys are registered.
enabled = false

# Optional rows (sorted by N; capped at 32):
# [app_shortcuts.entry.1]
# bundle_id = com.apple.Safari
# alt = true
# shift = false
# ctrl = true
# cmd = false
# key = s
```

### Parsing & safety

- Files larger than **64 KB** of resolved bytes, non-UTF-8 contents, or a resolved path outside `$HOME` fail the load (distinct from a missing file). If a config is already in memory, Altitude keeps it; otherwise it uses defaults that cannot be saved and does not change Launch at Login. The status menu shows a disabled **Config was not loaded** line until a successful Reload
- A missing file (including a dangling symlink) uses defaults, may write a starter config, and still reconciles Launch at Login
- Invalid fields inside a readable file keep that field's default; the load still counts as success
- Stow-style symlinks are allowed only when the resolved target stays under `$HOME`; Settings / menu saves write through the symlink to that target and leave the link in place
- Bools accept `true` / `false` / `yes` / `no` / `1` / `0`
- `#` starts a comment to end of line
- A missing or empty shortcut uses the default chord; a missing modifier flag keeps that flag's default
- If either desktop modifier set has no modifiers, or the two sets are equal, both defaults are used (`⌥` / `⌥⇧`)
- A missing, empty, or invalid window key uses that chord's default key; if either resolved window chord has no modifiers, or the two chords are equal, both defaults are used (`⌃⌥F` / `⌃⌥A`)
- `[app_shortcuts.entry.N]` blocks are discovered dynamically, sorted by `N`, and capped at 32; an entry needs a non-empty `bundle_id` and a valid letter or digit `key` (missing modifier flags default to false). Entries with empty modifiers, duplicate chords, Window letter conflicts, or Desktop digit conflicts (same modifiers as Switch/Move with `1`…`9`) are skipped on load
- Unquoted key letters are case-insensitive; a quoted key is invalid. The stored letter is resolved through the active keyboard layout when the hotkey is registered; if that layout has no such key, the chord stays unregistered until the next apply
- Invalid bools/ints keep the field default; unknown keys are ignored
- Old `[spaces]`, `[hotkeys]`, and `[arrange]` sections are ignored

### Settings & menu

- **Settings…** (Cmd+comma) writes `~/.config/altitude/config.toml` immediately and reapplies hotkeys and motion
- Before any Settings or menu save (including Launch at Login), if the on-disk file changed since the last successful load, Altitude reloads it, beeps, refreshes Settings, drops the edit, and does not overwrite the file or change Launch at Login
- While a load has failed, Settings and Launch at Login saves stay locked (beep and redisplay) until a successful **Reload Config**
- **Desktop** tab — Switch/Move record modifiers only (digits 1–9 stay fixed); **Use Default** restores `⌥` / `⌥⇧`
- **Windows** tab — Maximize/Equal Split record a letter chord; **Use Default** restores `⌃⌥F` / `⌃⌥A`
- **App Shortcuts** tab — enable toggle; Add opens an application picker (starts in `/Applications`) and records that app's bundle ID; each row can re-choose the app and record a letter or digit chord; config may still list empty `bundle_id` values from hand edits, which do not register hotkeys
- Same-tab sibling conflicts (App Shortcuts vs Windows letter chords, and App Shortcut digit chords vs Desktop Switch/Move modifiers) beep, revert the control, and show a red **already in use** message (clears on a successful change or when the window redisplays)
- **Open Config…** / **Reload Config** for hand edits; Reload refreshes an open Settings window from disk. A failed Reload keeps memory, shows **Config was not loaded**, and does not reconcile Launch at Login
- **Launch at Login** (menu or General) writes `launch_at_login` immediately; a failed write beeps, leaves the file unchanged, and restores the Login Item
- Reload and relaunch reconcile the Login Item to config (pending approval stays while true, removed when false) except after a failed load
- While macOS waits for Login Items approval, the menu item and General switch stay unchecked; clicking the menu item cancels that pending registration

## Permissions

1. Grant **Accessibility** to Altitude in System Settings → Privacy & Security → Accessibility.
2. Prefer a stable codesign identity (`make` default) so macOS keeps the same trust entry across rebuilds.
3. If hotkeys beep and nothing happens, open the status menu and use the Accessibility item.

## Good to know

- Desktops are numbered 1–9 in Mission Control order across all displays.
- Digit Switch best-effort focuses the target display (raise a window on that Space, else warp + modifier-cleared click on the menu bar) then dock-swipes that display's Space strip; focus can still miss on an empty Space.
- A hotkey that failed to register is tried again on the next reload or Settings save.
- Hotkeys, window arrangement, and App Shortcuts Space hops need Accessibility.
- App Shortcuts leave the target window on its Space (no pull onto the current desktop). Repeating a shortcut while that app is already frontmost cycles its windows, including windows on other Spaces, then wraps. Coming from another app still focuses the window you were last in.
- If a private SkyLight or Accessibility symbol is missing, Altitude skips that operation instead of crashing at launch.
- Window arrangement affects the desktop under the pointer and skips minimized, fullscreen, and other-desktop windows.
- Window arrangement uses the primary (menu-bar) display as the vertical origin, so a display above that screen stays aligned.
- Mission Control itself is unchanged when motion is turned off.

## License

MIT — see [LICENSE](LICENSE).
