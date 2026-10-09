# 人物绑定、修形与服装：算法和开源工具深度调研

日期：2026-10-04。目标：保留空与澪的脸、发型、服装设计，获得自然走路、伸手与跳舞，并为换装留下可维护的结构。

本轮检索论文作者页面、官方文档、源码仓库和许可证，下载关键代码作静态核查。没有安装新插件、运行其演示或推理模型，也没有改动当前 binding13 POC。因此下文的效果预期是方案判断；macOS 实机适配与本人物效果仍需下一轮对照。

## 结论与优先级

更合适的长期路线是：**分离身体与服装，整理可变形拓扑，稳健转移权重，使用多姿态修形处理肩肘，再给自由衣片加入局部物理。** 这些步骤解决不同问题。自动绑定模型可以参与权重对照，但不能替代衣服结构整理。

当前 binding13 的四个修形是有用的基线：改进了肩袖轮廓，并保留原动作。然而它们按上臂方向驱动，再烘焙进既有动作；没有布料惯性、表面碰撞，也不能直接保证新导入舞蹈动作获得同样修正。当前人物仍是一张完整穿衣外表面，衣服下面的身体未补齐。这是未来换装的结构性缺口。

建议依次测试：

1. **Robust Weight Transfer + 独立衣服**：解决腋下、肩袖和宽松衣物的权重误配。
2. **Pose Shape Keys + 运行时 PSD/RBF**：解决多个方向抬臂、弯肘、转腕时的形状，减少逐动作补丁。
3. **原生弹簧骨或 GPU XPBD**：让袖口、衣摆、裙摆响应重力与运动；局部模拟优先。
4. **UniRig / SkinTokens 对照**：比较自动蒙皮质量，保留外观；不是先替换整个人物。

## 重点候选

| 工具 / 算法 | 对本项目的作用 | 代码许可与状态 | 接入判断 |
| --- | --- | --- | --- |
| [Robust Weight Transfer for Blender](https://github.com/sentfromspacevr/robust-weight-transfer) | 身体到衣物的权重转移，对不可靠匹配区域进行权重修补 | 仓库 LICENSE 为 GPL-3.0；论文作者实现为 MIT | **最高优先级**；离线工具，不改变 Godot 渲染器；需核查 Blender Python 原生依赖 |
| [Pose Shape Keys](https://studio.blender.org/tools/addons/pose_shape_keys) | 在真实姿态中雕刻修形，并支持后续修改权重与约束 | Blender Studio 工具；GPL-3.0+；1.1.1 声明 Blender 5.0 起、6.0 以下，支持 Action Slots | **最高优先级**；当前 Blender 5.2.1 落在声明范围，尚未实测 |
| [RBFPoseDriver3D](https://github.com/MykytaPetrenko/RBFPoseDriver3D) | Godot SkeletonModifier3D，根据骨骼姿态混合修正骨骼和 BlendShape | 源码公开；未找到 LICENSE，API 元数据也未声明许可 | 算法参考；当前不能列为许可已确认的可分发插件；可独立实现小型运行时求值器 |
| [GPU Cloth Sim](https://github.com/alien-life/gpu-cloth-sim) | GPU 布料约束、骨骼锚定、重力、惯性、身体与衣物碰撞 | MIT；README 描述 v3.0；源码距离约束已经使用 XPBD | **局部布料首选测试候选**；4.5+、计算渲染器；Mac/Metal 与现有修形组合未实测 |
| [SpringBoneSimulator3D](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html) | 给裙摆、衣摆或袖口辅助骨骼加入次级运动与简化碰撞 | Godot 原生，MIT | 成本较低；模拟骨链，不能保证所有衣物三角形不穿模 |
| [SoftBody3D + Jolt](https://docs.godotengine.org/en/4.7/tutorials/physics/soft_body.html) | 原生可变形衣片，固定点跟随骨骼附件 | Godot 原生；官方建议使用 Jolt | 适合作为低面数袖片、衣摆的物理基线；需要单独设计固定点与碰撞 |
| [RetopoFlow 4](https://github.com/CGCookie/retopoflow/tree/v4.2.0) | 在原模型表面整理肩、肘、袖管和衣摆的面流 | v4.2.0 manifest 声明 GPL-2.0+、Blender 4.2 起；现成发行包可收费 | 优先于只减少面数；需要局部建模工作，保持原外观再烘焙贴图 |
| [UniRig](https://github.com/VAST-AI-Research/UniRig) | 自动骨架与蒙皮；可将修改后的骨架输入 skin 阶段 | 代码与官方模型卡均声明 MIT；官方推理要求 NVIDIA CUDA，至少 8GB 显存 | 可对现有模型做自动权重对照；不是 Mac 原样可运行的官方路线 |
| [SkinTokens](https://github.com/VAST-AI-Research/SkinTokens) | 更新的统一骨架、权重预测方法，UniRig 的后续项目 | 代码 MIT；官方模型卡 MIT，要求至少 14GB NVIDIA 显存 | 值得 GPU 侧对照；论文指标不是空、澪的质量保证 |
| [GarmentCode](https://github.com/maria-korosteleva/GarmentCode) | 用参数化版型重建衬衫、开衫和裙子，利于独立换装资产 | PyGarment / GarmentCode MIT；仿真、身体模型和数据另看各自条款 | 长期服装结构路线，工程量较大 |
| [Design2GarmentCode](https://github.com/Style3D/design2garmentcode-impl) | 图、草图或文本到服装版型程序 | 代码 MIT；默认流程还需 LMM API、Qwen 参数投影器及独立仿真依赖 | 研究候选；不是直接输出可用 Godot 衣服的插件，默认 API 有成本 |

Pose Shape Keys 的版本与许可来自 [官方版本页](https://extensions.blender.org/add-ons/pose-shape-keys/versions/)。RetopoFlow 要对应分支：仓库默认 master 的 manifest 是 3.4.11，不能把下载 master 当作 v4；[v4.2.0 manifest](https://raw.githubusercontent.com/CGCookie/retopoflow/v4.2.0/blender_manifest.toml) 与分支源码需一起核查。

## 1. 权重修补，比直接复制最近表面更贴近衣服问题

[Robust Skin Weights Transfer via Weight Inpainting](https://www.dgp.toronto.edu/~rinat/projects/RobustSkinWeightsTransfer/index.html) 是 SIGGRAPH Asia 2023 的工作。方法先找可靠表面对应，再把未匹配区域的权重通过几何平滑优化补齐。它适合宽松衣物与身体之间存在间隙的情形。

源码核查确认 Blender 实现同时检查距离和法线角度，再用目标几何的 Laplacian 和约束求解补权重。当前最近三角形插值容易在腋下、两腿之间或松袖内部选择不合适的身体表面；这是本项目值得优先比较的原因，属于基于算法机制的判断，不是本人物已经实测胜出。[插件实现](https://github.com/sentfromspacevr/robust-weight-transfer/blob/main/weighttransfer.py)

依赖是 `scipy`、`libigl==2.5.1`、`robust-laplacian`。Blender 5.2.1 的 Python、NumPy 与 arm64 wheel 需要匹配，不能直接把 Windows 的预编译依赖复制过来。官方作者 [MIT 示例代码](https://github.com/rin-23/RobustSkinWeightsTransferCode) 可作为离线实现参考，但其 README 的完整 body-to-garment FBX 工作流仍写着 Coming soon；Blender 插件更接近实际操作。[依赖清单](https://raw.githubusercontent.com/sentfromspacevr/robust-weight-transfer/main/requirements.txt)

它不会修复破洞、错误版型或缺失身体，也不会产生布料重力。先把可用身体或拟合权重代理与衣服摆在一致的绑定姿态，再转移；转移后仍检查归一化、最多四个影响、手指、袖口和完整动作周期。

## 2. 多姿态 PSD / RBF，改善肩肘并覆盖新增动作

肩部需要同时处理抬臂、前后摆臂、旋转和胸部姿态。现有单个上臂方向系数表达能力有限。PSD 通过示例姿态提供期望形状，RBF 则根据当前姿态在示例之间插值；它可以驱动修形权重，也可以驱动辅助变形骨骼。

Pose Shape Keys 适合制作这些示例。Godot 侧按骨骼当前姿态求值，新增动作只要落在样本覆盖范围内，就能获得修正；超出范围仍需新增样本或限制外推。Blender 的驱动器本身不能被当作 Godot 中仍在运行的程序：固定动作可烘焙权重，任意动作需要运行时求值。

实际找到的 RBFPoseDriver3D 当前源码支持多网格 BlendShape、最多三个驱动骨骼，使用四元数角距离；权重由高斯距离计算后归一化。它是简化的核混合，没有看到求解插值矩阵以保证每个训练姿态严格复现的步骤。必须比较中间姿态和示例重现误差，不能仅凭“RBF”名称判断质量。[源码](https://github.com/MykytaPetrenko/RBFPoseDriver3D/blob/main/addons/rbf_driver_3d/rbf_driver_3d.gd)

许可证尚未确认，建议把它列为算法参考，或用独立实现替代。搜索还找到 IngoClemens 的 RBF Nodes，但原 [仓库当前仅保留维护迁移说明](https://github.com/IngoClemens/blender)，旧文章中的开源下载地址不能直接当作现成插件。

下一轮先制作少量覆盖关键方向的肩肘示例：垂手、前伸、侧举、举高、交叉伸手、弯肘和前臂转动。数量是初始实验设计，按实际误差增补。原 11 个动作与一段未参与制作的舞蹈动作共同验证，避免只修好制作时看到的动作。

## 3. GPU XPBD，真正处理袖口重力和惯性

GPU Cloth Sim 的 v3 文档描述了骨骼目标、顶点色模拟权重、碰撞、焊接粒子与 GPU 输出。衣片可把肩缝权重设为固定，袖口设为自由，中间渐变。与当前修形相比，它能根据重力与运动状态改变形状；实际效果与稳定性需要本人物测试。[仓库](https://github.com/alien-life/gpu-cloth-sim)

不是只看演示：下载的 `cloth_solve.glsl` 已有 compliance、按 dt² 缩放的参数和累计 λ，属于 XPBD 距离约束；源码比 README 中概括的 PBD 更具体。[求解器代码](https://github.com/alien-life/gpu-cloth-sim/blob/main/addons/godot_gpu_cloth/shaders/compute/cloth_solve.glsl)、[XPBD 作者论文](https://matthias-research.github.io/pages/publications/XPBD.pdf)

接入时有五个需要验证的点：

- **渲染器**：当前 POC 明确使用 Compatibility，不能在其中运行计算着色器。正式工程声明 Forward Plus。另建 Forward+ 研究副本；Godot 4.7 的原生 Metal 支持 RenderingDevice，但插件 README 声明 Vulkan，Mac/Metal 尚未实测。[Godot 计算着色器](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)、[Metal 架构](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)
- **Morph 组合**：当前 skin pass 从基形与四个骨骼权重做 LBS，未见 Morph 输入；不能默认把 binding13 的四个修形一起带进模拟目标。先分开对照，组合时验证或补足 Morph 通路。[skinning pass](https://github.com/alien-life/gpu-cloth-sim/blob/main/addons/godot_gpu_cloth/shaders/compute/cloth_skin.glsl)
- **材质**：代码会替换不符合 v3 接口的 ShaderMaterial。保留动漫画风需要把 GPU 位置、法线读取接入原材质逻辑，再验证平涂和硬边阴影；不直接使用默认写实织物效果。[solver 材质处理](https://github.com/alien-life/gpu-cloth-sim/blob/main/addons/godot_gpu_cloth/src/gpu_cloth_solver.gd)
- **模拟规模**：每个人物约 9.5 万三角形，不宜直接作为第一轮布料实验。先给独立袖片或衣摆使用低面数网格；如果仍渲染原高面数表面，需要另做低面数到高面数的形变映射。UV 顶点焊接不等于任意高低分辨率代理绑定。
- **身体与衣服**：当前缺少衣服下的完整身体。先补局部身体或碰撞代理，并保留袖口可见的内侧表面；身体碰撞不能仅拿同一张穿衣外壳代替。

该插件的 Skin bind 槽到 Skeleton 骨骼映射有处理，避免简单把 glTF 权重索引当骨架索引。这是源码中的积极信号，但不代表整套服装在本机已经通过。

## 4. 成本较低的原生物理路线

SpringBoneSimulator3D 是骨链次级运动，适合小幅摆动的衣摆、裙摆和袖口辅助骨。需要把衣物顶点绑到这些骨骼，再用身体胶囊近似碰撞。它不支持把 Y 分支当一条链，也不做逐三角布料碰撞。应保持骨架和模拟器单位缩放。[Godot 4.7 文档](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html)

SoftBody3D 可作为局部衣片的原生物理基线。官方建议 Jolt；固定点可以跟随 BoneAttachment3D，官方披风教程明确要求通过 pinned point 的附件路径跟随骨骼。它不是在普通 Skinned Mesh 上自动叠加的服装按钮。[SoftBody3D](https://docs.godotengine.org/en/4.7/classes/class_softbody3d.html)、[披风教程](https://docs.godotengine.org/en/4.7/tutorials/physics/soft_body.html)

这两条路线比 GPU 方案容易保留现有渲染材质，适合与 GPU 袖片做同一动作、同一轮廓的对照。

## 5. 蒙皮算法与自动绑定：有价值，但不负责衣服下垂

**DQS / 保持体积**能改善某些转腕、弯肘的体积损失，但不会产生布料重力。Godot 的 [DQS PR #89131](https://github.com/godotengine/godot/pull/89131) 在本轮读取时仍 open、未合并；没有确认当前引擎存在可直接启用的原生路径。不能假设 Blender 的 Preserve Volume 算法随普通 GLB 一起转移。

**Direct Delta Mush**值得作为肩肘平滑与体积保持的对照。libigl 有实现，相关 header 声明 MPL-2.0；库同时包含其他许可模块，需按实际使用文件核查。它更像需要实现或离线烘焙的算法库，不是已确认的 Godot 一键插件。[算法教程](https://libigl.github.io/tutorial/#direct-delta-mush)、[实现许可](https://github.com/libigl/libigl/blob/main/include/igl/direct_delta_mush.h)

**UniRig**把骨架和蒙皮分成阶段，允许先编辑骨架再预测权重，适合比较现有 54 骨架的蒙皮。**SkinTokens**进一步统一骨架与权重预测；官方模型卡给出 NVIDIA 至少 14GB 显存要求，UniRig 官方推理要求至少 8GB。这里是推理要求，不是训练要求，也不是我们实际测出的耗时。[UniRig 官方仓库](https://github.com/VAST-AI-Research/UniRig)、[SkinTokens 官方模型卡](https://huggingface.co/VAST-AI/SkinTokens/blob/main/README.md)

SkinTokens 的论文改进数字不能当作空和澪的预期提升。两者仍需检查手指、骨骼语义映射和原动作迁移，也不会补齐服装内部身体。

## 6. 服装拓扑与版型，直接影响换装质量

保留原角色外观时，可以只重拓扑或重建衣物，保留脸与头发。RetopoFlow 与 Blender 原生建模适合整理连续袖管、肩缝、肘部和衣摆；之后从原衣物烘焙贴图并做轮廓对比。Instant Meshes 是 BSD 风格许可的自动重网格工具，可作起点，但自动出四边形不能保证动画需要的面流。[Instant Meshes](https://github.com/wjakob/instant-meshes)

GarmentCode 用参数化缝制版型表达衣服，对长期换装比一个焊在身体上的外壳更有利。Design2GarmentCode 将图、草图或文字转成版型程序；其代码 MIT，但默认流程含 LMM API、Qwen 投影器和单独的仿真器。可用于款式重建研究，当前不列为最短接入路线。[GarmentCode 论文项目](https://igl.ethz.ch/projects/garmentcode/)、[Design2GarmentCode 官方流程](https://github.com/Style3D/design2garmentcode-impl)

身体模型、数据与服装仿真库须单独核查，不能把主仓库 MIT 当作全部依赖的许可。

## 其他候选与排除理由

| 候选 | 核查结论 |
| --- | --- |
| [RigAnything](https://github.com/Isabella98Liu/RigAnything/blob/main/LICENSE.md) | Adobe 非商业研究许可；不列为商业游戏的确定可用开源工具 |
| [HOOD](https://github.com/Dolorousrtur/HOOD)、[ContourCraft](https://github.com/Dolorousrtur/ContourCraft) | 神经布料研究，代码 MIT；官方路线有 PyTorch/CUDA 等依赖，示例含 SMPL 系列身体。优先用于离线研究，不作为本轮 Godot 插件首选 |
| [Surface Heat Diffuse Skinning](https://github.com/meshonline/Surface-Heat-Diffuse-Skinning) | MIT 体素/热扩散实验；发布说明较旧，原生二进制与 Blender 5.2 / arm64 需移植核查 |
| [godot-vrm](https://github.com/V-Sekai/godot-vrm) | 插件 MIT，样本角色另有许可；可参考 humanoid、MToon 与弹簧骨管线，不能把普通 GLB 自动变成完整换装角色 |
| [Rokoko Blender 插件](https://github.com/Rokoko/rokoko-studio-live-blender) | 可辅助动作重定向；服务订阅与动作资源另看条款。解决动作映射，不能修复坏衣物拓扑或产生衣料重力 |

## 下一轮建议的三个具体对照

| 对照 | 内容 | 回答的问题 |
| --- | --- | --- |
| A：稳定修形路线 | 原外观、独立袖片、稳健权重转移、多姿态修形；袖口辅助骨使用原生 SpringBone | 肩肘在新动作中能否保持自然，较低成本的次级运动够不够 |
| B：局部物理路线 | 同一衣物与动作，独立 Forward+ 场景；GPU XPBD 只模拟自由袖口/衣摆 | 重力、加减速与转身后的衣料表现是否明显改善，Mac 和材质是否可接入 |
| C：自动权重路线 | 同一外表面与尽量相同骨架，UniRig / SkinTokens 与当前代理权重对照 | 自动蒙皮是否减少肩肘与手指错误，原动作迁移成本是否可接受 |

A、B 共用同一低面数衣物与外观，避免同时换模型与动作后无法定位效果来源。最初模拟预算可从每件局部衣片约 500–2000 个顶点开始，这是实验预算，不是已测出的性能保证。A 优先做，B 并列试袖口；C 在 NVIDIA 环境条件允许时另做。

验收先看实机：原脸、发型、配色与衣物轮廓；站立、走路、跑步、举手、交叉伸手、弯肘转腕、蹲伏及舞蹈；再检查穿模、袖口抖动、脚底滑动、停下后稳定与瞬移复位。原 11 个动作名称、时长、手掌检查和 CharAnim 兼容继续保留。额外用未参与修形制作的动作检查泛化，记录 30/60 FPS 下的 CPU/GPU 开销。

## 证据与当前状态

资料、仓库元数据和下载代码摘要放在 `evidence/character_algorithm_research_20261004/`：

- `repositories.json`：本轮读取的仓库许可标识、分支、最后 push 时间等，不能仅按星数判断成熟度。
- `supplementary-metadata.json`：RBF 许可状态与 DQS PR 状态。
- `source/download-index.json`：代码与许可证 URL、字节数和 SHA-256；没有执行下载代码。
- 下载的关键实现：Robust Weight Transfer、GPU XPBD solver 与 skin pass、RBF driver，以及相关许可证与 manifest。

当前可运行版本仍是 binding13_sleeves。以上候选均没有被描述为“已经修好了本人物”；下一步需要在独立 POC 中实测。

后续实测：本机 Metal、Morph 适配、原生弹簧骨与 GPU 袖片已在独立工程测试并录制三组对照，见 [衣物运行时 POC](CHARACTER_CLOTH_RUNTIME_POC_20261004.md)。原调研轮的“未实测”状态只描述当时。
