"""Independently compare decoded character semantics before/after GLB packing.

Walks every live primitive, morph, skin and animation reference by its semantic
location; accessor/view renumbering and removal of unused samplers are allowed.
Float arrays are compared byte for byte, including signed zero. No renderer is
started and no visual/contact acceptance is inferred.
"""
from pathlib import Path
import argparse
import hashlib
import json

from glb_io import load
from prepare_local_garments import read


def audit(args):
    old, blob = load(args.input)
    new, packed = load(args.output)
    comparisons = []

    def same_array(a, b, label):
        av, bv = read(old,blob,a), read(new,packed,b)
        assert av.shape == bv.shape and av.dtype == bv.dtype and av.tobytes() == bv.tobytes(), label
        comparisons.append({'scope':label,'scalar_values':int(av.size),'bytes':av.nbytes})

    def except_keys(value, keys):
        return {k:v for k,v in value.items() if k not in keys}

    for key in ['asset','nodes','scenes','scene','materials','textures','samplers','extensions','extensionsUsed','extensionsRequired']:
        assert old.get(key) == new.get(key), key
    assert len(old.get('meshes',[])) == len(new.get('meshes',[]))
    for mi,(om,nm) in enumerate(zip(old.get('meshes',[]),new.get('meshes',[]))):
        assert except_keys(om,['primitives']) == except_keys(nm,['primitives']), ('mesh metadata',mi)
        assert len(om['primitives']) == len(nm['primitives'])
        for pi,(op,np) in enumerate(zip(om['primitives'],nm['primitives'])):
            assert except_keys(op,['attributes','indices','targets']) == except_keys(np,['attributes','indices','targets'])
            assert op['attributes'].keys() == np['attributes'].keys()
            for name,index in op['attributes'].items():
                same_array(index,np['attributes'][name],f'mesh/{mi}/primitive/{pi}/attribute/{name}')
            assert ('indices' in op) == ('indices' in np)
            if 'indices' in op:
                same_array(op['indices'],np['indices'],f'mesh/{mi}/primitive/{pi}/indices')
            assert len(op.get('targets',[])) == len(np.get('targets',[]))
            names = om.get('extras',{}).get('targetNames',[])
            for ti,(ot,nt) in enumerate(zip(op.get('targets',[]),np.get('targets',[]))):
                assert ot.keys() == nt.keys()
                for name,index in ot.items():
                    same_array(index,nt[name],f'mesh/{mi}/primitive/{pi}/target/{names[ti] if names else ti}/{name}')
    assert len(old.get('skins',[])) == len(new.get('skins',[]))
    for si,(os,ns) in enumerate(zip(old.get('skins',[]),new.get('skins',[]))):
        assert except_keys(os,['inverseBindMatrices']) == except_keys(ns,['inverseBindMatrices'])
        if 'inverseBindMatrices' in os:
            same_array(os['inverseBindMatrices'],ns['inverseBindMatrices'],f'skin/{si}/inverseBindMatrices')
    assert len(old.get('animations',[])) == len(new.get('animations',[]))
    actions = []
    for ai,(oa,na) in enumerate(zip(old.get('animations',[]),new.get('animations',[]))):
        assert except_keys(oa,['channels','samplers']) == except_keys(na,['channels','samplers'])
        assert len(oa['channels']) == len(na['channels'])
        for ci,(oc,nc) in enumerate(zip(oa['channels'],na['channels'])):
            assert except_keys(oc,['sampler']) == except_keys(nc,['sampler'])
            os,ns = oa['samplers'][oc['sampler']],na['samplers'][nc['sampler']]
            assert except_keys(os,['input','output']) == except_keys(ns,['input','output'])
            for field in ['input','output']:
                same_array(os[field],ns[field],f'animation/{oa.get("name",ai)}/channel/{ci}/{field}')
        actions.append({'name':oa.get('name',''),'channels_exact':len(oa['channels'])})
    assert len(old.get('images',[])) == len(new.get('images',[]))
    image_hashes = []
    for oi,ni in zip(old.get('images',[]),new.get('images',[])):
        assert except_keys(oi,['bufferView']) == except_keys(ni,['bufferView'])
        if 'bufferView' in oi:
            ov,nv = old['bufferViews'][oi['bufferView']],new['bufferViews'][ni['bufferView']]
            raw = blob[ov.get('byteOffset',0):ov.get('byteOffset',0)+ov['byteLength']]
            compact = packed[nv.get('byteOffset',0):nv.get('byteOffset',0)+nv['byteLength']]
            assert raw == compact
            image_hashes.append(hashlib.sha256(raw).hexdigest())
    report = {'scope':'Independent live-reference decode: all base attributes/indices, every morph POSITION/NORMAL, skin/IBM, node JSON, all original action channels/time/scalars and embedded image bytes',
              'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'output':str(args.output),'output_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'all_live_arrays_bit_exact':True,'array_reference_comparisons':len(comparisons),
              'scalar_values_compared':sum(r['scalar_values'] for r in comparisons),
              'decoded_bytes_compared':sum(r['bytes'] for r in comparisons),'actions':actions,
              'node_json_mesh_default_weights_target_names_exact':True,'embedded_image_sha256':image_hashes,
              'no_renderer_started':True,'pass':True,'array_details':comparisons}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(args.report,'pass',len(comparisons),'arrays',len(actions),'actions',flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--report',required=True,type=Path)
    audit(parser.parse_args())
