# 空的贴图升级 POC：商业会员与 12K

2026-10-06。本轮使用用户新登录的 Edge 商业会员账号，未使用旧账号的 MCP OAuth。正式游戏人物未替换。

商业会员可以输出真实的 12K 漫反射。当前三组候选都没有通过外观验收：重新贴图改变眼睛和发色，原图增强在 UV 接缝处留下色块。分辨率标签不能代替实际人物近景检查。

## 付费样本

把本地已批准的 `art/models/raw/CH_sora_rodin_apose_20261005/model.glb` 上传至 Rodin 的 3D Editing。确认导入模型花费 0.5 积分；Native 材质选择 Extreme High，显示 12K(Beta)，去光照开启，PBR 细节 3.5。参考图为原正面设计，提示词要求保留服装、配色、琥珀色眼睛、棕色头发及动漫画风。材质确认花费 2 积分。任务完成时余额由 233 变为 230.5，本次实耗 2.5 积分。

[服务样本](https://hyper3d.ai/workspace/rodin/2911f9f5-3375-4623-9a96-21ba6799ca7c)。下载文件 `base_high_pbr.glb` 为 135,889,636 字节。解包后漫反射为 12288×12288；法线及金属度/粗糙度贴图为 4096×4096，并非所有贴图都是 12K。原始下载、图片和提交记录位于 `art/models/raw/CH_sora_texture12k_business_20261006/`。

导入确认把网格从 52,799 个位置顶点重排为 19,739 个，并改变 UV。不能直接把这份 GLB 或贴图覆盖到原动画人物。`rebake_diffuse_original_uv.py` 用原静态模型作目标、生成结果作来源，只烘焙颜色到原 UV；分别保存 4K 和 12K 图片。`apply_character_texture.py` 将图片装入当前带骨骼 GLB 的独立候选，逐项确认节点、网格、蒙皮、动画、访问器、材质和原二进制完全保留。

12K 候选的眼睛变为灰褐色，头发明显变深，衣服出现偏写实的细纹。迁移后的掌心有色斑；尚未分离生成贴图与投射烘焙各自的贡献，不能把此问题全部归因于服务。候选未用于游戏。

## 两轮免费原图增强

[OmniCraft Image Enhancer](https://hyper3d.ai/workspace/omnicraft/enhancer) 页面标示免费。上传当前人物原始 2048×2048 漫反射图集，分辨率选择 4K，相似度 2，动态与锐度 0；分别试 AI 强度 5 和 0。两次下载都解码为 4096×4096 JPEG，尽管服务下载文件后缀为 PNG。

两轮都保留了主要五官和配色，但下巴、手背、头发及衣服出现沿 UV 分块的颜色接缝。强度为 0 也没有消除问题，不能把这个设置视为逐像素保真。下采样回 2K 后，两个结果相对原图的平均 RGB 绝对差分别约 5.79 和 5.76（0–255 范围）。这些数值是辅助诊断，是否采用仍以模型表面为准。

## 实际检查与交付

独立工程为 `art/poc/character_texture12k_20261006/godot/`。原版、重贴 4K、重贴 12K、增强 5%、增强 0% 共五组，在 Godot 4.7.2 分别截图：站立、招手、行走 × 全身、脸、手 × 正、背、左、右、上、下、俯视、仰视。每组 72 张，合计 360 张。各次 import 和截图进程退出码均为 0，无 SCRIPT ERROR。四份候选的原几何、UV、骨骼、动作和微笑数据保留检查通过。

证据位于 `evidence/character_texture12k_business_20261006/`，总记录为 `verification.json`。本轮未修改游戏 GLB、正式人物库或交付包，未声称执行生产工程全量测试。

![原版、12K重贴、零强度4K增强](../../evidence/character_texture12k_business_20261006/face-comparison-final.jpg)

- [身体八方向对照](../../evidence/character_texture12k_business_20261006/body-eight-angle-comparison.jpg)
- [手掌八方向对照](../../evidence/character_texture12k_business_20261006/hand-eight-angle-comparison.jpg)
- [保留原骨骼的12K候选](../../art/poc/character_texture12k_20261006/godot/variants/native-12k/CH_sora.glb)
- [强度0的4K候选](../../art/poc/character_texture12k_20261006/godot/variants/enhanced-zero-4k/CH_sora.glb)

当前不批量处理其余六个人物。下一轮需要先解决身份一致性与 UV 接缝，再比较分辨率；原版继续作为外观基准。已有肩袖几何缝隙也不属于提高贴图尺寸能修复的问题。
