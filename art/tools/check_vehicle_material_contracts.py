"""Exercise vehicle-only metal allowances against actual used GLB materials."""
import argparse
import copy
import json
from pathlib import Path
from unittest.mock import patch

import model_audit


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', type=Path, default=root / 'game/assets/models')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    specs = json.loads((root / 'art/models/model_quality_contracts.json').read_text())['authored_vehicle_materials']
    rows = []
    for model, spec in specs.items():
        path = args.model_dir / (model + '.glb')
        graph, binary = model_audit.load(path)
        actual = model_audit.material_report(path, spec)
        rows.append({'model': model, 'case': 'authored finishes', 'passed': actual['ok'], 'failures': actual['failures']})
        if not actual['ok']:
            continue
        approved_name = next(iter(spec))
        for case in ['flattened metal', 'flattened roughness', 'unlisted metal', 'normal map', 'ORM map', 'missing named finish']:
            candidate = copy.deepcopy(graph)
            approved = next(mat for mat in candidate['materials'] if mat.get('name') == approved_name)
            if case == 'flattened metal':
                approved['pbrMetallicRoughness']['metallicFactor'] = 0.
            elif case == 'flattened roughness':
                approved['pbrMetallicRoughness']['roughnessFactor'] = 1.
            elif case == 'unlisted metal':
                paint = next(mat for mat in candidate['materials'] if mat.get('name') in actual['actual'] and mat.get('name') not in spec)
                paint.setdefault('pbrMetallicRoughness', {})['metallicFactor'] = .6
            elif case == 'normal map':
                approved['normalTexture'] = {'index': 0}
            elif case == 'ORM map':
                approved['pbrMetallicRoughness']['metallicRoughnessTexture'] = {'index': 0}
            else:
                approved['name'] += '_unexpected'
            with patch.object(model_audit, 'load', return_value=(candidate, binary)):
                result = model_audit.material_report(path, spec)
            rows.append({'model': model, 'case': case, 'passed': not result['ok'], 'failures': result['failures']})
    report = {'passed': all(row['passed'] for row in rows), 'checks': len(rows), 'rows': rows}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': report['checks']}))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
