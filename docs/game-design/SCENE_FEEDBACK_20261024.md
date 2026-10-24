# 试玩截图修整（2026-10-24）

用户提供 11 张截图，指出冰柜、屋内外店主、车辆、告示牌、木材、农园入口、街树、空摊和非节日摆件的问题。本轮按 12 个问题分别分配 agent，主任务统一合入源资产、实际渲染复核及交付。

## 逐项处理

| 问题 | 负责 agent | 改动 |
| --- | --- | --- |
| 冰柜 | freezer_rebuild | 移除顶面商品照片，重建真实内腔、四格铁篮、独立冰品、滑动玻璃和把手。 |
| 店主屋内外重复出现 | shopkeeper_uniqueness | 保留单一邻居实例，按营业日程进入实际工作区域，进出房间只改变可见性；空柜台不触发店主交易。 |
| 漂浮海报、空白立板 | plaza_signs | 修平公告栏原网格的局部承载面，纸张贴合正面；两块高立板改成活动期间才出现的双面矮木牌。 |
| 木材颜色 | plaza_timber_palette | 庭院桌、椅、棚、滑梯木架和低台使用同一暖杉木色范围，保留木纹、原 UV、金属及非木部件。 |
| 公交车 | bus_rebuild | 在保留原车身涂装的基础上重做真实窗洞、窗框、玻璃、活动门、车内座椅和线路灯箱；复拍发现的车壳缺口及轮拱破边也在源网格修正。 |
| 公交站牌 | bus_stop_sign_rebuild | 改为有厚度和卷边的金属牌盒，文字贴合牌面，固定臂和螺钉实际连接棚檐。 |
| 运菜车 | kei_truck_rebuild | 两处实例共用圆弧车顶、压制车身、完整轮拱、圆轮胎、内嵌车灯、镜面、踏板和货斗五金；保留原菜箱、蔬菜与贴图。 |
| 农园入口 | farm_approach_terrain | 移除竖直封口，连续下坡并转弯接回草地，坡面 UV 保持实际面积；坡地与远景共用草地基色，小路远端自然淡入。 |
| 街树 | street_tree_rebuild | 替换面包店旁单株树：独立榉树冠、分枝、暖灰棕树皮、入土短根、真实树池与树干碰撞。 |
| 空摊 | stall_lifecycle | 普通日无用途时整摊收纳；备货、真实送达、合作试吃和集市才摆出，食品随剩余份数显示。 |
| 滑梯 | slide_rebuild | 重做连续曲面和出口、圆卷边、完整梯级、平台护栏、木架与连接五金，保持占地和玩法入口。 |
| 非节日摆件 | festival_prop_lifecycle | 平日收起舞台、太鼓和金鱼池的模型、碰撞与交互；活动按筹备、开场、收场展开，日常可从公民馆借用，结束或取消后归还。 |

## 源文件与复现

六个修改或新增的模型为 `I07_ice_freezer`、`B01_bus`、`D07_kei_truck`、`P02`、`P05` 和 `T12_street_zelkova`。权威源及可编辑制作文件放在 `art/library/appliances/`、`vehicles/`、`signage/`、`plaza/` 和 `street_trees/`。配置统一登记在 `art/models/game_assets.json` 的 `assets` 对象，项目检查会拒绝错误放在顶层、导致导出器跳过的模型条目。

对应来源清单：

- `art/manifests/models_freezer_20261024.json`
- `art/manifests/models_bus_cabin_20261024.json`
- `art/manifests/models_kei_truck_20261024.json`
- `art/manifests/noticeboard_mount_20261024.json`
- `art/manifests/models_slide_20261024.json`
- `art/manifests/models_street_tree_20261024.json`
- `art/manifests/bus_stop_sign_20261024.json`
- `art/manifests/plaza_signage_20261024.json`

模型经原 `game_export.py` 导出，使用 `level_check.py` 检查真实支撑面并同步 `_stats/_level.json`。新工具分别审计窗洞、车壳、轮拱、柜内结构、滑面连续性、纸面覆盖和树干/冠层尺寸；旧数据的失败记录保存在本轮证据目录，容差不因新版失败而放宽。公交中间版本的车头缺口、货车后窗挡杆、海报穿插和站牌固定件埋入过深都保留失败记录，并修正来源后再验。

运行时专项为 `shopkeeper-presence`、`bus-cabin`、`plaza-signage`、`street-tree`、`farm-approach`、`stall-lifecycle`、`plaza-timber`、`bus-stop-sign`，并扩展既有 `truck-glazing` 和 `props-lifecycle`。这些组已接入全量入口。自动演示使用真实公民馆借用菜单进入平日金鱼小游戏。

截图入口保留在 `scene_feedback_capture.gd`、`plaza_signage_capture.gd`、`farm_approach_capture.gd` 和 `plaza_timber_capture.gd`。使用现有 screen 0、原生渲染、静音和隔离存档；截图清单记录实际渲染帧。没有创建虚拟屏幕。

## 整合回归

首轮全量跑完 2798 项，没有脚本错误，暴露 24 项失败。除六个变更模型的审计摘要需要重算外，既有剧情和相机测试也需要按实际状态准备场景：平日收纳的空摊不能交互，纸牌使用店内入口，试吃先离开房屋，借用低台或太鼓必须经过真实活动状态，集市店主和摊位要同步迁移。原有距离、支撑、相机遮挡和剧情断言保持；相关五组复验 197 项通过。

角色回归另有两处与本轮模型无关的历史版本假设。空的跑姿改用现有 revision3 的横胸摆臂几何契约，保留旧姿态的原断言。莲的 19 项认证保护测试使用与原认证摘要一致的真实 revision2 源模型，另加 3 项当前 revision3 的实际安全回退检查；没有为当前版本补签认证或更改运行时保护。该历史样本位于 `scripts/tests/fixtures/`，沿用所有导出预设对测试目录的排除规则。

公交轮拱的中间版本虽然通过局部检查，原生复拍仍出现双轮拱和撕裂。复查完整原网格后确认旧轮胎分件使用了错误轴心，真实轮圈还残留在静态车壳。后续源检查改为测量完整轮圈、四轮完整周向覆盖及静态车壳的轮胎残留，并以被拒版本作反例。最终源与游戏模型各 20 项检查通过，六视角原生复拍确认双轮拱及撕裂消失。

## 验收与交付

最终 Godot 4.8-dev7 独占全量 2799/2799 通过，退出 0，用时 935.12 秒；没有 SCRIPT/SHADER ERROR。293 个模型完整审计通过，六个变更模型的权威源、游戏摘要、支撑面记录与模型清单一致。12 项均完成原生复拍；解压应用 211 项完整演示通过，并额外复核 15 张成品关键位置截图。

ZIP 完整性、应用签名及成品 PCK 检查通过；检查了挂载后的 4921 个资源路径，没有测试场景、测试脚本或历史角色样本。当前验证平台为 macOS arm64；Intel 的可选衣物加速库未提供，已有代码使用 GDScript 回退，未作 Intel 实机验收。headless dummy renderer、故障负例和本机编辑器主题日志另有分类；解压演示退出时另记录一条 shader RID 释放提示，不将日志称为严格零 ERROR。

`builds/HareMachi.zip` 已原子替换，字节数 2623131226，SHA-256 `d5fd6f251190581f0c2bb8abfcb264c048381c5d04060ae1c1108be400900eda`。默认 104 份存档和照片摘要不变，旧解压应用及临时导出目录已清理；Web 保持原版本。证据根目录为 `evidence/visual_rework_20261024/`，交付摘要 `delivery.json`，对照页 `index.html`。

这轮修整不等于此前普通 E/空格重复对话已经复现，也不代表自然游玩时长或所有人物动作获得用户认可。那些问题仍按各自记录保留范围。
