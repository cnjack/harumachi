# 人物骨骼与动作逐项复核记录（2026-10-18）

状态：v100 七模型与 `340bf/f6` runtime/native 组合的2451项功能回归通过，退出0；模型已安装到游戏、日期源目录和素材库，最终九段新视频和单人168秒/多人48秒合集已完成。技术检查、有限原生目视和用户接受分别记录，尚未取得新版人工自然度通过。桌面ZIP和Web未更新，另一次场景试走失败保留在下文。

## 人工基准与候选身份

原始人工导出为 49 项：有问题 27、通过 12、不确定 1、稍后再看 5、未点评 4，另有 15 条精确单帧意见。依据保存在本地的[原始点评][human]，SHA256 为 `1bfbe9096d0812af16ca15f2773d5ab7052814acfad6f6f2974849059b14a888`。原通过是保护基准；原未定意见不能自行升级成缺陷，也不自动判为新版通过。

[新 49 项页面][ui]和[复评说明][guide]已有 1400 张原生图、同帧骨架叠图和 70 组走跑路线。它对应 v97 画面，后续澪、田中的专项修复需看各自补拍，不能把旧页面图片当成新组合。用户的新 49 项结果仍待交回；原页面和原点评保留。

本稿采用 [integration-v100 候选清单][bank] 的精确身份；该候选清单保留当时未推广状态，正式安装另见`art/manifests/character_rig_review_20261018.json`及`evidence/rig_fix_20261017/v101-production-promotion-completion.json`。相对 v99，仅将澪 78 处、春 312 处 SCALAR accessor 的数字 min/max 规范成单元素数组；两模型 BIN、全部 4580 个 decoded accessor 和其余 JSON 精确保留，另外五份模型逐字相同，[格式修复和原版工具实测][normalization]保留新旧 SHA。没有通过 Blender loader shim 绕过格式错误。历史来源仍见 [LATEST_STATE_V99][state]；当前组合验收记录位于`v101-final-full-tests-supported-probe/root-full-qualification.json`，不能将旧 SHA 或旧检查改名为本组合结果。

| 人物 | 当前候选 SHA 前缀 | 当前范围 |
| --- | --- | --- |
| 空 Sora | `1a9dbf551648` | 继承 v97 复评候选 |
| 莲 Ren | `964388d72833` | 继承稳定躯干后的 clean964，不采用撤回的后腰修形 |
| 春 Haru | `8e005cda56d0` | `c0e275…` 元数据规范化后身份；保留原认可跑法，只在真实循环端点附近封口 |
| 澪 Mio | `289fd7233400` | `a730…` 元数据规范化后身份；保留 v80 走跑与衣裙来源，追加伸展袖形候选；有限残余见后文 |
| 小葵 Aoi | `25127d4c9f13` | 继承 v97 复评候选 |
| 田中 Tanaka | `c3e517b838f2` | run-v4 手掌避开衣身；伸展重建重力袖形 |
| 和子 Kazuko | `fd49e931c622` | 原接受 walk 围裙曲线与修正后的 run 来源组合 |

## 原 27 个问题逐项入口

表内“处理”描述本轮采用的修复类别，不是人工通过结论。每个 `人物/动作` ID 均可在原点评与新页面定位；精确原图、标记和 SHA 以原点评为准。公共证据分为[关节拟合][joints]、[莲肩轴][ren-shoulder]、[手部结构][hands]、[步态与支持][gait]和[新批次有限目视][visual]。

| 序号／原 case | 原问题及原定位 | 处理类别与追溯入口 | 有限验证与待复评重点 |
| --- | --- | --- | --- |
| 01 `sora/idle` | 膝后弯、罗圈腿；0% 正面／右侧 | 关节中心、站姿腿轴和最终鞋面支持；[关节拟合][joints]、[步态][gait] | 最终 modifier 腿轴检查及有限正侧图；仍需看整体站姿自然度。 |
| 02 `sora/run` | 小臂太外，像老奶奶跑步；37.5% 背面 | 重建跑步收足／摆臂，躯干补偿保留自定义臂姿；[步态][gait] | 原生 88 项中的摆臂门槛和连续样本可追溯；阈值不能代替跑感。 |
| 03 `sora/wave` | 小臂衣服及腿张开大；12.5% 正面 | 站姿腿轴、袖身接缝及局部袖形；[新图][ui]、[有限目视][visual] | 褶皱、袖下露肤与站距需原图复评，不能只按骨链连续判贴合。 |
| 04 `sora/stretch` | 大臂像折断；62.5% 正面 | 肘部结构、袖身连续与动作修形；[结构][joints]、[新图][ui] | 缩略图未见原大断折；整圈袖形与皮肤遮挡不由单帧保证。 |
| 05 `sora/bow` | 仍是腿部问题 | 站姿腿轴／骨盆支持同类修正；[步态][gait] | 已有正侧面及最终腿轴证据，鞠躬观感待人评。 |
| 06 `ren/idle` | 膝像骨折、小腿外翻及向前折；0% 正面／右侧 | 髋深度、膝踝中心与站姿求解；[关节拟合][joints]、[步态][gait] | 宽裤遮住内部关节，表面裤褶不能单独证明骨轴。 |
| 07 `ren/walk` | 膝绑定问题；0% 右侧；后来追加“一歪一歪的” | 紧凑步幅；相对新骨盆重算 Spine 补偿，去掉重复侧倾；[步态][gait] | 原生前后胸侧倾峰峰 16.993°→3.596°，肩高差振幅 112.31→23.48mm；用户仍需看实际连续走路。 |
| 08 `ren/run` | 膝绑定问题；12.5% 右侧 | 新腿轴、紧凑回收跑步和躯干／臂姿补偿；[步态][gait] | 新 quick 使用 3.2m/s，与旧 4.5m/s 对照条件不同，应按实际速度判断。 |
| 09 `ren/wave` | 肩膀离躯干太远；87.5% 背面 | 按真实上臂壳中心拟合肩轴，补偿 rest／动画／绑定矩阵；[莲肩轴][ren-shoulder] | wave 通道来源保留；壳内定位不等于所有肩部动作自然。 |
| 10 `haru/stretch` | 衣服局部有问题；37.5% 正面 | 衣面、肘袖轮廓与法线复核；[新图][ui]、[有限目视][visual] | 本稿不据联系图宣称原贴合问题已消失；紫袖软褶与局部起伏留用户判断。 |
| 11 `mio/run` | 脚踝／脚底太靠里；0% 正面 | 紧凑跑步、有向脚道与服装联动；[步态][gait]、[新图][ui] | 脚道检查不能用绝对间距掩盖交叉；3.2m/s 新 quick 不冒称保留旧 4.5m/s 步幅。 |
| 12 `mio/stretch` | 手臂衣服贴合；62.5% 正面 | 物理接缝同步、局部袖形与中间形状过渡；[v99 实际目视][mio-v99]、[当前状态][state] | 灰楔／长垂尖明显减小；窄折缝约 1mm、局部压缩与全域自交限制仍保留，不判全衣面自然通过。 |
| 13 `aoi/idle` | 站立膝盖过弯 | 膝踝关节中心、站姿屈曲与支持修正；[结构][joints]、[步态][gait] | 有限正侧图已不呈原半蹲，仍需确认儿童姿态自然。 |
| 14 `aoi/walk` | 脚踝绑定问题 | 踝轴、紧凑步行、最终足面与鞋底支持；[步态][gait]、[小葵／田中目视][aoi-tanaka] | 抽样未见明显侧翻，不等于全周期无滑步／足滚动误差。 |
| 15 `aoi/run` | 小腿肌肉外翻；37.5% 正面 | 腿轴与回收跑姿、躯干侧倾补偿；[步态][gait]、[小葵目视][aoi-tanaka] | 原定位的静态／真实近相位图已对照；未以稀疏图覆盖所有落地时刻。 |
| 16 `aoi/wave` | 衣服贴合 | 袖口／局部衣面修正与五向复看；[新图][ui]、[小葵目视][aoi-tanaka] | 白袖口仍略厚圆；未确认清晰破洞，贴合观感待复评。 |
| 17 `aoi/stretch` | 衣服贴合 | 肩肘轮廓和短袖形态复核；[新图][ui]、[小葵目视][aoi-tanaka] | 没有凭骨链连续声称衣物全部贴合；腋下厚环状边缘保留复看。 |
| 18 `aoi/bow` | 双腿拆开太大 | 站距、膝轴与骨盆支持；[步态][gait]、[小葵目视][aoi-tanaka] | 现有正面站距收拢，最终自然度未由代理代填。 |
| 19 `tanaka/idle` | 腿部问题 | 髋深度、膝踝中心与站立支持；[结构][joints]、[步态][gait] | 宽裤／靴筒遮挡内部轴；有限图与指标分开。 |
| 20 `tanaka/walk` | 脚步和骨骼绑定 | 老年人物紧凑步行、鞋面支持、躯干侧倾补偿；[步态][gait] | 保留较小摆臂和硬靴风格；不强行统一年轻人步态。 |
| 21 `tanaka/run` | 骨骼绑定 | 腿轴与紧凑跑姿；另修新发现的手掌进入蓝衣身；[run-v4 原生资格][tanaka-run] | 修复后 35 定格＋239 最终移动骨帧双手真实衣面交叉为零；有限样本，不是所有相位／混合的数学保证。 |
| 22 `tanaka/wave` | 手部骨骼、衣服、关节 | 肩肘中心与手部结构／权重；[结构][joints]、[手部][hands]、[新图][ui] | 已看手腕主轮廓连续；细指和袖口不能由跑步手掌避让结果代替。 |
| 23 `tanaka/stretch` | 手臂像骨折 | 四个 stretch-only 字段重建宽袖重力引导，保骨轨／基底权重；[c3e5 原生资格][tanaka-stretch] | 621 实际姿态全支持域及真实前臂／手表面审查；宽袖上侧体积保留，有限技术目视接受，最终组合与人评独立。 |
| 24 `tanaka/bow` | 骨骼绑定 | 腿轴、骨盆支持与弯腰姿态复核；[步态][gait]、[田中目视][aoi-tanaka] | 两脚及膝裤轮廓的有限观察不覆盖衣内全部骨骼；浅鞠躬风格待人评。 |
| 25 `kazuko/idle` | 脚踝绑定 | 踝中心与鞋面／站姿支持；[结构][joints]、[步态][gait] | 保留原 walk/bow 人工通过作为保护范围，不将站姿修正扩为全部动作改写。 |
| 26 `kazuko/wave` | 手臂不自然 | 挥臂姿态、手部／袖形复核；[步态][gait]、[新图][ui] | 原话没有具体单帧部位，保留整体挥手自然度给用户判断。 |
| 27 `kazuko/stretch` | 衣服贴合 | 服装局部接触与袖／围裙连续形态；[新图][ui]、[复评说明][guide] | 方向性 body→cloth 原门槛不等于双向无交叉、无撑空或全衣面自然，须看实际轮廓。 |

## 已认可与未定动作的保护

原 12 项通过为：空 walk；春 idle/walk/run/wave/bow；澪 idle/walk/wave/bow；和子 walk/bow。不能用修前中间 WIP 的过撑轮廓替代真正人工基准。春跑步保留原曲线主体，仅修端点；和子恢复原 28-key walk 围裙曲线。澪曾尝试精确恢复旧 walk 衣物曲线，但实际接触退步，当前继续采用 v80 来源，需让用户重新看原认可观感，没有把“恢复旧曲线”本身当成功。

空、春、澪、小葵的 dance 与莲 stretch 原为“稍后再看”；莲 dance 为“不确定”，原话“跳舞动作大多都不自然”；莲 bow、田中 dance、和子 run/dance 未点评。舞蹈按原指示不作主要重写目标，这些项目不以新技术检查自动变成通过。

## 步态、手部与衣面证据的边界

步态 88 项检查最终 modifier 结果，含站姿、完整足面测试、两周期接缝、腿轴／摆臂与九条躯干侧倾回归。旧源负控能重现九条新增侧倾失败，相关旧运行也暴露过后弯、半蹲、无腾空及接缝问题。已有 42 组三视角实际走跑骨包与完整足面离线重蒙皮补充；各原生报告仍绑定当时模型/runtime，不能直接改名成为 v100 最终组合全套结果。[步态记录][gait]保留测量域和跳过原因。

走跑切换使用紧凑 walk 的速度阈值与滞回、按 AP 时钟累计修正混合、指定方向的相位策略；稳态保留已认可动作。启动和手势收势回归只覆盖其明确时钟／稳定姿态域，已有 startup 四条符合、三条因观测间隔跳过的记录，不能说七人所有切换都已覆盖。当前 70 路线鞋面缓存检查也不等于完整足面、无滑步或自然度验收。

田中 run 的原缺掌不是简单缺面：近侧手掌进入前后实际蓝衣包络。采用最小、周期光滑的前臂姿态偏移，保肩肘位置、腿、网格和其他动作；没有把正常后摆手遮挡当缺陷。run-v4 的有限真实样本消除了已测交叉，旧连续样本的反例保留。

田中 c3e5 stretch 的原生 20 定格＋五向过程合计 621 实际姿态，包含 601 个连续 callback、596 个独立后帧确认；149 张连续 PNG 均有确认。同一批对 89902 面及物理副本检查没有新缝／翻／塌；受影响蓝袖与 4950 个实际可见前臂／手三角面没有已测交叉。皮肤点未动，宽度与垂量保留。模型衣内没有完整上臂皮肤，不能凭空补人体表面或把最近可见肤色的无符号距离叫作空气 gap；621 样本也不是全时域证明。

澪 a730（规范化后 `289fd…`）仅在 stretch 改四个袖形字段并追加一个中间控制，POSITION 与 NORMAL 同步；其余 11 动作原函数、骨轨、基础网格、skin／UV、裸皮肤和衣裙保留。25 张定格＋157 张五向连续原 PNG 中，旧灰楔与背部垂尖明显消除，未见新增明显鼓球、脱片、接缝露洞或轮廓长刺；证据与结论见[有限最终审查][mio-final]。825 个正确旧／新函数姿态复核和 698 个实际姿态支持域检查不等于所有时刻的自然度保证。

窄折带、局部平板感和接缝邻带约 1mm 微交仍存在，不能写成全局无自交。现有真实手臂／袖口的距离与原图风险位置已分开记录；部分衣内上躯干没有真实皮肤网格，离手臂的欧氏距离不能直接叫衣身撑空。低面积／急折诊断和有限可见性分级均保留，最终组合功能回归已通过，最终贴合自然度仍待用户复评。

## runtime、性能与交付验证

当前候选 runtime SHA 为 `340bf4e29d0660934ed32f307b05aafc5eaa7654ac0ffc08b7bd45aee922fb8e`，native 库 SHA 为 `f6c60416b6c6d04473c8a7bda3153e125a33b8f9ba5a73bf376da4ab2373b379`。原 garment 5mm 穿入、0.35 法向与 8ms 回调预算保留。原生后端之后补入通用身体边中点，针对已证实的“顶点安全、面内部穿入”缺口，未改衣物模型或接触阈值。

[12mm 候选][performance12]虽过几何 pilot，Mio walk 原生 p95 为 8.486／8.349ms，超过原 8ms，已拒绝。[15mm 候选][performance]保留 Mio 1648 个原身体点，仅对纯身体源面去重后静止长度严格大于 15mm 的边增加 2247 个最终蒙皮端点平均中点；不加面心，不按动作、相位或面 ID 特判。真实三人两轮走跑中，Mio p95 为 6.593–6.995ms，Kazu 为 6.838–7.029ms，四个动态 block 均低于原 8ms；Ren 仍只在已认证稳态走 fast 分支。该结果绑定 v100、340bf/f6 和已测场景，不是所有设备／场景性能承诺；15mm 也不是由 5mm 推导出的全表面误差上界。

[扩大查询域的同回调对照][expanded-domain]记录 122 对、13 个输出字段原字节相同。两条算术路径共享新增查询域，不能把它说成与旧顶点查询域语义相同，也不代替衣物自然度。真实缺插件回退和饱和等分支仍按各自夹具记录，未出现的分支不补写为覆盖。

和子旧围裙专检另修正了检测域：保留原 paint 源面，取消“静止时距第一层超过 12mm 即永久丢弃”的过滤，使动态外层可被实际最终姿态测到；只把非中性且有 Local 衣物模板支持的 22 个褐布误标签移出 pants，中性灰裤点和三个未证实标签保留。[第三候选原生正控][apron-supported]的 65 个请求全部 fresh，覆盖／恢复检查通过。该修改只影响 probe 分类，不改衣服、runtime 形变或其原有 5mm／0.5 法向、scale1 门槛；不能将修正误标签解释成清除了所有隐藏穿插或自然度问题。

围裙第三候选已应用；v100＋340bf/f6 的[最终2451项功能回归][full-running]全部通过，退出0。日志原样保留59条既有Dummy材质错误，以及13条数据库/照片故障注入错误；这些均逐类、逐恢复检查核对，严格无错误日志判定仍为false。七模型与runtime已正式安装，项目源码检查7611项/180JSON/303Python通过，最终录像和用户复评继续分别归档。Ren steady 证书只覆盖精确内容身份与允许姿态，未知修饰器、资源／carrier 变化和其他不符合域的状态需回退；不能推广为 Mio/Kazu 只按 phase 免求解。

提交范围见本地 [allowlist 复核][allowlist]。必要 writer、C++ 距离 helper、测试 fixture 和主路由不能漏；被拒绝的实验不因存在工作区而自动提交。当前入口和测试总数已据实际结果更新；历史发布包仍保留原2296项验收含义。

临时解包macOS arm64应用的native模块实际加载，澪/和子均有真实native层与完整求解计数；代码签名验证通过。导出阶段忽略override.cfg的窗口配置问题已通过临时project.godot修正，实际NO_FOCUS与screen0也已确认。该native加载资格保留既有58条Dummy与精确12 ObjectDB/6资源退出噪声，不称clean-log。

实际东侧场景试走未通过：澪以3.2米/秒走完，春在移动前就因静态ProjectRoute不可达中止，仍使用原4.5米/秒，莲未进入该轮移动。家具/静态布局未由人物修复改变；该场景问题单独记录于`v101-space-trial-collision-telemetry/telemetry.json`，不据此宣称全部场景通过，也不把它当人物绑定回归。

## 已交付旧九片与本轮最终九片

旧 [九条视频][old-videos]来自不可变 v97 模型和 `22564ee15b80…` runtime，七条 solo 各 24 秒，单人合集 168 秒；两条 group 各 24 秒，合集 48 秒。其媒体／journal 验证属于旧交付，保留且不可覆盖，不能宣称它们展示 v100 的 Mio `289fd…`（a730 几何前身）、田中 c3e5 或 340bf/f6 runtime。

已准备 [最终录像新入口][new-videos]，本轮使用明确ready freeze完成九段新视频；555项媒体/输入身份检查全部通过，实际九个窗口均为macOS、NO_FOCUS=true、screen0，澪/和子走跑段native计数确实增长。入口显式指定已验收的v100七模型bank、完整游戏快照、引擎、runtime/native addon/proof并冻结哈希；不会重建旧22564或静默使用LATEST97。只在新的目录录制，静音、现有 screen0、no_focus、隔离存档。

实际九片的覆盖为：每人 solo 站 1s、走 7s、跑 7s、挥手／伸展／鞠躬各 3s；莲／澪／和子同场走跑各 8s；七人同场站立／挥手／伸展／鞠躬／舞蹈。合计覆盖本次七种评审动作，solo 不含舞蹈，七人同场不走跑，也没有资源另五条 look/tend/talk/cheer/reference。每个 section 有显式 reset，不能由片段拼接证明自然游戏中的无重置动作切换。九片均为720个实际drawn-frame/24秒，完整解码、BT.709四项标签、实际位移及native活动检查通过。单人168秒/多人48秒合集使用stream-copy并保留人物章节，分别再次完整解码。117张抽帧联系图及关键原尺寸已有限目视，不代替连续自然度人评。默认104份存档保持不变，录像临时工程已清理；[交付目录][final-videos]保留单片、合集和逐图回执。

[human]: ../../evidence/rig_fix_20261017/human-review-original.md
[ui]: ../../evidence/rig_review_20261018_v97/index.html
[guide]: ../../evidence/rig_review_20261018_v97/REVIEW_GUIDE.md
[state]: ../../evidence/rig_fix_20261017/LATEST_STATE_V99.json
[bank]: ../../evidence/rig_fix_20261017/integration-v100-candidate-models/manifest.json
[normalization]: ../../evidence/rig_fix_20261017/v99-model-measurements/completion-v100.json
[joints]: ../../evidence/rig_fix_20261017/structure/body-joints/manifest.json
[ren-shoulder]: ../../evidence/rig_fix_20261017/structure/body-v2/manifest.json
[hands]: ../../evidence/rig_fix_20261017/structure/unified-v10b-fingers-models/manifest.json
[gait]: ../../evidence/rig_fix_20261017/gait/FINAL_FINDINGS.md
[visual]: ../../evidence/rig_review_20261018_v97/readonly-root-visual-review.md
[aoi-tanaka]: ../../evidence/rig_review_20261018_v97/independent-aoi-tanaka-visual-review.md
[mio-v99]: ../../evidence/rig_fix_20261017/clothing/v99/native-visual-review.md
[mio-final]: ../../evidence/rig_fix_20261017/clothing/v99/monotone1000-midpoint-models/FINAL_REVIEW.md
[tanaka-run]: ../../evidence/rig_fix_20261017/tanaka-run-hand-v98/native-v4-qualification.md
[tanaka-stretch]: ../../evidence/rig_fix_20261017/tanaka-run-hand-v98/stretch-gravity-v3/native-review/README.md
[performance12]: ../../evidence/rig_fix_20261017/v100-combined-body-edge-performance/root-performance-qualification.json
[performance]: ../../evidence/rig_fix_20261017/v101-body-edge15-candidate/LIMITED-PILOT-AND-PERFORMANCE-QUALIFICATION.json
[expanded-domain]: ../../evidence/rig_fix_20261017/v101-expanded-domain-compare-first/integration-equivalence.json
[apron-supported]: ../../evidence/rig_fix_20261017/apron-domain-supported-label-v100-positive/results.json
[full-running]: ../../evidence/rig_fix_20261017/v101-final-full-tests-supported-probe/
[allowlist]: ../../evidence/rig_fix_20261017/gait/submission-review-20261018/README.md
[old-videos]: ../../evidence/character_videos_20261018/
[new-videos]: ../../evidence/character_videos_final_tools_20261018/README.md

[final-videos]: ../../evidence/character_videos_final_20261018/README.md
