# 每日自动保存与网页UI发布（2026-10-04）

用户要求每天结束自动保存、更新网页UI及AGENTS.md并重新发布。原来睡觉调用会保存，但规则层的advance_day没有统一保存。现在结算作物、账本、天气、委托和day_changed回调后，GameState.advance_day自动保存一次；Main.sleep_now先把角色安排到次日卧室，不再重复写一份相同日期的快照。

save_game保留手动调用接口，并通过save_finished报告成功/失败及手动/自动类型。失败时不显示成功，也不覆盖上次快照。网页版监听这个结果更新工具栏，SQLite写入后的浏览器文件系统同步机制继续保留；存档位置、版本和本地权限不变。

新增DAILY_SAVE 8项，旧版6项失败，修复全部通过；全量573项通过。包括直接日期推进、结算字段、回调完成后保存、次日卧室、只写一次、深夜从湖区回家、数据库失败保留旧档与手动保存区别。失败测试使用隔离目录，不接触玩家存档。

官网新增site/ui.css和site/play.css，使用从game/ui_kit导出的30张皮肤/图标。导航、按钮状态、和纸面板、音乐播放器与试玩加载卡共用画风；手机导航已检查无裁切。壁纸、18首音乐、订阅本地保存和原有入口保留。字体子集已重新生成。

网页版从冻结工程单独构建Compatibility版本；建筑和角色图集保留1024尺寸，其余模型512，网格/骨骼/动画缓冲不变。UI库原图和像素目录不缩放。新PCK 233,557,004字节，约222.74 MiB，继续用4 MiB分段和重试。

真实浏览器发现旧preloadFile把Uint8Array当对象键转成巨大字符串，导致Invalid string length。现在传ArrayBuffer，启动正常。本地浏览器验证包括加载面板、实际进场、手动SQLite保存、刷新保留和继续恢复日期；没有游戏脚本解析错误。线上官网10项交互通过，9份公开文件与本地字节一致，WASM MIME/gzip/COOP/COEP和PCK首尾Range检查通过。

官网已发布版本20261004-012728，143个文件，服务器摘要全部通过；原子切换current，上一版releases/20261001-122321保留。地址为https://harumachi.nightc.com/，浏览器试玩在/play/。部署证据与最终验收均在evidence/daily_web_release_20261004。

最终macOS包为builds/HareMachi-daily-web-20261004.zip，1,448,821,661字节，SHA-256为a2c260fd101b26447be8cdf066a1d3228fe505016c91b24c47556a5d80a89932。ZIP CRC、Apple Silicon/Intel二进制和codesign检查通过；解压后完整剧情260.03秒、模拟1230.5秒、44张截图、Q05完成、退出码0，无SCRIPT ERROR。SQLite quick_check和v4快照摘要正常。验收后原子更新builds/HareMachi.zip，上一默认包保存在HareMachi-before-daily-web-20261004.zip。

本轮发布基于builds/daily-source-20261004/game的573项冻结工程。工作区另有598项的生活更新候选；其源码、证据和包保留，完整剧情因锁屏待复验，未纳入本次发布。退出时的既有Shader RID/Ogg清理警告已记录在verification.json，不影响上述运行与存档结果。
