# 澪语义表情与源部件（v18，2026-10-22）

本轮把“如何回应”交给现有 Clef-Omni，让眉眼、口形和手形表达同一个意图。原「桌面来信」仍是用户入口，气泡只显示台词；原眼睛、脸轮廓、0.736 头部比例、认可的衣袖拼接保留，伸懒腰仍已移除。

## 来源和实现

读过 [Soullink Emotion SDK](https://github.com/nanlingyin/soullink-emotion-sdk/tree/02cd75ac0a085a87d84d1a885f1b33eca8742d53) 的 engine、VAD、表情通道及可选分类器结构。本项目独立编写 Swift `EmotionPlayback`：Clef 输出语义类别，连续混合器控制已校准的澪参数，语句口型保留开合控制权。没有使用 embedding、第二个推理模型或把其 Pixi 7 适配器直接接进现有 Pixi 6 项目。VAD 数值作为连续状态记录；面部目标由本角色八套人工校准参数确定，不宣称移植了完整 FACS 求解器。

读过 [AstraLayering](https://github.com/wu-tian807/AstraLayering/tree/8ab3486c2a46233ab6431690c53fc0d1dd9f6a70) 的总提示词及脸、眼、嘴、手部规划。采用先定义部件职责、检查遮挡内层、独显后重组的流程。自己的制作规范在 [mio-emotion-layering.md](../../art/manifests/prompts/live2d/mio-emotion-layering.md)。本轮在原 PNG 上做语义分层与模型关键形，未调用生成模型重画长相。

## 可编辑资产

- 源 PSD / CMO3：53 个部件；正式 Cubism 4.0 目标 MOC3：36 参数、53 ArtMesh、三张图集。
- 两眼分别有眉毛、眼白、虹膜、上下眼睑和闭眼线。眉角独立；眨眼时眼睑遮住虹膜，虹膜不再跟着压扁；笑眼抬起下眼睑。
- 嘴部独立为两层闭口唇线、五层开口唇/口腔/牙齿/舌头，支持嘴角和圆口形。
- 两侧掌心各拆出五根完整手指，指根留重叠并固定，使用各侧张合参数协调。其他手形保留专用原画。
- 独显检查修复了掌心里的五个指尖轮廓残留，以及眼白层内的眼线残留。旧指尖归属规则先被六处回归断言检出，修后残留为零。
- 所有原始 PNG 保留。对照 v17 中性脸，眼区平均像素差 0.866/255，低于身份回归阈值 3。

## 决策与动画

现有 `/v1/systemone` 增加 `expression`、`intensity`、`hand` 三道 choice 问题。八种表情：neutral、warm、joyful、curious、concerned、surprised、determined、sleepy；三档强度；五种手势含义：rest、wave、explain、chin、encourage。输出只允许枚举，不能直接发送网格或程序指令。

提示词明确本轮消息优先：历史仅用于衔接，不能把旧表情当默认。六类合成情境 A/B 中，历史背景下的庆祝手势从 rest 恢复为 encourage，其余五类未发生类别退化；困惑仍可能被模型判为克制倾听，未用本地关键词强制覆盖模型。最近对话中的角色回复携带当时表情，仍限当前会话、最近半小时和八条对话上下文。模型据当前话题决定延续或转变。概率门槛按多选题处理：八种表情、五种手形不能套二选一的 0.5 门槛；真实庆祝样本中 encourage 为 0.377、explain 为 0.282，旧 0.4 门槛错误把有效首选变成放下手。

表情以 0.22 秒时间常数连续过渡，眨眼乘在眼睑开合上；说话时情绪控制嘴角和圆口，语句控制开合与标点停顿。标准文件含八种 exp3 及 happy/thinking 兼容别名、Idle/wave/think/talk/encourage 五组动作。新增加油为肩旁轻握拳，保持另一手自然下垂。

网页继续用标准 `model3` 加载，`mio-performance.js` 可选地接收同一个 Clef 决策，不内置推理服务或密钥。`Mio.emotion.json` 从 Swift 生成，避免两端维护两套表情参数。已对照 3,000 帧、33,000 个通道数值，最大误差 7.16e-7。网页验收必须在 `beforeModelUpdate` 中读取最终参数；Pixi 0.4.0 绘制后会恢复参数，绘制后的读值不能代表实际表情。[更新顺序](https://github.com/guansss/pixi-live2d-display/blob/v0.4.0/src/cubism4/Cubism4InternalModel.ts#L170)

## 验证记录

证据根目录为 `evidence/mio_emotion_20261022/`。当前已完成：

- 官方 Core：36 个参数均实际驱动几何或可见性，3,030 个动作/切换帧；42 张原生源对照和方向/眨眼截图。
- 全动作：6,514 张 Metal 帧、25 组切换。78.168 万连接带像素最小 alpha 254/255；实际 Core 接合误差最大 0.000137 px；13,028 条皮肤带无超阈暗线，无裁边。
- 表情切换：八种表情间的 64 种转换，共 5,760 个实际 Core 中间帧；无非有限顶点或翻转，最大单帧顶点位移 0.909 px。
- 手动模式：旧逻辑在自动切到手动动作后不再更新表情，新回归先检出四处失败。修复后手动动作只接管肢体，当前来信继续更新表情和口型，回复结束释放表情；360 张实际 Metal 帧及三状态近景通过。
- 组合压力：3,240 个表情/强度/动作/视线/眨眼组合，360 张 Metal 截图；无非有限顶点、网格翻转或多手叠影，最大连接误差 0.000126 px。
- 网页标准格式：关闭可选控制器后，五组 motion3 和八种 exp3 独立播放，2,548 帧、八项兼容检查通过。
- 网页中断切换：修复前 wave→think 手腕峰值 4,178 px/s；增加反向折肘经垂手及实际轨迹限速后，25 组、5,402 帧最终最大 832.4 px/s。
- 源图层：53 层非空；默认重组、眼口独显、指根和掌心残留检查。
- 表情：24 组脸部强度组合和真实过渡帧；网页八种表情与五种手势的十三项检查通过，另有手动说话和安静闭口回归。
- 真实 Clef：八条合成输入均得到可解码语义决策；中奖样本返回 joyful，按回应含义视为合理，并不强制模仿“意外”一词。此项不代表所有文本的分类准确率。

- 原生可见窗口：现有显示器上 33.602 秒、1,834 个渲染帧，平均 54.58 FPS；六个状态通过。目标仍为 60 FPS，这不是实测恒定 60 FPS 的声明。
- 完整测试：86 项；真实 Clef 开启的最终运行通过 84 项、跳过两项 HTTP；真实 HTTP 运行补验这两项，并由原生应用消费 14 个 Postman 响应。两次运行均无失败。新增的两项 Core/手动模式回归在最终 86 项运行中通过。
- 原桌面来信：24 个运行资源逐文件与源交付一致，同一 bundle 已重启；此时 Mac 锁屏，重启后的常驻桌面画面尚待解锁目视复核。没有另外安装用户应用。
- 项目检查：8,024 项、190 个 JSON、339 个 Python 文件通过。
- 网页包：6,266,430 字节，SHA-256 `fb7bafab8ff09f118673f65ee9d307acff386cc54f81173c0b0089412cdc6ccd`。

汇总为同目录 `verification.json`，源码/交付哈希和每项原始证据可追溯。各项失败反例保留，不以旧版数据替代当前验收。50 秒、60 FPS 的静音 MP4 来自真实 Metal 帧序列；它是复现演示，不是可见窗口帧率测量。

## 重复运行

从仓库根目录执行：

```bash
python3 art/tools/live2d/export_mio.py --work /tmp/mio-export
native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-emotion /tmp/mio-emotion
node native/mio-companion/tools/verify_web_emotion.mjs /tmp/mio-emotion/emotion-review.json
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-motion /tmp/mio-motion
python3 native/mio-companion/tools/audit_arm_connections.py /tmp/mio-motion
python3 native/mio-companion/tools/review_motion.py /tmp/mio-motion
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-expression-matrix /tmp/mio-expression-matrix
python3 native/mio-companion/tools/review_emotion.py /tmp/mio-emotion
python3 art/tools/live2d/review_parts.py --output /tmp/mio-source-layers
python3 native/mio-companion/tools/package_web.py --output /tmp/Mio-live2d-web.zip
```

`MIO_REVIEW_SAVE_FRAMES=1` 可保存演示全帧。所有验收进程静音，不创建虚拟显示器；合成对话模式不启动系统监控。网页包不含厂商 Core，已测范围为当前模型和指定 Pixi 播放器；不是任意模型/任意播放器兼容保证。当前手指是掌心姿态的小幅张合，转头为原画范围的小角度关键形，文字口型不是音素级语音同步。自然度和长相仍需用户复看，数值检查不能替代审美判断。
