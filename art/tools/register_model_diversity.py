"""Register explicitly reviewed, prepared candidates in the normal game export recipe.

Does not generate models or approve them. Selection requires an evidence review.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'evidence/hyper3d_diversity_20261013'
RAW = ROOT / 'art/models/raw/diversity_20261013'


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', required=True)
    args = parser.parse_args()
    scope = {r['id']: r for r in read(ROOT / 'art/manifests/model_diversity_20261013.json')['assets']}
    config_path = ROOT / 'art/models/game_assets.json'
    catalog_path = ROOT / 'game/data/model_diversity.json'
    manifest_path = ROOT / 'art/manifests/models_hyper3d_diversity_20261013.json'
    config, catalog, manifest = read(config_path), read(catalog_path), read(manifest_path)
    for aid in args.ids.split(','):
        row = scope[aid]
        selection = read(EVIDENCE / 'selected-reviews' / (aid + '.json'))
        prepared = read(RAW / 'ready' / (aid + '.json'))
        candidate = prepared['candidate']
        generation = read(RAW / aid / candidate / 'generation.json')
        actual_sha = hashlib.sha256((RAW / 'ready' / (aid + '.glb')).read_bytes()).hexdigest()
        if (selection['status'] != 'source_accepted' or selection['candidate'] != candidate
                or selection['prepared_sha256'] != actual_sha or prepared['prepared_sha256'] != actual_sha
                or min(selection['scores'].values()) < 4):
            raise RuntimeError(aid + ': missing, stale or failed individual review')
        recipe = dict(src='raw/diversity_20261013/ready/' + aid + '.glb', fit=row['fit'], size=row['size_m'],
                      tris=int(row['triangle_budget'] * .9), tex=1024,
                      provider='Hyper3D CLI Gen-2.5-High; reviewed anime reference and Blender local cleanup, 2026-10-13',
                      weld=.0002, preserve_material_names=True, roughness=1., specular=0.,
                      level=not aid.startswith(('C', 'T')), yaw=selection.get('export_yaw', 0),
                      license='Hyper3D account-generated asset; provenance in models_hyper3d_diversity_20261013.json',
                      source_page=generation['task_url'])
        if prepared.get('preserve_parts'):
            recipe.update(preserve_parts=True, preserve_origin=True, image_format='AUTO', level=False)
        config['assets'][aid] = recipe
        item = dict(label=row['label'], kind=row['action'], triangle_budget=row['triangle_budget'],
                    size_m=row['size_m'], fit=row['fit'], generation_id=generation['generation_id'],
                    source_sha256=generation['sha256'], prepared_sha256=actual_sha)
        catalog['assets'][aid] = item
        manifest['assets'][aid] = dict(**item, candidate=candidate, reference=row['reference'],
            reference_sha256=read(RAW / aid / candidate / 'intent.json')['reference_sha256'],
            task_url=generation['task_url'], local_geometry_changes=prepared['local_geometry_changes'],
            previous_export=row.get('previous_export'), export=recipe,
            source_review=str((EVIDENCE / 'selected-reviews' / (aid + '.json')).relative_to(ROOT)),
            scores=selection['scores'], observations=selection['observations'],
            acceptance='source reviewed; full native/exported-package acceptance pending')
        print('REGISTERED', aid, candidate, flush=True)
    write(config_path, config)
    write(catalog_path, catalog)
    write(manifest_path, manifest)


if __name__ == '__main__':
    main()
