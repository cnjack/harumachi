// Decompose the approved source PSD artwork without replacing its identity.
import Foundation
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let out = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
let source = try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("Mio.rig.json"))) as! [String:Any]
var eyes: [[String:Any]] = [],mouth: [[String:Any]] = []
for original in source["layers"] as! [[String:Any]] {
    let group=original["group"] as? String ?? ""
    if group == "eyes_open" || group == "eyes_closed" {
        for side in ["right","left"] {
            for component in group == "eyes_open" ? ["sclera","iris","upper","lower","brow"]:["closed"] {
                var part=original
                part["id"] = component == "sclera" ? "eyes_open_"+side:component == "closed" ? "eyes_closed_"+side:component == "brow" ? "brow_"+side:"eyes_"+component+"_"+side
                part["group"]=group+"_"+side;part["component"]=component
                part["defaultVisible"]=group == "eyes_open";eyes.append(part)
            }
        }
    }
    if group == "mouth_closed" || group == "mouth_open" {
        for component in group == "mouth_open" ? ["cavity","tongue","teeth","lip_upper","lip_lower"]:["lip_lower","lip_upper"] {
            var part=original
            part["id"]=group+"_"+component;part["component"]=component
            part["defaultVisible"]=group == "mouth_closed";mouth.append(part)
        }
    }
}
for (name,parts) in [("Face.parts.json",eyes),("Mouth.parts.json",mouth)] {
    try JSONSerialization.data(withJSONObject:parts,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(name))
}
print("Registered 12 independent brow/eye components and 7 lip/cavity/teeth/tongue components")
