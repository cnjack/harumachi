#!/usr/bin/env python3
"""Validate exported candidate data contracts, independently of visual acceptance.

The root UV and crown tag checks detect the failures preserved in rounds 5 and 7.
Uses only the standard library; no Blender, Godot, or image processing is needed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import struct

ROOT=Path(__file__).resolve().parents[1]

class GLB:
    def __init__(self,path):
        data=path.read_bytes()
        assert data[:4]==b'glTF'
        size=struct.unpack_from('<I',data,12)[0]
        self.doc=json.loads(data[20:20+size]);self.binary=data[28+size:]
    def values(self,index):
        a=self.doc['accessors'][index];v=self.doc['bufferViews'][a['bufferView']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        fmt={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
        stride=v.get('byteStride',struct.calcsize(fmt)*width)
        start=v.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from('<'+fmt*width,self.binary,start+i*stride) for i in range(a['count'])]
    def parts(self):
        return [(n,self.doc['meshes'][n['mesh']]) for n in self.doc['nodes'] if 'mesh' in n]
    def positions(self,prefix):
        return [p for n,m in self.parts() if n['name'].startswith(prefix)
                for primitive in m['primitives'] for p in self.values(primitive['attributes']['POSITION'])]

def rounded_points(points):return {tuple(round(v,5) for v in point) for point in points}

def area_squared(a,b,c):
    u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
    return sum(x*x for x in (u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]))

def rotate(q,v):
    x,y,z,w=q;vx,vy,vz=v
    tx=2*(y*vz-z*vy);ty=2*(z*vx-x*vz);tz=2*(x*vy-y*vx)
    return (vx+w*tx+y*tz-z*ty,vy+w*ty+z*tx-x*tz,vz+w*tz+x*ty-y*tx)

def audit(folder):
    checks=[]
    def check(name,passed,detail=None):checks.append({'check':name,'passed':bool(passed),'detail':detail})
    for path in sorted(folder.glob('T0*.glb')):
        glb=GLB(path);original=GLB(ROOT/'game/assets/models'/path.name)
        check(path.stem+' original trunk positions retained',rounded_points(glb.positions('Trunk'))==rounded_points(original.positions('Trunk')))
        for node,mesh in glb.parts():
            if not node['name'].startswith('Foliage'):continue
            primitive=mesh['primitives'][0];attrs=primitive['attributes']
            positions=glb.values(attrs['POSITION']);uv=glb.values(attrs['TEXCOORD_0']);normals=glb.values(attrs['NORMAL'])
            indices=[r[0] for r in glb.values(primitive['indices'])]
            tags=sum(p[0]<-.5 for p in uv)
            check(path.stem+' surviving inner crown',tags>100,{'tagged_vertices':tags})
            check(path.stem+' finite normalized foliage normals',all(all(math.isfinite(x) for x in n) and .98<sum(x*x for x in n)<1.02 for n in normals))
            degenerate=sum(area_squared(*[positions[k] for k in indices[i:i+3]])<1e-14 for i in range(0,len(indices),3))
            check(path.stem+' nondegenerate foliage triangles',degenerate==0,{'triangles':len(indices)//3,'degenerate':degenerate})
    grass=GLB(folder/'Grass_curved.glb')
    parts=grass.parts();check('all 15 grass variants exported',len(parts)==15)
    for node,mesh in parts:
        p=mesh['primitives'][0];positions=grass.values(p['attributes']['POSITION']);uv=grass.values(p['attributes']['TEXCOORD_0'])
        root_count=sum(v[1]<.0001 for v in positions)
        check(node['name']+' anchored wind roots',root_count>0 and all(abs(t[1])<.0001 for v,t in zip(positions,uv) if v[1]<.0001),{'root_edge_vertices':root_count})
        check(node['name']+' finite upright blades',all(all(math.isfinite(x) for x in v) and v[1]>=-.0001 for v in positions))
    building_path=folder/'S02_refined.glb'
    if building_path.exists():
        building=GLB(building_path)
        for node,mesh in building.parts():
            if not node['name'].startswith('GableFascia'):continue
            axis=rotate(node.get('rotation',[0,0,0,1]),(0,1,0))
            check(node['name']+' follows sloped roof',abs(axis[0])>.55 and abs(axis[1])>.4 and abs(axis[2])<.01,{'axis':axis})
        names=[n['name'] for n,m in building.parts()]
        check('continuous replacement canopy and fascia',all(n in names for n in ('TensionedCanvas','ScallopedCanvas','ContinuousFrontFascia')))
    result={'checks':checks,'passed':sum(x['passed'] for x in checks),'failed':sum(not x['passed'] for x in checks),
            'scope':'export data only, not human visual acceptance',
            'asset_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.glob('*.glb'))}}
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--assets',type=Path,default=ROOT/'game/assets/material_light_poc/shape');parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();result=audit(args.assets);args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:result[k] for k in ('passed','failed')}))
    for check in result['checks']:
        if not check['passed']:print(check['check'],check['detail'])
    raise SystemExit(bool(result['failed']))

if __name__=='__main__':main()
