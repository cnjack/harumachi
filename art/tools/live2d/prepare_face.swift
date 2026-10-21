// Alpha-preserving registration of imagegen's independent eye components.
import AppKit
import ImageIO

let root = URL(fileURLWithPath:CommandLine.arguments[1])
let source = "art/live2d/mio/face/components-20261021.png"
let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(source) as CFURL,nil)!,0,nil)!
let out = root.appendingPathComponent("native/mio-companion/Sources/MioApp/Resources/Mio")
let crops: [(String,[Int],[Int])] = [
    ("eye_white",[3,169,455,285],[569,169,446,283]),
    ("iris",[158,591,242,264],[624,591,242,264]),
    ("brow",[32,1002,442,137],[555,1003,439,134]),
    ("eye_lid",[40,1266,421,165],[591,1279,402,154])
]
var layers: [[String:Any]] = []
for (name,l,r) in crops {
    for (side,crop) in [("left",l),("right",r)] {
        let center: Double = side == "left" ? 273 : 327
        let rect: [Double]
        switch name {
        case "eye_white": rect = [center-17,200,34,20]
        case "iris": rect = [center-8.5,201,17,18.5]
        case "brow": rect = [center-17,187.5,34,4.8]
        default: rect = [center-17,211.5,34,6.5]
        }
        let part = image.cropping(to:CGRect(x:crop[0],y:crop[1],width:crop[2],height:crop[3]))!
        let file = name+"_"+side+".png"
        let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(file) as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,part,nil)
        precondition(CGImageDestinationFinalize(destination))
        layers.append(["id":name+"_"+side,"group":name+"_"+side,"texture":file,"rect":rect,"sourceAtlas":source,"sourceCrop":crop,"defaultVisible":name != "eye_lid"])
    }
}
try JSONSerialization.data(withJSONObject:layers,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("Face.parts.json"))
print("Registered eight independent face layers, preserving original head scale")
