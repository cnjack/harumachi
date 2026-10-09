# 猫的持续张望、小步与低尾复验（2026-10-07）

用户再次指出脸只看一个方向、脚走得不对、尾巴偏高。这轮修正正式巡游橘猫与三花猫的 Walk/Idle 和运行时头颈控制；保留 59 关节、12 节尾链、八权重、原网格与 UV。没有新生成模型或更新桌面编译包。

## 原因与修改

上一轮的头部张望虽然与脚步频率不同，仍烘在 Walk/Idle 片段里。停走切换重播片段时也会重播张望。把“骨骼完整片段有 32° 变化”当作脸会持续左右看，验收不够。现在 `cat_look.gd` 在动画播放后修改骨架，注意力时钟独立运行：正前方、向一侧看并短暂停留、回正、向另一侧看。常规幅度左右各 45°，转向提示与近距离看玩家最多 50°。两只猫的正面近景分别用于确定中立头部偏航修正，橘猫 -35°、三花猫 -30°；保留上一轮低头修正。

头部变形不能只靠骨骼角度验收。扩大张望后，发现旧头部权重泄漏到肩背，且邻边的头部权重会突然相差约 20%。本轮移除远离头部的影响，在物理重合顶点合并的表面邻接图上平滑头颈过渡；保留面部与耳朵细节的绑定。UV 接缝两侧统一权重，再限制八个影响。正负 50° 的实际蒙皮极限检查保留了旧失败数据，最大局部边长倍率从约 12.8/13.9 降至 6.2/6.6。该数字用于抓大片拉扯，不代表所有局部变形都已自然。

原四拍落脚顺序没有倒置。异常主要来自 15 cm 步幅、约 2.4 cm 抬爪与过低身体：慢走像跨步。现在步幅 10 cm，步速仍为 0.12 m/s，周期 0.8333 秒，10 秒 Walk 包含十二个周期。支撑占 76%，摆动轨迹在离地和落地边界保留与支撑阶段相同的速度，避免原先轨迹瞬间换速；摆动爪部实际抬高约 1.1–1.5 cm，身体下降由约 2.5 cm 改为 1.6 cm。前肘向后、后膝向前的关节平面保留。

尾根取消额外抬高的 2 cm，尾链改为轻微下垂、后段与尾尖缓慢上弯。尾尖落在背部下方，继续有左右延迟摆动；没有改回夹尾。尾巴网格、尾链密度和尾根限制区域保持不变。

## 验证方式

- `audit_motion.py` 对两只导出 GLB 各取 121 个时刻，测实际爪部、接缝、尾端和躯干。旧版在步幅、抬爪、下蹲与尾巴高度四项失败；新版完整循环通过。直线支撑阶段的偏移和接地不替代所有转弯、地形验证。
- `audit_gaze.py` 在五个步态时刻分别加入 -50°、0°、50° 的运行时头颈变形，对实际八权重表面测拉伸。旧头颈权重触发失败，修复后两只猫通过。
- `cat_motion_verify.gd` 检查实际正式资源的关节数、八权重、片段时长和步速；交替重播 Walk/Idle 每 1.5 秒，用 modifier 完成信号时的姿态计算实际头部表面前后点方向，验证张望在重播后仍连续。旧片段重复播放的表面方向范围约 17°，不能通过持续张望要求；新版约 90°。
- 独立 Forward+ 对照录像使用同光照、同镜头、真实 0.12 m/s 前移和 10 cm 地面线。左列上一版、右列修改后；有侧面脚步、十二秒正面张望、斜侧与待机。真实街道录像使用原 AmbientLife、巡游路径、碰撞与停走逻辑，镜头相对猫身体固定，避免把身体转向误当头部张望。
- 主场景 LIVING 26 项和 PROPS 46 项复验。相关测试、录像使用独立存档目录，并核对默认存档摘要。主测试集计数没有改变。全量没有与正在运行的其他原生 Godot 窗口并发执行。

主场景既有退出资源释放日志仍保留；没有把它写成整个项目无错误。眼球、眨眼和口型尚未增加独立绑定，本轮处理的是头颈朝向和身体步态。

## 文件与复现

当前正式 GLB 为 `game/assets/models/AN_cat_{orange,calico}_walk.glb`；可编辑源在 `art/poc/cat_motion_review_20261007/outputs/revised/`。上一版两个源文件和实际失败检查保存在本轮 `outputs/before/` 与 `evidence/cat_motion_review_20261007/`。修改前后摘要见 `integration.json`，最终汇总见 `verified-final.json`。

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_motion_review_20261007/build.py -- orange
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_motion_review_20261007/build.py -- calico
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_motion_review_20261007/audit_motion.py -- before
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_motion_review_20261007/audit_motion.py -- revised
$BLENDER -b --factory-startup --python-exit-code 1 -P art/poc/cat_motion_review_20261007/audit_gaze.py
python3 art/poc/cat_motion_review_20261007/render.py
python3 art/poc/cat_motion_review_20261007/verify_final.py
```

构建只写 POC；正式替换工具先要求候选检查通过，再核对当前摘要、导入、测底面与库存、跑相关测试及实际街道录像。正在运行的旧游戏实例需要重开才会加载新资源；`builds/HareMachi.zip` 本轮未重新导出。
