# Hyper3D 家具来源（2026-10-15）

`source/` 是14次已付费生成的不可变原始 GLB。`provenance.json` 保存生成任务、原始摘要、参考图摘要和逐件原始质量检查；原始检查中的 `native_game_acceptance:false` 描述修整前素材，最终游戏交付见 `docs/game-design/HYPER3D_FURNITURE_20261015.md`。

本轮结算7点，余额150→143，冻结0；不需要重新付费生成即可重建。参考图位于 `art/references/hyper3d_furniture_20261015/`，生成提示及记录位于 `art/manifests/prompts/hyper3d_furniture_20261015_generated.json`。

木作保留原三角面、UV与图集像素；局部修正尺寸、脚底、弧背和承重面。蛋糕柜、咖啡机保留生成主体，局部切除不透明假玻璃，增加真实薄玻璃。`legacy_auxiliary/` 只用于保留暖桌布与旧书；旧收银机来自前一批可追踪原件，均不是新家具主体。

在仓库根目录依次运行（Blender 5.2.1 LTS，Python 需 numpy、Pillow、scipy）：

```bash
blender -b --factory-startup -P art/tools/prepare_hyper3d_furniture_20261015.py
blender -b --factory-startup -P art/tools/prepare_hyper3d_glass_case_20261015.py
blender -b --factory-startup -P art/tools/prepare_hyper3d_espresso_20261015.py
blender -b --factory-startup -P art/tools/assemble_hyper3d_furniture_20261015.py
```

中间 GLB、可编辑 `.blend` 及修整测量报告写入忽略的 `art/models/raw/hyper3d_furniture_20261015/{ready,assembled}/`。从 `art/models/game_assets.json` 选本批27个 ID，交给 `art/tools/game_export.py` 导出；不要无参数重导全库。

导出后运行 `check_hyper3d_furniture_sources_20261015.py --stage game --out <证据JSON>`、`check_hyper3d_glass_case_20261015.py --input game/assets/models/I02_cake_showcase.glb --out <证据JSON>`，再跑倾角、模型审计、Godot import、家具专项、独占全量和实际桌面包验收。离线检查不能替代原生玻璃和坐姿检查。
