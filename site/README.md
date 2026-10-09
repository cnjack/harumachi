# 明年夏祭 · 官方网站

[访问官网](https://harumachi.nightc.com/) · [网页试玩](https://harumachi.nightc.com/play/) · [项目仓库](https://github.com/cnjack/harumachi)

官方网站提供产品介绍、网页试玩、官方壁纸与游戏原声。页面采用与游戏共用的纸张、图标和语义控件素材，插画遵循项目动漫画风。

## 网站内容

- 产品首页：故事、主要玩法、居民介绍与游戏实机画面。
- 壁纸收藏：16 张独立插画，其中电脑横版 9 张、手机竖版 7 张。2026 年夏日收藏「长夏来信」新增 10 张，提供 JPG 原尺寸下载与 WebP 预览。
- 游戏原声：18 首曲目，支持播放、暂停、进度与 MP3 / OGG 下载。
- 试玩入口：中文键鼠操作，进度保存到浏览器本地数据库。清除站点数据会移除本地进度。
- 项目动态与反馈：链接 GitHub 仓库和 Issues，不使用占位邮件订阅。

网站为静态 HTML、CSS 和 JavaScript；字体、图片与音乐均在本站提供，不依赖外部 CDN。代码与可授权的原创内容采用 MIT；字体等第三方许可见根目录 ASSET_LICENSES。

## 本地预览

```bash
python3 -m http.server 8765 -d site
```

打开 `http://127.0.0.1:8765/`。`#wallpapers`、`#music`、`#play` 支持直接进入及前进后退；页签支持方向键、Home 和 End。移动设备默认显示竖版壁纸。开启系统“减少动态效果”时减少动画，隐藏页面暂停背景画布。

网站源码可直接预览。可运行的 `play/` 是独立生成产物，不进入 Git；构建方法见 [WEB.md](../docs/game-design/WEB.md)。

## 图片与字体

素材目录集中在 `assets/library.json`。新增图像需记录实际宽高、文件大小、题材与来源，不将插画标为实机截图。长夏来信原图保存在 `art/references/site/wallpapers/summer_20261009/`，提示词与生成记录位于 `art/manifests/`。网页预览压缩为 WebP，下载 JPG 保留原尺寸，不放大。

UI 使用 `ui.css` 与 `assets/ui/`，来源是 `game/ui_kit/`。按钮、卡片不另造私有皮肤。霞鹜文楷与知漫星使用附带的 OFL 许可。修改页面或目录中的中文后重新生成字体子集：

```bash
python3 tools/web/subset_site_fonts.py
```

## 验证

```bash
python3 tools/check_project.py
python3 tools/web/check_site.py
```

自动检查验证目录、图片实际尺寸、下载文件、页面资源、字体字符和许可证。发布前还须在浏览器检查桌面与手机布局、页签、图片加载、音乐播放、实际下载和试玩入口。游戏本体有变更时，额外验证启动、保存、刷新继续、分段下载及数据库恢复。

## 发布

正式域名由现有 Caddy 服务提供 HTTPS。发布目录是 `/data/harumachi/releases/<release>`，`current` 指向当前版本；宿主机路径为 `/var/lib/containers/storage/volumes/netbird_netbird_caddy_data/_data/harumachi/`。

每轮发布遵循：

1. 在独立临时目录冻结已验收网站，生成逐文件 SHA256 清单。
2. 上传到服务器的新 release。若只更新官网，复用当前已验收游戏文件，记录游戏内容基线，并重新绑定该 release 的资源前缀。
3. 在切换前校验所有文件摘要与容器内资源路径。清单只包含线上文件，排除README；重新生成变更脚本的`.gz`，解压内容必须与对应源码一致，不能复用旧压缩副本。
4. 原子切换 `current`，保留旧 release 用于回滚。
5. 检查线上文件、下载、浏览器画面、WASM MIME、COOP/COEP 与 PCK Range；普通响应和浏览器压缩响应均须匹配冻结文件，保存证据后清理本轮临时文件。

`play/index.html` 的 `config.assetBase` 绑定 `/play/releases/<release>/`。各 release 的 `play/releases/<版本>` 链接指向容器内对应的 `/data/harumachi/releases/<版本>/play`，保证切换期间已打开的游戏仍可获取原版本资源。

Caddy 配置没有变化时无需 reload。调整配置须先验证，且保留绑定文件的 inode。回滚以相同的软链原子切换方式恢复旧 release，不能覆盖已发布目录。

最新官网发布摘要见 [WEBSITE_COLLECTION_20261009](../docs/game-design/WEBSITE_COLLECTION_20261009.md)。网页游戏内容基线为 `20261007-203612`、Godot `4.8.dev7.official.c971f93e7`；此次网站更新不重新导出游戏。历史 Web 验收见 [WEB_RELEASE_20261007](../docs/game-design/WEB_RELEASE_20261007.md)。
