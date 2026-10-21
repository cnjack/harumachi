import Foundation

public enum CubismParameters {
    public static func values(pose: RigPose, motion m: PuppetMotion) -> [String:Float] {
        func open(_ left: Bool) -> Float {
            let w = left ? m.leftHand : m.rightHand
            return PuppetMotion.smooth(0.8,1,max(w.x,w.y,w.z,w.w,left ? m.leftFist : m.rightFist,left ? 0 : m.rightChin))
        }
        return ["ParamAngleX":m.headShift.x*10,"ParamAngleY":-m.headShift.y*4,
            "ParamAngleZ":m.head*180 / .pi,"ParamBodyAngleZ":m.torso*180 / .pi,
            "ParamBreath":(pose.breath+1)/2,"ParamEyeLOpen":pose.blink>0.5 ? 0 : 1,
            "ParamEyeROpen":pose.blink>0.5 ? 0 : 1,"ParamMouthOpenY":pose.mouthOpen ? 1 : 0,
            "ParamHairFront":Float(sin(pose.time*1.6-0.3)),"ParamHairBack":Float(sin(pose.time*1.6+0.5)),
            "ParamShoulderL":m.leftShoulder,"ParamShoulderR":m.rightShoulder,
            "ParamElbowL":m.leftElbow,"ParamElbowR":m.rightElbow,"ParamWristL":m.leftWrist,"ParamWristR":m.rightWrist,
            "ParamHandL":Float(HandPresentation(motion:m,left:true).index),"ParamHandR":Float(HandPresentation(motion:m,left:false).index),
            "ParamHandOpenL":open(true),"ParamHandOpenR":open(false),
            "ParamHandCloseL":HandPresentation(motion:m,left:true).closure,"ParamHandCloseR":HandPresentation(motion:m,left:false).closure,"ParamThought":m.thoughtOpacity,"ParamTorsoLift":m.torsoLift]
    }
}
