# 素材、角色与 UI 清单 v0.6

当前清单摘要：192个游戏GLB文件、15种作物、32条配方、6种鱼、417条配音登记；统一UI原图8张、独立PNG49张、33图标、16控件底图、3背景及52个编辑器资源。当前整体范围见CURRENT_STATUS；下方v0.1–v0.6清单是分批来源与兼容记录，不代表每个旧任务仍是新局门禁。


所有素材的画风按 [ART_STYLE.md](ART_STYLE.md)：新海诚风格的动漫风，不走写实。

v0.1 的计划清单在 [v0.1/ASSETS_UI.md](v0.1/ASSETS_UI.md)。本页列出游戏里实际用到的东西。来源的完整记录在 `art/manifests/`。

## 3D 模型

v0.1–v0.3 的模型由腾讯混元 `hy-3d-3.1` 图生 3D 生成；v0.4 新做和重做的 27 个由 Hyper3D Rodin Gen-2.5 生成（记录在 `art/manifests/models_hyper3d.json`）。都经 `art/tools/game_export.py` 减面、定尺寸后放进 `game/assets/models/`。

| 类别 | 编号 | 游戏里的用途 |
| --- | --- | --- |
| 住宅 | H01 玩家家、H02 公寓、H03 民居（两处）、H04 庭院门、H05 自行车棚、H06 工具棚、H07 信箱 | 起点、Q00 信箱与家门、街道边界 |
| 种植 | H12a 种植箱（箱体、植物分开导出） | Q03 播种、浇水，植物按阶段长高 |
| 店铺 | S01、S02 面包店、S03 花店、S05 邮局、S06 社区中心、S08 杂货店 | 莲的面包店；花店和杂货店可买装饰；社区中心领活动标牌 |
| 公共设施 | P01 花架廊、P02 公告栏、P03 野餐桌、P04 秋千、P05 滑梯、P06 沙坑、P07 菜圃、P08 园艺台、P09 集市摊位、P10 小舞台、P11 小图书箱、P12 水龙头 | 庭院主体；公告栏接委托，摊位交付，水龙头装水 |
| 道路设施 | R06 公交亭、R08a 路灯、R09 路牌、R10 回收站、R11 时钟、R12 链桩 | 入口、指路、封住地图边缘；路灯傍晚亮 |
| 室内 | I01 床、I02 书桌、I03 书架、I04 矮桌、I05 衣柜、I06 落地灯、I07 龟背竹、I08 纸箱 | 卧室和客厅；纸箱是拆箱整理的入口 |
| 日式家具（v0.3） | J01 灶台水槽、J02 冰箱、J03 餐桌椅、J04 电饭煲柜、J05 碗柜、J06 电视柜、J07 被炉、J08 电风扇、J09 五斗柜 | 厨房和客厅；电饭煲柜是捏饭团的入口 |
| 玄关、缘侧、庭院（v0.3） | G01 鞋柜、G02 捞金鱼水槽、G03 晾衣架、G05 金鱼缸、G06 坐垫、G07 走廊柜、G08 猫、G09 太鼓 | 玄关、走廊、缘侧；G02 和 G09 放在共享庭院小舞台旁，是捞金鱼和太鼓的入口 |
| 角色 | CH_sora 主角、CH_mio 澪、CH_ren 莲、CH_haru 春；v0.4 新增 CH_tanaka 田中爷爷、CH_aoi 小葵（Hyper3D） | 已绑定骨骼，带 idle / walk / run，v0.4 起多了 wave / bow / look / stretch / cheer / tend / talk |
| Hyper3D 重做（v0.4） | M03 山墙屋、M12b 灌木、M12d 绣球花丛、P05 滑梯、P06 沙坑；新增 T01 庭院榉树 | 替换掉质量最差的 5 个混元模型；T01 成为庭院中央和街边的大树（M12d 改回灌木尺寸） |
| 农园（v0.4，Hyper3D） | F01 工具棚、F02 手压泵、F03 堆肥箱、F04 稻草人、F05 温室、F06 无人菜摊、F07 木桥、F08 菜地 | 河边市民农园；F08 也用在自家小院 |
| 作物（v0.4，Hyper3D） | C01 幼苗、C02 萝卜、C03 小松菜、C04 迷你番茄、C05 黄瓜、C06 毛豆、C07 向日葵、C08 草莓 | 按生长阶段缩放摆进地块；向日葵也种在对岸当风景 |
| 小动物（v0.4，Hyper3D） | A20 睡觉的三花猫、A21 麻雀、A22 坐着的橘猫 | 庭院矮墙、农园长椅、支巷墙头；麻雀成群出现 |
| 复用 | A07 灯笼、A10 自动售货机、A11 自行车、A12 长椅、A13 小黑板、A14 绣球花盆、A15 盆栽、A16 花箱、M01 町屋、M03 山墙屋、M05 民居、M07 电线杆、M12b 灌木、M12d 花丛 | 上一轮新海诚街景的混元模型，重新导出后用作街景和可布置物 |

v0.5 又加了 24 个 Pixal3D 模型（C09 胡萝卜、C10 土豆、C11 茄子、C12 玉米、C13 南瓜、C14 西瓜、C15 小麦、C16 洋葱；G10 商店货架、G11 面包推车；E01 屋台、E02 七夕竹子；D01 手推车、D02 雨水桶、D03 菜箱、D04 石灯笼、D05 小祠堂、D06 古井、D07 轻卡、D08 农具架、D09 柴堆、D10 石块、D11 芦苇、D12 花槽）和 8 个 Blender 程序模型（见 PIPELINE 第 11 节）。v0.4 合计 100 个 GLB，约 76 万三角面、57 MB（v0.3 时 78 个、约 64 万面、47 MB）。R07a 和 G04 盆景生成后没有放进场景。家里的模型进屋后会换成卡通漫反射材质（见 [PIPELINE.md](PIPELINE.md) 第 6 节）。彩旗串是在 Godot 里用代码搭的（两根木杆加一串三角旗），没有单独的模型。

v0.6 店内的模型：I02 蛋糕柜、I04 柜台、I05 面包架、I08 石磨、和子阿姨（Pixal3D），P_gondola 双面货架、P_deck_oven 双层烤箱、I03 冷饮柜、I07 冰柜（Blender 程序生成，冷饮柜和冰柜的玻璃面贴的是 codex 画的饮料架和冰淇淋），六种面包 B01–B06（Pixal3D）。v0.6 复查后重做了柜台（新参考图）、收纳箱 P_chest（Pixal3D 木箱，替换原来的程序方盒），冷饮柜和冰柜改为程序模型；菜箱、商店货架、面包推车、面包架、柴堆提高面数重新导出；15 个方形 Pixal3D 模型转正（见 [PIPELINE.md](PIPELINE.md) 第 13 节）。

## codex 生成的图片

提示词在 `art/manifests/prompts/`，记录在 `art/manifests/images_codex.json`。

| 文件 | 用途 |
| --- | --- |
| `art/references/characters/*_front.png`、`*_turnaround.png` | 4 名角色的正面立绘和三视图，作为图生 3D 的输入 |
| `art/references/characters/portraits_sheet.png` | 对话头像，每人一张平常、一张开心，由 `art/tools/cut_portraits.py` 统一抠成透明底、裁到 `game/assets/ui/portraits/`（田中和小葵在 `portraits_farm.png`，和子阿姨在 `v06/ui/pt_kazuko.png`） |
| `art/references/interior/furniture_sheet.png` | 玩家房间家具设定，裁成 I01–I08 的输入图 |
| `art/references/ui/icons_hud.png`、`icons_items.png` | HUD 图标和 14 种物品图标，裁到 `game/assets/ui/icons/` |
| `art/references/ui/title_keyart.png` | 标题画面主视觉 |
| `art/references/ui/paper_texture.png` | 所有面板的米白纸纹底 |
| `art/references/textures/grass_raw.png`、`gravel_raw.png`、`stone_raw.png` | 草地、庭院碎石、石板路的地面贴图（处理成无缝） |
| `art/references/world/gameplay_view_concept.png` | 游戏视角概念图，定镜头高度和画面构成 |
| `art/references/interior/furniture_sheet2.png`、`furniture_sheet3.png` | v0.3 日式家具和玄关、缘侧、庭院道具设定，裁成 J01–J09、G01–G09 的输入图 |
| `art/references/textures/interior/*_raw.png` | 7 张室内无缝贴图：木地板、榻榻米、灰泥、厨房瓷砖、洗石子、缘侧木板、隔扇纸，处理后放 `game/assets/textures/house/` |
| `art/references/world/card_window.png`、`card_garden.png` | 窗外街景和北院的庭院背景画 |
| `art/references/h3d/*.png`（v0.4） | 重做 M03、M12b、M12d、T01 用的干净单体参考图（T01 画了两版，第二版树冠是实心的几团） |
| `art/references/farm/*.png`（v0.4） | 19 张农园、作物、小动物参考图 |
| `art/references/characters/tanaka_*.png`、`aoi_*.png`（v0.4） | 两位新角色的正背面设定，切成正面、背面两张给 Hyper3D |
| `art/references/characters/portraits_farm.png`（v0.4） | 田中爷爷、小葵的头像（平常 / 开心） |
| `art/references/ui/icons_farm.png`（v0.4） | 20 个图标：7 种种子、7 种收获、锄头、旧洒水壶、堆肥、杂草、春的信、向日葵发夹 |
| `art/references/world/sky_dusk.png`、`sky_night.png`（v0.4） | 黄昏、夜晚天空全景（处理成左右无缝的 4096×2048） |
| `art/references/world/bg_river.png`（v0.4） | 河对岸的堤坝、稻田、电线杆和山丘，农园南边的远景卡片 |
| `art/references/v05/models/*.png`（v0.5） | 24 张 Pixal3D 参考图 |
| `art/references/v05/ui/icons_*.png`（v0.5） | 4 张图标表，共 80 个图标 |
| `art/references/v05/ui/ban_*.png`（v0.5） | 8 张横幅：晴町商店、面包店、厨房、七夕、品评会、夏祭、花火、灯笼流 |
| `art/references/v05/tex/*.png`（v0.5） | 草丛和野花图集、野草地、深色草丛、土路三张地面贴图 |
| `art/references/v06/models/I04_shop_counter_v2.png`、`P_chest_v2.png`（v0.6 复查） | 重画的柜台（只有收银机）、带铁包角的木箱 |
| `art/references/v06/tex/fridge_front.png`、`freezer_top.png`（v0.6 复查） | 冷饮柜玻璃门里的饮料架（正视）、冰柜玻璃顶下的冰淇淋（俯视） |
| `art/references/v06/prologue_anime/P1–P7_*.png`（v0.6 反馈） | 序章的 7 张动漫插画：巴士、商店街、榉树、夏祭回忆、黄昏的空庭院、奶奶家的信箱、缘侧；游戏里用裁成 1920×1080 的 `game/assets/ui/prologue/*.jpg` |

### 小游戏的画面（codex 小游戏任务生成）

每个游戏的图片在 `game/assets/minigames/<id>/`，每张图的提示词写在同目录的 `CREDITS.md`。

| 游戏 | 图片 |
| --- | --- |
| 捏饭团 | 厨房窗口背景、饭勺、四种米饭形态（散饭、不成形、三角、包好海苔）、海苔条、四种馅（梅干、鲑鱼、昆布、金枪鱼蛋黄酱）、图标；背包里的“饭团”图标 `game/assets/ui/icons/onigiri.png` |
| 拆箱整理 | 客厅整理背景（书架、窗台、矮柜、餐具架）、三种纸箱状态、24 件小物（画册、书、碗盘、茶壶、达摩、招财猫、收音机、台灯、雪花球……）、图标 |
| 晴町地图拼图 | 晴町手绘俯视地图（拼图本体，也挂在卧室墙上）、书桌背景、图标 |
| 捞金鱼 | 俯视水槽、四种金鱼、三种状态的纸捞网、盛鱼的碗、图标 |
| 祭典太鼓 | 夜祭小舞台背景、太鼓、“咚”“咔”音符、命中光效、图标 |

天空全景（8K 等距柱状图）和远景卡片（远山、近丘、山坡房屋、古塔、屋顶线、三棵树、三朵云）沿用上一轮新海诚街景时做的素材，放在 `game/assets/textures/`。

## 音乐与音效

文件都在 `game/assets/audio/`。

- 音乐：本地 MiniMax Music 3（社区 MLX 8-bit 版）生成，44.1 kHz 立体声，统一到 −20 LUFS。请求、种子和每条弃用原因在 `art/manifests/music_minimax/`（`takes.json`），原始 WAV 在 `art/audio/music_raw/`。四首完整试听：`evidence/audio/soundtrack_preview.mp3`。
- 环境声和音效：`art/tools/synth_audio.py` 用代码合成，清单在 `art/manifests/audio_synth.json`。

| 类别 | 文件 | 什么时候响 |
| --- | --- | --- |
| 音乐 | `music/title.ogg` 标题（D 大调，钢琴领奏、弦乐和钢片琴，72 BPM，72 秒；种子 2026092731） | 标题画面，放完后交叉淡入重来 |
| 音乐 | `music/day.ogg` 小镇白天（G 大调，尼龙吉他、钢琴、竖笛、钟琴、刷鼓和沙锤，92 BPM，110 秒；种子 2026092741） | 筹备阶段的室外；进屋后变闷 |
| 音乐 | `music/market.ogg` 傍晚集市（C 大调五声音阶，篠笛、筝、三味线、太鼓、拍手，100 BPM，71 秒；种子 2026092751） | 集市开始后 |
| 音乐 | `music/ending.ogg` 结尾（D 大调钢琴和弦乐，64 BPM，37 秒，最后一个和弦自然消失；种子 2026092724） | 结尾面板弹出时，只放一次 |
| 环境声 | `amb/day.ogg` 麻雀、远处的鸟、微风和树叶 | 白天室外 |
| 环境声 | `amb/evening.ogg` 暮蝉（ヒグラシ）、集市人声、风铃 | 集市傍晚 |
| 音乐 | `music/taiko.ogg` 祭囃子（132 BPM，约 52 秒，代码合成，和谱面 `game/data/taiko_chart.json` 一起生成） | 太鼓小游戏，只在游戏里放 |
| 环境声 | `amb/room.ogg` 安静的室内，窗外隐约的鸟叫 | 家里 |
| 环境声（v0.4） | `amb/farm.ogg` 河水流动、咕嘟声、麻雀、远处的鸣蝉 | 农园白天 |
| 环境声（v0.4） | `amb/night.ogg` 铃虫、稻田里的蛙鸣 | 19:24 以后到清晨的室外 |
| 环境声（v0.4） | `amb/rain.ogg` 雨声、屋檐滴水 | 雨天室外 |
| 脚步 | `sfx/step_{stone,gravel,grass,wood,tatami}_0..3.wav` 各 4 个变体 | 每次脚跟着地，按脚下地面选；客厅是榻榻米，玄关洗石子用石板声 |
| UI | `ui_hover`、`ui_click`、`ui_open`、`ui_close`、`ui_next`、`ui_select`、`ui_invalid`、`ui_rotate` | 按钮悬停和点击、面板开关、对话翻页、布置时旋转或放不下 |
| 提示音 | `sting_item`、`sting_coin`、`sting_quest_accept`、`sting_step`、`sting_quest_done`、`sting_save`、`sting_fanfare`、`sting_sparkle` | 获得物品、买东西、接委托、推进一步、完成委托、存档、集市开场、灯笼亮起 |
| 拟音 | `fx_door`（拉门）、`fx_mailbox`、`fx_water_tap`、`fx_water_pour`、`fx_soil`、`fx_paper`、`fx_place`、`fx_pickup`、`fx_basket`、`fx_purr` | 进出家门和活动中心、开信箱、装水、浇水、播种、贴标牌、放下和收回物件、交面包篮、摸缘侧的猫 |
| 拟音（v0.4） | `fx_flap`、`fx_hoe`、`fx_pump`、`fx_harvest` | 麻雀被惊飞、锄地、手压泵、收菜 |
| 小游戏 | `mg_count`、`mg_go`、`mg_good`、`mg_perfect`、`mg_miss`、`mg_result` | 所有小游戏的倒数、判定和结果 |
| 小游戏 | `mg_rice_scoop`、`mg_rice_press`、`mg_filling`、`mg_nori`、`mg_serve`、`mg_order_bad`、`mg_customer_leave` | 捏饭团 |
| 小游戏 | `mg_pickup`、`mg_place`、`mg_place_good`、`mg_bump`、`mg_box_open`、`mg_box_fold`、`mg_rotate` | 拆箱整理 |
| 小游戏 | `mg_slide`、`mg_slide_blocked`、`mg_hint`、`mg_solved` | 地图拼图 |
| 小游戏 | `mg_water_in`、`mg_water_out`、`mg_catch`、`mg_tear`、`mg_escape`、`mg_splash`、`mg_new_poi` | 捞金鱼 |
| 小游戏 | `mg_don`、`mg_ka`、`mg_combo`、`mg_full_combo` | 太鼓 |

## UI 结构

所有界面都用 Godot Control 和 Theme 在代码里搭（`game/scripts/ui/ui_root.gd`、`ui_theme.gd`），文字由 Godot 渲染。生成的图片只用在头像、图标、纸纹和标题图上。参考画布 1920×1080，支持界面缩放。

| 界面 | 位置 | 内容 | 按键 |
| --- | --- | --- | --- |
| 目标卡 | 左上 | 当前委托名、下一步做什么、金币、邻里支持标记（集齐 3 枚开集市） | — |
| 区域牌 | 右上 | 当前区域名；下面一行“第 N 天 · 周几 · 时刻 · 天气”（v0.4） | — |
| 提示条 | 右上区域牌下方 | 获得物品、完成委托、已保存等短提示，几秒后淡出 | — |
| 交互提示 | 底部居中 | `[E] 和澪说话` 这类近处提示 | E |
| 对话框 | 底部，左侧叠头像 | 名字牌、正文，选项在右侧；打开时角色停住 | E / 点击继续，1–4 或点击选项 |
| 背包 | 居中面板 | 图标、数量、说明；任务物品单独标出；v0.4 起普通物品 20 格（10 × 2） | Tab |
| 委托页 | 居中面板 | 进行中和已完成的委托，每一步标成已完成 ✓ / 当前 ▶ / 未开始 ·，以及奖励 | J |
| 商店 | 居中面板 | 店主一句话、商品、价格、余额 | 在店门口按 E |
| 布置模式 | 底部布置栏 | 当前物品、能不能放和原因、操作说明 | 左键放下，Q / E 旋转，1–5 换物品，F 收回，Z 撤销，右键 / Esc 退出 |
| 菜单 | 居中 | 继续、保存、读档、设置、回到标题 | Esc |
| 设置 | 居中 | 界面缩放、鼠标灵敏度、总音量、音乐、音效与环境声、反转视角、全屏 | — |
| 结尾面板 | 居中 | 用时、庭院摆了什么、三位邻居的熟悉度（♥0–5）和他们喜欢的物件 | 继续逛逛 / 回到标题 |
| HUD（v0.5） | 左上 / 右上 | 金币后面是种植等级徽章和经验条；金币变化冒出 +/− 数字；右上的天气图标按晴、多云、雨、夜、节日切换，日期写成“7月4日（四）” | — |
| 商店（v0.5） | 居中 | 横幅、店主一句话、买 / 卖两个标签、可滚动的商品行（价格、已有、等级锁、买 1 / 买 5、卖 1 / 全卖）、余额和背包格数 | — |
| 料理（v0.5） | 居中 | 横幅、时钟、配方行（成品图标、卖价、用时、每种材料的 已有/需要，锁住的写怎么解锁）、做 1 份 / 做 5 份 | — |
| 背包（v0.5） | 居中 | 等级和金币、六个带图标的标签、10 列格子（叠放数量）、说明写卖价 | Tab |
| 收纳箱（v0.5） | 居中 | 左边背包、右边箱子，左键整组、右键一个 | — |
| 日历（v0.5） | 居中 | 月份格子（节日、集市、休息日、今天）、下一个节日的横幅和说明 | C |
| 提示卡（v0.5） | 顶部居中，不挡操作 | 升级、节日开始、早上的收支；最多同时两张，几秒后淡出 | — |
| 地块互动（v0.4） | 交互提示 + 选项 | 翻土 / 播种（列出背包里能种的种子和数量）/ 浇水（壶里剩几次）/ 施肥 / 收获；快捷操作只弹提示条，不开对话框 | E |
| 卖菜（v0.4） | 对话选项 | 无人菜摊原价、周六集市摊位 1.3 倍；每种菜一个选项加“全部卖掉” | E |
| 送礼与每日委托（v0.4） | 和邻居聊天之后的选项 | 能交的公告栏委托先问；然后是今天的对话，最后问要不要送一份菜（喜欢的菜排在前面） | E / 1–4 |
| 小游戏框架 | 全屏，1640×960 纸纹面板 | 标题、分数、剩余时间、状态提示、底部操作说明；中间是游戏舞台；规则卡和结果卡居中弹出，结果卡写星级、分数、明细和奖励 | 各游戏自己的键位；Esc 离开 |
| 小游戏记录 | 居中（暂停菜单进入） | 5 个游戏的图标、名字、地点、星数、最好成绩，总星数 | 好的 |

对话框、交互提示和布置栏都通过 `_dock()` 设置四个 offset 贴在底部。v0.1 用 `.position` 摆位置，导致对话框跑出屏幕，这一版已修复，并有三种窗口尺寸下的测试。

## 视觉规则

- 面板用米白纸纹，墨蓝文字，青草绿和少量珊瑚色做强调。
- 布置合法与否同时用文字和颜色表示，不只靠颜色。
- 画面上方留给天空；重要面板避开角色和脚下落点。
- 地面保持干燥：没有积水反光，集市傍晚只改光的颜色和角度，打开路灯和纸灯笼。v0.4 的雨天也不做积水，只降低阳光、加雾和雨丝；浇过水的菜地土色变深。

## 没做的

- 手柄按键提示。
- 英文等其他语言。

## 应用图标（2026-10-01）

纸灯笼与金鱼徽记，内置 imagegen 生成，保留透明圆角。原图 `art/references/app_icon/harumachi-20261001.png`，提示词 `art/manifests/prompts/app_icon/lantern-goldfish.txt`。工程 PNG `game/icon.png`，macOS ICNS `game/harumachi.icns`。格式导出脚本 `art/tools/export_app_icon.py` 只做尺寸与格式转换；旧 `icon.svg` 保留。
