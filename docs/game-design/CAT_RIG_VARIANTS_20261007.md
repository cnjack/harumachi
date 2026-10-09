# 猫脸、耳朵和尾巴绑定对照（2026-10-07）

用户看过当前猫的骨架与动作后，指出脸部、尾巴方向可疑，关节密度可能不够，要求比较多种方案并下载 AI 模型实测。本轮是独立绑定试验，正式 `AN_cat_orange_walk.glb`、`AN_cat_calico_walk.glb` 与编译包没有替换。

## 当前绑定的问题

直接导入正式 GLB，排除 Blender 自动创建的骨骼显示网格，只统计实际绑定的猫网格。两只猫各 48 关节。耳根有少量蒙皮权重，左右 `Ear_Tip` 都没有权重；作者文件的耳尖骨末端约高出模型 2.8 cm。`Tail_Tip` 末端沿用狐模板的方向，橘猫在前后轴上超出模型约 4.9 cm，三花猫约 6.4 cm。

原适配脚本把头部上半区强制设成 `Head` 单骨权重，尾巴按前后轴分段拟合。这两个做法没有充分考虑猫的实际耳部和弯曲尾巴。骨骼叠加图连接的是导出关节，不包含 Blender 末端骨的完整长度；因此必须同时检查作者文件里的末端轴和实际蒙皮，不能只看一张骨架图。

审计在 `evidence/cat_rig_variants_20261007/baseline-audit.json`，工具为 `art/poc/cat_rig_variants_20261007/audit.py`。

## 五种对照

| 方案 | 橘猫 / 三花猫关节数 | 实际产物 |
| --- | --- | --- |
| 原绑定 | 48 / 48 | 保留原权重与六个动作，另加统一诊断动作作为对照 |
| 位置与权重修正 | 48 / 48 | 按实际网格重定位头、下颌、耳朵和尾巴；尾巴沿表面中心线拟合；修正权重并平滑下脸到脖子、尾根到臀部的过渡 |
| 耳朵与尾巴加密 | 59 / 59 | 在修正版基础上，尾巴从 5 节到 12 节，每耳从 2 节到 4 节；不增加眨眼或嘴型系统 |
| MagicArticulate 层级版 | 44 / 38 | 官方权重在 MPS 上实际预测的骨架；保存 NPZ、未蒙皮的可编辑 Blender 文件及原生叠加图 |
| MagicArticulate 空间版 | 33 / 30 | 同上，使用另一组官方权重；这两只猫上的耳部和脸部骨架更简化 |

手工方案保留原网格位置和 UV，误差为 0；六个原动作经过新参考姿态的变形矩阵迁移，再与正式 GLB 匹配原时长。新增 `FaceTailProbe` 是程序编写的诊断动作，使用相同的世界轴转头、下颌、耳抖与摆尾角度，不是 AI 生成的动画。每顶点最多四个归一化权重。

三组已蒙皮方案的 `.blend` 与 `.glb` 在 `art/poc/cat_rig_variants_20261007/outputs/{baseline,fitted,dense}/`。AI 作者文件在 `outputs/{ai_hier,ai_spatial}/`，网格没有蒙皮；不要把它们当成可直接播放现有动作的游戏角色。

## AI 实测与运行边界

使用 [MagicArticulate 官方仓库](https://github.com/Seed3D/MagicArticulate)，提交 `de2172d8bc688ff838506a35e29a9d0b30edc10b`。从作者指定的 Hugging Face 仓库下载 Michelangelo 的 `shapevae-256.ckpt`，以及 `checkpoint_trainonv2_hier.pth`、`checkpoint_trainonv2_spatial.pth`，三份合计约 12.7 GB。下载位置、文件大小和实际推理校验记录在证据目录。

官方源码面向 CUDA / FlashAttention。本轮用 PyTorch 2.8.0、Transformers 4.39.3，在 Apple M5 Max 的 MPS 上使用 FP32 与 eager attention；为自定义 OPT 补上标准四维因果遮罩，模型权重没有修改。最终主模型 `load_state_dict(strict=True)` 成功。兼容补丁在 `magic-mps-compat.patch` 与 `michelangelo-torch-compat.patch`。这属于本地适配，未验证与官方 CUDA FP16 输出逐项一致。

| 权重 | 橘猫推理 | 三花猫推理 |
| --- | --- | --- |
| 层级版 | 12.90 秒，44 关节 | 8.50 秒，38 关节 |
| 空间版 | 8.23 秒，33 关节 | 7.26 秒，30 关节 |

计时包含本次骨架生成，不含下载和加载。当前发布代码只提供骨架预测，未提供本轮可运行的 AI 蒙皮阶段；本轮没有宣称完成 AI 蒙皮或 AI 动作生成。UniRig 和 RigAnything 只克隆并核对了运行条件，没有执行，不能计入已实测方案。

AI 图显示两种模型能提取大致四足结构与尾链，但在这两份输入上没有得到完整、精细的耳部控制链。空间版的脸部尤其简化。不能据此推断所有猫模型上的表现，也不能仅凭关节总数判断哪个方案更好。

## 验证结果

`check_variants.py` 对旧版先跑：30 条结构检查失败 12 条，能抓到原来的耳尖无权重和末端越界。修正版两只猫合计 30 条、加密版合计 44 条结构检查通过；它们检查末端位置、耳链有效权重、权重归一化、四权重上限和原网格/UV 保留，以及重合顶点权重一致。主游戏测试集数量没有改变。

`deformation_audit.py` 检查 Blender 实际求值后的蒙皮，每个动作取 17 个时刻，忽略原长小于 1 mm 的边。以下是诊断动作中单个时刻最多出现的两倍以上拉伸边数：

| 方案 | 橘猫 | 三花猫 |
| --- | --- | --- |
| 原绑定 | 173 | 208 |
| 修正 48 关节 | 39 | 44 |
| 加密 59 关节 | 39 | 43 |

这项改善主要来自权重与过渡修正。额头和耳根的中间候选出现过接缝裂缝。原因是 UV/法线接缝的重合顶点在邻接平滑后获得不同权重；只统一 10 微米内重合顶点的权重，不焊接网格或改 UV。新检查在中间候选上失败，最终导出后重新导入的最大权重差为 0。加密增加控制粒度，本轮相同诊断角度下这个指标差别很小。诊断动作仍有最大约 3.36 / 4.12 倍的局部拉伸，Walk、Idle、Sit 也保留较大拉伸候选。尤其坐姿不能仅凭结构检查通过就验收。全模型边统计是定位线索，不能代替逐处像素和几何审查。

对六个导出 GLB 使用 `level_check.py --rest-pose`，输出写入独立证据文件，没有改写正式 `_level.json`。原网格保留，站立支撑面保持原结果。

Godot 4.7.2 Forward+ 实际录制 1920×1080、30 FPS、20.03 秒，比较全身、脸部、尾巴和原 Walk；每段切换骨架可见性，以便查看实际表面。AI 三视角另作静态叠加。两套预览没有游戏 autoload，存档目录隔离，默认存档摘要未变。正式两份模型摘要与基线审计一致。

## 查看与复现

- `evidence/cat_rig_variants_20261007/compare/cat-rig-comparison.mp4`：左原版、中 48 修正版、右 59 加密版；上橘猫、下三花猫。
- `compare/FaceTailProbe_0210.png`：脸与耳朵骨架近景。
- `compare/FaceTailProbe_0260.png`：去掉骨架的脸部表面。
- `compare/FaceTailProbe_0320.png`：尾链近景。
- `ai-preview/AI_0010.png`、`AI_0030.png`、`AI_0050.png`：实际 AI 全身、脸与尾巴预测。
- `summary.json`、`regression.json`、`deformation.json`、`level-*.json`：结果与限制；`compare/verification.json`、`ai-preview/verification.json`：原生录制与存档校验。

从仓库根目录运行：

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_rig_variants_20261007/build_variants.py -- orange fitted
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_rig_variants_20261007/build_variants.py -- orange dense
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_rig_variants_20261007/check_variants.py
python3 art/poc/cat_rig_variants_20261007/render_compare.py
PYTORCH_ENABLE_MPS_FALLBACK=1 art/poc/cat_rig_variants_20261007/.venv/bin/python art/poc/cat_rig_variants_20261007/infer_magic.py --ordering hier
PYTORCH_ENABLE_MPS_FALLBACK=1 art/poc/cat_rig_variants_20261007/.venv/bin/python art/poc/cat_rig_variants_20261007/infer_magic.py --ordering spatial
python3 art/poc/cat_rig_variants_20261007/render_ai.py
```

还需对下脸/颈部与坐姿的剩余拉伸继续定位，再决定是否替换正式猫。脸部表情还涉及眼睑、眼球与嘴型，增加耳骨或尾骨不能自动补齐这些表演能力。
