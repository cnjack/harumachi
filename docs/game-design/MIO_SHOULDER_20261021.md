# 澪肩部连接修订（2026-10-21，v13）

后续用户反馈：肩位部分获认可，但独立下袖原画仍有圆盖感和分段痕迹，因此本记录不代表肘部视觉验收。最新恢复方案见 [v14 肘部恢复](MIO_ELBOW_RESTORE_20261021.md)。

用户指出 v12 的垂手肩头有台阶、招手肩片不跟随、伸展腋下有多余布瓣。此前关节中心和连接带数值通过，没有覆盖这些外轮廓问题，v12 的肩部视觉结论被用户否决。本轮以用户后续认可的招手连接为基准，分别修垂手肩高和伸展袖根重叠。

## 源素材和绑定

- 补画 `torso-armholes-20261021.png`，仅将上身左右外侧袖窿区域注册到原躯干。原颈口、蓝衬衫、扣子、口袋和下摆保留原像素。
- 补画 `upper-sleeves-clean-20261021.png`，替换旧上臂上的椭圆内轮廓；下臂衣袖、公共前臂、手型和头部原画继续使用原素材。上臂末端收进下臂覆盖区，避免深折肘时出现三角突出。
- 移除 `shoulder_left/right` 和 `sleeve_left/right` 四个重复层。源布局和源 PSD 为 28 层，Cubism PSD/模型为 30 ArtMesh（左右眼另行分层）。
- 垂手肩头上提 7 源像素；举高时肩头上提 20、向内移 12。招手抬起一侧的肩根位置保持用户认可版本。整条肩→肘→腕子层一起移动，避免各裁片独立挪动造成断开。
- 上臂仅在隐藏袖根做有限收整，最小局部面积比保持大于 0.20。最初压缩过强的候选被三角面回归拒绝，已减轻压缩并重新检查。
- 托腮求解使用肩头调整后的实际起点，按 Cubism 参数关键形状的插值求解；修复上提肩头后指尖离开下巴的回归。

`Mio.rig.json` 布局为 `20261021-shoulder-v13`，头部比例仍为 0.736。`MioBindings.java` 将肩部位移写入官方旋转变形器，上臂根部形变由 `MioCubismBake` 写入关键形状。重新保存 CMO3 并由本机 Cubism Editor 5.3.04 导出 MOC3，第三方播放不依赖 Swift 临时遮片。模型仍为 Cubism 4.0 目标（MOC version 3）、24 参数和五套标准 motion3；托腮动作参数随新起点重新烘焙。

生成提示词与来源见 `art/manifests/prompts/live2d/mio-shoulder-repair.txt`、`art/manifests/mio_shoulder_20261021.json` 和 `images_codex.json`。带针织纹理的中间草稿未直接用于模型。

## 复验入口

```bash
swift native/mio-companion/tools/pack_assets.swift "$PWD"
swift native/mio-companion/tools/export_psd.swift "$PWD"
python3 art/tools/live2d/export_mio.py --work /tmp/mio-shoulder-cubism
native/mio-companion/tools/build_app.sh
swift test --package-path native/mio-companion --disable-sandbox
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-shoulders /tmp/mio-shoulders
MIO_LEGACY_RIG=1 native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-shoulders /tmp/mio-source
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-cubism /tmp/mio-core
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-motion
python3 native/mio-companion/tools/review_motion.py /tmp/mio-motion
python3 native/mio-companion/tools/audit_arm_connections.py /tmp/mio-motion
python3 native/mio-companion/tools/check_joint_seams.py /tmp/mio-motion
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion-window /tmp/mio-window
```

本轮证据目录 `evidence/mio_shoulder_repair_20261021/`。`--review-shoulders` 用明确姿势输出五动作各六相位，适合源/正式模型一对一比对；完整验收仍需全动作与全部切换。测试入口均静音、不启动系统监控或网络，不创建虚拟显示器。

新增回归先在旧资源上捕捉到固定袖片/躯干边缘 6 处失败、抬肩袖根 122 处失败。最终 45 项 Swift 测试中 43 通过，2 项 HTTP 测试按本轮范围跳过。检查覆盖实际 MOC 骨段长度、肘腕连接、指尖下巴接触、源三角面形变、源袖宽、响应时间和手型。

最终逐动作视觉、全帧接缝、原生窗口及交付结果以同目录 `verification.json` 为准。未在独立第三方播放器中实测，不能把官方 Core 一致性检查称作所有播放器验收。

## 本轮结果

6514 帧覆盖五动作、全部 25 组切换、完整自动周期、说话打断、长时钟及视线极值。781680 个连接带像素最小 alpha 为 253/255，Core 最大肘腕接合误差 0.000137 像素；13028 条平坦皮肤带最大暗线亏损 1.797（阈值 4），无失败、无裁边。五份肩肘腕局部表和全部切换表已查看，源布局与正式 Core 五动作已一对一比对。

| 动作 | 本轮画面结论 |
| --- | --- |
| 放下 | 肩头与衣身肩线衔接，上臂不再露固定圆片；肘腕连接连续 |
| 招手 | 保留用户认可的抬臂侧肩位；收进肘部覆盖区的上臂末端不再突出小三角 |
| 伸懒腰 | 袖根内收后与衣身重叠，所查相位不再出现双层腋下布瓣 |
| 思考 | 重新求解上提后的肩部起点，指尖保持下巴接触；袖根未脱开 |
| 说话 | 所查展开和收回相位中肩、肘、袖口、腕部连续 |

现有显示器原生窗口实播 28.17 秒，1677 帧、平均 59.54 FPS（目标 60），六状态检查通过。托腮测得指尖误差 0.000031 像素、思考云不透明度 1；六张状态图和自身窗口图已查看。本轮未新建虚拟屏幕、未开启音频或网络。`shoulder-placement-comparison.png` 为三种肩位对照，`source-core-comparison.png` 为源/正式渲染对照，`window-contact.png` 为实播六状态。

正式运行目录已封装为同证据目录的 `Mio-Live2D-v13.zip` 并检查 CRC；源码和编辑工程继续保留在仓库内。自然度结论限于本轮检查的画面，不替代用户对最终视觉的评价。
