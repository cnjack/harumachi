# 宣传片提示词

- `*-image.txt`：八张关键帧的内置imagegen实际提示词，采用edit/style-transfer。原生截图和生成图在`art/references/promo_20261015/`；人物镜头同时引用游戏头像。
- `*-action-v2-video.json`：最终八段书奇MiniMax H3动作请求。桥景目标4秒，其余各8秒；data URI以实际PNG路径代记，完整请求在本地工作目录生成。任务编号和实际源文件摘要在主片清单中。
- `*-video.json`：首轮被用户指出动作不足的请求，保留追溯，未用于最终主片。
- `music.json`：本地MiniMax Music3原始96秒纯音乐请求。
- `motion-direction-v2.md`：最终动作方向与场景意义。

主片清单为`art/manifests/promo_20261015.json`，独立实机版清单为`promo_20261015_native.json`。片尾`festival-endcard.png`由最终夏祭动画第191帧直接抽取，未经AI重画。
