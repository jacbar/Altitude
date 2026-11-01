import AppKit

enum AppMenu {
    /// Installs the Altitude + Edit main menu used while an Altitude window is key.
    static func install(target: AnyObject) {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Altitude")
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(MenuBarController.showSettings),
            keyEquivalent: ","
        )
        settings.target = target
        settings.keyEquivalentModifierMask = .command
        appMenu.addItem(settings)

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
