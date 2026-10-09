# 免费树木与植被素材核对

核对日期：2026-10-04。以下来自作者或官方素材商店，许可和免费版本范围分别核对。

| 素材 | 免费部分 | 格式与用途 | 来源 |
| --- | --- | --- | --- |
| Quaternius Stylized Nature MegaKit Standard | 实际下载包为 68 个模型，CC0；完整版 116 个并非全都免费 | glTF、FBX、OBJ；树、灌木、花、草与岩石，适合统一动漫植被 | [作者](https://quaternius.com/packs/stylizednaturemegakit.html)、[下载](https://quaternius.itch.io/stylized-nature-megakit) |
| Quaternius Ultimate Stylized Nature Pack | 作者页面列 63 个模型，整包免费，CC0 | glTF、FBX、OBJ、Blend；风格化树木与花草 | [作者页面](https://quaternius.com/packs/ultimatestylizednature.html) |
| KayKit Forest Nature Pack FREE | 免费层 100+ 模型，CC0；Extra 和 Source 收费 | glTF、FBX、OBJ；更简洁的树、灌木、草与岩石 | [作者页面](https://kaylousberg.com/game-assets/forest-nature-pack)、[下载](https://kaylousberg.itch.io/kaykit-forest) |
| Kenney Nature Kit | 作者页面列 330 份素材，CC0；下载包实查有 329 个 GLB | 几何更简单，适合远景、零散植被和布局 | [作者页面](https://kenney.nl/assets/nature-kit) |

优先选择 MegaKit Standard。其 Ghibli 风格更接近日式动漫小镇，已有树干、树冠、花草和灌木可以统一使用。此处是画风判断，不代表已经替换主场景。免费版没有现成的 Godot 工程或风动画着色器，这些属于收费 Source 版。接入时还需要匹配现有光照，叶片透明裁切与树干、叶片的风权重分开处理。

## 实际下载和检查

- MegaKit 原 ZIP：`art/models/raw/free_foliage_20261004/quaternius_standard/original.zip`，104,088,529 字节。SHA-256：`298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`。
- 免费范围和许可：`quaternius_standard/unpacked/License_Standard.txt`，明确列 68/116 与 CC0。
- 使用独立 Godot 4.7.2 工程导入并实例化全部 68 个 glTF，失败 0，无 SCRIPT ERROR。结果：`evidence/free_foliage_20261004/godot-probe/verification.json`。
- Kenney 原包：`art/models/raw/free_foliage_20261004/kenney/original.zip`。仅做解压和文件清点，尚未做全部模型的导入检查。
- 下图为实际模型的 Blender 预览，统一了展示尺寸与照明，原模型和贴图保持原文件；不代表游戏最终光照。八个示例的三角面数和原始尺寸见 `evidence/free_foliage_20261004/examples.json`。

![免费 MegaKit 实际模型示例](../../evidence/free_foliage_20261004/quaternius_examples.png)

## 推荐具体文件

庭院树先看 `CommonTree_1.gltf` 和 `CommonTree_3.gltf`；树林中混用 `CommonTree_4.gltf`、`Pine_1.gltf`、`Pine_3.gltf`；院墙附近用 `Bush_Common.gltf`、`Bush_Common_Flowers.gltf`；地面点缀用 `Grass_Common_Short.gltf`、`Grass_Wispy_Short.gltf` 和 `Flower_3_Group.gltf`。这些文件均在免费 Standard 包内。最终取舍仍以放进小镇后的近景和摆放检查为准。
