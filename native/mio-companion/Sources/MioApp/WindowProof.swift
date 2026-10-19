import AppKit
import MetalKit

// Export ONLY this app's own view tree and its own Metal render targets. This
// never reads the display or any other window and needs no screen-capture grant.
@MainActor func saveOwnWindow(_ window: NSWindow, to url: URL) throws {
    guard let root = window.contentView,
          let cached = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    root.cacheDisplay(in: root.bounds, to: cached)
    var overlays: [(NSRect, NSImage)] = []
    func visit(_ view: NSView) throws {
        if let metal = view as? MTKView, let renderer = metal.delegate as? MioRenderer {
            let frame = root.convert(metal.bounds, from: metal)
            let tmp = url.deletingLastPathComponent().appendingPathComponent(".gpu-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try renderer.snapshot(to: tmp, pose: renderer.pose, width: max(1, Int(frame.width * 2)), height: max(1, Int(frame.height * 2)))
            if let image = NSImage(contentsOf: tmp) {
                let y = root.isFlipped ? root.bounds.height - frame.maxY : frame.minY
                overlays.append((NSRect(x: frame.minX, y: y, width: frame.width, height: frame.height), image))
            }
        }
        for subview in view.subviews { try visit(subview) }
    }
    try visit(root)
    let image = NSImage(size: root.bounds.size, flipped: false) { rect in
        cached.draw(in: rect)
        for (frame, image) in overlays { image.draw(in: frame) }
        return true
    }
    guard let tiff = image.tiffRepresentation, let output = NSBitmapImageRep(data: tiff),
          let png = output.representation(using: .png, properties: [:]) else { return }
    try png.write(to: url)
}
