import AppKit
import MetalKit
import MioCore

struct RigDescription: Decodable {
    struct Layer: Decodable {
        let id: String; let texture: String; let rect: [Float]; let group: String
        let joints: [[Float]]?
        let bendSpans: [Float]?
        let variant: String?
        let jointPiece: String?
    }
    let canvas: [Float]
    let origin: [Float]?
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
    var gestureRevision = -1
    var gestureStart: Double = 0
    var lastFrameTime: Double?
    var targetLook = SIMD2<Float>.zero
    private var previousMotion: PuppetMotion?
    func motion(for pose: RigPose) -> PuppetMotion {
        let current = PuppetMotion(pose: pose)
        guard let previousMotion else { return current }
        return current.blended(from: previousMotion, fraction: PuppetMotion.smooth(0, 0.4, Float(pose.time - gestureStart)))
    }
    func selectGesture(_ gesture: CharacterGesture, revision: Int) {
        guard revision != gestureRevision else { return }
        previousMotion = motion(for: pose)
        pose.gesture = gesture; gestureStart = pose.time; pose.gestureTime = 0
        gestureRevision = revision
    }

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
        fragment float4 rig_fragment(O in [[stage_in]], texture2d<float> t [[texture(0)]],
            texture2d<float> palm [[texture(1)]], texture2d<float> back [[texture(2)]],
            texture2d<float> inward [[texture(3)]], texture2d<float> fist [[texture(4)]],
            texture2d<float> chin [[texture(5)]], constant float4 &weights [[buffer(0)]],
            constant float2 &extra [[buffer(1)]], constant float &opacity [[buffer(2)]]) {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float4 c = t.sample(s, in.uv);
            if (weights.x < 0) { c.a *= opacity; return c; }
            // Mix registered drawings in premultiplied space. Drawing six
            // translucent layers separately would make the wrist fade through.
            float4 b = palm.sample(s,in.uv), d = back.sample(s,in.uv), e = inward.sample(s,in.uv);
            float4 f = fist.sample(s,in.uv);
            float4 g = chin.sample(s,in.uv);
            c.rgb *= c.a; b.rgb *= b.a; d.rgb *= d.a; e.rgb *= e.a; f.rgb *= f.a; g.rgb *= g.a;
            float4 out = c*weights.x + b*weights.y + d*weights.z + e*weights.w + f*extra.x + g*extra.y;
            if (out.a > 0.0001) out.rgb /= out.a;
            out.a *= opacity;
            return out;
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
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - (lastFrameTime ?? now)))
        lastFrameTime = now
        if !isPaused {
            pose.time += dt
            let follow = Float(1 - exp(-dt * 7))
            pose.lookX += (targetLook.x - pose.lookX) * follow
            pose.lookY += (targetLook.y - pose.lookY) * follow
        }
        pose.gestureTime = pose.time - gestureStart
        pose.speaking = Date() < speakingUntil || (pose.gesture == .talk && pose.gestureTime < CharacterGesture.talk.duration)
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
        let arm = layer.group.hasPrefix("arm_") || layer.group.hasPrefix("hand_")
        let head = ["head", "hair", "eyes_open", "eyes_closed", "mouth_open", "mouth_closed"].contains(layer.group)
        let motion = motion(for: pose)
        func point(_ u: Float, _ v: Float) -> Vertex {
            var p = SIMD2<Float>(r[0] + r[2] * u, r[1] + r[3] * v)
            if arm, let joints = layer.joints, joints.count == 3 {
                p = motion.armPoint(p, shoulder: SIMD2(joints[0][0], joints[0][1]),
                                    elbow: SIMD2(joints[1][0], joints[1][1]),
                                    wrist: SIMD2(joints[2][0], joints[2][1]), left: layer.group.hasSuffix("_left"),
                                    elbowBendSpan: layer.bendSpans?[0] ?? 104, wristBendSpan: layer.bendSpans?[1] ?? 30,
                                    upperArm:layer.jointPiece.map { $0 == "upper" })
            } else if layer.group == "thought_cloud" {
                p += motion.headShift+SIMD2(motion.head*30,Float(sin(pose.time*2))*1.2)
                p = motion.torsoPoint(p)
            } else if head {
                if layer.group == "hair" {
                    let weight = max(0, (p.y - 95) / 200)
                    p.x += Float(sin(pose.time * 1.6 + Double(v) * 1.5 - 0.3)) * 2.6 * weight
                }
                if layer.group.hasPrefix("eyes") { p.x += pose.lookX * 1.5; p.y -= pose.lookY * 0.6 }
                p = motion.torsoPoint(motion.headPoint(p))
            } else if layer.group.hasPrefix("shoulder_") {
                p = motion.torsoPoint(p)
            } else if layer.group == "lower_body" {
                p = motion.lowerBodyPoint(p)
            } else {
                let upper = max(0, min(1, (750 - p.y) / 500))
                p.y -= pose.breath * 1.5 * upper
                p.x = 300 + (p.x - 300) * (1 + pose.breath * 0.002 * upper)
                p = motion.torsoPoint(motion.neckPoint(p))
            }
            let origin = SIMD2<Float>(rig.origin?[0] ?? 0, rig.origin?[1] ?? 0)
            p = (p - origin) * scale + offset
            return Vertex(position: SIMD2<Float>(p.x / Float(size.width) * 2 - 1, 1 - p.y / Float(size.height) * 2), uv: SIMD2<Float>(u, v))
        }
        var result: [Vertex] = []
        // Denser arm and neck grids resolve joint bends without pulling the torso.
        let columns = arm ? 24 : 20, rows = head ? 24 : 64
        for y in 0..<rows { for x in 0..<columns {
            let u = Float(x) / Float(columns), v = Float(y) / Float(rows)
            let du: Float = 1 / Float(columns), dv: Float = 1 / Float(rows)
            result += [point(u,v), point(u+du,v), point(u,v+dv), point(u+du,v), point(u+du,v+dv), point(u,v+dv)]
        } }
        return result
    }
    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, size: CGSize, pose: RigPose) {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        for layer in rig.layers {
            if let variant = layer.variant, variant != "relaxed" { continue }
            if layer.group == "eyes_open" && pose.blink > 0.5 { continue }
            if layer.group == "eyes_closed" && pose.blink <= 0.5 { continue }
            if layer.group == "mouth_open" && !pose.mouthOpen { continue }
            if layer.group == "mouth_closed" && pose.mouthOpen { continue }
            var opacity: Float = layer.group == "thought_cloud" ? motion(for:pose).thoughtOpacity : 1
            if layer.id == "hand_right_chin_front" { opacity = motion(for:pose).rightChin }
            if opacity < 0.001 { continue }
            let v = vertices(for: layer, size: size, pose: pose)
            guard let buffer = device.makeBuffer(bytes: v, length: v.count * MemoryLayout<Vertex>.stride, options: .storageModeShared) else { continue }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setFragmentTexture(textures[layer.id], index: 0)
            var weights = SIMD4<Float>(-1,0,0,0)
            var extra = SIMD2<Float>.zero
            if layer.group.hasPrefix("hand_") && layer.id != "hand_right_chin_front" {
                let motion = motion(for: pose)
                weights = layer.group == "hand_left" ? motion.leftHand : motion.rightHand
                extra = SIMD2(layer.group == "hand_left" ? motion.leftFist : motion.rightFist,
                              layer.group == "hand_right" ? motion.rightChin : 0)
            }
            for (index, variant) in ["palm","back","inward","fist","chin"].enumerated() {
                encoder.setFragmentTexture(textures[layer.group + "_" + variant] ?? textures[layer.id], index: index+1)
            }
            encoder.setFragmentBytes(&weights, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentBytes(&extra, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setFragmentBytes(&opacity, length:MemoryLayout<Float>.stride,index:2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
        }
        encoder.endEncoding()
    }
    func snapshot(to url: URL, pose: RigPose, width: Int = 750, height: Int = 1000) throws {
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
