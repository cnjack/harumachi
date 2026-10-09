# 猫慢走的对角配合与轻落脚（2026-10-07）

用户指出希望左前/右后、右前/左后有更明显的配合，并要求整体更自然。本轮沿用已绑定的两只 Hyper3D 猫，保留网格、UV、59 关节与八权重，调整慢走相位、摆腿和身体运动；没有重新付费生成模型。

## 修改

原 Walk 四腿按 0、0.25、0.5、0.75 等间隔循环。现在按左后、左前、右后、右前的顺序使用 0、0.42、0.5、0.92：对角腿相差 0.08 个周期，约 67 ms，形成接近成对的配合，同时保留四脚的落地先后。步速仍为 0.12 m/s，周期 0.8333 秒，步幅 10 cm。支撑占比由 76% 降至 70%，摆动时间增加；抬爪目标由 16 mm 降至 12 mm，摆动脚掌的转角从 12° 降至 8°。

慢走胸臀侧摆减半，水平侧移缩小，垂直起伏也减小；头颈仍居中且张望独立。慢走关键帧提高到 60 Hz，落地边界保留连续的位置与速度。Run 保留对角同步的小跑，Sneak 与其它八个片段保留原定义。

`cat_foot_plant.gd` 从实际 GLB 的 `gait_walk_phases` 与 `gait_duty_factor` 读取慢走支撑时序；兼容旧资源的原相位，避免动画已改而世界脚掌支撑仍使用旧节奏。`cat_walker.gd` 的水平速度逐渐接近目标速度，转向速度减小；播放率继续使用实际水平速度，休息与受阻时重置移动速度，保存字段保持原规则。

## 验证

`audit_walk.py` 对真实重新导入蒙皮在一个完整周期取 161 个时刻，以爪部表面离地而非骨骼名称判断摆动。旧版的对角抬爪重叠为 0，胸部侧摆约 3.19°，触发新检查；新版两只猫各四项通过，对角摆动重叠比约 0.43–0.48，侧摆约 1.60°，实际抬爪最高约 13.2/13.5 mm，支撑地面误差约 0.21/0.18 mm。该比值是交集除以并集，不能直接称作完全同步。

完整九片段重新导入检查同时保留接地、支撑滑动、头身位置与实际表面拉伸门槛。新旧同光照、同镜头、同 0.12 m/s 速度的 24 秒对照在 `evidence/cat_natural_walk_20261007/compare/`，分别看斜侧与正面。参数和数字通过不替代画面自然度评审。

旧正式 GLB、作者文件和三个运行脚本备份在 `art/poc/cat_natural_walk_20261007/before/`，替换前摘要在 `source-contract.json`。新作者文件和 GLB 在 `outputs/`。安装时核对旧摘要、原子替换模型与两个运行脚本；随后完成正式导入、底面与库存更新、独立存档全量测试、真实街道走停转向与世界脚掌支撑复查。结果汇总见 `source-verified.json`。

桌面包须在独立临时目录导出、解压并完成完整 autoplay 退出 0，确认默认存档与源码摘要后才原子替换唯一 `builds/HareMachi.zip`；实际发布结果见 `release/verification.json`，不存在该成功记录时不能说编译包已更新。主场景已有退出资源释放日志单独保留。

本轮4.7.2候选包完整 autoplay 已退出0，但同期另一项工作按用户要求升级Godot4.8，源码摘要保护因此阻止了旧引擎包替换。最终采用已完成导出、解压、1329全量和200项完整演示的4.8-dev7正式包，未再次覆盖它。`reconcile_delivery.py`核对正式包摘要及其冻结源码清单：两只猫GLB、移动脚本和脚掌支撑脚本均与本轮安装摘要相同；当前工程与冻结版本仅有UI库README文字不同。正式包SHA-256为`e4ebd7806dfff0b1e1de76551d640f61436678c3b1d0053e9ed62671162ecf62`。成功记录明确区分旧候选包被阻止和当前包核对通过。

对照视频：[24秒新旧对照](../../evidence/cat_natural_walk_20261007/compare/natural-walk-comparison.mp4)，左列旧版、右列新版，上排橘猫、下排三花；[真实街道走停与转向](../../evidence/cat_natural_walk_20261007/world/natural-cats-in-street.mp4)。对照使用4.7.2渲染，正式交付的4.8版本与测试证据见`evidence/godot48_docs_20261007/`，不混用引擎验收结果。

## 复现

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_natural_walk_20261007/animate.py -- orange
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_natural_walk_20261007/animate.py -- calico
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_natural_walk_20261007/audit_walk.py -- before
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_natural_walk_20261007/audit_walk.py -- after
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_natural_walk_20261007/audit_all.py
python3 art/poc/cat_natural_walk_20261007/render.py
python3 art/poc/cat_natural_walk_20261007/reconcile_delivery.py
```

`install_verify.py`是本轮一次性安装记录，要求目标仍为旧版摘要，当前已安装版本不能再次执行；`release.py`保留当时4.7.2发布尝试，当前构建按PIPELINE的`./tools/godot`入口进行。
