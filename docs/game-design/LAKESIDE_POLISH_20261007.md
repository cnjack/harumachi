# 湖岸、浅滩与旧木细节

用户指出两岸太直、向日葵过多、水面缺少浅深变化和溪石，以及路面、立牌、桥木太单调。先在当前 Main 场景拍摄七个视角，再修改并按同样视角复查。

## 实际变化

- 桥附近保留中心和跨河位置，其他河段有缓弯和宽窄变化；河中心样本变化约 2.8 米，宽度变化约 1.2 米。地形、水面、地图、岸边碰撞共用形状。贴水地形细分为 0.5 米，消除原 1.5 米网格产生的岸边棱角。
- 远岸装饰向日葵从 12 株减为两个小组、共 4 株。温室原有作物不删，全农园当前共 6 株。
- 水底由河床到湖心加深；颜色从浅青绿过渡到深蓝，浅水半透明，减少整片云反射压过水色的问题。水深同时参考实际深度纹理，石头进入水中有可见水线。
- 沿溪流和湖岸浅滩复用 30 处 D10 溪石，使用新的手绘石面。高低和尺度有变化，避开钓鱼落点；通过物理地面射线支撑，不能把渲染水面当作石头的底座。
- 小路有宽窄变化、参差边缘和干燥磨痕；原地面和石板增加少量局部色差，保持用户选定方向。
- 农园立牌有手绘叶纹、青海波边饰、掉漆和旧钉；文字仍由清晰 Label3D 单独绘制。桥面和栏杆使用旧杉木纹理，板间有色差、日晒、磨痕和旧雨迹；桥的网格与可通行碰撞不变。

四张新贴图由内置 imagegen 生成，原图在 art/references/lakeside_polish_20261007/，提示词在 art/manifests/prompts/lakeside_polish_20261007/，实际纹理在 game/assets/textures/lakeside_polish/。石头复用已有 Pixal3D 网格，未新提交收费 3D 生成。来源登记在 images_codex.json 和 models_lakeside_polish_20261007.json。

## 验证

新 LAKESIDE_POLISH 八项先用旧场景运行，八项全部失败；最终八项全部通过。湖区通行与钓鱼 39 项、天气联动 23 项、PLACEMENT 12 项、PROPS 46 项通过，共 128 项。道具普查中发现的 20 处溪石悬空已修正，最终普查零悬空。

当前开发测试总数为 1235，增加的八项已经进入全量入口。本轮没有运行全量：另一普通游戏运行仍在使用，按 AGENTS 的并发约束保留该会话，未终止它，也未把专项结果称为全量通过。日志保留引擎退出时的资源清理和 headless dummy material 提示；无本轮 SCRIPT ERROR。

全部测试和截图都显式设置独立 HARUMACHI_SAVE_DIR。成片由 Godot 4.7.2 Forward+ 实际录制，1600×900、30 fps、约 21 秒，七个镜头；FFmpeg 解码与时长检查通过。源工程已更新，本轮没有导出或替换 builds。

证据：evidence/lakeside_polish_20261007/verification.json。视频：lakeside-polish.mp4。修改前后对比：bridge_banks-comparison.png、lake_overview-comparison.png、sign_close-comparison.png、path_and_sign-comparison.png。桥木旧图镜头不同，只用于问题确认，不作为同视角材质对照。
