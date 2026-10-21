import Foundation

public enum CubismParameters {
    public static func values(pose: RigPose, motion m: PuppetMotion) -> [String:Float] {
        func open(_ left: Bool) -> Float {
            let w = left ? m.leftHand : m.rightHand
            return PuppetMotion.smooth(0.8,1,max(w.x,w.y,w.z,w.w,left ? m.leftFist : m.rightFist,left ? 0 : m.rightChin))
        }
        return ["ParamAngleX":m.headShift.x*10,"ParamAngleY":-m.headShift.y*4,
            "ParamAngleZ":m.head*180 / .pi,"ParamBodyAngleZ":m.torso*180 / .pi,
            "ParamBreath":(pose.breath+1)/2,"ParamEyeLOpen":1-pose.blink,
            "ParamEyeROpen":1-pose.blink,"ParamMouthOpenY":pose.mouthAmount,
            "ParamEyeBallX":max(-1,min(1,pose.lookX+FaceRig.attention(pose.time).x)),
            "ParamEyeBallY":max(-1,min(1,pose.lookY+FaceRig.attention(pose.time).y)),
            "ParamBrowLY":pose.resolvedGesture == .think ? 0.35 : (pose.speaking ? 0.2*Float(sin(pose.time*2.7)) : 0),
            "ParamBrowRY":pose.resolvedGesture == .think ? -0.15 : (pose.speaking ? 0.15*Float(sin(pose.time*2.7-0.3)) : 0),
            "ParamMouthForm":pose.speaking ? 0.25 : 0,
            "ParamHairFront":0,"ParamHairBack":0,
            "ParamShoulderL":m.leftShoulder,"ParamShoulderR":m.rightShoulder,
            "ParamElbowL":m.leftElbow,"ParamElbowR":m.rightElbow,"ParamWristL":m.leftWrist,"ParamWristR":m.rightWrist,
            "ParamHandL":Float(HandPresentation(motion:m,left:true).index),"ParamHandR":Float(HandPresentation(motion:m,left:false).index),
            "ParamHandOpenL":open(true),"ParamHandOpenR":open(false),
            "ParamHandCloseL":HandPresentation(motion:m,left:true).closure,"ParamHandCloseR":HandPresentation(motion:m,left:false).closure,"ParamThought":m.thoughtOpacity,"ParamTorsoLift":m.torsoLift]
    }
}
