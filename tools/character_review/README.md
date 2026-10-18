# 人物绑定人工点评界面

把已有原生截图组织成逐项人工点评界面，不启动游戏，也不修改绑定。

```bash
python3 tools/character_review/build.py --evidence /path/to/new-evidence
node --test tools/character_review/model.test.cjs
```

完整交互回归使用开发依赖`linkedom`执行真实页面脚本，不启动浏览器或服务器，也不依赖本地证据与大截图：

```bash
npm --prefix tools/character_review install
npm --prefix tools/character_review test
python3 tools/character_review/test_build.py
```

在新的证据目录打开 `index.html`。原始点评批次保留原样，修复后重拍或新增连续视角时使用另一个目录。需要保留 `locomotion-poses/`、`joint-poses/` 及其清单；骨架叠图和 `motion-previews/` 为可选素材。工具按现有七个人物、七种动作构建49个项目，读取每个动作全部相位和五个方向。HTML内嵌索引，不通过网络请求读取清单。

每项可填写整体判断、四个分项和文字意见；画面意见绑定精确的动作相位与方向，可以附归一化坐标标记。连续移动模式按当前方向选对应GIF，并可切换实际录制的方向；缺少顶部或侧面时，会明确标出当前实际方向与已有选项，不把右侧冒称顶部。相位、骨架和XY标记只用于静态画面，GIF的意见写在“本项意见”。居民跑步按各视角实际记录的速度标注；无数值时显示“游戏实际速度”或“速度未记录”，不在日程中使用的跑步明确标为动作对照。看过图片不算完成点评，“稍后再看”也不计入已点评。

意见输入后立即写入当前浏览器存储。浏览器拒绝存储时，界面持续提示手动导出，不能显示保存成功。导出JSON包含全部49项、未点评但已写下的意见、原图与骨架叠图来源摘要；文字版用于阅读。将JSON交回聊天即可继续处理。不同浏览器之间用导出、导入继续。

导入先完整校验数据集、项目、帧、状态和坐标。默认按项目补齐尚未填写的内容；同一项目已有意见时保留当前项目，不混入导入文件的同项意见。选择替换时先保存一份旧状态，操作后可立即撤销；用户继续编辑后取消整包撤销，避免抹掉新意见。数据集身份包含原图、叠图及全部`motion_views`的文件SHA与速度标签，重拍非默认方向也会生成新身份。旧单`motion`集合保留原摘要算法，JSON schema_version=1、localStorage键和导入协议保持兼容。

生成目录仍在忽略的 `evidence/`，不提交截图、个人意见或导出文件。界面源码保存在本目录，生成时只更新HTML、CSS和JS，不覆盖点评JSON，也不清除浏览器进度。

连续原生截图可独立转换为实时长预览，不启动游戏、不更新点评页面：

```bash
python3 tools/character_review/motion_previews.py --evidence /path/to/new-evidence
python3 tools/character_review/test_motion_previews.py
```

需要 Pillow。工具读取 `continuous/continuous-gait.json`（也支持 `--input <报告>`），按每张原图实际 `elapsed_s` 生成 320px 身像 GIF，以累计10ms边界取整保持时长，整条预览共用固定调色板。原PNG保留；每人另有走/跑三视角、八个最接近实际相位的图表，标明真实相位和时间。`motion-previews/manifest.json`记录来源报告、每张PNG、预览及图表的SHA与实际GIF时长。它只组织画面，不能代替原图精细衣物和穿模验收。

各方向输出如 `ren-walk-front.gif`、`ren-run-fast-back.gif`，录制左侧/顶部时还会有`-left.gif`/`-top.gif`；右侧同时保留旧单视角别名 `ren-walk.gif`、`ren-run-fast.gif`。空的跑步别名为 `sora-run.gif`。构建器优先用预览manifest逐视角读取文件、实际速度与SHA，拒绝与manifest不符的GIF；缺少manifest时仍支持旧单视角和带方向后缀的文件。旧14组报告没有`view`时按历史右侧处理，不继承界面当前选择的方向。预览工具不写`index.html`，不会改旧UI或点评文件；最终素材完成后才对新的证据目录运行构建器。

## 从修复候选重新取证

使用新的证据目录，保留原始点评批次。`capture.py`在临时项目中覆盖候选模型，启动独立虚拟显示器，使用Dummy音频与独立存档；结束后核对默认存档摘要、释放显示器并检查临时项目删除。它不覆盖正式模型或交付包。

```bash
python3 tools/character_review/capture.py --out /path/to/new-evidence --candidate-models /path/to/frozen-models
python3 tools/character_review/annotate.py --evidence /path/to/new-evidence
python3 tools/character_review/build.py --evidence /path/to/new-evidence
```

默认拍七人、七动作，共1400张五方向原生截图，以及14组真实走跑。原图不经重画；骨架叠图来自同一渲染帧的最终SkeletonModifier3D姿势，按记录的投影视口尺寸缩放。每次静止采样必须收到较晚一帧的请求确认，并与实际渲染帧、动作名和时间相符。

可用`--jobs joint-poses --actors sora --clips stretch --phases 0.375,0.625`缩小复现范围；`--pose-views front`可只采一个方向，默认仍为前、右、后、左、顶五方向。`--jobs hands --hand-clips stretch`给双手分别拍两面近景；取景位置来自最终骨架，不能把被衣服挡住的近景称为完整手部验收。

`--jobs continuous --continuous-clips walk`或`--continuous-clips run`只取对应的真实移动动作，可配合`--continuous-views front,right,back,left,top`。不传时仍采走路和跑步，人物、速度、两周期和采样方式保持原设置；该选项不影响静态或动作切换取证。报告的`requested_clips`明确记录本次范围。轻量参数检查运行`python3 tools/character_review/test_capture.py`，不启动 Godot。

`--jobs transitions`记录真实控制器的起步、走跑切换、停止、挥手和鞠躬收势。`analyze_transitions.py <transition-gait.json>`生成图表和原生联系图；`tools/audit_character_transitions.py --input <报告> --output <结果>`只检查明确界定的启动/收势回归，报告实际覆盖和跳过数量。高速摆腿的最大位移不能单独判为跳变，也不能把这些局部回归当作全部动作自然的证明。

`--jobs multi-performance`在同一镇场景交替测三人衣物修正开/关，测量窗口不截图；应独占运行，避免其它游戏或离线重算污染结果。连续取证虽记录求解计时，但截图读回和诊断探针有额外开销，不能替代独占性能对照。

`--garment-risk-actors mio`仅给指定人物启用风险源面诊断，避免把尚无对应profile的其他人物一起切换。`--garment-fixed-layer-reuse`与`--garment-skin-direction-skip`保留为显式对照参数；当前已验收运行时默认安全启用这两项，不能再把它描述为默认关闭。显式诊断标记的画面同样不能作为最终点评素材；本机性能和可选原生后端范围见人物逐项记录。

`--hide-arm-fill`、`--disable-lod`和`--garment-proxy-mio`只用于定位问题，不能生成正式点评素材；构建器会拒绝带这些诊断标记的画面。`--export-garment-proxy`导出实际导入的源顶点与LOD面索引，供离线对照，不能混用GLB与Godot重新排序后的顶点编号。

用户明确要求使用现有桌面时，所有取证命令添加`--display existing`（需要时用`--screen 0`选择已有屏幕）。该分支不编译或启动虚拟显示器程序，仍使用Dummy音频、临时工程和隔离存档，结束后记录`virtual_display_created=false`。

## 最终视频的49项复评

`python3 tools/character_review/video_build.py --evidence evidence/character_videos_final_20261018`为已验证的九条最终影片生成独立入口。每人站立、走、跑、挥手、伸展、鞠躬使用单人原片，舞蹈使用七人同场并标明对应人物位置。可暂停、慢放、按真实机位跳转、记录视频时间点并导出完整49项JSON。新协议和浏览器存储与旧图片页独立，原结果保留。

来源核对、保护规则、导入流程和验证范围见[视频入口说明](video_README.md)。`npm test`同时运行原图片页与新版视频页交互测试；Python协议检查为`python3 -m unittest discover -s tools/character_review -p 'video_test_*.py'`。离线DOM/媒体事件模型不代替真实浏览器播放和布局验收。
