# 空、澪也重新生成 A pose

2026-10-05。用户要求另外两位也重新生成。以此前满意版本的正背参考保持脸、头发、衣服和配饰，改为手臂斜向下的 A 姿势，再分别提交一次 Hyper3D Rodin High Quad。共 2 次付费 3D 任务，无额外付费重试。旧两位已保存在 `art/models/archive/characters_before_leads_apose_20261005/`，另外五人的正式 GLB 摘要保持不变。

## 生成与绑定

新图由内置 image_gen 编辑，正背面同一人，腋下留出衣服和手臂间隙，手掌朝身体。补正空的左腕手表后才提交模型。图在 `art/references/character_leads_apose_20261005/`，提示词在同名 manifests/prompts 目录。参考目标 45°，服务生成网格的实测斜率约为空 52°、澪 51–54°，人物库按实测角显示。

原始 GLB 为 `art/models/raw/CH_<人物>_rodin_apose_20261005/model.glb`，完整请求和来源在 `character_leads_apose_20261005.json` 与 `models_hyper3d_leads_apose_20261005.json`。采用正常化身高、解剖代理手部对齐、焊合 UV 重合顶点后的热权重。保留 54 人物骨（其中 30 手指骨、2 前臂扭转骨），追加 12 袖口辅助骨；原 11 动作名称和时长保留。

比较代理与热权重后，两人的初版尖条分别最多 182/10 和 188/76；最终约束上身不接受腿骨权重，平滑接缝，澪的包身与带子跟随躯干，裙摆使用连续左右腿混合权重。基础修正的短边尖条检查均为 0。原始裙型仍会在迈步时被腿顶穿，随后烘焙 `Skirt_Clearance`，只在前后方向留出净空，保持左右宽度。肩袖修形强度比旧 T pose 小，袖口使用已验收的原生限幅弹簧。

焊合还合并了澪头部一个原本拥有单独角点 UV 的小三角面。没有放松表面门槛：按原位置、UV、权重与修形层补回独立角点，最终原外观三角面和 UV 全部保留。完整核对为 `asset-contract.json`，原动作时长误差 0、权重归一、骨索引和手指骨全部通过。

## 游戏与人物库

正式 `CH_sora.glb`、`CH_mio.glb` 已更新。配方启用完整骨骼复制，旧七人打包工具会尊重新两人的来源，避免下次导出退回 T pose。人物库的 GLB、四权重浏览器预览、A pose 原稿、正背参考、静音参考姿态的 Blender 副本及实际网格缩略图同步更新。两位的 12 个文件下载与磁盘摘要一致。

[空的本机库入口](http://127.0.0.1:8787/art/library/#game%2FCH_sora)，[澪的本机库入口](http://127.0.0.1:8787/art/library/#game%2FCH_mio)。主要工具为 `build_leads_apose.py`、`lead_garment_weights.py`、`lead_skirt_clearance.py`、`package_leads.py` 和 `audit_leads.py`。原始模型、所有失败权重候选、修正和对比均保留。

## 验证

证据目录 `evidence/character_leads_apose_20261005/`。`sora-comparison.mp4`、`mio-comparison.mp4` 均为 27.77 秒、833 帧、30 FPS，左侧此前满意版本，右侧 A pose 再生成版。含正侧走路、跑步、招手、鞠躬、跳舞和停下。运行时 CharAnim 有效，衣物辅助骨只在 12° 内运动。图片来自实际 Godot 4.7.2，未用概念图替代。

完整游戏 661 项全部通过，退出码 0，无 SCRIPT ERROR。源工程与导出应用均拍摄七人走路、招手、跳舞实景。日期包为 `builds/HareMachi-leads-apose-20261005.zip`，冻结源码为 `builds/leads-apose-source-20261005/game`。包的 CRC、严格签名及 x86_64/arm64 双架构通过；解压应用完整剧情 332.85 秒、模拟 1228.5 秒、44 张截图、Q05 完成、退出码 0，无 SCRIPT ERROR。SQLite quick_check 为 ok，v4 快照摘要通过。退出仍有旧版同样存在的一个 shader RID 提示。

默认 `builds/HareMachi.zip` 只在全部验收完成后更新；前版保存在 `builds/HareMachi-before-leads-apose-20261005.zip`。最终状态、文件摘要与验证结果见本轮 `verification.json`。
