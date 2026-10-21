# 澪 Cubism 模型

当前 v17：`Mio.cmo3` 为可编辑 Cubism 工程，`Mio.psd` 为 RGB/8、30 层导入素材。正式入口为 `native/mio-companion/Sources/MioApp/Resources/MioCubism/Mio.model3.json`。

模型通过本机 Cubism Editor 5.3.04 官方导出，目标 Cubism 4.0（MOC version 3），29 个有效参数、30 个 ArtMesh。保留 0.736 头部比例及用户认可的 v14 衣袖连接，保留原眼睛、中性脸轮廓，使用 3×3 小角度投影关键形，所有五官及下巴协同变化；小幅视线、眉部和眨眼使用原眼睛原画。眼口六层使用脸部 alpha 剪裁。只有 Idle、wave、think、talk 四组动作；伸懒腰已移除。

`Mio.physics3.json` 提供前后发两组物理。Idle 为 12 秒闭环，动作淡入淡出 0.35 秒；手型 ID 曲线单独关闭淡入淡出，避免多手叠影。实际复验包括官方 Core、Swift Metal 和 Pixi Cubism4 网页播放器，五种 exp3 表情为 neutral / happy / thinking / concerned / sleepy。详见 [v17 记录](../../../../docs/game-design/MIO_PERFORMANCE_20261021.md)。

在仓库根运行 `python3 art/tools/live2d/export_mio.py` 重建。工具先注册透明脸部件，再生成源关键形、PSD 和动作，调用本机 Editor 及 JDK 21 导出；`--editor` / `--jdk` 可指定安装目录。桥接依据 autoLive2d MIT 工具，来源、固定提交和许可证在 `art/tools/live2d/vendor/autolive2d/`。不下载软件、不修改许可证、不分发厂商二进制。

网页包由 `python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip` 生成，包含 model3 引用的十五个运行文件、可选 Pixi 事件适配 JS 与说明。保持 Mio 目录及相对路径，用 HTTP/HTTPS 提供文件。

Swift 从本机安装目录或 `MIO_CUBISM_CORE_PATH` 加载官方 Core，使用 Metal 绘制索引网格及正向/反向剪裁遮罩；normal / additive / multiplicative 管线已实现，本轮真实模型只验 normal。Swift 读取同包 motion3、exp3 和 physics3，保留思考指尖接触与安全过渡辅助。网页使用播放器自己的物理和动作过渡，未承诺头发与全身逐帧完全一致；不代表支持任意第三方模型。
