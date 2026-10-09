"""A small closed-mouth smile trial; preserve the approved base face and UVs.

Authored landmarks come from front orthographic screenshots. Never infer a
mouth solely from the character's height. This is a candidate until reviewed.
"""
from pathlib import Path
import argparse,json,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from repair_head_neck import read,append,save
from retime_glb import load,durations
from motion_math import world_matrices
from face_wave_palm import smooth

LANDMARKS={'ren':{'centre_x':.0043,'mouth_y':1.555,'half_width':.019},'sora':{'centre_x':.0051,'mouth_y':1.4014,'half_width':.024}}

def trial(source,target,who,lift=.0015):
    d,blob=load(source);b=bytearray(blob);world,_=world_matrices(d,b);lm=LANDMARKS[who];nodes=[];largest=0.;count=0
    for ni,node in enumerate(d['nodes']):
        if 'mesh' not in node or 'skin' not in node:continue
        mesh=d['meshes'][node['mesh']]
        if mesh.get('name')!='model':continue
        old_count=len(mesh['primitives'][0].get('targets',[]));nodes.append((ni,old_count))
        for p in mesh['primitives']:
            attrs=p['attributes'];local=read(d,b,attrs['POSITION']);points=(np.c_[local,np.ones(len(local))]@world[ni].T)[:,:3]
            amount=np.zeros(len(points))
            for side in [-1,1]:
                dx=(points[:,0]-(lm['centre_x']+side*lm['half_width']))/.014
                dy=(points[:,1]-lm['mouth_y'])/.013
                amount+=np.exp(-.5*(dx*dx+dy*dy))
            amount*=smooth(.025,.055,points[:,2]);amount=np.minimum(amount,1)
            amount[amount<.003]=0
            delta_world=np.zeros_like(points);delta_world[:,1]=amount*lift
            delta=delta_world@np.linalg.inv(world[ni][:3,:3]).T
            p.setdefault('targets',[]).append({'POSITION':append(d,b,attrs['POSITION'],delta)})
            largest=max(largest,float(np.linalg.norm(delta_world,axis=1).max()));count+=int(np.sum(amount>0))
        mesh.setdefault('extras',{}).setdefault('targetNames',[]).append('GreetingSmile')
        mesh['weights']=mesh.get('weights',[0.]*old_count)+[0.]
        if 'weights' in node:node['weights'].append(0.)
    assert nodes
    for animation in d['animations']:
        end=max(float(read(d,b,s['input']).max()) for s in animation['samplers'])
        for ni,old_count in nodes:
            channel=next((c for c in animation['channels'] if c['target']=={'node':ni,'path':'weights'}),None)
            if channel:
                sampler=animation['samplers'][channel['sampler']];assert sampler.get('interpolation','LINEAR')!='CUBICSPLINE'
                times=read(d,b,sampler['input']).ravel();original=read(d,b,sampler['output']).reshape(len(times),old_count)
                values=np.c_[original,np.zeros(len(times))]
                if animation['name']=='wave':values[:,-1]=smooth(0,.22,times/end)*(1-smooth(.78,1,times/end))
                if times[0]>0:
                    times=np.r_[0.,times];values=np.vstack([np.r_[original[0],0.],values]);sampler['input']=append(d,b,sampler['input'],times[:,None])
                sampler['output']=append(d,b,sampler['output'],values.reshape(-1,1))
            else:
                existing=max((s for s in animation['samplers'] if float(read(d,b,s['input']).max())==end),key=lambda s:len(read(d,b,s['input'])))
                times=read(d,b,existing['input']).ravel();value=np.zeros(len(times))
                if animation['name']=='wave':value=smooth(0,.22,times/end)*(1-smooth(.78,1,times/end))
                time_accessor=existing['input']
                if times[0]>0:times=np.r_[0.,times];value=np.r_[0.,value];time_accessor=append(d,b,time_accessor,times[:,None])
                # Reuse a scalar template; append recomputes count and bounds.
                output=append(d,b,existing['input'],value[:,None])
                animation['samplers'].append({'input':time_accessor,'output':output,'interpolation':'LINEAR'})
                animation['channels'].append({'sampler':len(animation['samplers'])-1,'target':{'node':ni,'path':'weights'}})
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig');rig.setdefault('extras',{})['greeting_expression']={'mode':'closed-mouth smile trial','target':'GreetingSmile','max_corner_lift_mm':largest*1000,'eyes_changed':False}
    save(d,b,target);assert durations(source)==durations(target)
    report={'character':who,'source':str(source),'target':str(target),'landmarks':lm,'max_corner_lift_mm':largest*1000,'affected_vertices':count,'candidate':True};target.with_suffix('.smile.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--character',choices=list(LANDMARKS),required=True);p.add_argument('--lift-mm',type=float,default=1.5);a=p.parse_args();trial(a.source,a.target,a.character,a.lift_mm/1000)
