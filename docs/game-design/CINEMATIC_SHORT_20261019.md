# 夏祭短片：从 Kimodo 动作到 56 秒成片（2026-10-19–20）

本片是「明年夏祭」的一分钟电影化实验：空在榉树下点亮灯笼，澪走来打招呼，两人一起走向夏祭，最后镜头拉开到整场祭典。成片只用游戏现有场景和人物，动作由本地文本生成模型产出，再重定向到游戏骨架；整个拍摄在独立副本里完成，正式工程和人物模型没有改动。

## 交付

| 项目 | 结果 |
| --- | --- |
| 成片 | `evidence/cinematic_20261019/Harumachi_Next_Summer_56s.mp4` |
| 规格 | 1920×1080，24 fps，H.264 High，yuv420p；AAC 48 kHz 双声道；56.000 秒；1344 帧；89,345,506 字节 |
| 响度 | 整片 −16.4 LUFS，真峰值 −0.9 dBFS |
| 摘要 | `d8a4a7174e8f852b80acc52afb32164498e7657af6f7b74a236605edea1f29f3` |
| 关键帧 | `evidence/cinematic_20261019/stills_v7/`，11 张 |
| 逐帧 | `evidence/cinematic_20261019/frames/00000.png`–`01343.png` |
| 配乐 | `evidence/cinematic_20261019/music/take1_novocal.wav`，56.065 秒，44.1 kHz 双声道 |
| 隔离副本 | 基于提交 `6e654d1`，见 `evidence/cinematic_20261019/clone.json` |

解码完整，无坏帧；成片第 672 帧与源 PNG 的平均 PSNR 为 38.92 dB。画面带宽银幕黑边，黑边在渲染时直接画进 1920×1080 画面。

## 动作来源：Kimodo

采用 NVIDIA Kimodo 的 G1 文生动作模型（`kimodo-g1-rp`），本地 CPU 推理，100 步扩散，30 fps，34 关节。加载 18.2 秒；八段提示词逐段生成，每段 19–33 秒。提示词和种子固定在 `tools/cinematic_20261019/kimodo_prompts.json`，原始输出在 `evidence/cinematic_20261019/motion_sources/kimodo/`，每段的摘要、帧数、种子和提示词记在 `generation.json`。

八段动作：

| 片段 | 长度 | 用途 |
| --- | --- | --- |
| `neutral` | 2.0 s | 站姿校准 |
| `sora_walk` | 5.0 s | 空走向树下、离场、祭典穿行 |
| `sora_stop_look_up` | 5.0 s | 空抬头看灯笼、看烟花 |
| `sora_reach_lantern` | 4.0 s | 空伸手点灯 |
| `sora_turn_wave` | 4.0 s | 空转身向澪挥手 |
| `mio_walk` | 5.0 s | 澪走来、同行 |
| `mio_wave` | 3.0 s | 澪打招呼 |
| `look_up_wonder` | 5.0 s | 两人看烟花的收尾姿势 |

HY-Motion 只做了接口和输出验证：保存了一段 SSE 可视化返回（`hy_sse_test.txt`）和一段走路 FBX（`hy_test_walk.fbx`），没有进入成片。本片统一用 Kimodo，原因是种子可固定、能完全离线重跑，并且输出的 G1 骨架与既有 MotionBricks 重定向链一致。

## 重定向

`convert_kimodo.py` 把 Kimodo 的 `posed_joints`、`global_rot_mats` 和 `foot_contacts` 转成 MotionBricks 的 G1 输入；再用 `tools/motionbricks_poc/retarget.py` 重定向到空的游戏骨架。八段动作各追加到两个人物名下，片段名统一为 `motionbricks_poc_<动作>`，全部非循环。

重定向只追加动画：原 GLB 的二进制前缀、节点、蒙皮、网格、形态键、贴图、材质和原有动画 JSON 保持原样；正式模型的 SHA-256 在重定向前后一致。修正范围包括中立站姿校准、完整 G1 正向链、按人物调整的肢体比例、伸手和脚部 IK、接触锁定；没有用程序替换步态，也没有挂游戏内修正器。没有声称的部分：人工观感验收、G1 不具备的脚趾/头部/手指动作、原生布料修正、源动作集中不存在的跑步。

产物在 `art/poc/motionbricks_20261018/retargeted/cinematic-film-v1/`，清单 `manifest.json` 记录了 16 个片段、原始模型摘要和每段的源 NPZ。空和澪的成片模型摘要分别是 `728a3c2b…` 和 `915bdf40…`。

## 隔离与时间线

短片工程是从正式仓库复制出来的独立副本，源提交 `6e654d1`；`clone.json` 记录了复制前后正式模型的摘要，两者相同。电影脚本只存在于副本的 `game/cinematic/`，正式工程没有新增场景或资产。

驱动脚本 `tools/cinematic_20261019/godot/cinematic.gd` 用 24 fps 固定时间线，共 1344 帧。它把 `AnimationPlayer` 设为手动推进，按镜头调用 `play()` 和 `seek(t, true)`，因此拍摄快慢不会改变动作。九场戏：

| 镜头 | 时间 | 内容 | 动作 |
| --- | --- | --- | --- |
| S1 | 0–5 s | 空从树下走进画面 | `sora_walk` |
| S2 | 5–9 s | 抬头看灯笼 | `look_up_wonder` |
| S3 | 9–14 s | 伸手点亮灯笼，11.05 秒点火 | `sora_reach_lantern` |
| S4 | 14–19 s | 空在灯下等，澪走来 | 空 `idle` / 澪 `mio_walk` |
| S5 | 19–24 s | 澪在前景，空转身挥手 | `sora_turn_wave`、`mio_wave` |
| S6 | 24–29 s | 两人转身走向祭典 | 两人 `walk` |
| S7 | 29–34 s | 侧面经过屋台 | 两人 `walk` |
| S8 | 34–39 s | 烟火升空，两人抬头 | `sora_stop_look_up`、`look_up_wonder` |
| S9 | 39–56 s | 镜头升起拉远，字幕与标题 | 两人保持仰望 |

每个镜头有一组起止机位、视线目标、焦距、对焦距离、滚转和手持噪声，切换处直接切镜。烟花和灯笼辉光是时间的函数，不依赖帧率。片尾字幕为「灯，又亮起来了」，下面是 `HARUMACHI · NEXT SUMMER`。

## 构图与特效返工

这一轮不是一次拍完，下面几处是逐张看静帧后改的：

- **S4**：东侧机位把澪切在左边缘，招牌居中，空被灌木挡住。改为南侧机位 `(2.3,1.60,3.6)→(2.5,1.58,4.1)`，视线落在两人之间的灯笼上，空在灯笼旁、澪从左后方走近。
- **S5 灯笼白方块**：径向渐变的透明边缘落在方片边界，加法混合下露出白色方块。把渐变透明度压到 0.34 处归零，缩小像素尺寸并下移挂点。
- **S3 白色长条**：点火烟花的部分火星寿命过长，慢速火星停在镜头和人物之间，形成白色块。给点火事件单独设 0.45–0.75 秒寿命；闪光灯只让 `flash_size ≥ 1.0` 的事件驱动，照射范围从 70 缩到 34 米。
- **S8 切头**：抬高机位、下调视线，让两人的肩和头都留在画面内。
- **S6 招牌**：抬高南侧机位后招牌仍在两人中间；再往东绕会撞进树干，已放弃。现在把招牌当作祭典场地的前景，不再追求完全避开。
- **S6 晴天娃娃挡镜头**：榉树枝上按剧情挂着七个晴天娃娃，中心约 `(4.0, 3.0, 7.0)`，半径 2.3 米。原机位推到 `z=6.6` 时正好撞进其中一个，画面被白色娃娃占满约两秒。把推进终点收到 `z=5.3`，娃娃留在画面左上，不再遮住两人。新增 `S6_depart_late`（28.2 秒）静帧专门复查这一段。
- **ImmediateMesh 报错**：点火火星全部熄灭后，烟花仍在 2.9 秒的活动窗口内，`surface_end()` 在零顶点时被调用，日志刷出 52 条 `No vertices were added`。给 `film_fx.gd` 加顶点计数，零顶点时清掉空 surface，不再结束空面。重拍后日志为零条。

## 渲染与检查

画面在 1920×1080 的 `SubViewport` 里渲染，`RenderingServer.force_draw(false)` 后读回纹理存 PNG；窗口用 960×540、`-t --position 80,80`，保证 macOS 持续出帧。1344 帧用时 480.6 秒，状态 `ok`，`failures` 为空，日志没有 `SCRIPT ERROR`。

逐帧差异检查把相邻帧缩到 96×54 后求平均绝对差：最大的八次跳变正好是八个切镜点（5/9/14/19/24/29/34/39 秒，最大 37.59 在 19 秒切镜）；非切镜最大 6.35（51.0 秒）；11.08 秒点火闪光为 5.88，属于预期。20 对几乎相同的帧中，14 对在片尾全黑段，其余分布在片头淡入和切镜前后。亮度从 53 秒开始下降，55 秒后全黑。

## 配乐

用本机 MiniMax Music 3 MLX（`MiniMax-Music3-MLX-Serve-8bit`，30 步，44.1 kHz 双声道）生成日式夏祭纯音乐：钢琴起，太鼓和弦乐在 8 秒进入，27 秒起加入祭典律动，40 秒后铺开，52 秒后回到钢琴收束。

第一版（种子 4242，请求 56 秒）实际 56.065 秒，长度与画面一致，但 `art/tools/music_vocal_check.py` 标出 16–28 秒有人声风险：`stem_voice_max 0.60`、`mix_voice_max 0.14`。去掉长笛提示词后又生成了两版，模型分别在 27.667 秒和 34.830 秒自然结束，长度不够。最后保留第一版母带，用 htdemucs（MPS）分出四轨，去掉被判为 vocals 的整条分轨，再复检：`stem_voice_max 0.08`、`mix_voice_max 0.06`，没有 hot 秒。这条分轨在 16 秒前几乎静音，16–28 秒和 44–56 秒能量最高；复检结果见 `evidence/cinematic_20261019/music/`。

处理后的立体声为 −18.2 LUFS、−0.5 dBFS；编码时用 `loudnorm` 到 −16 LUFS，并在 55.7 秒做 0.3 秒淡出。成片实测 −16.4 LUFS、−0.9 dBFS。母带、去人声分轨和分离出的人声轨都保存在 evidence 的 `music/` 下。

## 成片编码

```sh
ffmpeg -framerate 24 -i evidence/cinematic_20261019/frames/%05d.png \
  -i evidence/cinematic_20261019/music/take1_novocal.wav \
  -filter_complex "[1:a]atrim=0:56,loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=55.7:d=0.3[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a aac -b:a 192k -ar 48000 -t 56 -movflags +faststart \
  evidence/cinematic_20261019/Harumachi_Next_Summer_56s.mp4
```

`ffprobe -count_frames` 读到 1344 个视频帧、24/1 帧率和 56.000 秒；音频 48 kHz 双声道、56.000 秒。整片重新解码无错误。

## 限制

- 没有景深、运动模糊和逐镜调色；画面质感仍来自游戏本身的渲染。
- 人物没有面部动画和口型，也没有手指动作；动作来自 G1 骨架，脚趾和头的细节有限。
- 声音只有配乐，没有环境声、脚步和灯笼点火音效。
- 成片是 1080p、24 fps，黑边直接渲染进画面；没有 4K 或宽银幕独立版本。
- S6 的空心招牌仍会从澪身前经过；晴天娃娃虽然不再挡镜头，仍在画面中部，作为剧情物件保留。
- 布料仍是源资产和游戏修正器的结果，不是独立布料模拟；这段短片没有证明长时间大幅度动作下的衣物表现。
- 配乐不是一次生成的完整 56 秒纯音乐：用了第一版母带，并去掉了人声检查判中的分轨。

## 复现

```sh
# 副本和电影脚本
python3 tools/cinematic_20261019/prepare_clone.py
CLONE=$(cat evidence/cinematic_20261019/clone_path.txt)
cp tools/cinematic_20261019/godot/*.gd "$CLONE/game/cinematic/"

# 关键帧
HARUMACHI_SAVE_DIR="$CLONE/save" timeout 420 ./tools/godot --path "$CLONE/game" \
  --resolution 960x540 --position 80,80 res://cinematic/cinematic.tscn \
  -- --film-stills="$PWD/evidence/cinematic_20261019/stills_v7"

# 逐帧
HARUMACHI_SAVE_DIR="$CLONE/save" timeout 1800 ./tools/godot --path "$CLONE/game" \
  --resolution 960x540 --position 80,80 res://cinematic/cinematic.tscn \
  -- --film-capture="$PWD/evidence/cinematic_20261019/frames"

# 配乐（请求 JSON 在音乐工程的 work/ 下）
python3 ~/.agents/skills/local-music/scripts/music.py generate \
  --request /Users/jack/workpath/research/music/work/film-harumachi-request.json \
  --out /Users/jack/workpath/research/music/outputs/film-harumachi

# 人声检查
VOCAL_CHECK_SITE=/tmp/film-vocal-site \
  /Users/jack/workpath/research/music/.venv-align/bin/python art/tools/music_vocal_check.py \
  evidence/cinematic_20261019/music/take1_novocal.wav
```

引擎固定 Godot 4.8-dev7（`./tools/godot`）。拍摄需要真实窗口持续出帧，不能用 headless；纯逻辑检查可以 headless。evidence 只保存在本地，不提交。
