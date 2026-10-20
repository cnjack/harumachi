import Foundation
import Darwin

/// Official Cubism Core ABI. Core remains an external, separately licensed
/// installation. Never fall back to treating a custom rig as a MOC model.
public final class CubismModel {
    public struct Failure: LocalizedError {
        public let message: String
        public init(message: String) { self.message = message }
        public var errorDescription: String? { message }
    }
    public struct Parameter { public let id: String; public let minimum, maximum, value: Float }
    public struct Mesh {
        public let id: String; public let positions, uvs: [Float]; public let indices: [UInt16]
        public let texture, order: Int; public let opacity: Float
    }
    public struct Manifest: Decodable {
        public struct References: Decodable {
            public let Moc: String; public let Textures: [String]
        }
        public let Version: Int; public let FileReferences: References
    }
    private typealias GetInt = @convention(c) (UnsafeRawPointer?) -> Int32
    private typealias GetPointer = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    private typealias GetSize = @convention(c) (UnsafeRawPointer?) -> UInt32
    private typealias MocFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
    private typealias Check = @convention(c) (UnsafeRawPointer?, UInt32) -> Int32
    private typealias Initialize = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
    private typealias Update = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias Canvas = @convention(c) (UnsafeRawPointer?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> Void
    private var library: UnsafeMutableRawPointer?
    private var mocMemory: UnsafeMutableRawPointer?
    private var modelMemory: UnsafeMutableRawPointer?
    private var model: UnsafeMutableRawPointer?
    public let textureURLs: [URL]
    public private(set) var parameters: [Parameter] = []
    public private(set) var width: Float = 0, height: Float = 0
    public private(set) var coreVersion: UInt32 = 0, mocVersion: UInt32 = 0
    private var origin: [Float] = [0,0], ppu: Float = 1
    private func function<T>(_ name: String, _ type: T.Type) throws -> T {
        guard let address = dlsym(library,name) else { throw Failure(message:"Cubism Core symbol missing: \(name)") }
        return unsafeBitCast(address,to:type)
    }
    public static func resource(_ path: String, inside root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains(":"), !path.contains("\\"),
              !path.split(separator:"/").contains("..") else { throw Failure(message:"Unsafe Cubism resource path: \(path)") }
        let url = root.appendingPathComponent(path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.resolvingSymlinksInPath().path+"/"), FileManager.default.fileExists(atPath:url.path) else {
            throw Failure(message:"Missing Cubism resource: \(path)")
        }
        return url
    }
    public init(manifest url: URL, corePath: String? = nil) throws {
        let manifest = try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:url))
        guard manifest.Version == 3, !manifest.FileReferences.Textures.isEmpty else { throw Failure(message:"Expected Cubism model3 Version 3") }
        let root = url.deletingLastPathComponent()
        textureURLs = try manifest.FileReferences.Textures.map { try Self.resource($0,inside:root) }
        let data = try Data(contentsOf:Self.resource(manifest.FileReferences.Moc,inside:root))
        guard data.count >= 64, data.prefix(4) == Data([77,79,67,51]), data.count <= Int(UInt32.max) else { throw Failure(message:"Invalid MOC3 header or size") }
        let path = corePath ?? ProcessInfo.processInfo.environment["MIO_CUBISM_CORE_PATH"] ?? "/Applications/Live2D Cubism 5.3/res/libLive2DCubismCoreJNI.dylib"
        guard let handle = dlopen(path,RTLD_NOW|RTLD_LOCAL) else { throw Failure(message:"Install Cubism Core or set MIO_CUBISM_CORE_PATH. \(String(cString:dlerror()))") }
        library = handle
        do {
            let buffer = UnsafeMutableRawPointer.allocate(byteCount:data.count,alignment:64);mocMemory = buffer
            data.copyBytes(to:buffer.assumingMemoryBound(to:UInt8.self),count:data.count)
            guard try function("csmHasMocConsistency",Check.self)(buffer,UInt32(data.count)) == 1 else { throw Failure(message:"Official Core rejected MOC3 consistency") }
            coreVersion = try function("csmGetVersion",(@convention(c) () -> UInt32).self)()
            mocVersion = try function("csmGetMocVersion",(@convention(c) (UnsafeRawPointer?, UInt32) -> UInt32).self)(buffer,UInt32(data.count))
            guard let moc = try function("csmReviveMocInPlace",MocFunction.self)(buffer,UInt32(data.count)) else { throw Failure(message:"Cannot revive MOC3") }
            let size = try function("csmGetSizeofModel",GetSize.self)(moc)
            guard size > 0 else { throw Failure(message:"Empty Cubism model") }
            let memory = UnsafeMutableRawPointer.allocate(byteCount:Int(size),alignment:64);modelMemory = memory
            guard let instance = try function("csmInitializeModelInPlace",Initialize.self)(moc,memory,size) else { throw Failure(message:"Cannot initialize Cubism model") }
            model = instance
            var canvas: [Float] = [0,0]
            try function("csmReadCanvasInfo",Canvas.self)(model,&canvas,&origin,&ppu)
            width = canvas[0]*ppu;height = canvas[1]*ppu
            guard width > 0,height > 0,ppu > 0 else { throw Failure(message:"Invalid Cubism canvas") }
            let ids: UnsafePointer<UnsafePointer<CChar>?> = try pointer("csmGetParameterIds")
            let mins: UnsafePointer<Float> = try pointer("csmGetParameterMinimumValues")
            let maxs: UnsafePointer<Float> = try pointer("csmGetParameterMaximumValues")
            let values: UnsafePointer<Float> = try pointer("csmGetParameterDefaultValues")
            for i in 0..<(try count("csmGetParameterCount")) {
                parameters.append(Parameter(id:String(cString:ids[i]!),minimum:mins[i],maximum:maxs[i],value:values[i]))
            }
            let masks: UnsafePointer<Int32> = try pointer("csmGetDrawableMaskCounts")
            let flags: UnsafePointer<UInt8> = try pointer("csmGetDrawableConstantFlags")
            for i in 0..<(try count("csmGetDrawableCount")) {
                // Mio is exported without clipping/additive/multiplicative or
                // inverted masks. Reject unsupported models explicitly.
                guard masks[i] == 0, flags[i]&0x0b == 0 else { throw Failure(message:"This renderer requires unmasked normal-blend Cubism meshes") }
            }
            try update([:])
        } catch {
            modelMemory?.deallocate();modelMemory = nil
            mocMemory?.deallocate();mocMemory = nil
            dlclose(handle);library = nil
            throw error
        }
    }
    deinit { modelMemory?.deallocate();mocMemory?.deallocate();if let library { dlclose(library) } }
    private func count(_ name: String) throws -> Int { Int(try function(name,GetInt.self)(model)) }
    private func pointer<T>(_ name: String) throws -> UnsafePointer<T> {
        guard let p = try function(name,GetPointer.self)(model) else { throw Failure(message:"Core returned no \(name)") }
        return p.assumingMemoryBound(to:T.self)
    }
    public func update(_ values: [String:Float]) throws {
        guard values.values.allSatisfy(\.isFinite) else { throw Failure(message:"Non-finite Cubism parameter") }
        let p: UnsafePointer<Float> = try pointer("csmGetParameterValues")
        let output = UnsafeMutablePointer(mutating:p)
        for (i,parameter) in parameters.enumerated() { output[i] = min(parameter.maximum,max(parameter.minimum,values[parameter.id] ?? parameter.value)) }
        try function("csmUpdateModel",Update.self)(model)
    }
    public func meshes() throws -> [Mesh] {
        let ids: UnsafePointer<UnsafePointer<CChar>?> = try pointer("csmGetDrawableIds")
        let positions: UnsafePointer<UnsafePointer<Float>?> = try pointer("csmGetDrawableVertexPositions")
        let uvs: UnsafePointer<UnsafePointer<Float>?> = try pointer("csmGetDrawableVertexUvs")
        let vertices: UnsafePointer<Int32> = try pointer("csmGetDrawableVertexCounts")
        let indices: UnsafePointer<UnsafePointer<UInt16>?> = try pointer("csmGetDrawableIndices")
        let counts: UnsafePointer<Int32> = try pointer("csmGetDrawableIndexCounts")
        let textures: UnsafePointer<Int32> = try pointer("csmGetDrawableTextureIndices")
        // Core 6 combines drawable/offscreen render orders. Mio has no
        // offscreens; its authored drawable order also defines the full order.
        let orderAPI = dlsym(library,"csmGetDrawableRenderOrders") == nil ? "csmGetDrawableDrawOrders" : "csmGetDrawableRenderOrders"
        let orders: UnsafePointer<Int32> = try pointer(orderAPI)
        let opacities: UnsafePointer<Float> = try pointer("csmGetDrawableOpacities")
        return try (0..<(try count("csmGetDrawableCount"))).map { i in
            guard let points = positions[i],let tex = uvs[i],let triangles = indices[i],Int(textures[i]) >= 0,Int(textures[i]) < textureURLs.count else { throw Failure(message:"Invalid drawable buffers") }
            guard (0..<Int(counts[i])).allSatisfy({ Int(triangles[$0]) < Int(vertices[i]) }) else { throw Failure(message:"Drawable index exceeds vertex count") }
            var canvas: [Float] = []
            for v in 0..<Int(vertices[i]) { canvas += [points[2*v]*ppu+origin[0],height-(points[2*v+1]*ppu+origin[1])] }
            guard canvas.allSatisfy(\.isFinite),opacities[i].isFinite else { throw Failure(message:"Non-finite Core output") }
            return Mesh(id:String(cString:ids[i]!),positions:canvas,uvs:Array(UnsafeBufferPointer(start:tex,count:Int(vertices[i])*2)),indices:Array(UnsafeBufferPointer(start:triangles,count:Int(counts[i]))),texture:Int(textures[i]),order:Int(orders[i]),opacity:opacities[i])
        }.sorted { $0.order < $1.order }
    }
}
