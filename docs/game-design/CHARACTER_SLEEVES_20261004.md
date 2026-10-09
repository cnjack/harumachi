# 肩袖与袖口修形（2026-10-04）

用户指出走路时肩头过宽、袖口缺少自然下垂。本轮继续使用已修好手掌的 binding9 人物，没有重新提交模型生成任务。当前版本是 binding13_sleeves；正式游戏人物素材未替换。

## 原因与处理

实机近景能看到肩部像被撑起、袖管偏硬。肩袖没有误绑到头骨，但完整穿衣网格沿用了人体蒙皮，宽松衣料缺少专门的姿态修形。只调整手掌与前臂无法改变衣料的这些轮廓。

在原网格上增加 4 个修形：左右肩部、左右袖口。肩袖轮廓收窄并下落，袖口在垂手时下垂；修形强度随上臂方向变化，抬手时减弱。修形向量沿几何邻接平滑，避免肩头变尖或袖口与皮肤交界出现突变。头部、手指、腿部与身体中线受到保护。

本轮经历四个候选：binding10 的袖口有改善，但空的肩部变化偏小；binding11 加强肩部后出现偏尖的轮廓；binding12 平滑修形并补足袖口下落；binding13 继续调整肩袖上缘的下落。采用最后一版。

参考姿态的修形权重为零。静态基形顶点与 UV 检查通过，材质与内嵌贴图逐项摘要相同，骨架仍为 54 个关节、30 个手指。原 11 个动作名称、时长和步速数据保留。

修形与骨骼动作使用同名 NLA 轨，导出时合并为同一动画，再校正时长。Blender 导出器支持按 NLA 轨名称合并，Godot 有专门的 Blend Shape 动画轨；本轮另用项目锁定的 Godot 4.7.2 实机检查了动画播放器中的权重。[Blender glTF 手册](https://docs.blender.org/manual/en/4.4/addons/import_export/scene_gltf2.html)、[Khronos 导出器实现](https://github.com/KhronosGroup/glTF-Blender-IO/blob/main/addons/io_scene_gltf2/blender/exp/animation/tracks.py)、[Godot 动画轨说明](https://godotengine.org/article/animation-data-redesign-40/)

## 检查结果

对站立与行走各取 32 个周期采样，测实际变形后的衣料表面。表中宽度是肩袖衣料轮廓，不是骨架尺寸；袖口下落是相同骨骼姿态下，开启与关闭修形的实际表面差。

| 人物 | 旧版最大肩袖宽度 | 当前最大肩袖宽度 | 袖口平均下落的周期中位数 |
| --- | --- | --- | --- |
| 空 | 45.61 cm | 42.54 cm | 左 1.21 cm，右 1.15 cm |
| 澪 | 39.36 cm | 38.05 cm | 左 0.98 cm，右 1.02 cm |

新回归先拿 binding9 跑，两个人物均失败；binding13 均通过。检查包括肩袖宽度、袖口下落和袖口边长增长，防止局部修形又拉出长三角。前一轮的 832 个掌面采样仍通过。原 CharAnim 每人在 4 秒内产生 8 次脚步事件。

Godot 原生检查确认：参考姿态 4 个修形权重归零；走路时启用；招手时抬起的右臂修形减弱，未抬起的左臂保留修形。实机截图每人 224 张，覆盖参考、站立、走路、跑步、招手、伸展、跳舞，4 个方向、8 个周期。另有每人 16 秒的正面走路、侧面走路、跑步和招手对照。

本轮是姿态驱动修形。完整独立服装、遮挡身体补齐、裙摆与身体碰撞仍按 [服装管线调研](GODOT_CHARACTER_CLOTHING_20261004.md) 继续集成；不以此声明已完成整件衣服的实时布料模拟。

## 文件与复现

- 工具：`art/poc/character_pipeline_20261003/tpose_20261004/sleeve_drape.py`，当前参数为 `--strength 1.3`，其余使用默认值。
- 可编辑源：`binding13_sleeves/authoring/sora_proxy.blend`、`mio_proxy.blend`。
- 交互对照：`open_sleeve_poc.command`、`open_mio_sleeve_poc.command`。左右切动作，V 切方向，空格暂停，Esc 退出。
- 当前资产：`godot/assets/sora_proxy.glb`、`mio_proxy.glb`；旧 binding9 与各候选保留。
- 证据：`evidence/character_pipeline_tpose_20261004/sleeves/`。`binding9_palms-regression.json` 为旧版失败，`binding13-regression.json` 为新版通过，`native-morph-probe13.json`、`driver13.json`、`palms-preserved13.json`、`asset-contract13.json`、`material-preservation.json` 分别检查实机修形、控制器、手掌、资产和材质。
- 视频：`sora-shoulders-cuffs-before-after.mp4`、`mio-shoulders-cuffs-before-after.mp4`，左侧修正前，右侧修正后。
