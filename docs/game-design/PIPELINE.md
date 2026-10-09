# 模型、工程与交付流程

当前事实见[CURRENT_STATUS](CURRENT_STATUS.md)，精确引擎入口为`./tools/godot`。早期失败与日期补充保存在[历史流程记录](history/PIPELINE_HISTORY_20261007.md)，旧数字和旧包不代表最新状态。

## 当前运行与交付

1. 运行`./tools/godot --version`核对4.8-dev7；`python3 tools/install_godot_templates.py --platform all --evidence evidence/<本轮目录>/templates`安装同版本macOS及Web模板。
2. 模型、脚本与资源修改后先import。全量使用本轮独立存档、超时和独占监测，检查退出码、SCRIPT ERROR、shader错误与报告。
3. 改模型、镜头或布局必须原生截图；吃饭用真3D食物/空盘，人物不重新生成。CLI生成模型记录来源和任务ID，付费前说明。
4. 桌面冻结、导出、解压、签名/架构检查、完整autoplay退出0，再原子替换HareMachi.zip。保存摘要、截图、默认存档前后和清理记录在evidence。
5. 临时冻结/解压/导出都在本轮临时目录，完成清理。builds最多ZIP+web；旧历史包不得重新堆回去。
6. Web在独立副本由prepare_web切Compatibility，保留UI图集像素坐标、原音频与骨骼。浏览器启动/保存刷新/继续通过才替换Web；线上部署单独按site/README管理。

常用命令与测试组见[AGENTS.md](../../AGENTS.md)。原生Cua持续按键已可用，普通首餐和入口已测；连续三天/两条自然整篇未完成。技术、普通AI与真人体验证据分开。

## 1. 模型服务：从 Hyper3D 换成混元

用户指定的是 Hyper3D Rodin。接入时 Blender MCP 里的 Hyper3D 试用 key 返回 `API_INSUFFICIENT_FUNDS`，完全没法生成。经用户同意，改用腾讯混元 3D `hy-3d-3.1`（TokenHub 接口），调用封装在 skill `~/.agents/skills/hunyuan-3d/scripts/hy3d.py`。

所以 v0.1–v0.3 的模型来源都是混元，manifest 里也是这么记的。

**v0.4 起恢复使用 Hyper3D Rodin。** 用户充值后，通过 hyper3d MCP 工具直接调用（不经过 Blender MCP）：`rodin_create_uploads` 拿预签名上传地址 → `curl -X PUT` 上传参考图 → `rodin_generate`（Gen-2.5，Raw 网格，GLB）→ `rodin_wait` 轮询 → `rodin_get_result` 拿到带签名的下载地址 → 保存到 `art/models/raw/<ID>_h3d/model.glb`。27 个任务全部记在 `art/manifests/models_hyper3d.json`（generation_id、档位、面数、参考图、验收结果）。签名下载地址有时效，不写进 manifest；查看结果用 `https://hyper3d.ai/workspace/rodin/<generation_id>`。

| 批次 | 内容 | 档位 / 面数 | 结果 |
| --- | --- | --- | --- |
| 重做最差的 5 个 | M03 二层人字屋、M12b 灌木、M12d 绣球花丛、P05 滑梯、P06 沙池 | 房子 High 60k，其余 Medium 30k–40k | 全部采用（原来的混元版本记在 `game_assets.json` 的 `prev_src`） |
| 新的庭院大树 | T01 榉树 | High | 第一版只有枝干、树冠没长出来，退回；换一张“树冠是几团实心云朵”的参考图重做，第二版采用 |
| 新角色 | 田中爷爷、小葵（正面 + 背面两张参考图一起提交） | High 40k | 采用，再走 `rig_char.py` 绑定 |
| 农园与作物 | 工具棚、手压泵、堆肥箱、稻草人、温室、无人菜摊、木桥、菜地；幼苗、萝卜、小松菜、番茄、黄瓜、毛豆、向日葵、草莓 | Medium 10k–30k | 全部采用 |
| 小动物 | 睡觉的三花猫、麻雀、坐着的橘猫 | Medium 6k–10k | 全部采用 |

挑最差的 5 个模型的方法：把 78 个游戏 GLB 全部用无界面 Blender 渲两个角度，和参考图并排排成对比表（`/tmp` 下的临时图，没入库），逐个看。M03 是一团糊掉的形状（原参考裁图只有 242×432，还混着树叶），M12b、M12d 是扁平、像素化的一片，P05、P06 结构很弱。这几个的参考图先用 codex 重新画成干净的单体三视角图（`art/references/h3d/`），P05、P06 直接用原来 1024² 的裁图。

## 2. 参考图与生成

1. 把四张社区扩展图按编号裁成单体图，放在 `art/references/community/crops/`。一张图只留一个主体，去掉编号文字（`art/tools/grid.py` 用来画网格、核对裁切）。玩家房间的家具先用 codex 画一张家具设定图，再裁到 `art/references/interior/crops/`。
2. 角色另用 codex 画正面立绘和三视图，放在 `art/references/characters/`。
3. 每张图提交一个图生 3D 任务，按用途指定生成面数：9 个建筑和角色 40k，13 个中型道具 20k，8 件家具 15k，11 个小道具 12k。进 Blender 后再减面。
4. 45 个任务全部记录在 `art/manifests/models_hunyuan.json`，包括 job_id、提交时间、参考图、原始 GLB 路径和最终游戏文件的面数、尺寸、贴图大小。下载链接是有时效的签名 URL，没有写进 manifest。
5. 原始 GLB 保存在 `art/models/raw/<ID>/model.glb`，之后一律只读。
6. v0.3 的家具和庭院道具：codex 另画两张设定图（`furniture_sheet2.png` 日式家具，`furniture_sheet3.png` 玄关、缘侧和庭院道具），裁成 18 张单体图（`art/references/interior/crops2/`，J01–J09、G01–G09），用 `hy3d.py batch art/models/raw/jobs_house.json` 一次提交，每个 16k 面，18 个全部完成，用时约 22 分钟。批量命令会覆盖 `art/models/raw/manifest.json`，提交前先备份成 `manifest_v02.json`。G04 盆景生成出来像个花盆，没有用；其余 17 个导出进游戏。

先做了 P02 公告栏、P09 摊位、S02 面包店三个样件，在 Godot 里站在旁边比过比例、走近看过穿模，然后才批量提交。

## 3. Blender 整理（`art/tools/game_export.py`）

全程用无界面 Blender 跑，不开编辑器：

```bash
Blender -b --factory-startup -P art/tools/game_export.py -- art/models/game_assets.json [ID ...]
```

`art/models/game_assets.json` 给每个资产一段参数：

| 字段 | 作用 |
| --- | --- |
| `src` | 原始 GLB |
| `fit` / `size` | 按高度（h）或最长边把模型缩放到真实尺寸，单位米 |
| `yaw` | 转正，让正面朝 Blender −Y，导进 Godot 就是 +Z |
| `trim` / `cut_above` | 切掉生成时自带的地面裙边或顶部杂块 |
| `clear_inside` | 删掉内框里的面（比如摊位棚下多出来的实心块） |
| `min_island` | 删掉悬浮的碎片 |
| `keep_origin` | 默认把原点放在底面中心；需要时保留原点 |
| `tris` | 减面目标。建筑 20k，道具 4k–8k，家具 5k，角色 14k |
| `smooth` | 按角度平滑的阈值 |
| `tex` | 贴图缩到 1K 或 2K |
| `soil` | 种植箱的土面拆成单独网格，给种植状态换材质用 |
| `weld` | 减面前合并重合顶点的距离（相对尺寸）。Rodin 的植物网格一焊接就会出现非流形扇面，把减面卡在 30k 左右，所以 v0.4 的 Hyper3D 模型都设 `weld: 0` |
| `level` | v0.7.3。默认 `"auto"`：把模型立在它凸包最大的朝下的面上（见第 14 节）；这个面不到外形投影的 15%（作物、灯笼、人物）就不动。`true` / `false` 强制放平或不放平 |
| `tilt` | 放平之后再额外转一个轴角 `[ax, ay, az, 度]`，一般用不到 |

每个资产的处理顺序是：导入 → 合并 → 放平 → 转正 → 缩放 → 切裙边 → 定原点 → 减面（v0.4 起最多重复 5 轮，直到面数不超过目标的 110%）→ 平滑 → 缩贴图 → 改成哑光材质 → 导出 GLB（JPEG 贴图），并写 `_stats/<ID>.json`（里面有放平前后的倾角 `lean_src_deg` / `lean_deg`）。`art/tools/ce_preview.py` 会从前、后、左、右和俯视出预览图，逐个检查。**导出之后要跑一次 `level_check.py`**（第 14 节），PROPS 测试读它的结果。

v0.4 之后是 100 个游戏用 GLB，约 76 万三角面、57 MB（v0.3 时 78 个、约 64 万面），其中 27 个来自 Hyper3D。v0.3 的数字：78 个游戏用 GLB，约 64 万三角面、47 MB（v0.2 时是 61 个）。其中 47 个来自这次的 45 个任务（种植箱 H12a 拆成箱体、植物、整体三份）；另外 14 个（灯笼、长椅、自动售货机、自行车、町屋等）复用上一轮新海诚街景做的混元模型，用同一个脚本重新减面导出，来源记在 `art/models/game_assets.json` 的 `provider` 字段。

## 4. 角色绑定（`art/tools/rig_char.py` v3）

生成的角色是一整块静态网格，不带骨骼。绑定脚本同样在无界面 Blender 里跑：

```bash
Blender -b --factory-startup -P art/tools/rig_char.py -- art/models/static_chars/CH_x.glb out.glb [预览目录]
```

1. 按网格包围盒比例放一套人形骨骼：髋、脊柱、胸、颈、头，双臂到手，双腿到脚。
2. 这些网格用自动热权重会失败，所以按几何位置自己算权重：
   - 左右腿按离中线的距离柔和过渡，中间留一条混合带，裙子和宽裤不会被撕开；
   - 大腿根往髋部混合，宽松衣服往髋部靠；
   - 手臂按离躯干的距离分配。
3. 生成三段动画：
   - idle：48 帧，缓慢呼吸，头部轻微摆动；
   - walk：22 帧，按 8 个相位查表驱动髋、膝、踝弯曲，右腿比左腿晚半个周期；支撑脚落地时骨盆下沉，脚跟着地、脚尖离地；髋部左右扭转、上身反向转，手臂摆动带手肘弯曲；
   - 从正面、背面看的动作（v3 补上的）：两只脚落在靠近中线的两条线上，而不是模型站姿那样分得很开；骨盆每一步移到支撑脚上方（约身高的 1.9%）；摆动腿一侧的骨盆下沉 5°，每步换一边；每一帧重新算两条腿的内收角，让踩在地上的脚不跟着骨盆滑动，脚掌保持水平，头保持端正；
   - 摆臂（v3 之后又修过一次）：生成的角色是 A 字站姿，手臂离开身体 8–22°。以前统一放下 22°，结果有的角色手插进了上衣和裤子，往前摆时还会越过中线。现在每个角色单独算放下的角度：手垂到身体最宽处外侧约身高 2.5% 为止（sora 左 9.7° / 右 11.3°，mio 5.8° / 8.8°，ren 1.6° / 2.5°，haru 12.4° / 12.4°）。摆动前后不对称，走路向前 11°、向后 20°，手肘主要在向前摆时弯（−24°），向后时几乎伸直。走路上身前倾 3°，跑步 7°；
   - 跑步摆臂（再修一次）：之前跑步时大臂只在 −34°（肘在身后）到 +17° 之间动，主要是小臂在肩膀旁边上下甩，看起来大臂没动。现在大臂向前 26°、向后 44°，量出来是 −55° 到 +19°（四个角色差 ±3°）；手肘固定弯 82–88°，整条手臂作为一个整体摆；跑步时手臂比放松站姿多张开 6°，向前摆时大臂绕自身长轴内旋 26°，手收到胸前而不是抬到肩旁；锁骨跟着摆动转 4°，上身反向转从 9° 加到 12°。走路的参数没有变。这里的角度是上臂骨在侧面（Y–Z 平面）上偏离竖直向下的角度，正值表示肘在身体前面；改前改后对比图在 `evidence/run_arm_before_after.png`；
   - run：16 帧，步幅更大、膝盖抬得更高，节奏更快；
   - v0.4 的 7 段手势：wave（举右手挥两下）、bow（鞠躬）、look（左右张望）、stretch（伸懒腰）、cheer（双手举高）只播一次；tend（弯腰照料作物）、talk（说话手势）循环。每段都从 idle 的放松站姿开始、回到它结束，腿部骨骼也打关键帧（固定在站姿），这样在 Godot 里从走路切过来时腿不会留在半步上。预览时要先把 NLA 轨道静音，否则底下的 walk/run 会叠上来。
4. 从支撑脚的移动距离算出每段动画对应的地面速度（主角走约 1.42 m/s、跑约 2.39 m/s，按各人身高不同），作为 glTF extras 写在 `Rig` 节点上。

v0.4 用同一个脚本重新绑定了全部 6 个角色（新增田中爷爷、小葵），走路和跑步的速度和 v0.3 完全一致（sora 1.417 / 2.385 m/s 等），说明步态没有被动到。

v1（只有整腿前后摆，看起来像两根筷子）和 v2（侧面正常，但从背后看两条腿仍是分得很开的两根直杆，骨盆侧倾方向每步不换边）都备份在会话目录，没有放进项目。脚本会从侧面、正面和游戏镜头的 35° 俯角前后各出一组预览，用来检查这两个方向。

## 5. Godot 接入

- 引擎固定Godot4.8-dev7，精确版本由`tools/godot-version.json`指定，入口为`./tools/godot`。使用相同4.8.dev7模板；不要依赖可能被覆盖的全局应用。4.7.2是历史基线，不能混用旧模板。
- GLB 直接放 `game/assets/models/`，由 `world_builder.gd` 按 `layout.gd` 的表格摆放，不手动拖场景。重新导出 GLB 不会丢掉交互和碰撞。
- 碰撞用简单的盒子（`add_box_collider`），不做逐三角形碰撞；地面、墙、建筑分层。
- 交互点和 NPC 站位写在数据里，换模型不用改玩法代码。
- 角色 GLB 导入后的结构是 `Rig/Skeleton3D/CH_x`，加一个带 idle、walk、run 的 AnimationPlayer。`CharAnim`（`game/scripts/player/char_anim.gd`）负责：
  - 读取 `Rig` 的 extras，拿到每段动画的原生步速；
  - 实际速度超过 2.85 m/s 用 run，否则用 walk，停下用 idle，切换时混合 0.22 秒；
  - 播放速率 = 实际速度 ÷ 原生步速，走限制在 0.6–1.35 倍，跑 0.8–1.45 倍。到了上下限宁可有一点滑步，也不让腿乱抡；
  - 模型没有动画时返回 invalid，玩家和 NPC 退回到原来的程序化上下起伏。
- 玩家速度：走 1.8 m/s，跑 3.7 m/s。
- 每次脚跟着地（walk / run 动画的 0 和 0.5 相位），`CharAnim` 发出 `stepped` 信号，驱动脚步声。

## 6. 玩家的家（`game/scripts/world/house_builder.gd`）

家是一个 `HouseBuilder` 节点，全部由脚本里的几张表搭出来：`ROOMS`（房间范围、地面、脚步声）、`WALLS`（墙线和上面的门、玻璃拉门、窗）、`FURNITURE`（模型、位置、朝向、碰撞）、`POINTS`（交互点）。坐标是相对家原点（`Layout.ROOM_ORIGIN`，z = 400）的米数。

- **剖面视角**：每面东西向墙挂在一个枢轴节点下。玩家进入某个房间时（`track_player` → `update_cutaway`），z 不小于这个房间南边界的东西向墙用 0.35 秒缩到 32 cm，门框横梁、窗格、玻璃一起隐藏；南外墙一直是矮的。墙的碰撞体不跟着缩，所以矮墙照样挡人；墙和家具在 `L_PLACED` 层，挡人不挡镜头，镜头的弹簧臂在家里也关掉碰撞。
- **地面着色器** `shaders/house_floor.gdshader`：一个着色器四种地面（木地板、榻榻米、洗石子、缘侧木板）。贴图按世界坐标采样，两种尺度混合去掉重复感；榻榻米按 1.8×0.9 米错缝算出每一块，每块换一点色相和纹理偏移，长边画布边（ヘリ），短边画接缝；靠墙的地方画一圈淡淡的暗边。
- **墙面着色器** `shaders/house_wall.gdshader`：灰泥贴图加低频手绘斑驳；0.86 米以下是竖向木腰板（用木地板贴图竖着铺，画板缝），上沿压一条深色压条；底部踢脚线，1.86 米门楣高度一条长押，顶部一圈天花边线。这些线脚都按世界高度画，墙被切矮时自然只剩踢脚线和腰板。厨房的瓷砖和客厅的隔扇纸用同一个着色器，关掉线脚。
- **卡通光照**：两个着色器和地毯着色器 `house_rug.gdshader` 的 `light()` 都是两段色阶：平行光在 0.5 附近做一个柔和的阶跃，受光面平涂，阴影面加 `shadow_tint`（淡紫）× `shadow_fill` 的补光；点光源分两级亮度。生成的家具模型进屋后由 `HouseBuilder.toonify()` 换成 `DIFFUSE_TOON`、关掉高光和金属度。
- **阳光与光柱**：屋顶不画出来，只用两块 `SHADOWS_ONLY` 的盒子投影（`ROOF_PARTS`）：缘侧上方的屋檐故意留短，下午的阳光能照进客厅深处；卧室那块屋檐到墙为止，格子窗的影子落在书桌和地板上。光柱 `_build_sunbeams()`：按白天的太阳方向（`SUN_DAY_ROT`，和 `WorldBuilder.apply_phase` 共用），从每个北面开口里屋檐挡不住的那一段，扫出 5 层平行的四边形薄片，一直落到地面。着色器 `house_beam.gdshader` 是加法混合、不写深度，从开口到地面逐渐变淡，两侧和斜看时淡出，拉门的柱子和窗格留出暗缝，还有缓慢漂移的条纹。傍晚光柱隐藏，太阳压低变橙，吊灯、台灯（带影子的点光源）和灯罩自发光亮起。室内还打开了体积雾、SSIL 和偏紫的环境光（`WorldBuilder.set_indoor_look`）。
- **窗外和院子**：厨房、客厅侧窗后面 12 cm 贴一张 codex 画的街景（`card_window`），面朝屋里，从外面看是背面被剔除，所以从院子里看不到。北面庭院画 `card_garden` 向后倾斜 47°，正对家里固定镜头的视线，看起来像一幅平整的背景画。四周是木板围墙。小镇的远景地面原来铺到 z = 400，正好盖住家的北院，现在收到 z = 360。
- **状态**：`sync_state()` 按标记切换纸箱（`house_tidy`）、缘侧金鱼缸（`goldfish_home`）和卧室墙上的地图相框（`map_framed`，贴图就是拼图小游戏的那张地图）。
- 贴图：7 张室内无缝贴图（木地板、榻榻米、灰泥、厨房瓷砖、洗石子、缘侧木板、隔扇纸）和两张背景画由 codex 生成，处理成 1024 px（背景 1536×1024），放在 `game/assets/textures/house/`。

## 7. 小游戏（`game/scripts/minigames/`）

- **基类** `minigame.gd`（`class_name MiniGame`）：统一的全屏框架——1640×960 的纸纹面板、标题、分数、剩余时间、底部操作提示，中间 1560×760 的舞台；状态机 规则卡 → 倒数 → 游玩 → 结果卡 → 关闭；星级、最好成绩、奖励回调（`GameState.record_minigame`）；Esc 离开（游玩中离开不记成绩）。子类只写 `mg_info / mg_build / mg_reset / mg_begin / mg_process / mg_input / mg_time_up / mg_result_lines`，外加三样便于测试和演示的东西：`mg_auto`（演示用的自动玩法）、`mg_simulate(skill, seed)`（不开画面、按熟练度算出一局的分数）、`mg_self_test`（至少 6 项自检）。
- **接入**：`GameUI.play_minigame(id)` 负责加载脚本、锁输入、藏 HUD，太鼓会先停掉镇上的音乐，结束后恢复；测试用的 instant 模式直接按熟练度 0.85 算一局。`Story.play_mg(id)` 从交互里调用它。暂停菜单的“小游戏记录”列出 4 个游戏的星数和最好成绩。
- **沙盒** `scenes/mg_sandbox.tscn`：`-- --mg=<id>` 直接玩一个；`--auto` 让演示 AI 玩；`--shots=<dir>` 每 1.5 秒截一张图；`--selftest` 跑游戏自检，再检查星级门槛递增、熟练度 1.0 必得 3 星、0 必得 0 星、同一种子结果相同、平均分随熟练度上升。
- **用 codex 做游戏**：每个游戏一份规格（玩法、时长、操作、星级思路、画面要求、可用的音效名），加上一份共同要求（都在 `art/manifests/prompts/minigames/`）（只能改 `mg_<id>.gd` 和 `assets/minigames/<id>/`，不许改基类，画面由 codex 自己生成并写 `CREDITS.md`，必须自检全过）。把 `game/` 复制 5 份到临时目录，用 `codex exec -s workspace-write` 同时跑 5 个任务，10–16 分钟全部完成，再把两类文件拷回工程。收回后逐个在 4.7.2 下自测、开窗口自动玩一局、看截图。统一修了一个问题：TextureRect 先设贴图、后设 `EXPAND_IGNORE_SIZE`，尺寸会被撑成贴图原始大小（饭团订单卡里的菜碗、太鼓的鼓都大得出框），把 `expand_mode` 挪到设贴图之前。太鼓的倒计时从 49.5 秒放宽到 52 秒，保证最后一个音符之后才结束。
- **太鼓曲子和谱面**：`art/tools/audio/taiko_song.py` 用合成器写一段 132 BPM、约 52 秒的祭囃子（篠笛旋律、締太鼓的八分音符、每小节开头的大太鼓、摇铃，谱面上的每个音符还有一声轻的引导鼓；玩家敲下去的响声由游戏播放），同时输出 `game/data/taiko_chart.json`（104 个音符，第一个音符在 3.636 秒），两者出自同一份节拍表，所以不会错位。游戏里用音频播放位置加输出延迟校正来算当前时间。

## 8. 音乐与音效

### 音乐（MiniMax Music 3）

四段音乐用本地部署的 MiniMax Music 3 生成（`/Users/jack/workpath/research/music`，社区移植的 MLX 8-bit 版，`mlx-serve 26.8.7`，只监听 127.0.0.1:11438）。

```bash
cd /Users/jack/workpath/research/music && ./run-server.sh      # 另开终端
art/tools/gen_music_minimax.sh [title day market ending]       # 请求在 art/manifests/music_minimax/<名字>.json，输出 art/audio/music_raw/<名字>.wav
<venv>/python art/tools/music_to_game.py                       # 切掉首尾静音，统一到 −20 LUFS、真峰值不超过 −1.5 dBTP，写成 game/assets/audio/music/<名字>.ogg
```

在 M5 Max 上，生成时间大约是曲长的 2–2.3 倍。请求格式是 `{prompt, lyrics, duration_seconds, steps: 30, seed}`，prompt 按 `### Global Metadata / ### Vocal Details / ### Timed Arrangement` 三段写：风格、调性、速度、编制，然后按秒写段落安排。

调提示词时踩过的坑（逐条记录在 `art/manifests/music_minimax/takes.json`）：

- `duration_seconds` 只是上限。歌词只写 `[Instrumental]` 时，模型大约 24 秒就收尾。
- 歌词里写 `[Verse]`、`[Chorus]` 这类段落标签能撑满长度，但模型会配上无词的哼唱。换成器乐段落标签（`[Piano Solo]`、`[Interlude]`、`[Strings Solo]`、`[Flute Solo]`、`[Break]`、`[Outro]`）后，长度够了，也没有人声。
- 在 prompt 里罗列“不要唱、不要哼、不要合唱……”没有用，可能反而把人声引出来了。改成正面描述（“Pure instrumental chamber piece for piano, strings and celesta only”，`Vocal Details` 写 None）效果更好。
- 写满上限的曲子会在上限处直接截断。循环播放的曲子无所谓，结尾曲不行：把上限设得比计划的结尾长（60 秒），段落安排里写明最后一个和弦“自然衰减到完全安静，之后不再开始新的内容”，得到一条 37 秒、自然收尾的版本。

人声检测（`art/tools/music_vocal_check.py`）：只用 Whisper 转写会漏掉无词哼唱，所以每条都做两项独立检查：

- demucs（htdemucs）分离出人声轨，记下人声轨和整段混音相差不到 12 dB 的秒数；
- AudioSet 分类模型（AST）分别给人声轨和整段混音的每 4 秒打分，看 Singing / Humming / Choir / Speech 等类别。

拿之前代码合成的标题和白天音乐（不可能有人声）做对照，两项都没有报警。前几版的标题、白天和结尾都检出了哼唱（人声轨 Humming 最高 0.49，混音里出现 Female singing），集市有一段像约德尔唱法的声音，都换掉了。最后留下的四首，人声轨最高分分别是 0.05、0.11、0.30、0.03，混音最高 0.04。集市那一格在 40–46 秒，比混音低 28–60 dB，实际听不到。

MiniMax 生成的曲子有前奏和结尾，不是无缝循环，所以音乐不再用 Vorbis 的 loop 标记。`Audio._maybe_loop()` 在曲子结束前 3 秒启动第二个播放器，从头交叉淡入。结尾曲单独播放一次，放完后回到原来的曲子。

许可：权重受 MiniMax-Music3 Community License 约束。用于商业产品时要在界面上显著标明“MiniMax-Music3”，公开发布时要说明内容是机器生成的，所以标题画面底部写了“音乐：MiniMax-Music3（AI 生成）”。

### 环境声和音效（`art/tools/synth_audio.py`）

环境声和音效由代码合成，不含任何采样或第三方录音：

```bash
<venv>/python art/tools/synth_audio.py          # 输出到 game/assets/audio（环境声和音效），清单写到 art/manifests/audio_synth.json
<venv>/python art/tools/synth_audio.py game/assets/audio music   # 只在需要时：重新渲染代码合成的备用音乐，会覆盖 MiniMax 的曲子
```

依赖 numpy、scipy、soundfile（自带 Vorbis 编码的 libsndfile）。代码分三块：

- `audio/synth_core.py`：乐器和效果。
  - 加法钢琴：略微拉伸的泛音、两根弦微失谐、两段衰减、击弦噪声；
  - 钟琴 / 钢片琴 / 风铃 / 金属声，用非谐泛音做；
  - Karplus–Strong 拨弦（尼龙吉他、筝），用全通滤波做小数延迟调音，音高误差在 2 音分以内；
  - 带气声的横笛、柔和弦乐铺底、贝斯；
  - 太鼓、梆子、沙锤、拍手、底鼓；
  - 合成的立体声混响；
  - 把循环尾部的余音叠回开头，循环接缝处没有断点。
- `audio/sfx.py` 和 `audio/amb.py`：脚步（石板、碎石、草地、木地板、榻榻米）、UI、提示音、拟音、猫的呼噜声和三段环境声；`sfx.mg()` 是 35 个小游戏音效（倒数、判定、盛饭、捏饭、海苔、放东西、滑块、入水、破纸、咚、咔……），文件名 `mg_<名字>.wav`，由基类的 `sfx()` 播放。
- `audio/music.py`：第一版的四段合成音乐，现在只作备用，默认不渲染。

生成后逐项检查过：各频段能量分布、循环接缝、峰值和响度。

Godot 这边是 `Audio` 自动加载（`game/scripts/autoload/audio.gd`）：

- 总线：Master（硬限幅）接 Music、Ambience、SFX、UI 四条子总线。Music 总线上挂一个低通，进屋时把截止频率降到 900 Hz，听起来像隔着墙。
- 音乐和环境声各用两个播放器交叉淡入淡出；音乐快放完时从头交叉淡入，环境声是无缝循环；结尾曲单独播放，原来的音乐先淡下去，结尾曲放完再回来。
- 提示音有优先级：完成委托的提示音盖过同时出现的“获得物品”，大的提示音会让音乐让位约 2 秒。
- 所有按钮在节点加入场景树时自动接上悬停和点击声；对话翻页、打开和关闭面板、布置、旋转、放不下，都在各自的位置调用。
- 脚步：玩家的脚步声不带方位，NPC 用 3D 播放器，离得远就听不见。
- 读档恢复期间和测试里不播放游戏提示音（`game_on` 开关）。
- 设置页有三档音量：总音量、音乐、音效与环境声，保存在 SQLite 的 settings 表；旧 settings.json 只用于首次迁移。

## 9. 验证方式

- **湖岸视觉回归（2026-10-07）**：当轮开发1235项；新增 --only=lakeside-polish 八项，旧场景8失败、最终8通过。岸线必须同时更新 LakesideLayout 和 lakeside_shape.gdshaderinc，贴水地形用0.5米采样。水深读取实际深度纹理；溪石用 L_GROUND 射线支撑，再直接 rest_on，避免 rest_on_terrain 把水面当支撑。立牌纹理使用实际板面坐标映射，防止 BoxMesh 图集裁掉边饰。相关128项与21秒原生视频见 LAKESIDE_POLISH_20261007.md；全量未在另一游戏运行期间并发执行。

- **选款进入普通游戏（2026-10-06）**：game/data/material_selection.json 记录用户的 A/B/B/A/A/A，Main 在世界建好后调用 MaterialChoiceProfile。带 --material-options 的对比进程保留原始选项；普通启动及截图使用已选默认组合。selected_material_entry.gd 先等 autoload 与 Main 就绪，再加载录制控制器，避免 SceneTree 入口预加载依赖时出现未注册 singleton 的错误。默认组合、原模型／碰撞签名、实际六视角和 12 秒录像见 evidence/material_selection_20261006/verification.json；环境联动 23 项通过。

- **当前场景材质选款（2026-10-06）**：`python3 art/poc/material_scene_options_20261006/run.py --preview` 直接加载当前 `main.tscn`，对六类表面分别选择四款。用 `--tag final-review` 原生录制 24 款，成片在 `evidence/material_scene_options_20261006_v2/`。每次进程都设置独立存档目录；选项只写本轮评价记录。材质切换检查原模型、草簇数量、碰撞身份与变换不变，R 恢复原材质。面板使用 UIKit；草叶 vec3 色值显式转线性空间后传给着色器。完整操作与素材来源见 POC 的 README。

- **材质视频样板（2026-10-06）**：`art/poc/material_review_20261006/godot/` 是独立 Godot 4.7.2 Forward+ 工程，六种地表各有 A/B；四张 imagegen 图用于实际材质，已有 Hyper3D 住宅用于实景。运行 `python3 art/poc/material_review_20261006/record.py --tag review` 原生录制 40 秒 1080p/30fps 并编码 MP4；视频、8 张截图、日志和检查在 `evidence/material_review_20261006_v1/`。窗口 override 与录制分辨率保持一致，避免 Movie Maker 输出 720p 而截图仍为 1080p。隔离工程不加载游戏 autoload，不修改默认存档。详见该 POC 的 README。

- 自动测试：`res://scenes/tests.tscn`，当前清单1359项，含规则、SQLite、UI、模型摆放、路线、生活、完整夏季和镜头检查。独立HARUMACHI_SAVE_DIR、超时与SCRIPT ERROR检查必须同时使用；全量不与其他Godot实例并发。专项入口与数量见AGENTS，最终数以JSON报告为准。
- 卡顿检查要让时钟实际推进，记录逐帧耗时，不能只看平均FPS。工具`evidence/desktop_stutter_20261007/perf_probe.gd`的`--fixed`模式在真实起床卧室和商店街记录480帧，截图回读放在计时之后；使用固定引擎、置顶原生窗口和独立存档。运动清晰度检查在固定镜头距离下核对人物与镜头的渲染插值位置，镜头避障另跑`--only=camera-body`。桌面缓存用晚会专项检查移动、旋转后的实际食物支撑；方法与结果见[卡顿修复](DESKTOP_STUTTER_20261008.md)。
- 自动演示：普通标题入口`--autoplay`沿实际碰撞路径、Story交互、摆放控制器、料理面板、灯笼输入、日历赴约和拍照完成新夏季至Q15，检查控制与保存恢复。当前基线200项、9张关键截图。自动对白与阶段暂停明确记录，不作为自然四小时；`--showcase`是节日展示夹具。打印的AP mark/frame用于录像剪辑。
- 录制时游戏窗口不能被别的窗口完全挡住：macOS 会停止给被挡住的窗口画帧，演示就停在原地。用 `-t --position <x>,<y>` 置顶并放到屏幕角落。

  ```bash
  W="-t --position 3100,1990"
  $GODOT --path game $W --write-movie <dir>/play_full.avi --fixed-fps 30 res://scenes/main.tscn -- --autoplay
  $GODOT --path game $W --write-movie <dir>/play.avi --fixed-fps 30 res://scenes/main.tscn -- --autoplay --no-music > <dir>/play_log.txt
  $GODOT --path game $W --write-movie <dir>/fest.avi --fixed-fps 30 res://scenes/main.tscn -- --showcase --no-music > <dir>/fest_log.txt
  $GODOT --path game $W --write-movie <dir>/title.avi --fixed-fps 30 --quit-after 210
  python3 art/tools/make_highlight_reel.py <dir>       # 精华（按 play_log.txt 的标记切）
  python3 art/tools/make_festival_reel.py <dir>        # 节日合集（按 fest_log.txt 的标记切，需要 Pillow）
  python3 art/tools/make_minigame_reel.py <dir>        # 小游戏合集（需要 Pillow）
  ```

  剪辑公共部分在 `art/tools/reel_lib.py`（读标记、0.4 秒交叉淡化、字幕卡、垫音乐、−16 LUFS）。全程录像用 ffmpeg 两遍 loudnorm 压到 −16 LUFS。
- 实机：导出包解压后运行，`--print-fps` 记录帧率，记录见 [PLAN.md](PLAN.md)。

## 10. 时间、天气、风与小动物（v0.4）

| 部分 | 实现 |
| --- | --- |
| 时钟 | `GameState` 里的 day / minute / weather，`_process` 里按 1.5 游戏分钟/秒推进；暂停、任何输入锁（对话、界面、小游戏、转场）都会停。每过一分钟发 `time_changed`，NPC 作息和 HUD 都挂在这上面 |
| 光影 | `WorldBuilder.update_time()` 每帧按 13 个关键帧插值太阳角度、颜色、强度、环境光、雾、饱和度、路灯；天空是自写的 sky 着色器 `shaders/sky_blend.gdshader`，三张全景图混合 + 缓慢旋转。天空辐照度重算很贵，所以天空参数每 2 游戏分钟才更新一次（天空用 INCREMENTAL 模式） |
| 天气 | `GameState.weather_for(day)` 用天数作种子；`WEATHER_MOD` 乘到光影上；`WeatherFX` 是跟着镜头走的 GPU 粒子雨（1400 根竖直 billboard 雨丝，叠加混合） |
| 风 | `shaders/foliage_sway.gdshader`：导入的哑光材质换成同贴图的着色器，顶点按高度平方摆动，相位来自 `NODE_POSITION_WORLD`，全局 uniform `wind_strength`（晴 1.0 / 多云 1.35 / 雨 2.1）。`WorldBuilder.SWAY` 列出会摆的模型，`spawn()` 时自动替换，同一材质共享一份 |
| 河 | `shaders/water.gdshader`：两层流动噪声、高光条纹、岸边泡沫，顶点小波浪；颜色乘时刻色调 |
| 地块 | `PlotView`：F08 菜地模型 + 按作物摆 1–4 个作物模型（幼苗 C01 → 0.55 倍 → 1 倍），浇水后土色变深、成熟时有呼吸的光斑；状态没变就不重建 |
| 小动物 | `AmbientLife`：麻雀跳、啄、被惊飞，蝴蝶和蜻蜓摆翅；两只漫游猫使用59关节、八权重与九个动画片段，`CatWalker`控制走停与休息，独立头部张望和世界脚掌支撑。慢走对角配合的作者文件、实际蒙皮检查与新旧录像见[猫慢走记录](CAT_NATURAL_WALK_20261007.md) |
| 区域 | 小镇、家（z=400）、农园（x=700）三个区域；`WorldBuilder.set_region()` 只显示玩家所在的那一块 |
| 对话 | `data/dialogue.json`（105 条）+ `scripts/story/dialogue.gd`：按时段、天气、星期、熟悉度、flag、委托、区域、集市筛选，选条件最具体、今天没说过的一条；♥4/♥5 事件优先级 100、只播一次 |

新增的环境声 farm（河水、麻雀、远处的鸣蝉）、night（铃虫、蛙鸣）、rain（雨声和滴水）和音效 flap（麻雀起飞）、hoe（锄地）、pump（手压泵）、harvest（拔菜）同样由 `art/tools/synth_audio.py` 合成（`python synth_audio.py <out> farm night rain`；新音效用 `sfx.build_farm()` 单独渲，不会重渲旧的）。

2D 素材：黄昏和夜晚的天空全景、河对岸远景、20 个农园图标、田中爷爷和小葵的头像都由 codex 生成，`art/tools/process_farm_2d.py` 负责把天空左右接缝接上、抠远景卡片、切图标去白边和黄边、抠头像。

## 11. v0.5：Pixal3D、Blender 程序模型、草地

### Pixal3D（优先使用，自建、免费）

- 服务在局域网 `192.168.10.202:8099`（RTX 4080），通过 skill `pixal3d-image-to-3d` 的客户端调用，一张图生成一个带贴图的 GLB。一次只跑一个任务，一个约 7 分钟（1536 分辨率），队列最多 3 个。`/tmp` 下的 `pix_queue.py` 负责排队、下载，结果放 `art/models/raw/<ID>_pix/model.glb`，记录在 `art/manifests/models_pixal3d.json`。
- 先做了质量对比：用同一张参考图生成手压泵（已有 Hyper3D 版）、迷你番茄和二层人字屋。Pixal3D 的形状和贴图都很接近参考图，和 Hyper3D 相当，所以 v0.5 的 24 个新模型（8 种新作物、商店货架、面包推车、屋台、七夕竹子、12 个农园和街景小道具）全部用 Pixal3D。
- Pixal3D 的网格约 100 万面、4K 贴图，而且是不连续的三角面。Blender 的 decimate 在焊接后停在 5–10 万面（非流形边太多），所以加了 `rebake` 流程（`game_export.py` 里的 `rebake()`）：
  1. 焊接后导出 OBJ，交给 `art/tools/meshlab_decimate.py`（pymeshlab 二次误差边收缩，不保护 UV 和边界）减到目标面数；
  2. 导回 Blender，自动展 UV；
  3. 用 Cycles 把原模型的颜色烘焙到新贴图上（只烘颜色，不带光照）。
  作物 7000 面（胡萝卜叶和麦穗很细，减到 7000 面会碎成散点，这两个用 14000），小道具 8000 面，贴图 1024。
- 朝向和高度都由 `game_assets.json` 的 `fit / size / yaw` 统一处理，和 Hyper3D、混元的模型走同一条导出流程。
- 失败和重试：E01 屋台、G10 商店货架、G11 面包推车三张参考图里小物件很多，1536 分辨率下服务端报 “Inference exited with status 1”（同一时段别的任务都正常）。改用 1024 分辨率、换一个种子各重试一次，manifest 里用 `retry_of` 记着第一次的任务。队列后半段的小道具也改用 1024，每个任务更快。三个模型在 1024 重试后都成功了。
- 游戏里缺哪个 GLB 就跳过哪个（启动时记在 `stats.missing`），所以模型没生成完也能跑测试和演示。

### Blender 程序生成（`art/tools/proc_models.py`）

适合规则结构、需要精确尺寸或要给 Godot 留碰撞面的东西，直接在无界面 Blender 里用代码搭：

| 模型 | 说明 |
| --- | --- |
| P_bridge | 10 米拱桥：26 块桥板沿抛物线排列，桥下纵梁，两侧栏杆和扶手，石砌桥台；单独一条隐藏的“deck”网格给 Godot 做三角网格碰撞 |
| P_farm_gate | 农园入口的木门，小屋顶、两盏红灯笼 |
| P_signpost | 三向路牌，文字由 Godot 的 Label3D 写 |
| P_yagura | 夏祭盆舞台：四柱平台、红白条纹围布、栏杆、屋顶、梯子 |
| P_toro | 灯笼流用的纸灯笼（纸面自发光） |
| P_long_table | 品评会长桌 |
| P_chest | 家里的收纳箱 |
| P_offer_stand | 月见供台和团子 |

材质只用纯色，靠游戏里的卡通光照出效果；8 个模型一共约 4500 面。

### 草地和地面

- `shaders/ground.gdshader` 的 `use_variety`：三张 codex 画的草地贴图（`meadow`、`grass_dark`、`dirt`，先做成左右上下无缝）按世界坐标的两层噪声混合，出现野花斑块、深色草丛和裸土。
- `GrassField`（`scripts/world/grass_field.gd`）：把 codex 画的 8 种草丛/野花切成 4×2 图集（`process_v05_2d.py` 抠掉叶子之间的白底），用十字交叉的双面片 MultiMesh 按区域撒开，排除小路、菜地、建筑和道具；每 16 米一块，55 米外淡出；着色器 `tuft.gdshader` 按实例随机选图、调色、跟着全局风力摆动。农园约 3600 丛，小镇和小院约 840 丛（启动日志里的 `GRASS ... tufts`）。

### 2D 素材（`art/tools/process_v05_2d.py`）

4 张图标表（80 个图标：8 种新种子和作物、10 种调料、24 种料理面包、背包/箱子/洒水壶、节日小物、天气图标、背包标签、等级徽章、日历、锅和烤箱……）、8 张横幅（商店、面包店、厨房、五个节日；裁成 3:1）、草丛图集和 3 张地面贴图。

### 角色

绑定脚本新增 `dance`（盆舞：拍手、左右举手、踏步，循环），6 个角色重新绑定，走路和跑步速度不变。

## 12. v0.6：草叶、纸灯笼、店内、配音、音乐、片头

### 草地（`game/scripts/world/grass_field.gd`、`game/shaders/grass_blade.gdshader`）

v0.5 的草地是照片风格的地面贴图加十字面片草丛，远看像一块平涂的绿布，上面撒着稻草色的贴片，和小路的交界是直线。v0.6 改成：

- **草叶**：一丛是 11–17 片锥形草叶（每片 3 段 + 尖，UV.y 从根 0 到尖 1），三种形状变体，MultiMesh 按 8 米一块分区，38–46 米外按距离淡出。三种风格：lawn（庭院、小院，11–24 cm）、meadow（农园，18–42 cm）、tall（河岸和墙根，45–90 cm，更多枯黄草尖）。农园约 1.2 万丛，小镇约 4000 丛。
- **着色**：`world_vertex_coords`，草叶按地面法线（向上）打光，所以一片草地像一整块柔软的表面而不是一根根线；颜色从根部的深绿过渡到草尖，草尖颜色由世界坐标上的两层噪声在黄绿、蓝绿和少量晒白的暖色之间变化；一侧略暗，像画出来的折痕；少数草尖是枯黄色。
- **风**：沿风向移动的“风带”让一片片草先后弯下去，被风压到的草尖会亮一点（新海诚片子里草地上那种银色的波纹），每片草还有自己的小抖动。全局参数 `wind_strength` 随天气变化；新加的全局参数 `grass_push` 每帧写入玩家位置，0.85 米内的草会往外倒。
- **地面**：`ground.gdshader` 的 `lawn_mode` 用和草叶完全相同的调色函数画地面，颜色取根部和草尖之间偏暗的位置，再加一点刷子笔触，所以草叶之间露出来的地面和远处看不清草叶的草地都和草叶连得上。
- **边缘**：`feather` 参数让平面边缘 0.3 米内的像素按噪声丢掉（`plane_size` 用 instance uniform 传给每个平面），农园小路边缘被草盖住一些，庭院草坪的边也是不规则的；草丛允许伸进路面 14 cm，离路越近草越矮。
- **花**：v0.5 画的 8 种草丛只留下三叶草、蒲公英、紫花和波斯菊，以很低的密度撒在草里。

### 纸灯笼（`art/tools/lantern_textures.py`、`art/tools/proc_models.py`）

- `lantern_textures.py` 画和纸贴图：纸色、斑驳和短纤维，每一圈竹骨一道阴影，两端变暗；红灯笼正反面写“祭”、侧面写“晴町”，白灯笼画红圈“晴”字纹和上下红边，盆提灯画蓝色桔梗和草叶；灯笼流的四面分别是“祈”、莲花、“想”和“晴”字纹。字用的是游戏自带的 OFL 字体霞鹜文楷，没有用系统字体。
- `P_chochin_red / white / bon`：车削出来的灯身，22 道竹骨之间纸面微微内凹（每道骨两行顶点），黑漆上下圈带一道金线、顶盖、铁丝提环和小坠；纸面贴图同时接到发光，所以墨字不会发亮。原点在提环上，Godot 里直接挂在绳子上。每盏约 2400 个三角面。
- `P_toro`：木底座和四个脚、四根角柱、上下框，四面贴图纸，里面一根蜡烛和发光的火苗。
- `P_farm_gate`：两盏白底“晴”灯笼代替原来的红球。
- 一个坑：用 bmesh 新建的 UV 层名字和 Blender 基本体的“UVMap”不一样，`join()` 以后会被丢掉，灯笼流四面的贴图全变成一个像素的颜色。现在建 UV 层时统一命名为“UVMap”。
- Godot 里 `WorldBuilder.hang_chochin()` 挂灯笼，所有挂着的灯笼在 `_process` 里按各自的相位小幅摆动。

### 店内（`game/scripts/world/interior_builder.gd`）

两间店用同一个构建器：8 × 6 米的房间，后墙和两侧墙满高，前墙只有 0.85 米高留出门口（剖面视角能看到里面），隐形的只投影屋顶让阳光从敞开的前面照进来；地板和墙用家里的着色器（木地板、灰泥、白瓷砖），模型进来时换成卡通材质；货架上的商品是 codex 画的 6 × 4 商品贴图集，每件商品是一张贴在薄盒子正面的面片；面包是 Pixal3D 生成的六种面包模型，一层一种。门口、柜台、烤箱、石磨、冷饮柜、冰柜、蛋糕柜都是交互点。

### v0.6 的 Pixal3D 模型

15 个任务（`art/manifests/models_pixal3d_v06.json`）：和子阿姨，店里的柜台、面包架、蛋糕柜、冷饮柜、冰柜、石磨、双层烤箱、商店货架，六种面包。两个没用上：商店货架（I06）在服务端推理失败，烤箱（I01）生成出来是一块发黑的斑驳方块（Pixal3D 对不锈钢和玻璃这种反光的东西不太行），这两个改成 Blender 脚本生成（`P_gondola` 的层高和摆商品的代码完全对得上，`P_deck_oven` 有发光的炉窗、把手、旋钮和数码屏）。

`game_export.py` 的 `rebake()` 加了 `fill_holes()`：烘焙前把目标贴图设成全透明，烘焙后所有没被烘到的像素（UV 岛之间的缝，以及射线没打中原模型的小块）用 push-pull 金字塔从周围填上。以前这些地方是黑色，远处 mipmap 一混就成了模型上的黑斑；和子阿姨的第一版就满身黑洞，现在干净了。

### 和子阿姨

codex 画正反两面的 A 字姿势设定图 → 取正面交给 Pixal3D → `rebake` 到约 2 万面、2048 贴图（Pixal3D 的人物朝向和混元相反，在 `game_assets.json` 里加了 `yaw: 180`）→ `rig_char.py` 自动绑定。走、跑、鞠躬都正常；抬手的动作（欢呼、伸懒腰、盆舞）会把围裙和披在肩上的开衫一起拉起来（生成的网格手臂和身体连在一起，自动权重分不开），所以她的待机动作只用张望和鞠躬，也不参加盆舞。头像是 codex 画的。

### 配音（`art/tools/voice/`）

- **试听选角**：`make_voice_samples.py` 给 8 个角色各做 2–4 个候选：CustomVoice 的预设音色加风格指令；或者“重塑音色”——先用 CustomVoice 说一句参考句，用 ffmpeg 变调改变音色，再让 Base 模型克隆这个音色说台词，这样新台词的语调是自然的而不是被重采样过的。每条都用 Qwen3-ASR 转写回来算字错率。`evidence/voice_samples/index.html` 是试听页（响度统一到 −18 LUFS，可以勾选并复制选择）。第一轮用户选了 7 个角色；春的候选都“不像奶奶”，第二轮 `make_haru_v2.py` 改音色本身：VoiceDesign 模型按文字描述造声音，或者用 WORLD 声码器把年轻女声“变老”（降基频、加慢速抖动和气声、共振峰下移 5–7%）再克隆。用户选了 VoiceDesign 的 V1。选择记录在 `art/manifests/voice_cast.json`。
- **生成全部台词**：`gen_voice_lines.py` 从 `dialogue.json` 和所有脚本里的 `say("谁", "心情", "台词")` 收集台词（运行时拼接的、带 `%` 的跳过），CustomVoice 角色按台词的心情（开心 / 难过 / 惊讶）在风格指令后加一句，克隆音色的角色用各自的参考音频。每句转写回来检查，字错率超过 0.3 就换种子重来（最多三次，留最好的）。一共生成了 545 句；全部完成后只有 6 句超过 0.3，逐条看过都是数字读法（“2011”读成“二零一一”）或同音字（河童 / 合同），没有读错。输出 `game/assets/audio/voice/<角色>/<台词的 md5>.ogg`，游戏里 `Audio.voice()` 用同样的 md5 找文件，所以对话数据不用加任何编号。
- **去掉旁白**：用户试听后指出旁白“你把活动标牌端端正正地贴在公告栏中央……”停顿断错了（读成“贴在公告栏中，央路过的人”——字都对，所以字错率是 0，ASR 检查不出来）。旁白改成只有文字：删掉 106 句旁白配音，`voice_cast.json` 里旁白设为空（生成脚本会跳过），`Audio.voice()` 不再给旁白和地点描写配音。现在是 7 个角色、439 句、约 34 分钟、16 MB。教训：字错率只能查读错字，查不出断句和语气，长句的旁白最容易出这种问题。
- **断句检查和多音字**（`pause_check.py`）：ASR 转写带标点，标点的位置跟着音频里的停顿走。脚本对比原句和转写的断句位置，找出“原句的断句被丢掉、在旁边 2–3 个字处又冒出一个”的句子——也就是停顿挪了位置。剩下的 439 句里查出 4 句（例如田中的“我是习惯了，不来反而睡不着”被读成“习惯了不来，反而……”），现在它是生成脚本的验收条件之一：挪了停顿的版本算比读错字更差，会换种子重来（最多 5 次）。有一句（澪的“活动标牌放在……社区活动中心，门口挂着……”）五次都读成“中心门口，”，把台词改成了“……社区活动中心。那儿的门口挂着一块木牌子，很好认。”
- 同一次检查发现 TTS 不认识“澪”这个字（líng），9 句带澪名字的台词都读成了“木 / 莫 / 秒 / 谬”或者直接吞掉。生成脚本加了读音替换表（`PRON`，澪 → 玲），送进 TTS 的是同音的常用字，文件名仍按原文的 md5 算，游戏里不用改。这 9 句已重新生成。
- **播放**：`GameUI.say()` 显示台词时播放，自动演示会等配音播完再翻页；新的“Voice”总线，说话时音乐压低约 5 dB。

### 音乐（v0.6）

13 个新请求在 `art/manifests/music_minimax/`（七夕、品评会、夏祭、盆舞、花火、灯笼流、月见、农园、夜晚、雨天、店内、回忆、片头），每首两个种子，全部过一遍 `music_vocal_check.py`（demucs 人声分离 + AudioSet 分类）。10 首第一轮就有干净的一版；农园两版都被判成含有人声类的声音（很可能是竖笛主旋律），换成吉他、曼陀林、马林巴的编制重做三版才过；品评会和夜晚的合格版本太短，各补了三版。选中的版本和理由记在 `takes.json`。

### 序章（`art/tools/make_prologue.py`，`scripts/ui/prologue.gd`）

最初的片头是视频：codex 画 6 张关键帧，LTX-2.5 逐张图生视频（1024×576，每段 9.7 秒），加独白、字幕和片头曲后编成 Godot 能播的 Ogg Theora。用户看过后要动漫风，这个视频和它的剪辑、编码工具都删掉了（LTX 和 MiniMax-H3 的对比结论保留在 README 的“视频模型”一节）。

现在的序章：

- **插画**：codex 画 7 张 16:9 动漫风插画（`art/references/v06/prologue_anime/`，提示词在 `art/manifests/prompts/v06/prologue_anime/`），画风写成“日本 TV 动画的一帧：干净的线稿、平涂和两层阴影”，明确不要厚涂、不要写实。每次都附上游戏里空和澪的头像作为人物参考（用 `codex exec -i` 附图，脚本在 `art/tools/codex_gen_ref.sh`），第一张（夏祭回忆）画好后也作为画风参考附给其余 6 张，所以 7 张里的空是同一个人。
- **处理**：`make_prologue.py` 按 `game/data/prologue.json` 的顺序把插画裁成 1920×1080 放进 `game/assets/ui/prologue/`。
- **播放**：`prologue.gd` 用两层 TextureRect 交替：每张按 json 里的 zoom / pan 缓慢推拉（放大量保证不露边），1 秒交叉淡入；字幕在下方渐显，底下垫一条渐变暗带；空的独白就是普通的配音台词（`gen_voice_lines.py` 也读 prologue.json），每张停留“这句的长度 + 2.2 秒”，最后一张多停 2.5 秒；全程放 MiniMax 的片头曲，说话时音乐自动压低。`-- --prologue-only`（从标题画面进，导出包里也能用）播完就退出，用来录 `evidence/prologue.mp4`。
- **读音**：TTS 把“晴町”读得忽对忽错（ASR 听成晴天、晴晴、秦丁……），发音替换表里加了“晴町 → 晴挺”，19 句带“晴町”的台词和序章一起重录了。第二句开头紧接着“晴町”时仍然容易含糊，加了“下了车，”起头。

### codex 并行

v0.6 的 30 张图（6 张片头关键帧（后来随片头视频一起弃用，换成 7 张序章插画）、15 张模型参考图、2 张旧物插图表、2 张徽章表、商品贴图集、和子阿姨头像、两张店内概念图、1 张图标表）8 个一组并行生成；另开一个 codex 任务按 LORE.md 写第三章相关的邻居台词和和子阿姨的台词（60 条），收回后逐条读过再合并进 `dialogue.json`（旁白条目改挂到新的“榉树”交互上）。

## 13. v0.6 模型复查

1. **全部渲染**：150 个 GLB 每个两个角度渲染（`/tmp` 下的 Blender 脚本，EEVEE，420 px），拼成三张总览图挑出最差的一批。
2. **先看是不是导出的问题**：把 Pixal3D 的原始输出和游戏里的版本并排渲染。菜箱、商店货架、面包推车、面包架、柴堆的原始输出还可以，是 `game_export.py` 按 8000 面减面时把细木条减坏了（菜箱变形、推车的轮子没了、面包架少了横档）。这 5 个改成 30000 面、2048 贴图重新导出。
3. **转正**：Pixal3D 是在参考图的相机视角下重建的，参考图是前右 3/4 视角，所以模型在自己的坐标里是斜的（20–65 度）。对每个模型取水平投影的点，在 0–90 度里找外接矩形面积最小的角度，就是它斜了多少；再按 90 度的四个方向各渲一张正面图，对照参考图选出正面，把 `yaw` 写进 `game_assets.json`，导出时先转。15 个方形的模型转了正（小卡车、两个柜台、蛋糕柜、面包架、石磨、货架、推车、屋台、菜箱、手推车、花箱、工具架、柴堆、小祠堂、石灯笼）；圆的（水桶、植物）不用管。古井一开始也被当成圆的漏掉了，它的屋顶架是方的，第二轮补上（转 38 度）。场景里的摆放角度原本就是按“正面朝哪”写的，转正后大多不用改，只挪了卡车和柜台。
4. **重做**：
   - 柜台 I04：旧参考图上有糖罐、小物件，Pixal3D 生成出一根悬空的杆子。让 codex 重画一张只有柜台和收银机的参考图，Pixal3D 1536、种子 7 重做，`min_island` 去掉一个飘着的小瓶子。
   - 收纳箱 P_chest：以前是程序生成的方盒子。codex 画了一只带铁包角和圆锁的木箱，Pixal3D 生成。
   - 冷饮柜 I03、冰柜 I07：Pixal3D 把玻璃和不锈钢做成灰色的一团，改在 `proc_models.py` 里用方块搭柜体，玻璃门 / 玻璃顶是一张贴图平面，贴图是 codex 画的正视饮料架和俯视冰淇淋（带一点自发光，像开着灯）。
   - 第一轮复查时 Hyper3D 用不了（会话里没有 Rodin 工具，Blender MCP 没连上），按“Pixal3D → Hyper3D → Blender”的顺序只用到了第一步和最后一步。之后 `hyper3d-rodin_*` MCP 工具重新连上：上传参考图（预签名 PUT）→ `rodin_generate`（Gen-2.5-Medium，Raw，3 万面）→ `rodin_wait` → 下载 GLB。用 v0.5 的参考图重做了小卡车 D07，质量明显好过 Pixal3D 版（车身、车窗、货箱里的菜都清楚），导出 1.2 万面。Rodin 的模型本来就是摆正的，不用转。
5. 前后对比：`evidence/model_review_v06.jpg`。

### 邻居的活动路线

`NPC.set_roam(key, stops)`：每站 `[位置, 朝向, 动作, 停留秒数]`，第 0 站就是原来的站位。停留时间到了、玩家不在 2.4 米以内，就走向下一站；到站后转身、换站姿或做一次手势。走路时 `_avoid()` 把前方 1.7 米内的玩家和邻居折算成侧向推力，离目标越近推力越小（不然有人站在目标旁边会绕着目标打转）；玩家正挡在前面 0.8 米内时先等最多 1.5 秒。`Main._sync_roams()` 每秒按“今天的节日 / 周六集市”给每个人设置或清空路线；`NPC.freeze` 每帧由 Main 设置（对话、过场、转场、界面、盆舞）。脚本安排的走路（集市开场、节日过场）不受暂停和让路等待影响，一定会走到。自动演示去找某个邻居时先让他 `hold`，停在原地等玩家走过去。测试里默认关掉路线，CROWD 组单独打开检查。

### 店门口掉出地图（v0.6 反馈）

商店和面包店的室内在远处（z = 400）单独搭的。前墙中间留着 1.6 米的门，门外画了一片街面，但地面碰撞体只比房间大 1 米，从门口直接走出去就踩空往下掉，而“掉下去就放回原处”的检查又只在室外生效。改成：

- 从门口走出 0.3 米就自动回到主街（和家的前门一样），按 E 出门照旧；
- 地面碰撞体盖满门外画着的整片街面；
- 掉落保护对所有地方生效：玩家每在地面上站稳 0.4 秒记一次位置，掉到 −3 米以下就放回最后记下的位置（隔得太远就放回这个区域的入口）。
测试 SHOP6 覆盖这几条。

## 14. v0.7.3：模型摆放和穿模怎么系统地查

这一轮用户连着指出了几处“歪”和“穿”：店门口货架后仰、面包推车歪、古井歪、和子阿姨穿进柜台、推车旁边多了一块不相干的招牌、招手时衣服被拉起来。上一轮是一件一件手调的（量一个角度、截图看一眼），调完还是歪。这次把它们分成三类，每类都换成能对全部模型批量跑、跑完有数字的办法。

### 模型自己歪（导出时解决）

- **原因**：Pixal3D 按参考图的相机坐标建模。参考图是略微俯拍的 3/4 视角，出来的模型就整体向后仰一个俯角（10°–30°），同时绕竖轴偏 45°–65°。`yaw` 只修得了后者。
- **怎么量**：“立着”的物理定义是凸包上最大的那个朝下的面贴着地。`art/tools/level_util.py` 取凸包里和竖直向下夹角 40° 以内的面，把共面的合在一起，面积最大的就是底座，它和水平面的夹角就是倾角。四条腿的脚尖、平底、两个轮子加一只支脚都能算对。上一轮试过顶点回归、上下截面质心、主成分分析，对不对称的模型（带顶棚的货架、带把手的推车）结果从 11° 到 37° 都有，不能用。
- **怎么修**：`game_export.py` 导出时自动把底座放平（`level: "auto"`）。底座不到外形投影 15% 的模型（作物、纸灯笼、人物、法棍）没有“底座”这回事，不动；要强制就写 `level: true`。
- **转正**：`squareness()` 对模型下 60% 的高度求最小外接矩形，矩形占外形 90% 以上（方形底座）时，它偏离坐标轴的角度就是 `yaw` 还差多少。
- **检查**：`$BLENDER -b --factory-startup -P art/tools/level_check.py` 量全部 GLB，写 `game/assets/models/_stats/_level.json`（2 秒）。PROPS 测试要求：记录比 GLB 新；底座占 45% 以上的模型倾角 ≤ 2°；方形底座的模型转正 ≤ 2°。

### 摆的位置不对（在建好的世界里普查）

- **原因**：坐标写在 `layout.gd`、`house_builder.gd`、`interior_builder.gd` 的表里，靠目测填。模型换了（放平以后变深）、房间放大了、墙挪了，旧坐标不会跟着动。和子阿姨穿进柜台就是店放大以后她的站位没跟着改。
- **怎么查**：`WorldBuilder.spawn()` 给每个实例打上 `model_id`。`scripts/tests/prop_audit.gd` 在测试里对整个世界（镇、农园、家、两家店）逐个模型用网格本身算，不用包围盒（货架的顶棚、推车的把手会把包围盒撑得很大）：
  1. 落地面（离底 0.3 米以内的部分）的凸包互相重叠 → 两个道具挤在一起；
  2. 楼房的竖直墙面采样点落进道具的外形 → 道具插进楼里；
  3. 道具外形碰到 `Layout.WALLS` 或不属于任何模型的碰撞体（手搭的墙、柜台、壁橱）→ 穿墙；
  4. 往下打射线找地面，底比地面高 4 cm 以上又没有东西托着 → 悬空；低 6 cm 以上 → 陷地。
  植物、动物、挂着的灯笼本来就会交叠或离地，列在 `LOOSE` 里跳过。
- **人站的位置**：店主的站位不要写死在日程里，进店时按 `InteriorBuilder.spec_for(k).keeper` 放；测试量“离这个点多远”，容差 0.6 米。以前的测试是“离房间原点 5 米以内”，错的和对的位置都满足，所以从来没抓到过。
- **不相干的东西挨在一起**（推车旁边的荞麦面招牌）程序判断不了语义，只能靠截图。`shots.gd` 的 `close_*`、`facade_*` 视角挨家店拍一遍。

### 动起来才穿（绑定时解决）

- **原因**：生成的角色是一整块封闭网格，A 字站姿下手臂内侧从腋下起和衣服侧面焊在一起。权重怎么调都没用：同一条边的两个顶点，一个跟手臂走，一个跟身体走，抬手时这条边就被拉成一片布。
- **怎么修**：`rig_char.py` 的 `separate_arms()` 在绑定时，把腋下以下“手臂面”和“身体面”之间的顶点复制一份，手臂的面改用复制出来的顶点，两边各自只跟自己的骨骼走，再给两个开口补上一块面。手臂面的判断除了权重，还要落在手臂骨骼的粗细范围内（手臂顶点到骨骼距离的下四分位 ×1.5，朝身体那侧收紧，封顶 0.05 倍身高），这样贴着手臂的围裙、开衫留在身体上。环境变量 `RIG_SEPARATE_ARMS=0` 可以关掉。
- **检查**：PROPS 测试在 Godot 里把每个角色摆到招手最高点，在 CPU 上算蒙皮，统计被拉长到 3 倍以上的边的总长；修之前 30–208 米，修之后 0.7–6.4 米，阈值 12 米。
- **截图工具**：`shots.gd` 的 `npc_wave`、`npc_wave_close`、`npc_bow`、`npc_cheer` 把 7 个邻居排成一排、定格在手势中间。

### 以后加模型的顺序

1. 导出（自动放平）→ 看 `_stats/<ID>.json` 里的 `lean_src_deg`，大于 5° 的截图确认一下放平后对不对；
2. 跑 `level_check.py`；
3. 写进摆放表以后跑 `-- --only=props`（约 3 分钟）；
4. 用 `shots.gd` 截图看朝向和语义（离谁近、像不像这家店的东西）。

## 15. 店面橱窗：真实陈列室（2026-10-03）

五家店有八个底层开口。`shop_windows.gd` 只放透明玻璃，`shop_displays.gd` 在门面里搭出 2.2 米进深的地板、墙、腰板、窗台、家具和独立商品；`shop_glass.gdshader` 不读取货架或商品图片。傍晚提高实际 OmniLight 的亮度。

开口先从房屋实际网格量出，位置保存在 `ShopWindows.WINDOWS` 与 `art/models/rodin_shop_windows_20261003.json`。`open_shop_display_cavities.py` 使用 `mesh_cavity_clip.py` 裁切开放网格，插值原 UV，保留开口外的框、柱和底部地台。连续布尔在不封闭的生成壳上可能产生残片或误删外墙，不能仅凭 Blender 退出码判断成功。

改 S01/S02/S03/S05/S08 时，先重新生成开口源文件、导出，再跑 `window_aperture_check.py`、`level_check.py` 和原有建筑审计；等待 Godot import 完成后跑 `--only=display`、PROPS 与正面 / 斜侧 / 夜间截图。陈列台与商品应留在玻璃内侧至少 2.5 厘米。S01 两个黄瓜筐另由 `replace_store_cucumbers.py` 按菜台实际坡度拼入导出模型。

小模型参考图由内置 imagegen 生成，Pixal3D 自建服务生成网格，再用 `game_export.py` 定尺、放平、转正、减面和重烘焙；素材原稿与每次任务保留。完整经验及来源见 [小模型拼接与真实橱窗](WINDOW_DISPLAYS_20261003.md)。v0.7.3 旧的室内映射 shader 与图片保留为历史素材，街面陈列不再加载它们。

## 16. v0.7.3：对话头像

codex 可以直接画透明背景。14 张头像一张一张重画（`art/manifests/prompts/v07/portraits/`，附上旧头像那一格当长相参考），`art/tools/cut_portraits.py` 只裁掉空白、缩成 512×512，不再按颜色抠底。以前从奶白底的整张表里抠，和底色接近的衣服会被抠出洞。测试 UI6 检查透明背景和衣服上的洞。

## 17. 官网部署（2026-09-30）

`site/` 已部署到 <https://harumachi.nightc.com/>，服务器 `root@nightc.com`。复用已有的 Podman Caddy 容器，独立域名配置、自动 HTTPS，静态文件放在持久数据卷的 `/data/harumachi/releases/<版本号>/`，用 `current` 软链接切换版本。首次版本是 `20260930-235301`。

更新命令、服务器路径和回滚方法见 [site/README.md](../../site/README.md)。上线前校验所有页面资源引用和 JavaScript 语法、备份现有 Caddy 配置，上传后校验文件摘要，再校验配置并热加载。上线后检查 HTTPS、HTTP 跳转、44 个发布文件的状态和摘要，并用浏览器查看实际画面和控制台。证据保存在 `evidence/site_deploy_20260930/`。

### 壁纸与配乐页（2026-10-01）

页头固定显示“晴町 / 壁纸 / 游戏音乐”。壁纸用内置 imagegen 生成 3 个主题、各 2 种构图，共 6 张，原图和提示词保存在 `art/references/site/wallpapers/`、`art/manifests/prompts/site/wallpapers/`，记录写入 `images_codex.json`。导出 JPG 下载文件和 WebP 预览，不裁剪、不放大；尺寸取实际图片尺寸。

将游戏里的 18 首完整 OGG 配乐复制到 `site/assets/music/`，另用 ffmpeg 转成 192 kbps MP3 供浏览器试听。曲目名、用途、时长和文件地址集中在 `site/assets/library.json`，页面逻辑在 `site/library.js`；曲名也要包含在字体子集里。

验证电脑、手机两种布局，实际点击播放检查音频时间和解码状态、切换页暂停、实际下载 JPG 和 MP3 并校验摘要；检查头部 tab 的键盘切换和直接链接。发布时把 `library.js` 也打进包，上传新版本、校验文件，再原子切换 `current`，不用重新加载 Caddy。证据在 `evidence/site_tabs_20261001/`。


日期追加、旧包路径与当轮验收移到[历史流程记录](history/PIPELINE_HISTORY_20261007.md)，不作为当前构建目录规范。

- 场景质感专项：`--only=scene-quality`共27项；旧版同范围25项失败，新版通过。牌面先测真实表面和倾角，背面文字要避开木柱；墙切低时的牌签应依附家具。木纹按分件长轴取样，玻璃单独保留。声音范围、左右声道和演出落点用实际引擎录音核对，不能只检查播放方法存在。全量1359和解压包200项记录见[场景质感](SCENE_QUALITY_20261008.md)。
