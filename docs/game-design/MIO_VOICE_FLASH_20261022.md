# 桌面来信接入 Tencent DeepSeek Flash 与延迟验收

本轮按用户指定读取 JCode 的 `tencent-tokenhub` 配置，使用 `https://tokenhub.tencentmaas.com/v1`、`deepseek/deepseek-flash`。原 `io.harumachi.MioCompanion` 应用已配置；API Key 按接口地址存入 macOS Keychain，未写入偏好设置、仓库或测试日志。没有更改 JCode 本身的配置。

## 实测结果

测试在这台 Mac 上调用真实本地 Qwen3-ASR-0.6B、Qwen3-TTS-1.7B CustomVoice、声学唤醒/Silero VAD 与真实 Tencent LM。六条不同合成输入按真实时钟逐 160 ms 送入生产采集处理入口；没有使用模拟 LM，也没有把音频一次性快放来冒充实时结果。以下是最终版本六条普通对话的样本统计，不能据此保证公网服务长期的 P95 或 SLA。

| 项目 | 中位数 | 最小–最大 |
| --- | ---: | ---: |
| 输入人声结束到开始播放回复人声 | **2,537 ms** | **2,351–2,765 ms** |
| 输入人声结束到端点确认 | 619 ms | 561–685 ms |
| 最终 ASR | 72 ms | 55–87 ms |
| 文字提交到 LM 首字 | 1,523 ms | 1,398–1,649 ms |
| TTS 请求到首个非静音 PCM 包 | 124 ms | 120–125 ms |
| 文字提交到开始播放回复人声 | 1,848 ms | 1,631–1,990 ms |

远端 LM 是本轮最大的等待来源。首句按标点流式送入 TTS，后续文字生成与播放并行，不等待完整回答。进程查询、网页读取各需要两次 LM 请求；本轮分别在文字提交后 **3,440 ms、3,957 ms** 开始播报实际结果。它们分别只测了一次，不是分位数统计。

“人声结束”以已知合成 PCM 的最后一个 RMS > 0.003 的 32 ms 块为基准；播放测量使用 AVAudioPlayerNode 的实际播放时钟及 40 ms 音量采样。测试进程的混音器静音，不改变系统总音量。这是实时音频回放的应用链路延迟，尚未包含真人麦克风、实际扬声器到耳边的声学验证。

## 测试中修复的问题

- Flash 在 TokenHub 默认会开启思考。按[腾讯官方调用指南](https://cloud.tencent.com/document/product/1823/132248)显式发送 `thinking.type=disabled`，保持用户配置的完整模型 ID。新增协议回归拿旧逻辑实际运行失败，HTTP 400；修复后通过。
- 日常聊天不再附带全部工具定义；仅当本轮文字包含进程诉求或 HTTPS 链接时提供对应只读工具。工具执行端仍独立校验权限与参数。
- 一条正例被声学阈值漏掉；另一条被 ASR 转写为“小林”。用 Swift 实际重采样数据校准 KWS，阈值从 0.3 调为 0.2，score 仍为 1.5。只有声学检测确认后，才允许“小林/小琳/小铃”等转写近音称呼。
- “这个小零件放在桌子上”能触发声学候选，现增加首句称呼检查，在本机拒绝该句，不发送给远端 LM。最终 **6/6 正例触发、10/10 普通/近音负例没有启动 LM 对话**；这不等于真实电视背景声或长时噪声误报率已验收。
- 打断发生在已开始播放人声之后；调用返回约 **11 ms**，随后 400 ms 内无新增播放块，口形复位。尚未完整播放任何短句的取消请求从待回应历史移除，避免模型在新问题后补说旧回答；已播出的短句仍保留上下文。
- 开启麦克风前先终止已有播放，避免切换 voice processing 导致播放时钟与旧队列不一致。

## 功能验收与证据

`evidence/mio_voice_flash_20261022/verification.json` 汇总最终测量，`native/native-pipeline.json` 保存合成测试对话与每轮分段时间，`timings.jsonl` 是独立计时记录。`first-complete/` 保留优化前完整结果，失败记录保留在 `before-fix-*` 与 `before-alias-*`，不混入最终样本。

- 六组真实唤醒 → VAD → ASR → LM → TTS → 原生播放/口形通过，十组负例通过。
- “最喜欢麦茶”及后续追问通过；已播放后打断、下一轮恢复通过。
- 模型主动选用 `list_processes` 并读取真实进程；模型选用 `read_website` 并读取 `https://example.com`；禁止无用户链接或附加查询参数的边界通过。
- 112 项 Swift XCTest：108 通过、4 项其他可选服务测试跳过，0 失败；本机 ASR/TTS 和协议夹具显式启用。项目源检查通过。
- 原生验收只读取本应用自有窗口缓存。Mac 仍锁屏，未声称完成前台 UI、真人麦克风、真实外放回声或真人语音打断验收。基准期间 Clef 被隔离，表情决策服务延迟没有计入上述数字；正常应用保留原 Clef 配置与并行表情决策。

## 复用入口

已安装应用继续使用仓库根目录 `open_mio_companion.command`。不会自动启动麦克风；解锁后在原窗口点击“开启语音”，系统授权完成后说“小澪”。

需要显式重新导入 JCode 的同一 Tencent 配置时：

```bash
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --import-jcode-tencent
```

该命令只接受已配置的 Tencent HTTPS 地址与 `deepseek/deepseek-flash`，使用原应用进程写入并读取验证钥匙串；正常启动不会读取其他应用的凭据。

复测可使用已保存的测试 WAV（均为本机合成，不含真人录音）：

```bash
MIO_VOICE_TEST_SILENT=1 \
MIO_VOICE_REALTIME_REPLAY=1 \
MIO_VOICE_REPLAY_WAV="$PWD/evidence/mio_voice_pipeline_20261022/wake-replay.wav" \
MIO_VOICE_REAL_WEB_LM=1 MIO_VOICE_WEB_TEST=1 \
MIO_VOICE_TIMING_LOG="$PWD/evidence/mio-voice-repeat/timings.jsonl" \
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion \
  --review-voice "$PWD/evidence/mio-voice-repeat"
```

`MIO_VOICE_REPLAY_FILES` / `MIO_VOICE_NEGATIVE_FILES` 可分别传入额外 WAV 路径的 JSON 数组。测试读取已保存模型与钥匙串，不需要把 Key 放进命令行。网络延迟随服务负载变化；当前约 2.5 秒，不是亚秒响应。下一步降延迟应针对远端首字与语义端点做同条件对照，不能单纯压低静音阈值来抢话。
