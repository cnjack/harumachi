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

- 格式：官方导出 MOC3，目标 Cubism 4.0，29 参数、30 ArtMesh。
- 动作组：Idle（12 秒自动待机）、wave（招手）、think（思考）、talk（说话）。后三项各 5 秒。
- 五种标准 exp3 表情：neutral、happy、thinking、concerned、sleepy；通过 model.expression(name) 选择。
- 支持标准 physics3 头发物理及眼口遮罩；播放器应开启物理和自动待机。
- 可选 mio-performance.js 接入事件和文字：const controller = await MioPerformanceController.create(model, "/Mio/"); controller.event({intent:"reply",mood:"happy",text:"你好，今天也一起加油。"})。
- intent 支持 welcome / quiet / waiting / reply；欢迎有 180 秒冷却，文字按标点停顿。JS 是 Pixi 0.4.0 适配层，其他播放器直接加载标准模型文件。
- 手型曲线禁用淡入淡出，肩肘腕曲线仍使用 0.35 秒过渡，避免两只手叠影。
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
    names = ['Mio.model3.json', refs['Moc'], refs['DisplayInfo'], refs['Physics'], *refs['Textures']]
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
