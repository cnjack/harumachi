# GitHub项目维护

目标仓库：<https://github.com/cnjack/harumachi>。当前工作区本身是Git仓库；游戏、网站、设计文档和必要开发素材放在同一历史中。

## 提交范围

提交`game/`的全部运行资源、代码和数据，`site/`的网页源码/媒体，`tools/`、`art/tools/`、素材来源记录、参考图和保留的authoring，以及设计文档。二进制按`.gitattributes`交给Git LFS；Godot `.uid`和可编辑导入设置继续跟踪。

忽略生成缓存`.godot/`、桌面/Web导出`builds/`、网站游戏导出`site/play/`、测试存档与`evidence/`、历史输出`output/`、原始生成包`art/models/raw/`、POC和音频备选。忽略不删除本机资料。依赖原稿的素材再导出按本地归档路径准备；最终可运行素材在`game/assets/`完整维护。

证据文档中的`evidence/`链接属于本机验收资料，不保证克隆仓库时可直接访问。公开版本变更应记录Git提交和测试摘要，完整截图/录像可随选定的Release附加，避免把全部历史数据库和临时工程提交。

## 日常流程

```bash
git switch -c fix/具体问题
git lfs pull
# 修改后运行相关检查与实际画面
python3 tools/check_project.py
git add <本轮文件>
git diff --cached --stat
git commit -m "说明具体修改"
git push -u origin HEAD
```

用Pull Request写具体问题、改后行为和验证。不要用force push覆盖既有历史，不提交访问令牌、个人存档或导出包。源检查CI采用只读权限，默认不拉取大量LFS内容；真实Godot全量与包验收按AGENTS本地执行。

## 引擎与凭据

共享`tools/godot-version.json`固定版本，`tools/godot.local.json`或`HARUMACHI_GODOT_BIN`只在本机选择二进制。各素材服务、GitHub登录和部署SSH凭据留在用户环境，不写入项目。推送前核实当前账户确实具有此仓库写权限。

## 构建与网站

项目源码是维护对象，已发布包是输出。桌面和Web编译包沿用`builds`唯一最新交付规则；网站当前发布可以早于桌面最新源码，差异明确写进CURRENT_STATUS。部署服务器与自动化凭据不要跟随普通Pull Request执行。
