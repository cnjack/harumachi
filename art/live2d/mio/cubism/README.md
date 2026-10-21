# 澪 Cubism 模型

当前 v15：`Mio.cmo3` 为可编辑 Cubism 工程，`Mio.psd` 为 RGB/8、34 层导入素材。正式入口为 `native/mio-companion/Sources/MioApp/Resources/MioCubism/Mio.model3.json`。

模型通过本机 Cubism Editor 5.3.04 官方导出，目标 Cubism 4.0（MOC version 3），29 个有效参数、34 个 ArtMesh。保留 0.736 头部比例及用户认可的 v14 衣袖连接，新增转头网格关键形、独立眼球/眼睑/眉毛与嘴型连续形变。只有 Idle、wave、think、talk 四组动作；伸懒腰已移除。

`Mio.physics3.json` 提供前后发两组物理。Idle 为 12 秒闭环，动作淡入淡出 0.35 秒；手型 ID 曲线单独关闭淡入淡出，避免多手叠影。实际复验包括官方 Core、Swift Metal 和 Pixi Cubism4 网页播放器，详见 [v15 记录](../../../../docs/game-design/MIO_NATURAL_MOTION_20261021.md)。

在仓库根运行 `python3 art/tools/live2d/export_mio.py` 重建。工具先注册透明脸部件，再生成源关键形、PSD 和动作，调用本机 Editor 及 JDK 21 导出；`--editor` / `--jdk` 可指定安装目录。桥接依据 autoLive2d MIT 工具，来源、固定提交和许可证在 `art/tools/live2d/vendor/autolive2d/`。不下载软件、不修改许可证、不分发厂商二进制。

网页包由 `python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip` 生成，仅包含 model3 引用的十个运行文件与说明。保持 Mio 目录及相对路径，用 HTTP/HTTPS 提供文件。

Swift 从本机安装目录或 `MIO_CUBISM_CORE_PATH` 加载官方 Core，使用 Metal 绘制本模型普通混合/无遮罩网格；并不代表支持任意第三方模型。Swift 的头发弹簧与网页的标准 physics3 求解器不同，外观已分别复核，未承诺逐帧一致。
