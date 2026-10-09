# 技术流程的日期记录（刷新前）

以下保留当轮版本、检查数、失败和交付状态；当前流程见[PIPELINE](../PIPELINE.md)，当前交付见[CURRENT_STATUS](../CURRENT_STATUS.md)。

本轮首餐门路交付已完成：1329项独占全量0失败，编译包完整夏季演示200项通过、退出0，默认存档未变，临时构建已清理。`builds/HareMachi.zip` 为最新验收包。证据见 evidence/first_meal_route_20261007/delivery.json；普通四小时与75分乐趣尚未验收。

## 首餐门路回归（2026-10-07）

当前开发清单1329项，生活组53项、对话UI16项。新门路检查使用0.4米半径、1.6米高度胶囊沿连续折线检测实际墙、家具与纸箱，旧版先触发失败；不依赖交互测试的stand_at。原生普通标题试玩独立记录，没有预置材料、瞬移、改钟或自动剧情。工具操作间隙不能计入自然时长。发布仍需冻结工程独占全量、解压编译包及完整autoplay。详见[FIRST_MEAL_ROUTE_20261007.md](../FIRST_MEAL_ROUTE_20261007.md)。

# 模型 → Blender → Godot 制作流程 v0.6

## 对话盘点、编辑与配音同步（2026-10-07）

dialogue_review.py提取条件组、互动函数与动态反馈；选择和回复一起读，编辑人工评分，build_dialogue_scores.py生成离线对照页。check_dialogue_review.py检查角色、心情、分支、状态代码、选项数量、占位符和纯显示字符串修改边界；坏句回归先在旧源确认会失败，不能代替文学审阅。改台词后用原选角生成固定文本，核对md5、ASR与断句，清理不再引用的音频、清单项和无源导入描述，再import。417条当前清单、92句新音频、591项结构检查与原生四组合证据见[本轮审阅](../DIALOGUE_REVIEW_20261007.md)；自动转写不证明逐句听感。

## 2026-10-07 新猫完整绑定与游戏接入

当前完整猫入口为 `art/poc/cat_full_rig_20261007/`：bind.py 拟合实际部位并在物理重合顶点的邻接图上生成八权重，animate.py 编写九个动作与连续过渡，audit.py 对重新导入的真实表面逐片段测量，render.py 看完整循环。游戏源码安装前必须核对 source-contract 的旧摘要与备份，install.py 原子替换并记录按摘要回退。新的骨锚点 foot-plant 控制需要与世界转向和实际表面检查区分；完整源动作和发布门槛见 [完整绑定流程](../CAT_FULL_RIG_20261007.md)。

## 人物运动清晰度复验（2026-10-07）

`--only=motion-clarity` 检查6项实际W+D+Shift斜跑、横跑、相同物理帧屏幕稳定性、跑速、镜头复位和人物贴图过滤。先在旧代码触发失败，再验证新代码；相机碰撞引起的正常取景变化不算抖动。固定真实run姿势、同相机四朝向比较FXAA/各向异性过滤，再看实际移动；截图放大只用最近邻，不能用后期锐化充作改善。镜头位置跟随与人物同物理帧更新，输入仍按渲染帧处理。当前1322项独占全量通过，本轮结果与默认存档摘要见evidence/diagonal_run_20261007/verification.json。详见[人物斜跑清晰度](../DIAGONAL_RUN_CLARITY_20261007.md)。

## 2026-10-07 Hyper3D 中立猫候选交付

Hyper3D 中立猫通过已登录 CLI 生成，任务脚本 `art/poc/cat_neck_alignment_20261007/hyper3d_jobs.py` 把提交与读取分开；查询超时只恢复原 ID。`prepare_hyper3d.py` 保存完整原网格，并以四脚与高处头部确定刚性前向、真实支撑面放平；`render_hyper_front.py` 与 `render_hyper_four.py` 输出真实模型截图。底面、截图与任务摘要见 [中立猫流程](../CAT_NEUTRAL_BASELINE_20261007.md)。

## 可挪动的现有茶托盘（2026-10-07）

居民早晨切片当轮独占冻结全量1311项通过，默认存档及源码摘要未变；新包须在本轮临时目录完成解压应用fresh完整自动演示，才替换唯一交付。运行验收和自然四小时分别记录。

`ResidentMorning`按P08真实三角形测完整托盘/杯具脚印，上方的同模型植物也查，不能仅凭支撑命中接受候选。静态几何/支撑缓存随变换或模型更新，新增与移除网格刷新动态检查；滑动途中继续检查存在、在场与净空。原生四选路径及性能记录用`--resident-morning-demo --evidence=<隔离目录>`，仅为夹具演出验收。保存失败、目标移除与托盘释放有32项回归；普通发现与自然时长另验。见[制作记录](../RESIDENT_MORNING_20261007.md)。

## 猫的中立基准与源网格检查（2026-10-07）

用户指出头身不齐时，先关闭张望并拍正面、上方、下方低角度与两侧，同时显示移除 Armature 后的源网格与当前基准。检查脸部参考图是否已经侧转；骨骼中线或两耳根关节平齐不能代替真实眼睛与耳朵外形验收。低头须在源脸部转正后应用，转头围绕颅部中心，避免偏额关节带来的侧移。模型重做先按 Pixal3D 免费流程，参考图先检查头与身体是否同向，再提交；完成后放平、测底面与统一尺度，五个角度实际渲染。详见 [中立姿态与新候选](../CAT_NEUTRAL_BASELINE_20261007.md)。

## 餐点 CLI 复查与截图时序（2026-10-07）

CLI 查询或下载失败时先核对已有任务与本地摘要，不能重复提交。`daily_life_demo.gd` 截图会等待 `frame_post_draw`，短动作可能在这一帧结束并释放；用 `shot_action()` 暂停该动作演出时钟，捕获当前状态后恢复，并在等待后检查有效性。修改前原生复查出现已释放对象错误，修正后五种食物的 18 项演出、消费及控制恢复检查通过。详见 [CLI 餐点复查](../MEAL_MODELS_CLI_20261006.md)。

## 猫的持续张望与小步复验（2026-10-07）

当前猫源文件入口为 `art/poc/cat_motion_review_20261007/`。Walk/Idle 负责躯干、爪部与尾链，`cat_look.gd` 在动画后修改头颈，注意力时钟不能被 Walk/Idle 重播重置。用 modifier 完成信号取得实际修改姿态，测真实蒙皮面部方向；不能只测原片段 Head 骨骼角度。两只猫必须同时验完整步态、左右极限转头、权重接缝和真实街道，旧数据先触发检查。导出、安装与复验步骤见 [猫动作复验](../CAT_MOTION_REVIEW_20261007.md)。上一轮工具与数据保留为历史，不应覆盖最新正式 GLB。

## 猫的步态、蒙皮和延迟摆尾（2026-10-07）

`art/poc/cat_lively_motion_20261007/build.py` 用四拍步态、双骨爪部 IK、胸臀反向摆动、独立头颈张望和尾链传播重建 Walk/Idle，保持网格和 UV。错误模板权重必须按实际解剖范围修正，在物理重合顶点合并的邻接图上平滑；四权重截断造成跳变时采用八权重，并确认 GLB 与 Godot 网格格式真实支持。Godot 的 glTF 自定义值在 `meta.extras`，原生步速须从实际导入层级读取。旧动作先触发回归，再对完整导出循环测实际蒙皮接地、滑步、尾尖、胸臀、张望和拉伸；数字通过后还要看侧、斜侧、后侧及实际街道。命令、证明和局限见 [猫的全身动作](../CAT_LIVELY_MOTION_20261007.md)。

## imagegen 与 Hyper3D 商店素材（2026-10-07）

新增十件模型先用imagegen制作独立参考，shop_asset_jobs.py经Hyper3D CLI提交已授权的High Raw任务；已有submission.json时不重复付费，--fetch只轮询/下载。原稿、参考摘要和任务ID保存在models_hyper3d_shop_20261006.json，游戏版经game_export、level_check、model_audit与实机近景验收。另有三张海报和两幅电视节目插画；商品图标从实际网格渲染到统一UI-kit。蛋糕柜保留外尺寸，薄玻璃逐面覆盖材质，商品支持面查询带实际层高上限。新增--only=shop-life专项24项；原生约42秒录像记录欢迎语、真实工作往返、补货与天气电视。制作和复现见[商店记录](../SHOP_LIFE_20261006.md)。

## 猫绑定适配与 AI 骨架实测（2026-10-07）

`art/poc/cat_rig_variants_20261007/` 保留原版、48 关节修正版、59 关节加密版及两种 MagicArticulate 预测骨架。检查实际绑定网格，排除 Blender 骨骼显示辅助网格；末端轴与长度同时查 `.blend`，不能只看 GLB 关节连接。权重按表面邻接平滑，也要处理头颈、尾根的旧预算突变；用相同诊断角度取实际蒙皮边长，并保存仍未合格的变形。`render_compare.py` 与 `render_ai.py` 使用临时独立 Forward+ 工程录制，完成后清理临时工程和 AVI。AI 兼容运行采用官方权重、MPS FP32 和标准 eager 因果遮罩；记录严格加载、模型摘要和实际输出，不把只预测骨架说成完成蒙皮与动画。74 条候选结构检查通过不代表整体动画验收，正式模型尚未替换。复现命令与证据见 [绑定对照](../CAT_RIG_VARIANTS_20261007.md)。

## CLI 餐点与运行轨迹检查（2026-10-06）

`art/tools/generate_meal_cli.py submit` 记录一次文字任务；`submit reference` 为指定参考图版本单独提交一次，`collect [reference]` 恢复已有任务并下载 GLB。记录存在时不会再次提交；查询/下载错误保留 ID。每次付费生成先说明用途，不合格输出登记 rejected，再经 game_export、level_check、model_audit 和实际餐盘截图验收。详见 [CLI 餐点模型](../MEAL_MODELS_CLI_20261006.md)。

`--spatial-report=/abs/report.json` 记录逐帧身体碰撞和每 0.2 秒的实例/可见性/位置；`--world-audit` 使用声明的日期和站位夹具，不计自然时间。静态 AABB 相交另列，不直接算穿模。[运行结果](../WORLD_RUNTIME_RESULTS_20261006.md) 保留候选调查及睡猫与加高墙体阻挡体的解释。

## imagegen 与 Hyper3D 环境素材（2026-10-06）

本轮用内置 imagegen 制作风铃、雏菊混合草丛、芦苇参考，再通过已授权的 Hyper3D CLI 分别提交一次 High Raw 50 万面；合计 1.5 积分。原稿、任务 ID、参考摘要保存在 models_hyper3d_environment_20261006.json。风铃用 prepare_furin.py 保留 UV 拆纸签挂点；三件经 game_export.py、level_check.py 与 model_audit.measure 更新正式清单。环境专项 --only=environment-life 为 23 项，彩旗/作物 --only=bunting 为 4 项，演员退开 --only=npc-overlap 为 3 项；本轮独立冻结全量 1150 项通过，无 SCRIPT ERROR；新模型必须再验真实近景与环境动画。参考、导出规格、原生录像与复现见 [环境记录](../ENVIRONMENT_LIFE_20261006.md)。

## 普通原生试玩与引导修复（2026-10-06）

独立原生审阅者从标题恢复已有首日，实际阅读公告/手账并追踪合作；未到店、未跨日。公告重复查看改为当前合作阶段和可选社区帮忙。日历负游戏日的星期计算独立处理，地图标签检查全部先前标签并保留画布边界。旧反例分别16/2、28/3、26/1，修改后对应专项通过；最终1086全量退出0，无SCRIPT ERROR，默认存档摘要不变。原生修复像素和授权的限时系统WASD持续移动另验，不能以测试替代普通连续玩法。见[NATIVE_UI_REVIEW_20261006](../NATIVE_UI_REVIEW_20261006.md)。

## 普通小桌与横幅复验（2026-10-06）

共享小桌加入普通料理、独处入口和实际可见性门槛；新厨房横幅使用内置image_gen平涂重绘并登记提示词，人物不改。普通饭团旧34项失败1项，隐藏桌三个反例旧44项失败3项；最终44专项、1077全量退出0，无SCRIPT ERROR。临时Web的站位/材料是夹具，实际E和面板像素另列；修复前冻结候选的解压应用204到Q15退出0，不冒充本轮最新包。见SUMMER_TABLE_REUSE_20261006及对应evidence目录。

## 完整headless与实际Web隔离复验（2026-10-06）

headless fresh204到Q15/home、退出0，图像和自然时间不计。临时Web复制已测试源码、Compatibility优化后本地8784验证，测试驱动停靠后用真实Edge鼠标/键盘；实际发现并修复P08遮挡、面板顶部裁切和动态庆祝图标。最终1066全量、31路线专项通过；本轮图像/响应头/范围见SUMMER_INTEGRATED_20261006。临时导出清理，不替换builds。

## 饭团与实际分装路线（2026-10-06）

`--only=meal-routes`27项；最终1062全量、退出0、无SCRIPT ERROR。`--meal-routes-demo --meal-role=rice|serve`准备原生输入：E/厨房鼠标，或1/2/A/D/W/S/Enter及鼠标拖动。新半成品保存、实际模型四角/茶托盘/重叠、固定碗份身份与松开行为有回归；原生因Mac锁屏未验。Rice制作与真正携到杯边分开，不以库存制作记录画在桌上。见SUMMER_MEAL_ROUTES_20261006。

## 邻里回请验证（2026-10-06）

`--only=neighbour-meal`检查33项邀请、来源、半成品、角色作者、两份守恒、私人/同场、普通材料、满包、暂缓和多话题并行。最终1035项全量通过，旧1033中1失败的数字类型恢复已保留日志并修正。`--neighbour-meal-demo`用真实E/切法键/鼠标制作验证新链，配独立数据库与绝对证据目录；当前Mac锁屏，尚未原生验收。P08支持面先按56点/四角扫描，再检查两碗实际脚印与上方物件，不能只量中心最高面。见SUMMER_RECIPROCAL_20261006。

## 食物去向的验证入口（2026-10-06）

`--only=food-purpose`检查35项份量、预留、旧记录、SQLite、杯边路线、中断回访、下一餐暂缓、私人知情和真实灶台按钮反馈。完整1002项、0失败、无SCRIPT ERROR。`--food-purpose-demo`配独立数据库，用E/数字选择/鼠标制作验证抽象杯边吃饭；当前Mac锁屏，原生未完整验收，早期遮挡截图不计通过。自定义截图镜头切换后等待4个物理帧，避免截到上一帧。见SUMMER_FOOD_PURPOSE_20261006及本轮verification。

## 完整合作演示与挂法对照（2026-10-06）

--autoplay的新档走SummerAutoplay，报告参数--autoplay-report=<绝对JSON>；实际碰撞走路/交互目标/装配键盘/日历保存/最终控制逐项检查，失败退出非0。--autoplay-resume仅从真实隔离存档调试，写fresh_run=false和起始摘要，不冒充全程。最后fresh 204项、退出0；约938秒为技术时间，不能计入四小时。

--lantern-choice-demo提供低侧/高通道的四个原生观察视角。--only=summer-flow检查主动旧箱、盆舞休息、便笺、灯挂取舍/回架/支路、花火站位与严格路径。全量始终单独运行；默认存档摘要前后核对。

## 日历与晚会的验证入口（2026-10-06）

`--only=calendar-advance`检查邀请、两种准备组合、逐日保存、同日失败、实际睡眠/午夜和损坏快照恢复。`--only=summer-gathering`检查独立新篮、材料/份量、实际路径与桌面、盘子距离、满包/跨日收尾、剩食归属、旧档收灯、唯一桌与活动身份。

原生`--calendar-demo`、`--gathering-demo`均配独立`--test-db`和绝对`--evidence`目录，窗口置顶。准备进度/日期/站位是声明的夹具；E/C/数字/鼠标、实际演员走动、桌面和作品变化另有画面。全量独占Godot，套timeout，并检查SCRIPT ERROR；输出JSON也使用绝对路径。

## 吃饭演出简化（2026-10-06）

LivingAction的eat分支只负责真实桌面的食物/空盘，不创建SkeletonModifier或hand目标。DailyLifeView提供实际支撑坐标和桌面镜头；每日演示分别截图吃前/吃后。原来手到嘴的eat断言改为不依赖骨骼的回归，旧实现48项失败1，新实现48项通过。sip与give保留各自现有行为。此次没有改对白或人物模型，不需重生成配音；编译包仍待完整夏季交付验收。


## 合作接入与工作间验证（2026-10-06）

新增summer-workshop专项23项，合作接入专项59项。只读独立审核指出的J接受卡步、ready浮标、旧步骤文案均有旧失败证据；现场朝向、预览取消恢复、安装改动失效另有实际碰撞/SQLite检查。原生workshop-demo使用E、A/D、Space、Esc与选择按钮，日期/前章和站位是明确夹具，不是自然时长。

--test-db现在在GameState初始化时实际设置SaveDB目录和数据库路径，不能只改旧SAVE_PATH。正式验证优先使用独立HARUMACHI_SAVE_DIR，始终核对默认存档摘要。默认第1槽本轮误写的记录与保存现状见evidence/summer_goal_20261006/default-save-observed；没有可靠起始副本，不声明原进度已恢复。


## 合作项目与安全试走（2026-10-06）

当前1227项全量通过，新summer-projects专项62项、summer-workshop专项23项、summer-space专项33项、calendar-advance专项28项、summer-gathering专项28项。NPC.walk_safe仅用于明确试走，按当前实体碰撞逐步检查；普通walk/日程保留，修改后还跑crowd默认/巡游回归。试走结果按布置revision保存，Vector3路径存成数字字典而非JSON字符串。

交接先减少篮内份量，pending记录手里一份；实际服务停点、近距动作与结束校验完成后记received。读档只归还未完成pending，不发已交出份量。试吃配方规则校验phase/role/n=1，craft_max不放多批，recipe_known不写false占位。材料及服务字段按整数恢复。

原生--cooperation-demo分food和--cooperation-host两路径，均使用E/数字/鼠标烤箱/K/Esc，站位和家具为显式夹具。截图、失败回归与完整状态见evidence/summer_goal_20261006，普通自然发现、主线/跨章接入和时长仍另验。


## 夏季基础、事实与短操作（2026-10-05）

当前开发工程1227项，新增SUM_A/SUM_E专项44项。用`--only=summer-foundation`单跑；独立HARUMACHI_SAVE_DIR和--test-db，套timeout并检查SCRIPT ERROR，全量单独运行。故意照片写失败的错误只对应明确回归，不能略过脚本错误。

MiniGame新增context和mg_outcome；剧情短模式关闭自由奖励权威，真实成果由GameState制作或共同场景提交，星级不能代表拼图复原/捕获/目击。started只在实际游玩状态成立，退出保留当次outcome；旧档保留成绩，缺事实不倒填。小游戏结果字段保存和读档一起检查。灶台发panel_closed结束原互动，用meal_shape锁完成短操作交接，不能仅close_modal(false)留下等待协程。

实际场景移动用Story.physical_point；Story._point是导航，跨区域可能返回出口，不用于演员站位或合影。原生专项：`--summer-foundation-demo --evidence=<目录>`，最后有效记录native-verified；站位/日期是夹具。复审、失败记录、配音与候选构建见[本轮记录](../SUMMER_IMPLEMENTATION_20261005.md)。


## 编译产物保留规则（2026-10-05）

按用户要求，builds顶层只保留最新桌面HareMachi.zip和最多一个最新Web目录web。旧包、重复包、解压目录、冻结工程与临时构建目录都清理。临时导出与验收使用本轮独立临时目录；验证记录放evidence，验证通过后替换最终产物，清理临时目录。具体规则见AGENTS.md，清理记录为evidence/builds_cleanup_20261005/cleanup.json。

下文的历史包名和冻结目录保留为当时的制作记录，这些历史文件已按本规则删除。


## 2026-10-05 首三天生活样本验证

此前生活样本批次738项，其中DAILY_LIFE 48项。专项用`--only=daily-life --test-db=/tmp/harumachi-daily.db`，全量去掉only；均套timeout。首次736项全量发现桌面支撑审计与嵌套数字读档三处失败，保留失败日志后修正。支撑只认可实际渲染三角面，不因support_surface标记放宽悬浮；手持物需使用当前骨架、4.7.2回调与modifier结束时的手部位置。

原生样本：`HARUMACHI_SAVE_DIR=/tmp/harumachi-daily-native $GODOT --path game --resolution 1920x1080 -t --position 100,100 res://scenes/main.tscn -- --daily-life-demo --evidence=/tmp/harumachi-daily-shots`。夹具仅安排站位，互动实际走E/数字键/鼠标/J/Esc；测试目录替换SQLite、设置和槽位，生产存档目录固定不动。代码、失败到通过的证据、配音与候选包见 [本轮实现](../DAILY_LIFE_20261005.md)。


## 2026-10-05 好玩审核与行为回归

上一审核修正批次690项全量通过，其中FUN为29项。仅按技术检查不能给好玩打分；设计、运行和真人体验分别记录，标准在 [FUN_REVIEW](../FUN_REVIEW.md)。先用旧数据或旧规则重现，再修复；本轮先18项旧15失败，组合28项旧10失败，最后品评预留29项旧1失败。源副本、原始失败、复审及最终结果在 evidence/fun_audit_20261005。

专项命令为 `$GODOT --headless --path game res://scenes/tests.tscn -- --only=fun-contracts --test-db=/tmp/harumachi-fun-test.db --out=/tmp/fun-test.json`，全量去掉only；套timeout，并检查SCRIPT ERROR。`--test-db`替换此进程的测试库与备份位置，避免测试入口删除真人主存档。带窗口的验证使用独立工程副本和独立测试用户目录，生产project.godot的晴町日常目录保持不动。

配音收集器同时读取日常选项回复。新19句已生成并ASR核对，9句旧音频与清单项先归档再从游戏移除；该批次结束时334句仍有2个旧ASR出界，不能据新句通过宣称全配音听感已验收。剧情阅览生成器可按当前源文件重新构建，不读取真人存档。


## 2026-10-05 空和澪也重做 A pose

两位依据原外观正背参考新生成，保留原 11 动作、30 手指骨及袖口次级运动。比较两种权重并修正包带、裙摆和肩袖，正式游戏、配方、人物库与默认试玩包同步替换；旧版留存。另外五人模型摘要保持不变。661 项全部通过，解压应用完整剧情 332.85 秒、44 张截图、Q05 完成、退出码 0、SQLite 校验通过。新旧逐人录像与制作过程见 [空澪再生成](../CHARACTER_LEADS_APOSE_20261005.md)。

## 2026-10-05 七人人物正式接入

空、澪沿用已满意外观并再降低肩袖；其余五人用保留原设定的下垂 A pose 生成。七人统一 54 人物骨（含 30 手指骨），空、澪另有 12 袖口辅助骨，保留原 11 动作和时长。成人采用焊合 UV 重合顶点后的热权重，小葵采用校正代理转移，和子追加披肩平滑与围裙姿态净空修形。游戏正式 CH 文件、可保骨骼的导出配方和人物库已接入；661 项全部通过。制作、对照、下载与发布证据见 [七人人物记录](../CHARACTER_ROSTER_APOSE_20261005.md)。

日期与默认 macOS 包已更新，旧包留存。最终解压应用完整流程 333.97 秒、44 张截图、Q05 完成、退出码 0，SQLite 校验通过；详见本轮 verification.json。

## 2026-10-05 3D 素材库与参考老树

新增本机 3D 素材室：目录来自游戏导出、68 个 Quaternius Standard glTF、329 个 Kenney GLB 及人物原稿。原包与许可证保留，缩略图由实际网格渲染，Three.js r180 本地加载。9 个 CC0 植被拟合米制、按材质拆树干/叶片、保留 PNG alpha 与 UV，再用 preserve_parts 和 image_format AUTO 导出；不强制 JPEG。制作主树使用 hero_shade_tree.py 的曲线枝干、体素合并、颜色烘焙和分层透明叶片，来源记录与提示词可追溯。完整步骤见 [ASSET_LIBRARY](../ASSET_LIBRARY.md)、[HERO_TREE](../HERO_TREE_20261005.md)。

猫的 glTF 在 UV 接缝处拆顶点，直接减面会产生大量开边；先仅焊合重合几何顶点，再简化，保留每面 UV。model_audit.py 的输出必须写到 game/assets/models/_stats/_audit.json，随后跑 level_check.py 和 Godot import。解析错误检查、全量单独运行和实景验收仍沿用既有流程。本轮最终冻结工程为 661 项完整检查，全部通过；PROPS 同时核对树下新铺地的支撑碰撞。

v0.1 的规划原文在 [v0.1/PIPELINE.md](../v0.1/PIPELINE.md)。本页写的是实际跑通的流程。



# 原技术流程尾部的日期补充

## 日式建筑构件与比较场景（2026-10-01）

`Blender -b --factory-startup -P art/tools/japanese_joinery.py` 生成木货架、室内墙框与商店侧墙，源文件、打包贴图的 .blend、原始 GLB 在 `art/models/raw/japanese_joinery_20261001/`。接着用 `game_export.py -- art/models/game_assets.json P_gondola P_shop_wall_frame P_store_sidepanel` 导出，运行 level_check、Godot import、带 timeout 的 PROPS 测试与 shots。游戏版木纹是 imagegen 原图的 1024 JPG 导出；材质的颜色乘数写入 glTF baseColorFactor，没有涂改图像。

`res://scenes/architecture_review.tscn` 是独立建筑对比场景：方向键旋转；1 原商店、2 新町屋、3 并排。带 `-- --out=/tmp/architecture-review` 自动截图四面与并排图后退出。用固定 Godot 4.7.2、`-t --position 3100,1990`；模型都经 WorldBuilder.spawn。`-- --only=walls` 单独查围墙瓦帽高度，在 PROPS 和全量回归中也会运行。详细来源与本轮验证范围见 [ARCHITECTURE_REVIEW.md](../ARCHITECTURE_REVIEW.md)。

### 本轮 macOS 包验证（2026-10-01）

本轮模型更改先跑完整 338 项回归，再导出日期版 ZIP，用 ditto 解压到 `builds/native-architecture-20261001/`。应用和 SQLite 框架均含 x86_64 / arm64，codesign 深度严格验证通过。解压应用由标题页的 `--newgame --shots=...` 检查实际模型，再由 `--autoplay` 跑完整流程；1222.5 秒、Q05 完成、退出码 0、SQLite quick_check ok 后才用临时文件原子更新 `builds/HareMachi.zip`。存档用 HARUMACHI_SAVE_DIR 隔离，测试与演示后恢复玩家原照片。结果与校验记录在 `evidence/package_architecture_20261001/`。

### 做旧材质与保留零件导出（2026-10-01）

`art/tools/texture_landmarks.py` 对备份游戏 GLB 更新 UV / 材质；输出 .blend 与 GLB 到 `art/models/raw/landmarks_aged_20261001/`。`game_export.py` 的 preserve_parts 分支保留物理原点与网格节点，避免把桥面的 deck 合并掉。用 `evidence/model_textures_story_20261001/geometry_check.py` 检查世界空间全部三角形的哈希，再跑 level_check、import、PROPS 和实机截图。`-- --only=materials` 单独跑四项材质 / 背景 / 字牌检查；本轮完成时全量回归为 338 项；供货更新后为 385 项。

剧情 HTML 由 `tools/story/build_review.py` 与 `review.template.html` 生成，数据直接来自当前 quests / prologue / festivals / dialogue / collection 和 story 脚本；源文件 SHA 与原委托记录一并保存。`docs/game-design/story.html` 是内嵌字体、图像、字体许可证的单文件版本，`docs/game-design/story/index.html` 是开发版本。重新生成用项目的 Python venv，见该目录 README。

### 应用图标格式

选择 imagegen 正方形原图后，用 `art/tools/export_app_icon.py <PNG>` 生成 1024 PNG、标准 iconset 与 ICNS。project.godot 的 config/icon 指向 PNG，config/macos_native_icon 指向 ICNS；macOS 导出 application/icon 同样指向 ICNS，include_filter 将 ICNS 带入资源包。字段含义见 [Godot 4.7 macOS 导出设置](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformmacos.html)。临时导出后比较 Contents/Resources/icon.icns 与源文件摘要，避免运行与 Finder 使用不同版本。正式包仍按发布流程验证后再替换。


### 剧情与供货增量验证（2026-10-01）

`-- --only=narrative` 单独运行剧情与供货检查，共 43 项。五条剧情一致性和错过节日的回归先在旧数据上失败；新流程通过真实店门、试吃纸签、烤箱、居民、柜台和庭院摊位检查。全量回归为 385 项。数据库和新合影都使用 HARUMACHI_SAVE_DIR，默认玩家存档目录不变。

带画面的新流程可用 `--newgame --bakery-demo --demo-out=<JSON> --demo-shots=<目录>`，从完成 Q05/Q06 的明确测试起点驱动新委托；脚本在 tools 目录，不依赖导出中排除的 tests。带窗口一律置顶、使用约定的屏幕位置。`shots.gd` 新增 bakery_order_ui、bakery_menu_old、bakery_menu_new、bakery_market，静态截图使用注明的任务状态；完整参与与补看由实际交互演示验证。

本轮新增 48 条角色配音，按现有选角生成并逐句 Qwen3-ASR 回转写；新条目全部满足 CER 不高于 0.3 且 pause_ok。清理三条不再使用的旧台词与 OGG，当前 manifest 为 326 条。旁白、春、田中继续只显示文字。

`-- --only=keepers` 检查两家店在节日与分钟更新期间的室内站位，以及离店后的日程恢复，共 3 项。使用当前 S02 版本重新跑了 153 模型的倾角记录，再导入、完整回归。

陈列检查 `-- --only=bakery-display` 对照 P09 网格实测的 0.525 米台面，旧篮底 0.89 米先失败，新篮底 0.525 米通过。素材持续并行更新时，使用已冻结的发布工程完成 level_check、import、385 项全量回归与导出，避免验证过程中资源版本漂移。

本轮最终 ZIP 来源是冻结快照，验证汇总在 `evidence/narrative_20261001/verified-release.json`。正常速度完整演示为陈列校正前的功能版本，1223.8 秒；仅陈列校正后的最终包用 `--fixed-fps 30 --disable-vsync -- --autoplay` 跑完整流程，实际 123.8 秒。加速检查验证流程与退出状态，不用它推算正常玩家的游玩时长。两个版本的包摘要和速度分别记录。


## Hyper3D 高质量模型与图集编辑（2026-10-02）

完整方法、参数对比与证据见 [HYPER3D_QUALITY_REVIEW.md](../HYPER3D_QUALITY_REVIEW.md)。`rodin_asset.py` 使用现有 OAuth 连接上传参考图、一次提交、按任务 ID 等待与下载；`--resume` 恢复同一个任务。模型在 `game_assets.json` 明确指定重展 UV、底色烘焙和原物理边界。导出后必须运行 `model_quality_check.py` 更新 `_stats/_quality.json`，再运行倾角检查和 Godot import。旧门楼瓦面、叠块舞台屋顶与无图集烤箱先在旧文件上失败；本轮新增五项回归，当前工程全量 390 项通过。三类画风、图集位置与字牌仍需看真实截图。

## 全模型巡检与建筑制作经验（2026-10-02）

[MODEL_AUDIT_20261002.md](../MODEL_AUDIT_20261002.md) 记录 153 个 GLB 的正反面巡检、四栋房屋和三件道具重做、14 件原稿的减面裂缝修复、九张图集编辑和 39 件旧 PBR 材质修正。要点是先在无 UV 几何副本上精确焊接接缝重复顶点，再减面、重展 UV 和烘焙；图集按每米像素密度验收，房屋还需检查门窗和人尺度。H03 的纸门由 `finish_house.py` 补格线并校正高度；H01 和 S06 显式缩减 UV 留白。生成 High Quad 的七个任务与积分估计在 `art/manifests/models_audit_20261002.json`。

导出后增加 `$PY art/tools/model_audit.py game/assets/models game/assets/models/_stats/_audit.json --contracts art/models/model_quality_contracts.json`；继续运行 model_quality_check、level_check、import、PROPS 和同镜头截图。`model_stage.gd` 可以批量出正反面清单。模型专项 28 项通过，当前全量 395 项、0 失败；此前剧情冻结发布快照仍是 385 项。

## 模型更新版重新打包（2026-10-02）

从当前工程复制发布快照 `builds/models-release-source-20261002-095933/game`，153 个模型与上一轮验收摘要一致。重新 import、395 项全量检查通过，再用 Godot 4.7.2 导出 macOS 通用 ZIP。ZIP CRC、深度严格签名、应用和 SQLite 框架的 x86_64 / arm64 架构均通过。

解压应用以 `--newgame --shots=...` 从标题进入，八个视角确认新房屋、农具棚、招手角色、面包和门楼；随后以 `--fixed-fps 30 --disable-vsync -- --autoplay` 跑完整条演示，实际 318.7 秒，模拟游戏时间 1229.6 秒，Q05 完成，退出码 0、无 SCRIPT ERROR。这个运行是加速验证，不用于估计玩家游玩时长。SQLite quick_check 和快照校验摘要通过，原存档、设置和照片保持不变。引擎退出时仍报告一个 shader RID 泄漏，流程和退出码正常。

验证后原子更新 `builds/HareMachi.zip`（744,379,746 字节），SHA-256 为 `e7c84fb6acc4a100b467d8d2cd26b65da43d42b12e010a4c7af3c669ce850a8c`。旧包保存在 `builds/HareMachi-before-models-20261002-095933.zip`，日期包为 `builds/HareMachi-models-20261002-095933.zip`。完整证明在 `evidence/package_models_20261002-095933/verified-release.json`。

## 建筑近景反馈修正（2026-10-02）

用户指出公寓和会馆近看弯曲、缺少日式细节，并要求增强商店菜筐。对比服务原稿与游戏版确认变形在原稿中已有；随后以米制 Blender 构件和 imagegen 材质修正街区 12 种建筑，保留占地和用途。梁柱、窗框、纸门、格子、雨户、椽头、瓦块及瓦当为真实几何；门牌、招牌和价格签用可读文字。菜筐有独立图集，玻璃反射为手绘底色。六块商店橱窗从导出网格重新测量。

每栋正反左右全貌、四向近景及檐口共九张，合计 108 张；另有实际场景近景、白天与夜间菜筐、商店窗户与街区视角。发现并修正瓦面行缝不足、侧墙错位、匾额遮挡，以及地台边缘与推车、小祠堂相交。最后模型专项 31 项、全量 398 项均通过，无 SCRIPT ERROR。旧数据三项新增回归均失败，射线结构基准要求小于 6 毫米，菜筐实际密度高于 300 px/m。

工具、可编辑源文件、素材来源与多面验收见 [ARCHITECTURE_CLOSEUP_20261002.md](../ARCHITECTURE_CLOSEUP_20261002.md)，证据在 `evidence/architecture_closeup_20261002/`。Hyper3D 原稿保留；此次修正后的建筑结构来源为 Blender，没有新增 Hyper3D 积分生成。

发布验证：新版 ZIP 为 782,758,026 字节（约 783 MB），SHA-256 `fcf3cf38e94af82e382a1aa232d4c957ff3f3e3bffd73525d3e0eb67304f37bb`。由最终工程快照导出；ZIP CRC、严格深度签名、x86_64 / arm64 架构通过。解压应用 11 个近景视角通过，加速完整自动演示 319.2 秒、Q05 完成、退出码 0；SQLite quick_check 为 ok，原存档、设置和照片不变。验证结果见 `evidence/architecture_closeup_20261002/verified-release.json`，原包备份在 `builds/HareMachi-before-closeup-20261002-133809.zip`。


## Hyper3D 独立主体与近景模块（2026-10-03）

12 类建筑主体已替换为图生 Hyper3D，原始任务 ID、参考图和装配来源保存在 `art/manifests/models_hyper3d_scene_20261003.json`。奶奶家拆成主屋 / 缘侧 / 格子门，公寓拆出六个单户墙面；单户部件实际密度约 304–367 px/m，整屋原件约 59 px/m。详细方法、错误尝试和源路径见 [本轮制作记录](../HYPER3D_SCENE_REPLACEMENT_20261003.md)。

当前测试数为全量 410、PROPS 43。`model_audit.py` 应写 `_stats/_audit.json`；三件地标专用 `model_quality_check.py` 写 `_stats/_quality.json`，两份报告不能互相覆盖。模型专项、全量与真实截图分别报告；整栋建筑仍低于 200 px/m 的项保留失败，不用放大图像或降低门槛制造通过。


## 湖区、钓鱼与实际 UI 验证（2026-10-03）

当前全量 449 项，新增 `--only=lakeside` 专项 39 项。全量保留一项既有整栋贴图密度失败，新增功能检查全部通过。地形、路径、水岸、钓点与地图以 LakesideLayout 为基准，杆、线和浮漂由 FishingView 表现；鱼获提交走 GameState 一次性票据，SQLite 字段保持向后兼容。

画面演示用 `--newgame --lake-demo --lake-demo-out=<无空格目录>`，需要单独的 HARUMACHI_SAVE_DIR。它实际走环湖路线、发送钓鱼按键、出售鱼获、购买调料、在厨房做菜并验证存读档。导出后还要跑原完整 `--autoplay`，不能用专项替代旧流程。完整制作经验见 [湖畔与钓鱼](../LAKESIDE_AND_FISHING.md)。

## 整栋近景材质补全（2026-10-03）

当前全量检查为 452 项，包含新增的两项贴图差异回归和一项面包店橱窗净空回归。`bake_building_materials.py` 在原始 Hyper3D UV 上烘焙 imagegen 立面编辑及米制木材、灰泥、瓦釉、布纹；`material_detail_check.py` 将最终图与插值后重新 JPEG 编码的控制组比较。之前整栋 200 px/m 门槛保持不变，12 类建筑现均通过。原有 39 项湖区检查仍保留。完整生成提示词、对齐办法和制作经验见 [建筑材质与近景修订](../BUILDING_MATERIALS_20261003.md)。

立面投影先用模型射线算可见性，避免把风铃、管道等前景图案重复画到后墙；临时可见性顶点色只供烘焙，导出前删除。町屋的投影使用实际 UV 对应点求出的刚体逆变换，和前一轮转正后的几何对齐。

## 远方小记验证（2026-10-03）

当前全量 481 项，冻结工程已全部通过，新增 `--only=homage` 29 项。新插图沿用内置 imagegen，必须保存真正的 alpha；Sprite3D 的裁切属性是 `alpha_scissor_threshold`。原图边界参与米制高度计算，避免透明留白把物件抬离地面。`--homage-demo` 使用真实 E 与对话，作物和起点是显式测试条件；发布仍需解压应用跑完整 `--autoplay`。详见 [实现、素材与来源](../HOMAGE_20261003.md)。

## 小模型拼接验收（2026-10-03）

当前全量 500 项，含 `--only=display` 的 19 项。旧场景在 19 项新检查上全部失败，冻结工程全量通过。15 种素材共 16 次 Pixal3D 生成，已保存原稿、参考图、任务 ID 与游戏导出摘要。八扇窗户各 117 条物理净空射线通过，本轮解压应用 20 张近景和 44 张完整剧情截图通过，Q05 完成、SQLite 校验正常、原生退出码 0；默认 ZIP 已更新，旧包备份保留。见 [真实橱窗与制作经验](../WINDOW_DISPLAYS_20261003.md)。


## 人物换装与骨骼管线 POC（2026-10-03）

空、澪各生成 Raw 整身、Quad 整身与宽 A 姿势基础身体，另试标准 BANG。保留原人物；隔离 POC 比较旧绑定、Rigify 热权重、模块服装及同网格对照。Raw 热权重有未赋权重顶点，拒绝导出；Quad 可绑定但不保证变形更好。模块身体与独立衣服共享骨架，并带覆盖区身体遮罩；Godot 4.7.2 实际运行、20 张截图与换装跳舞录像完成。澪极端抬手仍未通过诊断门槛，BANG 也未给出完整可换装身体。详见 [人物管线试验记录](../CHARACTER_PIPELINE_POC_20261003.md)。


## 人物管线第二轮：肘与手掌（2026-10-03）

用户指出衣服伸手变形和走路腕肘异常后，追加隔离 IK 对照。明确腕部方向、肘膝极向，保留 Rigify 驱动器并验证 Blender 与 Godot 的掌心方向；旧数据失败、新数据通过。18 张实机截图和 12 秒录像完成。独立衣服代理未通过美术与接缝验收，保持体积修改器没有改变本轮 GLB 的位置/蒙皮属性。另查 VRoid/VRM 标准基体、体素蒙皮、AccuRIG、Cascadeur，标准样本有 30 根指骨；这些替代路线尚未适配为空、澪。见 [第二轮实测与文档证据](../CHARACTER_PIPELINE_ROUND2_20261003.md)。

## 圆形小地图与生成背景（2026-10-03）

本阶段全量 524 项，含 UI_MAP 专项 24 项；冻结工程全量通过。两张透明图集共 24 个图标，三张背景覆盖弹框、HUD 和圆形地图边缘。大背景使用九宫格，窄条单独匹配角区；运行时等比取图与缓存，原 PNG 保留。输入和三个分辨率布局已验收；本轮解压应用两种分辨率真实交互、24 张 UI 截图及 44 张完整剧情截图通过。默认 ZIP 已更新，旧版留有备份。来源、制作经验和命令见 [界面记录](../UI_MAP_REFRESH_20261003.md)。

## 统一 UI 素材库（2026-10-03）

本阶段全量554项，含UI_KIT专项16项和DIALOGUE_UI专项14项。新增三张原生透明图集，统一按钮状态、物品格、提示卡和进度条；32个图标按语义ID获取。HUD、弹框、列表、日历、钓鱼、加载和小游戏从 `game/ui_kit/` 取得样式。`UITheme`、`UIIcons` 只保留兼容接口。

`prepare_ui_kit.py` 读取原图透明区域写目录；`ui_kit/build_resources.gd` 输出47个编辑器资源与48张独立PNG；`audit_ui_kit.py` 扫描私有边框，绘制地图和灯笼属于明确例外。`package_ui_kit.py --previews evidence/ui_kit_20261003/gallery-final` 创建含字体许可、提示词、哈希和独立Godot工程的素材ZIP；必须从最终ZIP解压、导入并运行图库。调用方法和经验见 [UI_KIT.md](../UI_KIT.md)。

对话期间使用AmbientUI父层隐藏常驻界面；不要在各个视图反复写visible开关。`dialogue_begin`幂等，`say`和`choose`也进入对话显示状态；通知在结束时补播，姓名标签按原状态恢复。`--ui-demo --ui-dialogue-demo --ui-demo-out=<目录>` 是实际鼠标和数字键演示；旧工程14项中9项失败，修复14项通过。过程和显示范围见 [对话修复](../DIALOGUE_UI_20261003.md)。

## 摆放与支撑批量检查（2026-10-04）

本阶段全量565项：PLACEMENT新增12项，移除献礼盒后HOMAGE为28项。旧12项检查失败10项，修复专项全部通过。旧PropAudit现在分别扫描镇和农园；PLACEMENT补齐所有模型树根、三只环境猫、长椅座面/脚底、入口和楼梯净空。深度登记577个model_id，原World登记505个；渲染支撑不能只用碰撞平面或模型脚印判断。

`rest_on_terrain`查询已创建的可见地形，`surface_height`可读取不带碰撞的座面；树根小幅埋土，动物脚底与支撑面匹配。常驻游戏逻辑不依赖被导出排除的测试脚本。新近景及删除盒子的验证见 [摆放记录](../PLACEMENT_REVIEW_20261003.md)。

## 每日保存与网页同步（2026-10-04）

本轮发布冻结工程573项全通过，DAILY_SAVE新增8项，旧版6项失败；后续生活开发版本598项另列于下一节。advance_day在日结信号回调完成后自动保存一次，sleep_now不再二次保存；save_finished统一手动/自动与成功/失败反馈。浏览器使用同一SQLite规则和现有同步标记。

网页UI从ui_kit/export_web_skins.gd导出，site/ui.css为共用样式，site/play.css为试玩外壳。图集像素目录不能随网页图片降采样一起缩放。prepare_web.py支持--source/--target/--evidence，要求新隔离目录；建筑/角色图集1024，其余512，几何与动画不变。preloadFile必须传pack.bytes.buffer，不能直接传Uint8Array作为对象键。新PCK约222.74 MiB，分段下载验证正常；详情见 [每日存档与网页发布](../DAILY_SAVE_WEB_20261004.md)。

## 2026-10-04 生活演出与拍照验证

当前全量 598 项，包括 LIVING 26 项。修改模型摆放后仍跑 PROPS 与 PLACEMENT；新增庭院墙也按真实高度检查墙帽。旧版首次 LIVING 22 项失败 20 项，新增兼容、透明鱼图与公交离站后为 26 项。发布验证的固定源码在 `builds/living-town-source-20261004/game/`。

`--newgame --living-demo --evidence=<绝对目录>` 通过导出应用的标题流程运行，不传场景路径。该演示使用实际键盘事件走通四个钓点、F8/F12/Esc 拍照、床的睡眠选项、日结和第二天 SQLite 存档；含公交到站、住宅街物理步行及动物连续近景。随后单独运行 `--autoplay --shots-dir=<绝对目录>` 检查原完整剧情。所有命令经 `art/tools/run_evidence_command.py` 设硬超时与独立存档目录。

拍照用独立 3840×2160 SubViewport 和同一世界、同一镜头输出 PNG，界面与姓名不参与图片；不会把窗口截图放大充作 4K。六鱼动漫图集由内置 imagegen 生成并复核，用 AtlasTexture 区域保留 alpha。相机 SVG/PNG/编辑器资源归共用 UI 库；重新导出 SVG PNG 用 `art/tools/export_control_symbols.gd`。本轮图标库为 33 个图标、16 控件与 3 底图；既有独立 v1 ZIP 保留为历史发布。

过程与证据见 [生活更新](../LIVING_TOWN_20261004.md)、[动物调研](../ANIMAL_ANIMATION_20261004.md) 和 `evidence/living_town_20261004/`。完整猫行走、跳跃与四足骨架没有在这次局部动画中交付。


## 2026-10-04：人物 T pose 与服装管线 POC

按原人物外观重新生成空与澪的正背面 T pose，Hyper3D 两个候选已下载。使用辅助人体转移权重，保留生成网格与贴图，加入手指和前臂扭转骨，迁移原游戏 11 个动作并校正时长。独立 Godot 4.7.2 POC 验证原 CharAnim 与脚步事件；正式人物素材未替换。服装分层、身体遮罩、裙摆辅助骨骼与原生胶囊碰撞的调研和验证见 [GODOT_CHARACTER_CLOTHING_20261004.md](../GODOT_CHARACTER_CLOTHING_20261004.md)。


## 2026-10-04：自然垂手与掌面修正

人物 POC 更新至 binding9。按实际掌部网格对齐代理手指坐标系，并修正张望、鞠躬、招手未抬起手的朝向；自然垂手时掌心朝身体，手指向掌心轻弯。旧版回归失败，新版 832 个实际蒙皮法线采样通过；原 11 个动作时长、资产完整性与 CharAnim 兼容检查通过。本轮未提交新生成任务，正式人物素材未替换。过程、对照视频与启动器见 [人物服装管线](../GODOT_CHARACTER_CLOTHING_20261004.md)。

发布复核补充：最终解压应用以 `-t --position 100,100 --fixed-fps 30 --disable-vsync -- --autoplay` 运行，避免超出可见屏幕的窗口延迟。此模式不按真实时间同步，仍走实际移动、交互与演出。完整44截图流程152.12秒、模拟1230.8秒、Q05完成，退出码0；证据在 `evidence/living_town_20261004/autoplay-fixed/`。


## 2026-10-04 公交与小镇细节验证

本轮 imagegen 生成公交参考图及草地、石板、沙地原图；提示词存于 art/manifests/prompts/town_detail_*.txt，图片和 Pixal3D 任务写入对应清单。运行 art/tools/detail_bus.py 校正模型、保留 UV 并拆车门与车轮，再通过 game_export.py 的 preserve_parts 导出 B01_bus。level_check.py 支撑面倾角为 0.09 度，新增模型单独测量后合并进 _level.json 和 _audit.json。近景验收后新增 18 项回归，旧版全部失败。当前完整测试数为 616。冻结工程为 builds/town-detail-source-20261004/game，证据见 evidence/town_detail_20261004。


最终解压应用的完整有窗口演示 329.15 秒完成，模拟 1228.5 秒、44 张截图、Q05 完成、退出码 0，无 SCRIPT ERROR；SQLite quick_check 为 ok，两份 v4 快照摘要匹配。默认 HareMachi.zip 已更新为 1,474,168,934 字节的通用包，SHA-256 为 `9e0140ab3f0cc832ca7ee69a575db1f67c1e4b1fc959ed6c984f05abab9f177e`；旧包保存在 `builds/HareMachi-before-town-detail-20261004.zip`。日期包为 `builds/HareMachi-town-detail-20261004.zip`，release_ready=true。


## 2026-10-04：人物肩袖与袖口修形

人物 POC 更新至 binding13_sleeves。保留原 T pose 基形、材质、贴图、54 关节与原 11 个动作，加入左右肩部、左右袖口四个姿态修形。肩袖轮廓收窄并下落，垂手袖口下落约 1 厘米；抬手时修形减弱。经过四个候选与实机近景比较，旧版回归失败、新版通过，手掌和 CharAnim 检查仍通过。正式人物素材未替换。参数、证据与对照启动器见 [肩袖修形记录](../CHARACTER_SLEEVES_20261004.md)。


## 2026-10-04：人物算法与开源插件深度调研

检索并核查权重修补、PSD/RBF、多姿态修形、GPU XPBD、原生弹簧骨与 SoftBody、自动绑定和服装版型工具。优先方案为独立衣物与干净拓扑、稳健权重、多姿态修形、局部物理。GPU Cloth 的源码含 XPBD 距离约束，但当前 Compatibility POC 不能直接运行，Mac/Metal、动漫材质与 Morph 叠加仍需实测；公开 RBF 原型未声明许可证。当前 binding13 保留，本轮没有安装插件、运行推理或改变模型。详细候选、许可证、源码核查与下一轮对照见 [深度调研](../CHARACTER_ALGORITHM_RESEARCH_20261004.md)。


### 衣物运行时隔离 POC（2026-10-04）

袖片分离、局部身体补面、原生弹簧辅助骨与 GPU XPBD 对照在 `art/poc/character_cloth_runtime_20261004/`。原 54 骨、30 根手指与 11 个动作保留；辅助骨袖片使用最多 8 个权重影响，复位要保留 Godot 4 的 Rest rotation。Spring 输出限幅 12°；GPU Morph adapter 保留原修形，固定肩缝不受碰撞投影，渲染只叠加平滑且限幅的局部位移。本地插件输出纹理接口与上游不同，使用整套隔离工程。素材契约、旧失败新通过、掌面和原生 GPU 检查完成后，用 `record_comparison.py --tag final` 顺序录制两个角色；保留同动作、同时间、同镜头。完整参数、许可、录像及尚未解决的拓扑问题见 [衣物运行时 POC](../CHARACTER_CLOTH_RUNTIME_POC_20261004.md)。

## 猫的 Hyper3D 模型与菜单 2D 动画（2026-10-04）

本轮按用户要求采用 Hyper3D 生成橘猫、三花猫站姿，Blender 适配 Mesh2Motion 48 关节模板并迁移 CC0 四足动作。素材入口、任务 ID 与复现脚本见 [CAT_MOTION_20261004.md](../CAT_MOTION_20261004.md)。绑定 GLB 用独立动画导出，最后 `finalize_cat_assets.py` 去掉法线与金属粗糙贴图，仅保留漫反射；二进制、外形、UV、骨架、动画与颜色贴图摘要保持一致，不再送入静态导出。

动画模型量支撑面时使用 `level_check.py -- --rest-pose <输出JSON> <GLB…>`：清除导入动作叠加，并排除 Blender 自动创建的骨骼显示网格。本次旧测量把 `glTF_not_exported` 的 Icosphere 算进去，得到无效的 37.66°；只量实际站姿猫后为 0.02°、0.32°。测量写入 `_stats/_level.json`，模型完整库存写入 `_audit.json`，只合并本轮两只猫的条目。

菜单采用独立生成的透明动漫图集，八帧 Walk、四帧 Idle；资源在 `game/ui_kit/`。`register_menu_sprites.py` 只读取 alpha 查找原生区域，用 AtlasTexture margin 对齐头部与脚底，绝不改原 PNG 像素。运行时 `menu_cat.gd` 为 Control + AnimatedSprite2D，没有 3D 资源；Hyper3D 猫只用于游戏场景。质量重要的模型优先用 Hyper3D，Pixal3D 简单道具评估另行研究。

## 2026-10-05 标题与面板上的垂尾猫

菜单装饰按用户草图更新到标题文字上沿，缩小后走动、趴下，尾巴垂到字前方轻摆，再起身返回。`register_rest_sprites.py` 只登记原图区域和虚拟留白；固定身体与八帧尾巴分开播放，避免整只猫抖动。`UIKitComponents.resting_cat()` 供背包、日历、设置复用，暂停时仍动画、忽略输入。实际截图、22秒录像与检查见 [CAT_UI_REST_20261005.md](../CAT_UI_REST_20261005.md)。

## 2026-10-05 参考老树版桌面包验收

最终冻结工程为 `builds/hero-tree-final-source-20261005/game`，661 项全量通过，无 SCRIPT ERROR。解压通用应用专项试玩 41.34 秒通过，三只猫 E 喵叫、司机对话、停车、覆盖确认和第 4 槽读取均通过；六份槽位快照摘要有效。完整剧情 329.65 秒完成，44 张截图，Q05 完成，退出码 0；SQLite quick_check 为 ok，v4 当前与前次快照摘要有效。 默认 `builds/HareMachi.zip` 已更新，日期包为 `builds/HareMachi-hero-tree-20261005.zip`，1,568,207,066 字节，SHA-256 `f2a8c18459ba53fb964104d0da4c1ea22ec8858b39ce46a1d429dcf6f06af5df`；旧版保存在 `builds/HareMachi-before-hero-tree-20261005.zip`。包的 CRC、签名和 Intel / Apple Silicon 双架构检查通过。总证据为 `evidence/asset_library_20261004/verification.json`，release_ready=true。

工作区保留其他人物制作任务的后续文件；本轮导出从已经验证的冻结工程执行，没有在角色再处理时读取半写入的模型。最终源码文件摘要保存在 final-frozen-files.json。


## 2026-10-05 人物头颈验收补充

头颈支点按实际头部网格定位，不沿用衣物体积的身体中心或仅由手臂斜率推算；脸与头发保留 Head 刚性权重，真实颈部与领口分别过渡。所有 11 个动作都采样，尤其张望、伸展、欢呼；原验收遗漏的动作不能靠静态与招手代替。权重只按颜色或硬 x/z 范围划分会在接缝留下尖条，应结合几何连接、UV 接缝与局部平滑。固定脸和手指，必要时保留八权重，避免第四个权重截断突然换骨。工具与旧失败数据见 [头颈与春婆婆验收](../CHARACTER_HEAD_NECK_20261005.md)。


## 2026-10-05 逐人检查下脸与所有衣服网格

人物验收按角色依次进行：每人11个动作，在正、侧、斜侧面取五个时刻，头颈近景与全身都看。顶端头部刚性检查不能覆盖下颌、耳下或上衣；审计必须遍历所有绑定网格，不能只取最大网格，否则独立袖片会漏检。下脸诊断用audit_jaw_skin.py，全部网格针状拉裂用audit_pose_tears.py，旧文件先验证会失败；真实颈部和浅色领口结合实际截图判断，避免强制整条脖子跟随Head。relax_skin_boundaries.py的脸脚保护高度按整个人物计算，独立袖片可用--mesh只处理指定网格。正式素材替换、人物库、可编辑下载与临时目录编译验收流程见[六人逐人检查](../CHARACTER_INDIVIDUAL_REVIEW_20261005.md)。


## 2026-10-05 招手与微笑验收

招手时掌心面向被招呼的人，垂手时仍面向身体；只修wave转向，保留其他动作。用实际蒙皮掌面多边形检查朝向，骨骼法线只能辅助诊断。手部比例按人物逐一看，缩手时掌、手指和关节层级一起缩，并保留腕部过渡。表情从微小闭嘴笑试起，检查正、斜、侧面和开始/峰值/结束；没有自然结果时保留固定表情。新增微笑通道不能用只有首尾的常量采样，必须在实际Godot中确认峰值播放、结束回零和走路取消后的恢复。详见[招手、微笑与手部比例](../CHARACTER_GREETING_20261005.md)。


## 2026-10-06：同一动画人物的贴图升级

高分辨率贴图候选先验证实际图片尺寸，再验证网格与 UV。Rodin 的导入确认可能重排网格和 UV，不能直接覆盖原动画 GLB；只迁移漫反射到原 UV。`art/tools/characters/rebake_diffuse_original_uv.py` 保存烘焙图片，`apply_character_texture.py` 生成独立候选并确认原节点、网格、蒙皮、动画和二进制保留。后者要求输入图片已对应原 UV，不会自行推断对应关系。整张 UV 图集做生成式增强可能破坏接缝，强度 0 也须检查；站立、招手、走路分别看脸、手和衣服的八个方向。12K 仅代表像素尺寸，身份一致性、配色和接缝未验收就不要采用。实测与费用见 [2026-10-06 POC](../CHARACTER_TEXTURE_POC_20261006.md)。


## 手部局部肤色候选

`rebake_diffuse_original_uv.py --restore-hands-from <原骨骼GLB>` 可按原腕关节平面和手/前臂权重定位手部，在腕部过渡；`--hand-albedo face-median` 从候选脸的颜色样本取动漫底色。该选项只烘焙贴图，需检查色彩空间与实际手腕过渡，不能代替最终动作验收。图像像素应通过 `foreach_get` 一次读出，逐像素 RNA 访问会反复复制整个图像。未完成状态与用户放宽一致性的标准见 [PBR 探索](../CHARACTER_PBR_SWEEP_20261006.md)。


## 人物多视角参考图

后续人物参考图按正面、左侧、右侧、背面四视图制作，同一人、同一体型与服装，使用正交视角、统一身高与脚底线。正背面 A pose 手臂下垂约45度，侧面是同一姿势的投影；手表、口袋和发型按人物的真实左右对应。整体四视图用于一致性审查，另存四张独立 PNG 供支持多图的图生 3D 入口使用。Hyper3D 给现有网格重贴图的入口只接受一张参考图（官方 Generate Texture 文档与网页实测），因此应选择含四个面的整图；逐张追加再点击会切换单选，不能当作四图同时输入。生成前必须截图确认实际选中的参考及多图模式，记录文件数与图中视角数。先看领口、后脑、袖长和衣摆，再提交付费生成。版本化参考不改写已有模型的历史输入；范例见 art/references/character_multiview_20261006/sora/reference-set.json。

2026-10-07 本轮最终全量：1201 项、0 失败，退出 0，无 SCRIPT ERROR；测试期间源码/测试数据与默认存档摘要前后不变。证据为 evidence/meal_plate_review_20261006/full-accepted/。本次仍未更新编译包，不以源工程回归代替导出包的完整 autoplay 验收。

2026-10-07 局部布局沿用修复：26 项路径/视线/新旧记录回归，原生 E/选择键确认无关装饰不重演、取餐桌变更只补莲。独占冻结全量1227项、0失败，退出0、无SCRIPT ERROR；运行期间无其他Godot，快照与当前源码一致，默认存档摘要不变。相关回归旧全局hash语义16项失败5项；两位整篇独立评分仍为64.8–72.8和61.2–69.2，感官U保留原分母，不自动升分。证据在evidence/layout_reuse_20261007/，详见LAYOUT_REUSE_20261007.md。编译包尚未更新。

### 试吃专项与摊位CLI（2026-10-07）

`--only=project-tasting` 运行36项用途、保存失败、餐具、行走和中断检查；`--project-tasting-demo --evidence=<目录>` 以声明夹具运行四种菜单/盛法的真实 E/选择与3D→空托演出。P09 的两次CLI任务和采用记录在 models_hyper3d_stall_20261007.json；生成查询不重提交。柜台检查须包括同一模型里的商品三角形及食物近景遮挡，中心支撑与脚印通过仍不足以证明可用。材质清理错误、完整回归和普通试玩分别记录，不把局部通过写成整体好玩。

2026-10-07 最终验收：project-tasting 40项、summer-gathering 30项、food-purpose 37项；独占冻结全量1278项、0失败，退出0，无SCRIPT ERROR、材质空引用0条，默认存档摘要不变，当前源码与快照相同。临时餐点在自身mesh退出时解除渲染base；桥保留逐surface的浅深材质，不能再叠加geometry override。原生四组合native-clean退出无引擎ERROR；编译包须另行导出和完整autoplay验收，尚未替换。

2026-10-07 当前桌面候选更新：合作陈列改当前真实柜台外围支撑（旧63项失败1项、新63项通过），自动演示早晨使用真实时钟等待实际走到营业时段，实际进店校验成立；独占全量1279/0，最终解压应用fresh --autoplay 200项检查到Q15、退出0、无SCRIPT ERROR/material null，默认存档摘要不变。新HareMachi.zip已原子替换并清理临时工程，Web保留此前已验收版本。完整界限和摘要见 [当前包验收](../SUMMER_RELEASE_20261007.md)。两份整体分数仍64.8–72.8/63.2–71.2，未过75，自然四小时/真人体验未证明。
