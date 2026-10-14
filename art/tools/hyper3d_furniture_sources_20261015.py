"""Immutable, portable generated sources; never calls a paid provider."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[2]
def source_record(aid):
 ledger=json.loads((ROOT/'art/library/hyper3d_furniture_20261015/provenance.json').read_text());record=ledger['assets'][aid];path=ROOT/record['source_glb']
 assert hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],'Generated source changed'
 assert record['source_review']['source_sha256']==record['sha256'] and record['source_review']['source_geometry_usable_with_repairs'],'Source review does not bind this model'
 return path,record
