import Cocoa
import ReSwift

enum ScreenViewAction: Action {
    case setDisplayID(CGDirectDisplayID)
}

enum InUseIndicatorStyle: String, Codable {
    case info
    case warning
}

struct VirtualDisplayModeSize: Codable, Equatable {
    let width: UInt
    let height: UInt
}

struct SavedWindowFrame: Codable, Equatable {
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

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

class ScreenViewController: SubscriberViewController<ScreenViewData>, NSWindowDelegate {
    static let warningStripeColor = makeWarningStripeColor()

    var refreshRate: CGFloat = 60 {
        didSet {
            guard refreshRate != oldValue else {
                return
            }
            applyDisplaySettings()
        }
    }

    var preferredDisplayMode: VirtualDisplayModeSize? {
        didSet {
            guard preferredDisplayMode != oldValue else {
                return
            }
            applyDisplaySettings()
        }
    }

    var preferredWindowFrame: SavedWindowFrame?
    var topContentInset: CGFloat = 0
    var isWindowCurrentlyHighlighted: Bool {
        isWindowHighlighted
    }

    var inUseIndicatorStyle: InUseIndicatorStyle = .warning {
        didSet {
            guard inUseIndicatorStyle != oldValue else {
                return
            }
            onHighlightStateChanged?(isWindowHighlighted)
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(didClickOnScreen)))
    }

    private var display: CGVirtualDisplay!
    private var stream: CGDisplayStream?
    private var isWindowHighlighted = false
    private var previousResolution: CGSize?
    private var previousScaleFactor: CGFloat?
    var onDisplayConfigurationChanged: ((CGSize, CGFloat) -> Void)?
    var onWindowFrameChanged: ((CGRect) -> Void)?
    var onHighlightStateChanged: ((Bool) -> Void)?
    private var hasRestoredWindowFrame = false

    private static func makeWarningStripeColor() -> NSColor {
        // 7:10 gives a slope of 0.7, which is ~35 degrees and tiles seamlessly.
        let unit = 8
        let tileWidth = 10 * unit
        let tileHeight = 7 * unit
        let phasePeriod = 70.0 * CGFloat(unit)
        let stripePhaseWidth = 34.0 * CGFloat(unit)
        let backgroundColor = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.12, alpha: 1)
        let stripeColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.0975, alpha: 1)
        let backgroundComponents = backgroundColor.usingColorSpace(.deviceRGB)
        let stripeComponents = stripeColor.usingColorSpace(.deviceRGB)

        guard
            let backgroundComponents,
            let stripeComponents,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: tileWidth,
                pixelsHigh: tileHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            return backgroundColor
        }

        let subpixelGrid = 4
        let totalSamples = CGFloat(subpixelGrid * subpixelGrid)

        for y in 0 ..< tileHeight {
            for x in 0 ..< tileWidth {
                var stripeCoverage: CGFloat = 0

                for sampleY in 0 ..< subpixelGrid {
                    for sampleX in 0 ..< subpixelGrid {
                        let samplePointX = CGFloat(x) + (CGFloat(sampleX) + 0.5) / CGFloat(subpixelGrid)
                        let samplePointY = CGFloat(y) + (CGFloat(sampleY) + 0.5) / CGFloat(subpixelGrid)
                        let rawPhase = 7.0 * samplePointX - 10.0 * samplePointY
                        let normalizedPhase = rawPhase.truncatingRemainder(dividingBy: phasePeriod)
                        let wrappedPhase = normalizedPhase >= 0 ? normalizedPhase : normalizedPhase + phasePeriod

                        if wrappedPhase < stripePhaseWidth {
                            stripeCoverage += 1
                        }
                    }
                }

                let blend = stripeCoverage / totalSamples
                let color = NSColor(
                    calibratedRed: backgroundComponents.redComponent + (stripeComponents.redComponent - backgroundComponents.redComponent) * blend,
                    green: backgroundComponents.greenComponent + (stripeComponents.greenComponent - backgroundComponents.greenComponent) * blend,
                    blue: backgroundComponents.blueComponent + (stripeComponents.blueComponent - backgroundComponents.blueComponent) * blend,
                    alpha: 1
                )
                bitmap.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: tileWidth, height: tileHeight))
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return NSColor(patternImage: image)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "DeskPad Display"
        descriptor.maxPixelsWide = 5120
        descriptor.maxPixelsHigh = 2160
        descriptor.sizeInMillimeters = CGSize(width: 1600, height: 1000)
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x3456
        descriptor.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: descriptor)
        store.dispatch(ScreenViewAction.setDisplayID(display.displayID))
        self.display = display
        applyDisplaySettings()
    }

    private func applyDisplaySettings() {
        guard display != nil else {
            return
        }

        let systemResolution = preferredDisplayMode ?? currentSystemResolution()
        let presetModes: [(width: UInt, height: UInt)] = [
            (5120, 1440),
            (5120, 2160),
            (3840, 1600),
            (3440, 1440),
            (3840, 2160),
            (2560, 1440),
            (1920, 1080),
            (1600, 900),
            (1366, 768),
            (1280, 720),
            (2560, 1600),
            (1920, 1200),
            (1680, 1050),
            (1440, 900),
            (1280, 800),
        ]

        var modes = [CGVirtualDisplayMode(
            width: systemResolution.width,
            height: systemResolution.height,
            refreshRate: refreshRate
        )]
        for preset in presetModes {
            if preset.width != systemResolution.width || preset.height != systemResolution.height {
                modes.append(CGVirtualDisplayMode(
                    width: preset.width,
                    height: preset.height,
                    refreshRate: refreshRate
                ))
            }
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = modes
        display.apply(settings)
    }

    private func currentSystemResolution() -> VirtualDisplayModeSize {
        let systemWidth: UInt
        let systemHeight: UInt
        if let mainScreen = NSScreen.main {
            let scale = mainScreen.backingScaleFactor
            systemWidth = UInt(mainScreen.frame.size.width * scale)
            systemHeight = UInt(mainScreen.frame.size.height * scale)
        } else {
            systemWidth = 1920
            systemHeight = 1080
        }
        return VirtualDisplayModeSize(width: systemWidth, height: systemHeight)
    }

    override func update(with viewData: ScreenViewData) {
        if viewData.isWindowHighlighted != isWindowHighlighted {
            isWindowHighlighted = viewData.isWindowHighlighted
            onHighlightStateChanged?(isWindowHighlighted)
            if isWindowHighlighted {
                view.window?.orderFrontRegardless()
            }
        }

        if
            viewData.resolution != .zero,
            viewData.resolution != previousResolution
            || viewData.scaleFactor != previousScaleFactor
        {
            let isFirstConfiguration = previousResolution == nil
            previousResolution = viewData.resolution
            previousScaleFactor = viewData.scaleFactor
            onDisplayConfigurationChanged?(viewData.resolution, viewData.scaleFactor)
            stream = nil
            if let window = view.window {
                let windowContentSize = CGSize(
                    width: viewData.resolution.width,
                    height: viewData.resolution.height + topContentInset
                )
                window.contentAspectRatio = windowContentSize
                if let preferredWindowFrame, hasRestoredWindowFrame == false {
                    window.setFrame(preferredWindowFrame.cgRect, display: true)
                    hasRestoredWindowFrame = true
                } else {
                    window.setContentSize(windowContentSize)
                    if isFirstConfiguration {
                        window.center()
                    }
                }
            }
            let stream = CGDisplayStream(
                dispatchQueueDisplay: display.displayID,
                outputWidth: Int(viewData.resolution.width * viewData.scaleFactor),
                outputHeight: Int(viewData.resolution.height * viewData.scaleFactor),
                pixelFormat: 1_111_970_369,
                properties: [
                    CGDisplayStream.showCursor: true,
                ] as CFDictionary,
                queue: .main,
                handler: { [weak self] _, _, frameSurface, _ in
                    if let surface = frameSurface {
                        self?.view.layer?.contents = surface
                    }
                }
            )
            self.stream = stream
            stream?.start()
        }
    }

    func windowWillResize(_ window: NSWindow, to frameSize: NSSize) -> NSSize {
        let snappingOffset: CGFloat = 30
        let contentSize = window.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard
            let screenResolution = previousResolution,
            abs(contentSize.width - screenResolution.width) < snappingOffset
        else {
            return frameSize
        }
        let adjustedSize = CGSize(width: screenResolution.width, height: screenResolution.height + topContentInset)
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: adjustedSize)).size
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

    @objc private func didClickOnScreen(_ gestureRecognizer: NSGestureRecognizer) {
        guard let screenResolution = previousResolution else {
            return
        }
        let clickedPoint = gestureRecognizer.location(in: view)
        let onScreenPoint = NSPoint(
            x: clickedPoint.x / view.frame.width * screenResolution.width,
            y: (view.frame.height - clickedPoint.y) / view.frame.height * screenResolution.height
        )
        store.dispatch(MouseLocationAction.requestMove(toPoint: onScreenPoint))
    }
}
