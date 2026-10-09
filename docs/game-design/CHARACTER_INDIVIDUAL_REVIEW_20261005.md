# 六个角色逐人检查（2026-10-05）

按用户要求，依次检查莲、空、澪、田中、小葵、和子。春沿用上一轮已修好的版本，并参加整批数值回归。本轮没有提交新的图片或收费 3D 生成任务。

每人使用游戏的 CharAnim 驱动，在正面、侧面、斜侧面检查头颈近景与全身。11 个动作分别取 0%、25%、50%、75%、90% 五个时刻，再加原稿姿态；每个版本 336 张实机截图。逐人查看动作分镜与异常附近的重点帧，同时用更密的程序采样检查变形。截图存放于 `evidence/character_individual_review_20261005/`。

| 人物 | 检查结果与处理 | 最终分镜 |
| --- | --- | --- |
| 莲 | 下颌、耳下皮肤混入胸骨与手臂权重；张望时局部偏离头骨约 9 厘米。修正下脸权重、平滑领口接缝，并减小张望、鞠躬、伸展的头颈幅度。围裙、走跑、手部一起复查。 | [莲](../../evidence/character_individual_review_20261005/ren-final-contact.jpg) |
| 空 | 头颈没有莲的同类异常。扩展到所有独立网格后，伸展时左右袖片接缝出现短边拉裂，原检查只看最大网格，漏掉了袖片。只平滑两块袖片，身体、头部和动作不改。 | [空](../../evidence/character_individual_review_20261005/sora-final-contact.jpg) |
| 澪 | 检查下颌、领口、抬手、肘腕、裙摆、提包与走跑，未发现上述异常；保留原文件。 | [澪](../../evidence/character_individual_review_20261005/mio-before-contact.jpg) |
| 田中 | 脸部没有明显撕裂；张望和伸展的仰头幅度不适合老人。单独收敛头、颈、上胸旋转，保留走跑与网格权重。 | [田中](../../evidence/character_individual_review_20261005/tanaka-after-contact.jpg) |
| 小葵 | 脸正常，但张望会把胸前向日葵、领口和肩袖拉成碎条。重分配上衣的胸部和袖片权重，保护下脸和头发，再平滑衣物接缝。第一版影响了下脸，未采用；第二版通过。 | [小葵](../../evidence/character_individual_review_20261005/aoi-final-contact.jpg) |
| 和子 | 检查脸、颈、披肩、围裙、抬手、走跑和手部，未发现上述异常；保留原文件。 | [和子](../../evidence/character_individual_review_20261005/kazuko-before-contact.jpg) |

四个修复都保留当前网格坐标、三角面、UV、材质、贴图原始字节和原有修形，11 个动作名称与时长不变，30 根手指骨保留。空仍有 12 根袖口辅助骨。澪、和子、春的游戏 GLB 摘要与本轮开始时完全相同。

## 为什么上一轮会漏掉

头部检查原先只看身高 86% 以上的顶端，莲出问题的位置位于更低的下颌和耳下。小葵是衣服受到头骨影响，脸部检查本身会通过。空的袖片是独立网格，只检查最大网格不会覆盖它。

颜色与高度只能帮助选区域，不能代替解剖判断。浅色领口可能混入肤色区域，真实颈部也需要 Head / Neck / 胸部渐变权重，不能把所有残差都当成错误并强制跟头骨。空、澪、田中、和子的诊断数值结合截图解释，没有照搬莲的刚性下脸门槛。

## 回归与复现

- `art/tools/characters/audit_jaw_skin.py`：下脸与耳下诊断，7 个动作、17 个时刻。对已验证的莲下脸区域设置 2 毫米门槛，旧文件失败（90.18 毫米），修复后通过（约 0.00042 毫米，浮点误差量级）。
- `art/tools/characters/audit_pose_tears.py`：检查所有绑定网格及其修形，11 个动作、9 个时刻。原边长小于 12 毫米，动作后大于 70 毫米且增长超过 8 倍，即报告针状拉裂。小葵旧文件最多 206 条、空旧文件最多 9 条；最终七人均为 0。旧数据先运行并实际失败。
- `art/tools/characters/audit_head_neck.py`：七人的顶端刚性头部回归通过；此项必须和下脸、衣服及实机图一起判断。
- `audit_candidate_contract.py` 和正式 `audit_roster.py`：外观表面、UV、贴图、修形、动作时长、骨骼和权重检查通过。四人站立支撑面倾角为 0°。

候选、可编辑源文件在 `art/models/character_individual_review_20261005/`；修复前 GLB 保留于隔离 POC 的 `baseline/`。参数、采用脚本、实际截图与旧失败报告都在本轮证据目录。素材清单、导出配方、人物库 GLB 预览、Blender 下载和缩略图已经同步。浏览器四权重预览是近似显示，八权重人物的正式验收以 Godot 为准。

空在极端举臂时仍会露出白色内搭，当前保留原有分层外观。本轮的短边回归覆盖采样动作，不等于任意新动作、任意换装都已验收；增加动作或衣服后，应继续逐人复查。

## 正式工程与桌面包

738 项正式工程检查全部通过，退出码 0，无 SCRIPT ERROR。新包严格签名、ZIP CRC、x86_64 / arm64 双架构通过；五个实景截图完成。解压后的应用完整自动试玩 335.78 秒、模拟 1239.1 秒，44 张截图，Q05 完成，退出码 0，SQLite quick_check 为 ok。退出仍有既有的一条 shader RID 提示。

默认 `builds/HareMachi.zip` 已原子替换，1,614,283,570 字节，SHA-256 `c72461769724eaea5a317d3ca62bf0a45b848e970821c8f84aa69833588e57ac`。独立临时冻结工程、导出包和解压应用已经删除；builds 顶层只保留 HareMachi.zip 与 web。校验摘要、截图、保存数据库和命令记录保留于本轮 evidence。锁定的 Godot 4.7.2 在临时工程规范化了 33 个旧导入配置，差异仅为删除三个不支持的默认选项，实际素材和代码未变，另有 import-normalization.json 记录。完整结果见 `evidence/character_individual_review_20261005/verification.json`。

修复前后：[莲](../../evidence/character_individual_review_20261005/ren-comparison.jpg)、[空](../../evidence/character_individual_review_20261005/sora-comparison.jpg)、[田中](../../evidence/character_individual_review_20261005/tanaka-comparison.jpg)、[小葵](../../evidence/character_individual_review_20261005/aoi-comparison.jpg)。
