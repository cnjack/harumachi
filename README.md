<p align="center"><img src="site/assets/wallpapers/summer-river.webp" alt="晴川与山谷中的晴町，明年夏祭官方概念插画" width="100%"></p>

墙脚潮痕与苔纤维、石路磨耗、木牌、水面深浅和碎光、河石、连续摊位帆布及烤箱精修已写入源码，40项专项和1538项独占全量通过。新macOS包已导出并通过ZIP、解压、签名及双架构检查。最后一处旋转椅背纹向修复后的原生复拍、解压包200项演示仍待Mac解锁；当前正式桌面包和Web保持原已验收版本。见[本轮实现与待验范围](docs/game-design/MATERIAL_DETAIL_20261011.md)及`evidence/material_refinement_delivery_20261011/progress.json`。本次按用户要求先提交当前全部可入库修改。

<h1 align="center">明年夏祭</h1>
<p align="center"><strong>Harumachi: Next Summer</strong><br>一款关于归乡、日常与重逢的日式小镇生活游戏。</p>
<p align="center"><a href="https://harumachi.nightc.com/">官方网站</a> · <a href="https://harumachi.nightc.com/play/">网页试玩</a> · <a href="https://harumachi.nightc.com/#wallpapers">官方壁纸</a> · <a href="https://harumachi.nightc.com/#music">游戏原声</a></p>
<p align="center">开发中 · 中文 · macOS / 浏览器试玩 · 单人 · 键盘与鼠标<br><a href="LICENSE">MIT License</a></p>

## 回到晴町，过一个有约定的夏天

空回到奶奶曾经生活的小镇。清晨照看菜园，午后做一道家常菜，傍晚去邻居的店里坐坐。随着旧物和往事逐渐浮现，他与居民开始筹备停办十五年的夏祭，也重新拾起十岁那年留下的约定。

《明年夏祭》将生活经营与每日剧情结合起来。故事从安顿新家和第一顿饭开始，让玩家在一次次实际参与中认识晴町，与这里的人建立关系。

| 生活在晴町 | 与大家一起过夏天 |
| --- | --- |
| 种植、收获与料理，把菜园里的成果带上餐桌 | 合作试吃、集市开摊与灯笼试挂，逐步筹备夏祭 |
| 钓鱼、探索和旧物收藏，在小镇里发现往事 | 从日常对话到共餐、合影与花火，留下新的回忆 |

<p><img src="site/assets/day_1.webp" alt="游戏实机：晴町的市民农园" width="49%"> <img src="site/assets/day_3.webp" alt="游戏实机画面" width="49%"></p>
<p><em>上方为游戏实机画面；页首及官方壁纸为概念插画。</em></p>

## 开发进度

当前开发重心是夏季篇：归乡入场、生活活动、社区合作与夏祭收尾。桌面版与网页试玩分别验收和发布，官方网站提供壁纸与原声收藏。春、秋、冬的完整章节属于后续规划。

夏季篇的目标体验时长约四小时，仍在扩展与普通游玩验收中，尚未达到完整内容目标。最新版本、验证结果与已知限制以 [CURRENT_STATUS](docs/game-design/CURRENT_STATUS.md) 为准。

## 运行与开发

需要 **Git LFS** 与 **Godot 4.8-dev7**，精确版本为 `4.8.dev7.official.c971f93e7`。引擎和导出模板必须一致。

```bash
git lfs install
git clone https://github.com/cnjack/harumachi.git
cd harumachi
git lfs pull

export HARUMACHI_GODOT_BIN="/path/to/Godot"
./tools/godot --headless --path game --import
./tools/godot --path game
```

可从 [Godot 官方版本档案](https://godotengine.org/download/archive/4.8-dev7/) 获取引擎。macOS 二进制通常位于应用包的 `Contents/MacOS/Godot`。本机路径也可配置在忽略的 `tools/godot.local.json` 中；版本锁不随个人安装位置改变。

| 目录 | 内容 |
| --- | --- |
| `game/` | Godot 工程、玩法代码、数据、着色器与运行资源 |
| `site/` | 官方网站、壁纸与原声目录 |
| `docs/game-design/` | 设计规格、当前状态与验收记录 |
| `art/` | 素材工具、来源记录、参考图与可编辑素材 |
| `tools/` | 引擎入口、项目校验与 Web 构建工具 |

运行资源通过 Git LFS 管理。缓存、导出包、个人存档、大型原始生成包和本机验收证据不进入版本库。素材制作与重导出流程见 [PIPELINE](docs/game-design/PIPELINE.md)。

## 项目维护

```bash
python3 tools/check_project.py
python3 -m http.server 8765 -d site
```

每项任务完成后，执行相关自动检查和实际运行验收；通过后提交并推送 `main`，再确认远端 CI。涉及模型、镜头或界面的修改需要画面验证，游戏逻辑修改需要相应 Godot 测试。完整规则见 [AGENTS.md](AGENTS.md) 与 [维护指南](docs/REPOSITORY.md)。

三组 agent 完成全场景、多机位、天气、时间、活动和人物动物检查，最终 3021 张原生截图已逐图复核。修复七人鞋尖穿地、坐姿脚底、小葵掌心、和子围裙在走跑与舞蹈中被黑裤顶穿、湖岸路面支撑、曲线缺面和东岸隐形阻挡、西南远景空洞、上部树干相机穿入、盆踊被问候抢动作、钓鱼持竿骨骼兼容、阴雨室内光照、近镜头硬雨条及露天小院雨效缺失，试吃台和三组餐具支撑、出屋后邻里餐桌恢复，公共室内串景、室内拍照跳位和花园远景画片在自由镜头露边，以及猫的可见活动、家中金鱼和鸟虫形态。1498项独占全量与解压包200项完整夏季演示退出0，默认存档与照片未变；截图、完整测试和导出来自逐文件核对的冻结工程。见[全面视觉检查](docs/game-design/VISUAL_AUDIT_20261011.md)和`evidence/comprehensive_visual_qa_20261011/delivery.json`。Web仍为原已验快照。

此前，社区中心改为共用桌、阅读角、茶水和集中活动收纳；商店按类别成组陈列并集中冷藏奶蛋；精品面包房加入两组座位、咖啡后吧和四类独立甜点。阅读、喝茶、坐下休息、购买饮品与桌边享用均已接入。1421项独占全量、解压包200项完整夏季演示退出0，32个原生场景视角与两张商店UI截图已验，默认存档未变。见[日常格局重做](docs/game-design/INHABITED_PLACES_REDESIGN_20261010.md)与[实景改绘经验](docs/game-design/IMAGEGEN_SCENE_WORKFLOW.md)。此前树冠与绒毛苔藓继续保留。

官网发布流程见 [site/README.md](site/README.md)，网页游戏构建见 [WEB](docs/game-design/WEB.md)。发现问题可通过 [Issues](https://github.com/cnjack/harumachi/issues) 提供复现步骤、版本与截图。

## 许可

本项目的原创代码、文档及有权授权的原创素材采用 [MIT 协议](LICENSE)，版权归 Harumachi contributors。第三方组件、字体与外部素材保留各自的原始许可和使用条件，具体见 [素材与第三方许可](ASSET_LICENSES.md)。
