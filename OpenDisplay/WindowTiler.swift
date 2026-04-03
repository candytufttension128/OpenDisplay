import AppKit
import CoreGraphics

/// Window tiling manager — snap windows to zones by dragging to screen edges
class WindowTiler {
    static let shared = WindowTiler()

    enum TilePosition: String, CaseIterable {
        case left, right, topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, center, maximize

        func frame(in screen: NSRect) -> NSRect {
            let w = screen.width, h = screen.height
            let x = screen.origin.x, y = screen.origin.y
            switch self {
            case .left:        return NSRect(x: x, y: y, width: w / 2, height: h)
            case .right:       return NSRect(x: x + w / 2, y: y, width: w / 2, height: h)
            case .topLeft:     return NSRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
            case .topRight:    return NSRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
            case .bottomLeft:  return NSRect(x: x, y: y, width: w / 2, height: h / 2)
            case .bottomRight: return NSRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
            case .top:         return NSRect(x: x, y: y + h / 2, width: w, height: h / 2)
            case .bottom:      return NSRect(x: x, y: y, width: w, height: h / 2)
            case .center:      return NSRect(x: x + w * 0.1, y: y + h * 0.1, width: w * 0.8, height: h * 0.8)
            case .maximize:    return screen
            }
        }
    }

    /// Grid layout: tile N windows evenly across a screen
    struct GridLayout {
        let columns: Int
        let rows: Int

        func frames(in screen: NSRect, count: Int) -> [NSRect] {
            let cellW = screen.width / CGFloat(columns)
            let cellH = screen.height / CGFloat(rows)
            return (0..<count).map { i in
                let col = CGFloat(i % columns)
                let row = CGFloat(i / columns)
                return NSRect(
                    x: screen.origin.x + col * cellW,
                    y: screen.origin.y + screen.height - (row + 1) * cellH,
                    width: cellW, height: cellH
                )
            }
        }
    }

    private var monitor: Any?
    private var previewWindow: NSWindow?
    private var dragStartPos: NSPoint?
    private let edgeThreshold: CGFloat = 8

    /// Start monitoring mouse for edge snapping
    func startEdgeSnapping() {
        stopEdgeSnapping()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouse(event)
        }
    }

    func stopEdgeSnapping() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        hidePreview()
    }

    private func handleMouse(_ event: NSEvent) {
        let pos = NSEvent.mouseLocation

        if event.type == .leftMouseUp {
            if let zone = detectZone(at: pos), let win = frontmostWindow() {
                guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) else { return }
                let frame = zone.frame(in: screen.visibleFrame)
                moveWindow(win, to: frame)
            }
            hidePreview(); dragStartPos = nil
            return
        }

        // Dragging — show preview
        if dragStartPos == nil { dragStartPos = pos }
        if let zone = detectZone(at: pos),
           let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) {
            showPreview(frame: zone.frame(in: screen.visibleFrame))
        } else {
            hidePreview()
        }
    }

    private func detectZone(at point: NSPoint) -> TilePosition? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let f = screen.frame
        let left = point.x - f.minX < edgeThreshold
        let right = f.maxX - point.x < edgeThreshold
        let top = f.maxY - point.y < edgeThreshold
        let bottom = point.y - f.minY < edgeThreshold

        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if top { return .maximize }
        return nil
    }

    // MARK: - Preview overlay

    private func showPreview(frame: NSRect) {
        if previewWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .floating; w.isOpaque = false; w.ignoresMouseEvents = true
            w.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2)
            w.hasShadow = false
            w.contentView?.wantsLayer = true
            w.contentView?.layer?.cornerRadius = 10
            w.contentView?.layer?.borderWidth = 2
            w.contentView?.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
            previewWindow = w
        }
        previewWindow?.setFrame(frame, display: true)
        previewWindow?.orderFrontRegardless()
    }

    private func hidePreview() {
        previewWindow?.orderOut(nil)
    }

    // MARK: - Window manipulation via Accessibility API

    private func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else { return nil }
        return (windowRef as! AXUIElement)
    }

    private func moveWindow(_ window: AXUIElement, to frame: NSRect) {
        var pos = CGPoint(x: frame.origin.x, y: NSScreen.screens[0].frame.height - frame.maxY)
        var size = CGSize(width: frame.width, height: frame.height)
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    // MARK: - Grid tiling

    /// Tile all visible windows of the frontmost app in a grid
    func tileWindows(columns: Int, rows: Int) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        guard let screen = NSScreen.main?.visibleFrame else { return }

        let grid = GridLayout(columns: columns, rows: rows)
        let frames = grid.frames(in: screen, count: windows.count)
        for (i, win) in windows.enumerated() where i < frames.count {
            moveWindow(win, to: frames[i])
        }
    }

    /// Tile specific windows by PID into zones
    func tileAllVisibleWindows(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main!
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var allWindows: [AXUIElement] = []

        for app in apps {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let wins = windowsRef as? [AXUIElement] {
                allWindows.append(contentsOf: wins)
            }
        }

        guard !allWindows.isEmpty else { return }
        let cols = Int(ceil(sqrt(Double(allWindows.count))))
        let rows = Int(ceil(Double(allWindows.count) / Double(cols)))
        let grid = GridLayout(columns: cols, rows: rows)
        let frames = grid.frames(in: targetScreen.visibleFrame, count: allWindows.count)
        for (i, win) in allWindows.enumerated() where i < frames.count {
            moveWindow(win, to: frames[i])
        }
    }
}
