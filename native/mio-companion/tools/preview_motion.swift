// Contact sheets for the real Metal frame sequence, including the lift/return
// phases where shoulder foldovers were previously missed.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let names = ["放下", "招手", "思考", "说话"]
let background = NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)
func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 17) {
    (text as NSString).draw(at: NSPoint(x: x, y: y),
        withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.darkGray])
}
func save(_ name: String, size: NSSize, draw: @escaping () -> Void) throws {
    let result = NSImage(size: size, flipped: false) { _ in
        background.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        draw(); return true
    }
    let rep = NSBitmapImageRep(data: result.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
}
func frame(_ index: Int, in directory: URL) -> NSImage {
    NSImage(contentsOf: directory.appendingPathComponent(String(format: "frames/%04d.png", index)))!
}
try save("motion-gallery.png", size: NSSize(width: CGFloat(names.count * 375), height: 1090)) {
    for (row, time) in [30, 75].enumerated() { for col in names.indices {
        let x = CGFloat(col * 375), y = CGFloat((1 - row) * 540)
        frame(col * 210 + time, in: root).draw(in: NSRect(x: x, y: y, width: 375, height: 500))
        label("\(names[col]) · \(Double(time) / 30)s", x: x + 90, y: y + 510)
    } }
}
try save("transition-gallery.png", size: NSSize(width: 2100, height: CGFloat(names.count * 275))) {
    for gesture in names.indices {
        for (col, time) in [0, 8, 15, 30, 75, 137, 201].enumerated() {
            let x = CGFloat(col * 300), y = CGFloat((names.count - 1 - gesture) * 275)
            frame(gesture * 210 + time, in: root).draw(
                in: NSRect(x: x, y: y, width: 300, height: 240),
                from: NSRect(x: 0, y: 400, width: 750, height: 600),
                operation: .sourceOver, fraction: 1)
            label("\(names[gesture]) · \(String(format: "%.2f", Double(time) / 30))s", x: x + 40, y: y + 247, size: 16)
        }
    }
}
if CommandLine.arguments.count > 2 {
    let previous = URL(fileURLWithPath: CommandLine.arguments[2])
    // Resolve each action from its recorded name: old captures can contain a
    // different action order, including motions since removed from the app.
    func recordedFrame(_ gesture: String, in directory: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("attachment-probes.json")),
              let probes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let matching = probes.filter { $0["gesture"] as? String == gesture }
        guard matching.count > 60, let name = matching[60]["frame"] as? String else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent("frames/" + name))
    }
    try save("arm-comparison.png", size: NSSize(width: 1350, height: 820)) {
        for (col, gesture) in ["wave", "think", "talk"].enumerated() {
            for (row, directory) in [previous, root].enumerated() {
                let x = CGFloat(col * 450), y = CGFloat((1 - row) * 410)
                let old = row == 0
                guard let source = recordedFrame(gesture, in: directory) else { continue }
                let width = source.size.width
                source.draw(
                    in: NSRect(x: x + (750-width)*0.3, y: y, width: width * 0.6, height: 360),
                    from: NSRect(x: 0, y: 400, width: width, height: 600),
                    operation: .sourceOver, fraction: 1)
                label("\(old ? "修正前" : "修正后") · \(names[col+1])", x: x + 120, y: y + 377, size: 20)
            }
        }
    }
}
if let before = NSImage(contentsOf: root.appendingPathComponent("thumb-before.png")) {
    try save("thumb-comparison.png", size: NSSize(width: 960, height: 590)) {
        for (col, source) in [before, frame(270, in: root)].enumerated() {
            source.draw(in: NSRect(x: CGFloat(col*480), y: 0, width: 480, height: 540),
                from: NSRect(x: 145, y: 430, width: 505, height: 568),
                operation: .sourceOver, fraction: 1)
            label(col == 0 ? "修正前 · 拇指朝外" : "修正后 · 拇指朝头部",
                x: CGFloat(col*480+135), y: 556, size: 20)
        }
    }
}
