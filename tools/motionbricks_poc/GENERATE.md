# 独立 MotionBricks CPU 动作导出

只使用固定官方提交 `45c03facbf848e0c743091b7d9c17952096ff908` 的 Python 模型和 Git LFS 原权重，不写入游戏。模型网络、采样、姿态过滤和 qpos/FK 使用官方实现。

CPU loader 绕过官方训练设置和 GUI/键盘控制器，按相同 hparams 用 Hydra 实例化原模型，严格加载 state dict。它在输出目录复制一份官方 Python 包，只改四个文件五处 `torch.load` 的 `map_location="cpu", weights_only=False`；具体 unified diff 和源码摘要保存在 `cpu-source/`。旧版官方 PyTorch checkpoint 只允许来自固定仓库的原 Git LFS 对象；加载前逐个核对完整 SHA 和大小。没有更改权重或将其他模型替换进来。

依赖由主任务维护的 `art/poc/motionbricks_20261018/.venv` 提供。实际安装版本写入每轮 manifest；脚本首次模型导入前将 Matplotlib/XDG/HuggingFace/Torch 缓存限制在 POC 的 `cache/`。这些适配仅说明源码入口可走 CPU，真正可用性和时间必须由实际 smoke 证明。

准备源码，不导入 torch 或执行模型：

```sh
python3 tools/motionbricks_poc/generate.py --out /absolute/new-prepare-folder --prepare-only
```

一次 2 秒 smoke（由主任务启动）：

```sh
art/poc/motionbricks_20261018/.venv/bin/python tools/motionbricks_poc/generate.py \
  --out /absolute/new-smoke-folder --actions walk --duration 1 --lead-in .5 --tail .5 --threads 6
```

每条默认 8 秒/240 帧，含 7 秒动作和前后各 .5 秒 idle：

```sh
art/poc/motionbricks_20261018/.venv/bin/python tools/motionbricks_poc/generate.py \
  --out /absolute/new-batch-folder \
  --actions idle,walk,slow_walk,walk_left,stealth_walk,walk_stealth,injured_walk,walk_happy_dance,walk_boxing,hand_crawling \
  --seeds 1234 --threads 6
```

可追加 `walk_right` 与 `walk_zombie`。当前官方模式无 run，工具拒绝该 ID。默认逐动作保留失败诊断并继续，其余动作没有替代品；任一失败使整体退出码为 1。输出目录已存在时拒绝覆盖。

每动作导出 NPZ 与同名 JSON。NPZ 包含真实 30fps、34 个 `joint_names`/`joint_parents`、`qpos[T,36]`、`global_positions[T,34,3]` 米、`global_quaternions_xyzw[T,34,4]` 和单位 `global_scales`。34 骨的位置和旋转来自同一组最终 qpos 经官方 converter 的 FK；坐标为右手系 Y-up/Z-forward。原 qpos 另保留 MuJoCo 的 Z-up/X-forward 与根四元数 wxyz，不能直接混用两种轴。

`reference_qpos` 和对应的 `reference_global_positions/reference_global_quaternions_xyzw` 来自模型刚初始化的统一 idle，不会逐动作重新校准首帧。官方默认 dead Hand/toe 全局旋转为 identity，JSON 列出这些骨；人物手/脚朝向应从 active wrist_yaw/ankle_roll 取得。

`source_model_features` 与四个 `foot_contacts` 保留原模型的未标准化输出，但姿态过滤后的 qpos 可能不同。接触判断与重定向不得把原 ric positions 与最终 FK rotation 拼成一套姿态。contact 数值没有被改成新的物理接触真值。

首轮真实 CPU smoke 的 contact 是 414 维原始特征的第 410–413 列，逐值相同，范围约 −0.0216 到 1.0179。因此它甚至不是已经阈值化的布尔接触；脚滑、鞋底接地和人物重定向的接触条件仍须由最终 qpos/FK 或最终目标网格独立测量，不能直接用这些输出数值通过验收。

官方入口可能打印 `you are advised to provide all first 4 frames`。本工具提供的是官方 `get_context_mujoco_qpos()` 返回的完整四帧姿态。警告来自官方 `full_agent.py` 每次将第四帧 local-root 约束 mask 设为 False（第四帧有限差分速度未知），而 `motion_inference.py` 又宽泛地检查前四个 mask 全为 True；它只打印一次，所以外观像启动警告。此处保留官方 mask 和计算，不把未知速度伪标为有效来消除提示。四帧起始 context 是约束槽位的名称，不声称每个槽位的所有特征均已知。

JSON 记录 seed、正式模式、固定命令时间线、原权重摘要、真实 CPU 耗时、实际 pose/root backbone 与 VQ decoder 的 forward 次数、计划长度及 argmax pose tokens。每帧 generation ID 与 buffer role 分开记录初始参考、context、预测内部、结尾 style 约束及 hold；这些分类不把条件帧说成新自由生成。首轮 2 秒 smoke 实际导出 60 帧，三部分各调用 4 次，含 1 帧初始参考、16 帧 context 和 43 帧预测内部；模型加载约 12.17 秒，生成段耗时 0.128 秒包含主机记录开销，仅代表本次样本。

没有真实神经调用就拒绝导出；运动学 qpos 不冒充动力学仿真、人体原生模型或视觉验收。`--json-frames` 可另将全帧数组写进 JSON。
