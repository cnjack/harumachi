# AGENTS.md

写给在这个仓库里干活的 AI 编程助手（Copilot CLI、codex 等）和新加入的人。先读这一页，再动手。

## 这是什么

「明年夏祭」（Harumachi: Next Summer，之前的工作名是「晴町日常」）：日式小镇生活游戏，Godot 4.8-dev7（开发快照），macOS 桌面单机，键鼠，中文。玩家「空」回到奶奶住过的晴町，种菜、做饭、摆摊、过节，把停办十五年的夏祭办回来。

- 游戏工程：`game/`
- 设计文档：`docs/game-design/`，入口 [README.md](docs/game-design/README.md)，当前事实集中在 [CURRENT_STATUS.md](docs/game-design/CURRENT_STATUS.md)
- 素材源文件和工具：`art/`
- 录像、截图、测试结果：`evidence/`
- 导出包：`builds/HareMachi.zip`，当前Godot4.8-dev7；最新验收见`evidence/app_icon_windchime_20261009/delivery.json`
- 官方网站与网页试玩：`site/`，说明在 `site/README.md`

## builds 只保留最新交付（2026-10-05）

`builds/` 只允许保留一份最新已验收的桌面编译包 `HareMachi.zip`，以及最多一份最新已验收的 Web 导出目录 `web/`。目录顶层最多这两项。

- 旧包、日期副本、`before-*` 备份、解压后的 `.app`、构建工作目录和冻结源码快照都要清理；不要把旧编译包搬到别处继续堆积。
- 临时导出、解压检查和冻结工程放在本轮独立的临时目录，完成后删除。校验摘要、日志、截图和清理记录放在 `evidence/`。
- 新桌面包须导出、解压、跑完 `--autoplay` 且退出码为 0，再原子替换 `builds/HareMachi.zip`，随后删除旧包和临时文件。
- Web 先在临时目录构建并完成浏览器验收，再替换 `builds/web/`；保留最新已验证版本即可。
- 这一规则覆盖历史文档中在 `builds/` 保留旧包、日期包或冻结工程的做法。源码与素材继续放在 `game/`、`art/`，证据继续放在 `evidence/`；服务器发布目录的回滚策略按 `site/README.md` 管理。

## GitHub 项目维护（2026-10-09）

- 统一仓库：`https://github.com/cnjack/harumachi.git`，本工作区作为游戏与官网共用仓库。说明见[README.md](README.md)与[docs/REPOSITORY.md](docs/REPOSITORY.md)。
- Git LFS跟踪模型、贴图、音频、字体、二进制资源与扩展；先拉取LFS再打开工程。`.godot/`、`builds/`、`site/play/`、`evidence/`、试验与原始大包保持本地，不提交。忽略不等于删除。
- 每项任务完成且相关测试、实际运行验收通过后，提交本轮已验收修改并推送到`origin/main`，随后确认远端提交和GitHub CI。此项是用户的持续授权，不需要再次询问是否推送；如有明确“先不要做/不要推送”指令，则以当轮指令为准。
- 提交前跑`python3 tools/check_project.py`及本轮相关Godot或网站验收；未通过时先修复，不能把待验工作标成完成。只暂存本轮文件，保留其他任务的未完成修改。
- 推送前核对仓库、账户及远端进度；远端有新提交时先正常整合并重新验证，不使用force push。不提交凭据、个人存档或临时包。协作者的外部贡献仍可使用PR。
- 官网复用旧发布目录时，变更脚本的预压缩`.gz`必须重新生成并与源码核对；清单排除开发README。线上验收同时校验普通响应和浏览器压缩响应，避免浏览器运行旧代码。
- 引擎版本仍由tools/godot-version.json锁定；本机位置放忽略的tools/godot.local.json或HARUMACHI_GODOT_BIN，不能要求其他开发者使用/Users/jack路径。

## 最重要的一条：画风

**新海诚风格的动漫风，不走写实。** 干净的线条、平涂和硬边阴影，加上新海诚式的光（通透蓝天、积云、金色阳光、淡紫蓝阴影）。任何 2D 图、3D 模型、着色器、UI、宣传物料都照 [docs/game-design/ART_STYLE.md](docs/game-design/ART_STYLE.md) 做和验收。拿不准的时候，宁可更“动画”一点，也不要写实。

## 常用命令

```bash
GODOT=/Users/jack/workpath/godot/tools/godot-4.8-dev7/Godot.app/Contents/MacOS/Godot
PY=/Users/jack/.copilot/session-state/ca10e179-b441-4d77-b938-250cea2ee4c6/files/venv/bin/python   # PIL / numpy / scipy / soundfile / av
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender

$GODOT --headless --path game --import                               # 加了素材或 class_name 之后必须先跑
$GODOT --headless --path game res://scenes/tests.tscn -- --out=/tmp/t.json   # 全部测试（当前1359项；单独运行，套timeout）
$GODOT --headless --path game res://scenes/tests.tscn -- --only=scene-quality # 27项牌面、真实路向、材质、房间用途、净空与空间声音
$GODOT --headless --path game res://scenes/tests.tscn -- --only=motion-clarity # 6项斜跑/横跑帧间稳定、过滤、跑速与镜头复位
$GODOT --headless --path game res://scenes/tests.tscn -- --only=resident-morning # 32项居民旁观、提问、真实托盘移动、净空、取消与保存恢复
$GODOT --headless --path game res://scenes/tests.tscn -- --only=shop-life       # 24项实体陈列、欢迎语、电视、真实工作往返与购买
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-flow       # 18项挂法取舍、便笺、花火恢复与严格路径
$GODOT --headless --path game res://scenes/tests.tscn -- --only=calendar-advance   # 28项日历列、真实邀请、两种准备组合、保存/午夜/备份恢复
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-gathering   # 33项新篮、桌面盘沿、缓存失效、散场与同灯重约
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-space       # 33项空间、真实试用、归属和活动身份
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-projects    # 63项合作批次、真实使用、近距交接、剩食、碰撞与恢复
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-workshop   # 23项账本、代表灯笼、真实试挂、同物再用与Hyper3D桌面支撑
$GODOT --headless --path game res://scenes/tests.tscn -- --only=summer-foundation  # 44项首餐同批、真实成果、知情、补拍与迁移
$GODOT --headless --path game res://scenes/tests.tscn -- --only=daily-life   # 53 项首餐门路、麦茶、纸牌、预留、恢复、骨架与桌面支撑
$GODOT --headless --path game res://scenes/tests.tscn -- --only=crowd        # 只跑邻居、站位、店门口、序章几组（约 1 分钟）
$GODOT --headless --path game res://scenes/tests.tscn -- --only=props        # 只跑模型摆放 PROPS（约 3 分钟）
$GODOT --headless --path game res://scenes/tests.tscn -- --only=display      # 19 项真实橱窗、陈列和近树检查
$GODOT --headless --path game res://scenes/tests.tscn -- --only=ui-map       # 26 项地图标签、图标、背景和布局检查
$GODOT --headless --path game res://scenes/tests.tscn -- --only=ui-kit       # 16 项素材、控件状态和共用皮肤检查
$GODOT --headless --path game res://scenes/tests.tscn -- --only=dialogue-ui  # 16 项对话会话清理、通知补播、恢复和键鼠检查
$GODOT --headless --path game res://scenes/tests.tscn -- --only=placement    # 12 项树根、动物支撑、入口、楼梯和移除物检查
$GODOT --headless --path game res://scenes/tests.tscn -- --only=daily-save   # 8 项结算自动保存、次日位置、失败与备份检查
python art/tools/audit_ui_kit.py                                          # UI / 小游戏私有边框审计
$BLENDER -b --factory-startup -P art/tools/level_check.py                    # 导出模型后必须跑：量倾角，PROPS 测试读它
$GODOT --path game -t --position 3100,1990 res://scenes/main.tscn -- --autoplay    # 自动演示（约 20 分钟）
$GODOT --path game -t --position 3100,1990 res://scenes/main.tscn -- --showcase    # 节日演示
$GODOT --path game -- --prologue-only                                # 只播序章
$GODOT --path game --resolution 1280x720 -t --position 1700,1990 res://scenes/main.tscn -- --shots=/tmp/x --views=store_in,bakery_top   # 截图，视角在 scripts/tools/shots.gd
$GODOT --headless --path game --check-only --script res://scripts/tests/prop_audit.gd   # 只查一个脚本的语法（这时 autoload 不加载，“Identifier not found: GameState”这类报错可以忽略）
$BLENDER -b --factory-startup -P art/tools/rig_char.py -- art/models/static_chars/CH_x.glb game/assets/models/CH_x.glb   # 重新绑定角色
HARUMACHI_BUILD_STAGE="$(mktemp -d /tmp/harumachi-release.XXXXXX)"
$GODOT --headless --path game --export-release "macOS" "$HARUMACHI_BUILD_STAGE/HareMachi.zip"  # 验收后替换 builds/HareMachi.zip
```

常用截图视角：店门口 `close_store` / `close_bakery` / `close_florist` / `close_zakka` / `close_post`，橱窗 `win_store` / `win_florist` / `win_night`，7 个邻居排成一排做手势 `npc_wave` / `npc_wave_close` / `npc_bow` / `npc_cheer`，对话头像 `say_<人>_<neutral|happy>`。

录像、剪辑的完整流程见 [PIPELINE.md 第 9 节](docs/game-design/PIPELINE.md)。

## 必须知道的坑

- **引擎固定4.8-dev7**：精确版本`4.8.dev7.official.c971f93e7`，配置在`tools/godot-version.json`；优先运行`./tools/godot`，它会校验版本。不要依赖可能被自动更新的`/Applications/Godot.app`。`project.godot` features为"4.8"，导出模板为`4.8.dev7`。这是用户要求的开发快照迁移，当前1359全量和解压包200项夏季演示已通过；验收记录不能与历史4.7.2混用。
- **卡顿要查真实时钟和渲染帧**：未使用的晚会桌面不能随每个游戏分钟重扫三角面；桌面测量按实例、变换与来源缓存。只有玩家和跟随镜头启用物理插值，普通移动不能误清插值快照；传送与镜头snap须复位。见`docs/game-design/DESKTOP_STUTTER_20261008.md`。
- **警告当错误**：推断成 Variant 的变量要写明类型（`var p: Vector3 = ...`）；同一个函数里变量不能重名（嵌套循环里也不行）；字典字面量不能有重复键；不要写叫 `_set` 的方法。
- **窗口被挡住就停帧**：macOS 不给完全被遮住的窗口画帧，自动演示、录像、截图都会停住。带窗口运行时一律加 `-t --position <x>,<y>`（置顶、放屏幕角落）。
- **路径里有空格**（`3D model`）：`--shots=`、Blender 的文件参数要么加引号，要么先软链到 `/tmp` 下没有空格的路径。
- **不要在 `/tmp/mq` 里直接跑 Python**：那里有个 `inspect.py` 会盖掉标准库。
- **改名不能动存档目录**：`project.godot` 里 `config/custom_user_dir_name="晴町日常"` 固定了存档位置，别删。
- **每天结算只保存一次**：`GameState.advance_day()` 在全部结算和day_changed回调完成后自动保存；`Main.sleep_now()`先安排次日卧室位置，不能再补一次save_game，否则current/previous会都变成同一天。写入失败必须显示错误，不能发成功提示；网页版通过save_finished同步保存状态。
- **导出包不能指定场景**：导出的 app 不接受命令行里的场景路径，要从标题画面进，用 `--autoplay` / `--newgame` / `--prologue-only` 这类参数。
- **测试存档必须实际隔离**：优先设置独立 `HARUMACHI_SAVE_DIR`。`--test-db` 现已在 GameState 初始化时设置 SaveDB；路径放在本轮独立目录，数据库、照片、备份同目录。不能仅改旧 SAVE_PATH 变量。验证前后核对默认存档摘要。
- **测试里邻居路线默认关着**（`NPC.roam_enabled = false`），CROWD 组单独打开检查。改 NPC 行为时两边都要跑。
- **脚本解析失败时测试不退出**：headless 测试遇到 `SCRIPT ERROR` 会一直挂着。跑测试一律套 `timeout`，再 grep `SCRIPT ERROR`；怀疑哪个脚本就用上面的 `--check-only` 单独查。
- **全部测试不要和别的 Godot 实例同时跑**：并发时出现过和存档时间点有关的假失败，单独再跑就过。Blender 导出（4 路）、codex 生成（5 路）可以放心并行。
- **同一个父节点下节点重名会被自动改名**（变成 `@MeshInstance3D@123`），之后按名字就找不到。代码里批量建的节点，名字要带编号。
- **Blender 和 Godot 的坐标**：GLB 导进 Blender 是 Z 朝上，Godot 的 (x, y, z) 对应 Blender 的 (x, z, −y)。在 Blender 里量模型尺寸、深度时别搞混。
- **所有模型都经 `WorldBuilder.spawn()` 放**：它给实例打 `model_id` 标记，摆放普查（`scripts/tests/prop_audit.gd`）只查带标记的。代码里给某个模型单独补的碰撞体，要加 meta `model_part`，不然普查会把它当成一堵墙。
- **店主的站位不写在日程里**：莲和和子阿姨进店时由 `Main.enter_interior()` 放到 `InteriorBuilder.SPECS.<店>.keeper`，出店后回到日程。日程里不要写室内坐标（和子阿姨穿进柜台就是这么来的）。
- **橱窗位置是按店铺模型量出来的**（`scripts/world/shop_windows.gd` 的 `WINDOWS`）：重新导出 S01、S02、S03、S05、S08 以后要重新量，方法见 PIPELINE 第 15 节。
- **别用顶点统计猜模型歪了多少**：回归、主成分、上下截面质心对不对称的模型（带顶棚的货架、带把手的推车）结果从 11° 到 37° 都有。用 `art/tools/level_util.py` 的 `support_plane()`（凸包最大的朝下的面），最后以游戏里的截图为准。
- **摆放不能只跑旧PropAudit**：它按模型脚印检查，动物/树属于跳过项，也不单列嵌套商品。现在镇与农园都检查；还要跑PLACEMENT的实际渲染地面、墙帽/座面支撑和树冠净空。见 [摆放修复记录](docs/game-design/PLACEMENT_REVIEW_20261003.md)。

## 代码地图

| 路径 | 内容 |
| --- | --- |
| `scripts/autoload/game_state.gd` | 所有规则和数值、时间、背包、存档（v4） |
| `scripts/autoload/audio.gd` | 音乐、环境声、音效、配音（`voice()` 按台词 md5 找文件） |
| `scripts/autoload/progress.gd` | 成就、旧物、图鉴 |
| `scripts/world/shop_life.gd`、`shop_content.gd` | 两店欢迎语、工作往返、分层实体商品、海报与天气电视 |
| `scripts/world/main.gd` | 主场景：区域切换（镇 / 农园 / 家 / 店）、过场、NPC 调度、掉落保护 |
| `scripts/world/world_builder.gd` | 镇子、天空、光照、节日布置、去农园的小路 |
| `scripts/world/layout.gd` | 镇上的道具、墙、交互点、NPC 站位和路线（大部分“摆放”问题改这里） |
| `scripts/world/farm_builder.gd` | 农园 |
| `scripts/world/house_builder.gd`、`interior_builder.gd` | 玩家的家、商店和面包店室内 |
| `scripts/world/shop_windows.gd`、`shaders/shop_window.gdshader` | 店面橱窗：玻璃上的“室内映射”面片，傍晚亮灯 |
| `scripts/story/*.gd` | 委托、对话、节日、第三章 |
| `scripts/npc/npc.gd` | 邻居：作息、手势、活动路线、避让 |
| `scripts/ui/*.gd` | HUD、对话框、各种面板、标题、序章 |
| `scripts/tests/run_tests.gd` | 全部自动测试 |
| `scripts/tests/prop_audit.gd` | 摆放普查：重叠、插进楼里、穿墙、悬空、陷地（PROPS 组调用） |
| `scripts/tools/autoplay.gd`、`showcase.gd`、`shots.gd` | 自动演示、节日演示、截图 |
| `data/*.json` | 对话、委托、物品、配方、商店、节日、成就、旧物、序章 |

## 素材怎么做

**UI 从 `game/ui_kit/` 的统一素材库取**：语义样式用 `UIKitStyles`，组件用 `UIKitComponents`；不要在界面里再造 `StyleBoxFlat` 或私有边框。图标和PNG原图、编辑器资源、独立展示以及打包方式见 [UI_KIT.md](docs/game-design/UI_KIT.md)。

| 素材 | 工具 | 说明 |
| --- | --- | --- |
| 2D 图（参考图、UI、贴图、插画） | codex：`art/tools/codex_gen.sh <输出> <提示词文件>`，要附参考图用 `art/tools/codex_gen_ref.sh <输出> <提示词文件> <参考图…>` | 提示词放 `art/manifests/prompts/`，记录写进 `art/manifests/images_codex.json`；画风按 ART_STYLE.md。**codex 能直接出透明背景**（提示词里写 `BACKGROUND: fully transparent (PNG with an alpha channel)`），要透明底的图（头像、陈列架、图标）就这样要，不要自己按颜色抠图——和底色接近的衣服会被抠出洞。对话头像用 `art/tools/cut_portraits.py` 只裁边、缩成 512 |
| 3D 模型 | Pixal3D（skill `pixal3d-image-to-3d`）→ Hyper3D Rodin（用户指定CLI时使用`hyper3d`；否则按工具能力）→ Blender 程序建模（`art/tools/proc_models.py`） | 原始输出放 `art/models/raw/<ID>_<来源>/`；导出配置在 `art/models/game_assets.json`，跑 `$BLENDER -b --factory-startup -P art/tools/game_export.py -- art/models/game_assets.json <ID>`；来源写进对应的 `art/manifests/models_*.json` |
| 角色绑定 | `art/tools/rig_char.py` | Pixal3D 的角色要 `yaw: 180`。绑定时会把腋下手臂和衣服之间的接缝剪开（`separate_arms()`，不然抬手会拉起一片衣服），`RIG_SEPARATE_ARMS=0` 关掉。重新绑定后跑 `--only=props`，里面有招手时衣服拉伸的检查 |
| 音乐 | 本地 MiniMax Music 3（`/Users/jack/workpath/research/music`） | 要纯音乐，生成后用 `music_vocal_check.py` 查人声 |
| 配音 | mlx-audio 的 Qwen3-TTS（`art/tools/voice/gen_voice_lines.py`） | 选角在 `art/manifests/voice_cast.json`；旁白、春、田中不配音；读错的字加到 `PRON` |
| 音效、环境声 | `art/tools/synth_audio.py` | 程序合成 |

Pixal3D 的三个老问题：

- 模型按参考图的 3/4 视角建，绕竖轴偏 45°–65°，**放进游戏前要转正**（写 `yaw`）；
- 参考图是略微俯拍的，模型还会向后仰 10°–30°。v0.7.3 起 `game_export.py` 导出时自动放平（`level`），导出后必须跑 `level_check.py`，再跑 `--only=props`（放平、转正、摆放普查都在里面）。放平以后模型可能变深，原来贴墙的会插进墙里，普查会报出来；
- 玻璃和不锈钢做不好，改用 Blender 建模加手绘贴图。

每个新模型放进场景后都要截图看：朝向、贴地、有没有穿进墙或别的东西，还有程序判断不了的——离谁太近、像不像这家店的东西（推车旁边放了块荞麦面招牌就是这么漏掉的）。完整做法见 PIPELINE 第 14 节。

## 改完要做什么

1. 跑 import，再跑相关测试；改动大就跑全部测试。测试数量变了，同步 README、PIPELINE、PLAN 里的数字。
2. 改了摆放、模型、镜头：用 `shots.gd` 截图亲眼看，别只看数字。
3. 改了台词：重新生成配音，清掉没用的旧配音文件和 `voice_lines.json` 里的旧条目。
4. 更新文档：玩法写 GAMEPLAY，地图和摆放写 WORLD，工具和流程写 PIPELINE，这一轮做了什么写 PLAN。文字要具体、平实，别写套话（参考 `humanize-writing`）。
5. 发布前：导出、解压、用 `--autoplay` 跑完整条演示，退出码是 0。

## 和用户协作

- **官网与网页版发布**：官网使用 `site/ui.css` 与 `site/assets/ui/`，来自 `game/ui_kit/`，不要另造一套边框。网页版从已验证的冻结工程经 `tools/web/prepare_web.py --source <工程> --target <新目录> --evidence <证据目录>` 构建；保留原UI图集像素坐标，不缩放 `ui_kit/assets`。桌面工程继续Forward+，网页只在独立工程使用Compatibility。发布前检查浏览器实际启动、保存后刷新继续、下载分段、COOP/COEP、WASM MIME与字体；服务器创建新release、核对摘要后原子切换current，保留旧版。完整命令见 `site/README.md` 和 `docs/game-design/WEB.md`。

- 用户说中文，回复用中文，简短直接。
- 日期文档是当轮历史；当前引擎、包、测试数、已解决问题和待验范围以CURRENT_STATUS及对应verification为准。更新入口文档时检查矛盾，不批量改写旧日志/旧版本。
- 四小时是目标；当前45–90分钟只是估算，普通三天/完整两路线/75分乐趣尚未通过。不要把自动演示、游戏日或测试数量当自然时长。
- 用户试玩后会指出具体问题（某个模型摆歪、某句配音读错、某处穿模）。先截图确认、找到原因，再改；改完截图对比，并加一条测试防止再犯。新测试先拿旧数据跑一次，确认它确实会失败：容差要小到能抓住原来的问题（店主站位原来是“离房间原点 5 米内”，错的位置也满足，所以从来没报过）。
- 同一类问题被指出两次，说明一件一件地修不够用：写个工具把全部模型或全部地方批量量一遍，把结果变成测试（倾角、摆放普查就是这么来的）。
- 检查不用每次录全程录像，截图就够；测试和导出可以多进程并行跑（全部测试本身除外，见上面的坑）。
- 官网不需要写“画面、音乐、配音由 AI 工具辅助制作”这类说明。
- 用户点名要用的工具（Hyper3D、codex、Pixal3D……）就用它；用不了先告诉用户，别悄悄换。
- 生成要花钱的东西（Hyper3D 积分）之前，先说明要做什么。
