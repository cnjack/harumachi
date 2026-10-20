# 澪：现成 Live2D 模型与 Swift 接入调研

核查日期：2026-10-20。核查公开仓库的模型清单、参数、姿态配置、许可证、Swift Package 清单和官方源文件说明；未下载 SDK、运行第三方代码或替换澪。文件核查不等于本机播放验收。

建议先以 **Hiyori 验证正式 Cubism 播放链路，以 Natori 作为多套手臂姿态的制作参考**。保留澪的设计时，要重新适配素材、网格和变形器；直接换一张贴图无法保留另一角色绑定的质量。当前自有分层原型的弧形关节修复可以缓解翻面，但不能承担任意透视、手型或大幅姿态变化。

## 模型对比

以下数量来自本次读取的官方 `CubismWebSamples`，不是整个官网素材包的数量。

| 模型 | 已核对的运行资源 | 源工程 | 对本项目的用途 |
| --- | --- | --- | --- |
| **Hiyori / 桃濑日和** | 9 个 Idle、1 个 TapBody；肩部、左右 A/B 臂和手腕参数；一组 A/B 手臂替换 | 官网列出 `.cmo3`、`.can3` 和运行文件 | 首选播放基准。先验证头颈、自然待机、手臂替换、眨眼与口型 |
| **Haru / 接待员版** | 2 个 Idle、4 个 TapBody、8 个表情；左右各两套臂部件 | 官网还提供素材拆分 PSD 与导入 PSD | 最适合学习如何把澪的原画拆成可绑定素材 |
| **Mao / 虹色真央** | 2 个 Idle、6 个 TapBody、8 个表情；A/B 臂各有肩、肘、腕和手型参数 | 官网列出 `.cmo3`、`.can3`；Cubism 5 模型 | 后续面部活动范围、肩肘腕和表情表现的参考 |
| **Natori / 名取仁** | 3 个 Idle、5 个 TapBody、11 个表情；左右各三套臂部件，另有手表替换；含手指与前臂参数 | 官网列出 `.cmo3`、表情/动作 `.can3` | 最直接对应“像骨折、方向不对”的结构参考 |

对应运行清单：[Hiyori](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Hiyori/Hiyori.model3.json)、[Haru](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Haru/Haru.model3.json)、[Mao](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Mao/Mao.model3.json)、[Natori](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Natori/Natori.model3.json)。

源文件说明：[Hiyori](https://www.live2d.com/en/learn/sample/momose-hiyori/)、[Haru](https://www.live2d.com/en/learn/sample/haru-receptionist/)、[Mao](https://www.live2d.com/en/learn/sample/niziiro-mao/)、[Natori](https://www.live2d.com/en/learn/sample/natori-jin/)。GitHub 运行包中的 `.moc3` 与官网可编辑的 `.cmo3` 用途不同，不能把前者当作可直接修改的绑定工程。

## 手臂结构的关键发现

Hiyori 的 [`pose3.json`](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Hiyori/Hiyori.pose3.json) 对 `PartArmA` / `PartArmB` 做替换，切换时长为 0.5 秒。Haru 的左右臂分别拥有 A/B 两套。Natori 的[姿态配置](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/Samples/Resources/Natori/Natori.pose3.json)为左右各三套，官网也明确把“更换部件扩展动作表现”列为该模型的学习目标。

据此，本项目下一版源素材应准备放松、招手、胸前手势等独立姿态，分别绘制肩袖遮挡、肘内侧、前臂和手型，再在匹配姿态之间过渡。这里是制作建议，尚未生成这些新素材或宣称完成正式 Cubism 绑定。

同日后续：已为自有原型生成掌心、手背、内收侧掌、肩腰拆层源图，与原放松手型组成四套，导出 23 层 PSD。用户发现的拇指镜像错误已在源图列映射修正，并以真实纹理检查复验；源文件与证据见 `art/live2d/mio/pose-parts/`、`evidence/mio_pose_parts_20261020/`。这次工作仍不等于 `.cmo3` / `.moc3` 或官方模型播放验收。

## Swift / Metal 候选

| 项目 | 已核查情况 | 结论 |
| --- | --- | --- |
| [Live2D/CubismNativeSamples](https://github.com/Live2D/CubismNativeSamples) + Native Framework | 官方动作、表情、物理和姿态实现；Core 不在仓库，需要另行取得；当前 Metal 示例文档的工程入口为 iOS / Mac Catalyst | 以官方运行时为基础；AppKit 桌面窗口仍需做桥接，不能把示例当作现成 macOS 桌宠 |
| [KristopherGBaker/Live2DKit](https://github.com/KristopherGBaker/Live2DKit) | 已查看实际 Swift/ObjC++ 目录、测试目录、Package.swift、LICENSE；封装原始代码为 MIT；不附带 Core/Framework | 最接近当前架构的候选，但尚未本机编译验收 |
| [rlf23240/Live2DMetal](https://github.com/rlf23240/Live2DMetal) | 默认分支最后提交 2020-05-30；README 把动画、Parts、反向遮罩列为待做 | 可读历史实现，不作为本项目主依赖 |

Live2DKit 固定核查版本为 `ffe10b853ffee2dca072b0c1d9683f31903df55f`，默认分支最后提交时间为 2026-08-10。实际 [`Package.swift`](https://github.com/KristopherGBaker/Live2DKit/blob/ffe10b853ffee2dca072b0c1d9683f31903df55f/Package.swift) 要求 **Swift 6.2、macOS 26 / iOS 26**，而当前澪原型声明 macOS 14。若保留现有支持范围，必须评估回移植或写窄范围 ObjC++ 桥接。还需要按它的打包约定放置 Metal shader 库，不能直接增加一个普通版本依赖就认为接入完成。

官方 Native 核查版本为 `a3a64f6cb327aafce380949e0f54fe51c4d773d9`。[Metal 示例说明](https://github.com/Live2D/CubismNativeSamples/blob/a3a64f6cb327aafce380949e0f54fe51c4d773d9/Samples/Metal/README.md)和 [Core 取得说明](https://github.com/Live2D/CubismNativeSamples/blob/a3a64f6cb327aafce380949e0f54fe51c4d773d9/README.md)分别界定了平台与依赖边界。

## 素材使用与实施边界

官方示例模型有独立的 Free Material License 和各角色使用条件，SDK Core 又有单独条款；封装仓库的 MIT 不覆盖这些素材与库。[官方许可清单](https://github.com/Live2D/CubismWebSamples/blob/b1de66b0b1f1cb881d95fb6158622aeb6a2827bd/LICENSE.md)。

[Eikanya/Live2d-model](https://github.com/Eikanya/Live2d-model) 确实收集了大量模型，但其 README 说明素材多从手游提取、配置不保证正确，并提示不要商用。它适合发现视觉参考，本轮不作为直接打包进澪应用的素材来源。

建议后续顺序：

1. 明确可用 SDK 与模型条款后，用 Hiyori 验证 `.model3.json` 加载、原生 Metal、动作、姿态、遮罩、物理和透明窗口。
2. 用 Haru PSD / Natori 姿态结构整理澪的素材清单，再制作自己的可编辑绑定。
3. Clef 只选择已经验收的动作和表情；不要让模型直接指定关节角度。
4. 继续使用免系统隐私授权的事件来源；Cubism 播放不要求增加屏幕、摄像头或输入监控。

本轮仅完成调研和当前原型的折叠修复。官方模型尚未在本机播放，SDK/Editor 未安装，澪的 `.cmo3` / `.moc3` 制作仍未完成。原始核查结果在 `evidence/mio_arm_binding_20261020/research/`。
