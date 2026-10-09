# Godot4.8迁移与文档刷新（2026-10-07）

用户要求将现有工程更新到Godot4.8，并按当前内容刷新AGENTS及其他文档。目标版本是官方4.8-dev7开发快照，精确二进制为4.8.dev7.official.c971f93e7；它仍非稳定版，版本身份见[官方发布页](https://godotengine.org/download/archive/4.8-dev7/)。

## 版本与工具

`tools/godot-version.json`统一指定引擎、features、模板版本和固定二进制。`./tools/godot`每次启动校验精确版本；本轮将已安装的官方应用复制到`/Users/jack/workpath/godot/tools/godot-4.8-dev7/Godot.app`，不覆盖全局安装或4.7.2历史工具。project.godot使用4.8与Forward Plus，custom_user_dir_name仍为晴町日常。

模板从官方HTTPS档案按ZIP范围提取，验证长度和CRC，记录SHA256；只装macos.zip、单线程Web动态扩展的debug/release及version.txt。版本必须为4.8.dev7。安装工具不再依赖2026-10-01的4.7.2证据文件。

Godot-SQLite仍沿用现有4.7最低兼容库；[官方GDExtension说明](https://docs.godotengine.org/en/latest/tutorials/scripting/cpp/about_godot_cpp.html)允许较早版本扩展用于后续小版本，实际迁移以本轮SQLite规则与解压包结果为准。未更换数据库路径或格式。

## 实际检查

- 独立副本从干净导入开始；4.8导入0退出，1329项全量0失败，无SCRIPT ERROR、SHADER ERROR或材质空引用。
- 原生四视角为厨房、卧室、商店和居民招手；截图已查看，角色、UI、材料与场景正常。截图是夹具，不替代普通入场或自然时长。
- 同版本桌面模板、导出、解压应用精确引擎、签名与双架构、200项完整夏季到Q15及保存/控制恢复均通过，退出0。唯一桌面包已原子替换，SHA256为`e4ebd7806dfff0b1e1de76551d640f61436678c3b1d0053e9ed62671162ecf62`。
- 默认五份存档数据库摘要一致、运行代码与素材未变、临时工程已清理；本轮冻结后仅UI README说明更新，单独记录。证据在evidence/godot48_docs_20261007/delivery.json及post-doc-source-audit.json。
- 不自动启用纹理流送、接触阴影或改变现有画风；没有声称性能提升。Web准备工具已支持4.8并保留UI图集坐标，线上Web仍是已发布4.7.2快照。

## 文档修订

README/PLAN重新整理为当前入口，旧全文归档到history。CURRENT_STATUS集中引擎、交付、实际内容和待验；PIPELINE保留制作方法，日期验收追加移到历史页。GAMEPLAY区分新合作主线与旧档跑腿；WORLD改真3D餐点；FUN_REVIEW保留原权重和未过75状态；夏季规划的预算与实际接入分开；WEB和site区分开发工程与已发布版本。

原生持续输入阻断已关闭，普通首餐与修后门路已验；连续普通三天、两种自然整篇、210–270分钟和75分依然待验。45–90分钟是现有内容估计，技术路径时间另列。

解压包技术演示969.653秒，包含自动对白、预定选择和阶段暂停，不是自然游玩时长。Web.prepare实际验证4.8 Compatibility并保持63份UI PNG摘要；独立UI包从ZIP解压、4.8导入及三页图库通过。线上Web入口HTML/JS读回摘要与本地旧发布一致，本轮未部署Web。

迁移后已按用户后续要求部署Web，发布20261007-203612；本页“未部署Web”描述迁移批次当时范围，现状见CURRENT_STATUS及WEB。
