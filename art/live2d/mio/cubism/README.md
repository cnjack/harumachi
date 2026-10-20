# 澪 Cubism 模型

`Mio.cmo3` 是可继续编辑的 Cubism 工程，`Mio.psd` 是 RGB/8、32 层导入素材。运行包位于 `native/mio-companion/Sources/MioApp/Resources/MioCubism/`，入口为 `Mio.model3.json`；导入第三方播放器时保留整个目录及相对路径。

模型由本机已安装的 Cubism Editor 5.3.04 导入、绑定并导出，目标格式 Cubism 4.0（Core MOC version 3）。保留原人物图和 0.736 头部比例，有 22 个参数、32 个 ArtMesh、肩/头/躯干旋转变形器及独立透明度控制。五套标准 motion3：放下、招手、伸懒腰、思考、说话。没有复制或分发 Editor/Core 二进制。

复现：在仓库根运行 `python3 art/tools/live2d/export_mio.py`。工具使用已安装的 Editor 5.3.04 和 JDK 21，不下载软件、不修改许可证、不调用图形界面。可用 `--editor` / `--jdk` 指定安装目录。桥接依据 autoLive2d MIT 工具，来源、固定提交和许可证在 `art/tools/live2d/vendor/autolive2d/`；5.3 适配和澪的源绑定在相邻文件。

Swift 默认使用官方 Core 计算变形、Metal 绘制。Core 从本机 Cubism 安装加载，或通过 `MIO_CUBISM_CORE_PATH` 指定单独取得的官方 Native Core dylib；运行包本身不含 Core。当前 Swift 渲染器支持本模型使用的普通混合、无裁剪网格，不表示支持任意带遮罩/高级混合的第三方模型。

已用官方 Core 6.0.513 验证文件一致性、22 个实际有效参数、五动作和 25 组切换。验收记录见 `docs/game-design/MIO_CUBISM_20261021.md`。第三方播放器、Editor 可见窗口和最终自然度复评尚未完成；格式转换沿用既有手臂素材，不能替代进一步绘制与绑模修整。
