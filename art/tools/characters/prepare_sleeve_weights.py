"""Fit only existing garment sleeves to a continuous shoulder/elbow weight field.

No mesh, skin surface, UV, texture, joint or animation is changed. Input/output
paths make this composable after anatomical pivot repairs. Bare arm vertices and
hands are deliberately outside the correction; those require anatomical audits.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from motion_math import world_matrices
from prepare_local_garments import read, colours, smooth
from repair_head_neck import append, save
from glb_io import load


def cloth_mask(who,c):
    r,g,b=c.T
    if who=='sora':return (g>r*1.025)&(g>b*1.015)
    if who=='mio':return (g>r*.88)&(b<r*1.015)&(r>.25)
    if who=='haru':return (b>g*1.03)&(b>r*.95)
    if who=='tanaka':return (b>r*1.08)&(b>g*1.01)
    if who=='aoi':return (c.min(1)>.40)&(c.max(1)-c.min(1)<.20)
    # The shoulder shawl is authored separately. Limit this pass to white blouse.
    if who=='kazuko':return (c.min(1)>.52)&(c.max(1)-c.min(1)<.20)
    return np.zeros(len(c),bool)


def prepare(args):
    d,binary=load(args.input);b=bytearray(binary);rest,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};report={'character':args.character,'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'preserved':['POSITION','NORMAL','TANGENT','TEXCOORD_0','indices','images','skeleton','animations','bare skin weights','hand weights'],'sleeves':[]}
    height=max(float(read(d,b,p['attributes']['POSITION'])[:,1].max()) for n in d['nodes'] if 'skin' in n and 'mesh' in n for p in d['meshes'][n['mesh']]['primitives'])
    for node in d['nodes']:
        if 'skin' not in node or 'mesh' not in node or node['name'].startswith('HiddenArm'):continue
        skin=d['skins'][node['skin']];joint_names=[d['nodes'][j].get('name','') for j in skin['joints']];name_to_joint={n:i for i,n in enumerate(joint_names)}
        for p in d['meshes'][node['mesh']]['primitives']:
            a=p['attributes'];pos=read(d,b,a['POSITION']);col=colours(d,b,p);cloth=cloth_mask(args.character,col)&~((col[:,0]>col[:,1]*1.10)&(col[:,1]>col[:,2]*1.02)&(col[:,0]>.30));j=read(d,b,a['JOINTS_0']);w=read(d,b,a['WEIGHTS_0'])
            if 'JOINTS_1' in a:j=np.c_[j,read(d,b,a['JOINTS_1'])];w=np.c_[w,read(d,b,a['WEIGHTS_1'])]
            nj=j.copy();nw=w.copy();changed=[]
            for side in ['Left','Right']:
                arm_name='mixamorig:'+side+'Arm';fore_name='mixamorig:'+side+'ForeArm';hand_name='mixamorig:'+side+'Hand'
                shoulder=rest[ids[arm_name]][:3,3];elbow=rest[ids[fore_name]][:3,3];wrist=rest[ids[hand_name]][:3,3];upper=elbow-shoulder;lower=wrist-elbow;upper_length=np.linalg.norm(upper);lower_length=np.linalg.norm(lower);upper_axis=upper/upper_length;lower_axis=lower/lower_length
                t=(pos-shoulder)@upper_axis;u=(pos-elbow)@lower_axis;upper_radius=np.linalg.norm(pos-shoulder-t[:,None]*upper_axis,axis=1);lower_radius=np.linalg.norm(pos-elbow-u[:,None]*lower_axis,axis=1);on_lower=(u>0)&(lower_radius<upper_radius);arc=np.where(on_lower,upper_length+u,t);radius=np.where(on_lower,lower_radius,upper_radius)
                own=np.array([n.startswith('Cloth_'+side+'_') or n in [arm_name,fore_name,hand_name,'TWIST_'+side] for n in joint_names]);own_share=np.sum(w*own[j],axis=1)
                # Capsule-only selection protects lapels, straps, vest/pockets and hands.
                eligible=cloth&(arc>.018*height)&(arc<upper_length+lower_length-.045*height)&(radius<.083*height)&(own_share>.30)&(pos[:,1]>.52*height)
                blend=smooth(.018*height,.065*height,arc)*eligible
                fore=smooth(upper_length-.045*height,upper_length+.045*height,arc)
                active=np.flatnonzero(blend>1e-6)
                for vi in active:
                    alpha=float(blend[vi]);desired={name_to_joint[arm_name]:1-float(fore[vi]),name_to_joint[fore_name]:float(fore[vi])}
                    # Preserve a smaller secondary cuff contribution; a 40% spring
                    # weight at the rim made the split sleeves appear detached.
                    helper={int(ji):float(wi) for ji,wi in zip(j[vi],w[vi]) if joint_names[int(ji)].startswith('Cloth_'+side+'_') and wi>0};helper_total=sum(helper.values());keep=min(.10,helper_total)
                    for ji in list(desired):desired[ji]*=1-keep
                    if helper_total:
                        for ji,wi in helper.items():desired[ji]=wi/helper_total*keep
                    row={int(ji):float(wi)*(1-alpha) for ji,wi in zip(j[vi],w[vi]) if wi>0}
                    for ji,wi in desired.items():row[ji]=row.get(ji,0)+wi*alpha
                    row=sorted(row.items(),key=lambda kv:kv[1],reverse=True)[:j.shape[1]];total=sum(v for _,v in row);nj[vi]=0;nw[vi]=0
                    for slot,(ji,wi) in enumerate(row):nj[vi,slot]=ji;nw[vi,slot]=wi/total
                changed.extend(active.tolist());report['sleeves'].append({'mesh':node['name'],'side':side,'changed_vertices':len(active),'max_helper_share':.10,'upper_arm_length_m':float(upper_length),'elbow_blend_width_m':.09*height})
            if not changed:continue
            a['JOINTS_0']=append(d,b,a['JOINTS_0'],nj[:,:4]);a['WEIGHTS_0']=append(d,b,a['WEIGHTS_0'],nw[:,:4])
            if 'JOINTS_1' in a:a['JOINTS_1']=append(d,b,a['JOINTS_1'],nj[:,4:]);a['WEIGHTS_1']=append(d,b,a['WEIGHTS_1'],nw[:,4:])
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig');rig.setdefault('extras',{})['sleeve_weight_revision']='continuous_upper_arm_and_elbow_20261017'
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--character',required=True,choices=['sora','mio','haru','tanaka','aoi','kazuko','ren']);p.add_argument('--report',type=Path,required=True);args=p.parse_args();prepare(args)
