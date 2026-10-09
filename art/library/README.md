# 晴町 3D 素材室

从仓库根目录运行 `python3 art/tools/asset_library_server.py --port 8787`，打开 <http://127.0.0.1:8787/art/library/>。

- `catalog.json`：脚本生成的来源、许可、面数、尺寸配置、实际文件与游戏映射。
- `integration.json`：已选植被的源模型与米制高度。
- `previews/`：实际网格渲染缩略图。
- `vendor/three/`：本地 Three.js r180，保留 MIT LICENSE 与官方原包。
- `index.html`、`library.css`、`library.js`：分类、搜索和三维查看器。

模型原包在 `art/models/raw/`，游戏导出在 `game/assets/models/`。不要把它们复制成另一套失去来源的文件。完整许可、更新与 Godot 接入步骤见 [ASSET_LIBRARY.md](../../docs/game-design/ASSET_LIBRARY.md)。
