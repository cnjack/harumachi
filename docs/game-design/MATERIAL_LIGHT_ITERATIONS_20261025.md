# 材质与光影的四轮优化（2026-10-25）

这是对首版双场景 POC 的继续优化，起点为 `f25b593`。仍使用两张 imagegen 方向图作为美术参照，实际效果由 Godot 4.8-dev7 / Metal Forward+ 渲染。没有对游戏截图做重绘、调色或合成。首版的教程研究、模型审查和参考图来源保留在 [研究记录](MATERIAL_LIGHT_RESEARCH_20261025.md)。

**交付是独立候选。** 正式入口、原始桥 GLB、存档、桌面包和网站不因这轮实验改变。效果接近参考图的一部分：天空、冷暖、木材受光、窗光、倒影及远近层次；树形、草叶和建筑源模型的细节仍有明显差距，不能把自动检查通过理解为达到 imagegen 水平或用户美术验收通过。

## 四轮实拍与取舍

| 轮次 | 看到的问题与实际修改 | 固定机位复拍范围 |
| --- | --- | --- |
| 1 | 天空有第二层云干扰，树叶主要依赖碎纹理。独立天空 shader 使用已有 imagegen 天空；树冠改为较宽的明暗组与冠层法线；湖岸增加 3615 丛草，地面使用米制大色块和轻笔触。 | 两场景 × 晴午／夜晚 × 原版／合用，8 张 |
| 2 | 第一轮云层接缝可见、草叶透光偏白，夜桥难辨。混合全景边缘，统一三个天空的云位置，降低草叶背光；桥的旧木纹强度减弱，局部反光加强；增加夜间填光和窗前暖光。 | 两场景 × 晴午／夕照／夜晚 × 两模式，12 张 |
| 3 | 湖水缺少岸树和桥的倒影，远林仍像平面剪影。增加带深度检查的屏幕空间反射，保留天空回退；水面接受桥身投影；远景 MultiMesh 树冠使用相同明暗方法。 | 两场景 × 晴午／雨天／夕照／夜晚 × 两模式，16 张 |
| 4 | 木桥硬直角不易产生边缘光，天空云团过大，阴雨与夜色还需统一。导出独立真实倒角桥；缩小并重排天空云团；调整阴雨雾色、夜间草木配色；月亮、月光及水面高光统一方向。 | 两场景 × 六种天气时段 × 原版／材质与局部细化／光照／合用，48 张 |

每轮目录为 `evidence/material_light_refine_20261025/round1` 至 `round4`。各目录含原始 PNG、采样统计、进程日志及存档摘要结果。第四轮另有内部预览，用于判断倒角、月光和天空构图。首版 POC 保存在原来的 `evidence/material_light_poc_20261025/final/`，没有用新图覆盖。

图库可以把正式原版、优化前 POC、前三轮中的任一可用版本放在左侧，与最新候选滑动比较。未拍过的早期天气组合不可选，避免把不同天气或轮次冒充同条件对照。风、水波、雨滴相位会变化。

## 从教程落实到代码

本轮继续查阅官方教程与 API；没有把未观看的视频列为已学习内容。

| 来源 | 采用的方法 | 本项目的处理 |
| --- | --- | --- |
| [Godot Sky shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html) | 使用方向与全景坐标；区分天空画面和环境辐照用途。 | 同一云布局切换白天、夕照、夜晚；太阳／月亮单独按主光方向绘制。只在切换条件时改参数。 |
| [Godot 深度重建教程](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html) | reverse-Z 深度经逆投影恢复视空间位置。 | 水面反射射线使用本引擎 Forward+ 的深度范围，没有照抄旧 OpenGL 公式。 |
| [Godot Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) | 不透明阶段后的颜色缓冲、mipmap 采样、透明内容缺失边界。 | 最多 48 步反射追踪与 6 次命中细化，屏幕边缘渐隐；失败时回退天空。没有宣称得到完整场景的平面反射。 |
| [Blender Bevel 手册](https://docs.blender.org/manual/de/5.2/modeling/modifiers/generate/bevel.html) | 小尺度真实倒角、角度限制、重叠钳制与法线处理。 | glTF 在法线／UV 边缘拆点，先焊接重合的几何顶点，保留 loop UV，再给实体边缘倒角，补加权法线；用实测尺寸、材质槽、原生截图检验导出。 |

### 木桥：材质与真实边缘

桥继续采用当前正式游戏的深棕色 `#694a35`，没有恢复早期浅黄木桥。原纹理、板材方向、顶面与立面的差异保留，降低过强的细纹干扰。倒角是独立文件 `game/assets/material_light_poc/P_bridge_beveled.glb`，由 `art/tools/build_material_light_bridge_poc.py` 生成。

五个原部件与材质槽一一对应。栏杆和梁倒角 12 mm，桥板 6 mm，桥墩 8 mm，3 段；曲面背板没有可倒的闭合锐边，保留其形体。原 GLB 的 SHA-256 为 `58f5d236c6b5667aeb968fa44dfe01b672241c705fc0d3ea9e61a8a319831937`，未修改。候选导出顶点由 4,134 增至 62,249，不能称作免费细节；该开销只用于一座 POC 桥。来源、各部件面数和候选摘要在 `art/manifests/material_light_bridge_poc_20261025.json`。

运行时只替换这五个节点的可见 mesh，原碰撞保持。每次拍照后临时恢复原 mesh，比较整个 WorldBuilder 的网格、MultiMesh 数量及碰撞身份／变换摘要，再恢复候选。清单同时明确记录当前画面是否用了候选桥，不能再把候选状态写成“几何完全未变”。新增近岸草放在独立 POC 节点下，数量单独报告；避开湖水、道路与桥头通路。

### 树冠、草地与墙面

树叶保留原透明轮廓，使用局部三维噪声形成较大的亮暗组，以冠层中心的径向法线控制主受光。混合树干／叶片网格通过颜色分区保留树干；这是现有材质上的候选遮罩，不能替代完善的源材质分区。远景 MultiMesh 只换材质，不改实例变换或数量。

地面和草叶统一低频色调，控制背光，夜间向较暗的青蓝色收敛。墙面仅对接近中性的灰泥区域轻微混合较低 mip 的纹理，减少细脏点；没有把整座建筑磨平。当前近地草叶仍有片状感，部分树冠仍受原网格剪影限制；雨天尚未加入专用湿路面层。

### 水面与光照

水面保持原深浅水、岸线、水波、雨滴逻辑，增加屏幕内真实物体的反射。复查还修正候选天空回退中的 90° 方位差：继承的水面用 `atan(z,x)+PI`，而 [Godot 天空实现](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/environment/sky.glsl) 的全景坐标以 `atan(x,-z)` 为起点；候选在缩放前减去四分之一圈，最后重新拍摄完整矩阵与两侧视角。转向镜头还暴露了全景经线处的一条细竖线；原因是 wrap 坐标的隐式导数选到过度模糊的 mip，最终用修正周期跳变后的 `textureGrad` 采样，并记录实际加载的候选 shader 代码摘要。桥下阴影来自主光的实际遮挡；反射和阴影不再全部被无光照材质绕开。此方法仍会漏掉离屏物体与透明阶段内容，无法恢复被前景遮住的完整树冠，镜头边缘会渐变回天空。它不是完整的离屏镜像渲染，也不能据此宣称所有角度没有反射断裂。

晴午减少过早的远景雾，阴雨采用较低对比的蓝灰云层和更冷的漫射填光。夜间 POC 将主光调整为仰角 15°、朝向对应旋转 Y=140°，天空月盘和水面高光使用同一方向；月亮是项目已有纹理。这是固定镜头的美术取向，没有修改正式日夜时钟，也不是按日期计算月相或天体位置。白天与夕照仍沿用实际游戏时间的主光方向。

面包房用有限范围的暖色窗前光与局部反射探针；探针只在条件变化时刷新。没有把所有表面换成低粗糙度，也没有给整张图覆盖雾或光晕来掩盖源模型问题。

## 复现与验收

```bash
# 在已有屏幕静音运行，独立临时存档；1/2 切场景，左右切天气，空格切模式。
python3 tools/material_light_poc.py review
# 完整 48 张；默认写入四轮优化的 round4，不覆盖首版记录。
python3 tools/material_light_poc.py capture
# 同一实际机位绕目标旋转，验证反射、天空接缝和桥的侧面。
python3 tools/material_light_poc.py capture --orbit=-25 --conditions noon,night --modes baseline,combined --out evidence/material_light_refine_20261025/orbit-left
python3 tools/material_light_poc.py capture --orbit=25 --conditions noon,night --modes baseline,combined --out evidence/material_light_refine_20261025/orbit-right
# 性能样本关闭帧率限制与 VSync；不与其他 Godot 验收同时运行。
python3 tools/material_light_poc.py capture --uncapped --sample-frames=300 --conditions noon,night --modes baseline,combined --out evidence/material_light_refine_20261025/performance
# 本地图库含此前轮次；从 evidence 根目录提供文件，历史相对链接可正常打开。
python3 -m http.server 8787 --bind 127.0.0.1 --directory evidence
```

结果在 `evidence/material_light_refine_20261025/verification.json`，包括每轮运行记录、最终图像与 shader 摘要、回归、导出资源审计及性能原始值。

| 检查 | 实际结果与范围 |
| --- | --- |
| 四轮原生复拍 | 分别 8／12／16／48 张，1600 × 900；均正常退出，无脚本／shader／ERROR 行。 |
| 最终补拍 | 左右各旋转 25°，各 8 张，共 16 张；天空、倒影、桥侧面可见。与主矩阵的实际加载 shader 摘要一致。 |
| 图库 | 已在浏览器切换场景、天气、历史轮次、单项模式和分隔线；未拍的早期天气被禁用，图片加载完成，无浏览器 warning／error。 |
| 项目与相关回归 | `check_project.py` 8,324 项通过；环境 35、材质 40、树叶 8、景观 40、农场／金鱼 16，共 139 项断言通过。 |
| 隔离与原资产 | 默认 104 份存档／照片摘要保持；原桥文件摘要不变；候选／原桥支撑面倾角均为 0°。未创建虚拟显示器。 |
| 正式导出排除 | 在仓库外导出临时 PCK 并实际挂载，枚举 4,935 个文件，正常主场景存在、POC 文件及对应导入缓存为 0；临时包已清理。没有替换交付包。 |

相关 headless 回归使用 Dummy 渲染器，合计仍输出 292 条已知的 `material_get_instance_shader_parameters` 空材质错误，因此不能写成 headless 日志零错误。检查脚本逐条核对错误文本与 `dummy/storage/material_storage.cpp:264` 来源，没有将其他错误纳入豁免。材质组首次另报退出资源未释放，保留失败日志后用 `--frame-delay 16` 留出帧间释放时间，详细重跑及后三组不再出现该错误；测试断言和正式音频代码未改动。

第三轮首次完整拍摄遇到退出时仍引用 Ogg 音频的错误。详细日志定位到加载场景后启动的 day 音乐／环境声，已在 POC 加载完成和退出前显式 `Audio.silence()` 并等待释放，保留失败日志，再按第三轮源码重拍。它没有被忽略成“零错误”，也没有改玩家音量或系统总音量。原生退出仍有既有的 7 个 Texture RID 警告及加载界面 anchor 警告。临时导出日志有本机编辑器 Adaptive 主题缺失的 ERROR；导出进程、PCK 加载与内容审计均成功。这些结果不包括全量 2,861 项、正式包完整演示或人工美术验收。

### 渲染开销

Apple M5 Max、Metal 4.0 / Forward+，1600 × 900，固定相机、人物与模拟暂停，每种状态采样 300 帧，关闭 VSync 和帧率上限。下表是 GPU 耗时中位数；原始 FPS、P95 和采样时长保留在 `performance/manifest.json`。

| 场景 | 正式原版 | 完整候选 | 增量 |
| --- | ---: | ---: | ---: |
| 面包房晴午 | 3.28 ms | 4.11 ms | +0.83 ms |
| 面包房夜晚 | 3.30 ms | 4.58 ms | +1.28 ms |
| 湖桥晴午 | 2.94 ms | 4.05 ms | +1.11 ms |
| 湖桥夜晚 | 2.97 ms | 4.08 ms | +1.11 ms |

这组候选增加约 25%–39% 的 GPU 耗时。短样本 FPS 波动较大，不能由此得出完整游戏提速或持续稳定帧率的结论，也没有测量耗电、温度、其他设备与图形后端。天空、树冠、草丛、倒角和反射的开销尚未逐项拆分。

## 后续真正需要的源素材工作

继续缩小与 imagegen 的差距，应优先整理近景树冠的叶簇和轮廓、草叶形状及疏密，修补建筑窗框／檐口／布篷的源几何与材质遮罩。湖水若要稳定覆盖离屏岸树，需要单独评估平面反射或反射缓存的成本。当前 POC 的参数不能直接推广到全镇、人物和室内；这些范围尚未做美术验收。
