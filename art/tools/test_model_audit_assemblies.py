"""A real unchanged oven is accepted; removing real glass must fail."""
import json,struct,tempfile,unittest
from pathlib import Path
from edit_model_atlas import load
from model_audit import measure,assembly_report
ROOT=Path(__file__).resolve().parents[2]
class AssemblyAudit(unittest.TestCase):
 def test_real_assembly_and_missing_glass(self):
  source=ROOT/'game/assets/models/P_deck_oven.glb'
  spec=json.loads((ROOT/'art/models/model_quality_contracts.json').read_text())['intentional_assemblies']['P_deck_oven']
  accepted=assembly_report(source,spec,measure(source)['topology'])
  self.assertTrue(accepted['ok'],accepted)
  model,binary=load(source)
  glass={i for i,m in enumerate(model['materials']) if m.get('name')=='Oven_HeatGlass'}
  removed={i for i,n in enumerate(model['nodes']) if 'mesh' in n and all(p.get('material') in glass for p in model['meshes'][n['mesh']]['primitives'])}
  self.assertTrue(removed)
  for node in model['nodes']:
   if 'children' in node:node['children']=[i for i in node['children'] if i not in removed]
  for scene in model['scenes']:scene['nodes']=[i for i in scene['nodes'] if i not in removed]
  data=json.dumps(model,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
  binary+=b'\0'*((-len(binary))%4)
  packed=struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(binary),0x004e4942)+binary
  with tempfile.TemporaryDirectory(prefix='harumachi-oven-audit-') as folder:
   missing=Path(folder)/'missing-glass.glb';missing.write_bytes(packed)
   rejected=assembly_report(missing,spec,measure(missing)['topology'])
  self.assertFalse(rejected['ok'])
  self.assertEqual(set(rejected['insufficient_parts']),{'Oven_HeatGlass'})
  # The unused material name remains in the GLB, so a name-only check fails
  # to catch this actual missing surface. No game/source file is mutated.
  self.assertTrue(any(m.get('name')=='Oven_HeatGlass' for m in model['materials']))
if __name__=='__main__':unittest.main()
