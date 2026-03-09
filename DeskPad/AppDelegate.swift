import Cocoa
import Darwin
import QuartzCore
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

private struct AppSettings: Codable, Equatable {
    let version: Int
    let refreshRate: Int
    let inUseIndicator: InUseIndicatorStyle
    let preferredDisplayMode: VirtualDisplayModeSize?
    let windowFrame: SavedWindowFrame?
    let isWindowVisible: Bool
    let alwaysOnTop: Bool

    static let `default` = AppSettings(
        version: 1,
        refreshRate: 60,
        inUseIndicator: .warning,
        preferredDisplayMode: nil,
        windowFrame: nil,
        isWindowVisible: true,
        alwaysOnTop: false
    )

    init(
        version: Int,
        refreshRate: Int,
        inUseIndicator: InUseIndicatorStyle,
        preferredDisplayMode: VirtualDisplayModeSize?,
        windowFrame: SavedWindowFrame?,
        isWindowVisible: Bool,
        alwaysOnTop: Bool
    ) {
        self.version = version
        self.refreshRate = refreshRate
        self.inUseIndicator = inUseIndicator
        self.preferredDisplayMode = preferredDisplayMode
        self.windowFrame = windowFrame
        self.isWindowVisible = isWindowVisible
        self.alwaysOnTop = alwaysOnTop
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        refreshRate = try container.decodeIfPresent(Int.self, forKey: .refreshRate) ?? 60
        inUseIndicator = try container.decodeIfPresent(InUseIndicatorStyle.self, forKey: .inUseIndicator) ?? .warning
        preferredDisplayMode = try container.decodeIfPresent(VirtualDisplayModeSize.self, forKey: .preferredDisplayMode)
        windowFrame = try container.decodeIfPresent(SavedWindowFrame.self, forKey: .windowFrame)
        isWindowVisible = try container.decodeIfPresent(Bool.self, forKey: .isWindowVisible) ?? true
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
    }
}

private final class AppSettingsStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSettings {
        let fileURL = settingsFileURL()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            NSLog("DeskPad failed to load settings: %@", String(describing: error))
            return .default
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let directoryURL = settingsDirectoryURL()
            let fileURL = settingsFileURL()
            let tempURL = directoryURL.appendingPathComponent("settings.json.tmp", isDirectory: false)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var data = try encoder.encode(settings)
            data.append(0x0A)
            try data.write(to: tempURL, options: [])
            try atomicallyReplaceItem(at: fileURL, withItemAt: tempURL)
        } catch {
            NSLog("DeskPad failed to save settings: %@", String(describing: error))
        }
    }

    private func settingsDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".DeskPad", isDirectory: true)
    }

    private func settingsFileURL() -> URL {
        settingsDirectoryURL().appendingPathComponent("settings.json", isDirectory: false)
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

private final class TitleBarBackgroundView: NSView {
    private enum DisplayMode {
        case staticColor(NSColor)
        case errorPulse
    }

    private static let inactiveColor = NSColor(named: "TitleBarInactive") ?? .windowBackgroundColor
    private static let errorLowColor = NSColor(calibratedRed: 0.06375, green: 0.0675, blue: 0.075, alpha: 1)
    private static let errorHighColor = NSColor(calibratedRed: 0.78, green: 0.15, blue: 0.18, alpha: 1)

    private var displayMode: DisplayMode = .staticColor(inactiveColor)
    private var pulseTimer: Timer?
    private var pulseStartTime = CACurrentMediaTime()
    var fillColor: NSColor = .init(named: "TitleBarInactive") ?? .windowBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pulseTimer?.invalidate()
    }

    func setStaticFillColor(_ color: NSColor) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        displayMode = .staticColor(color)
        fillColor = color
    }

    func startErrorPulse() {
        guard case .errorPulse = displayMode else {
            displayMode = .errorPulse
            pulseStartTime = CACurrentMediaTime()
            pulseTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.updateErrorPulseColor()
            }
            pulseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            updateErrorPulseColor()
            return
        }

        if pulseTimer == nil {
            pulseStartTime = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.updateErrorPulseColor()
            }
            pulseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    override func draw(_: NSRect) {
        fillColor.setFill()
        bounds.fill()
    }

    private func updateErrorPulseColor() {
        let period = 2.025
        let elapsed = CACurrentMediaTime() - pulseStartTime
        let normalized = (cos((elapsed / period) * .pi * 2 - .pi) + 1) * 0.5
        let color = mixColor(
            from: Self.errorLowColor,
            to: Self.errorHighColor,
            progress: normalized
        )
        fillColor = color
    }

    private func mixColor(from start: NSColor, to end: NSColor, progress: Double) -> NSColor {
        let clamped = CGFloat(min(max(progress, 0), 1))
        guard
            let startComponents = start.usingColorSpace(.deviceRGB),
            let endComponents = end.usingColorSpace(.deviceRGB)
        else {
            return start
        }

        return NSColor(
            calibratedRed: startComponents.redComponent + (endComponents.redComponent - startComponents.redComponent) * clamped,
            green: startComponents.greenComponent + (endComponents.greenComponent - startComponents.greenComponent) * clamped,
            blue: startComponents.blueComponent + (endComponents.blueComponent - startComponents.blueComponent) * clamped,
            alpha: startComponents.alphaComponent + (endComponents.alphaComponent - startComponents.alphaComponent) * clamped
        )
    }
}

private final class DeskPadWindowViewController: NSViewController, NSWindowDelegate {
    static let titleBarHeight: CGFloat = 20
    private let windowControlTopInset: CGFloat = 1
    private let windowControlVerticalOffset: CGFloat = 7
    private let titleBar = TitleBarBackgroundView()
    private let body = NSView()
    private let contentViewController: NSViewController
    private var windowControls = [NSButton]()
    var onWindowFrameChanged: ((CGRect) -> Void)?
    var onWindowWillResize: ((NSWindow, NSSize) -> NSSize)?

    init(contentViewController: NSViewController) {
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleBar.translatesAutoresizingMaskIntoConstraints = false

        body.translatesAutoresizingMaskIntoConstraints = false
        body.wantsLayer = true
        body.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        view.addSubview(body)
        view.addSubview(titleBar)

        addChild(contentViewController)
        let contentView = contentViewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(contentView)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: view.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: Self.titleBarHeight),

            body.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: body.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutWindowControls()
    }

    func installWindowControls(for window: NSWindow) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let controls = buttons.compactMap { window.standardWindowButton($0) }

        guard controls.count == buttons.count else {
            return
        }

        for button in controls {
            button.removeFromSuperview()
            button.translatesAutoresizingMaskIntoConstraints = true
            titleBar.addSubview(button)
        }
        windowControls = controls
        layoutWindowControls()
    }

    func windowDidMove(_: Notification) {
        guard let frame = view.window?.frame else {
            return
        }
        onWindowFrameChanged?(frame)
    }

    func windowDidResize(_: Notification) {
        guard let frame = view.window?.frame else {
            return
        }
        onWindowFrameChanged?(frame)
    }

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        onWindowWillResize?(window, frameSize) ?? frameSize
    }

    private func layoutWindowControls() {
        guard windowControls.isEmpty == false else {
            return
        }

        var currentX: CGFloat = 12
        for button in windowControls {
            let buttonSize = button.frame.size
            let originY = max(0, floor(titleBar.bounds.height - buttonSize.height - windowControlTopInset + windowControlVerticalOffset))
            button.setFrameOrigin(NSPoint(x: currentX, y: originY))
            currentX += buttonSize.width + 6
        }
    }

    func updateTitleBarAppearance(isHighlighted: Bool, style: InUseIndicatorStyle) {
        guard isHighlighted else {
            titleBar.setStaticFillColor(NSColor(named: "TitleBarInactive") ?? .windowBackgroundColor)
            return
        }

        switch style {
        case .info:
            titleBar.setStaticFillColor(NSColor(named: "TitleBarActive") ?? .systemBlue)
        case .warning:
            titleBar.setStaticFillColor(ScreenViewController.warningStripeColor)
        case .error:
            titleBar.startErrorPulse()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    private var screenViewController: ScreenViewController!
    private var deskPadWindowViewController: DeskPadWindowViewController!
    private var refreshRateMenuItem: NSMenuItem!
    private var inUseIndicatorMenuItem: NSMenuItem!
    private var alwaysOnTopMenuItem: NSMenuItem!
    private var refreshRateOptions = [NSMenuItem]()
    private var inUseIndicatorOptions = [NSMenuItem]()
    private let appSettingsStore = AppSettingsStore()
    private var selectedRefreshRate: Int
    private var selectedInUseIndicator: InUseIndicatorStyle
    private var selectedDisplayMode: VirtualDisplayModeSize?
    private var selectedWindowFrame: SavedWindowFrame?
    private var isWindowVisible: Bool
    private var isAlwaysOnTop: Bool
    private let displaySnapshotPublisher = DisplaySnapshotPublisher()
    override init() {
        let settings = appSettingsStore.load()
        selectedRefreshRate = [30, 60].contains(settings.refreshRate) ? settings.refreshRate : AppSettings.default.refreshRate
        selectedInUseIndicator = settings.inUseIndicator
        selectedDisplayMode = settings.preferredDisplayMode
        selectedWindowFrame = settings.windowFrame
        isWindowVisible = settings.isWindowVisible
        isAlwaysOnTop = settings.alwaysOnTop
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let viewController = ScreenViewController()
        viewController.refreshRate = CGFloat(selectedRefreshRate)
        viewController.inUseIndicatorStyle = selectedInUseIndicator
        viewController.preferredDisplayMode = selectedDisplayMode
        viewController.preferredWindowFrame = selectedWindowFrame
        viewController.topContentInset = DeskPadWindowViewController.titleBarHeight
        viewController.isWindowVisible = isWindowVisible
        viewController.onDisplayConfigurationChanged = { [weak self] resolution, scaleFactor in
            self?.didUpdateDisplayConfiguration(resolution: resolution, scaleFactor: scaleFactor)
        }
        viewController.onWindowFrameChanged = { [weak self] frame in
            self?.didUpdateWindowFrame(frame)
        }
        screenViewController = viewController

        let containerViewController = DeskPadWindowViewController(contentViewController: viewController)
        containerViewController.onWindowFrameChanged = { [weak self] frame in
            self?.didUpdateWindowFrame(frame)
        }
        containerViewController.onWindowWillResize = { [weak viewController] window, frameSize in
            viewController?.windowWillResize(window, to: frameSize) ?? frameSize
        }
        viewController.onHighlightStateChanged = { [weak self] isHighlighted in
            self?.deskPadWindowViewController?.updateTitleBarAppearance(
                isHighlighted: isHighlighted,
                style: self?.selectedInUseIndicator ?? .warning
            )
        }
        deskPadWindowViewController = containerViewController

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = containerViewController
        window.delegate = containerViewController
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.backgroundColor = .windowBackgroundColor
        containerViewController.installWindowControls(for: window)
        containerViewController.updateTitleBarAppearance(isHighlighted: false, style: selectedInUseIndicator)
        window.title = "DeskPad"
        window.contentMinSize = CGSize(width: 400, height: 300)
        window.contentMaxSize = CGSize(width: 5120, height: 2160)
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        if let selectedWindowFrame {
            window.setFrame(selectedWindowFrame.cgRect, display: true)
        } else {
            window.center()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "DeskPad")
        let statusMenu = NSMenu()
        statusMenu.addItem(NSMenuItem(title: "", action: #selector(toggleWindow), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Bring Back", action: #selector(bringBackWindow), keyEquivalent: ""))
        statusMenu.addItem(makeAlwaysOnTopMenuItem())
        statusMenu.addItem(makeRefreshRateMenuItem())
        statusMenu.addItem(makeInUseIndicatorMenuItem())
        statusMenu.addItem(NSMenuItem(title: "Quit DeskPad", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        statusItem.menu = statusMenu
        updateWindowVisibilityMenuState()
        applyAlwaysOnTopSetting()
        applyWindowVisibilitySetting()

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
        persistSettings()
    }

    private func makeRefreshRateMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Refresh Rate")

        let options = [30, 60]
        refreshRateOptions = options.map { rate in
            let item = NSMenuItem(
                title: "\(rate) Hz",
                action: #selector(selectRefreshRate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = rate
            submenu.addItem(item)
            return item
        }

        menuItem.submenu = submenu
        refreshRateMenuItem = menuItem
        updateRefreshRateMenuState()
        return menuItem
    }

    private func updateRefreshRateMenuState() {
        refreshRateOptions.forEach { item in
            item.state = item.tag == selectedRefreshRate ? .on : .off
        }
    }

    private func makeInUseIndicatorMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "In Use Indicator", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "In Use Indicator")

        let options: [(title: String, style: InUseIndicatorStyle)] = [
            ("info", .info),
            ("warning", .warning),
            ("error", .error),
        ]
        inUseIndicatorOptions = options.map { option in
            let item = NSMenuItem(
                title: option.title,
                action: #selector(selectInUseIndicator(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.style.rawValue
            submenu.addItem(item)
            return item
        }

        menuItem.submenu = submenu
        inUseIndicatorMenuItem = menuItem
        updateInUseIndicatorMenuState()
        return menuItem
    }

    private func updateInUseIndicatorMenuState() {
        inUseIndicatorOptions.forEach { item in
            let style = InUseIndicatorStyle(rawValue: item.representedObject as? String ?? "")
            item.state = style == selectedInUseIndicator ? .on : .off
        }
    }

    private func makeAlwaysOnTopMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Always On Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        item.target = self
        alwaysOnTopMenuItem = item
        updateAlwaysOnTopMenuState()
        return item
    }

    private func updateAlwaysOnTopMenuState() {
        alwaysOnTopMenuItem?.state = isAlwaysOnTop ? .on : .off
    }

    private func updateWindowVisibilityMenuState() {
        statusItem.menu?.item(at: 0)?.title = isWindowVisible ? "Hide Window" : "Show Window"
    }

    private func applyAlwaysOnTopSetting() {
        window.level = isAlwaysOnTop ? .floating : .normal
    }

    private func applyWindowVisibilitySetting() {
        screenViewController.isWindowVisible = isWindowVisible
        if isWindowVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
        updateWindowVisibilityMenuState()
    }

    @objc private func selectRefreshRate(_ sender: NSMenuItem) {
        guard sender.tag != selectedRefreshRate else {
            return
        }

        selectedRefreshRate = sender.tag
        screenViewController?.refreshRate = CGFloat(selectedRefreshRate)
        updateRefreshRateMenuState()
        persistSettings()
    }

    @objc private func selectInUseIndicator(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = InUseIndicatorStyle(rawValue: rawValue),
            style != selectedInUseIndicator
        else {
            return
        }

        selectedInUseIndicator = style
        screenViewController.inUseIndicatorStyle = style
        deskPadWindowViewController.updateTitleBarAppearance(
            isHighlighted: screenViewController.isWindowCurrentlyHighlighted,
            style: selectedInUseIndicator
        )
        updateInUseIndicatorMenuState()
        persistSettings()
    }

    private func persistSettings() {
        appSettingsStore.save(
            AppSettings(
                version: 1,
                refreshRate: selectedRefreshRate,
                inUseIndicator: selectedInUseIndicator,
                preferredDisplayMode: selectedDisplayMode,
                windowFrame: selectedWindowFrame,
                isWindowVisible: isWindowVisible,
                alwaysOnTop: isAlwaysOnTop
            )
        )
    }

    private func didUpdateDisplayConfiguration(resolution: CGSize, scaleFactor: CGFloat) {
        let displayMode = VirtualDisplayModeSize(
            width: UInt(resolution.width * scaleFactor),
            height: UInt(resolution.height * scaleFactor)
        )

        guard selectedDisplayMode != displayMode else {
            return
        }

        selectedDisplayMode = displayMode
        persistSettings()
    }

    private func didUpdateWindowFrame(_ frame: CGRect) {
        let savedFrame = SavedWindowFrame(frame)

        guard selectedWindowFrame != savedFrame else {
            return
        }

        selectedWindowFrame = savedFrame
        persistSettings()
    }

    @objc func toggleWindow() {
        isWindowVisible.toggle()
        applyWindowVisibilitySetting()
        persistSettings()
    }

    @objc private func bringBackWindow() {
        if isWindowVisible == false {
            isWindowVisible = true
            applyWindowVisibilitySetting()
            persistSettings()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        applyAlwaysOnTopSetting()
        updateAlwaysOnTopMenuState()
        persistSettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_: Notification) {
        displaySnapshotPublisher.stop()
    }
}
