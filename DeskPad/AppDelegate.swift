import Cocoa
import Darwin
import ReSwift

enum AppDelegateAction: Action {
    case didFinishLaunching
}

private struct DisplaySnapshotFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }
}

private struct DisplaySnapshotHost: Codable, Equatable {
    let platform: String
    let hostname: String
}

private struct DisplaySnapshotArrangement: Codable, Equatable {
    let strategy: String
    let orderedDisplayIDs: [UInt32]
}

private struct DisplaySnapshotDisplay: Codable, Equatable {
    let displayID: UInt32
    let arrangementIndex: Int
    let isMain: Bool
    let isBuiltin: Bool
    let lastSeenAt: String
    let frame: DisplaySnapshotFrame
    let visibleFrame: DisplaySnapshotFrame
    let backingScaleFactor: Double
    let localizedName: String?
}

private struct DisplaySnapshotRoot: Codable, Equatable {
    let version: Int
    let generatedAt: String
    let host: DisplaySnapshotHost
    let activeDisplayID: UInt32?
    let mainDisplayID: UInt32
    let arrangement: DisplaySnapshotArrangement
    let displays: [DisplaySnapshotDisplay]
}

private struct DisplaySnapshotSignature: Equatable {
    struct Display: Equatable {
        let displayID: UInt32
        let arrangementIndex: Int
        let isMain: Bool
        let isBuiltin: Bool
        let frame: DisplaySnapshotFrame
        let visibleFrame: DisplaySnapshotFrame
        let backingScaleFactor: Double
        let localizedName: String?
    }

    let activeDisplayID: UInt32?
    let mainDisplayID: UInt32
    let orderedDisplayIDs: [UInt32]
    let displays: [Display]
}

private final class DisplaySnapshotPublisher {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    private var screenObserver: NSObjectProtocol?
    private var lastWrittenSignature: DisplaySnapshotSignature?

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func start() {
        guard screenObserver == nil else {
            return
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.writeSnapshotIfNeeded()
        }

        writeSnapshotIfNeeded(force: true)
    }

    func stop() {
        writeSnapshotIfNeeded()

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func writeSnapshotIfNeeded(force: Bool = false) {
        do {
            let snapshot = try makeSnapshot()
            if force == false, snapshot.signature == lastWrittenSignature {
                return
            }

            try write(snapshot.root)
            lastWrittenSignature = snapshot.signature
        } catch {
            NSLog("DeskPad failed to publish displays snapshot: %@", String(describing: error))
        }
    }

    private func makeSnapshot() throws -> (root: DisplaySnapshotRoot, signature: DisplaySnapshotSignature) {
        let generatedAt = timestampFormatter.string(from: Date())
        let mainDisplayID = CGMainDisplayID()
        let activeDisplayID = NSApp.keyWindow?.screen?.displayID ?? mainDisplayID
        let sortedScreens = NSScreen.screens.sorted {
            if $0.frame.minX != $1.frame.minX {
                return $0.frame.minX < $1.frame.minX
            }
            return $0.frame.minY < $1.frame.minY
        }

        let displays = sortedScreens.enumerated().map { index, screen in
            DisplaySnapshotDisplay(
                displayID: screen.displayID,
                arrangementIndex: index,
                isMain: screen.displayID == mainDisplayID,
                isBuiltin: CGDisplayIsBuiltin(screen.displayID) != 0,
                lastSeenAt: generatedAt,
                frame: DisplaySnapshotFrame(screen.frame),
                visibleFrame: DisplaySnapshotFrame(screen.visibleFrame),
                backingScaleFactor: Double(screen.backingScaleFactor),
                localizedName: screen.localizedName
            )
        }
        let orderedDisplayIDs = displays.map(\.displayID)
        let signature = DisplaySnapshotSignature(
            activeDisplayID: activeDisplayID,
            mainDisplayID: mainDisplayID,
            orderedDisplayIDs: orderedDisplayIDs,
            displays: displays.map {
                .init(
                    displayID: $0.displayID,
                    arrangementIndex: $0.arrangementIndex,
                    isMain: $0.isMain,
                    isBuiltin: $0.isBuiltin,
                    frame: $0.frame,
                    visibleFrame: $0.visibleFrame,
                    backingScaleFactor: $0.backingScaleFactor,
                    localizedName: $0.localizedName
                )
            }
        )

        let hostName = {
            let localizedName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let localizedName, localizedName.isEmpty == false {
                return localizedName
            }
            return ProcessInfo.processInfo.hostName
        }()

        let root = DisplaySnapshotRoot(
            version: 1,
            generatedAt: generatedAt,
            host: DisplaySnapshotHost(platform: "macos", hostname: hostName),
            activeDisplayID: activeDisplayID,
            mainDisplayID: mainDisplayID,
            arrangement: DisplaySnapshotArrangement(
                strategy: "frame-origin-left-to-right",
                orderedDisplayIDs: orderedDisplayIDs
            ),
            displays: displays
        )

        return (root: root, signature: signature)
    }

    private func write(_ snapshot: DisplaySnapshotRoot) throws {
        let directoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".DeskPad", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("displays.json", isDirectory: false)
        let tempURL = directoryURL.appendingPathComponent("displays.json.tmp", isDirectory: false)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encodedData(for: snapshot)
        try data.write(to: tempURL, options: [])
        try atomicallyReplaceItem(at: fileURL, withItemAt: tempURL)
    }

    private func encodedData(for snapshot: DisplaySnapshotRoot) throws -> Data {
        var data = try encoder.encode(snapshot)
        data.append(0x0A)
        return data
    }

    private func atomicallyReplaceItem(at destinationURL: URL, withItemAt tempURL: URL) throws {
        let status = tempURL.path.withCString { tempPath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(tempPath, destinationPath)
            }
        }

        guard status == 0 else {
            let code = errno
            try? fileManager.removeItem(at: tempURL)
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [
                    NSLocalizedDescriptionKey: String(cString: strerror(code)),
                ]
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    private let displaySnapshotPublisher = DisplaySnapshotPublisher()

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
        displaySnapshotPublisher.start()
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

    func applicationWillTerminate(_: Notification) {
        displaySnapshotPublisher.stop()
    }
}
