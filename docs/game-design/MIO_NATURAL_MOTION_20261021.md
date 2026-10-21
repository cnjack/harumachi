# 澪 v15：脸部绑定、动作节奏与网页播放（2026-10-21）

用户后续指出本版眼睛和脸型异常，面部方案已在 [v16](MIO_FACE_RESTORE_20261021.md) 撤回。以下保留当轮实现和验收历史，不代表当前面部或用户认可。

本轮落实 Haru 对照中发现的差距：旧模型的转头主要是整片平移，五官以图片切换为主，动作节拍重复，网页播放器默认查找 `Idle` 而模型只提供 `idle`。改动进入可编辑源工程、正式 MOC3 和四组 motion3，原「桌面来信」使用同一新版模型。

## 源素材与绑定

- 使用内置 imagegen，参考原眼睛素材补画透明眼白/睫毛、虹膜、眉毛和闭眼线。源图为 `art/live2d/mio/face/components-20261021.png`；[完整提示词](../../art/manifests/prompts/live2d/mio-face-components-v15.txt)，来源记录在 `art/manifests/images_codex.json`。`art/tools/live2d/prepare_face.swift` 保留 alpha 分割、注册八个独立部件，写出 `Face.parts.json`。
- `FaceRig.swift` 在导出时制作 AngleX/Y 的 3×3 网格关键形，横向转头改变脸部轮廓、五官间距和前后发的位置。眼球、眼睑、左右眉毛和嘴型独立绑定；眼睑连续收合。思考的下巴锚点保留，避免破坏原食指接触。
- 当前 29 参数、34 ArtMesh、1467 个关键形；34 层 PSD、CMO3、MOC3、图集同步。头部整体比例仍为 0.736；保留用户认可的 v14 肘部、肩位和手型源图。没有恢复伸懒腰，也未新增抱臂等整套手臂替换姿势。

## 动作和运行

Idle 改为 12 秒，有看向两侧、停留、回正和非等间隔眨眼，循环末端使用 1.5 秒 Hermite 衔接。招手和说话改成带停顿、幅度变化和肩/肘/腕先后跟随的节奏。四个动作仍是放下、招手、思考、说话。

网页导出使用标准 `Idle` 组和 `Mio.physics3.json`。前后发分别配置物理跟随，动作淡入淡出 0.35 秒。实际网页发现手型也被淡入，导致两种手掌短暂叠影；最终 `ParamHandL/R` 曲线单独设置 FadeInTime/FadeOutTime 为 0，其余曲线保留淡入。新增回归在修复前出现 16 处失败。

Swift 仍由官方 Core 计算网格、Metal 绘制，新增有阻尼的头发跟随。Swift 弹簧和网页 physics3 是两套求解器，共用输入/输出参数和源形变，外观分别检查，不承诺逐帧相同。29 参数有效不等于专业级大角度绑模；当前是小幅 2.5D 转头，没有侧面补画和完整透视手臂。

## 验收

证据目录：`evidence/mio_natural_motion_20261021/`，总索引 `verification.json`。

| 范围 | 结果 |
| --- | --- |
| 本地 Swift | 62 项：59 通过，3 项网络夹具测试跳过；本机官方 Core 回归实际运行 |
| 回归能否捕捉旧问题 | 原模型的新自然度检查 15 处失败；手型淡入修复前新增检查 16 处失败 |
| 官方导出 | consistency=true，MOC version 3，29 参数、34 ArtMesh |
| 最终 Core / Metal | 2060 帧，29 参数均有效，37 张静态/视线/眨眼对照图 |
| 全动作离屏 | 5210 帧、4 动作与 16 组切换；52100 个关节中心样本最低 alpha 253，无裁边 |
| 皮肤接缝 | 10420 条连接带，最大暗线缺口 1.4，低于阈值 4，无失败 |
| 现有显示器 | 28.16 秒 / 1678 帧 / 59.59 FPS，五状态检查通过；静音、无虚拟显示器 |
| 网页真实播放 | Pixi 6.5.10 + pixi-live2d-display 0.4.0 Cubism4，自动待机和物理正常；8 步切换完成，手型混合帧 0，控制台无错误/警告 |
| 网页包 | model3 引用的 10 个文件齐全，ZIP CRC、逐字节回读与摘要核对通过；不含厂商 Core |

逐项目视检查了四个动作的肩、肘、袖口、腕、颈和腰部放大表、四页覆盖 16 组切换的表、视线极值、长时钟和说话打断，以及网页浅/深底实播截图。未发现这些样本中的露底接缝、镜像手掌或叠影；这不代表用户已认可自然度。

原应用已通过 CLI 重启，入口仍为 `open_mio_companion.command`。重启时电脑再次锁屏，已确认新进程持续运行，但重启后的常驻主窗口未目视复核。上述 59.59 FPS 是本轮锁屏前可见窗口的结果；不能拿来声称锁屏后仍在持续画帧。本轮没有修改 Clef 的上下文、台词和网络协议，未重复真实 Clef 对话验收。

## 复现和交付

从仓库根执行：

```bash
python3 art/tools/live2d/export_mio.py
./native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-cubism /tmp/mio-core
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-motion
python3 native/mio-companion/tools/review_motion.py /tmp/mio-motion
python3 native/mio-companion/tools/check_joint_seams.py /tmp/mio-motion
python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip
```

网页复验页在 `native/mio-companion/tools/web_review.html`。将它作为 index.html，与模型目录 `Mio/` 一起通过本机 HTTP 服务提供。它只作开发验收，不是另一个桌面应用；外部运行库未复制进交付包。

当前交付包：`evidence/mio_natural_motion_20261021/Mio-live2d-web.zip`，入口 `Mio/Mio.model3.json`。四动作组名大小写是 `Idle` / `wave` / `think` / `talk`。
