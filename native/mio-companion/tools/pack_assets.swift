// Deterministic atlas slicing only; artwork comes from imagegen, never colour-keyed.
import AppKit
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let input = root.appendingPathComponent("art/live2d/mio/parts-atlas.png")
let out = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let crops: [(String, CGRect, [Double], String)] = [
    ("body", CGRect(x: 35, y: 0, width: 385, height: 600), [65, 252, 470, 730], "body"),
    ("hair_back", CGRect(x: 444, y: 55, width: 445, height: 530), [176, 36, 248, 260], "hair"),
    ("face", CGRect(x: 945, y: 155, width: 350, height: 322), [214, 92, 172, 180], "head"),
    ("hair_front", CGRect(x: 1320, y: 60, width: 454, height: 535), [176, 36, 248, 260], "hair"),
    ("eyes_open", CGRect(x: 20, y: 630, width: 419, height: 216), [242, 158, 116, 44.64], "eyes_open"),
    ("eyes_closed", CGRect(x: 475, y: 632, width: 400, height: 190), [242, 158, 116, 39.42], "eyes_closed"),
    ("mouth_closed", CGRect(x: 1010, y: 715, width: 220, height: 110), [282, 229.2, 36, 9.6], "mouth_closed"),
    ("mouth_open", CGRect(x: 1460, y: 685, width: 180, height: 145), [289, 227.7, 22, 12.6], "mouth_open")
]
var layers: [[String: Any]] = []
for (name, crop, rect, group) in crops {
    let part = atlas.cropping(to: crop)!
    let width = part.width, height = part.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    bytes.withUnsafeMutableBytes { ptr in
        let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var x0 = width, y0 = height, x1 = 0, y1 = 0
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        // Quantization dust in the generated alpha is not part of the sprite.
        if bytes[i + 3] < 12 { bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0 }
        if bytes[i + 3] > 32 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
    } }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: width * 4, space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    // CGImage cropping uses top-left image coordinates; byte rows already preserve source orientation.
    let trimmed = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))!
    let path = out.appendingPathComponent(name + ".png")
    let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, trimmed, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    layers.append(["id": name, "texture": name + ".png", "rect": rect, "group": group,
                   "sourceCrop": [crop.minX, crop.minY, crop.width, crop.height]])
    print("\(name): \(trimmed.width)x\(trimmed.height)")
}
let order = ["hair_back", "body", "face", "eyes_open", "eyes_closed", "mouth_closed", "mouth_open", "hair_front"]
layers.sort { order.firstIndex(of: $0["id"] as! String)! < order.firstIndex(of: $1["id"] as! String)! }
let manifest: [String: Any] = ["format": "harumachi-layer-rig", "version": 1, "name": "澪", "canvas": [600, 1000],
                              "layoutRevision": "20261020-face-proportions-v2",
                              "cubismCompatible": false, "layers": layers,
                              "parameters": ["ParamAngleX", "ParamAngleY", "ParamBodyAngleZ", "ParamBreath", "ParamEyeLOpen", "ParamEyeROpen", "ParamMouthOpenY"]]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Mio.rig.json"))
try json.write(to: root.appendingPathComponent("art/live2d/mio/Mio.rig.json"))
