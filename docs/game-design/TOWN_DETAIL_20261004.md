# 公交、墙顶、钟面和地面细节

公交主体改为 imagegen 参考图经本地 Pixal3D 生成的 GLB，保留生成的车身、车窗、格栅和轮毂；Blender 校正支撑面、车头朝向与米制尺寸，清掉侧面错误凸起，拆出两片车门与四个车轮。车长约 6.2 米，车门随到站演出打开，车轮随移动旋转。源图、原始 GLB、组装 Blender 文件和任务 ID 均保留于 `art/references/town_detail/` 和 `art/models/raw/B01_bus_pixal_20261004/`。

车站沿用生成的候车亭和长椅，覆盖模糊海报，增加独立站名、07 线路图、时刻表与站牌。西端围墙分开，入口接上向外延伸的道路、车道线、沙质路肩、护栏和路边草木。玩家可走到近处的道路边界，远处用于公交入场和景观。

所有镇边墙和住宅庭院墙采用白灰墙面、弧形瓦帽、分瓦接缝及圆形瓦当。保持原有墙高与猫的支撑高度，墙面和墙顶无镜面反射。

钟表保留生成的底座，钟面改为不透明圆盘、60 个立体刻度、12 个独立数字和三根指针，按游戏时间更新。场景中的固定文字提高字形分辨率并保持原有物理尺寸；公交、站牌、指路牌、公告栏标题和咖啡菜单使用独立字形覆盖生成纹理中的模糊字。

imagegen 新画了草地、石板和沙地三张动漫纹理。石板按一个尺度采样，避免不同大小的砖缝叠在一起；沙地有细砂、石子与耙痕。沙坑使用独立沙面，南町庭院新增约 5,800 簇草叶，房屋、街道和横向小径留出空隙。沿用原碰撞地面和走路音效类型。

证据目录：`evidence/town_detail_20261004/`。新增 TOWN_DETAIL 18 项在旧版本全部失败，当前版本专项全通过，冻结工程 616 项全量通过；近景包括公交、候车亭、进村道路、钟面、院墙、石板、沙坑和住宅街。最终全量测试和解压应用验证结果写入该目录的 JSON。

## 实际画面

![生成公交在镇口](../../evidence/town_detail_20261004/after-shots/detail_bus_front.png)

![候车亭与清晰站牌](../../evidence/town_detail_20261004/after2-shots/detail_bus_stop.png)

![转动钟面](../../evidence/town_detail_20261004/after-shots/detail_clock.png)

![瓦帽院墙与瓦当](../../evidence/town_detail_20261004/after-shots/detail_wall.png)

![进村道路](../../evidence/town_detail_20261004/after2-shots/detail_arrival_road.png)

![南町草地和石板](../../evidence/town_detail_20261004/after2-shots/residential_day.png)

## 素材来源

本轮四张图使用 image_gen 文生图模式，保留原始 PNG，未抠图或重画生成结果。公交参考图为 `art/references/town_detail/B01_bus_reference.png`；地面原图为 `game/assets/textures/town_detail/grass.png`、`stone.png`、`sand.png`。提示词分别见 [公交](../../art/manifests/prompts/town_detail_bus.txt)、[草地](../../art/manifests/prompts/town_detail_grass.txt)、[石板](../../art/manifests/prompts/town_detail_stone.txt)、[沙地](../../art/manifests/prompts/town_detail_sand.txt)。公交 GLB 使用 Pixal3D，Blender 做定尺、UV 保留整理与可动部件拆分。

## 导出应用专项验收

解压通用应用的专项试玩退出码 0：从外部道路驶入、停车开门和恢复操作通过；南町步行至 z=80.02；四处水域均成功钓到鱼；两张照片实测 3840×2160；床的键盘选择、日末总结、次日保存和读档通过，SQLite quick_check 为 ok，v4 快照摘要匹配。证据为 native-demo2/verification.json、native-storage.json 和 photo-sizes.json。自动试玩的按键现在立即清空输入缓冲，防止成功一帧后旧的按下事件再次抛竿。此修改只涉及验证工具；游戏规则与已通过的 616 项回归一致。


最终解压应用的完整有窗口演示 329.15 秒完成，模拟 1228.5 秒、44 张截图、Q05 完成、退出码 0，无 SCRIPT ERROR；SQLite quick_check 为 ok，两份 v4 快照摘要匹配。默认 HareMachi.zip 已更新为 1,474,168,934 字节的通用包，SHA-256 为 `9e0140ab3f0cc832ca7ee69a575db1f67c1e4b1fc959ed6c984f05abab9f177e`；旧包保存在 `builds/HareMachi-before-town-detail-20261004.zip`。日期包为 `builds/HareMachi-town-detail-20261004.zip`，release_ready=true。
