# 2026-10-18 人物新反馈修复记录

本轮按新反馈分为四组：空走路膝内扣、田中左臂隐没、和子走跑腿形、全员挥手与鞠躬时腿不动。本文记录最终方案与证据：当前源码组合已通过2502项独占完整功能回归，退出0；人工自然度复评仍由用户判断。

修改包括运行时姿态与控制器、脚底支撑、和子的等价布料计算加速及相关回归。七个角色的 GLB、权重、贴图和原动画资源未修改。引擎固定 `4.8.dev7.official.c971f93e7`；测试使用隔离存档、静音，未新建虚拟显示器。

## 1. 空：只修走路膝内扣

用户明确指出 walk 的膝盖向内弯，run 与 idle 没问题；这次反馈覆盖此前 walk 的人工通过记录。

原因是原 walk 的膝弯方向偏向内侧，脚底安全 IK 再抬高脚踝时，保留了这个膝平面，放大内扣。实际最终骨架中，膝相对三维髋—踝连线的有向内侧残差最坏为 −107.084mm；同一最坏姿势的原始骨轨约 −33.849mm，不能把两者混作一个量。

修复只进入 `Sora + walk` 分支，保留当前脚踝目标、骨长和脚朝向，用向前的双骨膝平面重新求解。run、idle 和模型数据不进入这段修正。

- 单项旧代码负控：[89 项中 1 项失败](../../evidence/rig_fix_20261018_sora_walk/negative-control/results.json)，仅新增 walk 有向膝残差门槛失败，最坏约 −121.87mm。
- 单项修复正控：[89 项全部通过](../../evidence/rig_fix_20261018_sora_walk/fixed-regression/results.json)。headless 与可见街道支撑高度不同，−121.87mm 与上述 −107.084mm 分属不同采样环境。
- 本轮组合 gait 正控的 walk 最小有向外侧残差为 +6.49mm，原门槛仍为不低于 −10mm。

单项修复批次另有470个真实连续最终姿态，最小有向外侧残差 +6.255mm，Natural修正前后脚踝最大位置差约1.35μm；切换记录429帧、428个完整最终骨架样本，无采样失败。进入idle的过渡末端未见硬切，run→walk结束时的帧间变化需按dt区分正常摆腿，不能只按毫米大小判跳变。

定位与原生骨架证据见 [空的分析记录](../../evidence/rig_fix_20261018_sora_walk/analysis-qualified-findings.md)、[连续检查](../../evidence/rig_fix_20261018_sora_walk/continuous-knee-check.json)及[切换复核](../../evidence/rig_fix_20261018_sora_walk/transition-after.md)。这些是各自冻结来源的单项证据，不代填当前最终组合的采样数。

## 2. 田中：左手臂被蓝上衣遮住并发生交叉

原视频站立与伸展起势可见左手臂隐没；新原生最终骨架重建进一步确认，walk phase .5 的左裸手边与躯干源面有 49 个交点。此前 run-hand-v4 只覆盖跑步的裸手域，不能据此认定所有动作、整片衣袖都已通过。

修复在 Natural 中只给左上臂增加 14° 外展，让其子链整体跟随；不重复旋转前臂与手，不改右臂。作用于 idle、walk、wave、bow、stretch；stretch 仅在起落两端淡入，中间原有抬臂段保留。**run 不变**，生产 GLB 不变。

- 组合旧代码负控中，walk 左腕距身体中线最小仅 91.64mm，未达到新增的 145mm 门槛。
- 组合 gait 正控中，同一指标最小为 198.21mm，33/33 个最终姿势新鲜有效。
- 实际修后按6动作×9相位重放54个正面最终骨姿：walk左裸手交叉由5/9相位、最多49个交点降为0；右手54姿态均无交叉。目标五动作所测左裸手的躯干遮挡清掉，run保留原来的少量正常投影遮挡。
- run九相位的全部骨位置与修前相同，旋转计算误差约2.41e−15°；stretch中间五个采样相位的全部最终骨字典精确相同，全部九相位的形状标量不变。有限抽帧未显示新增明显断袖或异常伸长，但没有把全蓝袖接缝交点设为零，也不宣称全袖面无穿插。

原图与定位见 [田中定位记录](../../evidence/rig_fix_20261018_followup/tanaka-visual-and-source-findings.md)，实际修后对照见 [54姿态复核](../../evidence/rig_fix_20261018_followup/tanaka-after-actual-qualification.md)。连续动作已在当前完整来源录制；最终交付采用[连续静止段版](../../evidence/rig_fix_20261018_followup/movie-tanaka-natural-transition/solo-tanaka/video.mp4)，保留wave→stretch→bow间的实际控制器状态。前一片在每段开头调用place/reset，导致stretch起始帧修正淡入时左手短暂被遮；原片与录制夹具问题保留，不以此修改生产姿态。

## 3. 和子：walk 脚踝外斜，run 前膝不抬、脚后拖

walk 的主要定位是膝相对髋—踝连线向内偏，令小腿向外斜；不能仅凭鞋的某个投影角就直接给 Foot 加反向 roll。修复仅在 walk 保留当前脚踝目标，重定向膝平面；原脚轨、Foot/Toe 朝向及骨长保留，后续脚底支撑仍照常执行。

run 当前选择的是更保守的收脚恢复：仅在摆腿期用连续 `sin²` 脉冲将脚踝目标最多向上移20cm，再按原骨长重解膝；后四分之一摆腿期用smoothstep的平方平滑回落，支撑期不执行这段位移。没有额外前推脚，也没有六臂曲线重采样，保留原run上身动作。其他动作不进入此分支，七个GLB不变。

| 指标 | 旧代码负控 | 当前方案已有证据或目标 |
| --- | ---: | --- |
| walk 最小有向膝外侧残差 | −65.95mm | 未改的walk修正已有 +1.49mm；门槛≥−10mm |
| run 两侧恢复期大腿前抬角 | 最小18.95° | 原生两峰约30°/31°；独立门槛仍≥30° |
| 同恢复期脚踝骨点在髋下方的距离 | 最大556.80mm | 原生两峰约399/388mm；新独立门槛≤420mm |

run恢复期仍取phase .25右腿与.75左腿，两者都是各自leg phase .75；完整鞋底、骨长、膝向前、循环接缝等检查仍覆盖原33个最终姿势。用户要求的是膝前抬自然。此前把“恢复时脚必须回到髋正下方”推成前向距离≥−30mm，是工程上的额外假设；它促使脚前推过多、压入围裙，不应保留为用户验收条件。新门槛保留抬膝，并以垂直收脚幅度抓住旧脚拖得过低的反例；没有放宽衣面或性能门槛。[旧代码配新门槛负控](../../evidence/rig_fix_20261018_followup/negative-gait-heel-contract/results.json)实际92项、3项失败，run为18.95°/556.80mm。

当前方案的 [Kazu完整衣物专项](../../evidence/rig_fix_20261018_followup/kazuko-full-cloth-heel/results.json)已实际取得10项、0失败：保留原65姿势及额外已知失败相位、原body/7点域，最大穿透4.691mm，最大Local位移90.578mm<120.5mm。末尾165个真实run完整求解回调的solve p95为7.669ms<原8ms，实际native backend启用。这是较早纯收脚方案的专项结果；后续平方窗、完整复拍、等价加速与最终全量分别记录如下。

随后首个组合全量[full-final](../../evidence/rig_fix_20261018_followup/full-final/results.json)实际2502项、2失败：旧围裙probe在run .3125报6.715mm，连续求解p95为8.651ms。两项均保留原失败；不把前述独立衣物专项通过升级成整批通过。

[同帧双尺度诊断](../../evidence/rig_fix_20261018_followup/apron-ray-same-frame-diagnostic/diagnostic-source-identity.json)保持原3268裤点、13551布面、.5法线门槛与5mm验收。scale1深6.7146mm，scale100仍深6.7274mm，排除了浮点精度借口。离线精确映射到源24764及同位置/权重UV副本24765，新衣物probe因两副本灰度差仅3/255跨过non_black_seams阈值而漏掉这处边界点；同帧重建也有真实边面相交。没有删旧点、修改语义分类或放宽门槛，见[定位](../../evidence/rig_fix_20261018_followup/apron-query24764-mapping-and-domains.json)。

增加末段回落后，[COW专项103项全部通过](../../evidence/rig_fix_20261018_followup/kazuko-late-settle-evaluation/results.json)：92步态+旧围裙1项+和子完整衣物10项。旧围裙65姿势最大穿深0；完整衣面原65加已知额外相位共66次最大3.124mm，最大Local85.053mm，真实178次完整run求解p95为7.775ms。抬膝门槛30°、收脚420mm、原5mm/8ms均保留。

和子布面建树另启用已有unique-panel分支，只把每个共用角点的100倍坐标乘法算一次，再按原三角面顺序填回。原生[同回调等价审计](../../evidence/rig_fix_20261018_followup/kazuko-unique-scaling-native/independent-result.md)取得102对完整求解、369条有序float32角点流、23字段原字节全同，六个最终姿势同帧匹配；1mm角点与.001权重负控均拒绝。此双算诊断不是性能数据，严格日志仅导入Adaptive主题缺失而为false；实际渲染进程退出0且无引擎错误。仅和子默认启用，不打开diagnostic_proxy_override，不改body、面域、约束顺序、迭代或其他人物。

末段一次回落的264图放大后仍发现主黑针点（front4像素/right8像素）。`full-final-v2`因此在361.9秒主动中止，退出−15，默认104份存档不变；没有完整结果，不计作通过。最终改用平方回落窗，只影响各腿phase>.75；[平方窗专项103/103](../../evidence/rig_fix_20261018_followup/kazuko-square-regression/results.json)再次通过：旧围裙最大穿深0，完整衣面66样本最大2.7425mm、Local最大84.389mm、受影响面积比例最大.33536，139次真实完整run求解p95为7.636ms。

[平方窗实际12图对照](../../evidence/rig_fix_20261018_followup/apron-query24764-square-actual-comparison.json)中，两个旧query位于外层后7.494mm；p.25/.75的全部54骨与222个shape保持精确不变。主针点缩至front/right各约1弱像素；同两条源edge与原8455面的交叉清掉，但转而与邻面8454相交，仍处外层。不能写成“两条edge对整个outer全清”或“全网格无自交”，也不为此抹除贴图或修改语义分类。[实际裁图](../../evidence/rig_fix_20261018_followup/square-native-comparison.png)与[边界说明](../../evidence/rig_fix_20261018_followup/square-actual-findings.md)原样保留。

平方窗的[完整原生复拍](../../evidence/rig_fix_20261018_followup/kazuko-square-native-independent.md)实际264静态、561连续、506切换帧、505对同帧完整骨架/morph，采样失败0。wave93帧/bow83帧九骨与root保持站姿；220非run静态及8个run恢复峰值与前一版全部骨/shape精确相同。这批是Natural d605+Garment65a6/旧库f6；读图场景run观察p95为8.146/8.427/8.313ms，不作为独占8ms通过。起走分析缺少符合工具条件的稳定idle样本，exit2但无已评估violation；不写成起走自然度已通过。

为保留原8ms预算，再把原GD的bounds/grid循环原序移入可选C11函数，只在和子启用。[152次同回调独立审计](../../evidence/rig_fix_20261018_followup/native-bounds-equivalence/independent-result.md)中，25字段、528组bounds/grid、528条有序树角流、528组完整native返回均原字节一致；11个最终run相位与旧f6库的54骨、222shape精确相同，两个内存负控准确拒绝。旧filter函数、所有约束、面与点、浮点写回顺序保留。

[无双算的10项原回归](../../evidence/rig_fix_20261018_followup/native-bounds-kazuko-performance/results.json)实际10/10，204次完整run求解p95为6.032ms，705次实际新方法调用；bounds均耗约68.78µs。它与前一批7.636ms不是配对时钟实验，不把差值写成稳定容量承诺。[真实旧库方法缺失回退](../../evidence/rig_fix_20261018_followup/native-bounds-real-method-fallback/native-bounds-equivalence.json)实际82对/4姿势通过，强制不可用flag为false、ClassDB实际方法缺失；保留原GD计算。早期`native-bounds-old-library-fallback`同时带强制flag，只当强制回退证据，不代替该独立能力检测。诊断严格日志均保留导入Adaptive主题错误。

已将通过上述专项的等价加速接入候选源码：Garment9c1fe、库c521，只和子启用，旧库/无native/显式`--native-geometry=off`继续原GD；当前完整全量已完成2502/2502、退出0，发布包未更新。最终影片绑定该来源，静态264图的旧加速来源不换标签。完整通过后只激活source-lock的accepted_library_sha256为已测试c521库，未重编译或改动游戏运行来源。

最初18cm前推/4cm上移方案及为其追加的32ms手臂移相**整版拒绝**。它虽然在 [positive-gait-v2](../../evidence/rig_fix_20261018_followup/positive-gait-v2/results.json)取得92/92，却出现可见黄围裙黑边尖折。[完整v2诊断](../../evidence/rig_fix_20261018_followup/full-v2-diagnostic/results.json)实际2498项、4失败：其中和子围裙/完整衣面两项穿透及一项8ms性能失败，另有一项已修夹具的问候恢复失败。原结果保留，不将其升级通过；旧大前推不是当前方案。

纯布与完整任一Local角面必须分别核对；旧大前推的 [单相位fairing试算](../../evidence/rig_fix_20261018_followup/kazuko-run-fairing-proof/README.md)未得到候选，未烘焙或推广新GLB。原始定位见 [和子分析](../../evidence/rig_fix_20261018_followup/kazuko-analysis.md)。

## 4. 七人：wave/bow 保留一个稳定站姿

原模型的 wave/bow 下半身轨道本来就是固定站姿。问题出在运行时：从 run 停下的同一帧立即启动手势，会把尚未结束的行走姿态混入手势；澪的 idle 与 wave/bow 又使用不同的腿部修正，连站立开始手势也能产生约 123.69mm 的腿部位置变化。

CharAnim 现在先进入 idle，等真实最终骨盆、双腿、脚与脚趾共九骨连续稳定 .25s、停止与转身过渡结束，再播放原上身手势。FootSupport 保存这一个最终站姿，在 wave/bow、动作结束的空 clip 帧及返回 idle 的过渡中持有；真实移动、重新放置、传送或坐下时释放。请求等待期间仍保持原来的 busy 语义，上身动作继续播放。

- 修正跑速夹具后的 [旧代码负控 42 项中 16 项真实失败](../../evidence/rig_fix_20261018_followup/negative-gestures-fixture-corrected/results.json)：七人的 run→stop→wave/bow 共 14 项，加上澪 idle→wave/bow 两项。初版的 17 项失败历史保留，其中春的一项属于未实际触发 run 的夹具误报，不计作修复收益。
- [v1 正控 42 项全部通过](../../evidence/rig_fix_20261018_followup/positive-gestures-v1/results.json)。澪四个手势场景的下半身位置漂移均为 0，局部四元数角差约 .03956°，上身挥手约 123.72°、鞠躬约 16.50°。七人移动取消、重新放置均释放锁定。
- 第43项专门在测试中省略FootSupport回调，验证手势已自然结束、控制器回idle后仍能释放。省略期间更新数为0，不靠1000倍播放速度推断modifier一定漏帧。[旧握手负控](../../evidence/rig_fix_20261018_followup/negative-gesture-handshake/results.json)实际1/1失败，[修复后43项](../../evidence/rig_fix_20261018_followup/positive-gestures-final/results.json)实际43/43通过。

另发现活动持续姿势可从`set_idle("wave"/"bow")`进入，绕过`play_once`。当前已把同一最终站姿缓存接到持续入口与循环退出，指定持续wave/bow会直接重复原片，普通单次手势仍只播放一次。原43项未改，追加澪持续wave/bow及退出的4项；[当前47项实际全部通过](../../evidence/rig_fix_20261018_followup/positive-gestures-loop47/results.json)。两种持续手势均观察到3次真实时间回绕，九骨位置与局部旋转漂移均为0；上身挥手123.73°、鞠躬16.50°，正常返回idle后释放。仅恢复旧Char4ae的[独立四项负控](../../evidence/rig_fix_20261018_followup/negative-persistent-gestures/results.json)有2项失败，腿漂移123.69mm，两个退出项通过。

澪真实手势使用稳定idle缓存，而原`garment_local_checks`的AP.seek不会启用该缓存。[独立真实控制器检查](../../evidence/rig_fix_20261018_followup/controller-gesture-garments/README.md)已在CharAnim `4ae57524cb811d9a7146b48062848aedcbb297f501ea3339d0be6fc47d324334`来源实际运行：wave/bow各自然到达三个中间相位，六次完整衣面测量，功能6项、0失败、进程退出0。穿透5mm、法线.35、Local位移上限120.5mm与原面积/p95政策不变。

该批 [validation.json](../../evidence/rig_fix_20261018_followup/gesture-garments-native/validation.json)的严格日志资格仍为false，原始63条ERROR未过滤：58条Dummy材质空值、1条Adaptive主题、2条系统返回码与2条日志目录写入错误。不能把功能6/6写成干净日志通过。当前CharAnim只增加持续循环入口，普通play_once几何设计未变，但这仍是旧冻结来源的六次证据，不能冒充当前完整来源的实时测量。

## 批次身份

[negative-gait](../../evidence/rig_fix_20261018_followup/negative-gait/results.json) 为 **92 项、3 项失败**，分别抓住田中 walk 左腕、和子 walk 膝平面与 run 恢复期。本组负控已包含此前空 walk 的单项修复，不能把它当成空的旧代码负控。

早期v2的92/92、当前heel衣物10/10、当前手势47/47及澪六次检查属于不同冻结批次，不合并成一个“最终全过”的来源。每批完整身份以各自`source-hashes.json`为准，首个未通过的完整来源保留于`evidence/rig_fix_20261018_followup/final-input-identity.json`，一次回落版另冻结于`evidence/rig_fix_20261018_followup/final-v2-input-identity.json`；平方窗与最终native候选分别冻结于`square-input-identity.json`、`final-native-input-identity.json`，350份GDScript、七模型、生产data与native扩展均有SHA；[最终完整结果](../../evidence/rig_fix_20261018_followup/full-final-native/results.json)已取得2502项、0失败、退出0，用时625.21秒。新测试UID取自本轮真实导入副本，来源另存`generated-source-uid.json`。

before-focused 与 after-focused 的七模型 SHA 清单相同：

| 人物 | GLB SHA256（本轮前后不变） |
| --- | --- |
| 空 Sora | `1a9dbf5516486c3770b0ce498ea009d73a89cfe4a5a5e3fe8489f352617f639b` |
| 莲 Ren | `964388d728336fe914e142b39ece3417db5d61af1c2d97b5b504fdeb0a983c83` |
| 春 Haru | `8e005cda56d062a6e7a2505f50e1a0e5d4bbd81347f0c527e3ec15b2a5b43be2` |
| 澪 Mio | `289fd7233400dcf1e53db919ff781a6649e7d18c4977de45a239f42aec15c5a7` |
| 小葵 Aoi | `25127d4c9f139fb6fa16161588a5b777dee9c3649687486695547d9d00e1ad20` |
| 田中 Tanaka | `c3e517b838f20ccb93c63e064f1da6d17986532d3796174bd3448b67c92eb5c4` |
| 和子 Kazuko | `fd49e931c62215ada89ee00ce2403310c71b6a318a99acf38acf71a53718bab5` |

## 最终验收与视频

[最终全量](../../evidence/rig_fix_20261018_followup/full-final-native/results.json)及[独立资格复核](../../evidence/rig_fix_20261018_followup/full-final-native/independent-qualification.md)确认2502项全部通过，含92项步态、47项手势；进程退出0，用时625.21秒，与其他Godot实例串行执行。和子完整衣面最大穿透2.742mm、Local最大84.389mm，澪/和子连续run求解p95分别6.694/6.124ms，原5mm/8ms门槛未放宽。和子实际native_geometry调用667次、fallback0；其他人物未启用该新方法。默认104份存档与照片SHA前后相同，COW工程已删除。

功能通过不等于无错误日志：全量运行原始75条ERROR保留，其中59条Dummy材质空值、13条数据库/照片故障注入预期错误、2条user日志目录写入错误、1条macOS系统返回码；导入另有Adaptive主题缺失与系统返回码各1条。没有SCRIPT/SHADER ERROR，但严格无ERROR日志资格为false。

本次交付三条24秒、1080p30、720帧H264视频，完整解码与BT.709有限范围标记通过。使用当前350份生产GDScript、七模型、22份data与c521扩展，额外注入只读遥测及录制控制器；现有screen0、no_focus、Dummy音频、独立存档，未新建虚拟显示器。AVI/WAV在编码及验证通过后删除，临时工程已清理。

| 视频 | 主要复查内容 |
| --- | --- |
| [爷爷单人](../../evidence/rig_fix_20261018_followup/movie-tanaka-natural-transition/solo-tanaka/video.mp4) | 站立、五向走跑、挥手、连续伸展与鞠躬；采用保留相邻静止段控制器状态的重录片 |
| [和子单人](../../evidence/rig_fix_20261018_followup/movie/solo-kazuko/video.mp4) | 五向走跑、膝前抬、脚斜、围裙与手势 |
| [七人同场](../../evidence/rig_fix_20261018_followup/movie/group-all-actions/video.mp4) | 反复持续挥手、两次鞠躬、返回idle；检查腿保持一个站姿 |

七人同场逐帧journal中，每人327个实际wave帧、6次真实循环回绕与84个bow帧均持有站姿；九骨世界位置最大变化约0.95µm、root位移0。手势尾部与最终idle均已释放锁定，没有把浮点噪声写成全世界矩阵逐位不变。影片原始退出日志各保留1条资源退出错误，严格日志资格仍为false；录像不作为性能基准。

根代理已复看三片抽帧；田中与和子另有独立原尺寸抽帧复核。有限画面未确认新增断袖、明确大穿模或长黑针；和子的硬明暗折面、抬腿围裙拱口与上述约1弱像素微折交叉仍留给连续人工点评，不宣称全网格无自交或自然度已通过。前一条田中片与所有旧点评页、旧录像、失败/中止批次原样保留。

旧Char4ae来源澪六次真实手势衣面功能通过仍只证明其冻结范围；当前持续入口已由47项与七人影片验证，但没有新增一批当前完整来源的同款六姿衣物测量。桌面ZIP、Web和旧导出加载证据保持历史来源；本轮交付源码与复查视频。
