# Code quality review — Altitude

Snapshot of maintainability and testability. Document only; product bug fixes beyond a small pure-helper extract are out of scope for the test-coverage / CI baseline.

## Findings

| Severity | Area | Summary |
|----------|------|---------|
| High | Indicator vs backend | SkyLight / Dock prediction can desync the menu bar space indicator from the true current Space. |
| High | `max_space` vs hotkeys | Parser allows `max_space` up to 16, but Carbon digit hotkeys hard-cap at 9. Config and runtime bounds diverge. |
| High | No tests / CI | Domain and helpers had no automated XCTest suite or PR CI before this baseline. |
| Medium | MinimalTOML errors | `ParseError` / throws are largely unused; bad values silently keep per-field defaults. |
| Medium | LaunchAtLogin | Errors from `SMAppService` registration can be swallowed; failures may be hard to notice. |
| Medium | Dead / unused signals | e.g. `moveFailed` (and similar) unused in call sites. |

## Domain-first test ROI

Highest return for unit tests is pure Domain logic:

1. **MinimalTOML / AppConfig** — parsing, clamps, bool synonyms, comments, unknown keys, save-shaped round-trip.
2. **Hotkey space bound helper** — `effectiveMaxHotkeySpace(maxSpace:spaceCount:)` reconciles config `max_space`, live Space count, and the digit-1…9 hard cap.

AX, SkyLight/CGS SPI, Dock swipe, and CGEvent taps need a live macOS session and stay manual / exploratory for now. UI snapshots and integration tests are explicitly out of scope for this baseline.
