import SwiftUI

/// Visual display arrangement editor — drag displays to reposition
struct DisplayArrangementView: View {
    @ObservedObject var manager: DisplayManager
    @State private var offsets: [CGDirectDisplayID: CGSize] = [:]
    @State private var dragging: CGDirectDisplayID?

    private let scale: CGFloat = 0.08 // scale real pixels to view points

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Arrangement").font(.subheadline.bold())
            Text("Drag to reposition. Changes apply when you release.")
                .font(.caption).foregroundStyle(.secondary)

            ZStack {
                ForEach(manager.displays) { display in
                    let bounds = CGDisplayBounds(display.id)
                    let w = bounds.width * scale
                    let h = bounds.height * scale
                    let baseX = bounds.origin.x * scale
                    let baseY = bounds.origin.y * scale
                    let offset = offsets[display.id] ?? .zero

                    RoundedRectangle(cornerRadius: 6)
                        .fill(display.isBuiltIn ? Color.blue.opacity(0.3) : Color.green.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(dragging == display.id ? Color.accentColor : Color.secondary, lineWidth: dragging == display.id ? 2 : 1)
                        )
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    .font(.caption2)
                                Text(display.name)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                if let mode = display.currentMode {
                                    Text("\(mode.width)×\(mode.height)")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        )
                        .frame(width: w, height: h)
                        .offset(x: baseX + offset.width + 150, y: baseY + offset.height + 50)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragging = display.id
                                    offsets[display.id] = value.translation
                                }
                                .onEnded { value in
                                    dragging = nil
                                    applyArrangement(display: display, translation: value.translation)
                                    offsets[display.id] = .zero
                                }
                        )
                }
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)

            // Mirror controls
            if manager.displays.count > 1 {
                Divider()
                Text("Mirroring").font(.caption.bold())
                ForEach(manager.displays.filter { !$0.isBuiltIn }) { display in
                    HStack {
                        Text(display.name).font(.caption)
                        Spacer()
                        Button("Mirror to Built-in") {
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

    private func applyArrangement(display: DisplayInfo, translation: CGSize) {
        let newX = Int32(CGDisplayBounds(display.id).origin.x + translation.width / scale)
        let newY = Int32(CGDisplayBounds(display.id).origin.y + translation.height / scale)

        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayOrigin(config, display.id, newX, newY)
        CGCompleteDisplayConfiguration(config, .permanently)
        manager.refresh()
    }
}
