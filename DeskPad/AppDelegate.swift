import Cocoa
import ReSwift

enum AppDelegateAction: Action {
    case didFinishLaunching
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let viewController = ScreenViewController()
        window = NSWindow(contentViewController: viewController)
        window.delegate = viewController
        window.title = "DeskPad"
        window.makeKeyAndOrderFront(nil)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.backgroundColor = .white
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = CGSize(width: 5120, height: 2160)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "DeskPad")
        let statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "Hide Window", action: #selector(toggleWindow), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Quit DeskPad", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        statusItem.menu = statusMenu

        let mainMenu = NSMenu()
        let mainMenuItem = NSMenuItem()
        let subMenu = NSMenu(title: "MainMenu")
        let quitMenuItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        subMenu.addItem(quitMenuItem)
        mainMenuItem.submenu = subMenu
        mainMenu.items = [mainMenuItem]
        NSApplication.shared.mainMenu = mainMenu

        store.dispatch(AppDelegateAction.didFinishLaunching)
    }

    @objc func toggleWindow() {
        if window.isVisible {
            window.orderOut(nil)
            statusItem.menu?.item(at: 0)?.title = "Show Window"
        } else {
            window.makeKeyAndOrderFront(nil)
            statusItem.menu?.item(at: 0)?.title = "Hide Window"
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return false
    }
}
