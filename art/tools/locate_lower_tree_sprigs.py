"""Locate existing lower-bough green clumps in the actual imported bark UV texture.
Produces small reproducible anchor data, not new image pixels or a replacement tree.
"""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('--source',required=True,type=Path);p.add_argument('--albedo',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();d=json.loads(a.source.read_text());points=np.asarray(d['vertices']);uv=np.asarray(d['uv']);tri=np.asarray(d['indices'],dtype=np.int64).reshape(-1,3);centre=points[tri].mean(axis=1);texcoord=uv[tri].mean(axis=1);img=np.asarray(Image.open(a.albedo).convert('RGB'),dtype=float)/255.;xy=np.mod(texcoord,1.)*np.array([img.shape[1]-1,img.shape[0]-1]);rgb=img[xy[:,1].astype(int),xy[:,0].astype(int)];green=(rgb[:,1]>rgb[:,0]*1.08)&(rgb[:,1]>rgb[:,2]*1.12)&(rgb[:,1]>.12);valid=green&(centre[:,1]>=2.65)&(centre[:,1]<=5.45)&(np.linalg.norm(centre[:,[0,2]],axis=1)>1.15);groups={}
for index in np.flatnonzero(valid):
 key=tuple(np.floor(centre[index]/.55).astype(int));groups.setdefault(key,[]).append(int(index))
anchors=[]
for key,indices in sorted(groups.items()):
 if len(indices)<4:continue
 c=centre[indices].mean(axis=0);normal=np.cross(points[tri[indices,1]]-points[tri[indices,0]],points[tri[indices,2]]-points[tri[indices,0]]).sum(axis=0);length=np.linalg.norm(normal)
 if length>.00001:normal/=length
 else:normal=np.array([c[0],0,c[2]])/max(np.linalg.norm(c[[0,2]]),.001)
 anchors.append({'at':[round(float(v),5)for v in c],'normal':[round(float(v),5)for v in normal],'source_triangles':len(indices)})
assert len(anchors)>=12,len(anchors);result={'source_sha256':d['source_sha256'],'source_albedo_sha256':hashlib.sha256(a.albedo.read_bytes()).hexdigest(),'method':'Existing green lower-bough source triangles grouped into0.55m surface clusters; original trunk, upper crown and alpha atlas retained','anchors':anchors};a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'anchors':len(anchors),'green_triangles':int(valid.sum()),'height_range_m':[float(centre[valid,1].min()),float(centre[valid,1].max())]}))
