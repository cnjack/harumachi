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
