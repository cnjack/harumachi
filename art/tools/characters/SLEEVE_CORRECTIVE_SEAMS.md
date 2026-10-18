# 伸展修形接缝修复

本入口修复现有 `SleeveFit_stretch_*` 的 POSITION/NORMAL 字段。它不新增修形、不改变原动画时间或权重函数，不改骨骼、基础网格、皮肤权重、UV、纹理、其他修形及衣裙数据。当前验证对象是澪 v80；其他角色需要自己的源身份、采集与验收。

输入是原 GLB 和同一 GLB 的原生五向姿态 manifest，后者必须有每根骨骼最终 basis、实际形状权重，以及上级目录的 `model-hashes.json`。输入捕获数据属于本地证据，不随仓库提供，入口不会声称能从新克隆重新制作全部模型。

```sh
python art/tools/characters/synchronize_sleeve_corrective_seams.py \
  --input source.glb --manifest capture/joint-poses/manifest.json \
  --output closed-field.glb --report closed-field.json \
  --character mio --feather 0 --smoothing-iterations 20
python art/tools/characters/stabilize_sleeve_corrective_fields.py \
  --input closed-field.glb --manifest capture/joint-poses/manifest.json \
  --output candidate.glb --report candidate.json --character mio --samples 128
python art/tools/characters/audit_sleeve_corrective_seams.py \
  --source source.glb --candidate candidate.glb \
  --manifest capture/joint-poses/manifest.json --output audit.json --expect-fixed
```

第一步在原白衣区域内，把同位置、兼容原皮肤权重的 UV 副本和原手臂切缝视为同一物理顶点。跨 mesh 先按部件平均，以免 UV 副本数量决定缝的位置，再沿真实源拓扑平滑既有位移场。主网格的暖色皮肤固定；独立 Sleeve 是原提取衣片，保留其暖色阴影布料。

第二步让同物理顶点的四个伸展目标共用一个幅度因子，以同姿态未加这四个目标的原表面为参考，限制新几何方向和面面积。共同因子同时保持插值过程中的物理接缝。稳定检查包括四个真实原生峰值与129个原动画相位。NORMAL 旋转跟随修改的几何方向，保留原硬边偏差与 UV 法线副本；不把基础法线统一抹平。

同一审计以 `--candidate source.glb --expect-fixed` 检查旧输入，应明确失败。原生截图/连续动作仍由采集方复验：离线通过不等于灰楔与袖口自然度通过，也不证明自交全部消失。旧字段及失败探索保留证据，不能用已闭缝代替视觉验收。
