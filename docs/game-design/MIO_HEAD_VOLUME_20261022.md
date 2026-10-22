# 澪头部体积修复（2026-10-22，v20）

用户指出 v19 转面仍像纸片。本轮在源模型中拆出耳朵和鼻尖，重做各部位的 XY 关键形，保留原眉眼、嘴部、0.736 头部比例及已确认的加油前臂内收。

## 实际修改

- `HeadParts.swift` 把原脸底的左右耳和鼻尖拆成独立 ArtMesh。耳根保留向脸下方延伸的重叠区，近侧耳根跟随脸颊；远侧耳向脸后方收进，由脸和侧发遮挡。正式 PSD/CMO3 从 55 层变为 58 层，参数仍为 38 个。
- 原鼻尖移动后会露出旧高光，因此用内置 imagegen 补一张无鼻高光的脸底。只采用鼻下方羽化的 26×30 源像素区域；其余脸底、耳朵、眉眼和嘴部继续来自原画。完整生成结果和实际提示词分别保存在 `Resources/Mio/face_nose_fill.png` 与 `art/manifests/prompts/live2d/mio-nose-fill-20261022.txt`。
- `FaceRig.turn` 为脸颊下颌、左右眼窝、鼻尖、嘴部、耳朵、发顶侧发和后发分别定义转面形状。远侧眼宽保留 88%，近侧为 102%；后脑宽保持在原宽附近。鼻尖、嘴和耳朵有不同的前后位移，侧发有根部一致的包裹变化。
- 这些形变写入 CMO3/MOC3 的关键形。Swift 和网页读取同一正式模型，不依赖播放器额外扭曲。思考 motion3 的食指接触随新下巴重新烘焙；其余四组动作文件保持原摘要。

PSD 使用标准 PackBits 无损存储，从 177,005,374 字节缩为 6,980,788 字节。`inspect_psd_channels.py` 独立解码核对 58 层的 232 个通道，像素完全相同；官方重新导出后 24 个运行文件摘要全部相同。

第一版候选出现侧发盖脸过多和耳根露细边，已经在源关键形及拆分范围中修正。最后检查的是修正后的 58 部件版。

## 验证证据

证据目录：`evidence/mio_head_volume_20261022/`。静态对照使用固定姿态、同一相机，关闭头发物理和视线扰动；不以晃动掩盖轮廓问题。

| 检查 | 本轮结果 |
| --- | --- |
| 固定转面 | 水平七档 × 上下五档，共 35 张真实 Core/Metal 图，逐图检查 |
| 正面保持 | 中性头部 RGB 平均误差各小于 0.007/255；颈部以下逐像素一致 |
| 回归负例 | 新检查对旧模型产生 33 个失败，能发现缺少耳鼻拆层、远侧眼压扁和后脑收窄 |
| Swift | 93 项，89 通过、4 项可选网络跳过；决策模型和网络行为未修改 |
| 正式格式 | 官方 Cubism 4.0 目标 MOC3，38 参数、58 ArtMesh；PSD 和 CMO3 同步 |
| Core 参数/动作 | 3,030 帧，38 参数均有实际作用 |
| 表情组合 | 3,240 组、360 张 Metal 图，无翻转或连接失败 |
| 全动作 | 6,514 张 Metal 帧，25 组切换；781,680 个连接带像素最小 alpha 254，最大接点误差 0.000137 px；13,028 皮肤带无暗线失败 |
| 头发 | 243 极值、1,209 Metal 帧，发根误差 0，物理残余 0；查看连续头部截帧 |
| 网页 | 25 组切换、5,379 帧；手腕峰值 826.19 px/s，低于 900 阈值；控制台无警告或错误 |

实窗首轮与图片分析、旧应用并行时仅 47.15 FPS，未达到 50 FPS 门槛，记录保留在 `native-busy/`。关闭旧应用、完成图片分析后独立复测：40.62 秒、2,419 帧、平均 59.55 FPS，九状态全部通过。原桌面来信已更新重启，确认 Clef 连接及持续出帧；全部 24 个运行资源与源目录、网页目录逐一核对摘要一致。结果见同目录 `verification.json` 与 `native/native-window.json`。

对照图：`head-before-after.png`（上为修复前，下为修复后），`head-grid.png`（35 角度），`hair-flow.png`（连续转头），`motion/look-extremes.png`（五动作视线极值）。网页可直接加载新版 `Mio/Mio.model3.json`；交付包为 `Mio-live2d-web.zip`，不含厂商运行库。

当前仍以正面至轻度侧向的动漫表现为目标；大幅侧面或背面需要新的侧面原画与关键形。检查通过表示本轮范围内的格式、连接、渲染和目视对照已完成，最终自然度仍由用户复评。

## 复现

```bash
python3 art/tools/live2d/export_mio.py --work /tmp/mio-head-export
bash native/mio-companion/tools/build_app.sh
native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --review-head /tmp/mio-head-after
# before 目录须来自旧模型的同一固定姿态入口
python3 native/mio-companion/tools/review_head.py /tmp/mio-head-after --before /tmp/mio-head-before --output /tmp/mio-head-comparison
```

`MIO_HEAD_FIXTURE` 可指定独立的标准模型目录供 `--review-head` 和 `HeadVolumeTests` 使用。工具仅合成测试截图联系表，不改源图。官方制作方法依据见[前轮调研](MIO_HEAD_VOLUME_RESEARCH_20261022.md)。
