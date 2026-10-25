# 用户反馈原生对照

在独立临时工程中使用，不能改玩家存档或创建虚拟屏幕。通过仓库的 `tools/godot` 启动，设置独立 `HARUMACHI_SAVE_DIR`，使用 `--audio-driver Dummy`、现有屏幕、置顶窗口。动态检查加 `--graphics-profile=balanced --graphics-benchmark`，以保留均衡 60 FPS 预算并避免无焦点后台限帧。原生性能不能由固定帧率电影推断。

- 金鱼：将 `goldfish_capture.gd` 复制到临时工程 `scripts/tools/feedback_goldfish_capture.gd`，用 `--script res://scripts/tools/feedback_goldfish_capture.gd --write-movie <临时AVI> --fixed-fps 30 -- --out=<证据目录>`。固定随机种子并从实际小游戏开始一轮。
- 跑步：在临时工程里将原 `character_visual_qa.gd` 复制为 `feedback_qa_base.gd`，将 `running_capture.gd` 放到原 QA 路径，使用 `res://scenes/main.tscn -- --qa-characters --out=<证据目录>`，同时开启 `--write-movie` / `--fixed-fps 30`。它复用机位和落地夹具，用真实 Player 连续跑两段，各 3 秒。
- `encode.py --evidence <证据根目录> --stage <AVI目录>` 按 `before/after` 内的 `clip.json` 截取原生帧，输出单独视频和左右对照，依赖 ffmpeg 与 Pillow。AVI 命名 `fish-before.avi`、`fish-after.avi`、`run-before.avi`、`run-after.avi`。

完成后删除临时工程和原始 AVI，保留 MP4、截图、摘要和日志。当前实例与边界见 `docs/game-design/RUN_FARM_FISH_20261025.md`。
