# 现有模型的材质与光影研究、双场景 POC（2026-10-25）

这轮用面包房门前和湖畔木桥做独立实验：保留真实模型、位置与碰撞，比较原版、只改材质、只改光照／天空、两者合用。每处覆盖晴晨 08:00、晴午 12:00、阴天 12:00、雨天 15:00、夕照 17:20、夜晚 21:00。

用户追加要求使用 imagegen 指导方向，因此先从游戏截图生成两张四格方向图，再生成白天／黄昏／夜晚三张天空贴图，将后者真正接进 Godot。方向图不是游戏画面；它们改变的树冠密度、局部比例和构图细节不算实现成果。最终基线为 `8214c56`，保留当日新合入的深棕农场木材；初期浅木桥截图只保存在迭代证据中。之前被否决并删除的 `tools/lighting_poc` 没有恢复。

正常游戏入口不加载本轮脚本。桌面交付包与网站未重新发布，视觉效果仍待用户审看。

macOS 可双击仓库根目录 `open_material_light_poc.command` 打开独立演示；结束时按 Esc。脚本、候选 shader 与天空贴图均从三个正式导出预设排除。

## 1. 调研结论与项目现状

好看的材质首先要能分出“是什么”和“怎样使用”，其次才是表面纹理的密度。对白墙、纸、布、粗石使用宽而稳定的色面；给漆木、涂层金属、玻璃保留不同的反射宽度。让光影负责体积和时间，让贴图负责材料与局部痕迹，二者不要重复画一套太阳阴影。

代码审查发现两种做法并存：`HouseBuilder.toonify()` 会统一关闭镜面并设置粗糙度；`public_facade_finish.gdshader`、`painted_finish.gdshader` 以颜色细节为主；但 `furniture_wood.gdshader` 和玻璃已经有局部粗糙度与 GGX 反射。因此不能宣称项目完全没有 PBR，也不应全局换成统一塑料材质。当前农场桥还经过 `FarmTimber`，已有板材方向、深色涂层与局部使用痕迹。

本轮选择的是 **动漫漫反射 + 克制的材质反射**：主要受光仍是两层明暗，粗糙度、法线细节和反射只帮助辨认木材、布料和五金。纯写实材质球、满屏污渍和强 HDR 镜面都不符合 [ART_STYLE](ART_STYLE.md)。

## 2. 给已有模型补材质的可执行流程

### 先判断模型结构

| 实际情况 | 推荐做法 | 本轮如何处理 |
| --- | --- | --- |
| 部件已有独立材质槽 | 保留槽名，在导入后绑定外部材质；不用重新生成整件模型 | 橱窗木框、陈列架、布篷支架按真实节点筛选 |
| 多种材料挤在同一张 atlas | 在 Blender 按语义拆材质槽，或绘制 ID mask；原 UV 和 base color 尽量保留 | 面包房暂用已有颜色与空间范围作候选遮罩，尚不是可靠的通用分类 |
| UV 拉伸／没有 UV | 长木板沿板材展开；重复墙面用统一米制密度；复杂单体重新展开再烘焙 | 桥沿已有逐板方向采样，微凹凸用表面梯度，避免依赖缺失切线 |
| 轮廓太尖、厚度不对、玻璃没开洞 | 先修网格、倒角、厚度和独立玻璃；贴图不能补出真实轮廓 | 保留现有结构，将源资产差距列为后续项 |
| 高模雕刻与低模已有配对 | 烘焙切线法线、AO、粗糙度，留足 UV 岛边距，检查斜视接缝 | 本轮未新增高模烘焙，不把纹理推导凹凸称为真法线烘焙 |

Godot 支持外部材质与导入覆盖，适合避免 GLB 重导入覆盖手工配置；材质覆盖优先级应在绑定前核对。[Godot 高级导入设置](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/advanced_import_settings.html)

Blender 的烘焙目标需要有效 UV 和目标图像；法线、粗糙度、AO 与颜色可分别输出。只取颜色时不要把直接光、间接光一起烘进底色，岛边缘需要扩展以防 mipmap 接缝。[Blender Cycles 烘焙](https://docs.blender.org/UATEST/manual/en/4.5/render/cycles/baking.html)

### 每种贴图承担一件事

| 通道 | 内容与导入 | 常见错误 |
| --- | --- | --- |
| Base Color | 手绘固有色，颜色纹理按 sRGB 解码；避免固定阳光高光、方向性投影 | 在贴图上画亮斑后又让引擎加一次高光 |
| Roughness | 线性数据；暗值更平滑，亮值更粗糙；按触摸、擦拭、织物、涂层划分 | 所有部件统一 0.3，或全部设 1.0 抹掉材料差异 |
| Metallic | 线性数据；裸金属与绝缘体区分，完整油漆覆盖处通常按涂层处理 | 木框、帆布、塑料一起继承金属度 |
| Normal | Godot 所用 OpenGL +Y 约定；检查切线、镜像 UV 与绿色通道方向 | 把木纹颜色直接当法线 RGB，或用法线期待改变轮廓 |
| AO | 线性；缝隙与接触处局部使用，通常主要影响环境贡献 | 烘入大块太阳投影，再叠 SSAO 变成脏黑边 |
| Emission | 自发光的灯具、窗内发光区域；另配真正照亮周边的灯 | 仅把窗户变亮，墙和地面没有响应 |

若合并 ORM，Godot 采用 R=AO、G=roughness、B=metallic。材质数值和颜色纹理应分开处理；法线改变照明方向，不改变网格形状。[Godot StandardMaterial3D / ORM](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)

PBR 的价值是把材料响应拆清楚，不能照搬成写实外观。微表面粗糙度控制反射的分布，Fresnel 随观察角变化；这解释了为什么材质要用斜视移动镜头复核。[LearnOpenGL PBR 理论](https://learnopengl.com/PBR/Theory) 底色与金属／粗糙度的不同语义可参考 [Adobe PBR Guide Part 2](https://www.adobe.com/learn/substance-3d-designer/web/the-pbr-guide-part-2)。本项目的低反射数值属于美术取舍，没有声称通过物理测量校准。

### 当前可用的起始范围

这些是待调的风格化起点，不是材料的物理常数。先固定中性灯光与曝光，按正常游玩距离调到可辨认，再去检查晴雨昼夜。

| 表面 | 粗糙度起点 | 细节的空间位置 |
| --- | --- | --- |
| 粉刷墙、粗石、纸 | 0.88–1.0 | 墙根、拼缝、边角；少量低频色差 |
| 帆布 | 约 0.96 | 折线、张力方向、边缘缝线；细织纹很弱 |
| 室外深棕旧木 | 基础 0.86，接触面最低约 0.68 | 顺板材的纤维；顶面与侧面有差别 |
| 木窗框、木架 | 约 0.56–0.67 | 手摸边、承物面；不覆盖玻璃和面包 |
| 涂漆支架 | 约 0.43，metallic=0 | 用宽而弱的反光交代截面 |
| 玻璃 | 沿用现有透射与反射参数 | 能看到真实展示物，避免反光盖住内容 |

Catlike Coding 的复杂材质教程展示了同一表面混合材质和非均匀光滑度的意义；其凹凸教程说明高度、法线与空间变换的关系。两者面向旧 Unity，采用概念，不复制 API。[复杂材质](https://catlikecoding.com/unity/tutorials/rendering/part-9/)、[凹凸与法线](https://catlikecoding.com/unity/tutorials/rendering/part-6/)

## 3. 光影怎样有层次

先只留太阳和环境光，锁住曝光。调出受光与阴影的明度差，再给环境光冷色、太阳暖色；确定阴影方向、接触和远近关系之后，才增加 AO、反射、辉光。否则容易用整体提亮掩盖光源问题。

| 层次 | 任务 | 本轮选择 |
| --- | --- | --- |
| 太阳／月光主光 | 建立方向与清晰投影 | 保留原时间对应的旋转，仅改能量、颜色及阴影参数 |
| 天光 | 让背光面可读，形成淡紫蓝阴影 | 用受控环境色，晴午能量 0.48；不让整个模型被天空平均照平 |
| 接触阴影 | 压住窗框、木板连接与墙角 | SSAO 半径 0.42、强度 1.25，避免大范围脏圈 |
| 少量间接亮度 | 提供邻近表面的颜色联系 | SSIL 半径 2.0、强度 0.35；仅为屏幕空间补充 |
| 反射 | 交代漆面、五金、玻璃 | 面包房局部 ReflectionProbe，UPDATE_ONCE，切换方案后刷新 |
| 窗光 | 夜景焦点与对路面的照明 | 原窗口前一盏受限 SpotLight，暖色、带阴影，范围 4.5 米 |
| 远景 | 区分前后层次 | 深度雾按天气改变距离，保留天空色与前景对比 |
| 色调映射与辉光 | 留住亮部颜色，控制发光范围 | Filmic，曝光 1.0；glow 0.25、threshold 1.55、bloom 0 |

光的颜色不能代替阴影方向；阴影偏移过大还会造成脱离接触面的假象。光源角度、阴影滤波和偏移应结合真实尺寸调试。[Godot 灯光与阴影](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html)

SSAO 适合局部接触，SSIL 是屏幕空间的间接照明补充，不能当完整 GI；屏幕外信息缺失仍可能产生边缘变化。色调映射和 glow 要在主光关系成立之后调。[Godot 环境与后处理](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)

### GI、反射和雾的取舍

| 技术 | 适合的场合 | 这次是否采用 |
| --- | --- | --- |
| LightmapGI | 基本静态室内、稳定时段，可接受烘焙与 UV2 成本 | 未采用；跨六个时段不直接共用一张烘焙光照 |
| SDFGI | 大场景、动态太阳，需要间接光并能承担性能成本 | 未采用；不是本轮效果来源 |
| VoxelGI | 有限范围的局部空间 | 未采用 |
| ReflectionProbe | 建筑附近或室内的局部反射环境 | 采用一盏；不逐帧重算 |
| SSR | 水或光滑面上可见物体反射 | 未采用；不会补出屏幕外的岸树 |
| VolumetricFog / FogVolume | 局部光束、空间雾，需要 Forward+ 与成本预算 | 未采用；本轮是深度雾，不称为体积光 |

GI 的漫反射与镜面反射要分开考虑，按平台和场景选方案。[Godot GI 对照](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html) SDFGI 支持动态光，但并不把所有动态物体都纳入同等精度的遮挡和发光贡献。[SDFGI 限制](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html)

反射探针支持盒投影和更新频率；它是局部环境近似，不是精确平面倒影。[ReflectionProbe 教程](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html) 若后续做树荫光束，可以用局部 FogVolume 控制范围，另验时间重投影的拖影与帧成本。[体积雾教程](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html)

## 4. 六种天气与时段

参数按 `material_light_poc_lighting.gd` 定义，单位是当前项目的美术能量，不是实测 lux。

| 条件 | 太阳能量 | 环境能量 | 视觉目标 |
| --- | ---: | ---: | --- |
| 晴晨 08:00 | 1.70 | 0.44 | 斜向暖阳，清淡冷影，空气透明 |
| 晴午 12:00 | 1.85 | 0.48 | 清晰形体与蓝天，不冲白墙面 |
| 阴天 12:00 | 0.32 | 0.66 | 缩小直射差异，保留木／墙／布区分 |
| 雨天 15:00 | 0.12 | 0.48 | 冷环境、短能见度、真实雨滴和水面涟漪，橱窗偏暖 |
| 夕照 17:20 | 1.65 | 0.44 | 暖受光、紫蓝阴影，水体不整体变棕 |
| 夜晚 21:00 | 0.25 | 0.29 | 深蓝环境可读，面包窗口形成局部焦点 |

雨天遵守当前“地面干爽”的画风约束，没有给整条路涂镜面湿地。天气变化来自天空覆盖、主光强弱、雾、雨粒子、水面涟漪和窗光，而不只是一个全屏滤镜。真正的积水、局部润湿与雨遮罩需要另定美术范围后做独立方案。

## 5. imagegen 如何指导实现

两张方向图在 [art/direction/material_light_20261025](../../art/direction/material_light_20261025/README.md)。每张有晴午、雨天、夕照、夜晚四格。采用内置 `image_gen.imagegen`，没有调用外部付费 3D 服务；完整提示词与各图片 SHA-256 在 `art/manifests/prompts/material_light_*_20261025.json` 和 `art/manifests/images_codex.json`。

从生成图提取的是可以实现的规则：阴影保留冷色、外墙与木框反射分开、窗光真正照到周围、水体留有蓝绿底色、天空用清晰云团。三张天空图为 1774×887 PNG，后两张以白天图编辑，尽量保持同一云形。实际运行对云层高度作 UV 压缩，让大云团靠近地平线；水面使用对应映射，太阳仍由引擎按真实光向绘制。天空图没有烘入太阳圆盘，避免与太阳灯方向打架。

全 360° 接缝和所有镜头还没有做完整美术验收，不能仅凭提示词写“无缝已验证”。这些 LDR 天空图也不是物理标定 HDRI。

作为对照，Roystan 的 toon 教程把硬边明暗、镜面和受光约束的轮廓光分开；不应该让暗面在没有光时自行出现整圈白边。[Roystan Toon Shader](https://roystan.net/articles/toon-shader/) Godot 自定义 `light()` 中 `LIGHT_COLOR` 已含光能与 PI 因子，漫反射结果也不要再乘一遍 ALBEDO。本轮复用项目 GGX 函数，遵守这些约定。[Godot Spatial Shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)

Gotibo 的 stylized sky 示例提供云量、光散射和太阳关系的完整 shader，可作为后续程序云的对照；本轮为了保持绘制风格，采用生成贴图加现有天气层，没有移植其云采样循环。[作者发布的 Stylized Sky](https://godotshaders.com/shader/stylized-sky/)

## 6. 两个实际 POC 做了什么

**面包房。** 原墙面、砖脚、屋顶、布篷和木材底色保留。木框与可用几何区域获得独立粗糙度及很小的纤维凹凸，布保持高粗糙度；支架按涂层处理。新增局部探针与夜间暖窗光。遮罩仍有启发式成分，下一步应在源 atlas 绘制材质 ID 或拆槽，不能直接扩大到全镇模型。

**湖畔桥。** 保留 `FarmTimber` 新增的深棕木色、真实 UV 细节与逐板方向，仅对候选实例改变表面参数，并用 1.2 毫米量级的纹理高度扰动法线。没有换掉源 GLB、桥板或碰撞。水体复用真实岸线、底深、波形、雨圈与太阳／月亮位置；把天空反射从原先受太阳再次染色的通道中分离，减少过细波纹，保持水深颜色。

水的候选是风格化光学实验，使用 unshaded 路径组合深浅水、天空反射和方向高光；它没有实时桥身投影、岸树倒影，也不是物理完整的折射模型。桥墩附近仍靠深度／透明度交代接触。若要正式采用，需要补齐遮挡或验证混合光照路径，再检查钓鱼、近岸与俯视镜头。Roystan 水教程中的深度上色与岸边泡沫很适合这种拆解，但教程实现基于 Unity，Godot 的深度重建使用本项目既有代码。[Toon Water](https://roystan.net/articles/toon-water/)

两个场景仍存在源资产差距：树冠分组不如方向图完整；部分树叶与墙面纹理频率偏高；草地大块色面和远树层次有机械感。增加纹理或 glow 不能补出生成图的树冠轮廓。应先改代表性树的叶片团块、法线与颜色分组，再用同样六种光照复验；当前没有以灯光改善替代这项工作。

## 7. 运行与对照

```bash
# 如本机尚无导入缓存，先拉取 LFS，再 import。
git lfs pull
./tools/godot --headless --path game --import --audio-driver Dummy

# 现有 screen 0，静音、隔离存档。默认复查窗口 15 分钟超时。
python3 tools/material_light_poc.py review

# 1 / 2 切场景；左右切时段；空格切四种方案；Q/E 旋转；R 复位；Esc 退出。

# 两处 × 六种时段 × 四种方案，生成 48 张真实截图和滑动对照页。
python3 tools/material_light_poc.py capture

# 不限帧短样本只看实验成本，不能替代正式游戏的 90 秒持续性能对照。
python3 tools/material_light_poc.py capture --out evidence/material_light_poc_20261025/performance \
  --conditions noon,night --modes baseline,combined --uncapped --sample-frames 300
```

默认输出 `evidence/material_light_poc_20261025/final/index.html`。图库把实拍四路对照与 imagegen 方向图分开显示。`manifest.json` 记录实际引擎、像素尺寸、出帧数、时间与几何签名；`material-bindings.json` 列出修改表面；`materials.json` 是加载场景的材质盘点。默认存档与照片在运行前后按 SHA-256 比较。

新增入口 `material_light_poc_entry.gd` 先加载真实主场景，再停止玩法调度，用显式天气、光照与远山刷新建立固定观察条件。它与普通跑图有所不同：不测 NPC、输入、完整 GI 动态或游戏长时间负载。修改只作用于复制的材质和环境；源 shader 衍生位置用唯一 token 检查，源文件变化时会报错而非静默替换错误位置。

## 8. 本轮验证与采用边界

最终结果记录在本地 `evidence/material_light_poc_20261025/verification.json`。相关回归共 91 项通过（环境 35、材质 40、农场木材／金鱼 16），无脚本和 shader 错误；项目源码检查通过。临时 macOS PCK 实际挂载列出 4,935 个文件，主场景存在，候选素材／脚本／shader 为 0；临时包已删除。Windows 和 Web 只更新排除配置，未做导出验收。初期 `pilot`、`round1`、`round2`、`round3` 是迭代记录；`round1` 的类型错误已修，`round2` 仍有冻结玩法后远山未刷新的问题，二者都不作为最终对照。最终矩阵在同步新基线、刷新远山和调整天空之后重新生成。

本机现有屏幕、Apple M5 Max、Forward+、原画质 1600×900 的 48 张最终截图均连续推进 60 帧，约 60 FPS（有意限帧）。另关闭垂直同步和 FPS 上限，逐配置采 300 帧，GPU 单帧中位数如下。它们是固定镜头的短样本，不代表实际玩法、移动镜头、耗电或持续温度。

| 场景／时间 | 原版 GPU ms | 合用候选 GPU ms | 原版→候选 FPS |
| --- | ---: | ---: | ---: |
| 面包房晴午 | 3.289 | 3.930 | 244.1 → 233.9 |
| 面包房夜晚 | 3.291 | 4.025 | 268.7 → 173.8 |
| 湖桥晴午 | 2.919 | 3.041 | 318.8 → 240.1 |
| 湖桥夜晚 | 2.932 | 3.045 | 316.4 → 306.3 |

面包房候选增加了 SSIL、局部探针和窗光，总成本高于基线；不能从 GPU 中位数推断所有帧都只增加同样时间。夜景候选 GPU P95 为 6.025 ms，也不能把这次短测称为稳定性能达标。首次取消 FPS 上限仍被 120 Hz 垂直同步限制的记录保存在 `performance-vsync-on/`，不用于这张表。

图库在内嵌浏览器实际检查了场景、天气、模式和滑动分隔线，图片均正常加载，控制台无错误。原生退出仍有 7 个 Texture RID 清理警告，与早期基线运行相同；没有脚本或 shader 错误。夜间深棕桥仍偏暗，源树冠分组和草地色块仍需美术复审。

正式推广顺序建议为：先选定色光方向与一类代表材质，完成源材质槽／ID mask；然后补水的遮挡与远景树团块；再分别做原画质、均衡、节能档位的持续性能和移动镜头验收。只有用户认同画面、且这些检查通过后，才把选定部分接进正常时间天气系统。当前提交的是研究资料、候选天空素材和可复现工具，不是已获美术认可的全镇升级。
