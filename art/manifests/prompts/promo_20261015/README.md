# 宣传片提示词

- `*-image.txt`：八张关键帧的内置imagegen实际提示词。原生参考图及生成图在`art/references/promo_20261015/`；人物镜头同时引用游戏既有头像。
- `*-video.json`：书奇H3请求，图片data URI替换为对应PNG名称，以免重复保存二进制。任务类型、镜头描述及生成参数保持原请求。
- `music.json`：本机MiniMax Music3的原始96秒纯音乐请求。

动画主片镜头清单为`art/manifests/promo_20261015.json`；已完成的90秒实机版为`promo_20261015_native.json`。

人物动作修订见`motion-direction-v2.md`和`festival-action-v2-video.json`。首轮桥边/夏祭只有轻微动作与镜头推进，用户已否定这种效果；旧六段批次已停止继续提交，主片清单须在动作试片验收后更新。保留旧提示词用于追溯，不把旧片段视为已通过的动画交付。
