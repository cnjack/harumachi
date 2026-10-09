# 标题上沿与垂尾猫（2026-10-05）

按用户草图，小猫在「明年夏祭」文字上沿走动，到右侧后趴下，尾巴垂到标题前方左右轻摆；休息七秒后起身返回。显示缩小到原图的 0.20，比原前景路上的猫小。尾巴落在「夏、祭」附近，标题与按钮仍清楚可读。原生 22.1 秒、30 FPS 演示为 `evidence/cat_ui_rest_20261005/title-cat-dangling.mp4`，静帧见 `title-native/lying.png` 与 `lying-detail.png`。

背包、日历、设置也加入同款卧猫，趴在面板上边缘，尾巴垂到面板内部空白处。背包放在顶部中间，日历与设置放在偏右处，避开标题、数值和按钮。菜单设置窗口与游戏内设置均使用同一组件。

## 动画资源

首版尾巴向后平摆，不符合用户补充的草图，已拒收。按草图重新生成的透明原图为 `game/ui_kit/assets/animations/title_cat/orange_lie_dangling.png`；确切提示词与两次来源记录在 `art/manifests/prompts/cat_motion_20261004/`、`images_codex.json`。原图像素及 alpha 保留，不抠色、不重新采样。

`register_rest_sprites.py` 读取原生轮廓，登记四帧趴下、倒放起身，以及八帧垂尾。AtlasTexture 的 region/margin 对齐头部和脚底。卧猫身体固定为一张 Sprite2D，尾巴单独用 AnimatedSprite2D 播放；尾根缓慢摆动约 ±4°，下垂部分沿竖轴放大 1.4 倍，保持尾根与边缘连接。身体不随尾巴抖动。

菜单控制为 `game/scripts/ui/menu_cat.gd`，以 `TitleHeading` 的实际位置和文字宽度定位。复用组件为 `game/ui_kit/cat_decoration.gd`，接口 `UIKitComponents.resting_cat(width,anchor_fraction)`，资源见 `game/ui_kit/animations.json`。它忽略鼠标与焦点，暂停时尾巴仍播放；没有 3D 视口或 GLB 依赖。

## 验证

旧版回归失败：猫不在标题上方，没有趴下/起身状态，也没有卧猫设置装饰。新版十项独立检查通过，覆盖纯 2D、小尺寸、标题位置、完整状态循环、静止身体、鼠标穿透、键盘焦点、实际设置/完成点击，以及暂停时尾巴继续动。

背包、日历、设置三处真实面板分别检查并截图，两相位均显示尾巴变化，身体位置和纹理不变。证据为 `evidence/cat_ui_rest_20261005/panels-native/`。UI KIT 16 项回归与私有边框审计保持通过。独立猫检查不改变主测试集计数；本轮未导出或发布安装包。
