# 小鸟与小猫动画调研（2026-10-04）

## 当前模型与问题

游戏里的 A21 麻雀、A22 坐猫和 A20 睡猫是静态 GLB，没有骨架或动画轨道。麻雀约 11 cm 高，坐猫约 35 cm 高。原实现靠整只鸟的移动、俯仰和左右晃动表现飞行，翅膀不动；猫靠整体缩放呼吸，坐猫会连身体一起转向玩家。这会让动物像移动的摆件，猫爪与墙面的接触也不稳定。

本轮保留原模型和纹理，加入局部动作：麻雀有两个独立翼根和羽片，受惊起飞时振翅，返回时从上方下降；啄食只动头部。坐猫的身体与爪保持原位，只转头、轻微动耳；睡猫只做胸腹呼吸。这些是局部顶点动画与独立部件动画，不能当成完整四足骨架。

实现是 `animal_motion.gd`、`animal_motion.gdshader` 和 `ambient_life.gd`。住宅街新增两处鸟群和两处蝴蝶。截图工具 `living_demo.gd` 会在同一次实际运行中拍摄地面、起飞的连续帧，以及坐猫注视玩家前后的画面。

## 可用方案

| 方案 | 已核实的能力 | 对晴町的用途和限制 |
| --- | --- | --- |
| [Quaternius Ultimate Animated Animal Pack](https://quaternius.com/packs/ultimateanimatedanimals.html) | 作者页写明 12 种动物、每种超过 12 个动作，提供 glTF/FBX/Blend，CC0 | 可参考行走、跳跃等动作的节奏；未下载验证本包是否包含适合本项目的麻雀和猫，不能说能直接套用。外形也需要单独按动漫画风验收 |
| [Blender Rigify](https://docs.blender.org/manual/en/latest/addons/rigging/rigify/basics.html) | 官方基础用法列出 Basic Quadruped 和 Cat 模板 | 适合以后制作站姿猫的四足骨架。现有蜷睡和坐姿模型缺少可展开的腿部形态，硬改成走路会拉扯身体，需要另做站姿模型 |
| [Blender Armature Deform](https://docs.blender.org/manual/en/5.0/animation/armatures/skinning/parenting.html) | 支持自动权重，官方也说明可能发生不合适的变形，需要手工修权重 | 翼根、脖子、耳朵、尾巴应单独验收。自动绑完只证明有权重，不证明动作自然 |
| [Godot 4.7 SkeletonModifier3D](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html) | 修改发生在 AnimationMixer 播放之后，可在已有骨架上叠加局部姿势 | 已用在玩家钓鱼持竿姿势中；将来可用于动物看向玩家与尾巴摆动。它不能给静态网格凭空增加四足动画 |

## 后续完整动画的制作要求

猫需要站姿模型，至少有脊柱、颈头、四腿、尾巴和耳朵；先做 idle、walk、trot、sit、lie_down、wake、stretch、jump、land，再接入靠近、受惊和休息状态。脚底要有接触检查，转弯不能靠旋转整个静止身体。当前坐猫和睡猫继续作为休息姿势，不拿它们硬拉成走路动作。

麻雀的完整骨架应有左右翼根、翼尖、颈头、尾部与脚。起飞要先蹲、蹬地，再开始上升；飞行速度与拍翼频率应分开，落地要减速并收翅。此次独立翼片解决了飞行时没有翅膀动作的问题，但尚未制作完整骨骼版、建筑避让和专门的蹬地动作。

验收以游戏里的近景连续帧为准：观察翼根是否断裂、猫的头颈有没有折痕、爪是否离地、尾巴是否穿墙。研究结果和本轮已经接入的局部动作分开记录；未验证的外部素材不能写成已适配。

实际复核：麻雀起飞连续帧见`evidence/living_town_20261004/native/animal_bird_flight_*.png`，已合成`bird_flight.gif`；坐猫与睡猫的有效近景在`visual-review/placement_cat_side.png`和`placement_sleep_cat.png`。最初两张猫近景被屋檐遮挡，已标记拒收，不作为动画质量证据；截图数字通过不能代替看图。完整猫行走和跳跃仍未交付。

## 后续补充：站姿猫与菜单猫已接入

本轮随后完成两只 Hyper3D 站姿猫、48 关节绑定和 Mesh2Motion 四足动作迁移，橘猫与三花猫已在住宅街实际巡游。正式状态使用 Walk/Idle，跳跃片段仍属于独立预览。菜单按用户要求使用单独绘制的透明 2D 帧动画，不运行 3D 视口。以上补充替代前文“完整猫行走仍未交付”的旧阶段结论；方法、来源和验证边界见 [CAT_MOTION_20261004.md](CAT_MOTION_20261004.md)。
