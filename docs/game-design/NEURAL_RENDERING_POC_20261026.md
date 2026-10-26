# 两场景神经渲染实验（2026-10-26）

按用户给出的 NeuralScreen 与 dlss5-macos-overlay，在本机 M5 Max 上完成面包房街景、湖边栈桥的实际 MLX/Metal 神经推理。产物是独立的静态对照与离线运镜视频；正式游戏、模型、材质、默认画质和交付包均未接入该效果。美术效果待用户审看。

## 来源与环境

- [NeuralScreen](https://github.com/perseval-BLR/NeuralScreen)，源码提交 `310ed7843a4c1567775f4f0aa1d5f04033d35a83`。模型输入来自 `v2.6.3` 发布包中的 `native/nvngx_dlssnr.dll`。
- [dlss5-macos-overlay](https://github.com/gtrg55/dlss5-macos-overlay)，提交 `0d4caa1fd36d2581785efa80e6ade09983a18f05`。使用该项目原有的 `RenderEngine`、MLX-DLSS、Metal 合成与估算光流。
- MacBook Pro，Apple M5 Max，40 核 GPU、128 GB 内存；macOS 27.0.1、Xcode 27.1。本轮补装官方 Metal Toolchain 27A266a，初次缺失导致的编译失败日志保留，随后编译和本地签名检查通过。
- Godot `4.8.dev7.official.c971f93e7`，原版游戏源场景，均衡画质，1280×720 输出，测试进程使用 Dummy 音频。使用现有显示器，无虚拟显示器。
- Windows 程序未在 Windows/NVIDIA 硬件实跑。Mac 输出不代表 NeuralScreen 在 Windows 上的输出，也未与 NVIDIA 原生运行时做像素等价验证。

发布 ZIP SHA-256：`014b347e62cde9a2dd1e472c18e74d3fc19639ff7775969dd8f70b90aac00b66`，与发布方 SHA256SUMS 一致。DLL SHA-256：`dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f`，与 Mac 项目曾验证的 DLL 相同。转换得到 649 个逻辑张量，最终权重摘要为 `bd91157a0bb9b0fb02f080ca83d9152d1f33b28d9ff28699c544aa2e36a21d1c`。DLL 仅作为数据读取，未在 Mac 执行。下载 ZIP 在提取并校验后删除，模型、DLL 与外部程序仅保存在本地忽略目录。

## 采样方法

机位来自 `shots.gd`：`bakery_scene_front`（10:30）与 `lake_pier`（16:18）。静态组每个配置处理 18 帧相同原图，排除前 6 帧预热；Natural 512、Natural 768、Cinematic 768 各跑一次，强度、Tone、Structure 均为 1，时序处理开启。

运镜组每场景采集 90 张原生渲染 PNG：固定 30 Hz，前 1 秒相机不动，后 2 秒平移 0.8 米。原始渲染帧计数分别为 59→149、209→299；两段都持续完成 90 帧渲染。随后使用 Natural 768 离线逐帧处理，每帧保留一一对应的结果，按原时间顺序生成 3 秒、30 FPS、无音轨的左右对照视频。

PNG 读取入口是本轮增加的独立诊断适配器；外部项目的模型和 `RenderEngine` 未改。8 组输入经读入/回写后的最大通道误差均为 0，排除了 PNG 色彩转换造成的假变化。所有结果保持 1280×720；512 与 768 是网络工作长边，对应 512×288 与 768×432。

## 本机处理速度

| 场景 | 配置 | 平均 ms/帧 | 处理帧/秒 | P95 ms |
| --- | --- | ---: | ---: | ---: |
| 面包房静态 | Natural 512 | 18.59 | 53.78 | 19.15 |
| 面包房静态 | Natural 768 | 27.01 | 37.03 | 27.38 |
| 面包房静态 | Cinematic 768 | 27.05 | 36.97 | 28.26 |
| 面包房运镜 | Natural 768 | 33.38 | 29.96 | 38.09 |
| 湖边静态 | Natural 512 | 18.39 | 54.37 | 18.64 |
| 湖边静态 | Natural 768 | 27.05 | 36.96 | 28.18 |
| 湖边静态 | Cinematic 768 | 27.31 | 36.61 | 28.52 |
| 湖边运镜 | Natural 768 | 31.06 | 32.20 | 37.08 |

以上时间包含缩放、估算光流、神经推理和合成，排除 PNG 读写、屏幕捕获、游戏渲染与显示。推理时采样游戏进程已退出。这些数字不能当作游戏和覆盖程序同时运行时的 FPS，也不能证明端到端延迟。首次 512、768 推理分别出现约 7.54 秒、5.95 秒的首帧开销；上表排除预热，不隐去这一启动边界。

## 画面观察与待验范围

面包房主要变化是橱窗、门框、树叶与材质的局部明暗和对比；窗格、陈列和原有建筑细节仍可辨。湖边主要变化在草地明暗、树冠与栈桥的光泽，水面和远景变化较轻。这里记录的是本轮图像观察，不代表画风已经获用户接受。两种配置的完整分辨率图片以及运镜对照已保留，便于逐处审看。

尚未验证：Windows 实际运行；Mac 屏幕捕获→覆盖显示的实时链路；与游戏争用 GPU 时的性能和耗电；真人试玩手感；人物脸、UI/小字、快速转镜头、长时间时序稳定性。模型的估算光流不等于游戏引擎真实运动向量。现有证据不足以把该效果设为默认或发布到游戏。

## 产物与检查

本地证据根目录：`evidence/neural_rendering_20261026/`。

- `index.html`：两场景拖动对照，切换 Natural 512/768、Cinematic 768；可展开运镜视频。
- `source/`、`motion_source/`：原始 PNG 与渲染帧记录。
- `results/`、`measurements.json`：6 组静态结果、180 张配对运镜结果和逐帧耗时。
- `videos/*-comparison.mp4`：每段 90 帧、1920×540、3 秒，左原图、右 Natural 768。
- `verification.json`、`provenance.json`：色彩回写、配对数量、存档保护与来源摘要。
- 外部项目 4 项 ScreenCore 测试通过，项目检查 `tools/check_project.py` 通过。采集进程退出码为 0；退出时保留了既有资源清理警告，未将其描述为零警告运行。
- 默认 104 份存档与照片摘要不变。未增加游戏内测试数量，未重新导出或发布游戏。

复现入口见 [`tools/neural_rendering_poc/README.md`](../../tools/neural_rendering_poc/README.md)。
