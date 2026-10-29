import AppKit

// Explicit bootstrap: `@main` on AppDelegate alone is unreliable for LSUIElement
// agent apps (delegate can fail to attach; then no menu bar item appears).
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
ProcessInfo.processInfo.disableAutomaticTermination("Altitude menu bar agent")
app.run()
