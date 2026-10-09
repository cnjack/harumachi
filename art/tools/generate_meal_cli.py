"""Submit one recorded Hyper3D CLI task per meal asset; never retry a submission."""
import hashlib
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLI = pathlib.Path('/Users/jack/.nvm/versions/node/v26.3.0/bin/hyper3d')
STYLE = ('One standalone solid food portion for a Japanese slice-of-life anime game. '
         'Flat cel colours, matte surfaces, simple clean silhouette, no photographic texture, '
         'no gloss. No plate, tray, hand, person, text or backdrop mesh. Flat stable bottom, '
         'centered origin, separate ingredient colours, watertight GLB, about 4000 polygons. ')
PROMPTS = {
    'B07_veg_sandwich': STYLE + 'A single triangular sandwich wedge resting on its broad bottom, '
        'two ivory bread layers with thin golden crust, clearly visible layers of green cucumber '
        'and red tomato between them. About 12cm wide, 6cm tall, 8cm deep. No toothpick.',
    'B08_focaccia': STYLE + 'One rectangular focaccia serving, thick golden bread with gently rounded '
        'corners, two distinct red tomato pieces and sparse green herbs on its upper surface. '
        'About 12cm wide, 3cm tall, 9cm deep. Sparse stylized dimples, no realistic bread pores.',
}

def command(*args):
    result = subprocess.run([str(CLI), '--output', 'json', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('CLI failed; existing submission record retained. No automatic resubmission.')
    return json.loads(result.stdout)

def folder(asset):
    return ROOT / 'art/models/raw' / (asset + '_hyper3d_cli_20261006' + ('_reference' if reference else ''))

mode = sys.argv[1]
reference = len(sys.argv)>2 and sys.argv[2]=='reference'
for asset, prompt in PROMPTS.items():
    image_path = ROOT / 'game/assets/ui/icons' / ('bread_sandwich.png' if asset=='B07_veg_sandwich' else 'bread_focaccia.png')
    if reference:
        prompt = ('A single triangular vegetable sandwich wedge, two bread layers enclosing red tomato and green cucumber. ' if asset=='B07_veg_sandwich' else 'A single rectangular tomato focaccia bread serving with tomatoes and herbs on top. ') + 'Match the reference shape and ingredients. Solid thick anime game prop with flat matte colours and simplified texture. Only this one food, no other objects.'
    target = folder(asset)
    target.mkdir(parents=True, exist_ok=True)
    record = target / 'generation.json'
    if mode == 'submit':
        if record.exists():
            print(asset, 'existing task retained', flush=True)
            continue
        metadata = dict(provider='Hyper3D CLI', asset=asset, tier='Gen-2.5-High',
            mesh_mode='Quad', quality=4000, geometry_format='glb', texture_delight=True,
            prompt=prompt, status='submission_attempt', submission_count=1, submitted_at=time.time())
        record.write_text(json.dumps(metadata, indent=2))
        (ROOT / 'art/manifests/prompts' / (target.name + '.txt')).write_text(prompt + '\n')
        arguments = ['generate', '--prompt', prompt, '--tier', 'Gen-2.5-High',
            '--mesh-mode', 'Quad', '--quality', '4000', '--texture-delight', '--format', 'glb']
        if reference:
            arguments += ['--image',str(image_path)]
            metadata['reference_image'] = str(image_path.relative_to(ROOT))
            metadata['reference_sha256'] = hashlib.sha256(image_path.read_bytes()).hexdigest()
        response = command(*arguments)
        metadata.update(response=response, generation_id=response['generation_id'], status='queued')
        record.write_text(json.dumps(metadata, indent=2))
        print(asset, metadata['generation_id'], metadata['status'], flush=True)
    elif mode == 'collect':
        metadata = json.loads(record.read_text())
        if metadata['status'] == 'downloaded':
            print(asset, 'already downloaded', flush=True)
            continue
        generation_id = metadata['generation_id']
        try:
            status = command('status', generation_id)
        except RuntimeError:
            print(asset, 'status unavailable; existing task retained', flush=True)
            continue
        (target / 'status.json').write_text(json.dumps(status, indent=2))
        try:
            result = command('result', generation_id)
            files = [f for f in result['files'] if f['name'].endswith('.glb')]
        except (RuntimeError, KeyError):
            print(asset, 'not ready', flush=True)
            continue
        selected = next((f for f in files if 'pbr' in f['name']), files[0])
        (target / 'result.json').write_text(json.dumps(result, indent=2))
        partial = target / 'model.glb.partial'
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--silent',
            '--show-error', '--output', str(partial), selected['url']], check=True)
        if partial.read_bytes()[:4]!=b'glTF':
            raise RuntimeError('Downloaded file is not a GLB; the task was not resubmitted.')
        partial.replace(target / 'model.glb')
        metadata.update(status='downloaded', selected_file=selected['name'],
            sha256=hashlib.sha256((target / 'model.glb').read_bytes()).hexdigest(),
            task_url='https://hyper3d.ai/workspace/rodin/' + generation_id)
        record.write_text(json.dumps(metadata, indent=2))
        print(asset, 'downloaded', (target / 'model.glb').stat().st_size, flush=True)
    else:
        raise SystemExit('Use submit or collect')
