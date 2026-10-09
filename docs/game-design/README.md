# 明年夏祭 · 设计与开发文档

广场升级已进入最新桌面包：1376项独占全量、解压应用200项完整夏季通过；广场质量8项、老树9项。见[广场升级交付](PLAZA_DELIVERY_20261010.md)。Web继续使用原已验收快照。

新增[电视曲面、雪花与货架陈列修复](SHOP_DISPLAY_FIX_20261009.md)：按真实玻璃贴合节目画面，加入动态雪花与換台干扰；独立商品分层摆放、烘焙品种和疏密变化。源工程修复，当前包仍以CURRENT_STATUS交付记录为准。

[项目介绍](../../README.md) · [官方网站](https://harumachi.nightc.com/) · [GitHub](https://github.com/cnjack/harumachi)

「明年夏祭」（Harumachi: Next Summer）是中文键鼠的日式小镇生活游戏。空回到奶奶住过的晴町，种菜、做饭、摆摊，与居民一起把停办十五年的夏祭办回来。画风按[ART_STYLE.md](ART_STYLE.md)采用动漫线条、平涂、硬边阴影和通透光色。

当前代码、引擎、交付与未完成验收集中在[CURRENT_STATUS.md](CURRENT_STATUS.md)。开发与最新桌面交付已迁移到Godot4.8-dev7；精确版本由`tools/godot-version.json`指定。线上Web游戏内容基线为4.8-dev7、20261007-203612；官网最新发布20261009-141000，新增夏日壁纸收藏。具体浏览器与下载验收边界见CURRENT_STATUS。

## 现在可以玩到哪里

普通新局从序章直接安顿到家，第二天从卧室开始。首餐、麦茶、面包纸牌逐步出现，玩家可以参加、延期或先出门。主要故事经过合作小样与现场开摊、旧物和社区工作间、灯笼试挂、夏祭晚会、合影与花火，结束后恢复自由控制。

首餐和其他餐点使用真实3D网格及同一托盘的吃前/吃后变化；不依赖手到嘴的吃饭动作。家、商店、面包店和社区工作间可进入。春与小葵有共同照苗的小场景，店主有工作往返，动物位置在安全区域按作息变化。

当前夏季主线45–90分钟仅为估算。210–270分钟的自然四小时目标、连续普通三天、两种普通完整路线和75分整篇乐趣仍待验收。种田、钓鱼、布置等自由活动另计，不用测试数或自动演示时长担保容量。

## 工程与交付

- 游戏：`game/`；素材、原稿与工具：`art/`；测试、截图与录像：`evidence/`。
- 最新已验收桌面包：`builds/HareMachi.zip`，Apple Silicon/Intel通用；2026-10-08已包含起床后室内卡顿修复，解压包完整夏季验收通过后原子替换。
- `builds/`最多保留桌面ZIP和一个Web目录，不再保留日期包、备份包、解压应用或冻结工程。
- 当前1359项独占全量0失败，解压包200项完整夏季演示通过，结果见`evidence/scene_quality_delivery_20261008/delivery.json`。4.8迁移阶段的1329项记录保留在`evidence/godot48_docs_20261007/delivery.json`；迁移前4.7.2的1329项基线见`evidence/first_meal_route_20261007/delivery.json`。
- 游戏包含15种作物、32条配方、6种鱼、6项节日；`game/assets/models/`有192个GLB文件，配音登记417条。数量来自当前文件/数据，不代表自然时长。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [CURRENT_STATUS](CURRENT_STATUS.md) | 当前事实、交付与待验范围 |
| [PLAN](PLAN.md) | 已实现工作、下一步与验收门槛 |
| [GAMEPLAY](GAMEPLAY.md) | 当前流程、操作与规则 |
| [WORLD](WORLD.md) | 地图、空间、支撑与摆放 |
| [PIPELINE](PIPELINE.md) | 模型、绑定、导入、测试和导出 |
| [FUN_REVIEW](FUN_REVIEW.md) | 十一维评价与最近独立结论 |
| [SUMMER_ACCEPTANCE](SUMMER_ACCEPTANCE.md) | 四小时主线与反灌水标准 |
| [SUMMER_IMPLEMENTATION_PLAN](SUMMER_IMPLEMENTATION_PLAN.md) | 分阶段实施规格及状态 |
| [LORE](LORE.md) / [FARMING](FARMING.md) / [BALANCE](BALANCE.md) | 人物、生活系统与数值 |
| [ASSET_LIBRARY](ASSET_LIBRARY.md) / [UI_KIT](UI_KIT.md) | 3D素材室与统一界面素材 |
| [WEB](WEB.md) / `site/README.md` | Web构建与已有部署 |
| [Godot4.8迁移](GODOT_48_MIGRATION_20261007.md) | 精确版本、兼容性与本轮证据 |

最近内容记录：[室内卡顿修复](DESKTOP_STUTTER_20261008.md)、[首餐门路](FIRST_MEAL_ROUTE_20261007.md)、[餐点CLI](MEAL_MODELS_CLI_20261006.md)、[试吃用途](TASTING_USE_PLAN_20261007.md)、[居民早晨](RESIDENT_MORNING_20261007.md)、[对话修订](DIALOGUE_REVIEW_20261007.md)、[新猫绑定](CAT_FULL_RIG_20261007.md)、[运动清晰度](DIAGONAL_RUN_CLARITY_20261007.md)、[湖岸细节](LAKESIDE_POLISH_20261007.md)。这些日期记录中的旧检查数和“当轮未交付”保留历史含义，当前状态以CURRENT_STATUS为准。

## 运行

在仓库根目录执行：

```bash
./tools/godot --path game -t --position 3100,1990
./tools/godot --headless --path game --import
HARUMACHI_SAVE_DIR=/tmp/harumachi-check ./tools/godot --headless --path game res://scenes/tests.tscn -- --out=/tmp/harumachi-tests.json
./tools/godot --path game -t --position 3100,1990 -- --autoplay --autoplay-report=/tmp/harumachi-autoplay.json
```

实际测试须设置本轮独立存档目录、加超时、检查SCRIPT ERROR，并让全量独占运行。自动演示当前覆盖完整夏季到Q15；`--showcase`是节日展示夹具。导出应用不能指定场景，只传`--autoplay`等入口参数。

## 已知限制

- 人物沿用现有网格、绑定与动作。sip/give和真实物件交接已存在，但不是通用的任意物件抓握系统；坐姿与衣服变形仍有局限。
- 生成建筑中不少门和柜门是一体网格；可进入范围是家、两家店和社区工作间。
- 居民共同生活以已编排场景为主，不是自由生成的社交模拟；普通发现、后续关系和任意位置的绕行仍待更多体验。
- 植物、动物、物件通过支撑/碰撞/路径检查，不代表所有动作的视觉交叠已彻底排除；碗柜吊灯遮挡是已知待细化项。
- 当前只有夏季篇和既有初秋节日；春秋冬完整章节、第二年及30天之后的经济仍未完整验证。
- Godot4.8-dev7是开发快照。迁移兼容性与运行证据单列，未声称性能收益或启用所有4.8新功能。

刷新前的完整入口文档保存在[历史README](history/README_BEFORE_REFRESH_20261007.md)。

场景材质、牌面字体、室内用途和空间音效的当前修订见[场景质感记录](SCENE_QUALITY_20261008.md)。

当前桌面应用图标为B“晴空风铃”，最新包验收见`evidence/app_icon_windchime_20261009/delivery.json`；[图标替换记录](APP_ICON_WINDCHIME_20261009.md)。
