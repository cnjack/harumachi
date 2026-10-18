# 其余人物源姿态修复与 MotionBricks 压力实验（2026-10-18）

本轮延续空、莲的源修复，审查其余五个人物，并在独立副本中生成六组较难的连续动作。游戏的原有站立/走跑资产与实验动作分开交付；MotionBricks片段不进入游戏、桌面ZIP或Web。

## 分人处理

| 人物 | 源检查与处理 |
| --- | --- |
| 空 | 保留前轮已修的源walk膝向，完整GLB字节不变。 |
| 莲 | 保留前轮裤腿/围裙权重与接缝修复，完整GLB字节不变。 |
| 春 | 核查腿部蒙皮、站姿、走跑与独立抬腿，未发现需套用其余人物修正的问题；保留原源文件。 |
| 澪 | 将站姿和收窄后的走路腿姿写回源动画，修正循环末端跳变；18条骨骼轨道改变。 |
| 小葵 | 将中立站姿膝向写回idle及站立手势源动画；49条轨道改变。 |
| 田中 | 将站姿腿向及左臂离开衣身的姿态写回相关源动画；54条轨道改变。跑步手臂风格仍沿用已有辅助。 |
| 和子 | 源walk膝向、run回收抬腿、站姿一起修正；61条轨道改变。run回收强度从旧辅助0.20米改为源作者采样0.21米，避免目标导入后的抬膝不足；额外1cm只保留到中段，75%至80%相位平滑退回基础恢复曲线，避免后摆顶入围裙。 |

其余五人的腿部核心顶点没有莲前轮那类髋骨误主导问题。本轮四份改动属于**源动画/姿态修复**，没有为了统一做法而重刷健康权重。七人的网格、权重、绑定逆矩阵、骨长/层级、UV、贴图、材质、原表情与衣物形态轨道保持原值。独立大角度测试仍可能暴露长裙与围裙碰撞，不将其称为全动作适配完成。

## 源作者流程与游戏辅助

`source_foundation_export.tscn`读取原GLB，关闭接地、衣物和切换修正，仅采样已验证的解剖姿态作者逻辑。原GLB以960fps无简化读入，作者输出120fps；所有原始采样先与原GLB数学插值比较，位置误差须低于0.1mm、旋转误差低于0.001rad。`bake_source_foundation.py`将局部变化作用于精确源时间，保留原二进制前缀，修正最后15%的循环残差并让首尾相同。四人重新烘焙的摘要与正式安装源文件一致。

`Rig.extras.source_pose_foundation`标明各类已作者姿态，运行时`NaturalLocomotionPose`跳过重复改腿。`CharacterFootSupport`继续处理真实地面；站在比作者平面高的铺地上时先将共同根节点抬至双脚共同所需高度，再由各脚适配不平地形，避免抬踝却不抬髋造成重新蹲下。既有动作切换、跑步手臂/手型和衣物辅助仍保留。

和子正式导入设为120fps并关闭该模型的动作简化/压缩，以保存快速回收腿的关键帧。其他模型导入设置不变。新源位于`art/models/character_roster_foundation_20261018/exports/`，清单为`art/manifests/character_roster_foundation_20261018.json`；game、library及源副本摘要一致。

复现从清单的`previous_source`开始，四份旧源摘要已核对，不能拿已带`source_pose_foundation`标记的新GLB再采一遍。以下只写新临时目录，采样场景必须作为普通场景运行，以加载其已有依赖；不能用`--script`运行。需要本轮Python环境中的NumPy/SciPy与锁定引擎，不能与全量测试并发。

```sh
ROSTER_STAGE="$(mktemp -d /tmp/harumachi-source-foundation.XXXXXX)"
export ROSTER_STAGE
python3 - <<'PY'
from pathlib import Path
import json, os
stage = Path(os.environ['ROSTER_STAGE'])
(stage / 'native').mkdir()
config = {
    'source_dir': str(Path('art/models/character_rig_review_20261018/exports').resolve()),
    'output': str(stage / 'native'),
    'extra_heel_recovery_m': .01, 'extra_recovery_settle_end': .8,
    'actors': {
        'mio': ['idle', 'walk'],
        'aoi': ['idle', 'talk', 'wave', 'bow', 'look', 'stretch', 'cheer'],
        'tanaka': ['idle', 'talk', 'walk', 'wave', 'bow', 'look', 'stretch', 'cheer'],
        'kazuko': ['idle', 'talk', 'walk', 'run', 'wave', 'bow', 'look', 'stretch', 'cheer'],
    },
}
(stage / 'config.json').write_text(json.dumps(config))
PY
HARUMACHI_SAVE_DIR="$ROSTER_STAGE/save" timeout 300 ./tools/godot \
  --headless --audio-driver Dummy --path game \
  res://scenes/source_foundation_export.tscn -- --config="$ROSTER_STAGE/config.json"
for actor in mio aoi tanaka kazuko; do
  art/poc/motionbricks_20261018/.venv/bin/python art/tools/characters/bake_source_foundation.py \
    --source "art/models/character_rig_review_20261018/exports/CH_$actor.glb" \
    --capture "$ROSTER_STAGE/native/$actor-native-source.json" \
    --output "$ROSTER_STAGE/candidate/CH_$actor.glb" \
    --report "$ROSTER_STAGE/report-$actor.json"
done
```

源独立性审计使用`audit_roster_foundation.py --models <含七人的候选目录> --output <报告.json>`。替换正式资产前，仍须进行原载荷保护核对、导入、步态/衣物回归及五方向实际画面复核。源姿态导出不更新历史Blender文件；GLB与本轮工具/来源清单共同记录当前修复。

## 回归与画面

已复核275张五方向源A/B和300张五方向实际游戏画面；98项步态与41项衣物专项通过。源A/B关闭全部游戏修正器，和子源run及澪/和子的极限抬腿仍可见衣面穿插；实际游戏继续依赖衣物辅助，不宣称纯源GLB在所有动作下衣物自足。最终独占完整回归2606/2606通过，退出0、726.12秒，测试输入摘要前后相同。原始72条ERROR分类见证据，无SCRIPT/SHADER或未分类错误；严格无ERROR资格为false。默认104份存档摘要不变。最终数据见`evidence/roster_foundation_20261018/delivery.json`。

新增五条源独立性回归：四人的辅助开关差异以及和子关闭全部修正器后的walk膝向。旧资产负控98项中恰好失败这五项，原有门槛没有放宽。另有全七人源数学审计、四份确定性重烘焙与七人保护数据对照。

提交前项目检查7815项通过；MotionBricks生成器五项输入/调度回归通过。点评页106项静态核对通过，包含十片摘要、60章及视角时间、媒体路径和JavaScript语法，不替代浏览器实点。

## MotionBricks 连续动作

使用[固定官方提交](https://github.com/NVlabs/GR00T-WholeBodyControl/tree/45c03facbf848e0c743091b7d9c17952096ff908/motionbricks)和此前已核对的四个G1权重，seed为20261018。本次六章每章12秒：不对称恢复、拳击多次变向、手足/肘撑切换、舞步整圈、肘撑爬行起身、低姿半圈。每章实际root/pose/VQ decoder各24次推理，无终端保持帧；舞步源朝向实际覆盖约363.3°，净转约357.0°，低姿净转约182.6°。模型阶段输出6×360帧，重定向七人形成42条独立POC片段。

公开G1菜单不提供翻腾/后空翻或跑步，因此不将这些动作伪称为已生成。人物适配采用原有骨比例、校准、IK和接触辅助；它不是官方人体模型为七个人分别生成动作，也没有执行动力学接触认证。章内连续生成，章与章之间独立重置。

最终十条录像均为72秒、1920×1080、30fps、H.264/BT.709、静音；七条单人、两组多人比较和一条G1源骨架，共21600帧，严格完整解码通过。每片24个采样核对原生PNG与编码同帧及前后邻帧；每片18张参考帧、共180张已逐项复核。两组多人涵盖七人全部42条动作，原生播放逐帧对照每人17个主要骨节点，共257040个变换样本，最大位置差3.462微米；骨数据匹配不等于自然度或接触通过。极限屈腿下的裙摆/围裙穿插、手肘离地及脚部接触误差继续按POC问题登记，不回写游戏来掩盖实验结果。

## 观看与点评

- [60项逐人逐动作点评页](../../evidence/roster_foundation_20261018/review-final/index.html)：慢放、逐帧、分章切换、本机记录与JSON导出。浏览器实点未验收，仅静态检查通过。
- [三人比较：空、莲、田中](../../evidence/roster_foundation_20261018/recordings-final/group-three/video.mp4)。
- [四人比较：澪、春、小葵、和子](../../evidence/roster_foundation_20261018/recordings-final/group-four/video.mp4)。
- [逐人六动作观察与边界](../../evidence/roster_foundation_20261018/motion-quality-findings.md)。

多人片为同步源时间的独立比较面板，没有人物相互接触仿真。机位按世界正面/右侧/斜侧分段，转身后不一定朝向镜头。全部录像在现有screen0、不抢焦点、静音和独立存档下完成。源模型修复与独立POC分开落盘，桌面包和Web未发布。
