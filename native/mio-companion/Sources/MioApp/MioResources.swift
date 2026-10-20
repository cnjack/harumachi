import Foundation

/// SwiftPM's native and Xcode builders place copied folders one level apart.
enum MioResources {
    static func directory(_ name: String) throws -> URL {
        // A packaged app must not depend on the absolute scratch build path
        // embedded in SwiftPM's generated Bundle.module accessor.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("MioCompanion_MioApp.bundle/Resources")
        var roots = packaged.map { [$0] } ?? []
        if !roots.contains(where:{ FileManager.default.fileExists(atPath:$0.path) }), let root = Bundle.module.resourceURL { roots.append(root) }
        for root in roots {
            for url in [root.appendingPathComponent(name),root.appendingPathComponent("Resources/"+name)] {
                if FileManager.default.fileExists(atPath:url.path) { return url }
            }
        }
        throw CocoaError(.fileNoSuchFile,userInfo:[NSFilePathErrorKey:name])
    }
}
