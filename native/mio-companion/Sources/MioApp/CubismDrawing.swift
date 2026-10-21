import AppKit
import MetalKit
import MioCore

/// Core geometry with reusable buffers and pre-rendered clipping groups.
final class CubismDrawing {
    let model: CubismModel
    let textures: [MTLTexture]
    let device: MTLDevice
    let motions: MotionLibrary
    private var hair: CubismPhysics
    private var expression = EmotionPlayback()
    private var prepared: [CubismModel.Mesh] = []
    private var vertices: [Int:MTLBuffer] = [:]
    private var indices: [Int:MTLBuffer] = [:]
    private var maskTextures: [String:MTLTexture] = [:]
    private var pipelines: [Int:MTLRenderPipelineState] = [:]
    private let maskPipeline: MTLRenderPipelineState
    private var frameSlot = 0
    private var vertexCache: [[Int:MTLBuffer]] = [[:],[:],[:]]
    init(device: MTLDevice, manifest: URL) throws {
        self.device = device
        model = try CubismModel(manifest:manifest)
        hair = try CubismPhysics(data:Data(contentsOf:manifest.deletingLastPathComponent().appendingPathComponent("Mio.physics3.json")),parameters:model.parameters)
        motions = try MotionLibrary(directory:manifest.deletingLastPathComponent())
        textures = try model.textureURLs.map { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw MioRenderer.RenderError.unavailable }
            var pixels = [UInt8](repeating:0,count:image.width*image.height*4)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data:bytes.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:image.width,height:image.height,mipmapped:false)
            descriptor.storageMode = .shared;descriptor.usage = .shaderRead
            guard let texture = device.makeTexture(descriptor:descriptor) else { throw MioRenderer.RenderError.unavailable }
            pixels.withUnsafeBytes { texture.replace(region:MTLRegionMake2D(0,0,image.width,image.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:image.width*4) }
            return texture
        }
        let library = try device.makeLibrary(source:"""
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 position; float2 uv; };
        struct O { float4 position [[position]]; float2 uv; float2 maskUV; };
        vertex O cubism_vertex(const device V *v [[buffer(0)]],uint id [[vertex_id]]) {
            O o;o.position=float4(v[id].position,0,1);o.uv=v[id].uv;
            o.maskUV=float2(v[id].position.x*.5+.5,.5-v[id].position.y*.5);return o;
        }
        fragment float4 cubism_mask(O in [[stage_in]],texture2d<float> image [[texture(0)]]) {
            constexpr sampler s(filter::linear,address::clamp_to_edge);
            float a=image.sample(s,in.uv).a;return float4(a);
        }
        fragment float4 cubism_fragment(O in [[stage_in]],texture2d<float> image [[texture(0)]],
            texture2d<float> mask [[texture(1)]],constant float4 &settings [[buffer(0)]]) {
            constexpr sampler s(filter::linear,address::clamp_to_edge);
            float coverage=1;
            if(settings.y>0.5) { coverage=mask.sample(s,in.maskUV).a;if(settings.z>0.5)coverage=1-coverage; }
            return image.sample(s,in.uv)*settings.x*coverage;
        }
        """,options:nil)
        func make(_ blendMode: Int,mask: Bool = false) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:"cubism_vertex")
            d.fragmentFunction=library.makeFunction(name:mask ? "cubism_mask":"cubism_fragment")
            let a=d.colorAttachments[0]!;a.pixelFormat = .bgra8Unorm;a.isBlendingEnabled=true
            a.sourceRGBBlendFactor = blendMode == 2 ? .destinationColor:.one
            a.destinationRGBBlendFactor = blendMode == 1 ? .one:.oneMinusSourceAlpha
            a.sourceAlphaBlendFactor = .one;a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor:d)
        }
        maskPipeline = try make(0,mask:true)
        for mode in 0...2 { pipelines[mode] = try make(mode) }
    }
    private func key(_ masks: [Int]) -> String { masks.sorted().map(String.init).joined(separator:",") }
    func prepare(_ command: MTLCommandBuffer,size: CGSize,pose: RigPose,motion: PuppetMotion) throws {
        let values = expression.apply(CubismParameters.values(pose:pose,motion:motion),expression:pose.expression ?? EmotionalExpression(style:.from(pose.mood)),time:pose.time,mouthOwned:pose.speaking || pose.speech != nil)
        try model.update(hair.update(values,time:pose.time))
        prepared = try model.meshes()
        let scale=min(Float(size.width)/model.width,Float(size.height)/model.height)
        let offset=SIMD2((Float(size.width)-model.width*scale)/2,(Float(size.height)-model.height*scale)/2)
        frameSlot=(frameSlot+1)%3;vertices=[:]
        for mesh in prepared {
            var data: [Vertex] = []
            for i in 0..<mesh.positions.count/2 {
                let p=SIMD2(mesh.positions[2*i],mesh.positions[2*i+1])*scale+offset
                data.append(Vertex(position:SIMD2(p.x/Float(size.width)*2-1,1-p.y/Float(size.height)*2),uv:SIMD2(mesh.uvs[2*i],1-mesh.uvs[2*i+1])))
            }
            let length=data.count*MemoryLayout<Vertex>.stride
            if vertexCache[frameSlot][mesh.sourceIndex]?.length != length {
                vertexCache[frameSlot][mesh.sourceIndex]=device.makeBuffer(length:max(1,length),options:.storageModeShared)
            }
            guard let buffer=vertexCache[frameSlot][mesh.sourceIndex] else { throw MioRenderer.RenderError.unavailable }
            if length>0 { data.withUnsafeBytes { buffer.contents().copyMemory(from:$0.baseAddress!,byteCount:length) } }
            vertices[mesh.sourceIndex]=buffer
            if indices[mesh.sourceIndex] == nil && !mesh.indices.isEmpty {
                indices[mesh.sourceIndex]=device.makeBuffer(bytes:mesh.indices,length:mesh.indices.count*2,options:.storageModeShared)
            }
        }
        let byIndex=Dictionary(uniqueKeysWithValues:prepared.map { ($0.sourceIndex,$0) })
        let groups=Dictionary(grouping:prepared.filter { !$0.masks.isEmpty },by:{ key($0.masks) })
        for (name,meshes) in groups {
            let width=max(1,Int(size.width)),height=max(1,Int(size.height))
            if maskTextures[name]?.width != width || maskTextures[name]?.height != height {
                let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
                d.usage=[.renderTarget,.shaderRead];d.storageMode = .private;maskTextures[name]=device.makeTexture(descriptor:d)
            }
            guard let texture=maskTextures[name] else { throw MioRenderer.RenderError.unavailable }
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=texture
            pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { throw MioRenderer.RenderError.unavailable }
            encoder.setRenderPipelineState(maskPipeline);encoder.setCullMode(.none)
            for id in meshes[0].masks {
                if let mesh=byIndex[id] { draw(mesh,encoder:encoder) }
            }
            encoder.endEncoding()
        }
    }
    private func draw(_ mesh: CubismModel.Mesh,encoder: MTLRenderCommandEncoder) {
        guard let vertex=vertices[mesh.sourceIndex],let index=indices[mesh.sourceIndex],!mesh.indices.isEmpty else { return }
        encoder.setVertexBuffer(vertex,offset:0,index:0)
        encoder.setFragmentTexture(textures[mesh.texture],index:0)
        encoder.drawIndexedPrimitives(type:.triangle,indexCount:mesh.indices.count,indexType:.uint16,indexBuffer:index,indexBufferOffset:0)
    }
    func encode(_ encoder: MTLRenderCommandEncoder) {
        encoder.setCullMode(.none)
        for mesh in prepared where mesh.opacity > 0.001 {
            encoder.setRenderPipelineState(pipelines[mesh.blendMode] ?? pipelines[0]!)
            let mask=maskTextures[key(mesh.masks)]
            var settings=SIMD4<Float>(mesh.opacity,mask == nil ? 0:1,mesh.invertedMask ? 1:0,0)
            encoder.setFragmentBytes(&settings,length:MemoryLayout<SIMD4<Float>>.stride,index:0)
            encoder.setFragmentTexture(mask ?? textures[mesh.texture],index:1)
            draw(mesh,encoder:encoder)
        }
    }
}
