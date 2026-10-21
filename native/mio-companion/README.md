# 澪 · 晴町桌面来信

2026-10-22 v18：原素材拆成 53 个可编辑部件，增加独立眉角、笑眼、圆口和十根手指。现有 Clef 直接选择八种表情、三档强度与五种手势含义，不使用 embedding；肩旁握拳「加油」接入原窗口。来源、原画对照和验收见[语义表情记录](../../docs/game-design/MIO_EMOTION_20261022.md)。

2026-10-21 v16：按用户反馈恢复原眼睛原画、眼位和脸型，撤回 v15 新眼形及脸颊横移形变。保留动作节奏、头发跟随、网页 Idle 和手型防重影。见[脸部恢复记录](../../docs/game-design/MIO_FACE_RESTORE_20261021.md)。

2026-10-21：125 句角色台词接入当地时间、最近对话和系统事件，由 Clef 选句；时间仅参与决策，桌面气泡保持纯台词。见[上下文决策记录](../../docs/game-design/MIO_CONTEXT_DIALOGUE_20261021.md)。

2026-10-21：按用户要求移除伸懒腰，并将当前角色放回原「桌面来信」。统一入口及本轮验收见[接入记录](../../docs/game-design/MIO_MAIL_INTEGRATION_20261021.md)。

macOS 14+ 的 Swift / Metal 桌面角色。当前默认使用正式 Cubism `.model3.json` / `.moc3`，通过官方 Core 计算形变；可编辑工程和 53 层 PSD 在 `art/live2d/mio/cubism/`。当前 v18 保留认可的衣袖拼接、原眼睛及中性脸型，模型含 36 参数、五组标准 motion3、八种标准表情和 happy/thinking 兼容别名。眉眼、口腔、手指可独立编辑，小角度转头、眼口遮罩和物理仍由源模型提供。运行需要本机已安装的 Cubism Core（默认读取 Cubism 5.3 安装，也可设置 `MIO_CUBISM_CORE_PATH`），不将厂商库打包进应用。本轮肘部恢复见[修复记录](../../docs/game-design/MIO_ELBOW_RESTORE_20261021.md)，分段绑定来源见[前轮记录](../../docs/game-design/MIO_ARM_NATURALNESS_20261021.md)。角色已接入原来的「桌面来信」，统一使用 `open_mio_companion.command`；旧 `preview_mio_motion.command` 也转到同一入口。构建：

```bash
./native/mio-companion/tools/build_app.sh
open native/mio-companion/dist/Mio.app
```

需要 Xcode 或包含 Swift 的 Command Line Tools。构建不下载第三方依赖。`dist/Mio.app` 是当前机器的临时签名本地应用，未做 Developer ID 签名或公证。窗口关闭后可从菜单栏「澪」重新打开；菜单可暂停接收、切换角色鼠标穿透和退出。角色窗口可以拖动。桌面气泡只显示角色台词，连接与决策来源可在来信主窗口查看。

当前 Cubism 离线复验（不创建系统监控或网络客户端，不启动常驻窗口）：

```bash
dist/Mio.app/Contents/MacOS/MioCompanion --review-cubism /tmp/mio-cubism
dist/Mio.app/Contents/MacOS/MioCompanion --review-performance /tmp/mio-performance
node tools/verify_web_performance.mjs /tmp/mio-performance/performance.json
dist/Mio.app/Contents/MacOS/MioCompanion --review-emotion /tmp/mio-emotion
node tools/verify_web_emotion.mjs /tmp/mio-emotion/emotion-review.json
python3 tools/review_emotion.py /tmp/mio-emotion
dist/Mio.app/Contents/MacOS/MioCompanion --review-expression-matrix /tmp/mio-expression-matrix
```

正式 Cubism 模型的全动作复拍使用以下入口；默认走官方 Core，只有显式设置 `MIO_LEGACY_RIG=1` 才切换历史分层后端：

```bash
dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-joints
python3 tools/review_motion.py /tmp/mio-joints
```

从此目录执行，Python 工具需要 Pillow。输出 6514 张真实 Metal PNG、关节坐标、五动作十部位放大图、25 组各 4 秒切换表、自动周期/说话打断、长时钟及视线极值表。测量包含画幅、关节中心 alpha、邻帧腕位移；工具不自动判定自然度。另用 `python3 tools/check_joint_seams.py /tmp/mio-joints` 检查实际皮肤连接带暗线。

用户入口统一为仓库根目录 [`open_mio_companion.command`](../../open_mio_companion.command)，同时显示来信主窗口与桌面角色。独立预览仅保留为开发调试参数 `--preview-motion`。`--review-motion-window <目录>` 运行 33.5 秒的隔离可见窗口验收。

## 角色和渲染

当前待机为双臂自然垂下，点击「放下」可平滑退出当前动作；动作结束回到垂手，招手和托腮时空闲手臂也保持下垂。正式 Cubism 模型、源码与五组标准 motion3 同步，当前验收见[语义表情记录](../../docs/game-design/MIO_EMOTION_20261022.md)。

源素材在 [`art/live2d/mio/`](../../art/live2d/mio/)：透明原始部件图、28 层 RGB/8 PSD、源布局 `Mio.rig.json`，以及 `cubism/` 下当前可编辑 CMO3 和包含眉眼、口腔和手指部件的 53 层 PSD。PNG 部件随 Swift Package 打包。上身、腰裙、独立上下臂衣袖、公共前臂、五套常用左右手型、一套食指托腮手型与七个头部部件分别成层；手臂使用 24×64 网格，身体 20×64，当前 Cubism 头部 16×32（历史分层渲染器保持原网格）。Metal 对预乘纹理进行过滤和透明混合，手型使用独立实心源图与几何过渡。当前含呼吸、轻摆、头发运动、眨眼、说话口型和角色区域内的鼠标视线。默认 60 FPS，全程静音；离线全组复拍按 30 FPS 取样。

当前头部采用用户在叠图预览中选定的「再缩小 20%」版本：相对前一版为 0.8，相对最初布局为 `0.92 × 0.8 = 0.736`。头部及五官图层围绕 `(300, 268)` 的颈部基点一起缩放，头部整体比例保持原值；v16 直接使用原眼睛图和原注册位置。当前 v18 延续 `20261021-elbow-v14`，保留按用户照片制作的食指抵下巴和思考云，使用分段衣袖、公共前臂及实心手型过渡；源 rig、PSD、CMO3 和应用资源同步。

`Mio.rig.json` 仅用于作者源布局；正式入口是 `MioCubism/Mio.model3.json`，其 `.moc3` 由已安装的 Cubism Editor 官方导出器生成。早期自有分层版本和格式核对保留在[历史记录](../../docs/game-design/MIO_REST_AND_FORMAT_20261020.md)。

重建当前 Cubism 工程与运行包：

```bash
python3 art/tools/live2d/export_mio.py --work /tmp/mio-export
python3 art/tools/live2d/review_parts.py --output /tmp/mio-source-layers
python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip
```

以下两个命令只重建历史源布局，不能代替上面的正式 Cubism 导出：

```bash
swift native/mio-companion/tools/pack_assets.swift "$PWD"
swift native/mio-companion/tools/export_psd.swift "$PWD"
```

从仓库根目录执行。第一条只按已量定的区域拆图，保留生成的 alpha，清除低于 12/255 的透明量化尘点；不按背景颜色抠图。第二条将同一布局导出为有独立可见状态的 PSD。提示词与来源在 `art/manifests/prompts/live2d/mio-parts.txt` 和 `art/manifests/mio_companion_20261020.json`。

## 五官比例修订（2026-10-20）

按用户反馈对照原头像调整源布局：眼睛整体宽度由 152 降至 116，闭嘴宽度 44 降至 36，开嘴由 30×21 改为 22×12.6；眼睛上移 6，嘴部中心上移约 10。脸型、发型与源 PNG 保留，睁/闭眼、开/闭口分别共用位置基准。修改写在 `pack_assets.swift`，同步两个 rig 和 PSD，应用直接读取修订资源。

新增 `FaceProportionsTests` 防止眼睛撑满脸、嘴型拉长、嘴部过低和切换漂移；旧布局先运行，有 7 处断言失败。原生六种状态、前后对照和重建应用的证据在 `evidence/mio_face_proportions_20261020/`，比例是否自然仍以用户复评为准。

## 澪的桌面角色头身比例（2026-10-20）

按用户反馈，将头发、脸和五官七层以颈部为中心整体等比缩小 8%，保留上一轮五官相对比例及身体尺寸。源布局、两个 rig、PSD 与应用资源同步。新增头身比和颈部衔接回归，旧版出现 2 处失败；9 项 Swift 单元测试、六种原生状态及打包应用 480 帧复验通过。API 未改，本轮未重跑 HTTP 模拟。全身前后对照见 `evidence/mio_head_proportions_20261020/head-comparison.png`，证据见同目录 `verification.json`；自然度待用户复评。

## 颈部与手臂动画（2026-10-20）

肩包及肩带已从新身体素材中移除，身体和双臂分别成层。手臂有肩、肘、腕三个关节，颈部从下颌到衣领连续变形；头部视线平滑跟随，带轻微摆头、点头和延迟发梢摆动。保留上一轮缩小 8% 的头部及五官相对比例。

历史上使用过 52 秒固定动作循环，已由 v17 的事件驱动演出替代。当前窗口提供自动、放下、招手、思考、说话、加油；自动模式安静待机，来信时由 Clef 的语义决策触发手势。手动动作结束回到垂手，可点击自动恢复事件驱动。中途切换沿实际手部速度约束衔接。伸懒腰已从按钮、调度、源码动作和标准模型动作包删除。

素材使用内置 imagegen，提示词在 `art/manifests/prompts/live2d/mio-articulated-body.txt`，新增源图在 `art/live2d/mio/articulated/body-arms-atlas.png`；旧头部原始图保留。`--render-motion <目录>` 导出轻摆、招手、伸展、思考、说话各 7 秒，共 1050 帧 / 30 FPS。证据在 `evidence/mio_animation_20261020/`。

## 手臂折叠与方向修正（2026-10-20）

上一版以 Y 坐标混合肩部旋转，肩帽一半固定、一半转动，形成折角；肘部混合旋转前后的位置，较大弯曲时会压扁并翻转袖子。`ArmDeformationTests` 读取真实 PNG 的 alpha，只检查可见三角形，在旧版先抓到 9 处断言失败。

源绑定重新量定肩、肘、腕，记录 `bendSpans: [104, 30]`。肩帽跟上臂整体转动，肘腕沿连续圆弧保留横向宽度；伸展取消反向预摆和过大的折肘，思考改为朝胸前收手。画布为 750×1000、原点 [-75, 0]，两边各加 75 像素活动余量；界面同步扩宽，人物显示大小与各部位比例保持。

本轮 15 项本地测试通过，API 未变、HTTP 模拟未重跑。网格检查覆盖每侧五动作各 211 相位及 25 组切换各 13 相位，最小有向面积比 0.284、最大 1.717；画幅内留出至少 5 像素。最终应用导出 1050 帧 / 35 秒，无裁边；原生窗口 600 帧，四个动作切换、Inbox 和暂停通过。证据在 `evidence/mio_arm_binding_20261020/`，用户自然度复评仍待确认。

复拍联系表（包含起手、收手和前后对比）：

```bash
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --render-motion /tmp/mio-motion/frames
swift native/mio-companion/tools/preview_motion.swift /tmp/mio-motion
```

现成 Cubism 模型与 Swift 接入方案见[调研记录](../../docs/game-design/MIO_LIVE2D_RESEARCH_20261020.md)。当前正式接入范围与第三方播放器边界见[格式记录](../../docs/game-design/MIO_CUBISM_20261021.md)。

## 多手型、肩袖和腰部衔接（2026-10-20）

内置 imagegen 新增四张源部件图，位于 `art/live2d/mio/pose-parts/`，提示词为 `art/manifests/prompts/live2d/mio-{palms-out,hands-back,hands-inward,torso-overlaps}.txt`。此轮双手分别有放松、掌心向外、手背和内收侧掌四种源图；招手与说话选掌心，思考选侧掌。伸展手型后续改为下方独立握拳素材。以同一腕点注册，在预乘 alpha 空间混合，手型权重也参与中途动作切换。

肩部补片藏在衣服和上臂后面，肩根在上身后面，前臂袖子可以盖到胸前；上身和裙腰有 144 像素布局重叠，裙子上方绘制隐藏延伸，腰部变形在裙摆前减弱，脚部保持不动。PSD、源 rig 和运行资源共用布局，旧头部比例保留。

用户指出招手拇指朝外后，确认生成图列与画面左右的对应关系反了。源拆图明确记录角色自身左右手和使用图列，交换掌心、手背及侧掌对应图块；不镜像整条手臂。`PosePartsTests` 读取真实纹理的拇指像素区，旧映射四张图共 8 处断言失败，修正后通过。掌心朝前招手时，拇指指向头部。

本轮 18 项本地 XCTest 通过；API 未改，真实 HTTP 模拟未重跑。发布应用输出 1050 帧，7350 个肩部、前臂及腰部连接采样的最小 alpha 为 253/255，无裁边；原生窗口 304 个实际 Metal 帧，四种动作、Inbox 和暂停通过。当前证据在 `evidence/mio_pose_parts_20261020/verification.json`，包含拇指前后对照、动作联系表与静音预览。视觉自然度仍待用户复评；不是正式 Cubism 模型，也未验证任意三维手腕翻转。

```bash
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --render-motion /tmp/mio-motion/frames
python3 native/mio-companion/tools/check_pose_frames.py /tmp/mio-motion
swift native/mio-companion/tools/preview_motion.swift /tmp/mio-motion
```

## 握拳伸懒腰与内收手方向（历史记录，2026-10-20，动作已移除）

用户指出伸手手指方向错误，并确认伸懒腰应握拳。新增内置 imagegen 绘制的 `pose-parts/fists.png`，四指自然收拢，拇指压在弯曲手指外侧；左右手按实际源图列与腕点注册。原始图片与提示词 `art/manifests/prompts/live2d/mio-fists.txt` 均入库，增加两层后为 25 层 PSD。

伸懒腰前 0.35 秒收拢成拳，放下手臂后在最后 0.35 秒松开；手腕沿前臂，五套手型在预乘 alpha 空间连续混合，切换动作也一起过渡。招手和说话继续张掌。回归同时检查实际拇指像素随张掌动作的朝向、握拳的紧凑轮廓、收放时序与总权重；旧版缺失握拳的 7 处断言先失败。最终验收记录在 `evidence/mio_stretch_fist_20261020/verification.json`。

用户随后截图圈出的横在腰前的手属于思考动作。内收侧掌源图的解剖左右列与掌心/手背源图相反，旧代码统一交换图列使拇指朝下；现按每种源图分别注册。旧内收映射的 5 处断言先失败，改后 20 项本地测试通过；同时覆盖招手、思考、说话各 101 个张掌/内收保持相位。保持另外 21 个旧图层、22 张旧纹理及缩小后的头部比例。

## 食指抵下巴与思考云（2026-10-20）

用户最终选定照片中的姿势：食指斜向上轻抵下巴，拇指自然抬起，中指、无名指和小指收拢；头部轻歪，头顶出现思考云。此前开放虎口和四指松拳的候选未采用。参考照片只用于手势，保留在本地证据目录，角色继续使用澪的原形象。

内置 imagegen 生成 `art/live2d/mio/pose-parts/chin-index.png`，提示词在 `art/manifests/prompts/live2d/mio-chin-index.txt`。以源腕点 `(825,870)` 注册，独立标定实际食指像素 `(547,554)`；仅沿源前臂轴延伸隐藏部分，把源边缘藏在袖口内。食指与手掌独立置于脸和头发前，隐藏前臂仍在袖口后方；画面右侧新增上臂前袖片，前臂根部裁成圆弧，源上臂和前臂以重叠的独立图层转动，避免深折肘时压扁衣袖。PSD 与两个 rig 共 29 层，另一侧保持连续圆弧绑定。

运动源根据变形后的下巴解两段手臂角度，指尖随歪头和视线保持接触；肩部选择短转角。原生矢量思考云导出为独立透明图层，手到位后在 0.85–1.2 秒淡入，3.9–4.2 秒先于落臂淡出；切换动作时连同手型一起缓动。当前证据在 `evidence/mio_thinking_20261020/verification.json`。API 未改，真实 Clef 接入状态保持前述边界。

## Clef 决策

使用已有 `clef-omni` 的 `POST /v1/systemone` 协议；`state` 携带事件类型、粗粒度元数据、主动提交的文本、澪的角色设定和有界上下文。`questions` 分别选择兼容 mood、回应方式、本次台词，以及八种 expression、三档 intensity、五种 hand 含义。125 句中文涵盖六个时段、周末、工作、休息、安慰、庆祝、晴町故事及连续追问；回复由 Clef 从当前候选中选择，不额外接入自由文本聊天模型。Clef 无权调用 shell、操纵应用或发送消息。

时间只参与台词与决策，不在气泡新增时钟。采用 Mac 当地日期、星期、时区和本次陪伴分钟数；问时间时直接填入实测时钟。上下文限最近 30 分钟的 8 条对话、10 分钟的 8 条系统事件及最近 20 个已说台词 ID，全部只保留在当前进程内。发送系统元数据前按事件类型筛选字段，不发送窗口标题、文档内容或未主动提交的自由文本。简短追问沿用前一话题，候选耗尽后按较早使用的句子轮换，并排除上一句。

用户说“先别打扰”“我先忙”等会暂停主动说话 20 分钟，期间仍回应主动来信；“可以说话了”“继续聊”恢复主动陪伴。普通系统回应至少间隔 90 秒；会话活跃时每 15 分钟提供一次日常话题机会、时段变化提供问候机会，45 分钟休息提醒优先，是否开口由 Clef 决定。会话离开后不主动说话。

地址和模型可在窗口中设置，或通过 `MIO_CLEF_BASE_URL`、`MIO_CLEF_MODEL` 配置。可选密钥只读 `MIO_CLEF_API_KEY`，不写入设置或日志。缺省为 `http://127.0.0.1:8098` / `clef-omni`。主窗口区分「Clef 决策」与「离线规则」，桌面气泡只显示台词；请求超时 6 秒，失败后冷却 30 秒，离线仍使用相同上下文台词库。自动事件的回应分类置信度低于 0.55 时安静；主动消息使用合法候选回复，不因“问候/普通回应”之间的概率分散而被压掉。表情不确定时中性，台词概率只用于候选排序。所有响应仍检查模型 ID、枚举、当前台词 ID 及有限的 0–1 置信度。

用户随后明确要求不要跳过、直接尝试填写的地址。当前客户端直接请求配置的 HTTP(S) 域名、局域网或本机地址，保留系统正常的网络授权流程；不再因为地址可能触发权限而预先拦截。仍拒绝带账号、密码、查询参数的配置，并报告重定向状态而不自动转发事件或可选密钥。`https://clef.scgzyun.com/v1/systemone` 已使用真实生产客户端验证，服务返回 `clef-omni` 决策。最初连通记录在 `evidence/mio_clef_live_20261020/verification.json`，当前按上文区分自动事件与主动来信的置信度规则。

真实窗口连接验证使用 `--connection-test <证据目录>`：该模式不创建 `SystemMonitor`，不读取 Inbox，只发送固定的“你好，澪。这是一条连接验证消息。”，保存窗口与连接结果后退出。`--review-dialogue <目录>` 同样隔离系统监控，使用七条合成消息依次检查角色介绍、报时、工作、追问、安静、恢复和庆祝，保存主窗口与桌面气泡。常驻模式继续沿用用户授权的粗粒度事件范围；合成测试不代替长期日常使用的自然度验收。

## 无需授权的来信

| 来源 | 接收内容 |
| --- | --- |
| NSWorkspace | 普通应用启退/切换的 bundle ID；睡眠、唤醒、会话状态；设备挂载/卸载事件 |
| Network / IOKit / ProcessInfo | 在线状态、电源类型、温度等级 |
| 时间与陪伴 | 当地时段变化、15 分钟日常话题机会、45 分钟休息提醒；睡眠唤醒后重新计时 |
| 程序内输入框 | 用户主动输入的文字，最多 1000 字 |
| 专用 Inbox | 主动投递的 JSON 文本消息；处理后删除 |

不读取屏幕、窗口标题、键盘输入、剪贴板、其他应用的通知内容、浏览器历史、邮件或聊天数据库，不接入麦克风、摄像头、辅助功能、输入监控、日历、通讯录和全盘访问。不会弹出系统通知授权，也不创建虚拟显示器。主动消息仅被澪接收和回应，不会转发给联系人。

收件箱默认位于 `~/Library/Application Support/HarumachiMio/Inbox/`，窗口底部可打开。外部程序写一个临时文件，再原子改名成 `.json`：

```bash
inbox="$HOME/Library/Application Support/HarumachiMio/Inbox"
printf '%s\n' '{"text":"本次构建已经结束。"}' > "$inbox/message.part"
mv "$inbox/message.part" "$inbox/message.json"
```

只处理该目录中的普通 `.json` 文件，不跟随软链接，文件限制 8 KiB。坏消息丢弃；每轮最多处理 20 件。系统事件 15 秒去重，队列最多 12 件，超过 60 秒丢弃；普通回应冷却 90 秒，主动消息及手动重连不受此冷却影响。暂停会取消在途请求、清空待处理队列并注销监听，恢复后不会应用旧响应。事件列表仅在内存保留最近 80 条。

## 验证

```bash
cd native/mio-companion
swift test
# Postman CLI 1.73.0，本地运行，不需登录或发布共享资源：
./tools/test_simulation.sh
./tools/build_app.sh
dist/Mio.app/Contents/MacOS/MioCompanion --render-samples /tmp/mio-poses
dist/Mio.app/Contents/MacOS/MioCompanion --smoke-test /tmp/mio-smoke
MIO_CLEF_BASE_URL=https://clef.scgzyun.com dist/Mio.app/Contents/MacOS/MioCompanion --review-dialogue /tmp/mio-dialogue
# 仅向指定服务发送合成消息；真实模型与本地模拟分别验收：
MIO_TEST_CLEF_URL=https://clef.scgzyun.com swift test --filter DialogueTests.testLiveContextualSentenceSelection
```

86 个 XCTest（其中 2 个需 HTTP 模拟服务、2 个需显式指定真实 Clef；有官方 Core 的本地环境还会运行真实模型检查）覆盖关节动作、比例、手型、时区跨日、六时段、话题连续性、候选轮换、上下文边界、安静策略及生产 HTTP 客户端。Postman 模拟包含正常、低置信度、未知动作/台词、错模型、坏 JSON、500、HTML 网关、重定向及超时。未登录 Postman，未查询拥有方共享 mock；本地 mock 来自现有客户端/服务说明及消费契约，不能证明真实 Clef 模型的判断准确率。时间与上下文批次见 `evidence/mio_context_dialogue_20261021/` 和 [验收记录](../../docs/game-design/MIO_CONTEXT_DIALOGUE_20261021.md)。

原生 smoke 使用现有显示器，验证持续出帧、真实 Inbox 接收、暂停丢弃和恢复。PNG 导出只读取本程序自己的视图缓存与 Metal 目标，再合成本程序画面；它不是桌面截屏，也不读取其他窗口。记录位于 `evidence/mio_companion_20261020/`。本轮未改游戏资源、Godot 测试数、`builds/HareMachi.zip` 或 Web 发布。

设置 `MIO_TEST_APP` 为已构建应用的绝对可执行路径，再运行 `tools/test_simulation.sh`，会额外验证原生窗口接收 Postman 模拟的 Clef 响应并更新角色。该模拟验证与上方真实 Clef 服务连通验证分别记录。

肩部局部复拍：`MioCompanion --review-shoulders <目录>`，保存五动作各六相位；设置 `MIO_LEGACY_RIG=1` 得到源布局对照。此入口不启动监控或网络。最终应结合 `--review-motion` 全动作切换检查，不能仅凭连接中心 alpha 判断轮廓自然。
