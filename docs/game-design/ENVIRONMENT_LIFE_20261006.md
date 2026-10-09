# 小镇的风、花草与天气（2026-10-06）

这轮把室外环境接到同一套天气状态，保留动漫平涂、哑光材质和手绘天空。已有的巡游猫、蝴蝶、草叶和水面动画继续使用；补上风铃、落叶、雏菊草丛、芦苇、近岸河声、移动云层和可见太阳。

## 正式素材

用户强调好看，并指定善用 imagegen 与 Hyper3D。第一版程序植物与风铃只用于联动验证，随后替换成三件 imagegen 设计、Hyper3D CLI 生成的模型：

| ID | 内容 | 游戏模型 |
| --- | --- | --- |
| E01_furin | 陶瓷金鱼风铃、编绳、木舌、叶纹纸签 | 约 1.8 万面、2K 漫反射、整体 64 厘米；上挂点为原点 |
| V04_daisy_meadow | 白色雏菊、花苞、三叶草、紫色小花与细草 | 1.4 万面、2K 漫反射、高 35 厘米 |
| V05_river_reeds | 弯叶芦苇、金色羽状穗与根部小草 | 1.8 万面、2K 漫反射、高约 1.3 米 |

三次 Gen-2.5-High Raw 生成均请求 50 万面，原稿保留。会员积分从 197 变为 195.5，冻结积分回到 0，合计消耗 1.5 积分。提示词在 `art/manifests/prompts/environment_life_20261006.json`，参考图在 `art/references/environment_life_20261006/`，任务与来源在 `art/manifests/models_hyper3d_environment_20261006.json`。没有自动重复付费提交。

风铃用 `prepare_furin.py` 均匀缩放、保留 UV 减面，并在纸签上方拆出独立挂点；源 Blender 与处理说明保存在同一原稿目录。三件模型均经过 `game_export.py` 和 `level_check.py`。风铃属于悬挂物，芦苇没有完整水平底座，两者的小支撑面倾角不表示主体歪斜；以实际挂点、根部射线与游戏近景验收。

## 联动

- `EnvironmentLife` 读取 GameState 的天气与时刻。晴天、阴天、雨天的基础风力分别为 1、1.35、2.1，另叠加缓慢阵风；草叶、原有植被、新草丛与落叶使用共同风向。
- 屋檐下放三只风铃，陶瓷主体绕固定挂点摆动，纸签有独立小幅摆动。经过摆幅中线且休止时间结束时响一下；离玩家较远、进入农园或进屋时停声。
- 原有挂灯笼和玩家可摆放灯笼保留挂点，雨天摆幅随风力增加。彩旗只让旗尖飘动，绳边与支柱固定；下方不再用整段实心碰撞，两根支柱仍阻挡人物。石灯、路灯与建筑保持原支撑。
- 落叶从真实树冠附近生成，旋转、下落并随风漂移；最多 48 片，着地、过时、换区域或进屋时清理。
- 16 种作物、盆花、原有芦苇与新草丛使用同一风向；盆器底部保留固定高度。草丛绕开道路、建筑、交互点和钓点。河岸新模型在静态地形进入物理空间后，用真实地面射线贴地，避免解析高度与渲染三角面之间的偏差。
- 近岸河声根据玩家到实际水岸的距离变化，湖边更轻；风声随风势变化。音频在 Ambience 总线上，服从既有音效音量；进屋时停止。
- 天空继续用原白天、黄昏、夜晚全景，新增移动的原生手绘云图层。雨天增加云层、压低阳光、隐藏太阳圆面，并开启水面雨圈；新增云层的移动独立于全景图。
- 已有蝴蝶与巡游猫在雨天停止室外活动；雨粒子只在室外开启，方向随风势变化。作物、邻居、雨天音乐继续读取原来的 GameState.weather。

河声、树叶风声与风铃音色由 `synth_environment_audio.py` 单独合成，没有覆盖现有音乐或环境音。来源与文件摘要在 `art/manifests/audio_environment_20261006.json`。

## 验证与复现

改动前新增六项检查全部失败。正式模型接入后的 `--only=environment-life` 为 23 项，另有 `--only=bunting` 四项和 `--only=npc-overlap` 三项，共 30 项新增回归，检查挂点固定、独立纸签、实际源模型、落叶运动与数量上限、天气水纹、道路钓点净空、真实地形支撑、音频总线和室内关闭。记录在 `evidence/environment_life_20261006/`。

真实游戏截图由 shots.gd 的 `life_chime`、`life_daisies`、`life_reeds`、`life_rain_bank`、`life_sunny_sky`、`life_rain_sky`、`life_leaves`、`life_cat` 视角生成。约 31 秒原生录像依次展示风铃、老树、彩旗与灯笼、行走猫、晴天河岸和雨天河岸，音轨为实际游戏声音；每秒状态与截图在 `final-native-demo/`。

```bash
HARUMACHI_SAVE_DIR="/tmp/harumachi-environment-save" timeout 180 "$GODOT" --headless --path game res://scenes/tests.tscn -- --only=environment-life --out=/tmp/environment-tests.json
HARUMACHI_SAVE_DIR="/tmp/harumachi-environment-movie-save" "$GODOT" --path game --resolution 1280x720 -t --position 1700,1990 --write-movie /tmp/environment.avi --fixed-fps 30 res://scenes/main.tscn -- --environment-demo=/tmp/environment-evidence
```

本轮改动在当前开发工程中，未替换桌面 ZIP、Web 导出或服务器发布目录。桌面发布仍须另行导出、解压并完成完整 autoplay。全量回归与默认存档摘要以本目录最终 verification.json 为准。

全量首次发现三个新模型缺少普查清单、动物计时的约 1e-14 JSON 浮点舍入，以及小葵被玩家摆放彩旗下方的整段碰撞挡住。已经补齐清单，用数值精度比较存档中的浮点量，并按彩旗实际支柱拆碰撞。另有演员既存重叠的退开回归：普通巡游只允许朝远离对方的方向离开，不能向对方深入；合作试走仍拒绝重叠起点。新增三个检查先在旧代码上出现一项失败，修正后全通过。彩旗、植物新增四项先在旧版上出现三项失败，修正后全通过。最终独立冻结副本 1150 项全量通过，退出码 0，无 SCRIPT ERROR。当前脚本、数据、着色器与模型摘要一致；倾角报告仅格式变化。已有退出资源提示和故意破坏数据库的测试日志保留，不当作新失败。结果与初次失败均保存在 verification.json 对应日志。
