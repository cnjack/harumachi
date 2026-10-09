"""Remove PBR reflection/normal maps without changing any mesh, UV or animation.

Generated ORM textures override scalar Metallic/Roughness defaults in Blender.
This material-only repair makes the on-disk GLB conform to the anime palette.
"""
import argparse
import json
from pathlib import Path
import struct
from edit_model_atlas import load, signature


def matte(source,output):
    g,b=load(source);before=signature(g,b);changed=[]
    for index,m in enumerate(g.get('materials',[])):
        p=m.setdefault('pbrMetallicRoughness',{})
        dirty='normalTexture' in m or 'metallicRoughnessTexture' in p or p.get('metallicFactor',1)!=0
        if not dirty:continue
        m.pop('normalTexture',None);p.pop('metallicRoughnessTexture',None)
        p['metallicFactor']=0;p['roughnessFactor']=0.92
        ext=m.setdefault('extensions',{});ext['KHR_materials_specular']={'specularFactor':0}
        changed.append(index)
    if changed:
        if 'KHR_materials_specular' not in g.setdefault('extensionsUsed',[]):g['extensionsUsed'].append('KHR_materials_specular')
        header=json.dumps(g,ensure_ascii=False,separators=(',',':')).encode();header+=b' '*(-len(header)%4)
        b+=b'\0'*(-len(b)%4)
        data=struct.pack('<III',0x46546c67,2,28+len(header)+len(b))+struct.pack('<II',len(header),0x4e4f534a)+header+struct.pack('<II',len(b),0x004e4942)+b
        Path(output).parent.mkdir(parents=True,exist_ok=True);Path(output).write_bytes(data)
        gg,bb=load(output)
        if signature(gg,bb)!=before:raise ValueError('Material repair changed geometry/UV/animation')
    return {'id':Path(source).stem,'changed_materials':changed,'geometry_uv_sha256':before,'geometry_uv_unchanged':True}


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('model_dir',type=Path);ap.add_argument('report',type=Path);args=ap.parse_args()
    results=[matte(p,p) for p in sorted(args.model_dir.glob('*.glb'))]
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(results,indent=2))
    print('MATTE',len([x for x in results if x['changed_materials']]),'repaired GLBs; geometry unchanged')
