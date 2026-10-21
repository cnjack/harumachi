import AppKit
import MetalKit
import MioCore

/// Draws only official Core's updated vertices/UVs/indices. Swift supplies
/// parameter values; all deformation and visibility interpolation is in MOC3.
final class CubismDrawing {
    let model: CubismModel
    let textures: [MTLTexture]
    let device: MTLDevice
    private var hair = HairPhysics()
    init(device: MTLDevice, manifest: URL) throws {
        self.device = device
        model = try CubismModel(manifest:manifest)
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
            pixels.withUnsafeBytes { bytes in texture.replace(region:MTLRegionMake2D(0,0,image.width,image.height),mipmapLevel:0,withBytes:bytes.baseAddress!,bytesPerRow:image.width*4) }
            return texture
        }
    }
    func encode(_ encoder: MTLRenderCommandEncoder,size: CGSize,pose: RigPose,motion: PuppetMotion) throws {
        try model.update(hair.update(CubismParameters.values(pose:pose,motion:motion),time:pose.time))
        let scale = min(Float(size.width)/model.width,Float(size.height)/model.height)
        let offset = SIMD2((Float(size.width)-model.width*scale)/2,(Float(size.height)-model.height*scale)/2)
        for mesh in try model.meshes() where mesh.opacity > 0.001 {
            var vertices: [Vertex] = []
            for i in 0..<mesh.positions.count/2 {
                let p = SIMD2(mesh.positions[2*i],mesh.positions[2*i+1])*scale+offset
                vertices.append(Vertex(position:SIMD2(p.x/Float(size.width)*2-1,1-p.y/Float(size.height)*2),uv:SIMD2(mesh.uvs[2*i],1-mesh.uvs[2*i+1])))
            }
            guard let buffer = device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<Vertex>.stride,options:.storageModeShared),
                  let indices = device.makeBuffer(bytes:mesh.indices,length:mesh.indices.count*MemoryLayout<UInt16>.stride,options:.storageModeShared) else { throw MioRenderer.RenderError.unavailable }
            var opacity = mesh.opacity
            encoder.setVertexBuffer(buffer,offset:0,index:0)
            encoder.setFragmentTexture(textures[mesh.texture],index:0)
            encoder.setFragmentBytes(&opacity,length:MemoryLayout<Float>.stride,index:0)
            encoder.setCullMode(.none)
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:mesh.indices.count,indexType:.uint16,indexBuffer:indices,indexBufferOffset:0)
        }
    }
}
