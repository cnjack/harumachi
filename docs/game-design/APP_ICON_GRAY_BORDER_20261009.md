# 风铃图标灰边修复（2026-10-09）

Finder 原先显示一圈很宽的银灰底板，插画缩在中间。旧 PNG 自带圆角和透明留白，主体也含半透明像素；导出包只有传统 ICNS，没有原生图标目录。此前只核对图标文件字节，没有检查 Finder 实际显示，漏掉了系统封装效果。

保留用户选择的 B「晴空风铃」主题，用内置 imagegen 对原图生成满幅、不透明的方形插画。源图为 `art/references/app_icon/options_20261009/B-sky-windchime-fullbleed.png`，提示词在 `art/manifests/prompts/app_icon/windchime-fullbleed_20261009.txt`，alpha 全部为 255。格式工具只做等比缩放和 ICNS 封装。

用户同意许可协议后，使用 Apple Icon Composer 制作 `game/harumachi.icon`。单个满幅图层，关闭图层玻璃效果、组半透明和组阴影；Godot 导出配置增加 `application/liquid_glass_icon`。包内含 `Assets.car`，Info.plist 的 `CFBundleIconName=harumachi`，同时保留传统 `icon.icns`。Godot 4.8-dev7 的对应导出实现见 [官方源码](https://github.com/godotengine/godot/blob/c971f93e7/platform/macos/export/export_plugin.cpp#L899)。

在本机 Finder 的「显示简介」中检查实际解压应用，宽灰边已消失。截图：`evidence/app_icon_gray_border_20261009/finder-after.png`。`art/tools/audit_app_icon.py` 的 10 项新包检查通过；先拿旧图运行，透明留白检查失败，记录为 `regression-old.json` 与 `regression-new.json`。

本轮从上一份已验收源码构建独立工程，只更改图标与导出设置。工作区其他正在制作的场景改动未混入包；没有重新运行玩法全量，1359 项记录仍来自上一份已验收基线。解压应用重新跑完 200 项完整夏季演示，Q05/Q15 完成、驱动瞬移 0，退出码 0；默认存档与照片摘要未变，SQLite quick_check 通过。ZIP CRC、严格签名、包内图标一致性通过。

最新桌面包已原子替换为 `builds/HareMachi.zip`，SHA-256 `2db9ab8951a8b8120e1ac70028531effc3233b9d7c3cd9cad4c51371ede09bb2`，1721771184 字节。独立临时工程与解压应用已删除。完整记录：`evidence/app_icon_gray_border_20261009/delivery.json`。
