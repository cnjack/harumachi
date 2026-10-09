# 做旧材质与背景修复（2026-10-01）

用户指出牌坊细节不足，并提供河边树背景模糊的截图，要求素材有使用多年的痕迹。原门楼、路牌、木桥和盆舞台的木材或屋面都是纯色；背景树精灵只有 475×204、274×166、206×168，却在离农园边界 3–4 米处铺到十几米宽。树图还有浅底边。门楼匾额文字在板中心外 3.5 厘米，木板本身厚 8 厘米，因此文字被板面遮住。

## 已改内容

- 内置 imagegen 生成做旧木纹、褪色瓦面、旧棉布和旧石材。木纹有灰化、细裂纹和磨损，瓦面有少量裂纹、缺口与积水痕迹，布面有清洗褪色和小旧渍；保留动漫平涂，去掉金属反光。第一版新瓦、新布和过于细碎的石纹没有采用。
- 七个模型换材质：`P_farm_gate`、`P_signpost`、`P_bridge`、`P_yagura`，以及上一轮新增的 `P_gondola`、`P_shop_wall_frame`、`P_store_sidepanel`。原木构件重新按长轴安排 UV；上一轮木构已有正确 UV，只替换贴图和色调。桥面的独立 `deck` 节点保留。
- 门楼文字移到板中心外 6.5 厘米，农园和主街两端均能看见匾额。文字仍由 Label3D 输出，不烤进贴图。
- 三张树丛重新生成，均为 1774×887，保留真实透明 alpha。农园平面树丛移到距离可行走范围至少 20 米的远层；近处由原有树和小型 3D 树提供深度。草地远景范围延伸到树根下面，避免底部露出浅色空隙。镇子树背景同样使用新图。

素材原图在 `art/references/materials/aged_20261001/`，提示词在 `art/manifests/prompts/materials/aged_20261001/`。运行用材质 JPG 在 `game/assets/textures/aged/`，树背景 PNG 在 `game/assets/textures/bg/`。没有按颜色抠图，也没有放大原来 206 像素的精灵充当高清图。

## 原图与提示词

| 原图 | 完整提示词 | 用途 |
| --- | --- | --- |
| `art/references/materials/aged_20261001/wood.png` | `art/manifests/prompts/materials/aged_20261001/wood.txt` | 灰化、裂纹与磨损木材 |
| `art/references/materials/aged_20261001/roof.png` | `art/manifests/prompts/materials/aged_20261001/roof.txt` | 褪色旧瓦 |
| `art/references/materials/aged_20261001/cloth.png` | `art/manifests/prompts/materials/aged_20261001/cloth.txt` | 旧棉布，乘以原来的红白颜色 |
| `art/references/materials/aged_20261001/stone.png` | `art/manifests/prompts/materials/aged_20261001/stone.txt` | 旧石脚与桥台 |
| `art/references/materials/aged_20261001/forest_a.png` | `art/manifests/prompts/materials/aged_20261001/forest_a.txt` | 透明成熟树丛 A |
| `art/references/materials/aged_20261001/forest_b.png` | `art/manifests/prompts/materials/aged_20261001/forest_b.txt` | 透明成熟树丛 B |
| `art/references/materials/aged_20261001/forest_c.png` | `art/manifests/prompts/materials/aged_20261001/forest_c.txt` | 透明成熟树丛 C |

## 工具和证明

`art/tools/texture_landmarks.py` 从本轮备份的原游戏 GLB 更新材质与 UV，保存可编辑 `.blend` 和原始 GLB 到 `art/models/raw/landmarks_aged_20261001/`。`game_export.py` 的 `preserve_parts` 模式保留物理坐标与各节点，不做归中、缩放、合并或减面。材质的颜色乘数写入 glTF，不涂改原图像。

`evidence/model_textures_story_20261001/geometry_check.py` 比较七个模型实际世界坐标的全部三角形，按 0.1 毫米量化后逐项哈希相同，节点名相同。153 个模型重新运行了倾角检查。

新增四项检查分别抓住：纯色木材和屋面、过小树图、近距离树背景卡片、埋进木板里的匾额字。各问题先在旧数据或旧位置上确认失败，修复后通过。本轮 PROPS 为 18 项，完整回归 338 项、0 失败，最终日志无 SCRIPT ERROR。证据在 `evidence/model_textures_story_20261001/`，包含用户截图、原文件、同镜头前后画面、几何比较、测试与导出记录。

剧情阅览另见 [story.html](story.html)，它不修改台词或存档；图片和字体内嵌，可单文件离线查看。

## macOS 包

`builds/HareMachi.zip` 已更新，623,211,635 字节（约 623 MB），Apple Silicon / Intel 通用，ZIP CRC 与深度代码签名检查通过。解压应用检查了字牌、背景与商店截图，再跑完整 `--autoplay` 1220.1 秒，Q05 完成、退出码 0、SQLite quick_check ok。旧包保存在 `builds/HareMachi-before-aged-materials.zip`，本轮没有更新线上 Web 试玩。
