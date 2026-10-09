# 空、澪的人物与换装管线 POC（2026-10-03）

这轮按用户要求重生人物并比较多种办法。主角为空；“零”按读音理解为澪。没有替换正式游戏人物、存档或发布包。

结论：固定基础身体、可编辑的人形骨架、独立服装与身体遮罩，是值得继续的结构。单纯重生整身人物或增加骨骼，不保证变形更好。当前样本仍是 POC，尤其澪的极端抬手和裙摆不能算通过生产验收。

## 实际做了什么

- Hyper3D 六次人物生成：每人整身 Raw 40k、整身 Quad 18k、贴身基础服装的身体 Quad 18k，全部下载。Quad 的 GLB 仍以三角形存储，不能把请求里的四边面数当成最终三角面预算。
- 两次标准 BANG 分件：空 8 部件、澪 10 部件。两次 High 分件请求被账户权限拒绝，没有返回任务 ID；拒绝记录保留。网络读断开后只恢复既有任务，未重复提交付费任务。
- 空、澪基础身体参考图由内置 imagegen 生成，保留原脸型、头发和配色，改为宽 A 姿势、贴身 T 恤和短裤。人物均按成年设定处理。原图、提示词和来源见素材清单。
- 每人五个成功的骨骼模型，加上 Raw + Rigify 的失败对照。Rigify 源文件有 IK/FK 控制器，游戏 GLB 只输出变形骨骼。空 35 根，澪的模块方案 39 根，其中四根为裙摆骨骼。
- 两个人都能在同一 Skeleton 上切日常、祭典两套独立服装。上衣和下装是不同网格，裙子是新建网格；被衣服覆盖的身体由对应遮罩隐藏。服装是 Blender 从基础表面提取或程序制作的试验衣服，不是已完成的美术服装。
- Godot 4.7.2 实际运行，截图 20 张；录下八秒跳舞与中途换装。实键验证了切动作、C 换装、暂停、侧面查看。六段新动作：idle、walk、wave、dance、squat、reach。

## 方法比较

| 方法 | 空 | 澪 | 换装与动作方面的结果 |
| --- | --- | --- | --- |
| 当前模型 + 现有绑定 | 控制组，19 骨骼 | 控制组，19 骨骼 | 身体、衣服一体，没有独立服装 |
| 新整身 Raw + 现有绑定 | 导出成功 | 导出成功 | 外形改变，仍需剪腋下接缝；不能直接换装 |
| 新整身 Quad + 现有绑定 | 导出成功 | 导出成功 | 同网格对照，不足以解决衣服粘连 |
| 新整身 Raw + Rigify 热权重 | 全部 19,998 顶点未赋权重，拒绝导出 | 40 / 19,992 顶点未赋权重，拒绝导出 | 保留失败，没有静默切回旧权重 |
| 新整身 Quad + Rigify 热权重 | 零未赋权重顶点，导出成功 | 零未赋权重顶点，导出成功 | 动作可编辑，但肩部拉伸仍存在 |
| 基础身体 Quad + Rigify + 模块衣服 | 导出、换装成功 | 导出、换装成功 | 最有后续价值；还需肩、腰、裙摆修正 |
| BANG 自动分件 | 有衣服与皮肤混合、身体缺失 | 有衣服与腿混合、身体缺失 | 不能直接成为换装模板 |

同 Raw 和同 Quad 的对照可以在 POC 里按 B 切换。Raw 热权重失败的列明确显示“未导出模型”，不会拿另一种绑定冒充。

旧绑定没有 squat 和 reach；对应截图显示 bow / cheer，并在界面标明替代动作。该两组图用于观察是否存在相应动作能力，不是同动作的质量对比。抬手的数值比较使用下述独立统一压力姿势。

## 统一抬手测量

`pose_audit.py` 清除导入骨架的动画数据，按骨骼默认方向计算两臂从垂直向下抬到 90°、155°的旋转。比较变形前后大于 2 毫米的网格边长度。数值只用于定位异常拉伸，不证明服装碰撞、脸型、脚步或整体美术质量。模块列只测基础身体，服装单独看截图。

155°抬手的结果如下。P99 是 99% 的边不超过的伸长比；最大值会受到局部小面和拓扑差异影响。

| 角色、模型 | P99 伸长比 | 最大伸长比 |
| --- | ---: | ---: |
| 空，当前 | 1.44 | 18.20 |
| 空，新 Raw + 旧绑定 | 1.25 | 44.87 |
| 空，新 Quad + 旧绑定 | 1.30 | 25.43 |
| 空，新 Quad + Rigify | 2.47 | 15.17 |
| 空，基础身体模块方案 | 1.94 | 5.18 |
| 澪，当前 | 2.52 | 25.88 |
| 澪，新 Raw + 旧绑定 | 1.65 | 21.03 |
| 澪，新 Quad + 旧绑定 | 2.05 | 26.90 |
| 澪，新 Quad + Rigify | 3.60 | 14.15 |
| 澪，基础身体模块方案 | 2.16 | 7.17 |

模块身体降低了最严重的单边拉伸，但空的 P99 比当前模型高，不能声称它全面改善了变形。整身 Quad + 自动热权重的 P99 也比旧绑定差。这正说明骨架、网格与权重要分别检查。

诊断门槛是最大边伸长不超过 8 倍、P99 不超过 2 倍；它用于抓原来的严重拉伸，不是发布标准。先跑旧模型，两个人都失败；模块空通过，模块澪的 P99=2.16 仍失败，原样保留为未解决项。门槛是本轮根据具体旧问题制定的，不是独立质量基准。

按仓库流程另跑了 `level_check.py`，结果单独保存在本轮 evidence，没有改正式 `_level.json`。六个静态网格的支撑面倾角是 0–3.92°，其中空的整身 Raw 为 2.91°、Quad 为 3.92°，仍需在正式采用前放平。带动画的 GLB 测得约 37°但支撑面只占脚印 5.6%，不满足稳定底面的条件，不能据此认定整个人物倾斜；本轮保留原始测量并结合实际站姿截图检查。

## 推荐继续的管线

1. 固定一个角色的基础身体和比例，先把肩、胯、肘、膝的拓扑与权重修好；不要每换一套衣服重生一次整个人。
2. 用 Rigify 控制器制作动作，输出固定命名的变形骨架。IK/FK 控制器留在 Blender 文件中，Godot 接收烘焙后的动画。
3. 衣服按固定身体制作、贴合和转移权重，和身体共用骨架；覆盖区用遮罩。裙摆、长袖、头发另加辅助骨骼和穿模检查。
4. 日常动作、舞蹈分别验收，包含脚锁定、手与道具接触、循环接缝和动作之间的过渡。当前六段是程序关键帧草稿，不是完成的舞蹈作品。
5. 多角色共用动作时，再做 Godot BoneMap、默认姿势和身高差异的重定向验证。本轮已验证同一个人的两套衣服共用动作，尚未验证跨角色共用同一动画资源。

本轮没有面部表情或独立手指绑定，没有布料物理模拟；服装美术、裙摆碰撞和运动时脚滑仍需完善。现阶段保留正式角色更合适。

## 查看和复现

- 双击 [open_poc.command](../../art/poc/character_pipeline_20261003/open_poc.command)。键盘：左右切动作，C 换装，B 总览/同 Raw/同 Quad，V 正侧面，空格暂停，R 重播，Esc 退出。
- [跳舞换装录像](../../evidence/character_pipeline_poc_20261003/wardrobe_dance.mp4)、[总览](../../evidence/character_pipeline_poc_20261003/screens/dance_festival.png)、[同 Quad 抬手](../../evidence/character_pipeline_poc_20261003/screens/same_quad_wave.png)、[侧面蹲下](../../evidence/character_pipeline_poc_20261003/screens/squat_side.png)。
- [空的 BANG 部件](../../evidence/character_pipeline_poc_20261003/bang-sora-parts.png)、[澪的 BANG 部件](../../evidence/character_pipeline_poc_20261003/bang-mio-parts.png)。每个格子分别缩放，仅供查看部件内容，不能从格子位置推断原始装配对齐。
- [任务、参考图、输出摘要清单](../../art/manifests/models_hyper3d_character_poc_20261003.json)。原始输出在 `art/models/raw/character_pipeline_poc_20261003/`，可编辑 Rigify 文件在 `art/poc/character_pipeline_20261003/authoring/`。
- [运行证据](../../evidence/character_pipeline_poc_20261003/screens/runtime.json)、[权重和换装接口检查](../../evidence/character_pipeline_poc_20261003/contract-checks.json)、[诊断门槛结果](../../evidence/character_pipeline_poc_20261003/quality-gate.json)。导入日志中的 Adaptive 编辑器主题缺失与模型无关；实际运行日志无 SCRIPT ERROR。
- [静态支撑面测量](../../evidence/character_pipeline_poc_20261003/static-level-check.json)、[动画 GLB 支撑面测量](../../evidence/character_pipeline_poc_20261003/level-check.json)。脚底倾角和动作用的骨骼权重属于不同问题。

本轮八个已接受任务按约 4 积分估算，尚未与实际账单核对。普通 Gen-2.5 的基础计费见 [Hyper3D API 文档](https://docs.hyper3d.ai/en/api-specification/rodin-gen2-5)。

```bash
GODOT=/Users/jack/workpath/godot/tools/godot-4.7.2/Godot.app/Contents/MacOS/Godot
POC='art/poc/character_pipeline_20261003/godot'
"$GODOT" --headless --path "$POC" --import
"$GODOT" --path "$POC" -t --position 1700,1990
python3 art/poc/character_pipeline_20261003/check_contract.py
python3 art/poc/character_pipeline_20261003/quality_gate.py
```

`quality_gate.py` 明确保留澪的诊断失败，不能把脚本退出码 0 当成两个人物都能发布。完整玩法回归和正式发布包未因这个隔离 POC 重跑。
