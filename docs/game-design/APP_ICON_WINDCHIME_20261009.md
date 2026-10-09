# 应用图标改为晴空风铃（2026-10-09）

用户从六张候选中选择B“晴空风铃”。源图为`art/references/app_icon/options_20261009/B-sky-windchime.png`，由内置imagegen生成，提示词在`art/manifests/prompts/app_icon/options_20261009.json`。

用项目的`art/tools/export_app_icon.py`做格式转换，不重画、不裁切、不更改构图。`game/icon.png`为1024×1024 RGBA，与所选图等比缩放后的像素完全一致；`game/harumachi.icns`覆盖16、32、64、128、256、512、1024像素。外部透明区域保留。

Godot工程图标和macOS原生图标均指向这两个文件。已核对导出应用Info.plist指向的ICNS与工程ICNS字节一致，ZIP CRC、严格签名和编译引擎通过。游戏内容与上一份1359项全量已验收源码一致，只改变图标资源及其导入记录，因此没有新增玩法测试。

完整解压包200项自动演示通过，Q05与Q15完成，退出0，驱动瞬移0；默认存档与照片摘要未变。最新桌面包已原子替换，临时工程、解压包及builds旧解压应用已清理。总记录为`evidence/app_icon_windchime_20261009/delivery.json`。

SHA-256 `072757c261e5353eacf060916d6fedd657baab0d34830a5202c5f26cea007446`，1715174016字节；线上Web保持原发布快照。
