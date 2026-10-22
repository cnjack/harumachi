# 桌面来信表情入口（2026-10-22，v23）

用户发现网页能选表情，桌面来信看不到相同入口。检查确认：Clef → Decision.expression → PerformanceCue → 两个 CharacterView → EmotionPlayback 已存在；主窗口只有动作按钮，缺少表情控制。自动表情在回应结束后恢复平静，因此平时不易看出。

本轮在原桌面来信增加「自动、平静、温柔、喜悦、好奇、关心、惊讶、坚定、困倦」。选择即时同步主窗口与桌面角色；手动选择保持眉眼和唇形，当前语句的说话口形、手势与眨眼继续工作；切回自动使用最新 Clef 决策。重新启动默认自动，不保存测试选择。

同时修复已结束的 SpeechTimeline 一直占有嘴巴的问题：说话前后释放嘴部开合，标点停顿期间仍由语句控制，惊讶的静止圆口形可以正常显示。源模型与网页包仍为 v22，39 参数、58 ArtMesh，本轮无需更换原画或重新绑定。

## 验证

证据在 `evidence/mio_desktop_expression_20261022/`。

- 旧口形逻辑先跑新测试，触发 2 条失败；修复后 99 项 Swift 测试中 95 通过、4 项可选网络跳过。
- `--review-desktop-expressions` 在原应用的两个真实窗口逐项切换八种表情，各自持续渲染，保存 16 张角色图与窗口图；手动表情配合招手、说话以及恢复自动均通过。测试静音，不开启系统监控、不发网络请求、不创建虚拟显示器。
- `--review-dialogue` 用七条虚构对话实测现有 Clef 服务，全部经真实决策返回：介绍自己为 warm，分享完成项目为 joyful；其余本次返回 neutral。实际记录含强度和手形，不能把有请求等同于每轮都应出现明显表情。两窗口实播共取证，桌面渲染器 930 帧。
- 最终应用已重启。通过原生按钮点击「惊讶」，确认选中状态、眉眼和圆口形；未选中按钮保持正常文字对比度。验收后恢复「自动」。
- 项目检查、提交与 CI 详情见同目录 `verification.json`。用户视觉认可单独保留。

```bash
bash native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-desktop-expressions /tmp/mio-desktop-expressions
```
