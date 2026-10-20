# 澪 · 晴町桌面来信

macOS 14+ 的 Swift / Metal 桌面角色原型，沿用游戏女主角澪的棕色短发、黄色发夹、奶油色开衫、蓝衬衣和深蓝百褶裙。双击仓库根目录的 `open_mio_companion.command`，或运行：

```bash
./native/mio-companion/tools/build_app.sh
open native/mio-companion/dist/Mio.app
```

需要 Xcode 或包含 Swift 的 Command Line Tools。构建不下载第三方依赖。`dist/Mio.app` 是当前机器的临时签名本地应用，未做 Developer ID 签名或公证。窗口关闭后可从菜单栏「澪」重新打开；菜单可暂停接收、切换角色鼠标穿透和退出。角色窗口可以拖动。

## 角色和渲染

源素材在 [`art/live2d/mio/`](../../art/live2d/mio/)：透明原始部件图、十层 RGB/8 PSD、独立格式的 `Mio.rig.json`。PNG 部件随 Swift Package 打包。身体、双臂、后发、脸、前发、睁眼/闭眼与闭嘴/开嘴分别渲染；手臂使用 24×64 网格，身体 20×64，头部 20×24，Metal 完成纹理采样和透明混合。当前含呼吸、轻摆、头发运动、眨眼、说话口型和角色区域内的鼠标视线。默认 30 FPS，全程静音。

这是自有分层动画格式，**不是 Cubism `.moc3` 模型，也不能加载 `.model3.json`**。PSD 已通过系统 ImageIO 合成图解码检查，可作为 Cubism 后续制作的来源；尚未在 Cubism Editor 内导入验收。本机未找到 Editor/SDK，本轮未下载或接受它们的许可，也未导出 `.cmo3` / `.moc3`。官方 Core 负责计算 Editor 模型的顶点，不能把分层 JSON 改名当成官方模型，见 [Cubism Core 文档](https://docs.live2d.com/en/cubism-sdk-manual/cubism-core-api-reference/)。

重建资源：

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

窗口动作按钮提供自动、轻摆、招手、伸懒腰、思考、说话。自动状态约 52 秒穿插一次完整动作组，来信回应期间使用说话手势；手动动作结束后回到轻摆，可点击自动恢复循环。肩肘联动先收臂再抬手，避免过渡时出画；中途切换用 0.4 秒缓动衔接当前姿势。只控制角色自身动画。

素材使用内置 imagegen，提示词在 `art/manifests/prompts/live2d/mio-articulated-body.txt`，新增源图在 `art/live2d/mio/articulated/body-arms-atlas.png`；旧头部原始图保留。`--render-motion <目录>` 导出轻摆、招手、伸展、思考、说话各 7 秒，共 1050 帧 / 30 FPS。证据在 `evidence/mio_animation_20261020/`。

## Clef 决策

使用已有 `clef-omni` 的 `POST /v1/systemone` 协议；`state` 携带事件类型、粗粒度元数据和主动提交的文本，`questions` 要求选择表情与预设回应。没有额外聊天模型，回复来自程序内的中文短句。Clef 无权调用 shell、操纵应用或发送消息。

地址和模型可在窗口中设置，或通过 `MIO_CLEF_BASE_URL`、`MIO_CLEF_MODEL` 配置。可选密钥只读 `MIO_CLEF_API_KEY`，不写入设置或日志。缺省为 `http://127.0.0.1:8098` / `clef-omni`。窗口明确区分「Clef 决策」与「离线规则」；请求超时 6 秒，失败后冷却 30 秒，低置信度保持安静。

**本轮按用户要求跳过所有可能触发授权的网络地址，只允许字面回环 IP `127.0.0.1` / `::1`，并拒绝 HTTP 重定向。** 旧服务 `192.168.10.202:8098` 在本轮命令行连通性检查中超时，应用不会自动连接它。macOS 15 起的局域网连接可能要求 Local Network 授权，见 [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)。没有启动转发器、隧道或修改系统权限；真实模型接入仍需要一个可用的本机 Clef 服务入口。

## 无需授权的来信

| 来源 | 接收内容 |
| --- | --- |
| NSWorkspace | 普通应用启退/切换的 bundle ID；睡眠、唤醒、会话状态；设备挂载/卸载事件 |
| Network / IOKit / ProcessInfo | 在线状态、电源类型、温度等级 |
| 工作计时 | 连续运行 45 分钟的休息提醒；睡眠唤醒后重新计时 |
| 程序内输入框 | 用户主动输入的文字，最多 1000 字 |
| 专用 Inbox | 主动投递的 JSON 文本消息；处理后删除 |

不读取屏幕、窗口标题、键盘输入、剪贴板、其他应用的通知内容、浏览器历史、邮件或聊天数据库，不接入麦克风、摄像头、辅助功能、输入监控、日历、通讯录和全盘访问。不会弹出系统通知授权，也不创建虚拟显示器。主动消息仅被澪接收和回应，不会转发给联系人。

收件箱默认位于 `~/Library/Application Support/HarumachiMio/Inbox/`，窗口底部可打开。外部程序写一个临时文件，再原子改名成 `.json`：

```bash
inbox="$HOME/Library/Application Support/HarumachiMio/Inbox"
printf '%s\n' '{"text":"本次构建已经结束。"}' > "$inbox/message.part"
mv "$inbox/message.part" "$inbox/message.json"
```

只处理该目录中的普通 `.json` 文件，不跟随软链接，文件限制 8 KiB。坏消息丢弃；每轮最多处理 20 件。系统事件 15 秒去重，队列最多 12 件，超过 60 秒丢弃；普通回应冷却 20 秒。暂停会取消在途请求、清空待处理队列并注销监听，恢复后不会应用旧响应。事件列表仅在内存保留最近 80 条。

## 验证

```bash
cd native/mio-companion
swift test
# Postman CLI 1.73.0，本地运行，不需登录或发布共享资源：
./tools/test_simulation.sh
./tools/build_app.sh
dist/Mio.app/Contents/MacOS/MioCompanion --render-samples /tmp/mio-poses
dist/Mio.app/Contents/MacOS/MioCompanion --smoke-test /tmp/mio-smoke
```

十四个 XCTest 覆盖关节动作、颈部过渡、头身及五官比例、约束、权限地址、过期/去重和生产 HTTP 客户端；Postman 模拟包含正常、低置信度、未知动作、错模型、坏 JSON、500、HTML 网关、重定向及超时。未登录 Postman，未查询拥有方共享 mock；本地 mock 来自现有客户端/服务说明及本轮消费契约，不能证明真实 Clef 模型的判断准确率。

原生 smoke 使用现有显示器，验证持续出帧、真实 Inbox 接收、暂停丢弃和恢复。PNG 导出只读取本程序自己的视图缓存与 Metal 目标，再合成本程序画面；它不是桌面截屏，也不读取其他窗口。记录位于 `evidence/mio_companion_20261020/`。本轮未改游戏资源、Godot 测试数、`builds/HareMachi.zip` 或 Web 发布。

设置 `MIO_TEST_APP` 为已构建应用的绝对可执行路径，再运行 `tools/test_simulation.sh`，会额外验证原生窗口接收 Postman 模拟的 Clef 响应并更新角色。该验证仍不代表真实模型上线。
