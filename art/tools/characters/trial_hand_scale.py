"""Scale hands and their finger hierarchies around wrists in a skinning candidate.

The approved mesh and UVs remain intact. Existing inverse binds intentionally
remain unchanged: the rest/animated joint scale makes the visible hand smaller,
including articulated fingers, with the existing wrist weights blending to the arm.
"""
from pathlib import Path
import argparse,json,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from repair_head_neck import read,append,save
from retime_glb import load,durations

def trial(source,target,scale=.9):
    d,blob=load(source);b=bytearray(blob);hands=[i for i,n in enumerate(d['nodes']) if n.get('name') in ['mixamorig:LeftHand','mixamorig:RightHand']];assert len(hands)==2
    for i in hands:d['nodes'][i]['scale']=(np.array(d['nodes'][i].get('scale',[1,1,1]))*scale).tolist()
    for animation in d['animations']:
        for channel in animation['channels']:
            if channel['target']['node'] in hands and channel['target']['path']=='scale':
                sampler=animation['samplers'][channel['sampler']];sampler['output']=append(d,b,sampler['output'],read(d,b,sampler['output'])*scale)
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig');rig.setdefault('extras',{})['hand_size_review']={'scale':scale,'wrist_preserved':True,'fingers_scale_with_palm':True,'review':'wave-smile-20261005'}
    save(d,b,target);assert durations(source)==durations(target);print(json.dumps({'source':str(source),'target':str(target),'hand_scale':scale}),flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--scale',type=float,default=.9);a=p.parse_args();trial(a.source,a.target,a.scale)
