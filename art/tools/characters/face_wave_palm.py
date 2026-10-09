"""Turn the waving palm to the recipient with forearm pronation and mild wrist roll.

Only wave rotation channels for RightForeArm / RightHand are changed. All other
clips, mesh/UV/image bytes, bone rests and clip timings remain intact.
"""
from pathlib import Path
import argparse,json,sys
import numpy as np
from scipy.spatial.transform import Rotation
sys.path.insert(0,str(Path(__file__).resolve().parent))
from repair_head_neck import read,append,save
from retime_glb import load,durations
from motion_math import world_matrices,palm_normal,sample_channel

def smooth(a,b,x):
    u=np.clip((x-a)/(b-a),0,1);return u*u*(3-2*u)

def angle_about(normal,target,axis):
    x=normal-axis*np.dot(normal,axis);y=target-axis*np.dot(target,axis)
    x/=np.linalg.norm(x);y/=np.linalg.norm(y)
    return float(np.arctan2(np.dot(axis,np.cross(x,y)),np.dot(x,y)))

def rotate_local(q,parent_world,axis_world,angle):
    parent=Rotation.from_matrix(parent_world[:3,:3])
    world_delta=Rotation.from_rotvec(axis_world*angle)
    return (parent.inv()*world_delta*parent*Rotation.from_quat(q)).as_quat()

def correct(source,target):
    d,blob=load(source);b=bytearray(blob);rest,parents=world_matrices(d,b)
    wave=next(a for a in d['animations'] if a['name']=='wave')
    names={n.get('name'):i for i,n in enumerate(d['nodes'])};fore=names['mixamorig:RightForeArm'];hand=names['mixamorig:RightHand']
    channels={c['target']['node']:c for c in wave['channels'] if c['target']['path']=='rotation'}
    outputs={};report=[]
    length=max(float(read(d,b,s['input']).max()) for s in wave['samplers'])
    # Constant wrist channels can have only two samples. Use the union grid.
    old_input=wave['samplers'][channels[fore]['sampler']]['input']
    times=np.unique(np.r_[0.,read(d,b,old_input).ravel(),read(d,b,wave['samplers'][channels[hand]['sampler']]['input']).ravel()])
    for time in times:
        phase=float(time/length);blend=float(smooth(0,.20,phase)*(1-smooth(.78,1,phase)))
        posed,_=world_matrices(d,b,wave,float(time));normal=palm_normal(d,rest,posed)
        axis=posed[hand][:3,3]-posed[fore][:3,3];axis/=np.linalg.norm(axis)
        roll=angle_about(normal,np.array([0.,0.,1.]),axis)
        fore_q=sample_channel(d,b,wave,channels[fore],float(time))
        fore_q=rotate_local(fore_q,posed[parents[fore]],axis,roll*.8*blend)
        posed,_=world_matrices(d,b,wave,float(time),{fore:fore_q})
        normal=palm_normal(d,rest,posed)
        hand_axis=posed[hand][:3,1];hand_axis/=np.linalg.norm(hand_axis)
        wrist_roll=angle_about(normal,np.array([0.,0.,1.]),hand_axis)
        hand_q=sample_channel(d,b,wave,channels[hand],float(time))
        hand_q=rotate_local(hand_q,posed[parents[hand]],hand_axis,wrist_roll*blend)
        outputs.setdefault(fore,[]).append(fore_q);outputs.setdefault(hand,[]).append(hand_q)
        report.append({'phase':phase,'blend':blend,'forearm_roll_deg':float(np.degrees(roll*.8*blend)),'wrist_roll_deg':float(np.degrees(wrist_roll*blend))})
    new_input=append(d,b,old_input,times[:,None])
    for node,values in outputs.items():
        values=np.array(values)
        for k in range(1,len(values)):
            if np.dot(values[k-1],values[k])<0:values[k]*=-1
        sampler=wave['samplers'][channels[node]['sampler']];sampler['output']=append(d,b,sampler['output'],values);sampler['input']=new_input
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig')
    rig.setdefault('extras',{})['greeting_palm']={'side':'Right','faces':'recipient / character +Z','forearm_share':.8,'review':'wave-smile-20261005'}
    save(d,b,target);assert durations(source)==durations(target)
    result={'source':str(source),'target':str(target),'changed_nodes':['mixamorig:RightForeArm','mixamorig:RightHand'],'changed_clip':'wave','max_forearm_roll_deg':max(abs(x['forearm_roll_deg']) for x in report),'max_wrist_roll_deg':max(abs(x['wrist_roll_deg']) for x in report),'samples':report}
    target.with_suffix('.wave-palm.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='samples'}),flush=True)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',required=True,type=Path);p.add_argument('--target',required=True,type=Path);a=p.parse_args();correct(a.source,a.target)
