# 空、莲：把腿部问题修回源资产（2026-10-18）

这轮修改了两个角色的正式 GLB，并使空的走路不再执行旧的逐帧膝盖重定向。绑定、源动画先成立，游戏里的鞋底接地继续处理地面适配。MotionBricks 仍是独立 POC，其 G1 重定向动画没有接入游戏。

## 原因与处理

| 人物 | 原因 | 本轮修改 | 独立验证 |
| --- | --- | --- | --- |
| 莲 | 左右大腿中段裤面仍有平均 80.8% / 91.4% 权重跟随骨盆，大腿骨转了，裤面留在原处 | 根据实际髋、膝、踝位置重建裤腿权重；围裙下摆连续跟随腿部，腰部保留固定；同步 UV 接缝副本 | 60° 独立抬髋时，裤面与所属大腿的偏离 p95 从约 28cm 降至数值误差；两侧中段权重归属各自大腿 |
| 空 | 权重和受控弯腿正常，原 walk 的膝弯曲平面内偏；此前只在游戏运行时纠正 | 将正确平面写入 walk 的双侧大腿、小腿、脚，共六条旋转轨道；运行时识别源资产标记并跳过旧纠正 | 原源动画最差内偏约 34mm，新源动画最小外向余量约 1.89mm；关闭所有游戏修正器的原生回归也通过 |

之前的 `4e04b36` 确实修改过绑定与骨架；后来的 `21f9340` 对空走路膝内扣的处理在运行时，未写回 GLB。因此，离开游戏修正器播放源模型时，问题仍能重现。本轮不把空的问题误归为蒙皮权重错误。

两人的骨骼 rest、inverse bind、网格位置、拓扑、UV、贴图、材质保留。莲的动画未改；空除 walk 六条旋转轨道外的动画未改。空保留原踝轨迹与脚朝向，1025 相位的脚/脚趾位置最大差约 0.0154mm。莲维持每顶点四个权重槽，7222 对原本重合且同权重的 UV 副本仍同权重。

完整回归还查出莲四处裤面 UV 接缝的旧 Local 衣物模板不一致：两份重合副本一份为零，一份带最多约 7.68cm 的围裙位移。此前不同权重使它们未被旧接缝检查配成一组；其中一对新权重仅差约 0.00000024，原生导入也会识别为同一接缝。最终 v8 把四个裤面顶点的误用 Local POSITION 值归零，与其另一副本一致；其他形态键数据保留。原生接缝间隙从 v7 反例的约 7.32cm 降到零，原 0.1mm 门槛不变。独立审计也检查近等权重 UV 副本，未降低穿透或模板限幅标准。

## 源文件与运行时

当前两人源文件在 `art/models/character_leg_foundation_20261018/exports/`；游戏模型、素材库副本与该目录逐字节一致。来源、旧摘要、新摘要及原 Hyper3D 来源登记在 `art/manifests/character_leg_foundation_20261018.json`。历史 Blender 文件保留，但没有把它描述为包含本轮改动；当前可重现来源是已登记 GLB 和修复脚本。

`NaturalLocomotionPose` 读取 `Rig.extras.leg_foundation.walk_knee_plane_authored`。空 walk 的源动画已负责膝盖方向，因此不再调用旧 `_place_ankle` 覆盖它。`CharacterFootSupport` 继续按实际地面处理鞋底接触；既有站姿、其他人物、跑步手臂和手型调整仍保留。本轮没有宣称七人的全部运行时姿态调整都已迁回素材。

莲的新权重需重新取得衣物证明，不能沿用旧 GLB 的通过记录。新证明使用原生最终骨架、两个实际根高度，各对 idle/walk/run 采样 128 相位，共 768 个姿态；关闭 Local 衣物求解，真实形态权重均为零。保留原 4625 个身体顶点，并在每个姿态检查 58758 个源面采样点，仍使用原 5mm 穿透和 0.35 法线门槛。最差约 4.55mm，额外源面采样点测得的穿透为零。清理裤面模板后，五个误受 Local 影响的裤面三角面不再归入该补充衣面集合；独立颜色衣面、身体锚点及完整身体源面保持，并恢复四个额外混合 UV 身体查询点。证明只适用于匹配模型/指纹的稳定动作，切换和其他动作仍有原回退路径。

## 验证与录像

证据目录：`evidence/leg_binding_foundation_20261018/`。

- `audit-sora-final.json`、`audit-ren-v8.json`：同一独立标准检测旧版失败、新版通过，并核对受保护源数据。空 v3/v6 文件摘要相同；莲最终使用 v8。
- `source-negative-control.json`：原生源动画回归在旧空 GLB 上失败；关闭全部游戏修正器后仍检测到约 34mm 内扣，不能靠运行时补偿通过。
- `surface-root-zero-v8.json`、`surface-root-010-v8.json`：最终模型重新取得的 768 姿态衣物证明及原始测量。
- `game-v6-rendered/locomotion-poses/` 中的空，以及 `game-v8-ren/locomotion-poses/` 中的最终莲：idle/walk/run，各四相位、前后左右顶部，共 120 张真实游戏画面。逐张同帧姿态核对通过，并用六张分人物/动作联系表复查。莲最终 60 张均匹配当前证明，真实 Local 衣物权重均为零；清单见 `native-visual-review.json`。
- `game-v6-rendered/continuous/` 中的空，以及 `game-v8-ren/continuous/` 中的最终莲：walk/run 的正面、侧面，共八段实际 Player/NPC 移动（莲run明确使用NPC跑速夹具，不宣称完整剧情路线），均超过两个循环，记录无失败。先前 v6 的 transitions 后续任务中断，不计为完整切换录像验收。
- `garment-local-v8-tests.json`：41项衣物专项全部通过。
- `full-v8-tests.json`：当前组合2601/2601项独占完整功能回归通过，退出0、713.33秒，含93项步态、98项摆臂/手型和47项手势；41项衣物专项及768姿态新模型证明通过，原5mm穿透和8ms求解门槛不变。120张五方向游戏画面及八段实际移动采样已复核，默认104份存档摘要不变。运行耗时不含导入。原始日志和错误分类见 `full-v8-log-classification.json`；运行72条ERROR均为既有Dummy材质或数据库/照片故障注入，导入1条为Adaptive主题环境错误；无SCRIPT/SHADER及未分类错误，严格无ERROR资格为false。两条24秒1080p30源模型对照视频已完成逐帧与完整解码检查；关闭全部游戏修正器展示修前/修后，包含走路、跑步和抬腿压力动作。自然度待用户复评，MotionBricks仍为独立POC，桌面ZIP/Web未更新。
- `reproducibility-final.json`：从上一轮登记源文件重新生成两份模型，摘要与最终素材逐字节一致。
- 两个 `video-*-final/media-verification.json`：每片720帧、1920×1080、30fps、24秒；12张原生同帧图与MP4解码匹配、连续样本时钟、全帧解码和来源摘要均通过。

源模型对照录像各 24 秒、原生 1080p30：左为修前，右为修改后。前 6 秒走路，随后 6 秒跑步，最后 12 秒为交替抬髋/屈膝的绑定压力动作。整个对照场景不加载游戏步态、接地或衣物修正器，因此跑步手臂仍呈现原素材姿态；游戏内已经调整的手臂以正常游戏检查为准。

- [莲：源绑定前后对照](../../evidence/leg_binding_foundation_20261018/video-ren-final/video.mp4)
- [空：源动画前后对照](../../evidence/leg_binding_foundation_20261018/video-sora-final/video.mp4)

本轮按用户要求未创建虚拟显示器；使用现有屏幕、不抢焦点、Dummy 音频和隔离存档。原生渲染逐帧写 PNG，再编码视频。窗口被遮挡时可能停止递增普通窗口 draw counter，故显式绘制视口，并用实际样本时钟、骨姿态、帧摘要和解码像素校验映射；不把这个 counter 当录像时钟。

技术检查不等于用户自然度认可。高抬腿压力动作显示蒙皮跟随能力，不代表该姿势是游戏动作或物理布料模拟。MotionBricks 的机器人动作到人物的重定向还需单独验收；既有 POC 和历史视频没有被本轮替换。桌面 ZIP、Web 未发布。

## 重现

Python 需 numpy、scipy、Pillow。修复工具只接受新的输出路径，不覆盖源模型。以下从上一轮已登记源文件重建：

```sh
python art/tools/characters/repair_leg_foundation.py --character sora --input art/models/character_rig_review_20261018/exports/CH_sora.glb --output /tmp/CH_sora-leg-candidate.glb --report /tmp/sora-leg-repair.json
python art/tools/characters/repair_leg_foundation.py --character ren --apron-follow --input art/models/character_rig_review_20261018/exports/CH_ren.glb --output /tmp/CH_ren-leg-candidate.glb --report /tmp/ren-leg-repair.json
python art/tools/characters/audit_leg_foundation.py --character sora --source art/models/character_rig_review_20261018/exports/CH_sora.glb --candidate /tmp/CH_sora-leg-candidate.glb --output /tmp/sora-leg-audit.json
python art/tools/characters/audit_leg_foundation.py --character ren --source art/models/character_rig_review_20261018/exports/CH_ren.glb --candidate /tmp/CH_ren-leg-candidate.glb --output /tmp/ren-leg-audit.json
```

`prepare_leg_foundation_preview.py --before <旧GLB> --after <新GLB> --character <sora|ren> --project <新临时目录> --output <证据目录>` 生成独立 A/B 场景；固定引擎先 import，再带 `--audio-driver Dummy -- --record` 原生运行，最后 `encode_leg_foundation_preview.py <证据目录>` 编码和全解码核验。画面输出显式调用 `RenderingServer.force_draw(false)`，同样的 QA-only 能力可由 `tools/character_review/capture.py --force-render` 启用。
