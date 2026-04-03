import SwiftUI

/// Visual display arrangement editor — drag displays to reposition
struct DisplayArrangementView: View {
    @ObservedObject var manager: DisplayManager
    @State private var offsets: [CGDirectDisplayID: CGSize] = [:]
    @State private var dragging: CGDirectDisplayID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Arrangement").font(.subheadline.bold())
            Text("Drag to reposition. Changes apply when you release.")
                .font(.caption).foregroundStyle(.secondary)

            GeometryReader { geo in
                let viewW = geo.size.width
                let viewH = geo.size.height
                let (scale, originX, originY) = computeLayout(viewW: viewW, viewH: viewH)

                ZStack(alignment: .topLeading) {
                    ForEach(manager.displays) { display in
                        let bounds = CGDisplayBounds(display.id)
                        let w = bounds.width * scale
                        let h = bounds.height * scale
                        let x = (bounds.origin.x * scale) - originX
                        let y = (bounds.origin.y * scale) - originY
                        let offset = offsets[display.id] ?? .zero

                        RoundedRectangle(cornerRadius: 6)
                            .fill(display.isBuiltIn ? Color.blue.opacity(0.25) : Color.green.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(dragging == display.id ? Color.accentColor : Color.secondary.opacity(0.5),
                                            lineWidth: dragging == display.id ? 2 : 1)
                            )
                            .overlay(
                                VStack(spacing: 1) {
                                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                        .font(.system(size: 11))
                                    Text(display.name)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                    if let mode = display.currentMode {
                                        Text("\(mode.width)×\(mode.height)")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            )
                            .frame(width: max(w, 40), height: max(h, 30))
                            .position(x: x + w/2 + offset.width, y: y + h/2 + offset.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragging = display.id
                                        offsets[display.id] = value.translation
                                    }
                                    .onEnded { value in
                                        dragging = nil
                                        applyArrangement(display: display, translation: value.translation, scale: scale)
                                        offsets[display.id] = .zero
                                    }
                            )
                    }
                }
            }
            .frame(height: 180)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // Mirror controls
            if manager.displays.count > 1 {
                Divider()
                Text("Mirroring").font(.caption.bold())
                ForEach(manager.displays.filter { !$0.isBuiltIn }) { display in
                    HStack {
                        Text(display.name).font(.caption).lineLimit(1)
                        Spacer()
                        Button("Mirror") {
                            if let builtIn = manager.displays.first(where: { $0.isBuiltIn }) {
                                manager.setMirror(source: builtIn.id, target: display.id, enabled: true)
                            }
                        }.controlSize(.small)
                        Button("Unmirror") {
                            if let builtIn = manager.displays.first(where: { $0.isBuiltIn }) {
                                manager.setMirror(source: builtIn.id, target: display.id, enabled: false)
                            }
                        }.controlSize(.small)
                    }
                }
            }
        }
    }

    /// Compute scale and origin to fit all displays centered in the view
    private func computeLayout(viewW: CGFloat, viewH: CGFloat) -> (scale: CGFloat, originX: CGFloat, originY: CGFloat) {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        for display in manager.displays {
            let b = CGDisplayBounds(display.id)
            minX = min(minX, b.origin.x)
            minY = min(minY, b.origin.y)
            maxX = max(maxX, b.origin.x + b.width)
            maxY = max(maxY, b.origin.y + b.height)
        }

        let totalW = maxX - minX
        let totalH = maxY - minY
        guard totalW > 0, totalH > 0 else { return (0.05, 0, 0) }

        let padding: CGFloat = 20
        let scaleX = (viewW - padding * 2) / totalW
        let scaleY = (viewH - padding * 2) / totalH
        let scale = min(scaleX, scaleY)

        // Center the displays in the view
        let scaledW = totalW * scale
        let scaledH = totalH * scale
        let originX = minX * scale - (viewW - scaledW) / 2
        let originY = minY * scale - (viewH - scaledH) / 2

        return (scale, originX, originY)
    }

    private func applyArrangement(display: DisplayInfo, translation: CGSize, scale: CGFloat) {
        guard scale > 0 else { return }
        let newX = Int32(CGDisplayBounds(display.id).origin.x + translation.width / scale)
        let newY = Int32(CGDisplayBounds(display.id).origin.y + translation.height / scale)

        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayOrigin(config, display.id, newX, newY)
        CGCompleteDisplayConfiguration(config, .permanently)
        manager.refresh()
    }
}
