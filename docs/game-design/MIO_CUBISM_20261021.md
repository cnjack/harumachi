# 澪正式 Cubism 格式与 Swift Core 接入（2026-10-21）

本页保留首次正式格式导出的历史状态；当前 v11 的源素材、24 参数、34 ArtMesh 和可见窗口验收见[后续手臂修复](MIO_ARM_NATURALNESS_20261021.md)。

用户要求正式 Live2D 兼容格式，随后明确要求在锁屏情况下用 CLI 完成。此前的 `harumachi-layer-rig` 保留为源布局和对照工具，不能作为 Cubism 运行模型。新默认后端读取真正的 `.model3.json` / `.moc3`。

## 交付与生成

- `art/live2d/mio/cubism/Mio.cmo3`：Cubism 保存的可编辑工程。
- 同目录 `Mio.psd`：32 层 RGB/8 PSD，独立左右眼。原 PSD 缺少 Cubism 导入器需要的分辨率资源；新 PSD 写入标准 72 DPI Image Resource 1005，不修改原 PNG 或原 rig。
- `native/mio-companion/Sources/MioApp/Resources/MioCubism/`：标准 model3、MOC3、cdi3、两张 4096 图集及五个 motion3。保留原 0.736 头部比例。
- 22 参数控制头/身体、肩肘腕、呼吸、发梢、左右眼、口型、五/六套手型、思考云和伸展。32 个 ArtMesh，2494 个几何关键形。手型 motion3 使用 stepped 段，避免插值经过其他手型。

`python3 art/tools/live2d/export_mio.py` 完成源关键形生成、PSD 导入、参数与变形器绑定、图集生成、cmo3 保存和官方 MOC 导出。使用本机 Cubism Editor 5.3.04 的现有库及 JDK 21，固定导出 Cubism 4.0（MOC version 3）。未复制 Editor/Core 库、未接受新协议、未修改许可证。工具在独立临时目录执行，不在仓库生成 Editor 用户配置。

Java 桥接源来自 [autoLive2d](https://github.com/KonshinHaoshin/autoLive2d)，MIT，固定版本与许可随工具保存；本轮添加 Cubism 5.3 签名适配及澪的原创绑定。没有手写 MOC 二进制或伪装文件后缀。文件类型参见 [Live2D 官方导出说明](https://docs.live2d.com/en/cubism-editor-manual/export-moc3-motion3-files/)；动作结构按 [官方 motion3 规格](https://github.com/Live2D/CubismSpecs/blob/master/FileFormats/motion3.json.md)。

## Swift 渲染

`CubismModel.swift` 动态加载官方 Core C ABI，64 字节对齐分配 MOC/Model 内存，先检查文件一致性，再创建实例和更新参数。读取实际 Core 输出的顶点、UV、索引、图集序号、绘制顺序和透明度；`CubismDrawing.swift` 使用 Swift/Metal 索引三角形绘制，预乘 alpha 过滤与混合。SDK 边界参见 [官方 Core 文档](https://docs.live2d.com/en/cubism-sdk-manual/cubism-core-api-reference/)。

默认 Core 为已安装 Cubism 的 native 库，可用 `MIO_CUBISM_CORE_PATH` 指定自行取得的官方 Native Core。安装库不进入 Git 或 app；不承诺 app 单独拷贝到另一台 Mac 后能在无 Core 情况运行。模型包本身采用标准相对路径，可以独立交给支持 Cubism 4.0 MOC 的宿主。

当前后端覆盖本模型普通混合、无遮罩的绘制需求；对不支持的遮罩/混合拒绝加载。它不是完整 Framework 的全部功能实现，也未通过所有第三方播放器验收。Swift 动作调度沿用现有平滑过渡逻辑，只输出参数值；形变与透明度在 MOC 中计算。离线入口 `--review-cubism <目录>` 位于 AppDelegate 之前，不构造监控、收件箱或网络客户端。未知 CLI 参数直接退出，防止误入常驻模式。

## 验证与边界

证据目录 `evidence/mio_cubism_20261021/`：

- 官方导出一致性检查通过，MOC version 3，22 参数、32 drawables。
- 每个参数分别取最小/最大值，实际顶点或透明度改变；初版发现参数树未注册、源拓扑仍为四顶点及 Part 透明度不传递，均修复后重导出。回归会拒绝无效参数及索引越界。
- Core 3090 帧覆盖五动作及全部 25 组切换；整数手型每侧恰有一套可见。21 张 Cubism 离屏 Metal 图及 5 张原渲染对照，检查入手、保持、收手；不把 Core 数值帧计为真实 GPU 帧。
- 36 项 XCTest 中 34 项通过、2 项网络测试跳过；项目检查 7945 项通过。
- 五个保持姿势与源渲染的轮廓交并比为 99.12%–99.46%，平均 RGB 差异为 0.38%–0.48%；逐图比对未发现由格式转换新增的显著位移。相似度不代表自然度通过。
- 单元测试验证旧 rig 不能当 model3、路径和缺图拒绝、标准动作段与计数、官方 Core 加载和损坏文件拒绝；修复失败初始化的重复释放问题。两个已有 HTTP 测试需要独立模拟，本轮未重跑。
- `comparison.png` / `poses.png` 为视觉比对表；仍沿用现有绘图，格式转换没有解决用户此前对手臂自然度的全部反馈。肩肘的褶皱和大角度立体转面仍需更好的源素材及人工调整。
- Mac 锁屏，未做 Editor/原生可见窗口/第三方播放器验收。本轮静音、无虚拟显示器；未进行 Clef 或常驻系统监控测试；游戏桌面与 Web 交付不变。

复验命令：

```bash
./native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-cubism /tmp/mio-cubism-review
swift test --package-path native/mio-companion
python3 tools/check_project.py
```
