# 家具圆角、曲面与反射落地（2026-10-14）

本轮把已确认的 8 张 imagegen 家具预览落实到场景模型，重点是桌沿圆角、椅背与座面弧度、家电结构、烤箱贴图和实际反射。画风继续采用干净的动漫色块与分段阴影，木漆、搪瓷、金属和玻璃保留各自克制的光泽。

没有新增付费 3D 生成，也没有调用 Hyper3D 或 Pixal3D。11 个现有 GLB 用 Blender 修改或重建，程序桌凳共用圆角网格；新增 2 张 imagegen 材质原图。模型目录仍为 264 件，配音仍为 436 条，引擎固定为 `4.8.dev7.official.c971f93e7`。

## 改了哪些模型

以下面数来自最终导出文件对应的 `game/assets/models/_stats/<ID>.json`。11 件合计 **294,908 个三角面**，是资产合计，不是单帧可见面数；`P_community_table` 已包含整桌 6 把椅子。

| 模型 | 实际变化 | 三角面 |
| --- | --- | ---: |
| `P_cafe_table` | 圆桌沿、两把椅子的弧背与浅弧座面、连续后背支撑 | 28,116 |
| `P_community_table` | 长桌圆角、6 把椅子的弧背和座面、连接构件 | 70,780 |
| `P_reading_chair` | 弧背、座面、圆润扶手与背部支撑 | 18,144 |
| `I04_shop_counter` | 木台面、柜体边缘与正面构件圆角；漆面、铜条分别反光 | 10,220 |
| `P_gondola` | 板边、立柱圆角，保留双面四层商品支撑位置 | 53,060 |
| `W17_display_shelf` | 三层板边圆角、货架支撑构件 | 14,084 |
| `I05_bread_shelf` | 四层板边圆角、货架支撑构件 | 17,296 |
| `W13_cedar_worktable` | 工作台面、框架与腿的多段圆角 | 15,744 |
| `I02_cake_showcase` | 柜体、玻璃框圆角；保留两层糕点与标签支撑 | 12,600 |
| `P_deck_oven` | 圆角外壳与门框、真实炉腔与通风孔、圆柱把手、旋钮刻度、玻璃 | 32,564 |
| `P_coffee_station` | 圆角机壳与台面、开放工作区、接水格栅、蒸汽管、空心杯和透明豆仓 | 22,300 |

椅子保留中央约 23 厘米宽的承托区与原来 0.48 米座高。弧面在离中心约 0.17 米处量得约 2.9 毫米高差，0.192 米处约 4.6 毫米；这些位置仍在倒角内侧，用来区分真实浅弧与只磨圆边缘。椅背在 0.36 米横向跨度内有约 13.6 毫米弓形深度，并有约 7° 后倾。中央承托、桌面及商品支撑没有随曲面一起凹下去。

程序家具由 `FurnitureForms.rounded_box()` 生成并缓存网格，接在 `PublicPlaceArt.bench()` 的顶板、腿和下层板上。顶板默认平面角半径 35 毫米、上下边半径 9 毫米，保留外包围尺寸、中央平面、台高和原有碰撞。工具屋、杂货修理桌、邮局、春家矮桌、照片比较桌和图书阅览桌均进入真实场景回归。

## 原图、UV 与可重复生成

9 件木家具保留原节点名、材质名和已有嵌入图片。曲面新增顶点的 UV 从原三角面插值转移，原有图集不重新生成；原模型没有嵌入图片的 W13 与糕点柜继续使用对应运行时材质，不虚构“原贴图”。脚本校验节点变换、座椅标记、脚印和各层支撑高度。对已有嵌入图片，清单记录导出前后字节一致。

两件家电重建了实际结构及其 UV，沿用未替换部件的材料用途。新增的 `oven_enamel_albedo.png` 和 `brushed_steel_albedo.png` 分别用于浅色搪瓷与拉丝钢，都是平光色图；反光不烘焙在图片中。搪瓷、控制面板、金属连接座、黑色密封条、石板、炉腔和玻璃仍为独立材料。游戏 GLB 将不透明零件按材质合批为烤箱 11 个、咖啡机 9 个网格节点，玻璃及豆仓保留独立节点；作者用 `.blend` 保留分件结构。

| 路径 | 用途 |
| --- | --- |
| `art/references/furniture_forms_20261014/` | 已确认的 8 张家具预览 |
| `art/library/furniture_forms_20261014/source/` | 9 件木家具的不可覆盖旧 GLB 源档 |
| `art/library/appliance_forms_20261014/source/` | 两件家电的不可覆盖旧 GLB 源档及来源摘要 |
| `art/tools/refine_furniture_forms_20261014.py` | 从源档重建圆角、曲面并转移 UV |
| `art/tools/refine_appliance_forms_20261014.py` | 从源档重建烤箱与咖啡机结构 |
| `art/models/raw/furniture_forms_20261014/`、`art/models/raw/appliance_forms_20261014/` | 可再导出的 GLB、作者用 `.blend` |
| `art/manifests/furniture_forms_geometry_20261014.json` | 木家具来源摘要、图片保留、尺寸和支撑量测 |
| `art/manifests/appliance_forms_geometry_20261014.json` | 家电来源、结构量测、材质、图片与输出摘要 |
| `art/manifests/furniture_forms_textures_20261014.json` | 两张 imagegen 原图的提示词、生成 ID 与目标路径 |
| `game/assets/textures/furniture_forms_20261014/` | 两张实际材质原图 |

重复运行必须读取上述 `source/` 档案，不能把本轮已细分的 GLB 当下一轮输入叠加细分。导出仍走 `game_export.py`，使用 `preserve_parts`、`preserve_origin`、`level:false`，保持场景原点和已量好的朝向。

## 为什么先前有参数却看不见反光

锁定版本的 Forward+ 在 `DIFFUSE_TOON` 分支中执行 `indirect_specular_light *= specular * metallic * albedo * 2.0`。木漆、搪瓷等材质采用 `METALLIC=0`，因此该分支会把间接镜面反射乘成零，仅增加 `SPECULAR` 不能恢复。该判断来自锁定提交的 [Forward+ 源码](https://github.com/godotengine/godot/blob/c971f93e7/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L2130-L2142)，不能泛化为所有版本或所有渲染器的行为。

本轮相关 shader 去掉 `render_mode diffuse_toon`，通过自定义 `light()` 保留分段漫反射，间接镜面走引擎原生粗糙反射路径。自定义光照还需显式输出直接镜面项；`furniture_reflection.gdshaderinc` 共用 GGX 分布、遮蔽与 Fresnel 计算。木材、家电、柜台漆面和糕点柜玻璃使用真实法线、视线、灯光、粗糙度与强度，不用固定 UV 亮斑或发光补偿。

木材仍按接触区控制磨亮、按结构区保持较哑的表面。已绑定原图的家具从单一原 UV 图读取细节，不再与方向不同的细木纹相乘，避免出现交叉纹。纸张、瓷器、布料和橡胶不套用木材效果。

原生同机位光泽开关差值记录在 `evidence/furniture_forms_20261014/gpu-reflection-controls.json`：咖啡桌最大 RGB 差 24、17,376 像素差值大于 3；烤箱为 50 / 57,832；工具屋为 18 / 51,394。它们证明材质开关进入了实际渲染；是否适合画风仍以原图复核为准。

## 回归与当前验收状态

新增 `furniture_form_checks.gd` 共 **32 项**，从导入后的真实网格及运行时实例读取证据：

- 11 件模型原有脚印、总高和贴地；9 件木家具的多段边缘，不能用平滑法线或单个 45° 倒角通过。
- 3 类座面的真实浅弧与中央座高、3 类椅背的横向曲率；桌面与 4 类货架各层真实支撑高度。
- 6 处程序桌面圆角、两件家电的圆角外壳、烤箱非退化 UV 面积及运行时原图/UV 变换保留。
- 实际场景材质有非零反射强度，且 `render_mode` 声明没有将非金属间接反射清零的 `diffuse_toon`。
- 超过 100 件实际生成的杂货、面包与糕点仍落在 4 类货架的真实渲染面上。

家电旧检查同步适配按材料合批：检查真实材质面积与冲煮头、蒸汽管、把手连接座等部位，不再依赖合批前的节点个数。大控制面板中央没有顶点，因此部位存在性用点到实际三角面的最近距离判断，不能只量最近顶点。检查数量未因合批而删减。

| 验收 | 当前结论 | 证据（位于 `evidence/furniture_forms_20261014/`） |
| --- | --- | --- |
| 旧版反例 | 原提交 `9b7aaa97091d8dcdcacc38a54e8d34a16f7df072` 上 32 项正常执行，19 项失败，退出码 1；无脚本解析错误 | `baseline-regression.json`、`baseline-regression-process.json` |
| 家具专项 | 32 项新检查与 44 项既有回归共 76 项通过，退出码 0 | `targeted.json`、`targeted-process.json` |
| 源工程原生家具图 | 54 张完成，退出码 0，无脚本或 shader 错误 | `native-final/manifest.json`、`native-final-process.json` |
| 源工程实际坐姿与店内全景 | 7 张完成，退出码 0；54 张缩图、12 张家具原图与 7 张坐姿/全景原图独立视觉复核通过 | `views/manifest.json`、`views-verified.json`、`source-visual-review.json` |
| 正常模式同机位新旧对照 | 旧版补拍 8 张完成，共 44 组正常模式新旧图可对照；光泽/磨损关闭图另计 | `before/manifest.json`、`old-native-verified.json`、`native-final/manifest.json` |
| 2,235 项独占全量 | 全部通过，退出码 0，无脚本或 shader 错误。首次仅烤箱 `_quality.json` 真实量测记录过期，使用原工具重测后完整复跑通过 | `full-suite.json`、`full-suite-process.json`、`full-verified.json`；首轮失败保留为 `full-first-stale-quality.*` |
| 解压桌面包 54 张家具图 + 7 张坐姿/全景 | 全部完成，退出码 0，独立视觉复核通过，无阻断问题；44 组正常新旧对照使用包内画面 | `package-native/manifest.json`、`package-views/manifest.json`、`package-visual-review.json` |
| 解压桌面包真实按键坐姿 38 项 | 全部通过，退出码 0；另复核 15 张过渡、落座、起身和恢复截图 | `package-seating/demo.json`、`package-seating-verified.json`、`package-seating-visual-review.json` |
| 解压桌面包完整演示 205 项 | 全部通过，退出码 0；Q05/Q15 完成、夏季收尾完成、驱动玩家瞬移 0 | `package-autoplay.json`、`package-verified.json` |
| 最新 ZIP 替换与摘要 | 已原子替换唯一 `builds/HareMachi.zip`，Intel/Apple Silicon 通用；SHA-256 `1d867ffdc56c70b4d3e5ade3498a05f10d0a27ec827f0783b16693c9f02efa86` | `package-installed.json`、`delivery.json`；临时冻结、导出和解压目录已删除 |

专项、独占全量、源工程原生运行和解压应用各阶段均确认默认 104 份存档、照片等文件摘要不变。静态截图不能替代保存恢复或输入流程测试；共用桌坐姿图未展示腿脚，咖啡桌遮挡部分膝部，本轮视觉报告没有把被挡住的位置算作已目视确认。Web 不在本轮验收范围。

## 复现顺序

以下命令在仓库根执行。本轮建模使用 **Blender 5.2.1**；先保留不可覆盖源档和两张色图，Blender 路径由本机设置，Godot 使用仓库包装器校验固定版本。源 GLB 已检查自包含图片与 Git LFS 跟踪；复现链只完成脚本和依赖的静态审查，**尚未在全新 checkout 实际重跑**，不能把它写成已验证的干净环境构建。

```bash
BLENDER="${BLENDER:-blender}"
"$BLENDER" -b --factory-startup --python-exit-code 1 \
  -P art/tools/refine_furniture_forms_20261014.py
"$BLENDER" -b --factory-startup --python-exit-code 1 \
  -P art/tools/refine_appliance_forms_20261014.py
"$BLENDER" -b --factory-startup --python-exit-code 1 \
  -P art/tools/game_export.py -- art/models/game_assets.json \
  P_cafe_table P_community_table P_reading_chair I04_shop_counter \
  P_gondola W17_display_shelf I05_bread_shelf W13_cedar_worktable \
  I02_cake_showcase P_deck_oven P_coffee_station
"$BLENDER" -b --factory-startup --python-exit-code 1 -P art/tools/level_check.py
python3 evidence/furniture_forms_20261014/verify_release.py import
python3 evidence/furniture_forms_20261014/verify_release.py targeted
```

变更烤箱后还须运行 `art/tools/model_quality_check.py -- game/assets/models game/assets/models/_stats/_quality.json` 更新真实量测，不能只修改旧报告时间。该脚本需要本地历史证据 `evidence/hyper3d_quality_20261001/original_bounds.json`；缺失时先恢复原边界记录。

本轮验收编排脚本 `evidence/furniture_forms_20261014/verify_release.py` 使用独立 `HARUMACHI_SAVE_DIR`，设置超时，检查退出码、脚本/shader 错误和默认存档摘要。`full` 记录整个游戏输入摘要，后续导出和包验收核对同一份源码。它是本地证据脚本，`evidence/` 不随 Git 提交。

```bash
python3 evidence/furniture_forms_20261014/verify_release.py native native-final
python3 evidence/furniture_forms_20261014/verify_release.py views
python3 evidence/furniture_forms_20261014/verify_release.py full
python3 tools/check_project.py
# 全量通过且源码保持不变后，逐项串行运行：
python3 evidence/furniture_forms_20261014/verify_release.py export
python3 evidence/furniture_forms_20261014/verify_release.py package-native
python3 evidence/furniture_forms_20261014/verify_release.py package-views
python3 evidence/furniture_forms_20261014/verify_release.py package-seating
python3 evidence/furniture_forms_20261014/verify_release.py autoplay
```

全量运行时不得并发启动另一个 Godot。原生窗口置顶，模型机位使用 `--furniture-finish-review`；坐姿及店内全景用 `--shots` 的 `form_shared_sit`、`form_cafe_0_sit`、`inhabited_cafe`、`inhabited_cafe_sip`、`inhabited_reading`、`inhabited_bakery`、`inhabited_store`。最终包通过全部检查和人工视觉审核后才能原子替换 `builds/HareMachi.zip`，随即清理临时导出、冻结工程与解压目录。
