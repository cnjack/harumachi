# 无文字组合道具（2026-10-15）

13个Hyper3D单体用于21组指定替换。`source/`保留未经改动的生成GLB，`authoring/`保留米制适配、UV及材质可编辑的Blender文件。原稿、参考图、任务链接、校验摘要和积分结算见`provenance.json`；游戏导出配置见`art/models/game_assets.json`，场景使用记录见`art/manifests/models_modular_props_20261015.json`。

单体以Godot的+Z为正面，底部居中。单位为米；Blender导入后Z朝上。箭头与立柱分别保留；格柜是单格开口模块，使用时逐格拼装，不把柜内物品烘进柜体。纸盒、包花纸、抽屉、晾布架和相框均可单独使用。相框中的故事图片来自游戏既有收藏图，不重新生成文字和照片。

| 部件 | 游戏尺寸 x/y/z（米） | 组合用途 |
| --- | --- | --- |
| MS01_signpost | .16 / 2.2 / .16 | 路标立柱、活动牌立柱 |
| MS02_arrow_board | 1.1 / .26 / .05 | 转向箭头，正反刻字 |
| MS03_garden_board | 1.15 / 1.5 / .12 | 双柱农园名牌 |
| MS04_wall_plaque | 1.2 / .24 / .04 | 无字木匾、活动牌面 |
| MS05_table_sign | .44 / .30 / .18 | 柜台立牌 |
| MS06_bus_pole | .38 / 2.3 / .16 | 独立公交站柱 |
| MS07_timetable_case | 1.1 / 1.0 / .08 | 时刻表、线路图框 |
| MS08_storage_bay | .62 / .48 / .40 | 横向、竖向拼接收纳 |
| MS09_archive_box | .35 / .16 / .29 | 档案盒与照片袋 |
| MS10_wrapping_rolls | .38 / .32 / .30 | 包花纸收纳 |
| MS11_archive_drawer | .52 / .18 / .65 | 开口档案屉 |
| MS12_linen_frame | .72 / 1.45 / .38 | 搭布晾架 |
| MS13_picture_frame | .65 / .50 / .05 | 墙面生活画框 |

P_signpost与R09由MS01和三件独立MS02组合；MS14_event_board由两根MS01与MS04组合。R06复用原候车亭，单独删除原网格中的旧蓝站牌柱，保留其余网格与UV；新站牌另行拼装。

## 离线重建

从仓库根目录运行。以下流程不调用付费生成：

```bash
BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
$BLENDER -b --factory-startup -P art/tools/prepare_modular_props_20261015.py
$BLENDER -b --factory-startup -P art/tools/prepare_modular_bus_shelter_20261015.py
$BLENDER -b --factory-startup -P art/tools/game_export.py -- art/models/game_assets.json MS08_storage_bay
python3 art/tools/build_engraving_masks_20261015.py
python3 art/tools/build_asset_library.py
```

准备工具优先读取本地`art/models/raw/modular_props_20261015/<ID>/a/model.glb`；新checkout缺少raw时自动读取本目录`source/<ID>.glb`。R06准备工具固定读取本目录保存的原候车亭，重复重建不会误切已修复的游戏网格。批量导出17个ID后必须运行`level_check.py`和`model_audit.py`更新实测清单。工具做米制适配、支撑面放平和面数缩减，保留原UV、原图集；游戏导出将图集压缩为JPEG，因此不宣称导出像素与原图逐像素相同。

## 游戏接入

```gdscript
var object := ModularProps.part(world, parent, "MS08_storage_bay", "MyBay", Vector3.ZERO)
```

`ModularProps.cubbies`拼装柜体并根据实际三角面托住柜内物件。不得用“柜体大致同高”代替真实层板接触；`support_surface`需指向实际承重网格。壁挂相框后沿贴真实墙面，桌面立牌落在实际柜台上。

刻字由`ModularProps.engrave`向现有木材着色器提供独立字体蒙版，不用Hyper3D生成文字，也不另外贴发光文字平面。字体为项目现有霞鹜文楷；字口有凹入明暗与局部法线。新文本先加入蒙版工具，生成纹理后再调用。刻字矩阵采用每个独立部件的实际局部空间，翻转箭头时背面保持正确阅读方向。
