# 明年夏祭 · Harumachi: Next Summer

中文、键盘鼠标的日式小镇生活游戏。空回到奶奶住过的晴町，种菜、做饭、摆摊，与居民一起把停办十五年的夏祭办回来。

游戏和官网在本仓库共同维护：[官网](https://harumachi.nightc.com/) · [网页试玩](https://harumachi.nightc.com/play/) · [当前开发状态](docs/game-design/CURRENT_STATUS.md)。

## 开始开发

需要 Git LFS 和固定版本 **Godot 4.8-dev7**（`4.8.dev7.official.c971f93e7`）。这是开发快照，项目与导出模板使用相同版本。

```bash
git lfs install
git clone https://github.com/cnjack/harumachi.git
cd harumachi
git lfs pull
```

从[官方版本档案](https://godotengine.org/download/archive/4.8-dev7/)安装引擎，然后指定本机二进制路径：

```bash
export HARUMACHI_GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
./tools/godot --version
./tools/godot --headless --path game --import
./tools/godot --path game
```

引擎入口会校验精确版本。也可在忽略的`tools/godot.local.json`中配置`{"binary":"本机引擎路径"}`，不用修改共享版本锁。首次导入缓存较大，不提交`.godot/`。

## 工程布局

| 目录 | 内容 |
| --- | --- |
| `game/` | Godot工程、脚本、数据、着色器、运行素材与SQLite扩展 |
| `site/` | 官网源码、壁纸/音乐目录、统一UI样式；Web游戏从工程另行构建 |
| `docs/game-design/` | 玩法、画风、世界、验收和历史设计记录 |
| `art/tools/`、`art/manifests/` | 素材制作工具、提示词与来源记录 |
| `art/references/`、`art/library/` | 参考素材、角色authoring与素材室 |
| `tools/` | 固定引擎入口、模板安装、Web构建及项目检查 |

二进制素材通过Git LFS管理。克隆后必须拉取LFS对象，指针文件不能代替模型、图片和音频。大体量原始生成结果、试验副本、音频备选、录像、测试存档和本机证据保留在本地归档，不加入源码仓库；游戏运行所需素材完整保存在`game/`。需要原始模型的重导出步骤，按[素材流程](docs/game-design/PIPELINE.md)准备相应本地原稿。

## 验证与交付

```bash
python3 tools/check_project.py
HARUMACHI_SAVE_DIR=/tmp/harumachi-check ./tools/godot --headless --path game res://scenes/tests.tscn -- --out=/tmp/harumachi-tests.json
```

Godot全量测试须加超时，并独占运行；脚本错误会使测试挂起。模型或镜头修改还须实际截图检查。当前桌面验收基线为1359项全量与200项完整夏季演示，结果不等于自然四小时或75分乐趣已达标。完整操作规则见[AGENTS.md](AGENTS.md)。

桌面导出、解压并跑完`--autoplay`退出0后，才能替换本机`builds/HareMachi.zip`。`builds/`只保留最新桌面ZIP及最多一个Web目录，整个目录不进入Git。

官网可用`python3 -m http.server 8765 -d site`预览。可运行的Web游戏需从已验收工程制作独立Compatibility副本，再导出到`site/play/`；该生成目录不提交。构建和服务器发布见[Web文档](docs/game-design/WEB.md)与[官网说明](site/README.md)。

## 协作

以`main`维护可验证的项目状态。新修改使用短分支，通过Pull Request说明问题、改动和验证；二进制通过LFS提交。默认CI只检查源码、数据与仓库边界，不自动下载大量LFS对象或部署服务器。凭据放环境变量和本机配置，不能提交。

第三方插件、字体、CC0素材及生成素材来源见[素材许可说明](ASSET_LICENSES.md)。
