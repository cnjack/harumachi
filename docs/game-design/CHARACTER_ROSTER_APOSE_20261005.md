# 七人人物 A pose 制作与游戏接入

更新：2026-10-05。制作目录沿用 `character_roster_apose_20261004`。空、澪保留用户满意的外观和绑定，肩袖再小幅下落；莲、春、田中爷爷、小葵、和子阿姨依据原设定重画正背参考，再各提交一次 Hyper3D Rodin High Quad 生成。共 5 个付费模型任务，没有额外提交失败候选。当前七人的正式游戏 GLB 已替换，旧七人完整保存在 `art/models/archive/characters_before_apose_20261004/`。

## 姿势与外观

新参考采用手臂向下约 45° 的 A pose，手与腰分开、掌心朝身体、腋下留出完整衣服。生成服务并不精确执行角度；下表是源网格手臂拟合测量，库中也显示实际值。人物原脸、发型、衣服颜色和主要配饰以原设定为准；身高沿用游戏配置。

| 人物 | 身高 | 原稿手臂相对水平线下垂角 | 采用的绑定 |
| --- | --- | --- | --- |
| 空 | 1.62 m | 已验收 T pose，肩袖姿态修形 | 代理人体转移、肩袖修形、限幅袖口次级运动 |
| 澪 | 1.58 m | 已验收 T pose，肩袖姿态修形 | 同上 |
| 莲 | 1.76 m | 46–50° | 焊合重合顶点后的自动热权重、围裙躯干权重 |
| 春 | 1.52 m | 50–51° | 自动热权重、马甲与口袋内手套归躯干 |
| 田中爷爷 | 1.60 m | 30–38° | 自动热权重 |
| 小葵 | 1.30 m | 43–45° | 重新测量身体中心、代理转移、袖口实际皮肤区域修正 |
| 和子阿姨 | 1.56 m | 约 40° | 自动热权重、披肩渐变权重、随动作变化的围裙净空修形 |

参考图在 `art/references/characters_apose_20261004/`。原始服务输出在 `art/models/raw/CH_<人物>_rodin_apose_20261004/`。作业 ID、原图、请求参数和摘要分别记录在 `characters_apose_20261004.json`、`models_hyper3d_characters_apose_20261004.json`；图片和最终选用提示词已登记 `images_codex.json`。没有保存有时效的下载 URL。

## 实测后选出的处理

只换自动绑定工具不能解决全部问题。glTF 的 UV 接缝会拆顶点，直接运行热权重曾留下大量未绑定顶点；仅焊合空间完全重合的顶点（1 微米），保留每面 UV，才使四位成人的热权重稳定。小葵仍不适合这条路，采用校正后的代理转移。手和手指保留已拟合的权重，不交给无法区分手指的粗自动绑定。

七人均使用 54 根人物骨，其中 30 根手指骨和 2 根前臂扭转骨。空、澪各增加 12 根袖口辅助骨，游戏总骨数为 66；其他五人总骨数为 54。原游戏 11 个动作名称和时长完整保留，另带 `reference` 原稿姿态。人体动作由原 CharAnim 驱动，步速和脚步事件继续使用原规则。

空、澪的四个肩袖修形沿用已验收实现，外肩下落参数从身高比 0.010 调至 0.016。袖口采用已实测的 Godot 原生 SpringBoneSimulator3D，四条短链，角度限幅 12°。新五人使用实测更稳定的权重结果，不统一强加试验中更差的弹簧布料版本。

和子阿姨经历了额外迭代。按颜色硬分衣物，会误把袖口或被围裙投影成黄色的内部裤面归进披肩、围裙；只看颜色不足以识别衣服。最终使用网格相连区域、表面前后层检测和局部权重平滑。删除内部裤面的候选导致围裙下方露空，已经拒绝，最终保留所有原外观三角面。围裙净空由实际姿态的裤面射线测量，烘焙成一个 `Apron_Clearance` 修形随各动作播放，避免迈步时裤腿穿到前面。它是当前动作的修形，不是通用布料物理。

试验中的切缝、程序袖筒、过宽服装蒙版和五人弹簧衣物候选都保留在制作目录与证据中，未作为最终导出。

## 接入、导出与回滚

最终候选为 `art/models/character_roster_apose_20261004/exports/CH_*.glb`；正式文件为 `game/assets/models/CH_*.glb`。七份文件逐一核对 SHA-256 相等。`game_assets.json` 的七个 CH 配方指向这些完整骨骼资产，启用 `preserve_rigged_character`。`game_export.py` 会检查动作和 skin 后原样复制，避免静态合并、减面再把手指、修形和动作去掉。

运行时共用 `game/scripts/characters/character_clothing.gd`，由 CharAnim 根据 Rig 元数据挂载；没有衣物元数据的角色使用普通动作绑定。衣物跟随器先更新手臂碰撞体，弹簧随后运行，最后只限幅辅助骨。原人物动作骨不受限幅影响。

制作工具在 `art/tools/characters/`。`build_roster.py` 只制作基础候选；不能把它的第一版代理权重直接当成最终版。最终成人走 `heat_trial.py` 与对应躯干处理，小葵走 `aoi_skin_patch.py`，和子另走 `kazuko_garments.py`、`kazuko_apron_clearance.py`。空、澪沿用 accepted-shoulders 与 clothing 的已验收源文件。所有选用的 Blender 文件位置在 `art/manifests/character_roster_20261004.json`。

资产检查与库更新：

```bash
PY=/Users/jack/.copilot/session-state/ca10e179-b441-4d77-b938-250cea2ee4c6/files/venv/bin/python
"$PY" art/tools/characters/audit_roster.py
python3 art/tools/build_asset_library.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 -P art/tools/render_asset_library.py -- 0 1 --characters
```

重新导出后必须重新生成实际库存和支撑面测量、Godot import、相关测试与近景。level_check.py 对含骨架的模型自动清除动作叠层和修形后测量原稿支撑面；避免把 Blender 导入后叠加的多个动作当成模型原稿。回滚时从 archive 恢复旧 GLB，同时把对应导出配方指向 archive；不要只换正式文件而保留新配方。

## 人物模型库

[本机人物库](http://127.0.0.1:8787/art/library/#game%2FCH_kazuko) 增加“人物角色”与“人物原稿”：7 个已接入游戏角色、7 个静态来源原稿。支持原 11 动作、原稿姿态、暂停、速度、骨架显示、旋转和线框；可下载正式 GLB、原始 GLB、正背参考与可编辑 Blender 文件。Blender 下载副本打开时处于参考姿态；动作仍保留在 NLA 轨道，单独取消所选轨道静音后播放。制作原文件未覆盖。

浏览器使用四权重预览文件，展示人体与修形动作；空、澪的衣物次级运动在实际 Godot 中运行。许可按项目人物及 Hyper3D 账户来源条款记录，人物集合没有标成 CC0。

## 验证与证据

证据目录：`evidence/character_roster_apose_20261004/`。

- `asset-contract.json`：七人原外观三角面与 UV 保留，顶点与 UV 最大数值误差小于 3×10⁻⁷；权重归一、骨索引、30 手指骨和原 11 动作时长均通过。
- `spikes-before.json` / `spikes-after.json`：真实短边在动作中变成 7 厘米以上尖条的检查，原坏候选最多 631 条，最终 0；保留相同门槛。
- `apron-clearance-before.json` / `apron-clearance-after.json`：9 动作、153 姿态，每姿态 978 个裤面采样。5 毫米以上穿透最多由 93 处降至 0；旧版最深 12.6 厘米。仅代表该采样范围。
- `final-game-tests.json`：661 项完整游戏检查全部通过，退出码 0，无 SCRIPT ERROR。原首次 659/661 的两项失败是新人物的库存、支撑面统计未刷新；重新实际测量后通过，没有放宽门槛。
- `roster-before.mp4`、`roster-after.mp4`：分别 27.77 秒，1920×1080，30 FPS，833 帧；相同动作顺序和正侧视角。`roster-comparison.mp4` 左旧右新。`roster-after/runtime.json` 验证七人的 CharAnim，以及空、澪限幅运行。
- `game-shots-final/`：游戏原场景中的七人招手、走路、跳舞实景。`library-characters.jpg` 是实际浏览器界面；`library-ui-checks.json` 是七人动作、骨架、暂停的实际操作结果，浏览器无错误。
- `library-download-contract.json`：42 个正式模型、预览、原稿、Blender、正背参考下载均返回 200，内容摘要与磁盘相符。

日期包为 `builds/HareMachi-characters-20261005.zip`，冻结源码为 `builds/character-roster-source-20261005/game`。导出应用的实景、完整剧情与保存校验结果统一写入本轮 `verification.json`，默认包仅在这些验收完成后更新。

后续换装应沿用这套骨架，制作独立衣服和完整基础身体，再做对应遮挡与动作检查。当前新五人仍是整身外观网格；本轮完成的是外观、绑定、原动作与游戏接入。

交互对照：双击 `art/poc/character_roster_apose_20261004/launch.command` 打开新版，命令行加 `--before` 打开旧版；左右键切动作、V 切正侧面、空格暂停。

## 本轮发布验收结果

日期包与默认 `builds/HareMachi.zip` 已更新为七人人物版，1611721351 字节，SHA-256 `5adab8c32b29efda77a72e212f3a76aeb212d9d578f4232eb957c2290f7c60e6`。旧默认包保存在 `builds/HareMachi-before-characters-20261005.zip`。ZIP CRC、严格签名验证及 x86_64 / arm64 双架构检查通过。解压应用的七人实景与完整剧情通过，实机 333.97 秒，模拟 1230.9 秒，44 张截图，Q05 完成，退出码 0，无 SCRIPT ERROR。SQLite quick_check 为 ok，v4 保存快照摘要通过。退出时仍有一个既有 shader RID 泄漏提示；旧树版本同样出现，完整流程与退出状态正常。总验收为 `evidence/character_roster_apose_20261004/verification.json`，release_ready=true。

支撑面工具补充：对带骨架的文件默认按无动作、无修形的原稿测量。七人的结果与各自实际静态源文件一致，见 `default-neutral-source-contract.json`。早期缓存记录的是 Blender 导入后的姿态；本轮没有据此旋转或修改人物。此项只改离线诊断工具，游戏模型与已验收包保持同一摘要。
