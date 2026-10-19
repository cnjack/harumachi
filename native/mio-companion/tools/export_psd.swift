// Reproducible, uncompressed RGB/8 layered PSD for import into an illustration
// editor or Cubism Editor. This exports source art; it does not fabricate moc3.
import AppKit
import ImageIO

struct Rig: Decodable {
    struct Layer: Decodable { let id: String; let texture: String; let rect: [Double]; let group: String }
    let canvas: [Int]; let layers: [Layer]
}
extension Data {
    mutating func u16(_ n: Int) { append(UInt8((n >> 8) & 255)); append(UInt8(n & 255)) }
    mutating func u32(_ n: Int) { append(UInt8((n >> 24) & 255)); append(UInt8((n >> 16) & 255)); u16(n & 65535) }
    mutating func ascii(_ s: String) { append(contentsOf: s.utf8) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
let rig = try JSONDecoder().decode(Rig.self, from: Data(contentsOf: resources.appendingPathComponent("Mio.rig.json")))
let w = rig.canvas[0], h = rig.canvas[1], count = w * h
let cs = CGColorSpaceCreateDeviceRGB()
func raster(_ layer: Rig.Layer) -> [UInt8] {
    let source = CGImageSourceCreateWithURL(resources.appendingPathComponent(layer.texture) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var bytes = [UInt8](repeating: 0, count: count * 4)
    bytes.withUnsafeMutableBytes { p in
        let context = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = layer.rect
        context.draw(image, in: CGRect(x: r[0], y: Double(h) - r[1] - r[3], width: r[2], height: r[3]))
    }
    return bytes
}
func plane(_ bytes: [UInt8], _ channel: Int, straight: Bool = true) -> Data {
    var data = Data(capacity: count)
    for i in 0..<count {
        let alpha = Int(bytes[i * 4 + 3])
        let value = Int(bytes[i * 4 + channel])
        data.append(UInt8(straight && channel != 3 && alpha > 0 ? min(255, value * 255 / alpha) : value))
    }
    return data
}
let layers = rig.layers.reversed().map { ($0, raster($0)) }
var info = Data(); info.u16(layers.count)
for (layer, _) in layers {
    info.u32(0); info.u32(0); info.u32(h); info.u32(w); info.u16(4)
    for channel in [0, 1, 2, -1] { info.u16(channel & 65535); info.u32(2 + count) }
    info.ascii("8BIMnorm"); info.append(255); info.append(0)
    info.append(["eyes_closed", "mouth_open"].contains(layer.group) ? 2 : 0); info.append(0)
    var extra = Data(); extra.u32(0); extra.u32(0)
    let name = Array(layer.id.utf8); extra.append(UInt8(name.count)); extra.append(contentsOf: name)
    while extra.count % 4 != 0 { extra.append(0) }
    info.u32(extra.count); info.append(extra)
}
for (_, bytes) in layers {
    for channel in [0,1,2,3] { info.u16(0); info.append(plane(bytes, channel)) }
}
if info.count % 2 != 0 { info.append(0) }
var layerMask = Data(); layerMask.u32(info.count); layerMask.append(info); layerMask.u32(0)
var psd = Data(); psd.ascii("8BPS"); psd.u16(1); psd.append(contentsOf: [UInt8](repeating: 0, count: 6))
psd.u16(4); psd.u32(h); psd.u32(w); psd.u16(8); psd.u16(3)
psd.u32(0); psd.u32(0); psd.u32(layerMask.count); psd.append(layerMask)
var composite = [UInt8](repeating: 0, count: count * 4)
for (layer, bytes) in layers.reversed() where !["eyes_closed", "mouth_open"].contains(layer.group) {
    for i in 0..<count {
        let src = i * 4, a = Int(bytes[src + 3])
        for c in 0..<4 { composite[src+c] = UInt8(min(255, Int(bytes[src+c]) + Int(composite[src+c]) * (255-a) / 255)) }
    }
}
psd.u16(0)
for channel in [0,1,2,3] { psd.append(plane(composite, channel)) }
let output = root.appendingPathComponent("art/live2d/mio/Mio.layers.psd")
try psd.write(to: output)
print("Layered RGB/8 PSD: \(output.path) (\(layers.count) layers)")
// Optional independent system ImageIO decoder proof of the merged PSD image.
if CommandLine.arguments.count > 2 {
    let preview = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
          let merged = CGImageSourceCreateImageAtIndex(source, 0, nil), merged.width == w, merged.height == h,
          let destination = CGImageDestinationCreateWithURL(preview as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("System PSD decoder rejected output")
    }
    CGImageDestinationAddImage(destination, merged, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PSD preview export failed") }
    print("System ImageIO decoded PSD composite: \(preview.path)")
}
