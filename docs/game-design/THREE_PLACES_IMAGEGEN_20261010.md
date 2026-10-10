# 社区中心、面包房与商店的实景改绘（2026-10-10）

本轮按[实景改绘流程](IMAGEGEN_SCENE_WORKFLOW.md)提升三处门前与室内。三张室内、三张门前改绘均使用真实游戏截图；四项实际素材由内置 imagegen 生成，分别是安静的松木纹、亚麻织纹、窗外夏景与社区手工图稿。改绘提供目标，运行截图和测试另作验收。

## 目标与实现

| 场景 | 室内 | 门前 |
| --- | --- | --- |
| 社区中心 | 错位宽木板、真实侧窗和格栅光、沿墙材料与档案台、纸卷、布料、工具与手工图稿；中央工作台和试挂通道留空 | 木框公告盒、雨帽、实际纸面和手工图稿、沿墙盆栽及伞架 |
| 面包房 | 暖木地板、低位烘焙背板与上部奶油色墙、真实窗洞、备料架、面粉袋、包布、面包托盘与香草小台 | 布篷织纹与支撑杆、木部细节、门侧植物；橱窗仍可透视真实陈列 |
| 商店 | 灰暖松木地板、窗边明暗、包装台、包纸与织物、壁边小物；现有米粮、调料、饮料、陶器与电视继续工作 | 旧绿木作与布篷织纹、实际支架、侧边盆栽和归还布料 |

新陈设集中在边缘与已有桌面，门口、柜台、烤箱、冰柜、工作台和试挂路线按实际角色碰撞检查。窗外夏景只作为洞口后的远景画片，窗框、窗洞和光影由实际场景构件承担；夜晚同步变暗。地板缝按米制排布，使用屏幕导数过滤，避免远处出现点状闪纹。

## 参考与复现

- 六张改绘及原始/最终对照图：`art/references/three_places_20261010/`。
- 改绘提示词：`art/manifests/prompts/three_places_20261010.json`、`three_places_exteriors_20261010.json`。
- 实际色纹与插图：`game/assets/textures/three_places/`；提示词为 `art/manifests/prompts/three_places_materials_20261010.json`。
- 构件与陈设：`PublicPlaceArt`，墙体接入 `InteriorBuilder`；公共室内的日照与玩家家中分别选择，入口保留同一玩法与存档身份。
- 本轮证据：`evidence/three_places_imagegen_20261010/`。

## 验收与实景

新增15项在旧场景失败14项，新场景全部通过。1399项独占全量、解压应用200项完整夏季演示通过，退出0，Q05/Q15完成，驱动瞬移0。25个原生视角、ZIP CRC、双架构、签名、SQLite完整性与默认存档/照片摘要通过。最新`builds/HareMachi.zip`已原子替换，临时工程已清理。SHA-256：`8cc278001bd0b5c0ab9df203b13f1bbb7a1a7baeaf86d5d619fc2a2c59a75d36`，字节数1775135159，精确引擎`4.8.dev7.official.c971f93e7`。

Apple M5 Max、Forward+、1280×720、三个实际移动视角，新旧同条件均约60 FPS。新版p95为16.820–17.066毫秒，最长帧19.992毫秒；时钟持续推进，样本每视角12秒，不代表其他设备或全程性能。首次全量的8项失败来自新桌面小物尚未声明共用支持节点；补齐后仍按真实表面测量，没有放宽悬空容差。

![社区工作间](../../art/references/three_places_20261010/final_workroom_overview.png)

![面包房](../../art/references/three_places_20261010/final_bakery_in.png)

![商店](../../art/references/three_places_20261010/final_store_in.png)

![社区中心门前](../../art/references/three_places_20261010/final_community_front.png)

![面包房门前](../../art/references/three_places_20261010/final_bakery_scene_front.png)

![商店门前](../../art/references/three_places_20261010/final_store_scene_front.png)

最终证据为`evidence/three_places_imagegen_20261010/delivery.json`。本轮提交仅包含场景工作，其他任务修改继续保留；Web仍使用20261007-203612快照。
