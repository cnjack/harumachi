# 明年夏祭 · 官网（Coming Soon）

当前官网与网页版已部署Godot4.8-dev7，发布`20261007-203612`。本地浏览器启动、自动/手动保存、刷新和继续通过；线上146文件、资源类型与分段响应通过。旧发布`20261004-012728`保留回滚。线上完整首次加载已打开实际游戏标题，无浏览器错误，资源包约324.16 MiB；实测当前线路约0.14 MB/s，首次等待较长。最终状态见`evidence/web48_deploy_20261007/`。

纯静态网站：`index.html`、`style.css`、`ui.css`、`play.css`、`main.js`、`library.js`，不依赖外部资源。固定页头有“晴町 / 壁纸 / 音乐 / 试玩”四个tab。`play/`是Godot4.8-dev7的浏览器导出，沿用游戏当前的UI与每日自动保存。

```bash
python3 -m http.server 8765 -d site      # 本地预览：http://127.0.0.1:8765/
```

- 页面由 codex 按 `art/manifests/prompts/site/build_brief.md` 生成；插画由 codex 按 `art/manifests/prompts/site/{hero,night,cast}.txt` 画（附了游戏里的角色头像），原图在 `art/references/site/`，网页用的是 `assets/*.webp`（带 jpg / png 兜底）。
- 画风按 `docs/game-design/ART_STYLE.md`：新海诚风格的动漫风，不走写实。
- 动画：主视觉缓慢推拉和视差、飘过的云、光点、逐字出现的标题、摇晃的纸灯笼、滚动渐显、角色头像浮动、胶片条自动滚动、夜景上的烟花。系统开了“减少动态效果”时只保留淡入。页面不在前台时画布动画暂停。
- 字体：霞鹜文楷的子集 `assets/fonts/wenkai-sub.woff2`（OFL，许可证在旁边）。改了文案要重新做子集：

  ```bash
  python3 - <<'PY'
  from fontTools import subset
  t = "".join(open(f"site/{f}").read() for f in ["index.html", "style.css", "main.js", "library.js", "assets/library.json", "play/index.html"])
  t = "".join(sorted(set(c for c in t if ord(c) > 0x2000) | set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ")))
  o = subset.Options(); o.flavor = "woff2"; o.layout_features = ["*"]
  f = subset.load_font("game/assets/fonts/LXGWWenKai-Medium.ttf", o); s = subset.Subsetter(o); s.populate(text=t); s.subset(f)
  subset.save_font(f, "site/assets/fonts/wenkai-sub.woff2", o)
  PY
  ```

- 「一起过夏天」印章（`.cast-stamp`）用的是"知漫星"毛笔字体子集 `assets/fonts/zhimangxing-sub.woff2`（OFL，许可证 `assets/OFL-ZhiMangXing.txt`），只挑了印章上那几个字，改了字要重新子集化。
- 「在晴町的一天」6 张卡片（`assets/day_1..6.jpg/webp`）是游戏里的实机截图，不是插画：种菜/做饭/过节/旧物是 `game/scripts/tools/shots.gd` 的 `--clean=1` 模式截的（隐藏 HUD、通知卡片和 NPC 头顶名字后，`--views=farm_field,ui_craft,fest_hanabi,ui_book_col`），摆摊是从 `evidence/screens/11_bread_on_stall.png` 裁掉 HUD 得到的，小游戏是 `evidence/screens/minigames/onigiri_play.png`（本身就是插画风格的 2D 小游戏界面）。要换图或加新视角，直接扩展 `shots.gd` 的 `VIEWS`。
- 订阅表单目前没有后端，只存在浏览器的 localStorage 里（页面上写明了）。接入真正的邮件服务时改 `main.js` 里的提交处理。
- 录屏：`evidence/site_coming_soon.mp4`。

## 壁纸和游戏音乐（2026-10-01）

- 固定页头的两个新 tab 使用 `#wallpapers`、`#music`，支持直接打开、刷新和浏览器前进后退。左右方向键、Home、End 可切换 tab。
- 壁纸：晴川夏日、夏祭灯火、雨后晴町，共 6 张；每个主题各有电脑横版和手机竖版。由内置 imagegen 分别生成，手机打开时默认显示竖版；也能手动切换设备。页面标明文件的实际尺寸和大小，提供 JPG 下载、WebP 预览。
- 壁纸原始 PNG 在 `art/references/site/wallpapers/`，提示词在 `art/manifests/prompts/site/wallpapers/`，来源记录在 `art/manifests/images_codex.json`。网站文件在 `assets/wallpapers/`。只转换格式，没有裁剪或放大生成图。
- 音乐：使用 `game/assets/audio/music/` 里的 18 首完整曲目，总长约 20 分 36 秒；网站 MP3 是 192 kbps，OGG 保留游戏原文件。播放器支持暂停、进度拖动和下载；进入页面不会自动播放，切换到其他 tab 时暂停。播放器未选曲前隐藏。
- 文件目录和曲目标题集中在 `assets/library.json`。新增图片、修改曲名或页面文案后，按上面的命令重新生成字体子集。
- 本地验证截图、播放状态、浏览器实际下载校验、发布包和线上检查记录放在 `evidence/site_tabs_20261001/`。

## 部署到 harumachi.nightc.com

官网地址：<https://harumachi.nightc.com/>。2026-09-30 首次部署，服务器是 `root@nightc.com`（`123.56.123.127`）。

- 复用 Podman 容器 `netbird-caddy`，站点配置追加在 `/root/netbird/Caddyfile`；Caddy 负责 HTTPS 证书和续期，HTTP 自动跳到 HTTPS。
- 容器内的网站根目录是 `/data/harumachi/current`，它指向 `releases/<版本号>`。宿主机对应 `/var/lib/containers/storage/volumes/netbird_netbird_caddy_data/_data/harumachi/`，文件保存在已有的 Caddy 数据卷里。
- 首次版本：`20260930-235301`。配置备份、上传包和校验日志在服务器的 `/root/netbird/deployments/harumachi/20260930-235301/`。
- 当前版本：`20261007-203612`，更新完整夏季、当前模型、入场与首餐门路；146文件摘要通过。前版`20261004-012728`保留回滚。
- 上线的是`index.html`、`style.css`、`ui.css`、`play.css`、`main.js`、`library.js`、`assets/`与`play/`。首页canonical、og:url、og:image使用正式域名。
- 文件使用 `Cache-Control: no-cache`，浏览器复用缓存前会确认版本。页面订阅仍然只存浏览器 localStorage，尚未接邮件服务。

### 更新页面

在仓库根目录执行；每次创建一个新版本，再切换 `current`，不需要重启或重新加载 Caddy。

```bash
release=$(TZ=Asia/Shanghai date +%Y%m%d-%H%M%S)
COPYFILE_DISABLE=1 tar -czf "/tmp/harumachi-$release.tar.gz" -C site index.html style.css ui.css play.css main.js library.js assets play
scp -O "/tmp/harumachi-$release.tar.gz" "root@nightc.com:/root/harumachi-$release.tar.gz"
ssh root@nightc.com bash -s -- "$release" <<'SH'
set -eu
release=$1
site_root=/var/lib/containers/storage/volumes/netbird_netbird_caddy_data/_data/harumachi
test ! -e "$site_root/releases/$release"
mkdir -p "$site_root/releases/$release"
tar --no-same-owner -xzf "/root/harumachi-$release.tar.gz" -C "$site_root/releases/$release"
find "$site_root/releases/$release" -type d -exec chmod 755 {} +
find "$site_root/releases/$release" -type f -exec chmod 644 {} +
ln -s "releases/$release" "$site_root/current.next-$release"
mv -Tf "$site_root/current.next-$release" "$site_root/current"
SH
curl -fI https://harumachi.nightc.com/
```

回滚页面时，把 `current` 用同样的 `ln -s`、`mv -Tf` 两步切回保留的旧版本。修改 Caddy 配置时要先校验再 `caddy reload`；`Caddyfile` 是单文件 bind mount，写回时保留原文件的 inode，不能用重命名替换它。

首次上线证据在 `evidence/site_deploy_20260930/`：`release.json` 记录版本和发布包摘要，`SHA256SUMS` 是 44 个发布文件的摘要，`verification.json` 记录线上逐文件校验，`homepage.jpg` 是正式域名的浏览器截图。

## 网页试玩与加载动画（2026-10-01）

`#play` 打开试玩介绍，`play/` 进入游戏。电脑键鼠操作，游戏和设置保存到浏览器本地的 SQLite 数据库；清除站点数据会清除进度。网页启动显示真实下载进度，游戏内分段建场景时显示灯笼动画。壁纸预览、目录读取和音乐缓冲也有加载反馈。

当前资源包约324.16 MiB，首访需要下载，按4 MiB分段重试；完成后再启动游戏。preloadFile传下载结果的ArrayBuffer，不能直接传Uint8Array。进度条显示真实字节，网络中断重试当前部分，失败提供重新加载。

试玩采用 Compatibility 渲染器，网页纹理和字体单独做瘦身，桌面素材保持原样。构建、数据库 schema、加载层、服务器响应头和验证流程见 [WEB.md](../docs/game-design/WEB.md)。WebAssembly 需要正确的 `application/wasm` MIME；`/play/*` 需要 COOP/COEP 响应头，Caddy 的 file_server 同时启用预压缩 gzip 文件。首次加入游戏时要先更新这段 Caddy 配置，以后换导出包只需切换版本。

## 统一UI与每日存档（2026-10-04）

UI皮肤与图标由game/ui_kit导出到assets/ui，导航、按钮、播放器、试玩加载卡共用同一画风。ui.css只维护语义角色和尺寸；不要修改生成PNG。play.css控制外壳，游戏本体继续用Godot控件。每天结算后自动保存到当前浏览器，工具栏显示成功/失败；手动保存仍可使用。

构建使用本轮独立临时目录：prepare_web.py --source <已验收的临时冻结工程> --target <本轮临时目录>/web-game --evidence <本轮目录>。验收后只保留builds/web/最新导出，清理临时工程；本地builds保留规则见AGENTS.md。当前构建及143文件发布摘要在evidence/daily_web_release_20261004；线上10项官网交互、9文件字节及Range/响应头通过。本地游戏启动、保存、刷新继续也通过。历史过程和验收见 [每日存档与网页发布](../docs/game-design/DAILY_SAVE_WEB_20261004.md)。

## 版本资源路径与本轮发布

导出的HTML注入config.assetBase=/play/releases/<release>/；JS、WASM、SQLite扩展和全部PCK段绑定相同发布。服务器新release的play/releases/<版本>软链指向容器内/data/harumachi/releases/<版本>/play，创建后检查Caddy容器能读到相同PCK摘要，再原子切current。每次发布必须重置版本前缀，不能复用上一版HTML前缀。SHA256SUMS和部署校验保存在/root/netbird/deployments/harumachi/<release>及本地evidence；无Caddy配置变化时不reload。

本地builds/web是一个可独立预览的当前导出，site/play为已部署版本绑定的外壳。site/play/releases/<当前版本>仅是指向父目录的本地预览软链，没有复制旧Web包。预览可使用python3 tools/web/serve_preview.py --root site --port 8770；线上核验使用tools/web/verify_deployment.py --site <冻结网站目录> --manifest <SHA256SUMS> --evidence <证据目录> --release <版本>。
