# 画风规范

**一句话：新海诚风格的动漫风，不走写实。**

干净的线条、平涂和两层阴影，加上新海诚式的光：通透的蓝天、大朵的积云、暖金色的阳光、淡紫蓝色的阴影、逆光的高光和光柱。画面要“像动画里的一帧”，不能像照片、厚涂油画或写实 3D 渲染。游戏里所有 2D 图、3D 模型、着色器和宣传物料都按这一页来，新素材也照这一页验收。

这条规则来自用户在 v0.3 和 v0.6 的几次反馈（家里的墙面地面“不要写实风”；片头的 LTX 视频画风偏写实，删掉改成动漫插画；水井、面包店等模型要“摆正、好看”）。

## 要什么

| 方面 | 要 | 不要 |
| --- | --- | --- |
| 线条 | 清晰、粗细一致的轮廓线，细节线少而准 | 素描线、潦草的线、没有轮廓的写实边缘 |
| 上色 | 平涂 + 一层到两层硬边阴影；受光面暖、阴影偏淡紫蓝 | 厚涂、油画笔触、柔和渐变的写实明暗、脏灰的阴影 |
| 光 | 新海诚式：高饱和的晴空、积云、金色夕照、逆光描边、光柱、空气里的尘 | 阴天写实光、HDR 照片感、强烈的镜面反射 |
| 人物 | 日本 TV 动画式：大眼睛、简洁的五官和发型、表情清楚 | 写实比例和皮肤质感、3D 渲染脸、欧美卡通 |
| 背景 | 和人物同一套画法，形体简化、细节有节制 | 照片贴图、写实纹理、过多噪点 |
| 材质 | 木头、纸、布、石头都画成“画出来的”质感 | PBR 金属和玻璃反光、照片材质 |
| 色彩 | 明亮、干净、夏天的饱和度；夜里是深蓝紫加暖灯 | 发灰、发棕的写实调色，大面积纯黑 |

## 各类素材怎么做

### 2D 图（codex 生成）

所有提示词开头都要写清画风，推荐直接用这一段（`art/manifests/prompts/v06/prologue_anime/_style.txt`）：

> Japanese TV anime style key frame, like a frame from a slice-of-life anime series (not a painting, not photorealistic, not 3D): clean confident line art, flat cel shading with crisp two-tone shadows, simple anime character designs with big expressive eyes, bright saturated summer colours, backgrounds drawn in the same clean anime style with simple shapes.

需要新海诚式的光时再加：warm golden sunlight, cool lavender shadows, big cumulus clouds, luminous blue sky, backlit rim light。

- 画人物时用 `art/tools/codex_gen_ref.sh` 附上游戏里的头像（`game/assets/ui/portraits/*.png`），保证人物一致；一组图先画一张定稿，再把它当画风参考附给其余几张。
- 提示词里写明 “not photorealistic, not a painting”。只写 “Makoto Shinkai inspired” 容易出厚涂的背景画，要和 “anime key frame, cel shading” 一起写。
- 不要文字、不要水印、不要对白框。

### 3D 模型

- 生成顺序：Pixal3D（自建，免费）→ Hyper3D Rodin（MCP 工具 `hyper3d-rodin_*`）→ Blender 程序建模。参考图用上面的 2D 画风画，干净背景、单个物体、3/4 视角。
- 导出时统一换成卡通材质：去掉高光和金属度，只留漫反射（`HouseBuilder.toonify`、`game_export.py`）。玻璃、不锈钢这类 AI 模型做不好的东西，用 Blender 程序建模加手绘贴图。
- Pixal3D 的模型是按参考图的相机视角建的，放进游戏前要转正（见 [PIPELINE.md](PIPELINE.md) 第 13 节）。

### 着色器和光

- 地面：手绘无缝贴图，去掉高光，只有大尺度的明暗变化；地面一直是干的。
- 草：一片片的草叶，按世界坐标调色，风吹过时草尖有亮带（新海诚片子里草地上的银色波纹）。
- 室内：两段色阶，受光面平涂暖色，阴影用淡紫色补光；画出来的光柱和飘尘。
- 天空：codex 画的白天、黄昏、夜晚三张全景图混合；远景是画出来的卡片（远山、屋顶线、树）。

### UI 和宣传物料

- 字体：霞鹜文楷（LXGW WenKai），和游戏内一致。
- 纸张、和纸、手写感；颜色取夏天的蓝、夕阳的橙、灯笼的红。
- 官网、海报、商店图都用 codex 按上面的画风画，不用游戏截图冒充插画。

### 吃饭的演出

- 采用生活动画里的省略：桌上有一份饭菜，短暂近景后变为空碗，再接味道、心情或两个人的闲聊。餐具声、环境声和饭菜的前后变化承担主要表达。
- 人物保持自然姿态，不要求握筷子、拿碗或把食物送到嘴边；吃饭道具不跟随手部骨骼。后续新增首餐、试吃和共餐都沿用这一约定。
- 共餐保留各自的份量和碗位，一人吃完时只改变这一份，另一份仍在桌上。演出和实际食物消费一致，不能把尚未吃的饭也清空。

## 验收

新素材进游戏前看三件事：

1. 放在游戏画面里，和旁边的东西是不是同一种画法（没有一块突然变成照片或写实 3D）。
2. 缩小到缩略图大小，还像不像动画截图。
3. 人物和已经定稿的头像、序章插画是不是同一个人。

不合格的重画或重做，不要靠调色硬凑。

建筑还必须在约两米的门前距离检查：梁柱、窗框和栏杆应保持直线，窗洞和檐口有真实深度，瓦当、格子和雨户等日式构件能辨认。正面、背面、左右侧分别截图，门窗与檐口再拍近景。缩略图、面数、4K 标签或拓扑完整都不能单独证明近景质量。此次做法见 [ARCHITECTURE_CLOSEUP_20261002.md](ARCHITECTURE_CLOSEUP_20261002.md)。
