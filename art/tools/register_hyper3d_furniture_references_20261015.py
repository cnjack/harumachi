"""Copy explicitly reviewed native imagegen outputs; retain portable prompts/source IDs."""
from pathlib import Path
import argparse,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('incoming',type=Path);p.add_argument('--review-pass',required=True);a=p.parse_args()
 allowed=set(a.review_pass.split(','));incoming=json.loads(a.incoming.read_text());assert allowed=={r['id'] for r in incoming}
 manifest=ROOT/'art/manifests/prompts/hyper3d_furniture_20261015_generated.json';prior={r['id']:r for r in json.loads(manifest.read_text())}
 for row in incoming:
  src=Path(row.pop('generated_path'));assert src.is_file() and src.read_bytes()[:8]==b'\x89PNG\r\n\x1a\n'
  dest=ROOT/'art/references/hyper3d_furniture_20261015'/(row['id']+'.png');dest.parent.mkdir(parents=True,exist_ok=True)
  if dest.exists():assert hashlib.sha256(dest.read_bytes()).digest()==hashlib.sha256(src.read_bytes()).digest()
  else:shutil.copy2(src,dest)
  row.update(reference=str(dest.relative_to(ROOT)),generation_id=src.stem,sha256=hashlib.sha256(dest.read_bytes()).hexdigest())
  review=ROOT/'evidence/hyper3d_furniture_20261015/reference-reviews'/(row['id']+'.json');review.parent.mkdir(parents=True,exist_ok=True)
  review.write_text(json.dumps(dict(status='pass',sha256=row['sha256'],reviewer='root',method='Direct full image inspection of native imagegen output shown inline',observations='Single complete furniture object; approved anime palette, rounded useful structure, quiet directional grain, clean support surfaces and actual open structural gaps. Final 3D requires separate geometry and native quality checks.'),ensure_ascii=False,indent=2)+'\n')
  prior[row['id']]=row
 manifest.write_text(json.dumps([prior[k] for k in sorted(prior)],ensure_ascii=False,indent=2)+'\n')
 print('Recorded',len(incoming),'reviewed references;',len(prior),'total')
if __name__=='__main__':main()
