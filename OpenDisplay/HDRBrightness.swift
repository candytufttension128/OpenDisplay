import AppKit
import CoreGraphics
import Metal

/// XDR/HDR brightness control for Apple Silicon MacBook Pro and Pro Display XDR
/// Unlocks brightness beyond the standard 500 nit SDR limit up to 1600 nits
class HDRBrightnessManager: ObservableObject {
    @Published var isHDRCapable = false
    @Published var currentNits: Double = 500
    @Published var maxNits: Double = 1600

    /// Check if a display supports EDR (Extended Dynamic Range)
    func checkHDRCapability(for displayID: CGDirectDisplayID) {
        guard let screen = screen(for: displayID) else { isHDRCapable = false; return }
        isHDRCapable = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
        if isHDRCapable {
            maxNits = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue) * 500.0
        }
    }

    /// Set XDR brightness using a full-screen CAMetalLayer with EDR headroom
    /// nits: 0 to maxNits (typically 1600 for XDR displays)
    func setHDRBrightness(nits: Double, for displayID: CGDirectDisplayID) {
        guard isHDRCapable, let screen = screen(for: displayID) else { return }
        currentNits = max(0, min(maxNits, nits))

        let edrValue = Float(currentNits / 500.0) // 1.0 = 500 nits SDR
        applyEDROverlay(edrValue: edrValue, screen: screen, displayID: displayID)
    }

    /// Reset to standard SDR brightness
    func resetToSDR(for displayID: CGDirectDisplayID) {
        removeOverlay(for: displayID)
        currentNits = 500
    }

    // MARK: - EDR overlay via Metal

    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]

    private func applyEDROverlay(edrValue: Float, screen: NSScreen, displayID: CGDirectDisplayID) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        if overlayWindows[displayID] == nil {
            let window = NSWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hasShadow = false

            let metalLayer = CAMetalLayer()
            metalLayer.device = device
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
            metalLayer.contentsScale = screen.backingScaleFactor

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer = metalLayer
            window.contentView = view

            overlayWindows[displayID] = window
        }

        guard let window = overlayWindows[displayID],
              let metalLayer = window.contentView?.layer as? CAMetalLayer,
              let drawable = metalLayer.nextDrawable(),
              let queue = device.makeCommandQueue(),
              let buffer = queue.makeCommandBuffer() else { return }

        // Set EDR headroom
        metalLayer.edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0, maxLuminance: Float(currentNits), opticalOutputScale: 100)

        // Fill with white at the desired EDR level
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        // EDR value > 1.0 means brighter than SDR white
        desc.colorAttachments[0].clearColor = MTLClearColor(red: Double(edrValue), green: Double(edrValue), blue: Double(edrValue), alpha: 0.01)
        desc.colorAttachments[0].storeAction = .store

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: desc) {
            encoder.endEncoding()
        }
        buffer.present(drawable)
        buffer.commit()

        window.orderFrontRegardless()
    }

    func removeOverlay(for displayID: CGDirectDisplayID) {
        overlayWindows[displayID]?.close()
        overlayWindows.removeValue(forKey: displayID)
    }

    func removeAllOverlays() {
        overlayWindows.values.forEach { $0.close() }
        overlayWindows.removeAll()
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}
