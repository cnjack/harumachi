# 猫的摆尾、张望与全身步态（2026-10-07）

这页保留上一轮制作与数据。用户后续再次指出脸朝向、脚步和尾高问题，当前正式版本与复验见 [持续张望、小步与低尾](CAT_MOTION_REVIEW_20261007.md)。

用户指出橘猫走路昂头、两只猫夹尾，随后要求尾巴明显而灵动地摆动、身体更协调，并补充头部只看一个方向、尾巴像折起来。最终版本已接入两只镇上巡游猫的正式 GLB；桌面编译包没有重新导出。

## 当前动作

- 每只猫保留原 Hyper3D 网格和 UV，使用 59 关节；尾链 12 节，每耳 4 节。经过实际 Godot 导入验证，网格使用最多 8 个骨骼影响。
- Walk 是新编写的四拍步态，10 秒片段包含八个步态周期，每周期 1.25 秒、位移步幅 0.15 m，对应游戏 0.12 m/s。站立阶段用双骨 IK 保持爪部接地，摆动阶段抬爪；胸肩和臀部反向小幅摆动，头部比肩部更稳定。
- 橘猫头颈前移、降低，保留 14° 的低头修正。慢走中加入独立于脚步的缓慢左右张望；两只猫的头部方向范围约 32°，颈部一起跟随，不再只盯着前方。
- 尾根从臀部平顺向后伸，后段逐渐弯曲；摆动角度沿尾链延迟传播，尾尖有较大摆幅与少量第二谐波。尾根不再保留尖锐向上的转折。
- Idle 是 8 秒的呼吸、张望、耳朵轻动和尾尖轻摆。停止时仍有动作，Walk/Idle 继续使用现有动画混合。其他片段仍是原 Mesh2Motion 动作的迁移对照，不宣称完成完整宠物表演系统。

这次慢走与待机是程序步态、爪部 IK 和尾链动作制作，不是新下载的 AI 动作模型输出。此前下载运行的 MagicArticulate 只参与骨架预测对照。

## 绑定修复

单纯抬起原尾链会拉扯臀部与后腿。检查真实变形后，裁去旧尾链深入臀部的参考段，按实际尾管重新分配权重，移除非尾部的错误影响。旧模板权重还在相邻顶点间混用了左右腿；本轮改用解剖距离场，并在物理重合顶点合并的邻接图上平滑。只统一接缝顶点的权重，不焊接网格或改 UV。

固定截成四个影响，会在第五个权重与其他值接近时突然换掉一个骨骼，形成局部裂扯。改为最多八个影响，并用 Blender 5.2 的 `export_influence_nb=8` 导出；GLB 包含 JOINTS_1/WEIGHTS_1，Godot 原生画面及网格格式检查确认实际启用八权重。

Godot 将 glTF 的自定义字段放在 `meta.extras` 字典里。`cat_walker.gd` 现在从 Skeleton 与祖先节点的 extras 读取 `walk_speed`，同时兼容旧的直接 metadata；避免忽略资产原生步速而导致滑步。

## 实测证据

`audit_motion.py` 对导出的 GLB 重新导入，取完整片段的 121 个时刻，计算实际蒙皮爪部、尾端、胸臀转动、接缝和网格边。旧版本在摆尾、胸臀配合、张望等检查中失败；最终两只猫共 21 项检查通过。

| 指标 | 橘猫 | 三花猫 |
| --- | --- | --- |
| 实际蒙皮尾尖左右摆幅 | 10.55 cm | 11.86 cm |
| 头部左右方向范围 | 31.91° | 31.54° |
| 尾链最大相邻方向变化 | 5.39° | 5.62° |
| 站立爪部最大地面偏差 | 0.31 mm | 0.34 mm |
| 站立阶段最大滑动 | 0.12 mm | 0.14 mm |
| 胸臀反向转动相关系数 | -0.989 | -0.989 |

这些接地和滑动数据对应平地直线步态，不代表转弯、所有地形或所有片段完全没有滑动。局部网格边仍有约 5.6 倍的最高拉伸候选；本轮将出现明显大片拉扯的错误权重修正，但不宣称完成全模型无变形验收。

`cat_motion_verify.gd` 检查正式导入资源：两只猫都是 59 关节、八权重网格、Walk 10 秒、Idle 8 秒、原生步速 0.12 m/s、头部左右张望和明显尾摆，均通过。主游戏测试集没有新增计数；独立验证脚本保留为后续资产回归入口。

独立 Godot 4.7.2 Forward+ 对照录像为 30 秒，依次展示侧面、斜侧、后侧和待机。实际主场景录像用原 `AmbientLife` 与 `cat_walker.gd`，两只猫在街道行走、暂停和转向；设置独立存档目录、固定白天并关闭 NPC 走动作为拍摄夹具。默认存档摘要未变。完整结果在 `evidence/cat_lively_motion_20261007/`。LIVING 26 项与 PROPS 46 项通过；`verified-final.json` 汇总导入、动作、真实街道、存档和最终正式资源摘要。

完整主场景退出时保留了既有 material-null / 资源释放日志，不能写成整个项目无错误；实际动作期间没有脚本解析错误，独立资产预览与导入验证正常。

## 产物与复现

- 正式资源：`game/assets/models/AN_cat_orange_walk.glb`、`AN_cat_calico_walk.glb`。
- 可编辑文件：`art/poc/cat_lively_motion_20261007/outputs/coordinated/{orange,calico}.blend`。
- 三列对照录像：`evidence/cat_lively_motion_20261007/compare/coordinated-cat-motion.mp4`，左原动作、中仅改姿态、右最终全身动作。
- 实际街道录像：`evidence/cat_lively_motion_20261007/world/cats-in-street.mp4`。
- 源摘要、替换记录：`integration.json`；真实蒙皮检查：`motion-coordinated.json`；引擎资源检查：`game-assets.json`；场景遥测：`world/runtime.json`。

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_lively_motion_20261007/build.py -- orange
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_lively_motion_20261007/build.py -- calico
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_lively_motion_20261007/audit_motion.py -- coordinated
python3 art/poc/cat_lively_motion_20261007/render.py
python3 art/poc/cat_lively_motion_20261007/record_world.py
```

构建工具只输出到 POC。正式资源替换必须核对上一版本摘要，导入并复验实际场景；不要直接运行旧 `finalize_cat_assets.py` 覆盖这两份新绑定资源。
