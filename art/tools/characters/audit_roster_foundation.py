"""Independent seven-person source audit: skin locality and raw animation geometry.

Does not execute the bake or game modifiers. Garment material is excluded from
anatomical leg checks and explicitly remains a separate high-flexion acceptance.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.spatial.transform import Rotation
from glb_io import load,durations
from motion_math import world_matrices
from repair_joint_fit import parts
from prepare_local_garments import colours
from rebuild_locomotion import shoe_sources, shoe_points

ACTORS=['sora','ren','haru','mio','aoi','tanaka','kazuko']

def audit(path,actor):
    d,b=load(path);rest,parents=world_matrices(d,b)
    ids={n.get('name'):i for i,n in enumerate(d['nodes'])}
    main=parts(d,b)[0];xyz=main['xyz'];rgb=colours(d,b,main['primitive']);dense=main['dense'];joints=main['joints']
    thigh=[]
    for side,sign in [('Left',1),('Right',-1)]:
        node=ids['mixamorig:'+side+'UpLeg'];hip=rest[node][:3,3];knee=rest[ids['mixamorig:'+side+'Leg']][:3,3];length=np.linalg.norm(hip-knee)
        mask=(xyz[:,1]>knee[1]+length*.30)&(xyz[:,1]<hip[1]-length*.40)&(xyz[:,0]*sign>.04)&(abs(xyz[:,0])<.24)
        family=[joints.index(ids['mixamorig:'+name]) for name in ['Hips',side+'UpLeg',side+'Leg']]
        mask &= dense[:,family].sum(1)>.99
        if actor=='mio':mask&=(rgb[:,0]>rgb[:,1]*1.10)&(rgb[:,1]>rgb[:,2]*1.02)
        if actor=='kazuko':mask&=(rgb.max(1)<.36)&(rgb.max(1)-rgb.min(1)<.08)
        if actor=='ren':mask&=(rgb[:,0]>rgb[:,1]*1.04)&(rgb[:,1]>rgb[:,2]*1.08)
        assert mask.sum()>50,(actor,side,'missing independent anatomical samples')
        wanted=rest[node].copy();wanted[:3,:3]=Rotation.from_rotvec([-np.pi/3,0,0]).as_matrix()@wanted[:3,:3]
        local=np.linalg.inv(rest[parents[node]])@wanted
        posed,_=world_matrices(d,b,rotations={node:Rotation.from_matrix(local[:3,:3]).as_quat()})
        actual=parts(d,b,posed)[0]['xyz'][mask]
        ideal=(wanted@np.linalg.inv(rest[node])@np.c_[xyz[mask],np.ones(mask.sum())].T).T[:,:3]
        lag=np.linalg.norm(actual-ideal,axis=1)
        own=float(dense[mask,joints.index(node)].mean());hips=float(dense[mask,joints.index(ids['mixamorig:Hips'])].mean())
        thigh.append({'side':side,'vertices':int(mask.sum()),'own_thigh_mean':own,'pelvis_mean':hips,'flex60_lag_p95_m':float(np.quantile(lag,.95)),
                      'no_pelvis_dominance':bool(own>.80 and hips<.15)})
    clips={}
    shoes=shoe_sources(d,b)
    for clip in ['idle','walk','run']:
        a=next(a for a in d['animations'] if a['name']==clip);rows=[];lowest=1.
        for t in np.linspace(0,durations(path)[clip],257):
            w,_=world_matrices(d,b,a,t)
            lowest=min(lowest,min(float(points[:,1].min()) for points in shoe_points(shoes,w).values()))
            for side,sign in [('Left',1),('Right',-1)]:
                hip,knee,ankle=[w[ids['mixamorig:'+side+s]][:3,3] for s in ['UpLeg','Leg','Foot']]
                axis=(ankle-hip)/np.linalg.norm(ankle-hip);off=knee-hip-axis*np.dot(knee-hip,axis)
                flex=180-np.degrees(np.arccos(np.clip(np.dot(hip-knee,ankle-knee)/np.linalg.norm(hip-knee)/np.linalg.norm(ankle-knee),-1,1)))
                rows.append([off[0]*sign,off[2],flex])
        x=np.asarray(rows);clips[clip]={'samples_per_side':257,'minimum_outward_m':float(x[:,0].min()),'minimum_forward_m':float(x[:,1].min()),'flexion_deg_range':[float(x[:,2].min()),float(x[:,2].max())], 'minimum_full_shoe_y_m':lowest}
    source_gates=[]
    if actor in ['aoi','tanaka','kazuko']:
        c=clips['idle'];source_gates.append({'name':'Raw standing knee plane and extension','passed':c['minimum_forward_m']>=-.002 and 2<=c['flexion_deg_range'][0] and c['flexion_deg_range'][1]<24})
    if actor in ['sora','kazuko']:
        c=clips['walk'];source_gates.append({'name':'Raw walking knee plane','passed':c['minimum_outward_m']>=-.010 and c['minimum_forward_m']>.001})
    for clip in ['walk','run']:
        source_gates.append({'name':'Full source shoes clear the flat floor in '+clip,'passed':clips[clip]['minimum_full_shoe_y_m']>=.006})
    for p in parts(d,b):
        assert np.isfinite(p['weights']).all() and p['weights'].min()>=0 and np.max(abs(p['weights'].sum(1)-1))<1e-5
    return {'actor':actor,'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'thigh':thigh,'clips':clips,'source_gates':source_gates,
            'passed':all(r['no_pelvis_dominance'] for r in thigh) and all(r['passed'] for r in source_gates),
            'runtime_modifiers':0,'scope':'Anatomical thigh and skeletal animation; not skirt/apron collision or naturalness approval'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--models',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    rows=[audit(a.models/('CH_'+who+'.glb'),who) for who in ACTORS]
    a.output.write_text(json.dumps({'actors':rows,'passed':all(r['passed'] for r in rows)},indent=2)+'\n')
    for row in rows:print(row['actor'],row['passed'],[(x['name'],x['passed']) for x in row['source_gates']])
    raise SystemExit(0 if all(row['passed'] for row in rows) else 1)
