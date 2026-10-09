# 剧情阅览

交付文件是上一层的 `story.html`，字体和图片已经内嵌，直接用浏览器离线打开。这里的 `index.html` 是较小的开发版本，使用本目录 assets。

内容：4 幕当下入场、3 段被实物触发的回忆、Q00–Q16 共 17 个委托和 58 个步骤、实际解锁关系、选择和条件对白、9 位人物背景、6 个节日、219 组日常对白、13 件旧物。来源是当前 `game/data/` 与 `game/scripts/story/`，步骤、奖励和函数位置可在页面中查看。JSON 里保存了源文件 SHA-256。

图中的三章是叙事分组，不强迫逐章顺序。Q06 由 Q03 解锁；Q10 在 Q05 完成后的换日开启；Q14 按日期和 Q05 解锁，不要求全部旧物委托完成；散场后可找澪补约。Q15 有河边补看，Q16 要求 Q05 与 Q06 都完成。Q12 / Q13 第 16 天起有居民代补。页面显示不同分支的对白，不把所有句子当一次游玩的连续台词；无法静态确定的表达式保留来源。

生成命令（使用项目现有 Python 环境，含 PIL / fontTools / brotli）：

```sh
/Users/jack/.copilot/session-state/ca10e179-b441-4d77-b938-250cea2ee4c6/files/venv/bin/python tools/story/build_review.py --snapshot 2026-10-07
```

编辑界面在 `tools/story/review.template.html`，提取和触发规则解释在 `tools/story/build_review.py`。生成器不读玩家数据库，不改变游戏剧情或配音。字体许可证在 assets/OFL.txt，单文件版本也保留许可证文本。

2026-10-07 的全量文字评分、动态反馈与改前改后对照另见[对话审阅](../DIALOGUE_REVIEW_20261007.html)，不将本页六个传统主线脚本的提取范围称作全部新生活互动。
