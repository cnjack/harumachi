# 电视曲面、雪花与货架陈列修复（2026-10-09）

用户指出电视没有雪花、画面不贴合凸起玻璃，货架种类单一且排列过于一致。核对当前源码与4.8-dev7实机，三个现象都仍存在：电视用平面QuadMesh，材质只有扫描线；商店反复等距摆同一个W14商品组合，烘焙架轮换三种食品。

## 电视

`prepare_shop_refresh.py`读取正式W18网格的正面三角面和原底色，区分玻璃与边框，取得9134个玻璃采样点。生成的`shop_tv_surface.json`含2303个顶点，轮廓跟随真实玻璃圆角，中间的凸起、竖向倾斜与凹进去的边缘都有真实深度。图片层比原玻璃前移1.8毫米，原稿里的小孔用实测玻璃的二次曲面补齐；不改变电视外壳和支撑架。

`ShopTelevision`按这个数据建立ArrayMesh和法线。原shader的平面圆角裁切被实际曲面轮廓替代，节目图片有轻微桶形映射与边缘变暗。名称移到下方边框，避免字面被玻璃或壳体截断。

营业时有持续轻微雪花，每12秒换节目时出现约0.65秒较强雪花、横向干扰与滚动暗带。噪声每秒更新24次。雨天节目仍读取当日天气；闭店关闭图像与噪声。雪花使用整数散列，避免大浮点正弦散列在实际渲染中变成近乎黑色的常量。本轮没有添加电视噪声音轨。

## 陈列

没有新增付费生成。复用原imagegen／Hyper3D W14组合，按连接部件拆出面粉袋、牛奶盒、茶罐、酱油瓶、鸡蛋盒，沿用底色与UV；清掉相邻包装的碎片、转正正面，再通过Blender正式导出。原W14与W18文件保留。来源与SHA-256在`art/manifests/models_shop_refresh_20261009.json`，原稿保留在`art/models/raw/shop_refresh_20261009/`。

商店货架按米粮、蛋品、调料、饮料、日用品分层，复用已有米袋、瓶筐、黄瓜筐和陶器。两座中央货架的内容不同，每层数量与间隔不同；袋装商品成小组摆，瓶筐旁保留空处。朝向有小幅差异，背面商品朝向另一侧走道，墙架商品朝向室内。

烘焙架改为吐司、长面包、可颂、甜甜圈、红豆包、菠萝包、奶油面包与咖喱面包，柜台和备料墙架分别放点心与原料，玻璃柜继续放草莓蛋糕。位置差异是稳定的陈列安排，读档不会随机换位。午后减少陈列、店主补货、欢迎语、营业与真实购买规则继续使用。

商品仍由WorldBuilder.spawn放置，逐件查询层板的真实支撑面；没有新增阻挡人物的整排碰撞。实测尺寸、倾角、正面朝向、模型清单和素材室预览已更新。

## 验证

七条回归在旧实现上全部失败。商店专项现为31项：新增真实曲面深度、图片到原玻璃距离小于4毫米、数据绑定原电视SHA、非零雪花状态、独立货种、烘焙种类、朝向差异及中央货架数量差异。原来的营业、支撑、净空、工作往返、购买等检查保留。

仅检查shader参数抓不到实际黑屏，因此另加`audit_shop_noise.py`检查原生1280×720换台截图里的玻璃区域：图像须主要为黑白，亮度空间标准差大于0.08。旧电视、退化的浮点噪声都失败；整数噪声实拍通过，标准差约0.165、黑白比例100%。独占全量1366项通过，退出0、无SCRIPT ERROR；实际等待与其他实例每秒核对，未发现并发。完整结果、源文件边界和默认存档校验以`evidence/shop_fix_20261009/verification.json`为准。

```bash
HARUMACHI_SAVE_DIR=/tmp/harumachi-shop-tests timeout 180 ./tools/godot --headless --path game res://scenes/tests.tscn -- --only=shop-life --out=/tmp/shop-tests.json
HARUMACHI_SAVE_DIR=/tmp/harumachi-shop-views ./tools/godot --path game -t --position 3100,1990 --resolution 1280x720 res://scenes/main.tscn -- --clean=1 --shots=/tmp/shop-views --views=shop_tv,shop_tv_side,shop_tv_static,shop_groceries,shop_pastries
HARUMACHI_SAVE_DIR=/tmp/harumachi-shop-movie ./tools/godot --path game -t --position 3100,1990 --write-movie /tmp/shop.avi --fixed-fps 30 res://scenes/main.tscn -- --shop-life-demo=/tmp/shop-movie --shop-display-review
```

画面录像使用固定日期和镜头，展示真实shader时间、换台雪花、斜视曲面及两店陈列；不计自然游玩时长。本轮更新源工程并按仓库规则提交；桌面与Web的当前包仍以CURRENT_STATUS所列交付为准。
