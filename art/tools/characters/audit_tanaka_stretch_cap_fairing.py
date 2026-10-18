#!/usr/bin/env python3
"""Compare Tanaka stretch correctives against the same uncorrected LBS surface.

All149 samples:129 authored inclusive phases plus20 actual no-fit final poses.
The unchanged run/other action functions are independently verified from exact
source payload/curves and inactive selected weight columns. Candidate rendering
and human acceptance remain separate. No Godot process is started here.
"""
import os
for key in ['OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS']:os.environ[key]='1'
import argparse,copy,json,hashlib
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from prepare_tanaka_stretch_cap_fairing import body_data,native_matrices,skin_matrices,fold_status,sha,physical_mesh
from motion_math import world_matrices
from repair_head_neck import read
from corrective_normals import unit,geometry_normals,rotate_between


def values(d,b,a,node,count,t):
 out=np.zeros(count)
 for c in a['channels']:
  if c['target']!={'node':node,'path':'weights'}:continue
  sampler=a['samplers'][c['sampler']];times=read(d,b,sampler['input']).ravel();vs=read(d,b,sampler['output']).reshape(-1,count);assert sampler.get('interpolation','LINEAR')=='LINEAR';out=np.array([np.interp(t,times,vs[:,i]) for i in range(count)])
 return out


def audit(args):
 source,d,b,mesh,pr=body_data(args.source);candidate,cd,cb,cm,cp=body_data(args.candidate);names=mesh['extras']['targetNames'];selected=[i for i,n in enumerate(names) if n.startswith('SleeveFit_stretch_')];assert len(selected)==4;faces=read(d,b,pr['indices']).reshape(-1,3);oldP=np.array([read(d,b,t['POSITION']) for t in pr['targets']]);newP=np.array([read(cd,cb,t['POSITION']) for t in cp['targets']]);baseN=unit(read(d,b,pr['attributes']['NORMAL']));newN=np.array([unit(baseN+read(cd,cb,t['NORMAL']))-baseN for t in cp['targets']]);N=len(source['positions']);dense=np.zeros((N,len(source['skin']['joints'])))
 for slot in range(source['joints'].shape[1]):np.add.at(dense,(np.arange(N),source['joints'][:,slot]),source['weights'][:,slot])
 pairs=cKDTree(source['positions']).query_pairs(1e-6,output_type='ndarray');pairs=pairs[np.max(abs(dense[pairs[:,0]]-dense[pairs[:,1]]),axis=1)<=.001];groups,count,edges=physical_mesh(source,faces);physicalfaces=groups[faces];erows=np.concatenate([np.c_[physicalfaces[:,0],physicalfaces[:,1],np.arange(len(faces))],np.c_[physicalfaces[:,1],physicalfaces[:,2],np.arange(len(faces))],np.c_[physicalfaces[:,2],physicalfaces[:,0],np.arange(len(faces))]]);erows[:,:2]=np.sort(erows[:,:2],axis=1);erows=erows[np.lexsort((erows[:,1],erows[:,0]))];same=np.all(erows[:-1,:2]==erows[1:,:2],axis=1);fa=erows[:-1][same,2];fb=erows[1:][same,2]
 # Every original byte remains, and JSON may only redirect4 selectedP/N streams.
 expected=copy.deepcopy(d)
 for i in selected:expected['meshes'][source['node']['mesh']]['primitives'][0]['targets'][i]=cp['targets'][i]
 for key in ['accessors','bufferViews','buffers']:expected[key]=cd[key]
 preserved=expected==cd and cb[:len(b)]==b
 a=next(a for a in d['animations'] if a['name']=='stretch');duration=max(float(read(d,b,x['input']).max()) for x in a['samplers']);samples=[]
 for phase in np.arange(129)/128:
  world,_=world_matrices(d,b,a,float(phase*duration));B,T=skin_matrices(source,world);samples.append(('authored',float(phase),values(d,b,a,source['ni'],len(names),phase*duration),B,T,None))
 for shot in json.loads(args.manifest.read_text())['shots']:
  if shot['id']!='tanaka' or shot['clip']!='stretch':continue
  _,(B,T)=native_matrices(d,b,source,shot);samples.append(('actual-native-nofit',shot['phase'],np.array([shot['blend_shape_values']['tanaka_static'][name] for name in names]),B,T,shot['file']))
 rows=[]
 for kind,phase,w,B,T,file in samples:
  v0=w.copy();v0[selected]=0;baseRest=source['positions']+np.einsum('k,knj->nj',v0,oldP);base=np.einsum('nij,nj->ni',B,baseRest)+T;old=base+np.einsum('nij,nj->ni',B,np.einsum('k,knj->nj',w-v0,oldP));new=base+np.einsum('nij,nj->ni',B,np.einsum('k,knj->nj',w-v0,newP));oldturn,oldcollapse=fold_status(base,old,faces);newturn,newcollapse=fold_status(base,new,faces);oldgap=np.linalg.norm(old[pairs[:,0]]-old[pairs[:,1]],axis=1).max();newgap=np.linalg.norm(new[pairs[:,0]]-new[pairs[:,1]],axis=1).max();change=np.linalg.norm(new-base,axis=1);affected=np.zeros(N,bool);affected[np.unique(faces[np.any((change>1e-9)[faces],axis=1)])]=True;geo0=geometry_normals(base,faces);geo1=geometry_normals(new,faces);actualNormal=unit(np.einsum('nij,nj->ni',B,unit(baseN+np.einsum('k,knj->nj',w,newN))));desired=unit(rotate_between(geo0,geo1,unit(np.einsum('nij,nj->ni',B,baseN))));error=np.degrees(np.arccos(np.clip(np.sum(actualNormal*desired,axis=1),-1,1)));tri0=base[faces];tri1=new[faces];n0=unit(np.cross(tri0[:,1]-tri0[:,0],tri0[:,2]-tri0[:,0]));n1=unit(np.cross(tri1[:,1]-tri1[:,0],tri1[:,2]-tri1[:,0]));ang0=np.degrees(np.arccos(np.clip(np.sum(n0[fa]*n0[fb],axis=1),-1,1)));ang1=np.degrees(np.arccos(np.clip(np.sum(n1[fa]*n1[fb],axis=1),-1,1)));newfold=(ang0<60)&(ang1>90)&(affected[faces[fa]].any(1)|affected[faces[fb]].any(1));rows.append(dict(kind=kind,phase=phase,native_file=file,source_bad_turn_faces=len(oldturn),source_bad_collapse_faces=len(oldcollapse),source_max_physical_duplicate_gap_m=float(oldgap),candidate_bad_turn_faces=len(newturn),candidate_bad_collapse_faces=len(newcollapse),candidate_max_physical_duplicate_gap_m=float(newgap),candidate_max_shift_vs_nofit_m=float(change.max()),normal_error_affected_p95_deg=float(np.percentile(error[affected],95)) if affected.any() else 0.,normal_error_affected_max_deg=float(error[affected].max()) if affected.any() else 0.,new_hinges_old_below60_to_over90=int(newfold.sum())))
 protected=[]
 for anim in d['animations']:
  if anim['name']=='stretch':continue
  for c in anim['channels']:
   if c['target']!={'node':source['ni'],'path':'weights'}:continue
   vs=read(d,b,anim['samplers'][c['sampler']]['output']).reshape(-1,len(names));assert not np.any(vs[:,selected])
  protected.append(anim['name'])
 summary=dict(samples=len(rows),authored=129,native=len(rows)-129,old_bad_samples=sum(r['source_bad_turn_faces']>0 or r['source_bad_collapse_faces']>0 or r['source_max_physical_duplicate_gap_m']>.0001 for r in rows),candidate_bad_samples=sum(r['candidate_bad_turn_faces']>0 or r['candidate_bad_collapse_faces']>0 or r['candidate_max_physical_duplicate_gap_m']>.0001 for r in rows),candidate_max_gap_m=max(r['candidate_max_physical_duplicate_gap_m'] for r in rows),candidate_max_shift_vs_nofit_m=max(r['candidate_max_shift_vs_nofit_m'] for r in rows),candidate_max_normal_error_p95_deg=max(r['normal_error_affected_p95_deg'] for r in rows),candidate_max_normal_error_deg=max(r['normal_error_affected_max_deg'] for r in rows),candidate_new_high_frequency_hinge_samples=sum(r['new_hinges_old_below60_to_over90']>0 for r in rows))
 report=dict(pass_offline=bool(preserved and summary['old_bad_samples']>0 and summary['candidate_bad_samples']==0),source_sha256=sha(args.source),candidate_sha256=sha(args.candidate),native_manifest_sha256=sha(args.manifest),tool_sha256=sha(__file__),scope=__doc__,reference_geometry='NoFit base LBS with four selected fields zeroed at exact actual/authored bones, not the old split Fit surface.',preserved_base_mesh_skin_rest_uv_images_all_animation_all_other_targets=preserved,protected_actions_with_exact_geometry_normal_function=protected,summary=summary,samples=rows,candidate_native_acceptance='pending')
 args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2));print(json.dumps(summary),flush=True);return report['pass_offline']


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args();raise SystemExit(0 if audit(args) else 1)
if __name__=='__main__':main()
