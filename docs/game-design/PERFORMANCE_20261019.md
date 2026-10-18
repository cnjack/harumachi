# 运行性能优化（2026-10-19）

目标：在不明显改变画面的前提下，把运行时帧时间、显存和每帧 CPU 逻辑降下来。重点是 AI 图生 3D 资产：292 个 GLB 里 241 个来自 Hyper3D/Pixal3D/Hunyuan，占三角面 96.8%、贴图显存 95.0%，而且全部按原图导出，没有做过减面或显存压缩。

## 审计结论

静态审计（[资产成本](../../evidence/performance_20261018/assets/summary.md)、[每帧代码](../../evidence/performance_20261018/code/findings.md)）与 1600x900 原生基准（[pilot](../../evidence/performance_20261018/runtime/pilot-baseline-1600x900-settle120/result.json)）给出的主要成本：

| 项 | 基线 |
| --- | --- |
| 模型贴图 | 623 张全部 lossless RGBA8、不降采样：6159.6 MiB（不含 mipmap） |
| 8192/4096 建筑图集 | 13 张 8192² + 3 张 4096²，共 3520 MiB |
| 衣物局部求解器 | 澪/和子站立 idle 也每帧全量求解，合计均值 8.6 ms、p95 12.8 ms |
| `update_time → _apply_look` | 每帧重刷 13 个室内的递归 `find_children`、橱窗灯光、20 栋楼营业陈列 |
| 环境生物净空 | 每帧约 48–64 次鸟 + 12 次虫 `intersect_shape`，每次新建查询对象 |
| 商店室内 | 851 个 MeshInstance、333 件商品；5171 draw call（1 主 pass + 4 阴影 split） |
| 显存 | 实测 `RENDER_VIDEO_MEM_USED` ≈ 10.97 GB |

## 本轮改动

### 1. 贴图显存：BC7/BC5 + 2048 上限

`game/assets/models/**/*.import` 共 623 张：`compress/mode=2`、`compress/high_quality=true`、`process/size_limit=2048`。法线贴图仍为 `compress/normal_map=0`：全部 292 个 GLB 材质都没有引用法线贴图，而按文件名判断会把 CC0 树的 `*_NormalTree_C` 颜色图集误当法线图（BC5 丢弃 alpha，树叶会变成不透明方块），所以这一项保持原状。改完重跑 `--import`。

7 张角色反照率（`CH_*_texture_diffuse.png`）例外，保持 `compress/mode=0`、只做 2048 上限：BC7 的颜色偏移会改变运行时按反照率像素做的身体/衣面顶点分类，实测让 `body_local_template_delta_max_m` 从 0 跳到 0.1199，衣物证明随之失配。7 张 2048² 共约 112 MiB。

静态估算：6159.6 MiB → 807.9 MiB（不含 mipmap），只算材质实际引用的贴图是 6103.6 → 793.9 MiB。8192² 图集降为 2048² 后，10 m 立面约 200 px/m，对这一套平涂动画风足够；画面验收见下文。

变更清单在 [model_import_changes.json](../../evidence/performance_20261018/import/texture/model_import_changes.json)。

### 2. 衣物求解器：0.6 mm 姿态容差缓存

`character_garment_support.gd` 在精确矩阵比较之后增加 `_pose_within_cache_envelope()`：只有全部骨骼矩阵的位移与三轴基向量差都 ≤ 0.6 mm，且**整副骨架**（含腿骨 IK 结果）同样在 0.6 mm 内、原始形态键值完全一致时，复用上一帧的布料修正量；否则照旧全量求解。只比衣物绑定骨不够——跑步时腰部几乎不动而腿会动，实测漏判过 14 mm 穿插。新分支计入 `pose_tolerance_cache_hits`，可用 `--garment-pose-tolerance=<米>` 覆盖阈值（0 关闭）。

缓存复用的是产生该解的同一组 `cached_matrices` / `cached_amounts`，所以最坏误差被阈值封顶。认证 steady 快路径的计数器不受影响；看门用例把该分支视为“未走认证快路径”的合法回退分支。

### 3. 每帧逻辑削减

- `world_builder.gd`：13 个室内的 `set_evening()` 改为状态签名 + 4 Hz；橱窗灯光与 20 栋楼营业陈列按 `int(minute)|weather|day|phase` 门控（时间补间仍逐帧）。`PublicPlaceArt.set_evening` 把 `SummerView` 节点列表缓存到房间 meta，不再每次递归 `find_children`。
- `ambient_life.gd`：鸟/虫的净空查询改为 8–12 Hz / 4–6 Hz 错峰；复用 `SphereShape3D` 与 `PhysicsShapeQueryParameters3D`；移动与姿态仍逐帧，只降低碰撞复查频率。
- `environment_life.gd`：天气字典只在天气变化时复制。
- `camera_rig.gd`：玩家网格列表按模型缓存，透明度没变就不写。
- `main.gd`：区域名、交互提示、任务指引改为 10 Hz；指引动画仍逐帧。
- `world_builder.gd` 风铃：风速在循环外只算一次，反向遍历替代 `duplicate()`。
- `shop_content.gd`：营业判定每次 update 只算一次；商品可见性、电视标题、标签文本只在变化时写；商品网格关闭阴影（厘米级小商品的阴影在货架内不可见，但每个网格要多吃 4 个阴影 split 的 draw）。

## 实测

同屏 A/B，1600x900、每视角丢弃 120 帧后采样 300 帧、vsync 关、静音、独立存档。对照工程是 HEAD 的 COW 副本（脚本与 623 个 `.import` 全部还原，其余内容一致），两者都在现有 screen 0（5120×2880、scale 2.0、75 Hz）上单独运行。上一轮的 pilot 基线在已移除的 screen 2 上采集且被另一个 Godot 进程重叠，只作为历史参考，不用于本轮结论。

| 场景 | 对照中位 ms | 优化中位 ms | 帧时间变化 | 对照 FPS | 优化 FPS | 对照 p95 | 优化 p95 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| street | 12.29 | 9.71 | -21.0% | 81.4 | 102.9 | 15.08 | 13.71 |
| plaza_day | 13.47 | 9.66 | -28.3% | 74.3 | 103.5 | 14.03 | 15.07 |
| farm | 12.45 | 8.91 | -28.4% | 80.3 | 112.2 | 17.51 | 16.39 |
| lake | 11.30 | 8.89 | -21.3% | 88.5 | 112.5 | 11.63 | 13.69 |
| store_interior | 14.33 | 9.95 | -30.6% | 69.8 | 100.5 | 16.95 | 14.45 |
| bedroom | 9.63 | 8.06 | -16.3% | 103.8 | 124.0 | 17.05 | 13.82 |
| plaza_festival_night | 10.22 | 10.95 | +7.1%（首次） | 97.8 | 91.3 | 16.33 | 11.83 |

夜晚节日场景的对照跑了两遍：10.22 ms 与 12.49 ms；优化版两遍是 10.95 ms 与 10.81 ms。优化值稳定，对照波动大（8.7M 图元、动态人群），第二次同条件比较是 **12.49 → 10.81 ms（-13.5%）**，p95 16.33 → 14.07。没有可靠证据表明夜晚变慢。

显存（`RENDER_VIDEO_MEM_USED` 中位）：

| 场景 | 对照 | 优化后 | 变化 |
| --- | --- | --- | --- |
| street / plaza / farm / lake | 10,848 MB | 3,627 MB | -66.6% |
| store_interior | 10,880 MB | 3,627 MB | -66.7% |
| bedroom | 10,896 MB | 3,643 MB | -66.6% |
| plaza_festival_night | 10,896 MB | 3,675 MB | -66.3% |

静态估算（贴图本体，不含 mipmap、渲染目标与几何缓冲）：6,159.6 MiB → 807.9 MiB；只算材质实际引用的贴图是 6,103.6 → 793.9 MiB（-87.0%）。其中 7 张角色反照率保持 lossless，比全 BC7 多约 84 MiB，换来衣物顶点分类与源证明完全一致。

商店室内的绘制调用 **5,170 → 1,633**，图元 4,648,925 → 2,610,894；差额来自商品关闭阴影后少掉的 4 个阴影 split。其他场景绘制调用基本不变（farm 1,205 → 1,187），说明白天帧时间的改善主要来自贴图带宽/显存压力，而不是牺牲可见物体。

原始结果：[对照](../../evidence/performance_20261018/runtime/control-head-1600x900-settle120/summary.md)、[优化后](../../evidence/performance_20261018/runtime/optimized-1600x900-settle120/summary.md)、[对照重跑](../../evidence/performance_20261018/runtime/control-repeat-night/summary.md)、[优化重跑](../../evidence/performance_20261018/runtime/optimized-repeat-night/summary.md)。

## 验收

同机位 1600x900 截图各 8 张，对照与优化逐图目视对比：[对照](../../evidence/performance_20261019/shots/control/)、[优化后](../../evidence/performance_20261019/shots/optimized/)。`close_store`、`close_bakery`、`win_store`、`win_night`、`npc_wave_close`、`life_daisies`、`shop_groceries`、`plaza_overview` 的招牌文字、商品标签、树冠与草叶 alpha、橱窗亮灯、七人服装颜色都一致；人物与草叶的姿态差异来自动画相位，不是画质变化。缩到 2048 的 8K 建筑图集在游戏机位下看不出软化，BC7 也没有可见色带。

针对性测试：

- LANDSCAPE 40/40、FOLIAGE 9/9、ENVIRONMENT 35/35。贴图改 VRAM 压缩后，树叶 alpha 仍在；`landscape_coverage_checks` 与 `foliage_library_checks` 里对 BPTC 图像先 `decompress()` 再查 alpha，因为 `detect_alpha()` 不能直接读压缩纹理。
- garment-local 的 45 项中，mio/ren/kazuko 的 65 样本、源衣面与恢复检查全部通过；15 项失败全部来自并发提交 `1dc998c` 更新 `CH_*.glb` 后未重签 `game/data/character_garment_proofs.json`，与性能改动无关。
- character-visual 167 项中 17 项失败：15 项同上证书失配；2 项是同一并发提交的源跑步手臂/落脚（ren 路缘 -0.0353 m、haru 草地 -0.0034 m、Sora 前臂），也不属于本轮。
## 完整回归

独占运行全部测试（Dummy 音频、独立存档，不与别的 Godot 实例并行），退出码 0，2628 项中 17 项失败。逐项归因：

- 1 项 `FOLIAGE_LIB` 树叶 alpha：`Image.detect_alpha()` 在 BPTC 压缩图像上直接返回 NONE。测试改为先 `decompress()`；单独重跑 `--only=foliage-library` 为 9/9 通过。运行时 alpha scissor 与截图 alpha 一直正常，这是测试读取方式的问题。
- 15 项 `GARMENT_STEADY_GUARDS`：并发提交 `1dc998c` 更新了 `CH_*.glb`，但没有重签 `game/data/character_garment_proofs.json`，证书 SHA 失配（期望 `d38b…`，实际 `cd28…`）。本轮只把容差缓存加入合法的未认证回退分支，不修改证明内容。
- 1 项 `CHARACTER_GAIT`：同一并发提交的 Sora 跑步前臂姿态（elbow 0.0814 m、wrist 0.2671 m 超出肩线），与性能改动无关。

上述 16 项并发失败没有在本轮改源资产或重签证明；与性能相关的贴图、衣物缓存和每帧逻辑在对应专项中通过。原始结果保存在 [完整回归](../../evidence/performance_20261019/full-test/results.json)与[归因摘要](../../evidence/performance_20261019/full-test/summary.md)。

## 复现

```bash
./tools/godot --headless --path game --editor --import --audio-driver Dummy
python3 tools/performance/run_bench.py --out evidence/performance_20261018/runtime/optimized-1600x900-settle120 \
  --resolutions 1600x900 --settle 120 --frames 300 --ablations "" --only baseline --screen 0
# 对照：把同一工程复制到 /tmp/haru_control，用 git show HEAD:<path> 还原脚本和全部 .import，再跑同一命令：
python3 tools/performance/run_bench.py --project /tmp/haru_control/game \
  --out evidence/performance_20261018/runtime/control-head-1600x900-settle120 \
  --resolutions 1600x900 --settle 120 --frames 300 --ablations "" --only baseline --screen 0
# 截图对照（真实渲染、静音、独立存档）：
HARUMACHI_SAVE_DIR=/tmp/perf_shots/save ./tools/godot --path game --resolution 1600x900 \
  -t --position 1660,60 --audio-driver Dummy res://scenes/main.tscn -- \
  --shots=/abs/evidence/performance_20261019/shots/optimized \
  --views=close_store,close_bakery,win_store,win_night,npc_wave_close,life_daisies,shop_groceries,plaza_overview
HARUMACHI_SAVE_DIR=/tmp/perf_verify/save ./tools/godot --headless --path game res://scenes/tests.tscn -- --only=landscape
```

## 未做

- 商品 MultiMesh 批处理、AI 网格离线减面（T05 484K 面、两只步行猫各 18 万面、小商品 1 万面/件）会改变几何与 UV，需单独批次和逐件视觉复核，本轮不混入。
- 阴影 8192 / 4 splits、4x MSAA 未降档；先保留现有画面上限。
- 274 张过期贴图与 26 张无引用内嵌贴图未删除，它们不占运行时显存，只影响包体。
