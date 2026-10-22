#!/usr/bin/env python3
"""Package only the files referenced by Mio.model3.json; no vendor runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

SOURCE = Path(__file__).resolve().parents[1] / 'Sources/MioApp/Resources/MioCubism'
README = '''# 澪 Live2D 网页模型

入口：Mio/Mio.model3.json。请解压整个 Mio 目录并保持相对路径，使用 HTTP/HTTPS 提供文件。
可导入支持 Cubism 4 的播放器；ZIP 导入功能由播放器决定。

- 格式：官方导出 MOC3，目标 Cubism 4.0，39 参数、58 ArtMesh。
- 动作组：Idle（12 秒自动待机）、wave（招手）、think（思考）、talk（说话）、encourage（加油）。后四项各 5 秒。
- 标准 exp3 表情：neutral、warm、joyful、curious、concerned、surprised、determined、sleepy；兼容 happy、thinking 别名。通过 model.expression(name) 选择。
- 支持标准 physics3 头发物理及眼口遮罩；播放器应开启物理和自动待机。
- 可选 mio-performance.js 接入事件和文字：const controller = await MioPerformanceController.create(model, "/Mio/"); controller.event({intent:"reply",mood:"happy",text:"你好，今天也一起加油。"})。
- Clef 决策可直接传 controller.respond(decision,text)，decision.expression 为 {style:"joyful",intensity:"normal",hand:"explain"}。不含 embedding 或第二个判断模型。
- intent 支持 welcome / quiet / waiting / reply；欢迎有 180 秒冷却，文字按标点停顿。JS 是 Pixi 0.4.0 适配层，其他播放器直接加载标准模型文件。
- 手型曲线禁用淡入淡出，避免两只手叠影。标准播放器使用 0.35 秒淡入淡出；可选控制器增加手腕速度约束与反向屈肘经放下姿态的过渡，适合中途打断动作。
- 左右转面由源模型 ParamAngleX（-30～30）控制，正面原画不变；ParamAngleZ 留给动作中的歪头。可选控制器保留动作角度，移除 Pixi 鼠标 X×Y 和呼吸额外叠加的歪头，避免左右看变成左右倾斜。
- v27 衣身与袖子比例：开衫外侧各收进最多 2.5 像素，袖筒和上下肘部衣料统一收窄最多 8%；保留肩根、袖口、关节中心和裸露手臂尺寸，直接包含在 MOC3 中。
- v25 裙摆比例：最宽处在源关键形中收窄 6%，腰线和腿部坐标保留；直接包含在 MOC3 中。
- v24 头部比例：头发、头脸及五官统一缩小 20%，固定各姿态原下巴连接点，五官内部比例和身体尺寸保留；直接包含在 MOC3 中。
- v22 身体转面：ParamBodyAngleX（-10～10）已绑定胸肩和腰部透视；脚固定，头和手臂保持连接。可选控制器以头部横向转角的 20% 驱动身体（最多 ±6）。
- v21 头颈：取消水平整体平移与待机歪头，收敛下颌位移和远侧眼压缩，保留固定领口。耳朵、鼻尖独立拆层；眼窝、脸颊下颌和前后头发采用各自的转面关键形，保留远侧眼的圆润形状与后脑体积。这些形变直接保存在 MOC3 中。
- Pixi Live2D 示例：Live2DModel.from('/Mio/Mio.model3.json')；手动招手 model.motion('wave', 0, 3)。

本包不含 Live2D Core 或播放器。请在自己的网页中使用已获得的兼容运行库。
已实测 Pixi 6.5.10 + pixi-live2d-display 0.4.0 Cubism4；并不表示每个第三方播放器均已验证。
模型源工程、PSD 和生成工具保留在仓库 art/live2d/mio/cubism 与 art/tools/live2d。
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((SOURCE / 'Mio.model3.json').read_text())
    refs = manifest['FileReferences']
    names = ['Mio.emotion.json','Mio.model3.json', refs['Moc'], refs['DisplayInfo'], refs['Physics'], *refs['Textures']]
    names += [motion['File'] for group in refs['Motions'].values() for motion in group]
    names += [expression['File'] for expression in refs.get('Expressions', [])]
    assert len(names) == len(set(names)), 'Duplicate runtime path'
    payload = {}
    for name in names:
        path = (SOURCE / name).resolve()
        assert path.is_relative_to(SOURCE.resolve()), 'Reference escapes model directory'
        payload['Mio/' + name] = path.read_bytes()
    assert payload['Mio/' + refs['Moc']][:4] == b'MOC3'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in payload.items():
            archive.writestr(name, data)
        archive.writestr('README-zh.md', README)
        archive.write(Path(__file__).with_name('mio-performance.js'), 'mio-performance.js')
    with zipfile.ZipFile(args.output) as archive:
        assert archive.testzip() is None
        assert all(archive.read(name) == data for name, data in payload.items())
    report = {'zip': str(args.output.resolve()), 'bytes': args.output.stat().st_size,
              'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'runtimeFiles': len(payload), 'motionGroups': list(refs['Motions']),
              'files': {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()},
              'vendorRuntimeIncluded': False, 'roundtripVerified': True}
    args.output.with_suffix('.verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'files'}, indent=2))


if __name__ == '__main__':
    main()
