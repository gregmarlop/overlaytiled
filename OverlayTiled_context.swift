import AppKit

// MARK: - Utils
func appSupportURL() -> URL {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("OverlayTiled", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
func colorToRGBA(_ c: NSColor) -> [CGFloat] {
    let cc = c.usingColorSpace(.deviceRGB) ?? c
    return [cc.redComponent, cc.greenComponent, cc.blueComponent, cc.alphaComponent]
}
func rgbaToColor(_ a: [CGFloat]) -> NSColor {
    guard a.count == 4 else { return .white }
    return NSColor(deviceRed: a[0], green: a[1], blue: a[2], alpha: a[3])
}

// MARK: - Settings model + persistence
final class OverlaySettings: Codable {
    var text: String = "© COPYRIGHT"
    var angleDeg: CGFloat = -30
    var fontSize: CGFloat = 36
    var opacity: CGFloat = 0.15
    var colorRGBA: [CGFloat] = colorToRGBA(.white)
    var spacing: CGFloat = 24
    var locked: Bool = false
    var windowFrame: CGRect? = nil

    var color: NSColor {
        get { rgbaToColor(colorRGBA) }
        set { colorRGBA = colorToRGBA(newValue) }
    }

    static let storageURL = appSupportURL().appendingPathComponent("settings.json")

    static func load() -> OverlaySettings {
        if let data = try? Data(contentsOf: storageURL),
           let s = try? JSONDecoder().decode(OverlaySettings.self, from: data) {
            return s
        }
        let s = OverlaySettings()
        s.save()
        return s
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.storageURL)
        }
    }
}

// MARK: - Resizable overlay view with tiled, rotated text + context menu
final class TiledOverlayView: NSView {
    let settings: OverlaySettings
    private let borderLayer = CAShapeLayer()
    private let hitPad: CGFloat = 8

    enum DragMode { case none, move, resize(edges: RectEdges) }
    struct RectEdges: OptionSet { let rawValue: Int
        static let left   = RectEdges(rawValue: 1 << 0)
        static let right  = RectEdges(rawValue: 1 << 1)
        static let top    = RectEdges(rawValue: 1 << 2)
        static let bottom = RectEdges(rawValue: 1 << 3)
    }

    private var dragMode: DragMode = .none
    private var dragOriginInScreen: NSPoint = .zero
    private var originalWinFrame: NSRect = .zero

    // weak app delegate for menu actions
    weak var appDelegate: AppDelegate?

    init(frame: NSRect, settings: OverlaySettings) {
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.6).cgColor
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineDashPattern = [6,6]
        borderLayer.lineWidth = 2
        layer?.addSublayer(borderLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        borderLayer.frame = bounds
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        borderLayer.path = path.cgPath
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Clip to rounded rect
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        clipPath.addClip()

        // Rotate around center
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: settings.angleDeg * .pi / 180.0)
        ctx.translateBy(x: -center.x, y: -center.y)

        // Text attributes
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: settings.fontSize),
            .foregroundColor: settings.color.withAlphaComponent(settings.opacity),
            .kern: 1.0
        ]
        let str = NSAttributedString(string: settings.text, attributes: attrs)
        let textSize = str.size()

        // Tile
        let stepX = textSize.width + settings.spacing
        let stepY = textSize.height + settings.spacing

        let inset: CGFloat = max(stepX, stepY) * 2
        let startX: CGFloat = -inset
        let endX: CGFloat = bounds.width + inset
        let startY: CGFloat = -inset
        let endY: CGFloat = bounds.height + inset

        var y = startY
        while y < endY {
            var x = startX
            while x < endX {
                str.draw(at: NSPoint(x: x, y: y))
                x += stepX
            }
            y += stepY
        }
    }

    // Context menu same as menubar
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let app = appDelegate else { return nil }
        return app.buildContextMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = self.menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    // MARK: - Hit testing for resize/move
    private func edgesFor(point p: NSPoint, in rect: NSRect) -> RectEdges {
        var edges: RectEdges = []
        if abs(p.x - rect.minX) <= hitPad { edges.insert(.left) }
        if abs(p.x - rect.maxX) <= hitPad { edges.insert(.right) }
        if abs(p.y - rect.minY) <= hitPad { edges.insert(.bottom) }
        if abs(p.y - rect.maxY) <= hitPad { edges.insert(.top) }
        return edges
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        let locInWin = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        let edges = edgesFor(point: locInWin, in: win.contentLayoutRect)

        dragOriginInScreen = NSEvent.mouseLocation
        originalWinFrame = win.frame

        if settings.locked { dragMode = .none }
        else if !edges.isEmpty { dragMode = .resize(edges: edges) }
        else { dragMode = .move }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let curr = NSEvent.mouseLocation
        let dx = curr.x - dragOriginInScreen.x
        let dy = curr.y - dragOriginInScreen.y

        switch dragMode {
        case .move:
            var f = originalWinFrame
            f.origin.x += dx; f.origin.y += dy
            win.setFrame(f, display: true)

        case .resize(let edges):
            var f = originalWinFrame
            if edges.contains(.left) { f.origin.x += dx; f.size.width -= dx }
            if edges.contains(.right) { f.size.width += dx }
            if edges.contains(.bottom) { f.origin.y += dy; f.size.height -= dy }
            if edges.contains(.top) { f.size.height += dy }
            f.size.width = max(120, f.size.width)
            f.size.height = max(80, f.size.height)
            win.setFrame(f, display: true)

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
        if let w = window {
            settings.windowFrame = w.frame
            settings.save()
        }
    }
}

// MARK: - Overlay window controller
final class OverlayWindowController {
    private let settings: OverlaySettings
    private(set) var window: NSWindow!
    private var view: TiledOverlayView!

    init(settings: OverlaySettings, appDelegate: AppDelegate) {
        self.settings = settings
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let defaultRect = NSRect(x: screen.midX - 240, y: screen.midY - 160, width: 480, height: 320)
        let rect = settings.windowFrame.map { NSRect(x: $0.origin.x, y: $0.origin.y, width: $0.size.width, height: $0.size.height) } ?? defaultRect

        view = TiledOverlayView(frame: rect, settings: settings)
        view.appDelegate = appDelegate

        window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.contentView = view
        window.ignoresMouseEvents = settings.locked
        window.makeKeyAndOrderFront(nil)
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func hide() { window.orderOut(nil) }
    func center() { window.center() }
    func setLocked(_ v: Bool) { window.ignoresMouseEvents = v }
    func refresh() { view.needsDisplay = true }
}

// MARK: - Settings window
final class SettingsWC: NSWindowController {
    private let settings: OverlaySettings
    private let overlay: OverlayWindowController

    private var textField: NSTextField!
    private var angleSlider: NSSlider!
    private var fontSlider: NSSlider!
    private var opacitySlider: NSSlider!
    private var spacingSlider: NSSlider!
    private var colorWell: NSColorWell!
    private var lockCheck: NSButton!

    init(settings: OverlaySettings, overlay: OverlayWindowController) {
        self.settings = settings
        self.overlay = overlay

        let rect = NSRect(x: 0, y: 0, width: 420, height: 280)
        let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Overlay Settings"
        win.center()
        super.init(window: win)

        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Text:"), { let tf = NSTextField(string: ""); self.textField = tf; return tf }()],
            [NSTextField(labelWithString: "Angle (deg):"), { let s = NSSlider(value: -30, minValue: -90, maxValue: 90, target: nil, action: nil); self.angleSlider = s; return s }()],
            [NSTextField(labelWithString: "Font size:"), { let s = NSSlider(value: 36, minValue: 10, maxValue: 120, target: nil, action: nil); self.fontSlider = s; return s }()],
            [NSTextField(labelWithString: "Opacity:"), { let s = NSSlider(value: 0.15, minValue: 0, maxValue: 1, target: nil, action: nil); self.opacitySlider = s; return s }()],
            [NSTextField(labelWithString: "Spacing:"), { let s = NSSlider(value: 24, minValue: 0, maxValue: 80, target: nil, action: nil); self.spacingSlider = s; return s }()],
            [NSTextField(labelWithString: "Color:"), { let c = NSColorWell(); self.colorWell = c; return c }()],
            [NSTextField(labelWithString: "Click-through:"), { let b = NSButton(checkboxWithTitle: "Locked (pass clicks)", target: nil, action: nil); self.lockCheck = b; return b }()],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        content.addSubview(grid)

        let buttons = NSStackView(views: [
            { let btn = NSButton(title: "Center Overlay", target: self, action: #selector(centerOverlay)); return btn }(),
            NSView(),
            { let btn = NSButton(title: "Close", target: self, action: #selector(closeSettings)); return btn }(),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            buttons.heightAnchor.constraint(equalToConstant: 28)
        ])

        for c in [textField as Any, angleSlider as Any, fontSlider as Any, opacitySlider as Any, spacingSlider as Any, colorWell as Any, lockCheck as Any] {
            (c as? NSControl)?.target = self
            (c as? NSControl)?.action = #selector(valueChanged)
        }
    }

    private func loadValues() {
        textField.stringValue = settings.text
        angleSlider.doubleValue = Double(settings.angleDeg)
        fontSlider.doubleValue = Double(settings.fontSize)
        opacitySlider.doubleValue = Double(settings.opacity)
        spacingSlider.doubleValue = Double(settings.spacing)
        colorWell.color = settings.color
        lockCheck.state = settings.locked ? .on : .off
    }

    @objc private func valueChanged(_: Any?) {
        settings.text = textField.stringValue
        settings.angleDeg = CGFloat(angleSlider.doubleValue)
        settings.fontSize = CGFloat(fontSlider.doubleValue)
        settings.opacity = CGFloat(opacitySlider.doubleValue)
        settings.spacing = CGFloat(spacingSlider.doubleValue)
        settings.color = colorWell.color
        settings.locked = (lockCheck.state == .on)
        settings.save()
        overlay.setLocked(settings.locked)
        overlay.refresh()
    }

    @objc private func centerOverlay(_: Any?) { overlay.center() }
    @objc private func closeSettings(_: Any?) { self.close() }
}

// MARK: - Status bar app (About with custom icon + clickable link; overlay right-click menu)
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let version = "1.3"
    let settings = OverlaySettings.load()
    var statusItem: NSStatusItem!
    var overlay: OverlayWindowController!
    var settingsWC: SettingsWC?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if #available(macOS 11.0, *) { btn.image = NSImage(systemSymbolName: "square.on.square.squareshape.controlhandles", accessibilityDescription: "Overlay") }
            else { btn.title = "Ov" }
        }

        overlay = OverlayWindowController(settings: settings, appDelegate: self)
        rebuildMenu()
    }

    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About OverlayTiled…", action: #selector(showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: overlay.window.isVisible ? "Hide Overlay" : "Show Overlay",
                     action: #selector(toggleOverlay(_:)), keyEquivalent: "")
        menu.addItem(withTitle: settings.locked ? "Unlock (disable click-through)" : "Lock (enable click-through)",
                     action: #selector(toggleLock(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Center Overlay", action: #selector(centerOverlay(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")
        return menu
    }

    private func rebuildMenu() {
        statusItem.menu = buildContextMenu()
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "OverlayTiled"
        alert.informativeText = """
Simple overlay watermark tool for macOS.
Version \(Self.version)
© 2025 Gregori Martínez
"""
        // Usa el mismo icono que en la barra de menús; sin “i” azul
        alert.icon = statusItem.button?.image
        alert.alertStyle = .informational

        // Enlace clicable
        let linkField = NSTextField(labelWithString: "")
        linkField.allowsEditingTextAttributes = true
        linkField.isSelectable = true
        let attr = NSMutableAttributedString(string: "Website: gregmarlop.ch")
        attr.addAttribute(.link, value: "https://gregmarlop.ch", range: NSRange(location: 9, length: "gregmarlop.ch".count))
        linkField.attributedStringValue = attr
        alert.accessoryView = linkField

        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleOverlay(_ sender: Any?) {
        if overlay.window.isVisible { overlay.hide() } else { overlay.show() }
        rebuildMenu()
    }
    @objc private func toggleLock(_ sender: Any?) {
        settings.locked.toggle()
        settings.save()
        overlay.setLocked(settings.locked)
        rebuildMenu()
    }
    @objc private func openSettings(_ sender: Any?) {
        if settingsWC == nil { settingsWC = SettingsWC(settings: settings, overlay: overlay) }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func centerOverlay(_ sender: Any?) { overlay.center() }
    @objc private func quitApp(_ sender: Any?) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
