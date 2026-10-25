# 材质与光影视觉方向（2026-10-25）

这两张图由内置 imagegen 从游戏实拍生成，用于讨论方向；不是游戏渲染，也不是已验收效果。四格依次是晴午、雨天、夕照、夜晚。桥的参考截图来自旧基线，最终 POC 已适配 8214c56 的深棕旧木，没有恢复浅黄色桥材。

- `bakery-direction.png`：面包房的暖墙、冷影、布篷和夜间窗光。
- `lake-direction.png`：木桥与水面、晴天蓝色反射、夕照高光和夜色。
- 提示词在 `art/manifests/prompts/material_light_directions_20261025.json`。
- 三张实际用于 POC 的天空贴图在 `game/assets/material_light_poc/`，独立提示词为 `art/manifests/prompts/material_light_sky_20261025.json`。
- 每张图的原图尺寸、SHA-256、生成工具与引用图片记录在 `art/manifests/images_codex.json`。

生成图改变了部分树冠、植物密度和建筑比例。实现时只取材质和光照关系；完整差距、教程与复现方法见 `docs/game-design/MATERIAL_LIGHT_RESEARCH_20261025.md`。
