# 3D 素材库与游戏接入

当前素材目录由build_asset_library.py生成，catalog登记596项来源/候选/游戏资产，游戏assets/models共有192个GLB。当前引擎读tools/godot-version.json；下方日期验收的旧包/固定工程路径是历史记录，已按builds保留规则清理。


更新：2026-10-05。素材室把项目导出、免费来源和人物原稿放在同一个可检索目录里，原文件与游戏版本分别保留。当前目录由脚本扫描生成；数量以网页与 `catalog.json` 为准。

## 打开素材室

在仓库根目录运行：

```bash
python3 art/tools/asset_library_server.py --port 8787
```

打开 <http://127.0.0.1:8787/art/library/>。按树木、植物、草地、人物等分类筛选，或搜索模型名、来源、游戏 ID。右侧可以拖动旋转、滚轮缩放、切换原始与卡通材质、显示线框、自动旋转和重置镜头。人物集合另外提供动作、骨架与原稿参考，具体制作记录见 [七人人物制作与验收](CHARACTER_ROSTER_APOSE_20261005.md)。服务只监听本机，关闭终端后停止；不需要联网加载 Three.js。

缩略图由实际网格渲染，三维预览读取实际 GLB/glTF。浏览器里的光照与卡通材质只用于检查，叶片风、玻璃和衣物运行效果以 Godot 实景为准。尺寸显示 X × Y × Z（米）；候选源文件尚未统一尺寸。

GLB 可以直接下载。Quaternius 的源 glTF 依赖同目录 `.bin` 与 PNG，按钮下载完整 ZIP，不能只取一个 `.gltf`。原稿的来源、许可、文件位置、面数、透明裁切、内置动画和游戏映射均保存在目录条目中。“已接入”表示已登记为游戏导出资产；实际摆放或加载入口另列在“接入与使用”中。

## 内容与许可

| 集合 | 本地内容 | 使用边界 |
| --- | --- | --- |
| Quaternius MegaKit Standard | 68 个 glTF，原始 ZIP、贴图和 Standard 许可 | CC0-1.0。免费层是 68 个，不包含收费 Source 工程、Godot 风动画或完整 116 个模型 |
| Kenney Nature Kit | 下载包实际 329 个 GLB，原始 ZIP 与许可 | CC0-1.0；轮廓简洁，适合远景和布局 |
| 游戏资产 | 当前 `game/assets/models/*.glb` | 项目制作及生成素材依各自来源条款；不能把整个集合标成 CC0 |
| 人物角色 / 人物原稿 | 当前骨骼导出与保留的来源原稿 | 项目人物与生成服务条款；静态原稿和可播放动作分别列明 |
| 院子老树 T05 | 独立自制主体与生成贴图 | 项目自制资产，生成素材按服务条款；不是免费包中的模型 |

作者链接、版本范围、下载证据见 [免费植被调研](FREE_FOLIAGE_20261004.md)。原许可保留在 `art/models/raw/free_foliage_20261004/<来源>/unpacked/`，下载摘要在各自 `provenance.json`。KayKit 与 Quaternius Ultimate 在调研中列为候选，当前目录没有声称已下载这些包。

## 已适配的植被

| 游戏 ID | Standard 源模型 | 高度 | 用途 |
| --- | --- | --- | --- |
| T01_courtyard_tree | CommonTree_1 | 6.5 m | 普通道路与边缘树 |
| T02_summer_tree | CommonTree_3 | 8 m | 高树与背景层次 |
| T03_round_ginkgo | CommonTree_5 | 7.5 m | 圆树冠。ID 为历史名，不表示源模型植物学上是银杏 |
| T04_slender_cedar | Pine_3 | 10 m | 林缘针叶树，历史 ID 保留 |
| M12b_shrub | Bush_Common | 0.75 m | 灌木，保留来源的红叶装饰色 |
| M12d_flower_bush | Bush_Common_Flowers | 0.85 m | 花灌木 |
| V01_fern | Plant_1 | 0.38 m | 花坛、草地的小植物；ID 为游戏语义 |
| V02_wildflowers | Flower_3_Group | 0.4 m | 成簇野花 |
| V03_grass_clump | Grass_Wispy_Short | 0.28 m | 地面草丛 |

配置是 `art/library/integration.json`，游戏布局在 `layout.gd` 与 `WorldBuilder._build_nature_accents()`。中央老树用独立的 `T05_old_shade_tree`，普通 CC0 树不再承担参考图里的主树。还原方法与实景见 [院子老树](HERO_TREE_20261005.md)。

适配时以米制缩放，底部归零；按材质拆开 `Trunk_*` 与 `Foliage_*`。保留 UV、PNG 原生 alpha 和叶片双面；移除原 PBR 法线、金属与粗糙度贴图，进入现有动漫光照。树干只做极轻微整体摆动，叶片单独摆动与轻颤，alpha scissor 截去透明背景。草花作为地表点缀，不能每个草叶都创建物理碰撞。

## 接入另一个候选模型

1. 核对作者和许可，在 `integration.json` 中增加 ID、源文件名和目标高度；不要覆盖原包。
2. 运行整理和导出。路径有空格，Blender 参数必须加引号。

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
"$BLENDER" -b --factory-startup -P art/tools/integrate_free_foliage.py -- V01_fern
"$BLENDER" -b --factory-startup -P art/tools/game_export.py -- art/models/game_assets.json V01_fern
"$BLENDER" -b --factory-startup -P art/tools/level_check.py
```

`game_assets.json` 同时登记 ready 原稿、来源 URL、许可、`asset_library_id`、`preserve_parts` 和 `image_format: AUTO`。含透明叶片不能强制 JPEG。有 trunk/foliage 部件的树才套对应风权重。

3. 通过 `WorldBuilder.spawn()` 放入场景，留下 `model_id`；根据实际地形调用 `rest_on_terrain()`。树干需要简单碰撞，补的碰撞体必须标记 `model_part`。位置、根部净空与交互点一起调整。
4. 使用tools/godot指定的Godot4.8-dev7跑import，再跑相关检查和近景截图；完整测试必须与其他 Godot 实例分开。数值合格仍要看实际贴地、剪影、透明边缘和玩家比例。

```bash
GODOT=/Users/jack/workpath/godot/tools/godot-4.8-dev7/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path game --import
# 用 run_evidence_command.py 的硬超时封装下面的测试命令
"$GODOT" --headless --path game res://scenes/tests.tscn -- --only=foliage-library
"$GODOT" --headless --path game res://scenes/tests.tscn -- --only=placement
```

## 更新索引与预览

```bash
python3 art/tools/build_asset_library.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P art/tools/render_asset_library.py -- 0 1
```

第二条只重渲染变更文件。大批量可分成 0/4、1/4、2/4、3/4 四个独立 Blender 进程。`catalog.json` 自动生成，不手工改；列表数据来自游戏配置、来源包和人物 roster。新增素材应先补来源记录，再重建索引。

目录字段：`id` 唯一 ID；`path` 原文件；`preview` 实际网格缩略图；`license`/`source`/`license_path` 来源；`bundle_path` 多文件包；`game_ids` 或 `library_source` 双向映射；`recipe` 接入例子；`uses` 直接使用入口；`triangles`、`alpha`、`animations` 技术信息。来源包不能改成游戏导出路径，两种版本需分别追溯。

验证与截图放在 `evidence/asset_library_20261004/`；原始 68 模型的 Godot 加载证据在 `evidence/free_foliage_20261004/godot-probe/`。

## 本轮桌面包验收

最终冻结工程为 `builds/hero-tree-final-source-20261005/game`，661 项全量通过，无 SCRIPT ERROR。解压通用应用专项试玩 41.34 秒通过，三只猫 E 喵叫、司机对话、停车、覆盖确认和第 4 槽读取均通过；六份槽位快照摘要有效。完整剧情 329.65 秒完成，44 张截图，Q05 完成，退出码 0；SQLite quick_check 为 ok，v4 当前与前次快照摘要有效。 默认 `builds/HareMachi.zip` 已更新，日期包为 `builds/HareMachi-hero-tree-20261005.zip`，1,568,207,066 字节，SHA-256 `f2a8c18459ba53fb964104d0da4c1ea22ec8858b39ce46a1d429dcf6f06af5df`；旧版保存在 `builds/HareMachi-before-hero-tree-20261005.zip`。包的 CRC、签名和 Intel / Apple Silicon 双架构检查通过。总证据为 `evidence/asset_library_20261004/verification.json`，release_ready=true。

## 七人人物库（2026-10-05）

“人物角色”显示七个当前游戏 GLB，“人物原稿”保留对应七个静态来源。人物可切换原 11 动作与 reference、暂停、调速、显示骨架；下载包括正式 GLB、原稿、正背参考与 Blender 作者文件。实际测得的手臂下垂角和骨数分别列明。浏览器采用四权重预览；空、澪的袖口次级运动以 Godot 实际画面为准。作者副本打开为参考姿态，NLA 动作全部保留，选择一条轨道取消静音后播放。详见 [七人人物](CHARACTER_ROSTER_APOSE_20261005.md)。
