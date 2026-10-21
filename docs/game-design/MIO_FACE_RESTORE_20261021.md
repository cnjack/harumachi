# 澪原眼睛与脸型恢复（2026-10-21，v16）

用户指出 v15 的眼睛和脸型异常。放大对照确认：新生成眼部改变了原来的圆眼轮廓；转头关键形又让脸颊横移而下巴固定，造成脸型偏斜。上一轮参数有效、帧率和接缝测试通过，不能说明长相修改已获接受。

## 修复

- 直接使用原 `eyes_open.png`、`eyes_closed.png` 和 `Mio.rig.json` 中的注册位置。眼睛、眉毛及脸部源 PNG 摘要未变；移除运行资源里的八张 v15 新眼部切片，保留生成原图作为历史记录。
- 撤回固定下巴的脸颊形变。脸轮廓保持原形，头部由父变形器作轻微平移和歪头；本版不再尝试用这套简化曲面制造大角度转脸。
- 原眼图内部保留小幅视线和眉部运动，眨眼形变避开眉毛；闭眼图切换区缩窄，消除半闭眼时两套睫毛叠影。七个眨眼相位已放大查看。
- 保留 0.736 头部比例、v14 肩肘衣袖、v15 动作节奏、头发物理、网页自动 Idle 与手型防重影。伸懒腰仍已移除。

可编辑 `art/live2d/mio/cubism/Mio.cmo3`、30 层 PSD、运行 MOC3/图集同步重建。当前官方 Cubism 4.0 目标模型有 29 个有效参数、30 个 ArtMesh；四个动作组仍为 `Idle`、`wave`、`think`、`talk`。模型资源在源目录、原桌面应用和网页预览内逐文件摘要一致。

## 本轮验证

证据目录：`evidence/mio_face_restore_20261021/`，汇总 `verification.json`。这里仅报告 v16 的新结果。

| 项目 | 结果与范围 |
| --- | --- |
| 回归反例 | 新的原眼布局与脸轮廓测试在 v15 出现 9 处失败；最终 63 项 Swift 测试中 60 通过、3 项需显式网络配置的测试跳过 |
| 官方 Core / Metal | 2060 帧、29 个有效参数、37 张最终模型渲染图 |
| 原眼对照 | 中性眼区与原版的像素平均绝对差由 v15 的 19.25 降为 1.69/255；这是识别原画漂移的辅助指标，不是自然度评分 |
| 放大查看 | 原版/撤回版/修复版并排，9 个视线方向、7 个眨眼相位、四动作共 16 个面部相位；原眼形和脸颊/下巴轮廓恢复，抽查相位无双睫毛 |
| 最终桌面窗口 | 现有显示器运行 28.15 秒，1680 帧，59.69 FPS；放下、招手、思考、说话和自动五状态通过；静音、无系统监控、无网络请求、无虚拟显示器 |
| 最终网页 | Cubism 4 播放器加载 29 参数，头发物理开启；45.1 秒 2700 帧，8 步切换完成，无手型双层帧、无浏览器错误 |
| 下载包 | `Mio-live2d-web.zip` 解压回读校验通过，10 个运行文件，1,722,962 字节；不包含厂商 Core 库 |
| 原桌面来信 | 同一路径 `native/mio-companion/dist/Mio.app` 已构建并重启；重启后进程存活。Mac 锁屏阻止了常驻主窗口的再目视检查，这一项未算完成 |

本轮没有改动手臂与标准动作文件，未重复全套 5210 帧关节检查；不能把 v15 的该项结果标成 v16 新验收。Clef 接口未改，也未重测真实网络。当前确认的是原画恢复及上述播放结果，用户对长相和自然度的最终评价仍待复评。

## 复现

在仓库根目录执行，使用已安装的 Cubism Editor/Core，不下载或代替接受厂商协议：

```bash
python3 art/tools/live2d/export_mio.py --work /tmp/mio-face-export
./native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-cubism /tmp/mio-face-core
python3 native/mio-companion/tools/review_face.py \
  --reference evidence/mio_face_restore_20261021/before/original-default.png \
  --rejected evidence/mio_face_restore_20261021/before/v15-default.png \
  --current /tmp/mio-face-core --output /tmp/mio-face-review
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion-window /tmp/mio-face-window
python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip
```

`review_face.py` 只裁剪真实渲染截图做对照，不改源图片。原图摘要、恢复范围和撤回素材记录在 `art/manifests/mio_face_restore_20261021.json`。当前重新生成的原眼图注册由 `art/tools/live2d/prepare_face.swift` 完成。
