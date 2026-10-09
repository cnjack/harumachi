# 项目维护指南

《明年夏祭》的游戏工程、官方网站、设计文档与必要开发素材统一维护于 [cnjack/harumachi](https://github.com/cnjack/harumachi)。`main` 是完成验证后的项目基线。

## 版本管理范围

版本库包含 `game/` 的代码、数据和运行资源，`site/` 的网站源码与媒体，以及制作工具、提示词、素材来源和设计文档。模型、图片、音频、字体和扩展二进制由 Git LFS 管理；Godot 的 `.uid` 和可编辑导入设置继续跟踪。

生成缓存、编译包、个人存档、测试数据库、本机证据、大型原始生成包及试验副本不提交。忽略规则不删除本地资料。游戏运行资源保存在 `game/assets/`，重导出所需原稿按素材流程准备。

设计文档中的 `evidence/` 链接指向本机验收资料，克隆仓库时不一定包含。公开变更记录应给出版本、验证摘要和已知限制；选定截图或录像可附加到 GitHub Release。

## 任务交付

1. 确认工作区与远端状态，保留其他任务尚未完成的修改。
2. 完成实现与文档更新，执行 `python3 tools/check_project.py` 以及本轮相关测试。
3. 验证实际运行或界面；涉及游戏交付时完成独立存档、解压包与自动演示验收。
4. 只暂存本轮已验收文件，审阅差异并提交。
5. 推送 `origin/main`，确认远端提交一致且 GitHub CI 通过。

```bash
git status --short
python3 tools/check_project.py
# 运行本轮相关测试与实际验收
git add <已验收文件>
git diff --cached --stat
git commit -m "Describe the verified change"
git push origin main
```

任务完成且测试通过后推送 `main` 已获项目维护者持续授权。明确的当轮暂缓指令优先。远端有新提交时正常整合并重新验证，不强制推送。外部协作者可通过 Pull Request 提供贡献。

## 环境与凭据

引擎精确版本由 `tools/godot-version.json` 固定。本机二进制使用 `HARUMACHI_GODOT_BIN` 或忽略的 `tools/godot.local.json` 配置。素材服务、GitHub 与部署凭据留在本机环境，不写入项目。

CI 使用只读仓库权限，检查源码、数据与提交边界；不默认下载全部 LFS 内容，也不自动部署服务器。实际 Godot 和导出包验证按 [AGENTS.md](../AGENTS.md) 执行。

## 许可与发布

原创代码、文档及有权授权的原创素材采用 [MIT](../LICENSE)。第三方内容保留原许可，详见 [ASSET_LICENSES](../ASSET_LICENSES.md)。修改或引入素材时同步来源记录。

桌面和 Web 编译包遵守 `builds/` 只保留最新验收版本的规则。官网与游戏各自发布，线上快照可以早于桌面源码；差异记录在 CURRENT_STATUS。网站部署见 [site/README.md](../site/README.md)，网页游戏构建见 [WEB.md](game-design/WEB.md)。
