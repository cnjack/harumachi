# 近似全双工研究探针

这些工具不接入桌面来信的运行路径，不修改语音设置或应用包。

`duplex_playback_probe.swift` 用 AVAudioEngine 离线渲染验证三种操作：

- `pause → play` 应保留已排队的 PCM，拼回暂停前后音频应与连续渲染一致。
- `stop → play` 是失败对照，必须检出尚未播放的 PCM 丢失。
- `stop → 新缓冲 → play` 应只包含新音频，旧回答不得漏入。

每种操作检查四个采样位置，共 12 例；输出 JSON，检查失败返回非零退出码。不会打开麦克风或扬声器，不测试 AEC、硬件停止延迟、Bluetooth 或真人插话。暂停期间 `playerTime` 可能不可用，应在暂停前记录游标。

在仓库根目录运行（Apple Silicon，部署目标与桌面来信相同）：

```bash
MIO_RESEARCH_STAGE="$(mktemp -d /tmp/mio-duplex-research.XXXXXX)"
CLANG_MODULE_CACHE_PATH="$MIO_RESEARCH_STAGE/clang-cache" swiftc -target arm64-apple-macosx14.0 \
  -module-cache-path "$MIO_RESEARCH_STAGE/module-cache" \
  -warnings-as-errors \
  native/mio-companion/tools/research/duplex_playback_probe.swift \
  -o "$MIO_RESEARCH_STAGE/playback-probe"
"$MIO_RESEARCH_STAGE/playback-probe" > "$MIO_RESEARCH_STAGE/result.json"
cat "$MIO_RESEARCH_STAGE/result.json"
```

受限进程可能无法访问系统 AudioComponent 注册服务；这与麦克风权限是两回事。本轮沙盒内初始化失败，允许访问系统服务后离线渲染完成。不要为了这个探针开启录音或改系统音量。

完整方案、测量口径、其余本机实验入口及未完成验收见[研究报告](../../../../docs/game-design/MIO_DUPLEX_RESEARCH_20261023.md)。原始研究脚本、公开音频和结果在忽略的 `evidence/mio_duplex_research_20261023/`；不把第三方权重、数据集或专用许可组件加入应用依赖。
