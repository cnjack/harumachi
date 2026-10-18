"""Bake a local upper-arm skin guide into existing stretch P/N columns only.

The source skin weights, bone tracks, base surface, UVs and all other actions
stay exact. A physical cloth vertex shares its guide weight and peak correction.
This is an offline candidate generator; native appearance remains a separate gate.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from scipy.sparse import coo_matrix,diags
from glb_io import load
from prepare_local_garments import read,smooth
from sew_arm_seams import dense_part
from synchronize_sleeve_corrective_seams import posed_part,physical_groups,garment_vertices
from corrective_normals import unit,geometry_normals,rotate_between
from motion_math import world_matrices
from repair_head_neck import append,save


def prepare(args):
 d,raw=load(args.input);b=bytearray(raw);sha=hashlib.sha256(args.input.read_bytes()).hexdigest();models=json.loads((args.manifest.parent.parent/'model-hashes.json').read_text());assert models[f'CH_{args.character}.glb']==sha
 parts={n['name']:dense_part(d,b,n)for n in d['nodes']if n.get('name')in ['CharacterBody','Sleeve_Left','Sleeve_Right']};order,offsets,groups,pairs=physical_groups(parts,args.character);N=int(offsets[-1]);labels=np.arange(N)
 protected=None
 if args.protected_reference is not None:
  pd,pb=load(args.protected_reference);pn=next(n for n in pd['nodes']if n.get('name')=='CharacterBody');protected=(pd,pb,dense_part(pd,pb,pn))
 for group in groups:labels[group]=group[0]
 _,labels=np.unique(labels,return_inverse=True);G=int(labels.max())+1;sizes=np.bincount(labels,minlength=G);rest,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};skin=d['skins'][0];bone_names=[d['nodes'][i].get('name','')for i in skin['joints']];binds=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
 P=np.concatenate([parts[name]['pos']for name in order]);H=float(P[:,1].max());allowed=np.concatenate([garment_vertices(parts[name],args.character)for name in order]);allowed&=P[:,1]>.52*H
 sides=args.sides.split(',');gamma=np.zeros(N);guide=np.zeros((N,len(bone_names)));side_bones={}
 for side in sides:
  S=rest[ids['mixamorig:'+side+'Arm']][:3,3];E=rest[ids['mixamorig:'+side+'ForeArm']][:3,3];W=rest[ids['mixamorig:'+side+'Hand']][:3,3];axis=E-S;length=np.linalg.norm(axis);t=(P-S)@(axis/length);radius=np.linalg.norm(P-S-t[:,None]*(axis/length),axis=1)
  current=np.concatenate([parts[name]['dense']for name in order]);own=[i for i,n in enumerate(bone_names)if n in ['mixamorig:'+side+'Arm','mixamorig:'+side+'ForeArm','TWIST_'+side]or n.startswith('Cloth_'+side+'_')];share=current[:,own].sum(1)
  side_bones[side]=own
  lateral=(-1 if side=='Right' else 1)*(P[:,0]-S[0])
  own_envelope=smooth(.10,.65,share) if args.guide_policy=='skin-share' else smooth(-.012,.025,lateral)
  g=args.strength*own_envelope*smooth(.005,.045,t)*(1-smooth(length-.005,length+.045,t))*(1-smooth(.09*H,.12*H,radius))*allowed
  if side=='Right':g[P[:,0]>=0]=0
  else:g[P[:,0]<=0]=0
  fore=smooth(length-.025,length+.025,t);row=np.zeros_like(guide);row[:,bone_names.index('mixamorig:'+side+'Arm')]=1-fore;row[:,bone_names.index('mixamorig:'+side+'ForeArm')]=fore
  take=(P[:,0]<0) if side=='Right' else (P[:,0]>0)
  gamma=np.maximum(gamma,g);guide[take]=row[take]
 # Both the geometrical ROI and its anatomical guide are shared across physical
 # UV copies and the original main/sleeve extraction seam.
 gfield=np.zeros(G);np.add.at(gfield,labels,gamma);gfield/=sizes
 guidefield=np.zeros((G,len(bone_names)));np.add.at(guidefield,labels,guide);guidefield/=sizes[:,None]
 edges=np.concatenate([parts[name]['edges']+offsets[i]for i,name in enumerate(order)]);edges=edges[allowed[edges].all(1)];pe=np.unique(np.sort(labels[edges],axis=1),axis=0);pe=pe[pe[:,0]!=pe[:,1]];graph=coo_matrix((np.ones(2*len(pe)),(np.r_[pe[:,0],pe[:,1]],np.r_[pe[:,1],pe[:,0]])),shape=(G,G)).tocsr();degree=np.asarray(graph.sum(1)).ravel();mean=diags(1/np.maximum(degree,1))@graph
 group_allowed=np.ones(G,bool);np.logical_and.at(group_allowed,labels,allowed)
 if args.guide_policy in ['smoothed-skin','monotone-arm']:
  original=np.concatenate([parts[name]['dense']for name in order]);guidefield=np.zeros((G,len(bone_names)));np.add.at(guidefield,labels,original);guidefield/=sizes[:,None]
  original_field=guidefield.copy()
  for _ in range(args.weight_smoothing):
   next_weights=.5*guidefield+.5*(mean@guidefield);guidefield[group_allowed]=next_weights[group_allowed]
  if args.guide_policy=='monotone-arm':
   amended=original_field.copy();addition=np.zeros(G)
   for side,own in side_bones.items():
    old_share=original_field[:,own].sum(1);new_share=np.maximum(old_share,guidefield[:,own].sum(1));increase=new_share-old_share;active=(increase>1e-9)&(old_share>.10);increase[~active]=0;other=np.array([i for i in range(len(bone_names))if i not in own]);amended[np.ix_(active,own)]=original_field[np.ix_(active,own)]*(new_share[active]/np.maximum(old_share[active],1e-20))[:,None];amended[np.ix_(active,other)]=original_field[np.ix_(active,other)]*((1-new_share[active])/np.maximum(1-old_share[active],1e-20))[:,None];addition=np.maximum(addition,increase)
   guidefield=amended;gfield*=smooth(.002,.05,addition)
 for _ in range(args.guide_smoothing):
  gfield=.5*gfield+.5*(mean@gfield);gfield[~group_allowed]=0
 gamma=gfield[labels];guide=guidefield[labels];guide/=np.maximum(guide.sum(1,keepdims=True),1e-20)
 rows=[r for r in json.loads(args.manifest.read_text())['shots']if r['id']==args.character and r['clip']=='stretch'and r['view']=='front'];names=[n for n in parts['CharacterBody']['names']if n.startswith('SleeveFit_stretch_')];samples=[];common_scale=np.ones(G)
 for target in names:
  phase=int(target.rsplit('_',1)[1])/1000;row=next(r for r in rows if abs(r['phase']-phase)<1e-6);world,_=world_matrices(d,b)
  for bone in row['bones']:
   at=ids[bone['name'].replace('mixamorig_','mixamorig:')];world[at]=np.eye(4);world[at][:3,:3]=np.asarray(bone['basis']).T;world[at][:3,3]=np.asarray(bone['position'])-row['position']
  matrices=np.asarray([world[j]@ib for j,ib in zip(skin['joints'],binds)]);perpart=[]
  for pi,name in enumerate(order):
   part=parts[name];lo,hi=offsets[pi:pi+2];before,B,normal=posed_part(d,b,part,row);base=part['pos'].copy()
   for n,value in row['blend_shape_values'][name].items():
    if value and n not in names:base+=value*part['shapes'][n]
   guided=np.einsum('vj,jab,vb->va',guide[lo:hi],matrices[:,:3,:3],base)+guide[lo:hi]@matrices[:,:3,3];shift=(guided-before)*gamma[lo:hi,None];perpart.append((name,before,B,normal,shift,guided))
   ratio=np.minimum(1,args.max_world_shift/np.maximum(np.linalg.norm(shift,axis=1),1e-20));np.minimum.at(common_scale,labels[lo:hi],ratio)
  samples.append((target,row,perpart))
 if args.fit_manifest is not None:
  fit_rows=[r for r in json.loads(args.fit_manifest.read_text())['shots']if r['id']==args.character and r['clip']=='stretch']+rows
  design=np.asarray([[r['blend_shape_values']['CharacterBody'].get(n,0)for n in names]for r in fit_rows]);gram=design.T@design
  rhs={name:np.zeros((len(names),len(part['pos']),3))for name,part in parts.items()}
  for ri,row in enumerate(fit_rows):
   if not np.any(design[ri]):continue
   world,_=world_matrices(d,b)
   for bone in row['bones']:
    at=ids[bone['name'].replace('mixamorig_','mixamorig:')];world[at]=np.eye(4);world[at][:3,:3]=np.asarray(bone['basis']).T;world[at][:3,3]=np.asarray(bone['position'])-row['position']
   matrices=np.asarray([world[j]@ib for j,ib in zip(skin['joints'],binds)])
   for pi,name in enumerate(order):
    part=parts[name];lo,hi=offsets[pi:pi+2];active=np.flatnonzero(gamma[lo:hi]>1e-8)
    if not len(active):continue
    base=part['pos'][active].copy();shaped=base.copy()
    for n,value in row['blend_shape_values'][name].items():
     if value:
      shaped+=value*part['shapes'][n][active]
      if n not in names:base+=value*part['shapes'][n][active]
    transform=np.einsum('vj,jab->vab',part['dense'][active],matrices);B=transform[:,:3,:3];before=np.einsum('vab,vb->va',B,shaped)+transform[:,:3,3];g=guide[lo:hi][active];guided=np.einsum('vj,jab,vb->va',g,matrices[:,:3,:3],base)+g@matrices[:,:3,3];shift=(guided-before)*gamma[lo:hi][active,None];delta=np.einsum('vab,vb->va',np.linalg.pinv(B),shift)
    rhs[name][:,active]+=design[ri,:,None,None]*delta[None]
  inverse=np.linalg.pinv(gram);fitted={name:np.einsum('kl,lvj->kvj',inverse,value)for name,value in rhs.items()}
  for ti,(_,row,perpart)in enumerate(samples):
   for pi,(name,before,B,normal,shift,guided)in enumerate(perpart):
    perpart[pi]=(name,before,B,normal,np.einsum('vab,vb->va',B,fitted[name][ti]),guided)
  # The shared physical cap was derived for the direct peak controls. Fitted
  # controls are reported without that unrelated, pointwise truncation.
  common_scale[:]=1
 report={'input':str(args.input),'input_sha256':sha,'manifest':str(args.manifest),'manifest_sha256':hashlib.sha256(args.manifest.read_bytes()).hexdigest(),'sides':sides,'strength':args.strength,'guide_policy':args.guide_policy,'guide_smoothing_iterations':args.guide_smoothing,'weight_smoothing_iterations':args.weight_smoothing,'max_world_shift_m':args.max_world_shift,'fit_manifest':str(args.fit_manifest)if args.fit_manifest is not None else None,'fit_manifest_sha256':hashlib.sha256(args.fit_manifest.read_bytes()).hexdigest()if args.fit_manifest is not None else None,'policy':'continuous original-arm capsule/skin-share ROI; guide toward Arm/ForeArm blend or physically smoothed original weights; shared physical ROI and peak correction; source skin never changes','nonzero_guide_vertices':int((gamma>1e-7).sum()),'samples':[]}
 for target,row,perpart in samples:
  phase=row['phase'];result={'phase':phase,'parts':[]}
  for pi,(name,before,B,normal,shift,guided)in enumerate(perpart):
   part=parts[name];lo,hi=offsets[pi:pi+2];shift*=common_scale[labels[lo:hi],None];delta=np.einsum('nij,nj->ni',np.linalg.pinv(B),shift);new=part['shapes'][target]+delta;after=before+shift;active=np.linalg.norm(shift,axis=1)>1e-9;faces=read(d,b,part['p']['indices']).reshape(-1,3);af=active[faces].any(1);affected=np.zeros(len(active),bool);affected[np.unique(faces[af])]=True;affected&=garment_vertices(part,args.character);baseN=unit(read(d,b,part['a']['NORMAL']));restGeo=geometry_normals(part['pos'],faces)
   # The old no-fit posed face can already be folded. Use transported REST
   # geometry and authored normal offset, rather than preserving that inversion.
   reference=unit(np.einsum('nij,nj->ni',B,restGeo));render=unit(np.einsum('nij,nj->ni',B,baseN));wanted=unit(rotate_between(reference,geometry_normals(after,faces),render));wantedRest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted));ti=part['names'].index(target);oldDN=unit(baseN+read(d,b,part['p']['targets'][ti]['NORMAL']))-baseN;offset=baseN-(normal-oldDN);along=(offset*wantedRest).sum(1);disc=along**2+1-(offset**2).sum(1)
   if np.any(disc[affected]<-1e-8):raise ValueError('Unreachable unit normal target')
   dn=unit(offset+(-along+np.sqrt(np.maximum(disc,0)))[:,None]*wantedRest)-baseN;dn[~affected]=read(d,b,part['p']['targets'][ti]['NORMAL'])[~affected]
   if protected is not None and name=='CharacterBody':
    pd,pb,pp=protected;mask=~garment_vertices(part,args.character);pti=pp['names'].index(target);new[mask]=pp['shapes'][target][mask];dn[mask]=read(pd,pb,pp['p']['targets'][pti]['NORMAL'])[mask]
   part['p']['targets'][ti]={'POSITION':append(d,b,part['a']['POSITION'],new.astype(np.float32)),'NORMAL':append(d,b,part['a']['NORMAL'],dn.astype(np.float32))};result['parts'].append({'mesh':name,'moved_vertices':int(active.sum()),'world_shift_max_m':float(np.linalg.norm(shift,axis=1).max())})
   if args.trace_dir is not None:
    args.trace_dir.mkdir(parents=True,exist_ok=True);np.savez_compressed(args.trace_dir/f'{name}-{target}.npz',rest=part['pos'],before=before,after=after,guided=guided,B=B,gamma=gamma[lo:hi],scale=common_scale[labels[lo:hi]],guide=guide[lo:hi],bone_names=np.asarray(bone_names),faces=faces)
  report['samples'].append(result)
 args.output.parent.mkdir(parents=True,exist_ok=True);save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();report['tool_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2)+'\n');print(args.output,report['output_sha256'])

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--trace-dir',type=Path);p.add_argument('--fit-manifest',type=Path);p.add_argument('--protected-reference',type=Path);p.add_argument('--character',default='mio');p.add_argument('--sides',default='Right');p.add_argument('--strength',type=float,default=.6);p.add_argument('--guide-policy',choices=['skin-share','spatial','smoothed-skin','monotone-arm'],default='skin-share');p.add_argument('--guide-smoothing',type=int,default=8);p.add_argument('--weight-smoothing',type=int,default=40);p.add_argument('--max-world-shift',type=float,default=.06);prepare(p.parse_args())
