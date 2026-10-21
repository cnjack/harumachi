// Register the approved eye artwork without repainting or rescaling it.
import Foundation

let root = URL(fileURLWithPath:CommandLine.arguments[1])
let out = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
let source = try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("Mio.rig.json"))) as! [String:Any]
var layers: [[String:Any]] = []
for original in source["layers"] as! [[String:Any]] {
    guard let group = original["group"] as? String,["eyes_open","eyes_closed"].contains(group) else { continue }
    // Left/right name the character's side, matching the original v14 PSD.
    // The PSD baker clips the full original texture at the face centerline.
    for side in ["right","left"] {
        var part = original
        part["id"] = group+"_"+side;part["group"] = group+"_"+side
        part["defaultVisible"] = group == "eyes_open"
        layers.append(part)
    }
}
precondition(layers.count == 4)
try JSONSerialization.data(withJSONObject:layers,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("Face.parts.json"))
print("Registered four original eye layers with unchanged artwork and proportions")
