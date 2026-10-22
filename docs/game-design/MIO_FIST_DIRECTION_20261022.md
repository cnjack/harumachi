# 澪加油手型方向修复（2026-10-22，v18.2）

用户指出加油手反了。旧动作复用了原伸展用的掌面握拳：拇指横跨画面中央、掌纹朝观众，放到肩旁后像把前臂翻向外侧。本轮补画同一双手的手背视图，让掌心朝角色、四指握拳，拇指只在外侧留下短轮廓。

## 源素材与绑定

- 使用 Codex 内置 `image_gen` 编辑参考图，直接输出透明 PNG；未按底色抠图。
- 原参考：`art/live2d/mio/pose-parts/fists.png`，保留原件。
- 新素材：`art/live2d/mio/pose-parts/fists-back-20261022.png`。
- 提示词：`art/manifests/prompts/live2d/mio-fists-back-20261022.txt`。
- 记录与摘要：`art/manifests/mio_fist_direction_20261022.json`、`art/manifests/images_codex.json`。

左右手列序不变：源图左列是角色左手（画面右臂），右列是角色右手（画面左臂）。腕点仍为 `(426,565)` / `(1110,565)`，缩放仍为 `(0.17,0.16)`。修改的是手掌朝向的原画，而非镜像整个手臂。

重新运行源贴图注册、55 层 PSD 导出和本机官方 Cubism Editor CLI 导出；源 rig、PSD、CMO3 与正式图集同步。模型仍为 38 参数、55 ArtMesh、Cubism 4.0 导出目标（MOC version 3）。与前版逐文件比较，正式运行资源只有 `texture_00.png` 和 `texture_01.png` 改变；MOC3、绑定、动作、表情、物理和第三张图集摘要一致。原眼睛、脸型、0.736 头部比例和认可的衣袖连接保持原版本。

## 验证

证据目录：`evidence/mio_fist_direction_20261022/`。

| 检查 | 结果 |
| --- | --- |
| 原纹理负例 | 新增像素回归在原版双拳出现 4 处失败：掌纹区域及错误侧拇指轮廓；原版掌纹占比约 9.40% / 9.15% |
| 修复后回归 | 双拳中央掌纹检测为 0，实际纹理上的拇指侧别通过；实际 MOC 抬拳阶段的径向方向通过 |
| Swift | 89 项中 85 通过、4 项可选网络测试跳过、0 失败；本轮不重复请求未修改的 Clef 接口 |
| 全动作 | 6,514 张真实 Metal 帧，含五动作、全部 25 组切换、长时钟、视线极值和自动说话 |
| 肩肘腕连接 | 781,680 个连接带像素，最小 alpha 254/255，最大锚点误差 0.000137 像素，无失败 |
| 腕部暗线 | 13,028 组平坦皮肤带，无超阈暗线；最大差值 1.367，阈值 4 |
| 可见窗口 | 解锁后的现有显示器，33.63 秒 / 2,002 帧，平均 59.53 FPS；自动、放下、招手、思考、说话、加油六状态通过 |

已目视复查加油的起手、保持、回落及五种切入状态；手背和袖口连续，未见新露底。`fist-before-after.png` 比较相同 1.50 秒相位的实际渲染手腕区域。数值检查只覆盖列明的连接与轮廓条件，不代替用户对动作外观的认可。

原「澪 · 晴町桌面来信」已重新构建并重启，应用内全部模型文件与源运行包逐字节一致；主窗口点击加油后显示新手型，渲染计数持续增加。此次可见验收补齐 v18 最终 55 部件版此前因锁屏未完成的窗口/FPS 检查。测试进程静音、无系统事件监控、无网络请求，未创建虚拟显示器。

## 网页交付

`evidence/mio_fist_direction_20261022/Mio-live2d-web.zip` 为最新网页包，6,624,527 字节，SHA-256：

```text
89ad0db230cdbfbd1aa6c2368a95c8352c82205973a6ca8d5b450b2e3f80f833
```

包内为标准 `.model3.json` / `.moc3`、三张图集、五组 motion3、表情、物理与可选网页适配层；未打包厂商 Core。网页预览目录在摘要复核时发现旧图集，已从当前运行资源重新同步，再加载浏览器复核。最新证据以本目录 `verification.json`、网页截图和控制台记录为准；上一轮完整表情与物理验收保留为历史。

## 复现入口

```bash
swift native/mio-companion/tools/pack_assets.swift
swift native/mio-companion/tools/export_psd.swift
python3 art/tools/live2d/export_mio.py --work /tmp/mio-fist-export
native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-fist-review
python3 native/mio-companion/tools/review_motion.py /tmp/mio-fist-review
python3 native/mio-companion/tools/audit_arm_connections.py /tmp/mio-fist-review
python3 native/mio-companion/tools/check_joint_seams.py /tmp/mio-fist-review
```
