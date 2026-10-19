import AppKit
import MetalKit
import MioCore

struct RigDescription: Decodable {
    struct Layer: Decodable { let id: String; let texture: String; let rect: [Float]; let group: String }
    let canvas: [Float]
    let layers: [Layer]
}
struct Vertex { var position: SIMD2<Float>; var uv: SIMD2<Float> }

final class MioRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let rig: RigDescription
    let textures: [String: MTLTexture]
    let started = ProcessInfo.processInfo.systemUptime
    var pose = RigPose(time: 0)
    var frameCount = 0
    var onFrame: (() -> Void)?
    var isPaused = false
    var speakingUntil = Date.distantPast

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RenderError.unavailable }
        self.queue = queue
        let resources = Bundle.module.resourceURL!.appendingPathComponent("Resources/Mio")
        rig = try JSONDecoder().decode(RigDescription.self, from: Data(contentsOf: resources.appendingPathComponent("Mio.rig.json")))
        var loaded: [String: MTLTexture] = [:]
        let loader = MTKTextureLoader(device: device)
        for layer in rig.layers {
            loaded[layer.id] = try loader.newTexture(URL: resources.appendingPathComponent(layer.texture), options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
        }
        textures = loaded
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 position; float2 uv; };
        struct O { float4 position [[position]]; float2 uv; };
        vertex O rig_vertex(const device V *v [[buffer(0)]], uint id [[vertex_id]]) {
            O out; out.position = float4(v[id].position, 0, 1); out.uv = v[id].uv; return out;
        }
        fragment float4 rig_fragment(O in [[stage_in]], texture2d<float> t [[texture(0)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            return t.sample(s, in.uv);
        }
        """, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "rig_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "rig_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let blend = descriptor.colorAttachments[0]!
        blend.isBlendingEnabled = true
        blend.sourceRGBBlendFactor = .sourceAlpha; blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blend.sourceAlphaBlendFactor = .one; blend.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }
    enum RenderError: Error { case unavailable }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { return }
        if !isPaused { pose.time = ProcessInfo.processInfo.systemUptime - started }
        pose.speaking = Date() < speakingUntil
        encode(command: command, pass: pass, size: view.drawableSize, pose: pose)
        command.present(drawable); command.commit()
        frameCount += 1
        if frameCount % 60 == 0 { onFrame?() }
    }
    func vertices(for layer: RigDescription.Layer, size: CGSize, pose: RigPose) -> [Vertex] {
        let r = layer.rect
        let scale = min(Float(size.width) / rig.canvas[0], Float(size.height) / rig.canvas[1])
        let offset = SIMD2<Float>((Float(size.width) - rig.canvas[0] * scale) / 2,
                                 (Float(size.height) - rig.canvas[1] * scale) / 2)
        let head = layer.group != "body"
        let pivot = SIMD2<Float>(300, 268)
        let angle = head ? (pose.lookX * 0.025 + pose.sway * 0.012 + (pose.mood == .thinking ? -0.035 : 0)) : pose.sway * 0.003
        func point(_ u: Float, _ v: Float) -> Vertex {
            var p = SIMD2<Float>(r[0] + r[2] * u, r[1] + r[3] * v)
            if head {
                p.x += pose.lookX * 5; p.y -= pose.lookY * 3 + pose.breath * 1.5
                if layer.group == "hair" {
                    let weight = max(0, (p.y - 95) / 200)
                    p.x += Float(sin(pose.time * 1.6 + Double(v) * 1.5)) * 2.6 * weight
                }
                if layer.group.hasPrefix("eyes") { p.x += pose.lookX * 1.5; p.y -= pose.lookY * 0.6 }
                let q = p - pivot
                p = SIMD2<Float>(q.x * cos(angle) - q.y * sin(angle), q.x * sin(angle) + q.y * cos(angle)) + pivot
            } else {
                let upper = max(0, min(1, (750 - p.y) / 500))
                p.x += pose.sway * 2 * upper
                p.y -= pose.breath * 2.5 * upper
                p.x = 300 + (p.x - 300) * (1 + pose.breath * 0.002 * upper)
            }
            p = p * scale + offset
            return Vertex(position: SIMD2<Float>(p.x / Float(size.width) * 2 - 1, 1 - p.y / Float(size.height) * 2), uv: SIMD2<Float>(u, v))
        }
        var result: [Vertex] = []
        // A deformable 12 x 16 mesh per drawable; no full-frame texture warping.
        for y in 0..<16 { for x in 0..<12 {
            let u = Float(x) / 12, v = Float(y) / 16, du: Float = 1 / 12, dv: Float = 1 / 16
            result += [point(u,v), point(u+du,v), point(u,v+dv), point(u+du,v), point(u+du,v+dv), point(u,v+dv)]
        } }
        return result
    }
    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, size: CGSize, pose: RigPose) {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        for layer in rig.layers {
            if layer.group == "eyes_open" && pose.blink > 0.5 { continue }
            if layer.group == "eyes_closed" && pose.blink <= 0.5 { continue }
            if layer.group == "mouth_open" && !pose.mouthOpen { continue }
            if layer.group == "mouth_closed" && pose.mouthOpen { continue }
            let v = vertices(for: layer, size: size, pose: pose)
            guard let buffer = device.makeBuffer(bytes: v, length: v.count * MemoryLayout<Vertex>.stride, options: .storageModeShared) else { continue }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentTexture(textures[layer.id], index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
        }
        encoder.endEncoding()
    }
    func snapshot(to url: URL, pose: RigPose, width: Int = 600, height: Int = 1000) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else { throw RenderError.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture; pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store; pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        encode(command: command, pass: pass, size: CGSize(width: width, height: height), pose: pose)
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { throw RenderError.unavailable }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
