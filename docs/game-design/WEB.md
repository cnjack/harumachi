# 网页试玩、SQLite 存档与加载反馈

开发与线上Web已更新到4.8-dev7，当前发布20261007-203612，本地浏览器保存刷新继续、线上146文件与响应头已验。线上完整冷启动已实际打开游戏标题且无浏览器错误；旧4.7.2的版本、大小和573项以下保留历史身份。当前资源为324.16 MiB，版本固定资源URL和详细记录见site/README及evidence/web48_deploy_20261007。

2026-10-04更新：官网与试玩外壳共用统一UI素材库，当前发布版本20261004-012728，PCK为233,557,004字节（222.74 MiB）。每日结算由advance_day统一自动保存，网页通过save_finished更新保存反馈。发布冻结工程573项通过，浏览器实际保存、刷新与继续恢复通过。完整记录见 [每日保存与网页发布](DAILY_SAVE_WEB_20261004.md)；下面的116 MiB和332项属于2026-10-01记录。

2026-10-01。引擎继续固定 Godot 4.7.2，网页使用 Compatibility 渲染器，桌面工程保留 Forward+。网页试玩面向电脑键盘和鼠标。

## 存档

`game/scripts/autoload/save_db.gd` 使用 Godot-SQLite v4.9（MIT，SQLite 为公共领域）。macOS、Windows x86_64 和单线程 Web 编译库放在 `game/addons/godot-sqlite/`，下载包的 SHA-256 已与官方 release 对照（Windows 库于 2026-10-10 从同一 v4.9 包补齐，见 `evidence/windows_sqlite_20261010/`）。

数据库为 `user://harumachi.db`，备份为 `user://harumachi.backup.db`。表结构：

| 表 | 内容 |
| --- | --- |
| metadata | 数据库 schema 版本和旧存档迁移标记 |
| snapshots | current、previous 两份 v4 进度快照，附 SHA-256 和保存时间 |
| settings | 每个设置项的名称和值 |

进度快照在 SQLite 事务中替换；参数绑定保留中文和引号，失败时回滚。数据库损坏时先保留损坏文件，再从一致性备份恢复。未来 schema 版本会拒绝读取，不会用旧备份覆盖它。旧 `save.json`、`save.bak`、`settings.json` 只迁移一次，文件保留。`config/custom_user_dir_name="晴町日常"` 不变。

浏览器内也执行 SQLite，数据库文件由 Godot 的浏览器文件系统持久保存。SQLite 写入后额外关闭一个 FileAccess 同步标记，通知浏览器文件系统保存。存档不上传服务器、不跨浏览器同步。隐私模式或清除站点数据可能使进度消失，试玩页面已说明。

测试可用 `HARUMACHI_SAVE_DIR=/tmp/<本轮目录>` 隔离进度和设置，不接触玩家数据库。全量测试会生成游戏里的照片，测试前后保留并恢复玩家已有的 `photo_natsumatsuri.png`。

## 加载反馈

- `Loading` autoload：灯笼动画、文字、进度条和输入/时钟锁定；等待时仍能画帧。
- 主场景先预载模型，再逐段建环境、建筑、道具、家和农园；`loading_ready` 为真后才处理游戏输入。
- 读档、回标题和场景切换共用加载层；进出区域使用简短提示。
- 网页外壳显示真实下载字节、初始化动画和可重试的失败提示；点击“开始游玩”后启动引擎和声音。
- 主资源包按 4 MiB 的 HTTP Range 分段下载，每段可重试 4 次；已完成的部分留在内存中。下载完交给官方 Engine.preloadFile，再 Engine.start，避免大文件中断后默认加载器停在进度条。
- 官网壁纸有图片加载指示及失败提示，音乐有缓冲提示。系统要求减少动态效果时停止 CSS 旋转。

加载层的视口覆盖和居中检查曾在旧实现中失败，修正后通过，证据为 `loading-before-fix.json` 和 `loading-after-fix.json`。

## 构建

在仓库根目录执行，Python 需要 Pillow 和 fontTools：

```bash
python3 tools/web/install_web_templates.py
HARUMACHI_WEB_STAGE="$(mktemp -d /tmp/harumachi-web.XXXXXX)"
cp -cR game "$HARUMACHI_WEB_STAGE/frozen-game"   # 当前game须已完成验收
<项目 Python> tools/web/prepare_web.py --source "$HARUMACHI_WEB_STAGE/frozen-game" --target "$HARUMACHI_WEB_STAGE/web-game" --evidence evidence/<本轮目录>
GODOT=/Users/jack/workpath/godot/tools/godot-4.8-dev7/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path "$HARUMACHI_WEB_STAGE/web-game" --import
mkdir -p "$HARUMACHI_WEB_STAGE/export"
$GODOT --headless --path "$HARUMACHI_WEB_STAGE/web-game" --export-release Web "$HARUMACHI_WEB_STAGE/export/index.html"
```

完成下述浏览器和保存验收后，将本轮export目录作为最新的builds/web替换，清理旧Web和本轮临时工作目录。builds只保留HareMachi.zip和web/，校验记录放evidence。

当前Web工具按tools/godot-version.json从官方4.8-dev7包按ZIP字节范围安装同版模板；原4.7.2模板安装是2026-10-01历史记录。当时只安装 `web_dlink_nothreads_{debug,release}.zip`，逐文件校验 ZIP CRC。插件启用 Extension Support，关闭 Thread Support。临时网页编译目录与桌面源码分开：模型纹理和独立图片降到适合浏览器的尺寸，普通纹理改用有损压缩，字体按游戏文案做子集；网格、骨骼和动画缓冲不变。保留原配乐、配音和音效，没有重新生成声音。

2026-10-01的游戏资源包约116 MiB；2026-10-04增加近景素材后约222.74 MiB。另有引擎和SQLite WASM。脚本和WASM可以生成`.gz`同名文件，Caddy用`file_server { precompressed gzip }`提供压缩版本。PCK本身已压缩，重复gzip收益很小，可省略。官方Engine.preloadFile要传pack.bytes.buffer，传Uint8Array会作为对象键转换为巨大字符串并触发Invalid string length。

本地预览：把 `builds/web/` 导出文件复制到 `site/play/`，然后 `python3 tools/web/serve_preview.py`。访问 `http://127.0.0.1:8770/play/`。

## 部署与验证

官网增加“在线试玩”tab，游戏放在 `/play/`。已有 Caddy 的 `harumachi.nightc.com` 站点仅对 `/play/*` 增加：

```caddyfile
@game path /play/*
header @game {
    Cross-Origin-Opener-Policy same-origin
    Cross-Origin-Embedder-Policy require-corp
}
```

发布包包括`index.html`、`style.css`、`ui.css`、`play.css`、`main.js`、`library.js`、`assets/`、`play/`。网页皮肤由game/ui_kit/export_web_skins.gd导出到site/assets/ui/；prepare_web要求新的隔离目标，保留UI图集及像素目录原尺寸。上传后逐文件核对摘要，再原子切换current。配置无变化时不改Caddy；保留上一版软链接及发布目录，以便回滚。

验证记录放在 `evidence/web_sqlite_20261001/`：SQLite 迁移、事务、设置、校验损坏、数据库损坏恢复和 schema 拒绝；加载层覆盖、居中、进度和锁定；浏览器保存后刷新、实际继续、游戏画面，以及慢速网络下的图片/音乐加载反馈。原生导出包需要解压后跑完整`--autoplay`，确认Q05/Q15、夏季完成、保存与控制恢复及退出码0。

当前回归为 332 项、0 失败，并确认没有 SCRIPT ERROR。迁移后发现旧 TIME 测试仍按 JSON 读取数据库，造成两项检查被跳过；已改成读 SQLite 快照，重新完整运行后包含这两项。最终原生包完整演示 1220.2 秒，Q05 完成，退出码 0。首次网页版启动的整包下载在公网中断，随后增加分段和重试；资源包和 WASM 不变。
