# 均衡档光影 POC（2026-10-25）

这是待用户观看的视觉方向样片，不是默认画质更新。基线为 `3cfbf7d`，正式 `game/`、默认设置和 `builds/HareMachi.zip` 均未修改。POC 控制器只由 `tools/lighting_poc/run.py` 复制到本轮临时工程并显式启用。

## 试做范围

保留均衡档 60 帧上限、85% 3D 渲染比例、4× MSAA、4096 方向光阴影、低质量 SSAO；没有加入 SSIL、SDFGI 或额外实时灯光。角色源模型、动作、足部约束、衣物预算、草密度、玩法与 UI 均保留。

- 调整天空与常量补光的占比。室外白天天空占比 0.58，随夜色增至 0.82；暖色阳光与偏冷补光分开。室内保留窗光与原体积雾，降低均匀补光和材质自身的阴影填充。
- 保持曝光 1.0，分时段调整对比度与辉光。提高辉光阈值，减少整片泛亮；灯笼仍保留光晕与纸面文字。
- 在原 4096 阴影图内调整级联分配与滤波宽度；SSAO 半径从 1.2 降至 0.65，避免过宽的暗晕。没有提高阴影图或 SSAO 的质量等级。
- 调整原深度雾的起止距离、颜色与密度，保留现有远景；树叶与草叶的法线向上偏置稍减，强化局部受光变化，不新增顶点或贴图采样。

第一版静态预览在 `preview/poc/`；第二版进一步降低白天天空补光占比，最终静态预览为 `preview-v2/poc/`。原版对照在 `preview/before/`。参数变化不等同于用户认可画面。

## 录像与测量边界

四个场景为农园正午、商店街 17:18、夏祭 20:10、商店室内 10:30。两侧使用相同的游戏时间、天气、镜头轨迹与均衡设置。环境和人物动画继续运行，跨进程的风与居民动画相位可能不同。

录像使用真实 Godot Movie Maker，现有 screen 0，1080p / 30 FPS 固定时间步，每段截取 360 帧。并排版保留两侧完整画面，各缩为 1280×720，顶部另加标题。没有 AI 生成画面、后期重打光或调色；视频只做裁时、缩放、标注与色彩空间转换。最终 MP4 使用 BT.709、有限范围、yuv420p，完整解码核对。录制会改变运行时节奏，不能用视频播放帧率证明游戏性能。

性能另开进程，关闭 Movie Maker，以 2560×1440、正常 60 帧上限在每个静态机位连续测量 30 秒，保留居民和环境动画。运行串行、存档隔离、测试进程静音；不创建虚拟屏幕，不改系统音量或电源策略。GPU 中位耗时与进程 CPU 用于短时对照，不是瓦数、温度或长时间游玩结论。

## 复现

需要锁定版本的 Godot、本机 FFmpeg/FFprobe 与 Python Pillow。标题条使用项目字体，由 Pillow 生成，不依赖 FFmpeg 可选的 `drawtext` 滤镜。

```bash
python3 tools/lighting_poc/run.py prepare --out evidence/lighting_poc_<日期>
python3 tools/lighting_poc/run.py preview --out evidence/lighting_poc_<日期>
python3 tools/lighting_poc/run.py bench --out evidence/lighting_poc_<日期> --seconds 30
python3 tools/lighting_poc/summarize.py evidence/lighting_poc_<日期>
python3 tools/lighting_poc/run.py record --out evidence/lighting_poc_<日期>
python3 tools/lighting_poc/encode.py evidence/lighting_poc_<日期>
python3 tools/lighting_poc/run.py finish --out evidence/lighting_poc_<日期>
```

原始 AVI 与冻结工程只存在于临时目录。`finish` 核对默认存档摘要后清理该目录；MP4、原生截图、逐场景原始采样、日志和来源摘要保留在 `evidence/lighting_poc_20261025/`。

若八段原尺寸视频已成功编码，只有拼接步骤中断，可以为同一证据目录的 `encode.py` 加 `--reuse-solos`；不能混入其他录制批次的视频。程序仍核对帧数、分辨率、两侧元数据，并完整解码所有成片。

## 短时性能对照

本机 M5 Max，四场景各 30 秒，原版与 POC 分进程串行运行。下表 GPU 为单帧中位耗时；一轮配对结果仅用于判断这个试做的即时开销，较小差异可能来自运行波动。

| 场景 | 原版 GPU | POC GPU | 变化 | 原版 / POC 平均 FPS |
| --- | ---: | ---: | ---: | ---: |
| 农园正午 | 6.353 ms | 6.366 ms | +0.2% | 60.00 / 60.03 |
| 商店街夕阳 | 6.330 ms | 6.338 ms | +0.1% | 59.93 / 60.03 |
| 夏祭夜景 | 6.614 ms | 6.897 ms | +4.3% | 59.95 / 60.03 |
| 商店室内 | 6.333 ms | 6.309 ms | −0.4% | 59.94 / 60.01 |

八次采样 P95 帧间隔均为 16.88–16.96 ms，未录屏时持续出帧检查通过。均衡档位、渲染比例、抗锯齿、阴影图、SSAO/SSIL、室内体积雾和曝光的实际运行断言通过。原始结果见 `bench/{before,poc}/result.json`，汇总见 `performance-comparison.json`。本轮未测瓦数、摄氏度或长时间游玩；不把这些短时结果当作温升结论。

## 视频与检查结果

`evidence/lighting_poc_20261025/videos/` 保留以下成片，左侧为当前均衡，右侧为光影 POC：

- `lighting-poc-comparison.mp4`：48 秒，依次为正午、夕阳、夜景、室内。
- `farm-compare.mp4`、`street-compare.mp4`、`plaza_festival_night-compare.mp4`、`store_interior-compare.mp4`：每段 12 秒，2560×776。
- 每个场景另有 `*-before.mp4` 与 `*-poc.mp4`：各 12 秒，1920×1080，便于单独全屏看细节。

13 个视频的帧率、时长、色彩标记和完整解码均通过；两侧三处采样镜头的坐标及朝向一致。已查看 24 张原生录像截图和四组最终视频中段抽帧，另核对八段 MP4 与对应原生截图的颜色传递。报告分别为 `media-validation.json`、`native-video-visual-review.json`、`video-color-validation.json`。第一轮拼接因本机 FFmpeg 缺少 `drawtext` 中断，改用 Pillow 标题条后复用同批八段原片完成。

观感上夕阳的冷暖分离、室内地板与家具阴影变化较明显；正午和夜景较克制。农园大面积绿色、既有树形与室内墙顶隐藏规则仍来自原场景，本轮没有把这些素材与场景结构问题列为已解决。抽帧检查不是完整的动态闪烁、全天气或玩家体验验收，最终视觉方向待用户观看决定。

临时工程、AVI 和标题条已清理，默认 104 份存档与照片摘要不变。源码检查通过，正式 `game/` 无差异；没有重导出包，也没有重跑全量 2845 项或导出包自动演示。历史正式版验收不能用作本 POC 的发布验收。
