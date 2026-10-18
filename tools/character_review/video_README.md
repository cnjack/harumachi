# 人物视频逐项点评

独立入口沿用纸面蓝色三栏界面，主体是九条已交付真实视频。不会读取或迁移旧图片点评的 localStorage，也不修改旧点评页、视频、报告或抽帧。

```bash
python3 tools/character_review/video_build.py --evidence evidence/character_videos_final_20261018
```

先核对 delivery、最终验收回执、freeze、实际录制输入、九片媒体 SHA 与现有解码/probe 回执，再按 journal 每段累计 count / fps 映射时间。生成该新目录的 `index.html` 和 `video-*` JS/CSS 快照。已有非视频点评 index 会拒绝覆盖。同一视频页可重新生成，媒体身份变化会得到新 dataset，不清旧存储。

49 项由每人六项单人动作和七人同场舞蹈组成。舞蹈明确标注左起人物位置；九片保留直接链接。五向按钮只来自实际 journal 的视角段，手势斜视、舞蹈正面按真实记录显示。切项暂停并定位，默认不播放；可慢放、重播本段及按 1/30 秒间隔定位。只有实际 currentSrc、metadata、seeking/seeked 与本项范围都确认后，才能记录时间点。时间是浏览器视频时间，不宣称逐帧解码精度。

判断、文字与时间点意见输入即存。通过／有问题／不确定计入已点评，“稍后”和仅看过不计。存储失败会持续警告，需要手动导出。完整 JSON 绑定49项模型／runtime／媒体／journal和时间范围；导入先完整验证、预览，再由用户明确确认整包替换，取消不变。

离线检查：

```bash
python3 -m unittest discover -s tools/character_review -p 'video_test_*.py'
node --test tools/character_review/video-dom.test.cjs
```

Python 测试中的极小人工文件只验证协议，不能充当媒体正控。DOM 测试使用内存 localStorage 和延迟媒体事件，不操作真实浏览器进度。实际 file:// 浏览器播放、原生 controls 和视觉布局仍需在工具允许时实测；离线测试不替代这部分。

Node 测试复用本目录 package 声明的 linkedom；如果运行环境把现有依赖放在独立目录，以 `NODE_PATH` 指向该目录，不需要修改 package 或 lock。已有本机进度若损坏，普通输入会保留旧原文，只在本页内存中编辑，直到手动导出或明确确认导入替换。写入后会读回核对，避免浏览器静默拒绝却显示已保存。首次零秒首帧以实际 loadeddata 确认，有时间位移的定位等待真实 seeked；已确认的同源同时间画面可以复用确认，七人舞蹈切换人物仍将意见记在新人物项。原生播放和重播都会在本段结束暂停，并定位回本段最后一个时间间隔。
