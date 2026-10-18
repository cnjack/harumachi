# 重建已求解衣物场的烘焙结果

`bake_periodic_garment_correctives.py` 读取**已经求解并验过单参考姿态**的场，将它们写成周期 POSITION/NORMAL 修形和动画权重。它不运行 QP，也不证明周期插值、运行时残差、画面或性能已通过。`restore_garment_shape_curve.py` 只恢复一个已经接受过的 LINEAR 标量函数；新驱动下仍必须重新验收。

需要 Python 3、numpy、scipy、Pillow。纯代码依赖都在本目录：`garment_bake_support`、`audit_local_garments`、`audit_native_garment_surfaces`、`source_surface_rays`、`prepare_local_garments`、`corrective_normals`、`motion_math`、`repair_head_neck`、`glb_io`。打包另用 `pack_character_glb.py`，逐解码数组及嵌入图像检验，不量化或简化模型。无需 Godot、OSQP 或个人目录。

## 输入和身份

- `--input`：求解所依据的准确源 GLB，`--expected-source-sha256` 必须明确匹配。
- `--controls`：参考目录，含 `poses.json`、以下一种控制清单、每参考的 NPZ。清单和姿态均须声明相同 `source_sha256`；若声明 native capture SHA，两者也须一致。
- `--curve-policy resample`：`references.json` 的 `references`，用于保留旧曲线并在必要新节点取正确舍入的 f32 值。零场参考保留为插值节点而不增加空 target。旧 key/time/value 全部保留；新增节点导致的旧函数误差会报告，不能称整段 bitexact。
- `--curve-policy zero`：`controls.json` 的 `frames`，只用于所选动作旧列全部为 0 的来源，遇到非零列就拒绝。包含零/终点的周期两邻接权重，参考全部保留。
- 每参考须有 `clip`、`phase`、`file` 和 `diagnostics.found_conservative_gate_passing_candidate=true`；zero 格式另需 `full_solver_profile_original_gate_pass=true`。NPZ 含 `rest_delta`、`base`、`posed`。`poses.json.poses` 含唯一 clip/phase、准确 `clip_time`、最终 `bones`（name/basis/position）、实际 `blend_shape_values`。
- `--character` 选择已有原 body 分类（mio/kazuko）；`--colour` 选择蓝/黄完整衣面谓词。完整原支持域保留，paint 完整三角和同 rest/skin 的物理 UV copies 闭包补齐可动域。旧 Local 字段不改。

法线由实际最终骨矩阵、旧形状法线和衣面几何变化重建，保原硬边。不可实现的单位法线组合会在报告明示，不自动冒称精确。新 POSITION/NORMAL 的 body 和衣域外增量必须为零。

## 命令

在仓库根目录，先设置下列变量为自己的新输出路径及真实输入。程序不会改正式素材；烘焙输出目录、恢复输出和报告必须是新路径。

```sh
python art/tools/characters/bake_periodic_garment_correctives.py \
  --input "$SOURCE" --expected-source-sha256 "$SOURCE_SHA" \
  --controls "$CONTROLS" --out "$RAW_OUTPUT" --output-name CH_mio.glb \
  --character mio --colour blue --curve-policy resample --clip walk --clip run

python art/tools/characters/pack_character_glb.py \
  --input "$RAW_OUTPUT/CH_mio.glb" --output "$PACKED_MODEL" --report "$PACK_REPORT"
```

和子的原 105 列为零的已求解来源改用 `--character kazuko --colour yellow --curve-policy zero --output-name CH_kazuko.glb`。最终选择保留这次新 run，恢复原 walk；不是探索版的 run global 曲线恢复：

```sh
python art/tools/characters/restore_garment_shape_curve.py \
  --input "$BAKED_KAZUKO" --expected-source-sha256 "$BAKED_SHA" \
  --accepted "$ACCEPTED_KAZUKO" --expected-accepted-sha256 "$ACCEPTED_SHA" \
  --mesh-node kazuko_static --clip walk --shape Apron_Clearance \
  --clear-prefix GarmentDrape --output "$RESTORED_MODEL" --report "$RESTORE_REPORT"
```

该步骤只清指定 prefix，遇到其他非零列就拒绝；目标 POSITION、rest POSITION 和 skin 必须与 accepted 输入一致。原先没有 time=0 的 looping 前缀不补零、不重采样。其余 11 动作、旧 payload 和骨轨精确保留。`Rig.extras.garment_local_clearance.disable_global_shapes` 仅解除该指定目标；运行时必须读取此策略，不能从本工具推断已启用。

## 本次最终来源边界

本轮选择为 Mio v80 `9e216ea1…`、Kazu v96 `fd49e931…`。它们此前分别由 ignored 的 `prepare_mio_complete_blue_source_v58.py` 和 `prepare_kazuko_closed_original_key_bank_v57.py` 烘焙，Kazu 再经 `restore_kazuko_accepted_walk_curve_v89.py` 恢复 walk。新增入口提取了这些阶段的纯代码；没有迁入已弃 QP/引导/稀疏 proxy 试验，也没有迁入拒绝的 Mio v92 原曲线恢复或 Kazu v90 run 恢复。

本轮输入仍保留在 ignored evidence：Mio ca1 源 GLB + `mio-finite-walk-run-v80-controls`（134 参考，125 非零新 target）；Kazu cb4 源 GLB + `kazuko-micro-reprojected-source-v70`（117 参考），原 accepted e2a 模型。NPZ、实际姿态包、捕获和质量报告未提交。**新 checkout 只取得源码和最终模型，不能凭这些 CLI 重新求出初始场**；重烘需要取回上述源与证据输入。工具会记录输入摘要，但生成的 metadata/报告文字及文件 SHA 可与历史 writer 不同；是否数组相同必须由独立 decoded 对照确认。

轻量回归：

```sh
python art/tools/characters/test_garment_bake_support.py
```
