# Security review — Altitude

Snapshot of the current security posture for the menu bar Space switcher. Document only; product fixes are out of scope for the test-coverage / CI baseline.

## Findings

| Severity | Area | Summary |
|----------|------|---------|
| High | SystemMotionSuppressor | Modifies CGEvent taps (trackpad swipe, Control-arrows, Command-Tab, app activation). Gated by Accessibility permission and `disable_system_motions` in TOML. |
| High | SkyLight / CGS SPI | Private SkyLight and CGS surfaces used for Space enumeration and switching. Undocumented APIs; can break or behave differently across macOS versions. |
| High | DockSwipeSwitcher | Synthetic Dock swipe injection to change Spaces. Relies on Accessibility and Dock gesture behavior. |
| Medium | Config / Launch at Login | `~/.config/altitude/config.toml` (including via symlink) and Launch at Login are a writable control plane for hotkeys, motions, and login registration. |
| Medium | Hotkey / tap teardown | Possible use-after-free risk if Carbon hotkey or CGEvent tap teardown races with callbacks during quit or re-apply. |
| Low / Info | Entitlements | App is unsandboxed (typical for Accessibility + SPI menu bar tools). |
| Low / Info | Config I/O | Config file read is unbounded in size; parse is a small allowlisted TOML subset (no string-exec / injection path). |
| Low / Info | Unused SPI | Some private symbols may be linked or declared without active call sites. |

## Notes

- TOML parsing is intentionally minimal and key-allowlisted; invalid values keep field defaults rather than failing closed into a hard error for the whole file.
- Accessibility is required for switching, window moves, and system-motion suppression. Without it, those paths should not run.
- This document is a baseline for agents and reviewers; it does not assert that High items are accepted forever—only that they are known and tracked.
