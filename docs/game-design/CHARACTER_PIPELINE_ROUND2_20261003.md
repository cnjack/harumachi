# 人物管线第二轮：衣服、肘部与手掌（2026-10-03）

用户反馈第一轮左侧衣服伸手时不自然，右侧走路的手肘与手掌有问题。本轮继续用现有 Hyper3D 素材做定位和对照，没有新提交付费生成，没有替换正式角色。第一轮产物保留。

结论：动作控制确实有可修正的问题；修正手腕方向后，掌心不再一直朝前。手指没有骨骼，张掌姿态仍然保留。衣服尚未找到可直接采用的方案，重新制作的工程代理也未通过外观验收。后续值得比较标准动漫基体与完整指骨，而不是把生成的一整块人物一直当作最终动画网格。

## 本轮实测

对比四列：当前游戏人物、第一轮模块 FK、同一个身体的 IK 校准、新衣服代理。最后一列标明“未合格”。

- 第一轮走路只有大臂、小臂的旋转，没有针对走路调整手腕，基础参考图里的掌心向前、五指展开被直接保留下来。
- 新动作以手腕目标、脚部目标和显式肘部/膝部极向控制 Rigify；手掌方向单独校准。没有把 FK 控制器的坐标轴当成人体关节轴直接通用旋转。
- 编写了掌心方向、肘部弯曲平面、手腕/脚目标误差检查，先跑旧动作确认失败，再检查新动作。门槛验证控制关系，不证明人物外观、手指形状或步态已经完成。
- Godot 4.7.2 实际运行，18 张截图，其中四张是腕肘近景；录下 12 秒走路、前伸、招手对照。旧角色没有前伸动作，界面标明其显示欢呼作为替代，不能当同动作质量对比。

掌心指标是变形骨骼相对绑定姿势的旋转，作用到初始掌面法线后，与身体内侧方向的点积。1 为朝内，0 为垂直，-1 为朝外。初始法线由基础参考图的掌心向前设定给出，仍需看真实网格验证。

| 指标 | 空 | 澪 |
| --- | ---: | ---: |
| 旧走路最小掌心朝内对齐 | -0.136 | -0.132 |
| 新走路最小掌心朝内对齐 | 0.963 | 0.965 |
| 新手腕目标最大误差 | 0.120 毫米 | 0.116 毫米 |
| 新脚部目标最大误差 | 0.172 毫米 | 0.175 毫米 |
| 新肘部弯曲平面与左右轴最小对齐 | 0.992 | 0.992 |

近景中能看到腕部方向变化。手肘位置仍来自上一轮比例估计；本轮控制了弯曲平面，没有声称关节位置已经逐角色手工对齐。手指仍然张开，手指体积和关节变形未验证。走路尚需真实参考、脚跟/脚尖滚动和步幅节奏调校。

## 衣服试验为何未采用

第一轮衣服从身体表面提取，保留了身体本身的拓扑和权重问题。整身人物里的上衣、手臂连接还需要网格清理与权重修正，不能靠增加骨骼解决。

本轮另建粗网格外衫和袖筒，使用身体最近三角面的重心插值转移权重，并限制躯干只取脊柱权重、袖子只取同侧手臂权重。这验证了新拓扑衣服可以复用身体骨架，但形体和接缝很硬，像工程代理，不能作为最终服装。2688 个新上衣顶点中，空 600 个、澪 582 个需要区域内最近骨骼回退，也说明单纯最近面转移尚不可靠。

后续服装需要真实版型、肩部与腋下的连续拓扑、袖口和腰部的干净边界，配合权重修正、裙摆/长袖辅助骨骼，以及必要的姿势修正形变。当前代理袖筒与躯干的接缝没有完成，不能把“没有一张长三角面被拉起来”当成衣服合格。

Blender 的 Data Transfer 支持最近面插值，本轮使用同类方法；距离最近并不保证语义上是同一个身体部位。[官方说明](https://docs.blender.org/manual/sl/5.2/modeling/modifiers/modify/data_transfer.html)

## 保持体积的导出限制

Blender Armature 的 Preserve Volume 使用双四元数蒙皮；glTF 2.0 的标准皮肤数据描述线性混合蒙皮，不能假设 Blender 修改器设置会随导出生效。[Blender 文档](https://docs.blender.org/manual/en/4.4/modeling/modifiers/deform/armature.html)、[glTF 规范](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)

本轮同一 Rigify 身体分别开启、关闭 Preserve Volume 导出 GLB。POSITION、JOINTS_0、WEIGHTS_0 完全相同。因此这个导出流程没有通过这些数据携带体积修正。该检查没有断言 Godot 所有渲染器都不可能支持双四元数；它只证明不能把 Blender 的勾选当成当前游戏导出路径已修好体积。

可继续试辅助扭转骨与可导出的姿势修正 morph targets。Blender 的 Corrective Smooth、表面变形或布料修改器在编辑器内有效，也必须另验证如何进入游戏运行时，不能只交 Blender 预览。

## 继续路线的文档调研

| 路线 | 解决的环节 | 当前证据 |
| --- | --- | --- |
| Rigify + IK/FK + 完整指骨 | 可编辑动作、腕肘方向 | 本轮已实测 IK 控制；未增加指骨 |
| 标准动漫基体 / VRoid + 独立服装 | 身体拓扑、完整人形骨架、换装贴合 | 已查官方换装功能，读取官方 VRM 样本结构；未适配空、澪 |
| Auto-Rig Pro 的体素/表面混合蒙皮 | 多层衣服、复杂拓扑的权重初始化 | 仅官方文档，未运行插件 |
| AccuRIG | 关节标记与手指自动绑定 | 官方系统要求列 Windows；本轮未实测 |
| Cascadeur / 动作库重定向 | 真实姿态、脚接触、跨角色动作 | 官方文档确认重定向及 GLB 导出；本轮未使用它制作动作 |

VRoid 的官方换装功能包含自动贴合、骨骼调整、网格编辑及 VRM 1.0 导出，支持 Windows/macOS。[官方发布说明](https://vroid.com/en/news/26gn98sTuPJQ53LxDQRyFg)

下载并读取 pixiv 的 `VRM1_Constraint_Twist_Sample.vrm`，它包含 54 项 humanoid 骨骼映射，30 项为两手指骨。样本元数据记录作者 pixiv Inc. 与 VRM Public License 1.0；这里只用于结构调研，没有冒充空、澪，也未接入正式游戏。[官方样本](https://github.com/pixiv/three-vrm/blob/dev/packages/three-vrm/examples/models/VRM1_Constraint_Twist_Sample.vrm)、[样本说明](https://github.com/vrm-c/vrm-specification/blob/master/samples/VRM1_Constraint_Twist_Sample/README.md)

Auto-Rig Pro 文档推荐复杂衣服网格可尝试体素方式，同时说明它对手指、面部等小部位不如表面热权重准确，建议混合使用；这仍不能修复错误的服装几何。[蒙皮文档](https://www.lucky3d.fr/auto-rig-pro/doc/auto_rig.html)

AccuRIG 有关节与手指绑定功能，官方系统要求页列出 Windows。[产品功能](https://www.reallusion.com/auto-rig/accurig/default.html)、[系统要求](https://manual.reallusion.com/ActorCore-AccuRIG-1/Content/ENU/1.0/03-Introducing-the-User-Interface/System_Requirements.htm)

Cascadeur 的重定向要求源、目标都建立 AutoPosing rig，不能把任何裸骨架直接复制进去。其导出文档支持 GLB/GLTF。[重定向要求](https://cascadeur.com/help/category/219)、[GLB 导出](https://cascadeur.com/help/category/283)

建议下一组有价值的对照是标准动漫基体与现有 Hyper3D 身体，使用同一套动作和服装验收。角色外观、头发及服装概念可以继续使用 Hyper3D；最终动画身体需要固定拓扑和完整骨架。这个混合方案目前是建议，尚未验证角色身份、美术适配和完整 Godot 管线。

## 查看与复现

- [第二轮启动脚本](../../art/poc/character_pipeline_20261003/round2/open_poc.command)，左右切动作、C 换装、V 正侧面、空格暂停。
- [12 秒对照录像](../../evidence/character_pipeline_poc_round2_20261003/walk_reach_comparison.mp4)。
- [空的腕肘近景](../../evidence/character_pipeline_poc_round2_20261003/screens/sora_walk_arms_front.png)、[侧面近景](../../evidence/character_pipeline_poc_round2_20261003/screens/sora_walk_arms_side.png)、[前伸对照](../../evidence/character_pipeline_poc_round2_20261003/screens/reach_casual.png)。
- [动作检查](../../evidence/character_pipeline_poc_round2_20261003/motion-checks.json)、[Godot 运行证据](../../evidence/character_pipeline_poc_round2_20261003/screens/runtime.json)、[保持体积导出检查](../../evidence/character_pipeline_poc_round2_20261003/volume-export/result.json)、[标准基体样本检查](../../evidence/character_pipeline_poc_round2_20261003/standard-avatar-inspection.json)。
- 工具和可编辑源文件在 `art/poc/character_pipeline_20261003/round2/`；新衣服被明确标记为未合格。原来的正式人物和第一轮源文件不变。

```bash
python3 art/poc/character_pipeline_20261003/round2/check_motion.py
```

骨骼方向检查通过不等于手掌造型、衣服和整个人物验收通过。本轮也没有新增完整玩法测试或发布包。
