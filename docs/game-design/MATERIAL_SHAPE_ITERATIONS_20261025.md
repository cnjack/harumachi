# 树形、草叶与建筑：第 5–8 轮（2026-10-25）

在 `aff2b49` 的双场景 POC 上继续四轮，重点由光照参数转向源模型。仍以原来的两张 imagegen 天气方向图为参照；本次另用 imagegen 生成阔叶与杉树叶簇透明图集，原图直接进入材质，没有重绘或修饰游戏截图。此前教程与第 1–4 轮见[研究记录](MATERIAL_LIGHT_RESEARCH_20261025.md)和[前四轮](MATERIAL_LIGHT_ITERATIONS_20261025.md)。

这是可运行、可恢复的独立候选。默认游戏、碰撞、原模型文件、桌面包和网站保持原版本。改进集中在树冠轮廓、草叶体积、窗框／檐口／布篷的实体结构和玻璃受光；远林仍重复使用四种树型，屋顶、花箱、推车等仍有原生成模型的粗糙处，尚未达到 imagegen 图的整体完成度。

## 四轮实拍

| 轮次 | 修改与实拍后发现的问题 | 主机位原生对照 |
| --- | --- | --- |
| 5 | 从现有四种树保留树干，重建叶簇；制作弯曲草叶。初拍发现叶簇像分离圆球、细叶碎点多，草的 UV 经 glTF 翻转后错误地让根部参与风摆。 | 两场景 × 晴午／夜晚 × 原版／合用，8 张 |
| 6 | 叶簇相互衔接，放大叶形，修正草根 UV；重建面包房窗框、檐口与连续布篷。近景发现檐板方向错误、旧布篷残片、二楼旧窗条叠在新窗格后面及墙面碎三角。 | 晴午／阴天／夜晚，两模式，12 张；另有 8 张近景 |
| 7 | 增加树冠内部体积、冠层法线与成组明暗，重新生成简洁杉叶图集；草分成长叶和低草；修正檐板旋转，清理旧窗格和布篷，补连续墙板。远景测试暴露了内部冠层标记的导出问题，修好后重拍；近景进一步发现按面中心删旧墙会留下边界缺口。 | 晴午／雨天／夕照／夜晚，两模式，16 张；另有 8 张近景 |
| 8 | 先切开修补边界再删除旧面，保留插值 UV；补实体百叶窗、玻璃天空反射、不同高度草簇及有限范围高草投影。叶图集显式生成 mipmap 并保持透明覆盖，避免远处细叶继续闪成噪点。 | 六种天气时段 × 四模式，48 张；补拍近景和两侧视角 |

证据在 `evidence/material_shape_refine_20261025/round5` 至 `round8`。每轮保留原始 PNG、采样和进程记录、源码与候选资源快照。`round6-close`、`round7-close` 保留当时的细节检查；失败或被否决的内部尝试另留在 `before-*`／`preview` 目录，不混入最终结果。

图库默认左侧为第 4 轮，右侧为第 8 轮。可以比较正式原版、首版及此前轮次，也可以选择窗框、布篷、草叶、杉树与侧面机位。仅允许选择该机位实际拍过的天气和模式。风、水波、雨滴的相位可能不同。

## 源模型与材质

- 可编辑源文件：`art/library/material_shape_poc_20261025/authoring/`，包含四种树、15 种草簇变体和面包房的 `.blend`。
- 候选 GLB、两张透明图集和导入设置：`game/assets/material_light_poc/shape/`。
- 生成器：`art/tools/build_material_shape_poc.py` 与 `material_shape_bakery.py`；来源、面数、参数、源文件与候选摘要在 `art/manifests/material_shape_poc_20261025.json`。
- imagegen 的原始提示词与输出摘要登记在 `art/manifests/images_codex.json`。两张图集均为实际 1254 × 1254 RGBA，不把请求的尺寸当成实际结果。

四种树分别有 17／21／21／27 个空间叶簇，每簇由内部低频体积和不同朝向的叶片组成。法线按树冠与叶簇共同调整，减少每片叶都单独发亮的碎点；近处有叶片轮廓，远处保留冠层体积。四种源树干的顶点位置集合逐一核对，未改动。实际 POC 对 6,824 个树实例使用候选叶冠，原实例位置与数量保持。树 GLB 为轻量运行时绑定资源，完整材质保留在可编辑源文件中。

草簇有 5 类、每类 3 个变体，每簇 19 片较高草叶加 31 片低草。叶片有曲率、收尖和中间折面；glTF 导入后根部的风权重为零。近岸补草从第 4 轮的 3,615 丛增加到 4,935 丛，继续避开湖水、道路和桥头。只给近处 17 个高草批次开启投影，并抬起阴影中的最低漫反射，避免细碎的全黑点。没有改变正常游戏的草预算或性能档位。

面包房保留原模型的大部分屋顶、砖墙、原纹理和底层真实陈列空间。31 个独立部件补齐窗框、分格、窗台、滴水檐、山墙檐板、连续布篷、波浪下摆、缝边、支撑杆、墙板和百叶窗。窗框倒角为 6 mm，布篷厚 12 mm。二楼玻璃采样同一天空图集并随视角变化，夜间有暖色发光；这是玻璃表面方案，没有新建完整二楼房间。

替换墙面和窗面前，先在空间边界切开相交的三角面，再删除区域内旧面；切割保留 UV 插值。此前仅按三角面中心删除会连同区域外的墙角一起删掉，近景能看见三角缺口，最终源文件已改用切割后的边界。

## 教程落实与排错

| 一手资料 | 采用方式与限制 |
| --- | --- |
| [Blender Normal Edit](https://docs.blender.org/manual/en/4.5/modeling/modifiers/normals/normal_edit.html) | 采用树冠径向法线的思路，在导出时写入自定义法线；没有在所有叶片上强行使用相同的向上法线。 |
| [Godot 3D 抗锯齿](https://github.com/godotengine/godot-docs/blob/master/tutorials/3d/3d_antialiasing.rst) 与 [Spatial shader](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html) | 透明裁切保留阴影，MSAA 配合 alpha-to-coverage；纹理坐标使用 UV 乘实际纹理尺寸，抗锯齿边缘小于裁切阈值。实际运行验证使用项目锁定的 4.8-dev7。 |
| [Godot 图像导入](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) | 外部 PNG 默认可能仍按二维用途导入。显式启用 mipmap，保留 alpha test coverage，阈值与 shader 同为 0.35；运行时读取实际图像，确认两张图集各有 10 层 mip。 |
| [Godot ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html) | 检查过 shadow_mesh 的约束：它还用于深度预通道，必须保持源网格位置。本次没有用删掉低草的影子网格替换深度几何，而是限制真实高草投影的批次。 |

第 7 轮首次导出把冠层标记放在 `COLOR_1`，`COLOR_0` 是全白，shader 读不到标记，远处只剩枝干。最终使用独立的负 UV 标记区分内部冠层，并显式导出活动顶点颜色。每次加载校验 3,612 个内部冠层顶点和 1,500 个草根边缘顶点。

第 5 轮曾在 Metal 退出阶段产生空材质 RID 错误。POC 退出前先恢复原网格和材质，等待两次真实渲染提交，再释放场景；修复后重新拍摄第 5 轮。它与 headless Dummy 渲染器的既有错误来源不同，没有一并忽略。

每次截图之后先确认当前 mesh 仍是预期候选，再暂时还原原 mesh，核对原网格、所有已改 MultiMesh 的 buffer／变换、原碰撞身份与变换，最后恢复候选。建筑通过独立显示节点替换可见表面，保留底层橱窗和原碰撞。

## 复现

```bash
# 在仓库根目录；已有屏幕、测试进程静音、独立临时存档。
python3 tools/material_light_poc.py review
# 1/2 全景，3 窗框，4 布篷，5 草，6 杉树；方向键切时段，空格切模式。
# 完整主矩阵默认写入本次 round8；已有证据需保留时指定一个新目录。
python3 tools/material_light_poc.py capture --out /tmp/harumachi-shape-review
python3 tools/material_light_poc.py capture --scenes bakery_joinery,bakery_entry,lake_grass,bakery_cedar --conditions noon,night --modes baseline,combined --out /tmp/harumachi-shape-close
# Blender 中重建当前候选；不要用新生成器冒充历史轮次的精确源码。
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P art/tools/build_material_shape_poc.py -- --pass 8
./tools/godot --headless --path game --import
python3 tools/audit_material_shape_poc.py --out /tmp/harumachi-shape-audit.json
# 图库从 evidence 根目录提供，才能访问历史和补拍的相对链接。
python3 -m http.server 8787 --bind 127.0.0.1 --directory evidence
```

也可双击仓库根目录的 `open_material_light_poc.command`。所有候选资产与工具入口仍从正式导出排除。

## 验证结果

详细结果在 `evidence/material_shape_refine_20261025/verification.json`。源资源检查 50 项通过；用同一检查器回放历史数据，确实检出第 5 轮的 15 份草根 UV 错误、第 6 轮两根檐板的朝向错误及第 7 轮首次导出的冠层标记缺失。

全模型支撑检查中，面包房、阔叶树和草的支撑面为 0°。杉树整体凸包受低枝影响，原模型／候选分别报告约 35°／34°，不能据此认定树歪；另取实际根部最低 12 cm 的 97 个点检查，原版和候选支撑面均为 0°，且完整树干点位不变。面包房源生成器在临时目录重建的 GLB 与交付候选逐字节一致。

最终图库有 80 张原生截图：48 张主图、16 张细节、16 张左右侧面；这些运行均退出 0，原网格和碰撞摘要恢复一致，未出现脚本、shader 或其他原生 ERROR。每张图前至少实际渲染 60 帧。浏览器逐项检查 52 个可选组合、9 个历史选项和分隔线两端，图像均加载成功，控制台无错误。

五组相关回归共 139 项通过：环境 35、材质 40、树叶 8、地形 40、农园反馈 16。headless 日志仍有 292 条来自 Dummy 渲染器的既有空材质查询，仅按完整来源 `servers/rendering/dummy/storage/material_storage.cpp:264` 单独分类，其余错误为零。工作区 `tools/check_project.py` 的 8,328 项检查通过；默认 104 份存档和照片摘要保持一致。

临时 PCK 导出后实际加载并枚举 4,935 个文件，正式主场景存在，候选脚本、shader、模型及其导入缓存均未混入。临时工程和包已删除。导出仍报告本机 Adaptive 编辑器主题缺失和既有 x86_64 GDExtension 库警告，这不是新正式桌面包验收。

M5 Max、1600 × 900、Forward+ 原画质，白天与夜间每组实际采样 300 帧，关闭应用帧率上限与 VSync。以下为同一次串行测量的 GPU 中位数／P95（ms）：

| 场景 | 原版 | 完整候选 |
| --- | ---: | ---: |
| 面包房晴午 | 5.01 / 5.41 | 4.39 / 4.71 |
| 面包房夜晚 | 3.59 / 4.04 | 4.83 / 5.16 |
| 湖畔晴午 | 3.38 / 4.39 | 4.44 / 4.76 |
| 湖畔夜晚 | 3.42 / 4.33 | 4.37 / 4.71 |

这是单次静态短样本，受测量顺序、缓存和系统状态影响；不能按面包房晴午这一组宣布优化了性能，也不代表完整游玩或耗电表现。测量帧率约 112–117 FPS。曾误启动一份与侧拍重叠的性能采样，已停止并弃用；此表仅采用随后独占运行的 `performance/`。


本轮不包括全量 2,861 项、正式包完整演示、全镇推广、移动平台或 Web 渲染验收。原生退出仍有既有 7 个 Texture RID 警告和加载界面 anchor 警告；这些没有被描述成日志完全无警告。美术效果仍待用户审看。
