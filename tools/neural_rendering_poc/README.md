# 两场景神经渲染实验

独立调用用户指定的 `gtrg55/dlss5-macos-overlay`，保留其 `RenderEngine`、MLX 模型和 Metal 合成实现。游戏的渲染配置、材质、模型与发布包不接入该工具。

固定来源：

- Mac 项目：`https://github.com/gtrg55/dlss5-macos-overlay`，提交 `0d4caa1fd36d2581785efa80e6ade09983a18f05`。
- Windows 项目：`https://github.com/perseval-BLR/NeuralScreen`，提交 `310ed7843a4c1567775f4f0aa1d5f04033d35a83`；实验模型来自其 `v2.6.3` 发布包。
- `nvngx_dlssnr.dll` SHA-256：`dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f`。DLL 仅供 Mac 提取模型数据，不在 Mac 执行；模型和外部程序留在忽略的本地实验目录，不提交。

## 采集

先按仓库说明准备锁定的 Godot。使用独立 `HARUMACHI_SAVE_DIR`、现有显示器及 `--audio-driver Dummy`，不用虚拟显示器。

`capture.gd` 使用 `shots.gd` 的 `bakery_scene_front`、`lake_pier` 两个机位，每个场景保存 90 张真实渲染 PNG。前 30 帧固定机位，后 60 帧平移相机 0.8 米。必须检查 `manifest.json` 的渲染帧计数，以及截图本身。

```sh
HARUMACHI_SAVE_DIR="$TRIAL/save_motion" ./tools/godot --path game \
  --screen 0 -t --position 60,80 --resolution 1280x720 \
  --audio-driver Dummy --fixed-fps 30 \
  --script "$PWD/tools/neural_rendering_poc/capture.gd" -- \
  --out="$TRIAL/motion_source" --graphics-profile=balanced --graphics-benchmark

HARUMACHI_SAVE_DIR="$TRIAL/save" ./tools/godot --path game \
  --screen 0 -t --position 60,80 --resolution 1280x720 --audio-driver Dummy \
  res://scenes/main.tscn -- --shots="$TRIAL/source" \
  --views=bakery_scene_front,lake_pier --clean=1 \
  --graphics-profile=balanced --graphics-benchmark
```

`TRIAL` 必须先设置为独立实验目录的绝对路径。调用方为两条命令分别设置超时，并在前后比对默认存档摘要。固定 30 Hz 与 PNG 编码用于生成配对素材，不作为游戏实时帧率测量。

## 推理

按外部项目 `docs/BUILDING.md` 提取模型、准备 Xcode Metal Toolchain、CMake 与 Ninja。只给外部 checkout 增加 PNG 诊断入口：

```sh
python3 tools/neural_rendering_poc/prepare_trial.py "$OVERLAY"
# 在 OVERLAY 中执行其 scripts/build-app.sh。
python3 tools/neural_rendering_poc/run_trials.py \
  --app "$OVERLAY/dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON" \
  --model "$OVERLAY/Models/NR.dlss" --evidence "$TRIAL"
python3 tools/neural_rendering_poc/review.py "$TRIAL"
```

`OVERLAY` 为外部 checkout 的绝对路径。每个场景测试 Natural 512、Natural 768、Cinematic 768，以及 Natural 768 的 90 帧运镜。`SceneTrial.swift` 读入 PNG 后使用原项目的 `RenderEngine.process()`；每组独立启动进程，避免跨场景历史残留。输入 PNG 的色彩转换回写另存为 `input-roundtrip.png`，应与原图进行像素比较。

`metrics.json` 排除前 6 帧预热，记录每帧、均值、中位数与 P95。时间包含缩放、估算光流、神经推理和合成，排除文件读写、游戏渲染、屏幕捕获与显示。它是处理吞吐，不是游戏 FPS 或端到端延迟。

`index.html` 展示完整分辨率的拖动对照。运镜视频左侧为原图、右侧为处理结果，以原始 30 FPS 时序播放；这是离线逐帧处理，不能据此声称实时 30 FPS。模型输出与 NVIDIA 官方运行时不保证一致。Windows 实跑、实时覆盖延迟、人物/UI、快速镜头和长时间稳定性仍需各自的验证。

## 与游戏同时实时运行

`live_game.gd` 使用相同机位和真实时钟，12 秒周期平移相机 ±0.8 米。1280×720、均衡 60 FPS，关闭焦点限帧但保留正常 60 FPS 上限；不使用 `--fixed-fps`。底部黑白条记录原始帧 ID，用来把游戏渲染、捕获和增强预览的实际显示配对。它只在独立测试入口绘制，不修改游戏场景。

先在外部 checkout 执行 `prepare_live.py` 并重新编译。该脚本锁定上述源码 SHA，遇到不属于本工具的修改拒绝覆盖；`--replace-owned-patches` 仅用于迁移本实验自身的旧适配。适配增加命令文件、时间戳和显示探针，测试期间禁用音频捕获，并调整实验覆盖窗口的层级与透明度；不修改 `RenderEngine`、MLX 权重、处理队列和游戏资源。

```sh
python3 tools/neural_rendering_poc/prepare_live.py "$OVERLAY"
# 在 OVERLAY 中执行 scripts/build-app.sh，然后分别启动下面两个有界进程。
HARUMACHI_SAVE_DIR="$LIVE/save" ./tools/godot --path game \
  --screen 0 -t --position 60,80 --resolution 1280x720 --audio-driver Dummy \
  --script "$PWD/tools/neural_rendering_poc/live_game.gd" -- \
  --out="$LIVE" --graphics-profile=balanced --graphics-benchmark

"$OVERLAY/dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON" \
  --live-trial "$LIVE"

# 两个进程就绪后，在第三个终端串行测试两个场景。
python3 tools/neural_rendering_poc/run_live.py "$LIVE" --seconds 30 --warmup 8 --record
python3 tools/neural_rendering_poc/analyze_live.py "$LIVE"
```

`LIVE` 是新的独立证据目录绝对路径；不要覆盖已有样本。同一时间只运行一个 Godot 和一个 overlay 实例。游戏入口 2400 秒自动退出，调用方也应为应用设置超时。测试结束向两个 `*-command.json` 分别写入 `{"id":"finish","action":"quit"}`，等待自身进程退出；应用会恢复启动前的 `renderSettings`。默认存档在前后做摘要对照。

默认矩阵是每场景原生、仅捕获显示、Natural 512/60、768/60、512/30、再次原生，共 12 组；每组预热 8 秒、采样 30 秒。`--record` 另外保存 8 秒左右分割的真实实时输出，左原图、右增强，保留输入时间戳，不补帧；录屏不在计时区间内。

帧率与延迟须分别解释：

- 游戏 FPS 来自墙钟时间内的实际渲染帧数。
- 处理 FPS 来自真正完成的 `RenderEngine.process` 数量。
- 显示 FPS 来自非零 `MTLDrawable.presentedTime`，并记录实际窗口 ID；覆盖层时间戳为零时不能用 GPU 完成时间代替，也不能把预览时间冒充覆盖时间。
- `capture_to_present_ms` 从 ScreenCaptureKit 时间戳到上述窗口呈现；`capture_to_processed_ms` 仅到处理完成。两者都不是按键到光子的硬件测量。
- 显示探针只采样游戏矩形，排除其他应用窗口；它用于核对延迟后的源帧 ID 是否真的覆盖了游戏。原生/仅捕获模式下，同帧匹配不构成“神经结果已显示”的证明。

本次实际结果及直接覆盖的兼容性限制见 [实时记录](../../docs/game-design/NEURAL_RENDERING_LIVE_20261026.md)。
