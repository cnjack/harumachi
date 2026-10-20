// Contact sheets for the real Metal frame sequence, including the lift/return
// phases where shoulder foldovers were previously missed.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let names = ["轻摆", "招手", "伸懒腰", "思考", "说话"]
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
try save("motion-gallery.png", size: NSSize(width: 1875, height: 1090)) {
    for (row, time) in [30, 75].enumerated() { for col in 0..<5 {
        let x = CGFloat(col * 375), y = CGFloat((1 - row) * 540)
        frame(col * 210 + time, in: root).draw(in: NSRect(x: x, y: y, width: 375, height: 500))
        label("\(names[col]) · \(Double(time) / 30)s", x: x + 90, y: y + 510)
    } }
}
try save("transition-gallery.png", size: NSSize(width: 2100, height: 1375)) {
    for gesture in 0..<5 {
        for (col, time) in [0, 8, 15, 30, 75, 137, 201].enumerated() {
            let x = CGFloat(col * 300), y = CGFloat((4 - gesture) * 275)
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
    try save("arm-comparison.png", size: NSSize(width: 1350, height: 820)) {
        for (col, gesture) in [1, 2, 3].enumerated() {
            for (row, directory) in [previous, root].enumerated() {
                let x = CGFloat(col * 450), y = CGFloat((1 - row) * 410)
                let old = row == 0
                let source = frame(gesture * 210 + 60, in: directory)
                let width = source.size.width
                source.draw(
                    in: NSRect(x: x + (750-width)*0.3, y: y, width: width * 0.6, height: 360),
                    from: NSRect(x: 0, y: 400, width: width, height: 600),
                    operation: .sourceOver, fraction: 1)
                label("\(old ? "修正前" : "修正后") · \(names[gesture])", x: x + 120, y: y + 377, size: 20)
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
