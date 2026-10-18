"""Bake a fitted sleeve field only into explicitly reviewed problem actions.

The source skeleton and every skin weight stay exact. Haru/Mio wave and ordinary
locomotion remain byte-equivalent in evaluated geometry because their corrective
weights are zero. Real posed cloth movement is capped before inverse skinning.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.spatial import cKDTree
from scipy import sparse
from glb_io import load
from prepare_local_garments import read
from repair_head_neck import append, save
from audit_sleeve_weights import assets,evaluate
from motion_math import world_matrices
PHASES=[.125,.375,.625,.875]


def patch_weights(d,b,animation,ni,count,times):
    result=np.zeros((len(times),count))
    if not count:return result
    for c in animation['channels']:
        if c['target']!={'node':ni,'path':'weights'}:continue
        s=animation['samplers'][c['sampler']];ts=read(d,b,s['input']).ravel();vs=read(d,b,s['output']).reshape(-1,count)
        assert s.get('interpolation','LINEAR')=='LINEAR'
        result=np.array([np.interp(times,ts,vs[:,i]) for i in range(count)]).T
    return result


def prepare(args):
    old=assets(args.input,args.character);fitted=assets(args.fitted_input,args.character);d=old[0];b=bytearray(old[1]);clips=args.clips.split(',');report={'character':args.character,'input':str(args.input),'fitted_input':str(args.fitted_input),'clips':clips,'sample_phases':PHASES,'maximum_authored_surface_shift_m':args.maximum_surface_shift,'source_weights_preserved':True,'source_geometry_uv_texture_skeleton_preserved':True,'targets':[]}
    changed_nodes={}
    for key,part in old[2].items():
        desired=fitted[2][key]
        if np.array_equal(part['joints'],desired['joints']) and np.array_equal(part['weights'],desired['weights']):continue
        # A fitted weight selection is only an initial guide. Feather its posed
        # displacement through real topology and UV seam copies before baking.
        edges=part['edges'];pos=part['pos'];colour=__import__('prepare_local_garments').colours(old[0],old[1],part['p']);skin_colour=(colour[:,0]>colour[:,1]*1.10)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.30);cloth=~skin_colour&(pos[:,1]>.52*old[3])&(abs(pos[:,0])>.04*old[3])
        duplicates=cKDTree(pos).query_pairs(1e-6,output_type='ndarray')
        weld_edges=np.r_[edges,duplicates]
        adjacency=sparse.coo_matrix((np.ones(2*len(weld_edges)),(np.r_[weld_edges[:,0],weld_edges[:,1]],np.r_[weld_edges[:,1],weld_edges[:,0]])),shape=(len(pos),len(pos))).tocsr();degree=np.asarray(adjacency.sum(1)).ravel();average=sparse.diags(1/np.maximum(degree,1))@adjacency
        ni=part['ni'];node=d['nodes'][ni];mesh=d['meshes'][node['mesh']];primitive=mesh['primitives'][key[1]];count=len(part['names']);target_names=mesh.setdefault('extras',{}).setdefault('targetNames',[]);new_names=[]
        for clip in clips:
            animation=next(a for a in d['animations'] if a['name']==clip);duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers'])
            for phase in PHASES:
                current=evaluate(old[0],old[1],part,clip,phase);wanted=evaluate(fitted[0],fitted[1],desired,clip,phase);shift=wanted-current
                for iteration in range(20):
                    shift=shift*.35+(average@shift)*.65
                    shift[~cloth]=0
                length=np.linalg.norm(shift,axis=1);factor=np.minimum(1,args.maximum_surface_shift/np.maximum(length,1e-9));shift*=factor[:,None]
                corrected=current+shift
                rest_lengths=np.linalg.norm(pos[edges[:,1]]-pos[edges[:,0]],axis=1);old_lengths=np.linalg.norm(current[edges[:,1]]-current[edges[:,0]],axis=1);limits=np.maximum(rest_lengths*1.25,old_lengths*1.01)
                valid=(rest_lengths>.00001)&(cloth[edges].any(1))
                a=edges[valid,0];c=edges[valid,1];edge_limits=limits[valid];free_a=cloth[a].astype(float);free_c=cloth[c].astype(float);freedom=np.maximum(free_a+free_c,1)
                for iteration in range(200):
                    vector=corrected[c]-corrected[a];length=np.linalg.norm(vector,axis=1);excess=np.maximum(0,length-edge_limits);move=vector*(excess/np.maximum(length,1e-9)/freedom)[:,None];acc=np.zeros_like(corrected);counts=np.zeros(len(corrected));np.add.at(acc,a,move*free_a[:,None]);np.add.at(acc,c,-move*free_c[:,None]);np.add.at(counts,a,(excess>0)*free_a);np.add.at(counts,c,(excess>0)*free_c);corrected+=acc/np.maximum(counts[:,None],1)*.85
                    shift=corrected-current;length=np.linalg.norm(shift,axis=1);shift*=np.minimum(1,args.maximum_surface_shift/np.maximum(length,1e-9))[:,None];shift[~cloth]=0;corrected=current+shift
                worlds,_=world_matrices(d,b,animation,duration*phase);matrices=np.array([worlds[j]@bind for j,bind in zip(part['skin']['joints'],part['binds'])]);linear=np.zeros((len(current),3,3))
                for slot in range(part['joints'].shape[1]):linear+=matrices[part['joints'][:,slot],:3,:3]*part['weights'][:,slot,None,None]
                active=np.linalg.norm(shift,axis=1)>1e-8;delta=np.zeros_like(current);delta[active]=np.einsum('nij,nj->ni',np.linalg.pinv(linear[active]),shift[active]);name=f'SleeveFit_{clip}_{round(phase*1000):03d}';new_names.append(name);target={'POSITION':append(d,b,primitive['attributes']['POSITION'],delta.astype(np.float32))}
                if 'NORMAL' in primitive['attributes']:target['NORMAL']=append(d,b,primitive['attributes']['NORMAL'],np.zeros_like(delta,dtype=np.float32))
                primitive.setdefault('targets',[]).append(target);report['targets'].append({'mesh':key[0],'target':name,'moved_vertices':int(active.sum()),'max_world_shift_m':float(np.linalg.norm(shift,axis=1).max()),'max_rest_delta_m':float(np.linalg.norm(delta,axis=1).max())})
        target_names.extend(new_names);mesh['weights']=mesh.get('weights',[0]*count)+[0]*len(new_names)
        if 'weights' in node:node['weights'] += [0]*len(new_names)
        changed_nodes[ni]=(count,new_names)
    # glTF weight animation is a scalar stream containing every target, so rebuild
    # the stream once per node/clip. Existing source values use their original times.
    for animation in d['animations']:
        original_channels=list(animation['channels']);duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);phase_grid=np.array([0]+PHASES+[1.]);times=np.unique(np.r_[np.linspace(0,duration,max(2,round(duration*60)+1)),phase_grid*duration]).astype(np.float32)
        for ni,(count,new_names) in changed_nodes.items():
            previous=patch_weights(old[0],old[1],animation,ni,count,times);values=np.c_[previous,np.zeros((len(times),len(new_names)))]
            if animation['name'] in clips:
                current_clip=clips.index(animation['name'])
                for anchor,phase in enumerate(PHASES):
                    peak=anchor+1;shape=np.zeros(6);shape[peak]=1;values[:,count+current_clip*len(PHASES)+anchor]=np.interp(times/duration,phase_grid,shape)
            # append() needs source accessor templates, independent of channel kind.
            template=next(s['input'] for s in animation['samplers']);time_id=append(d,b,template,times[:,None]);output_id=append(d,b,template,values.reshape(-1,1));new_sampler=len(animation['samplers']);animation['samplers'].append({'input':time_id,'output':output_id,'interpolation':'LINEAR'});animation['channels']=[c for c in animation['channels'] if c['target']!={'node':ni,'path':'weights'}];animation['channels'].append({'sampler':new_sampler,'target':{'node':ni,'path':'weights'}})
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig');rig.setdefault('extras',{})['sleeve_action_correctives']={'version':1,'clips':clips,'cap_m':args.maximum_surface_shift,'source_weights_untouched':True}
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();report['preserved_other_clips']=[a['name'] for a in d['animations'] if a['name'] not in clips];args.report.write_text(json.dumps(report,indent=2));print(args.report)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--fitted-input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--character',required=True);p.add_argument('--clips',default='stretch');p.add_argument('--maximum-surface-shift',type=float,default=.05);p.add_argument('--report',type=Path,required=True);prepare(p.parse_args())
