# 澪自然垂手与 Live2D 格式核对（2026-10-20）

## 自然垂手

上一版待机沿用便于拆图、绑定的外张双臂。本次修改源动作 `PuppetMotion` 的待机肩角，两侧向内收约 21.8°，手腕落在胯侧。待机保留轻微呼吸和摆动，动作结束回到这一姿势。界面原「轻摆」按钮改为「放下」，内部动作 ID 仍为 `idle`，现有决策协议不变。

只有参与动作的手臂随动作幅度退出垂手偏置：招手、托腮时另一条手臂继续自然垂下；伸懒腰时双臂退出偏置。保持阶段的招手掌心、双拳过头、食指抵下巴目标不变。手动过渡仍走实际姿势历史和原有限速；思考切伸懒腰仍先落臂。

新增回归按肩腕的实际变形坐标检查水平距离小于 55 像素、向下距离大于 210 像素，覆盖待机及四个动作结束。旧版先产生 80 处失败，修后通过。反向折肘回归以当时的自然垂手为参照，保持「另一条手臂不可提前抬起」原义。原生窗口新增双腕位置的垂手断言。

本轮只改源动作和界面按钮，不修改 PNG、PSD 或 rig 的源绑定布局；布局仍为 `20261020-continuous-v10`、30 层。

## 格式核对结论

**当前交付不是正式 Live2D Cubism 模型。** 之前完成了自有分层角色和 Swift/Metal 动画渲染，原始任务中的正式 Live2D 格式仍未完成，不能将视觉动作复核通过当成格式交付通过。

| 检查项 | 当前结果 |
| --- | --- |
| 两个 `Mio.rig.json` | 相同，`format: harumachi-layer-rig`、`cubismCompatible: false` |
| 源 PSD | `8BPS`、版本 1、750×1000、RGB/8、30 层分层绘画素材 |
| Cubism 编辑模型 `.cmo3` | 未生成 |
| Cubism 运行模型 `.moc3`、入口 `.model3.json` | 源素材和应用资源中均不存在 |
| 官方动态、物理、表情和姿势文件 | 无 `.motion3.json`、`.physics3.json`、`.exp3.json`、`.pose3.json` |
| 应用加载路径 | Swift `JSONDecoder` 解码自有 `RigDescription`，自有 Metal 顶点变形 |
| Cubism Core/SDK | Swift Package 未依赖，渲染器未接入 |

按 [Live2D 官方文件类型说明](https://docs.live2d.com/zh-CHS/cubism-editor-manual/file-type-and-extension/)，`.cmo3` 是 Editor 模型，`.moc3` 是程序使用的模型；[嵌入数据说明](https://docs.live2d.com/en/cubism-editor-manual/export-moc3-motion3-files/)说明 `.model3.json` 关联 MOC3、纹理及其他运行数据。PSD 只是后续制作来源，不能用改扩展名或另造 JSON 替代模型导出。

正式格式交付仍须在 Cubism 建模、绑定并导出，接入官方 Core/SDK 后验证真实加载与动作。现有 PSD 尚未在 Cubism Editor 导入验收，本轮没有声称完成这些步骤。

## 验证证据

格式核对结果在 `evidence/mio_rest_20261020/format-audit.json`；源动作旧版失败在 `before.txt`，最终本地测试在 `tests.txt`。完整离线复拍继续使用生产 Metal 渲染器和原来的 6514 帧范围，静音、不读取系统事件或连接 Clef，不创建虚拟显示器。最终指标及二进制摘要见同目录 `verification.json`。

30 项本地 Swift 测试通过，两项联网集成测试未跑。新一轮 6514 帧中，65140 个关节中心最小 alpha 253/255，无裁边；13028 条皮肤连接带最大异常变暗 0.67/255、无超阈值样本；最大右腕步长 14.66 像素/帧。五动作十部位放大表、25 组真实切换、自动/说话/视线和长时钟表已逐项复核，未发现新的贯通接缝、手型重影或反向折臂。现有显示器上的原生窗口连续渲染 838 帧、平均 29.80 FPS，含新增垂手断言的六状态全部通过。

[自然放下前后对照](../../evidence/mio_rest_20261020/rest-comparison.png)。本轮通过的是自然垂手与现有自有格式的动作验收，正式 Cubism 格式交付仍未通过。
