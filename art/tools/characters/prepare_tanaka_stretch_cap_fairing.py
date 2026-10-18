#!/usr/bin/env python3
"""Rebuild Tanaka's four stretch-only sleeve correctives from the uncorrected LBS.

The geometric guide lowers only data-selected upward sleeve crests by12mm with
40mm physical-geodesic falloff. It never reuses the split legacy Fit displacement.
Coincident compatible POSITION/JW copies share one displacement. Shoulder/cuff
boundaries and bare skin stay pinned; source hard-edge normals follow the new
geometry. Other target payloads, base mesh/UV/skin/rest and all curves stay exact.
"""
import os
for key in ['OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS']:os.environ[key]='1'
import argparse,copy,hashlib,heapq,json
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix,diags
from scipy.sparse.csgraph import connected_components
from glb_io import load
from repair_head_neck import read,append,save
from audit_local_garments import mesh_state
from prepare_local_garments import colours
from motion_math import world_matrices,sample_channel
from corrective_normals import unit,geometry_normals,rotate_between


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def body_data(path):
 s=mesh_state(path,'tanaka');d,b=s['d'],s['b'];mesh=d['meshes'][s['node']['mesh']];prim=mesh['primitives'][0];return s,d,b,mesh,prim


def native_matrices(d,b,s,shot):
 world,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};inv=np.linalg.inv(np.asarray(shot['model_basis']).T);origin=np.asarray(shot['model_position'])
 for bone in shot['bones']:
  i=ids[bone['name'].replace('mixamorig_','mixamorig:')];world[i]=np.eye(4);world[i][:3,:3]=inv@np.asarray(bone['basis']).T;world[i][:3,3]=inv@(np.asarray(bone['position'])-origin)
 return world,skin_matrices(s,world)


def skin_matrices(s,world):
 mats=np.asarray([world[j]@ib for j,ib in zip(s['skin']['joints'],s['binds'])]);B=np.zeros((len(s['positions']),3,3));T=np.zeros_like(s['positions'],float)
 for k in range(s['joints'].shape[1]):B+=mats[s['joints'][:,k],:3,:3]*s['weights'][:,k,None,None];T+=mats[s['joints'][:,k],:3,3]*s['weights'][:,k,None]
 return B,T


def physical_mesh(s,faces):
 N=len(s['positions']);dense=np.zeros((N,len(s['skin']['joints'])))
 for slot in range(s['joints'].shape[1]):np.add.at(dense,(np.arange(N),s['joints'][:,slot]),s['weights'][:,slot])
 pairs=cKDTree(s['positions']).query_pairs(1e-6,output_type='ndarray');pairs=pairs[np.max(abs(dense[pairs[:,0]]-dense[pairs[:,1]]),axis=1)<=.001];graph=coo_matrix((np.ones(2*len(pairs)),(np.r_[pairs[:,0],pairs[:,1]],np.r_[pairs[:,1],pairs[:,0]])),shape=(N,N)).tocsr();ng,groups=connected_components(graph,directed=False);count=np.bincount(groups);edges=np.unique(np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1),axis=0);pe=groups[edges];pe=np.unique(np.sort(pe[pe[:,0]!=pe[:,1]],axis=1),axis=0);return groups,count,pe


def projection(points,a,e,w):
 segments=[(a,e),(e,w)];best=np.full(len(points),np.inf);arc=np.zeros(len(points));closest=np.zeros_like(points);offset=0.
 for p,q in segments:
  vec=q-p;length=np.linalg.norm(vec);t=np.clip((points-p)@vec/(vec@vec),0,1);cp=p+t[:,None]*vec;radius=np.linalg.norm(points-cp,axis=1);chosen=radius<best;best[chosen]=radius[chosen];arc[chosen]=offset+t[chosen]*length;closest[chosen]=cp[chosen];offset+=length
 return arc,closest,best


def fold_status(base,new,faces):
 n0=np.cross(base[faces[:,1]]-base[faces[:,0]],base[faces[:,2]]-base[faces[:,0]]);n1=np.cross(new[faces[:,1]]-new[faces[:,0]],new[faces[:,2]]-new[faces[:,0]]);a0=np.linalg.norm(n0,axis=1);a1=np.linalg.norm(n1,axis=1);live=a0>1e-12;turn=live&(np.einsum('ij,ij->i',n0,n1)<0);collapse=live&(a1<a0*.15);return np.flatnonzero(turn),np.flatnonzero(collapse)


def guide_field(s,d,world,posed,rgb,faces,groups,count,physical_edges,drop,feather):
 ng=len(count);P=np.zeros((ng,3));np.add.at(P,groups,posed);P/=count[:,None];names=[d['nodes'][j]['name'] for j in s['skin']['joints']];ids={n.get('name'):i for i,n in enumerate(d['nodes'])};blue=(rgb[:,2]>rgb[:,0]*1.08)&(rgb[:,2]>rgb[:,1]*1.01);shift=np.zeros((ng,3));sides=[];allfree=np.zeros(ng,bool)
 for side,sign in [('Left',1),('Right',-1)]:
  chain=[world[ids['mixamorig:'+side+part]][:3,3] for part in ['Arm','ForeArm','Hand']];a,e,w=chain;upper=np.linalg.norm(e-a);fore=np.linalg.norm(w-e);raised=np.clip(((w-e)[1]/fore-.1)/.35,0,1);raised=raised*raised*(3-2*raised)
  share_mask=np.array([n.startswith('mixamorig:'+side+'Arm') or n.startswith('mixamorig:'+side+'ForeArm') or n=='TWIST_'+side for n in names]);share=(s['weights']*share_mask[s['joints']]).sum(1);allowed=blue&(share>.5)&(sign*s['positions'][:,0]>.2);gallowed=np.bincount(groups,weights=allowed,minlength=ng)==count;arc,cp,radius=projection(P,*chain);gallowed&=(arc>upper*.25)&(arc<upper+fore*.8);edges=physical_edges;boundary=np.zeros(ng,bool);cross=gallowed[edges[:,0]]!=gallowed[edges[:,1]];boundary[np.unique(edges[cross])]=True;free=gallowed&~boundary;allfree|=free
  if not free.any() or raised==0:
   sides.append(dict(side=side,raise_factor=float(raised),seed=None,cap_drop_m=0.));continue
  eligible=free&((P-cp)[:,1]>.025)&(arc>upper*.6)&(arc<upper+fore*.65)
  if not eligible.any():sides.append(dict(side=side,raise_factor=float(raised),seed=None,cap_drop_m=0.));continue
  eligible_ids=np.flatnonzero(eligible);seed=int(eligible_ids[np.argmax(P[eligible_ids,1])]);adj=[[] for _ in range(ng)]
  for u,v in edges:
   if free[u] and free[v]:
    length=float(np.linalg.norm(P[u]-P[v]));adj[u].append((int(v),length));adj[v].append((int(u),length))
  dist=np.full(ng,np.inf);dist[seed]=0.;queue=[(0.,seed)]
  while queue:
   value,at=heapq.heappop(queue)
   if value!=dist[at]:continue
   for to,length in adj[at]:
    candidate=value+length
    if candidate<dist[to] and candidate<feather:dist[to]=candidate;heapq.heappush(queue,(candidate,to))
  t=np.clip(dist/feather,0,1);gain=1-t*t*(3-2*t);gain[~free]=0;shift[:,1]-=drop*raised*gain;sides.append(dict(side=side,raise_factor=float(raised),seed_physical_group=seed,seed_source_vertices=np.flatnonzero(groups==seed).tolist(),seed_model=P[seed].tolist(),cap_drop_m=float(drop*raised),support_physical_vertices=int((gain>0).sum())))
 # Two mild Taubin passes on the displacement, not on the garment's base mesh.
 u,v=physical_edges.T;graph=coo_matrix((np.ones(2*len(u)),(np.r_[u,v],np.r_[v,u])),shape=(ng,ng)).tocsr();degree=np.asarray(graph.sum(1)).ravel();average=diags(1/np.maximum(degree,1))@graph
 support=np.linalg.norm(shift,axis=1)>0
 for _ in range(2):
  for amount in [.35,-.36]:shift+=amount*((average@shift)-shift);shift[~support|~allfree]=0
 norm=np.linalg.norm(shift,axis=1);shift*=np.minimum(1,drop/np.maximum(norm,1e-15))[:,None]
 return shift[groups],sides


def build(args):
 if args.output.exists():raise ValueError('Use a fresh immutable candidate output')
 s,d,raw,mesh,primitive=body_data(args.input);native_s,nd,nb,nm,np0=body_data(args.native_source)
 assert d['nodes']==nd['nodes'] and d['skins']==nd['skins']
 for semantic,accessor in primitive['attributes'].items():assert np.array_equal(read(d,raw,accessor),read(nd,nb,np0['attributes'][semantic]))
 assert np.array_equal(read(d,raw,primitive['indices']),read(nd,nb,np0['indices']))
 native=json.loads(args.manifest.read_text());proof=json.loads((args.manifest.parent.parent/'model-hashes.json').read_text());assert proof['CH_tanaka.glb']==sha(args.native_source)
 names=mesh['extras']['targetNames'];chosen=[i for i,name in enumerate(names) if name.startswith('SleeveFit_stretch_')];assert len(chosen)==4
 for index in chosen:
  assert not np.any(read(nd,nb,np0['targets'][index]['POSITION'])) and not np.any(read(nd,nb,np0['targets'][index]['NORMAL']))
 # All source bone curves for stretch must match the source used for native noFit.
 a=next(a for a in d['animations'] if a['name']=='stretch');na=next(a for a in nd['animations'] if a['name']=='stretch');assert a==na
 for c in a['channels']:
  sampler=a['samplers'][c['sampler']];ns=na['samplers'][c['sampler']]
  for semantic in ['input','output']:assert np.array_equal(read(d,raw,sampler[semantic]),read(nd,nb,ns[semantic]))
 original=copy.deepcopy(d);binary=bytearray(raw);faces=read(d,raw,primitive['indices']).reshape(-1,3);rgb=colours(d,raw,primitive);groups,count,edges=physical_mesh(s,faces);N=len(s['positions']);base_normals=unit(read(d,raw,primitive['attributes']['NORMAL']));reports=[];new_positions={};native_refs=[]
 for index in chosen:
  name=names[index];phase=int(name.rsplit('_',1)[1])/1000.;shot=next(shot for shot in native['shots'] if shot['id']=='tanaka' and shot['clip']=='stretch' and shot['phase']==phase and shot['view']=='front');world,(B,T)=native_matrices(d,raw,s,shot);base=np.einsum('nij,nj->ni',B,s['positions'])+T;shift,sides=guide_field(s,d,world,base,rgb,faces,groups,count,edges,args.drop,args.feather);delta=np.einsum('nij,nj->ni',np.linalg.pinv(B),shift)
 # Collapse the rest-space field after inverse skinning: coincident physical
 # copies may not receive different displacements even if a tiny JW differs.
  physical_delta=np.zeros((len(count),3));np.add.at(physical_delta,groups,delta);physical_delta/=count[:,None];delta=physical_delta[groups];factor=1.
  for attempt in range(15):
   result=base+np.einsum('nij,nj->ni',B,delta*factor);turn,collapse=fold_status(base,result,faces)
   if not len(turn) and not len(collapse):break
   factor*=.8
  if len(turn) or len(collapse):raise ValueError('Cannot produce a non-flipped guide')
  delta*=factor;new_positions[name]=delta.copy();old_geo=geometry_normals(base,faces);new_geo=geometry_normals(result,faces);old_render=unit(np.einsum('nij,nj->ni',B,base_normals));wanted_world=unit(rotate_between(old_geo,new_geo,old_render));wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted_world));normal_delta=wanted_rest-base_normals;moved=np.linalg.norm(delta,axis=1)>1e-9;affected=np.zeros(N,bool);affected[np.unique(faces[np.any(moved[faces],axis=1)])]=True;normal_delta[~affected]=0
  primitive['targets'][index]['POSITION']=append(d,binary,primitive['attributes']['POSITION'],delta.astype('<f4'));primitive['targets'][index]['NORMAL']=append(d,binary,primitive['attributes']['NORMAL'],normal_delta.astype('<f4'));gap=0.
  for group in np.flatnonzero(count>1):
   vv=np.flatnonzero(groups==group);gap=max(gap,float(np.linalg.norm(result[vv]-result[vv[0]],axis=1).max()))
  reports.append(dict(target=name,phase=phase,native_file=shot['file'],native_png_sha256=sha(args.manifest.parent/shot['file']),sides=sides,orientation_line_search_factor=factor,max_native_world_shift_m=float(np.linalg.norm(result-base,axis=1).max()),physical_duplicate_gap_m=gap,new_over90_faces=len(turn),new_under15percent_area_faces=len(collapse),moved_vertices=int(moved.sum()),normal_affected_vertices=int(affected.sum())))
 # Every other action has zero selected weight functions: positions and normal
 # functions are exactly preserved without retiming or modifying its curves.
 protected=[]
 for animation in d['animations']:
  if animation['name']=='stretch':continue
  for c in animation['channels']:
   if c['target']!={'node':s['ni'],'path':'weights'}:continue
   vals=read(d,raw,animation['samplers'][c['sampler']]['output']).reshape(-1,len(names));assert not np.any(vals[:,chosen])
  protected.append(animation['name'])
 expected=copy.deepcopy(original)
 for index in chosen:expected['meshes'][s['node']['mesh']]['primitives'][0]['targets'][index]=primitive['targets'][index]
 for key in ['accessors','bufferViews']:expected[key]=d[key]
 assert d==expected and bytes(binary[:len(raw)])==raw
 args.output.parent.mkdir(parents=True,exist_ok=True);save(d,binary,args.output)
 report=dict(stage='tanaka-stretch-local-cap-guide',diagnostic_candidate_native_acceptance='pending',input=str(args.input),input_sha256=sha(args.input),native_nofit_source_sha256=sha(args.native_source),native_manifest_sha256=sha(args.manifest),output=str(args.output),output_sha256=sha(args.output),tool_sha256=sha(__file__),method=__doc__,drop_m=args.drop,geodesic_feather_m=args.feather,taubin_displacement_passes=2,taubin_coefficients=[.35,-.36],physical_position_epsilon_m=1e-6,physical_JW_epsilon=.001,targets=reports,protected_actions_with_exact_geometry_normal_function=protected,all_animation_and_base_skin_rest_uv_other_target_payload_exact=True,source_original_binary_prefix_exact=True)
 args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--native-source',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--drop',type=float,default=.012);p.add_argument('--feather',type=float,default=.04);args=p.parse_args();build(args)
if __name__=='__main__':main()
