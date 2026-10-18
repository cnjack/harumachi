# MotionBricks 独立人物动作 POC

2026-10-18追加：已在本轮修复后的七人源副本上新生成六组连续控制挑战，完成十条72秒1080p30影片与60项点评页。安装在游戏中的只有人物基础源姿态修复，实验动画仍完全留在POC。源/游戏575张画面、POC180张参考帧与2606项游戏完整回归分别验收；极限衣物与接触不合格项明确保留。见[本批结果](../../docs/game-design/ROSTER_FOUNDATION_MOTIONBRICKS_20261018.md)及[连续生成和录制命令](GENERATE.md#连续高难度组合2026-10-18)。

以下十动作、每条80秒及对应哈希/数量描述首轮POC，不是追加六章批次。

这套工具使用 NVIDIA 官方 Python 模型生成 G1 动作，再重定向到七份人物模型副本，在独立 Godot 工程中检查和录像。`game/`、正式人物 GLB、桌面 ZIP 和 Web 不在写入范围。外部源码、权重、环境和生成物放在忽略的 `art/poc/motionbricks_20261018/`；日志、摘要和审计放在 `evidence/motionbricks_poc_20261018/`。

## 官方来源与公开边界

- [官方项目页](https://nvlabs.github.io/motionbricks/)与[本轮固定源码](https://github.com/NVlabs/GR00T-WholeBodyControl/tree/45c03facbf848e0c743091b7d9c17952096ff908/motionbricks)：提交 `45c03facbf848e0c743091b7d9c17952096ff908`。
- 公开预训练是 Unitree G1：34 骨运动表示，输出映射为 29 个铰链关节和 36 维 MuJoCo qpos。官网 UE5 人体演示不能当作已经发布的人体权重或任意人物导出器。
- 此提交的 G1 动作菜单没有 `run/sprint`；工具拒绝 `run`，不把加速走路命名为跑步。坐、跳凳、取剑也不在本轮已生成菜单中。
- 源码遵循 Apache 2.0，权重遵循 NVIDIA Open Model License；权重使用及再分发以[固定提交的完整协议](https://github.com/NVlabs/GR00T-WholeBodyControl/blob/45c03facbf848e0c743091b7d9c17952096ff908/LICENSE)为准。第三方组件仍按各自许可处理。

本轮实际生成的十类如下，均为 seed `1234`、30fps、240 帧/8 秒：

| 正式 G1 mode | 展示名称 |
| --- | --- |
| `idle` | 站立 |
| `walk` | 行走 |
| `slow_walk` | 慢走 |
| `walk_left` | 向左移步 |
| `stealth_walk` | 轻步潜行 |
| `walk_stealth` | 低身潜行 |
| `injured_walk` | 负伤步态 |
| `walk_happy_dance` | 欢快舞步 |
| `walk_boxing` | 拳击步态 |
| `hand_crawling` | 手足爬行 |

七个人物为 `sora` 空、`ren` 莲、`haru` 春、`mio` 澪、`aoi` 小葵、`tanaka` 田中、`kazuko` 和子。同一批十条 G1 源动作映射到七人的比例、idle 校准和骨架，形成七人各十条试验片段；这不等于模型原生生成了七十条不同人体身份的动作。G1 没有提供的人体头颈、手指表现仍需目标人物姿态补足。

## 安装与权重

以下命令从仓库根目录执行。已有环境和 vendor 时直接使用；新环境需要 Python 3.12、Git、系统 `curl`，下载前阅读上面的协议。路径含空格时保持引号。

```sh
POC_ROOT="$PWD/art/poc/motionbricks_20261018"
VENDOR="$POC_ROOT/vendor/GR00T-WholeBodyControl"
EVIDENCE_ROOT="$PWD/evidence/motionbricks_poc_20261018"
mkdir -p "$POC_ROOT/vendor" "$EVIDENCE_ROOT"
GIT_LFS_SKIP_SMUDGE=1 git clone --filter=blob:none --no-checkout https://github.com/NVlabs/GR00T-WholeBodyControl.git "$VENDOR"
git -C "$VENDOR" sparse-checkout init --cone
GIT_LFS_SKIP_SMUDGE=1 git -C "$VENDOR" sparse-checkout set motionbricks
GIT_LFS_SKIP_SMUDGE=1 git -C "$VENDOR" checkout --detach 45c03facbf848e0c743091b7d9c17952096ff908
python3.12 -m venv "$POC_ROOT/.venv"
PY="$POC_ROOT/.venv/bin/python"
"$PY" -m pip install -e "$VENDOR/motionbricks" \
  torch==2.14.1 numpy==2.5.4 scipy==1.18.1 mujoco==3.16.0 \
  hydra-core==1.3.7 omegaconf==2.3.1 pytorch-lightning==2.6.6 \
  transformers==5.1.0 vector-quantize-pytorch==1.31.6 einops==0.8.2
"$PY" tools/motionbricks_poc/fetch_weights.py "$VENDOR" \
  --receipt "$EVIDENCE_ROOT/official-weights-reproduce-1.json"
```

以上核心版本已在本轮 macOS arm64 / Python 3.12.13 上实际运行；完整实际版本记录在生成 manifest。官方安装依赖仍由其 `setup.py` 解析，跨平台、跨依赖版本不承诺数值或文件逐位一致。

`fetch_weights.py` 从固定提交的 Git LFS pointer 读取 SHA/大小，经官方 `media.githubusercontent.com` 端点下载并核验，再替换 pointer；TLS 校验保持开启。它同时处理 G1 网格，供需要真实机器人网格的后续用途使用。当前生成路径只解析 XML/FK，源动作视频采用真实 34 骨代理，无需将机器人 STL 冒充人体。

四个模型文件合计约 2.34GB：VQVAE 285,607,244 字节、pose 1,639,126,476 字节、root 409,551,754 字节、G1 原型条件 7,761,041 字节。`generate.py` 在反序列化前再次核对它们与固定提交的完整 Git LFS OID/大小，不接受 pointer、缺失文件或不同权重。

## CPU 适配与复现

官方演示硬编码 CUDA。本工具绕过 `demo.utils` 的 GUI/键盘输入及 `exp_setup.test` 的训练设置，按相同 hparams 用 Hydra 实例化原网络、严格加载 state dict，再显式以 `device=cpu` 构造官方 inferencer/agent。输出中的 `cpu-source/` 复制官方 Python 包，仅四个文件五处 `torch.load` 增加 CPU `map_location` 和明确的旧 checkpoint 加载选项；保留逐文件 SHA 和 unified diff，不改网络、权重、采样或 converter 数学。

Matplotlib、XDG、HuggingFace 与 Torch 缓存限定在 POC 的 `cache/`。没有键盘、显示器或其他生成模型参与源动作推理。主机固定每 16/30 秒调用官方规划接口，idle 也重新规划，避免原交互演示 idle 缓冲耗尽后持续 hold。这个调度选择写进每条 JSON。

先做源码准备或格式测试，不启动推理：

```sh
"$PY" tools/motionbricks_poc/generate.py --out "$POC_ROOT/motions/prepare-reproduce-1" --prepare-only
"$PY" -B tools/motionbricks_poc/test_generate.py
```

两秒 smoke 含 .5 秒 idle、1 秒 walk、.5 秒 idle；完整批次默认每条含 .5 秒 idle、7 秒指定动作、.5 秒 idle。所有输出使用新目录，已有目录拒绝覆盖。

```sh
"$PY" -B tools/motionbricks_poc/generate.py \
  --out "$POC_ROOT/motions/smoke-reproduce-1" --actions walk \
  --duration 1 --lead-in .5 --tail .5 --threads 6
"$PY" -B tools/motionbricks_poc/generate.py \
  --out "$POC_ROOT/motions/reproduce-1" --seeds 1234 --threads 6 \
  --actions idle,walk,slow_walk,walk_left,stealth_walk,walk_stealth,injured_walk,walk_happy_dance,walk_boxing,hand_crawling
```

每种动作开始前独立 `agent.reset()` 并重设 Python/NumPy/Torch seed；统一中性参考来自初始化 idle。十个片段之间不承诺连续过渡，也不通过重复、加速、补帧或循环凑长度。失败保留 `.failure.json` 并使整体退出码为 1，不生成替代动作。

本轮 `motions/batch-v1` 实际十条均成功，共 2,400 帧。每条 root/pose/VQ decoder 各真实执行 16 次，总计每部分 160 次；每条 1 帧初始参考、62 帧 context、177 帧预测内部均在 NPZ 中单列。条件帧不是新的自由生成帧。CPU 生成段合计约 4.93 秒，模型加载约 3.16 秒；它们包含主机记录开销，只是本批测量，不是实时互动或其它机器性能保证。

## 人物副本、审计与录像

以下是复现入口；生成、重定向、审计和画面验收分别留证，不把“文件已写出”当作动作自然的证明。人物输入为本仓库已有的七个 `game/assets/models/CH_*.glb`，重定向只写 POC 副本。

```sh
"$PY" -B tools/motionbricks_poc/retarget.py \
  --motions-dir "$POC_ROOT/motions/reproduce-1" \
  --output-dir "$POC_ROOT/retargeted/reproduce-1" \
  --characters sora ren haru mio aoi tanaka kazuko
"$PY" -B tools/motionbricks_poc/audit.py \
  --source-dir "$POC_ROOT/motions/reproduce-1" \
  --retarget-manifest "$POC_ROOT/retargeted/reproduce-1/manifest.json" \
  --out "$EVIDENCE_ROOT/reproduce-1-audit.json"
"$PY" -B tools/motionbricks_poc/prepare_viewer.py \
  --retargeted "$POC_ROOT/retargeted/reproduce-1" \
  --project "$POC_ROOT/godot-reproduce-1"
"$PY" -B tools/motionbricks_poc/record.py \
  --project "$POC_ROOT/godot-reproduce-1" --all \
  --out "$EVIDENCE_ROOT/reproduce-1-movie" --check-only
```

真正录像由主任务统一调度：同一条 `record.py` 命令去掉 `--check-only`，按七个单人、三人组、四人组及源 G1 骨架代理分别录制。需要本仓库锁定的 Godot 4.8-dev7、`ffmpeg/ffprobe` 和持续出帧的现有显示环境；测试静音、隔离存档，不创建虚拟显示器，不加载游戏 autoload。完整七人审计与原生画面需单独验收；本 README 不用源数据通过替代这些结果。

## 原生录像的精确采样与点评页

正式展示工程为 `art/poc/motionbricks_20261018/godot-batch-v3`，录制输出为 `evidence/motionbricks_poc_20261018/recordings-v1`。十条源动作各有 240 个真实采样，录制模式将 AnimationPlayer 切为 `AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`，每帧按 `n/30` 秒调用原生 `seek(..., true)` 评估 GLB 动画，`_process` 不再额外推进。首帧为 0，末帧为 `239/30 = 7.966666…` 秒；240 帧以 30fps 播放得到 8 秒，不重复尾帧、不强制循环、不扩帧。交互预览仍使用自动推进。每次换动作独立 reset，不能把章节拼接说成模型生成的连续过渡。

Godot 默认会优化导入的动画关键帧。`record.py` 先在独立 COW 工程做一次 import，调用 `configure_imports.py` 只改该 COW 的七个 `.glb.import`，将 `PATH:AnimationPlayer` 的 `optimizer/enabled`、`compression/enabled` 和 `animation/remove_immutable_tracks` 设为 `false`；随后删除该 COW 自己的 `.godot/` 缓存并重新 import，防止复用已经简化的场景。选项修改记录在 `import-options.json`，第二次 import 日志与最终 sidecar 文本分别保存在 `import-exact-keys/`、`final-import-sidecars.json`。不改游戏模型或游戏导入设置。原生 journal 同时记录 AnimationPlayer 相对路径、实际时间与 17 个关键骨架变换，独立数值核验使用 `audit_native_playback.py`。

影片中的每个动作保留第 0、中间和末尾源采样的同帧原生 PNG，文件名以 `native-` 开头，收据为 `native-stills.json` / `native-stills-verification.json`。编码前用实际 PNG 对原始 AVI 的相邻帧 `[-2,-1,0,1]` 做 RGB 误差对比，将实测偏移写入 `movie-frame-alignment.json` 后才确定裁切范围，不假定引擎已完成帧计数等于 AVI 的零起始索引。`media-verification.json` 保存实际裁切范围、1080p30/BT.709 参数、帧数、SHA、严格完整解码命令及结果；成功验证后删除原 AVI/WAV，失败时保留已产生的证据。

七条单人片、三人横排比较、四人 2×2 比较和 G1 源骨架代理各按相同十动作顺序录制；每条 2,400 帧/80 秒。多人片每格拥有独立地面与镜头，侧面不会因横排人物互相挡住。地面使用衰减抗锯齿网格、视口 MSAA4X，爬行动作扩大镜头范围并向前偏 0.3 米；这些只改变观察夹具，不改动作。原生窗口使用现有 screen 0、`no_focus=true`、请求位置 `1640,50`，实际位置另存 `native-display.json`；Dummy 静音，不创建虚拟显示器。默认存档、正式 GD/模型/data/native 摘要前后比较及 COW 清理结果在批次的 `integrity-and-cleanup.json`。

首次原生截图检查可用新输出目录单独执行，不启动 AVI 或 FFmpeg：

```sh
"$PY" -B tools/motionbricks_poc/record.py \
  --project "$POC_ROOT/godot-batch-v3" --take solo-sora --stills-only \
  --out "$EVIDENCE_ROOT/native-stills-reproduce-1"
```

十条影片与验证收据齐全后，生成本地中文点评页：

```sh
python3 tools/motionbricks_poc/build_review_index.py \
  --recordings evidence/motionbricks_poc_20261018/recordings-v1 \
  --out evidence/motionbricks_poc_20261018/review-v1 \
  --findings evidence/motionbricks_poc_20261018/quality-findings-final.md \
  --verify-video-hashes
```

打开输出目录的 `index.html`，可按人物/组别与动作跳播，切正面、右侧、斜侧，慢放或约一帧步进。每个“人物/组别 × 动作”可保存判断、具体点评和视频时间；内容仅保存在本机浏览器，点击“下载点评 JSON”导出 `motionbricks-human-review.json` 供继续修订。页面默认链接 `quality-findings-v1.md`，明示 G1 来源、非官方原生人类模型、没有跑步模式、章节 reset 与“自然度尚未通过”。默认要求七条单人、两条多人和一条源骨架共十条齐全；重复 take 拒绝静默覆盖，未齐版本须显式传 `--allow-partial`。索引生成器只读已有媒体与收据，不启动引擎或媒体进程。

本轮实际 `review-v1/index.html` 正是以上命令生成，十条影片、100 个点评项和来源 SHA 的静态检查通过，实际链接 `quality-findings-final.md`。页面交互尚未通过真实浏览器验收：内置浏览器的 URL 安全策略拒绝 `file://`，仅允许 HTTP/HTTPS；没有换浏览器或启动本地服务绕过。隔离的 Node.js DOM/storage mock 仅核对人物/动作跳转、慢放/逐帧控制、点评隔离与 JSON 导出逻辑，不证明浏览器实际布局、视频播放或本地持久保存可用。检查结果见 `review-v1/static-integrity.json` 与 `review-v1/dom-mock-verification.json`。视频本身的原生渲染与严格解码验收分别留在录像收据。

正式七条单人片的独立数值核验汇总为 `evidence/motionbricks_poc_20261018/native-playback-audits-solo-summary-v1.json`：70 个片段、16,800 个原生帧、285,600 个关键身体骨世界变换样本，源帧 0–239 各出现一次，无尾帧重复。最大位置差约 2.202 微米、旋转差约 0.00014844°，通过 50 微米/0.02° 的严格导入与采样一致性门槛。这只核对 17 个身体骨与已录制 SHA 的 GLB 同时刻一致，不替代手指、衣物、接地或自然度验收。

## 数据与判断边界

- 每条 NPZ 保留 30fps、真实 34 骨名称/父级、最终 `qpos[T,36]`、同一组 qpos 官方 FK 的世界位置/四元数/单位 scale、统一 idle 参考及逐帧 generation ID。人体重定向使用 Y-up/Z-forward、米、xyzw；原 qpos 保留 MuJoCo Z-up/X-forward、根 wxyz。
- JSON/manifest 记录固定源码、原权重 OID、seed、模式、命令时间线、计划长度、pose tokens、真实神经调用和耗时。原型片段只是起止条件，不能拿原型回放冒充新生成。完整 schema 与四帧 mask 警告解释见 [GENERATE.md](GENERATE.md)。
- `foot_contacts` 是原始 `model_features` 的四个输出值，可能小于 0 或大于 1，且与过滤后的 qpos 分开。目标鞋底接地、脚滑和碰撞必须另测，不用这些数值直接判合格。
- 官方 dead Hand/toe 的默认世界旋转为 identity；重定向读取 active wrist/ankle 朝向。七人骨长、idle 校准、IK/接触锁定是明确的后处理，不冒充人体原生生成或新学习的模型能力。
- MuJoCo `mj_forward` 独立核对 FK 属于运动学核验，没有 `mj_step` 动力学稳定性、关节扭矩、布料碰撞或全身零自交保证。保留旧材质、权重和 morph 也不保证新动作衣服自然。
- 已有源审计 `evidence/motionbricks_poc_20261018/batch-source-audit-v1.json` 核对十条全部 30 个 active 关节与 240 帧，最大位置差约 0.329 微米、旋转差约 0.0000182°。这是坐标与序列化证据，不是艺术质量验收。后续人物审计和录像以各自新 receipt 为准。
