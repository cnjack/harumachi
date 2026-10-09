# 晴町和纸 UI 素材库 v1.0

游戏使用的 UI 源库。暖白和纸、鼠尾草绿、深青线条与少量金色装饰；配合透明图标和圆形地图边缘。预览场景为 `res://scenes/ui_kit_gallery.tscn`，可切换组件状态、图标与组合示例。

## 内容

| 目录 / 文件 | 用途 |
| --- | --- |
| `assets/` | 8 张原始透明 PNG，保留生成结果 |
| `png/` | 33 个图标、16 张控件底图，独立透明 PNG |
| `resources/` | Godot Theme、图标与控件状态等52个编辑器资源 |
| `catalog.json` / `catalog.gd` | 52 个素材 ID、图集与实际像素坐标；JSON另含原图摘要 |
| `tokens.gd` | 颜色、文字层级、间距与标准尺寸 |
| `styles.gd` | 面板、按钮、物品格、列表行、提示卡、进度条的统一样式 |
| `components.gd` | 按钮、文字、图标和进度条的可复用构造器 |
| `gallery.gd` | 独立展示，不依赖游戏状态或存档 |

## 在 Godot 中使用

将 `ui_kit/` 和霞鹜文楷 `assets/fonts/LXGWWenKai-Medium.ttf`、字体的 `OFL.txt` 放入工程。先等待资源导入完成，再打开预览场景。编辑器用户可以直接给根 Control 的 Theme 指定 `ui_kit/resources/theme.res`，或给 Button 的主题覆盖指定 `button_primary_normal.res` 等资源。

```gdscript
extends Control

func _ready() -> void:
    theme = UIKitStyles.theme()
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", UIKitStyles.surface("modal", 24))
    add_child(card)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", UIKitTokens.SPACING[3])
    card.add_child(column)
    column.add_child(UIKitComponents.label("今日委托", "section"))
    column.add_child(UIKitComponents.icon("quest", 32))
    column.add_child(UIKitComponents.button("查看委托", show_quest, "primary"))

func show_quest() -> void:
    print("查看委托")
```

## 角色和状态

| 组件 | 参数 |
| --- | --- |
| `surface(role, margin)` | `modal` 大弹框；`hud` 窄卡片。窄卡 margin≤18 会自动使用更小角区 |
| `button(role, state, compact)` | role：primary / secondary / quiet / icon；普通文字按钮有 normal / hover / pressed / disabled 四张底图，focus为金色空心轮廓 |
| `slot(role, margin)` | normal / selected / disabled / empty |
| `row(role, margin)` | normal / selected / disabled |
| `notice(tone, margin)` | info / warning |
| `progress(part, colour)` | track / fill；填充使用 SAGE、GOLD 或 CORAL |
| `label(text, role)` | caption18 / body22 / section26 / title36 / hero48，均为1920×1080逻辑尺寸字号 |

普通按钮高50，紧凑按钮高40；物品格基准96；图标常用24 / 32 / 48。Quiet按钮普通状态透明，悬停后显示底图；图标按钮悬停和按下使用选中物品格。不要用状态图上的颜色替代游戏规则中的可用状态：禁用仍要设置 `Button.disabled`，选中页签仍要设置选中逻辑。

`UIKitAssets.icon(id)` 返回原图区域，不把图标预先缩成小图；`render_texture(id, width)` 用实际像素区域等比缩放并缓存，供九宫格样式使用。不要把完整留白图集直接拉伸到控件，也不要统一指定同一个角区：弹框、HUD与薄进度条分别匹配自己的比例。

## 更新素材

游戏工程在 `art/tools/prepare_ui_kit.py` 中维护图集分格和透明区域；原 PNG 保持不变。更新原图后：

```bash
python art/tools/prepare_ui_kit.py
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game --script res://ui_kit/build_resources.gd
"$GODOT" --headless --path game --import
```

`build_resources.gd` 导出编辑器资源和独立PNG，遇到保存错误会退出失败。来源、提示词、哈希与字体许可在独立素材包内保存。新增素材必须登记语义ID；界面只选择角色，不各自复制颜色和边框。

独立素材包由 `art/tools/package_ui_kit.py` 生成。打包后要在解压目录实际导入、运行展示场景；游戏接入还要跑 `--only=ui-kit`、素材审计和真实界面截图。

## 标题猫的 2D 动画（2026-10-04）

`animations.json` 单独登记动画素材；不改变原图标、按钮和面板目录的数量。`resources/title_cat.tres` 是可直接给 AnimatedSprite2D 使用的 SpriteFrames，含八帧 walk、四帧 idle。原生透明图集位于 `assets/animations/title_cat/orange_walk_idle.png`，来源与摘要见同目录 `source.json`。AtlasTexture 的 region/margin 对齐头部与脚底；不修改、抠色或缩放 PNG 原图。菜单装饰忽略鼠标和键盘焦点，无 GLB 或 3D SubViewport 依赖。

### 垂尾卧猫（2026-10-05）

调用 `UIKitComponents.resting_cat(76,0.8)`，作为 PanelContainer 的装饰子节点，默认趴在上边缘偏右处。身体固定，尾巴垂到面板内部轻摆；不会拦截输入或改变面板最小尺寸，暂停时继续动画。来源和参数在 `animations.json`、`assets/animations/title_cat/rest_source.json`；标题动画另用 `title_cat_rest.tres` 的四帧趴下和反向起身。
