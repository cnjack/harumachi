2026-10-25 面包房细节恢复：上一轮建筑替换丢失灰泥纹理、窗帘、细窗格和布篷褶皱，已撤下替换并恢复原模型、UV 和贴图，删除墙面模糊。第 8 轮灯光、树冠和草叶保留。新增当前显示资源检查，先在旧候选复现失败，再验证修复。见[修复与验证](docs/game-design/BAKERY_DETAIL_RESTORE_20261025.md)和[修复前后图库](evidence/bakery_detail_restore_20261025/final/index.html)。

2026-10-25 跑步、农场与捞金鱼：已删除被否决的光影 POC，保留原场景光照与默认均衡模式。七人的源跑步动画降为约 16° 前臂抬角并缩小摆幅，田中另留胸前衣物间距；农场木屋、椅凳、农具、箱桶、门架、围栏与桥统一深棕旧木，道路改为土褐色；捞金鱼增加独立摆尾、推进/滑行和受惊转向。16 项新增专项、14 组原生连续跑步、2861 项独占全量及解压应用 211 项完整演示通过。默认 104 份存档与照片摘要不变，唯一桌面 ZIP 已更新，Web 未发布。 见[本轮记录](docs/game-design/RUN_FARM_FISH_20261025.md)和[原生前后对照](evidence/feedback_run_farm_fish_20261025/index.html)。

2026-10-24 画面与耗电优化：新增原画质 60 帧、均衡 60 帧和节能 30 帧，默认均衡；暂停、后台和最小化分别限 30 / 10 / 5 帧。3D 分辨率、阴影、远景草叶及远处衣物重复计算按档位降低，近处人物与源动作保留。M5 Max 上两处场景各 90 秒对照，均衡 CPU 占用降低约 36%–41%，节能降低约 52%–63%；瓦数和机身温度未测。2845 项独占完整回归、18 项原生检查及解压应用 211 项完整演示通过，唯一 macOS ZIP 已更新，默认 104 份存档与照片摘要不变。 见[实现与测量边界](docs/game-design/POWER_PROFILES_20261024.md)和[前后滑动对照](evidence/power_profiles_20261024/index.html)。

2026-10-24 车辆细节与深色木材：公交与货车补充连续转角、灯具内层、轮毂、车门五金及货斗压筋、铰链和插销；保留车漆、橡胶、玻璃与金属的不同响应。广场七类木材由浅蜂蜜色改为深栗棕色。2813 项独占完整回归、24 组原生前后对照及解压应用 211 项完整演示通过；唯一 macOS ZIP 已替换，默认 104 份存档与照片摘要不变。 见[实现与验证](docs/game-design/VEHICLE_FINISH_20261024.md)和[原生对照](evidence/vehicle_finish_20261024/index.html)。

2026-10-24 室外性能优化：草地复用相同顶点，澪与莲启用已有原生衣物包围盒和空间网格计算。模型、草密度、阴影和抗锯齿设置保留；本机 2K 夜间广场约 79→87 FPS，3456×1932 实际像素下约 76→91 FPS，白天约持平至提高 3%，走跑基本持平。新增 7 项几何与完整求解等价性检查，2806 项独占完整回归通过。macOS ZIP 已重新导出，解压应用 211 项完整演示通过并原子替换交付包；默认 104 份存档与照片摘要不变，Web 未发布。 见[实测与验证](docs/game-design/OUTDOOR_PERFORMANCE_20261024.md)和[画面对照](evidence/outdoor_performance_20261024/index.html)。

2026-10-24 场景修整：11 张试玩截图拆为 12 项，各由独立 agent 处理。冰柜、公交、运菜车、公告栏、站牌、街树、滑梯和农园入口已修整；店主按实际工作区域出现，空摊与节日摆件按真实用途收放。2799 项独占完整回归、逐项原生复拍及解压应用 211 项完整演示通过。唯一 macOS ZIP 已更新，默认 104 份存档与照片摘要不变；Web 未发布。 见[修整与验收](docs/game-design/SCENE_FEEDBACK_20261024.md)和[前后对照](evidence/visual_rework_20261024/index.html)。下方各批次的数字与交付状态记录当时结果。

2026-10-24：测试场景新增防误启动与存档隔离检查，F6 误开 `tests.tscn` 时返回标题；对话专项 24 项、座位专项 27 项通过。普通游玩中的重复对话尚未复现，详情见[交互入口记录](docs/game-design/INTERACTION_ENTRY_20261024.md)。 本轮已重新导出 macOS 包，ZIP / 签名和解压应用的 205 项完整演示通过。

2026-10-19 跑步姿势历史记录（revision3）：七人前臂斜向对侧上胸约33°、肘部约90°、大臂正面内收约15°，另一臂向后外侧摆；直接改源动画。28张原生姿态预览完成，按用户要求停止长测试；macOS包已编译并替换`builds/HareMachi.zip`，签名、ZIP完整性及包内七人revision3资源检查通过，记录见`evidence/run_arm_cross_build_20261019/delivery.json`。完整动态验收与自然度待用户点评，网页版未更新。见[姿势修订](docs/game-design/RUN_ARM_POSE_20261019.md)。

前轮将七人的跑步手臂、手腕和松握手型修回源动画，并处理澪源裙面、和子源围裙及四人源走路鞋底接触；游戏保留地形、切换和衣物残差辅助。当轮2628项独占完整回归、源保护与加密衣面检查通过，留有44秒源对照、42秒七人跑步与24秒三人同场；见[源修复记录](docs/game-design/SOURCE_CLOTH_ARMS_20261018.md)。这些结果不代表revision3已重跑验收。本会话不使用虚拟显示器。

<p align="center"><img src="site/assets/wallpapers/summer-river.webp" alt="晴川与山谷中的晴町，明年夏祭官方概念插画" width="100%"></p>

其余五个人物已逐一核查：澪、小葵、田中、和子的基础姿态写回源动画，春保留原源；2606项独占完整回归、575张源/游戏五方向画面复核完成。新做七人×六组MotionBricks连续挑战，提供七条单人、两组多人和源骨架录像，每条72秒1080p30，附60项点评页。极端动作仍有衣物与接触问题，POC未接入游戏；见[本轮结果与视频](docs/game-design/ROSTER_FOUNDATION_MOTIONBRICKS_20261018.md)。

前轮空、莲的腿部问题已修回源资产：莲修正裤腿/围裙蒙皮，空修正源walk膝盖方向并停用旧运行时膝向纠正，接地保留为辅助。2601项独占完整回归、768姿态衣物证明和120张五方向实拍通过；[修复说明与两条对照视频](docs/game-design/LEG_FOUNDATION_20261018.md)。自然度待复评，MotionBricks仍为独立POC，桌面包/Web未更新。

前次七人跑步已按两段参考微调手部朝向：前摆轻微向胸中线收，后摆恢复原姿态，澪原本内倾的左手保留。98项专项及2600项独占完整功能回归通过，224张正侧面及修改前后各70张手部近景已复查；见[跑步手型修改](docs/game-design/RUNNING_HANDS_20261018.md)。新录[42秒七人依次跑步](evidence/run_hand_inward_20261018/movie/group-run-review/video.mp4)，每人正面/右侧各3秒，保留真实起跑，1080p30严格完整解码通过。自然度待人工复评，桌面包/Web未更新。

前次七人跑步已降低手位、缩小前后摆臂，并让肘部随步幅屈伸；春保留原节拍，爷爷左臂另留衣物净空。当时77项专项、224张正侧面原生姿态复查及2579项独占完整功能回归通过；见[跑步摆臂修改](docs/game-design/RUNNING_ARMS_20261018.md)。

上一轮人物四组反馈已处理：空走路膝内扣、爷爷左臂被衣身挡住、和子走跑腿形，以及七人挥手/鞠躬时腿保持站姿。当时源码组合通过2502项独占完整功能回归、退出0，包含92项步态与47项手势；原5毫米衣物穿透与8毫秒求解门槛未放宽。和子仍保留约1弱像素的围裙微折交叉，自然度待人工复评，见[修复与边界](docs/game-design/CHARACTER_FEEDBACK_20261018.md)。新录[爷爷单人](evidence/rig_fix_20261018_followup/movie-tanaka-natural-transition/solo-tanaka/video.mp4)、[和子单人](evidence/rig_fix_20261018_followup/movie/solo-kazuko/video.mp4)与[七人同场](evidence/rig_fix_20261018_followup/movie/group-all-actions/video.mp4)各24秒、1080p30，完整解码通过；使用现有屏幕、静音和独立存档，未创建虚拟显示器。

此前49项[逐项记录](docs/game-design/CHARACTER_RIG_REVIEW_20261018.md)、九段旧复评视频及[点评页](evidence/character_videos_final_20261018/index.html)原样保留；新反馈覆盖对应的旧人工结论，不由功能测试代填自然度通过。

上述人物审查批次当时仅更新源码与素材库；当时桌面 ZIP 仍是 2026-10-15 已验收包，Web 未随该批次发布。旧人工页面、旧视频和历史2296项包验收保持原含义。

指定的21组路牌、格柜、收纳、晾布架与相框已处理。13种无文字Hyper3D单体组合复用于100个实际源部件位置，其中43格分别组成五处用途不同的收纳柜。木牌与货架采用本地字体蒙版形成凹入明暗和局部法线；门前、房内与烘焙货架的系统提醒牌撤去，必要说明通过原交互展示。

50项专项、2296项独占全量、40张解压包原生画面及205项完整夏季演示全部通过，退出码0；默认104份存档与照片摘要不变。引擎仍为Godot4.8-dev7，模型292件，配音436条，人物语音默认关闭。Hyper3D结算6.5点，当前账户余额22→15.5、冻结0。唯一桌面ZIP已原子更新；Web保持原版本。 见[范围、来源与验收](docs/game-design/MODULAR_PROPS_20261015.md)和`evidence/modular_props_20261015/delivery.json`。

此前家具批次：按imagegen的圆角、弧背、木作与克制反射方向，14个Hyper3D单体替换烘焙店程序桌椅、柜台、货架、咖啡台，并复用于全游戏100组家具摆放。主体保留生成网格和原贴图；玻璃柜及咖啡豆仓局部修为真实薄玻璃，商品和咖啡豆可以透过玻璃看见。

87项家具专项、2246项独占全量、解压应用38项坐姿流程及205项完整夏季演示全部通过，退出码0；63张家具细节、7张坐姿/全景和11处室内全景已复核。默认104份存档与照片摘要不变，唯一桌面ZIP已原子更新，临时冻结与解压目录已删除。 引擎仍为Godot4.8-dev7，模型278件，配音436条，人物语音默认关闭。Hyper3D实际结算7点，余额150→143、冻结0；没有重提候选。Web保持原版本。见[Hyper3D家具重做与复用](docs/game-design/HYPER3D_FURNITURE_20261015.md)和`evidence/hyper3d_furniture_20261015/delivery.json`。

此前居民故事批次：节日道具现在随准备、练习、开放和收场变化；新增5户居民住处及6处工作或公共室内。首场集市接到春家邀请，沿图纸、量木件、两种实际试坐摆法、现场照片和寄信回信继续推进。拜访、改造和选择会留下可见变化，取消或错过预约仍能补约。人物语音继续默认关闭，正式登记436条。见[实现记录](docs/game-design/RESIDENT_STORY_DELIVERY_20261014.md)。 本轮2120项独占全量、解压应用的新拜访路线及205项完整夏季演示全部通过，退出码0。默认104份存档与照片摘要不变；唯一桌面ZIP已原子更新，临时导出工程已删除。验收见`evidence/layout_story_implementation_20261014/delivery.json`；自动验证不代表自然三天或四小时的玩家体验。

此前桥增加四盏有实体吊架的竹灯笼和两盆白绣球；全世界只保留两只地面猫，常规步速0.36米/秒，雨夜与离区返回保持连续位置。动态水波、真实日月与五灯反光、每图18座远山及四条水下鱼已实拍验收。语音默认0，保留旧明确选择；IndexTTS2等已做本机小样对照，正式417段未替换。41项新增专项、1841项独占全量及解压应用200项完整夏季演示通过，默认104个存档和照片摘要不变。额外积分0，本地唯一桌面ZIP已更新，Web保持原版本。见[本轮记录](docs/game-design/SCENE_LIFE_20261013.md)。

此前模型批次实际消费Hyper3D60点，余额210→150、冻结0；120个候选中逐件选择并完成60件模型，24件替换、36件新增，游戏共264件GLB。四面/灰模、60件四天气实拍、24组同机位对比、203项专项、1800项独占全量及解压应用200项完整夏季演示均通过，默认104个存档和照片文件摘要不变。唯一桌面ZIP已更新，Web保持原版本。见[模型多样性验收](docs/game-design/MODEL_DIVERSITY_20261013.md)。

<h1 align="center">明年夏祭</h1>
<p align="center"><strong>Harumachi: Next Summer</strong><br>一款关于归乡、日常与重逢的日式小镇生活游戏。</p>
<p align="center"><a href="https://harumachi.nightc.com/">官方网站</a> · <a href="https://harumachi.nightc.com/play/">网页试玩</a> · <a href="https://harumachi.nightc.com/#wallpapers">官方壁纸</a> · <a href="https://harumachi.nightc.com/#music">游戏原声</a></p>
<p align="center">开发中 · 中文 · macOS / 浏览器试玩 · 单人 · 键盘与鼠标<br><a href="LICENSE">MIT License</a></p>

## 回到晴町，过一个有约定的夏天

空回到奶奶曾经生活的小镇。清晨照看菜园，午后做一道家常菜，傍晚去邻居的店里坐坐。随着旧物和往事逐渐浮现，他与居民开始筹备停办十五年的夏祭，也重新拾起十岁那年留下的约定。

《明年夏祭》将生活经营与每日剧情结合起来。故事从安顿新家和第一顿饭开始，让玩家在一次次实际参与中认识晴町，与这里的人建立关系。

| 生活在晴町 | 与大家一起过夏天 |
| --- | --- |
| 种植、收获与料理，把菜园里的成果带上餐桌 | 合作试吃、集市开摊与灯笼试挂，逐步筹备夏祭 |
| 钓鱼、探索和旧物收藏，在小镇里发现往事 | 从日常对话到共餐、合影与花火，留下新的回忆 |

<p><img src="site/assets/day_1.webp" alt="游戏实机：晴町的市民农园" width="49%"> <img src="site/assets/day_3.webp" alt="游戏实机画面" width="49%"></p>
<p><em>上方为游戏实机画面；页首及官方壁纸为概念插画。</em></p>

## 开发进度

当前开发重心是夏季篇：归乡入场、生活活动、社区合作与夏祭收尾。桌面版与网页试玩分别验收和发布，官方网站提供壁纸与原声收藏。春、秋、冬的完整章节属于后续规划。

夏季篇的目标体验时长约四小时，仍在扩展与普通游玩验收中，尚未达到完整内容目标。最新版本、验证结果与已知限制以 [CURRENT_STATUS](docs/game-design/CURRENT_STATUS.md) 为准。

## 运行与开发

澪的独立 Swift / Metal 桌面角色原型：角色动作可用 [`preview_mio_motion.command`](preview_mio_motion.command) 本地预览；来信界面入口为 [`open_mio_companion.command`](open_mio_companion.command)，[启动与验证范围](native/mio-companion/README.md)。提供 30 层 PSD、连续袖子、多手型、动作过渡、系统事件和 Clef 决策接口。真实 Clef 固定消息连接已验证，常驻监控外发范围待确认；当前为自有分层格式。

需要 **Git LFS** 与 **Godot 4.8-dev7**，精确版本为 `4.8.dev7.official.c971f93e7`。引擎和导出模板必须一致。

```bash
git lfs install
git clone https://github.com/cnjack/harumachi.git
cd harumachi
git lfs pull

export HARUMACHI_GODOT_BIN="/path/to/Godot"
./tools/godot --headless --path game --import
./tools/godot --path game
```

可从 [Godot 官方版本档案](https://godotengine.org/download/archive/4.8-dev7/) 获取引擎。macOS 二进制通常位于应用包的 `Contents/MacOS/Godot`。本机路径也可配置在忽略的 `tools/godot.local.json` 中；版本锁不随个人安装位置改变。

| 目录 | 内容 |
| --- | --- |
| `game/` | Godot 工程、玩法代码、数据、着色器与运行资源 |
| `site/` | 官方网站、壁纸与原声目录 |
| `docs/game-design/` | 设计规格、当前状态与验收记录 |
| `art/` | 素材工具、来源记录、参考图与可编辑素材 |
| `tools/` | 引擎入口、项目校验与 Web 构建工具 |

运行资源通过 Git LFS 管理。缓存、导出包、个人存档、大型原始生成包和本机验收证据不进入版本库。素材制作与重导出流程见 [PIPELINE](docs/game-design/PIPELINE.md)。

## 项目维护

```bash
python3 tools/check_project.py
python3 -m http.server 8765 -d site
```

每项任务完成后，执行相关自动检查和实际运行验收；通过后提交并推送 `main`，再确认远端 CI。涉及模型、镜头或界面的修改需要画面验证，游戏逻辑修改需要相应 Godot 测试。完整规则见 [AGENTS.md](AGENTS.md) 与 [维护指南](docs/REPOSITORY.md)。

三组 agent 完成全场景、多机位、天气、时间、活动和人物动物检查，最终 3021 张原生截图已逐图复核。修复七人鞋尖穿地、坐姿脚底、小葵掌心、和子围裙在走跑与舞蹈中被黑裤顶穿、湖岸路面支撑、曲线缺面和东岸隐形阻挡、西南远景空洞、上部树干相机穿入、盆踊被问候抢动作、钓鱼持竿骨骼兼容、阴雨室内光照、近镜头硬雨条及露天小院雨效缺失，试吃台和三组餐具支撑、出屋后邻里餐桌恢复，公共室内串景、室内拍照跳位和花园远景画片在自由镜头露边，以及猫的可见活动、家中金鱼和鸟虫形态。1498项独占全量与解压包200项完整夏季演示退出0，默认存档与照片未变；截图、完整测试和导出来自逐文件核对的冻结工程。见[全面视觉检查](docs/game-design/VISUAL_AUDIT_20261011.md)和`evidence/comprehensive_visual_qa_20261011/delivery.json`。Web仍为原已验快照。

此前，社区中心改为共用桌、阅读角、茶水和集中活动收纳；商店按类别成组陈列并集中冷藏奶蛋；精品面包房加入两组座位、咖啡后吧和四类独立甜点。阅读、喝茶、坐下休息、购买饮品与桌边享用均已接入。1421项独占全量、解压包200项完整夏季演示退出0，32个原生场景视角与两张商店UI截图已验，默认存档未变。见[日常格局重做](docs/game-design/INHABITED_PLACES_REDESIGN_20261010.md)与[实景改绘经验](docs/game-design/IMAGEGEN_SCENE_WORKFLOW.md)。此前树冠与绒毛苔藓继续保留。

官网发布流程见 [site/README.md](site/README.md)，网页游戏构建见 [WEB](docs/game-design/WEB.md)。发现问题可通过 [Issues](https://github.com/cnjack/harumachi/issues) 提供复现步骤、版本与截图。

## 许可

本项目的原创代码、文档及有权授权的原创素材采用 [MIT 协议](LICENSE)，版权归 Harumachi contributors。第三方组件、字体与外部素材保留各自的原始许可和使用条件，具体见 [素材与第三方许可](ASSET_LICENSES.md)。
