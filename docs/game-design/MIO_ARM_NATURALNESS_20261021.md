# 澪手臂素材、Cubism 关节与动作自然度修复（2026-10-21，v11）

本轮修复对象是正式 Cubism 模型的肩、肘、腕与手型过渡。原 v10 用长弧连续扭曲整条衣袖，招手的上臂弯成软管，思考肘部绕转过大，初次格式导出没有解决这些源问题。

## 源素材与绑定

内置 imagegen 补画 `art/live2d/mio/articulated/arm-segments-20261021.png`，四块分别为左右上臂、左右前臂衣袖与裸露前臂，带可藏入对侧部件的肘部重叠。提示词、参考图和模式记录在 `art/manifests/prompts/live2d/mio-arm-segments-20261021.txt` 与 `art/manifests/images_codex.json`。注册、分层和隐藏边缘裁切由 `pack_assets.swift` 完成；保留原脸、发型、五官、上身、裙子和 0.736 头部比例。

源 rig 更新为 `20261021-articulated-v11`、32 层；Cubism 导入时独立左右眼，为 34 个 ArtMesh。CMO3、两份源 PSD、原型资源和正式运行资源均同步。运行模型仍是标准 Cubism 4.0 目标的 MOC3，24 个参数，增加左右收指程度参数；不是靠 Swift 拼接覆盖图片来补源模型缺陷。

- Body → Shoulder → Elbow → Wrist 形成真实 Cubism 旋转变形器层级。上臂、前臂保持骨段长度，手掌独立绕腕转动，几何关键形由 2494 减为 406。移除长弧扭曲，深折肘不再绕完整一圈。
- 思考使用两骨段解析求解，将食指抵住实际下巴；右肘参数上限收至 3.1 rad。反向折肘动作切换仍先经过垂手，沿用实测路径速度控制。
- 肩部隐藏轮廓收整，限制多余布片露出；前臂改为盖住上臂，修复托腮时前臂被上臂遮住的细条感。下臂、公共裸前臂和手掌分别重叠，实际皮肤拼接位改为腕前 46 像素，避开有意绘制的罗纹袖口。
- 收指从连续权重计算，不再在微小握拳权重出现时突变掌长。手腕附近 16 像素固定，压缩从掌部开始并平滑积分；手型交换仍只显示一套源图。源算法与 MOC 关键形一致，实际 Core 顶点回归检查每个动作的每一帧。
- 头部平移写入头部变形器，保留与旋转的正确先后关系，覆盖视线和伸展的完整竖向位移，避免手指目标与实际下巴因参数裁切分离。原始绘图与头部尺寸未变。

## 逐项复核

| 动作 | 肩部 | 肘部 | 袖口、手腕和手型 |
| --- | --- | --- | --- |
| 放下 | 根部持续藏入衣身，呼吸时覆盖稳定 | 上下臂保持直段，轻微自然屈肘 | 裸前臂与放松手持续连接，无横向切口 |
| 招手 | 向外抬起，另一臂保持垂下 | 明确的屈肘转向，消除长弧软管形 | 张掌拇指朝头侧，腕部小幅摆动，无换手重影 |
| 伸懒腰 | 双肩向外上方展开，肩根无露底 | 分段抬臂，不拉长或压扁骨段 | 抬起前握拳，落臂后松开；左右袖口与手腕连接一致 |
| 思考 | 头部歪向手侧，上臂留在身体旁 | 肘在肩下，前臂位于上臂前方 | 食指抵下巴后出现思考云，腕部不再被衣袖层遮成细条 |
| 说话 | 小幅摆动，空闲臂下垂 | 前臂从肘部展开，转向连续 | 自然张掌，伸出和收回时腕点固定 |
| 自动与中断 | 全周期和全部 25 组双向切换逐项检查 | 反向深屈肘先落臂再抬起 | 收指、变手型与运动解耦，不产生腕点跳变 |

视觉复核使用五份 `joints-*.png`、五份 `switch-to-*.png`，以及自动周期、自动说话、视线极值和长时钟切换联系表；包括起手、保持和收手。上述结果是所测动作与图像的验收，不把中心点覆盖或轮廓相似度单独当作自然度证明。

## 回归与实际运行

证据为 `evidence/mio_arm_naturalness_20261021/`：

- 新骨段回归在旧版先出现 823 处失败；旧收指阈值被新增掌长跳变测试检出。中间版本的实际 Core 检查还检出最多约 1.05 像素腕点漂移，已修复；原始失败日志、上下文图和报告保留。
- 39 项本地 XCTest：37 通过，2 项既有 HTTP 测试按本轮离线范围跳过。覆盖源骨段长度/直线性、不绕整圈、手腕固定区、收指连续性、实际 MOC 每帧骨段和接合、下巴接触、标准动作文件及损坏模型拒绝。
- 最终真实 Metal 6514 帧：五动作各 210 帧；25 组各 121 帧切换；两种长时钟下四组切换；完整自动周期及环回；25 个视线极值；三组自动说话打断。所有数量来自新复拍，未借用旧版通过记录。
- 真实 MOC 顶点测得肘、袖口和手腕最大接合误差 0.000137 像素，阈值 0.15。肩、肘、袖口、腕的 781680 个内部连接带像素最小 alpha 253/255，阈值 250，无失败。65140 个中心样本亦无露底、无裁边。
- 实际源皮肤拼接带 12936 处，最大暗线亮度亏损 2.447，阈值 4，无失败；有意绘制的袖口轮廓不当作皮肤接缝。
- 已解锁的现有屏幕原生窗口六状态全部通过：839 个真实 Metal 帧，平均 29.78 FPS。离屏截图不替代这项窗口验收。
- 35 秒、1050 帧、750×1000、30 FPS 的五动作静音预览 `mio-actions.mp4` 完整解码通过。前后对比、正式模型包、逐项报告与摘要在同一证据目录。

测试没有构造系统监控、Inbox 或网络客户端，没有声音或虚拟显示器。本轮不修改 Clef/API、Godot 工程或桌面/Web 游戏交付。第三方播放器范围沿用首次格式接入记录；本轮验收运行的是官方 Core 6.0.513 与 Swift/Metal。

## 复现

```bash
CLANG_MODULE_CACHE_PATH=/tmp/mio-clang-cache swift native/mio-companion/tools/pack_assets.swift "$PWD"
CLANG_MODULE_CACHE_PATH=/tmp/mio-clang-cache swift native/mio-companion/tools/export_psd.swift "$PWD"
python3 art/tools/live2d/export_mio.py
./native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-arm-review
python3 native/mio-companion/tools/review_motion.py /tmp/mio-arm-review
python3 native/mio-companion/tools/audit_arm_connections.py /tmp/mio-arm-review
python3 native/mio-companion/tools/check_joint_seams.py /tmp/mio-arm-review
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion-window /tmp/mio-arm-window
swift test --package-path native/mio-companion
python3 tools/check_project.py
```
