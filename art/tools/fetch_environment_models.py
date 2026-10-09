"""Resume the three already-submitted CLI jobs; never submit paid generations."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import ssl
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CONTEXT = ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')

def cli(action, generation):
    response = subprocess.run(['hyper3d', '--output', 'json', action, generation], capture_output=True, text=True, check=True)
    return json.loads(response.stdout)

def fetch(asset):
    folder = ROOT / 'art/models/raw' / (asset + '_hyper3d')
    submission = json.loads((folder / 'submission.json').read_text())
    generation = submission['generation_id']
    deadline = time.monotonic() + 1500
    while time.monotonic() < deadline:
        status = cli('status', generation)
        print(asset, status['status'], status.get('stage', {}).get('name', ''), flush=True)
        if status['status'] == 'completed':
            break
        if status['status'] == 'failed':
            raise RuntimeError(asset + ': generation failed; no resubmission')
        time.sleep(20)
    else:
        raise TimeoutError(asset + ': retain job id and resume later')
    result = cli('result', generation)
    candidates = [file for file in result['files'] if file.get('name', '').lower().endswith('.glb')]
    selected = next((file for file in candidates if 'pbr' in file['name'].lower()), candidates[0])
    with urllib.request.urlopen(selected['url'], context=CONTEXT, timeout=180) as response:
        (folder / 'model.glb').write_bytes(response.read())
    record = {'generation_id': generation, 'status': 'downloaded', 'file': selected['name'],
              'display_url': result.get('display_url'), 'tier': 'Gen-2.5-High', 'mesh_mode': 'Raw',
              'requested_faces': 500000, 'texture_delight': True}
    (folder / 'generation.json').write_text(json.dumps(record, indent=2))
    print('SAVED', asset, (folder / 'model.glb').stat().st_size, flush=True)
    return record

if __name__ == '__main__':
    with ThreadPoolExecutor(max_workers=3) as pool:
        records = list(pool.map(fetch, ['E01_furin', 'V04_daisy_meadow', 'V05_river_reeds']))
    (ROOT / 'art/manifests/models_hyper3d_environment_20261006.json').write_text(json.dumps(records, indent=2))
