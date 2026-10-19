"""Candidate-only continuous thigh sharing on Kazuko's existing yellow apron.

Only the selected primitive's JOINTS/WEIGHTS accessors are replaced. Existing
source local-target support supplies the cloth mask, including shadowed folds;
source body vertices, sleeves, bones, animations and all morph payloads stay exact.
Final source-proxy solving and native fit acceptance are separate requirements.
"""
from pathlib import Path
import argparse, copy, hashlib, json
import numpy as np
from scipy import sparse
from scipy.sparse.csgraph import connected_components,dijkstra
from scipy.spatial import cKDTree
from audit_local_garments import mesh_state
from prepare_local_garments import read, smooth
from repair_head_neck import append, save


def physical_groups(state):
    points=state['positions'];joints=state['joints'];weights=state['weights']
    dense=np.zeros((len(points),len(state['skin']['joints'])))
    for slot in range(joints.shape[1]):np.add.at(dense,(np.arange(len(points)),joints[:,slot]),weights[:,slot])
    pairs=cKDTree(points).query_pairs(1e-6,output_type='ndarray')
    if len(pairs):pairs=pairs[np.max(abs(dense[pairs[:,0]]-dense[pairs[:,1]]),axis=1)<1e-7]
    graph=sparse.coo_matrix((np.ones(2*len(pairs)),(np.r_[pairs[:,0],pairs[:,1]],np.r_[pairs[:,1],pairs[:,0]])),shape=(len(points),len(points))).tocsr()
    count,labels=connected_components(graph,directed=False)
    return dense,pairs,count,labels


def prepare(args):
    state=mesh_state(args.input,'kazuko');d=copy.deepcopy(state['d']);b=bytearray(state['b']);points=state['positions'];height=float(points[:,1].max())
    assert 0<=args.thigh_share<=.4
    assert len(state['local'])==24,'Expected the existing 4x3 front/back cloth targets'
    delta=np.array([state['shapes'][i] for i in state['local']])
    assert np.max(abs(delta[:,:,:2]))<1e-8,'Local garment target has unexpected non-Z support'
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig');profile=rig.get('extras',{}).get('garment_local_clearance',{})
    amplitude=float(profile.get('maximum_local_displacement_m',profile.get('amplitude',.12)))
    # These targets form a partition of unity; summing their scalar supports
    # restores the original continuous panel mask without a normal-facing gate.
    mask=np.clip(np.abs(delta[:,:,2]).sum(0)/amplitude,0,1)
    assert np.max(mask[state['body']])<1e-8,'Existing cloth support overlaps source body0'
    dense,pairs,groups,labels=physical_groups(state)
    group_mask=np.zeros(groups);np.maximum.at(group_mask,labels,mask)
    protected=np.zeros(groups,bool);protected[np.unique(labels[state['body']])]=True;group_mask[protected]=0
    mask=group_mask[labels]
    for report_path in args.retreat_report:
        report=json.loads(report_path.read_text());assert report['source_sha256']==hashlib.sha256(args.input.read_bytes()).hexdigest(),'Retreat report source differs'
        bad=np.asarray(report['unique_problem_faces'],int)
        faces=read(state['d'],state['b'],state['d']['meshes'][state['node']['mesh']]['primitives'][0]['indices']).reshape(-1,3)
        if not len(bad):continue
        seeds=np.unique(faces[bad]);edges=np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]],pairs],axis=1),axis=0)
        distance=np.maximum(np.linalg.norm(points[edges[:,0]]-points[edges[:,1]],axis=1),1e-8)
        graph=sparse.coo_matrix((np.r_[distance,distance],(np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(len(points),len(points))).tocsr()
        geodesic=dijkstra(graph,directed=False,indices=seeds,min_only=True)
        fade=args.retreat_factor+(1-args.retreat_factor)*smooth(0,args.retreat_distance,geodesic)
        minima=np.ones(groups);np.minimum.at(minima,labels,fade)
        group_mask*=minima;mask=group_mask[labels]
    names={d['nodes'][ji].get('name'):i for i,ji in enumerate(state['skin']['joints'])}
    hip=names['mixamorig:Hips'];left=names['mixamorig:LeftUpLeg'];right=names['mixamorig:RightUpLeg']
    amount=(1-smooth(.34*height,.53*height,points[:,1]))*args.thigh_share
    left_share=smooth(-.12*height,.12*height,points[:,0])
    # The source apron already has substantial, spatially varying thigh skin.
    # Replacing it with a hips-dominant target would erase that existing drape.
    # Transfer only a bounded additional fraction toward the two thigh bones;
    # the upper waist's bottom=0 rows and original spine/hip continuity survive.
    transfer=amount*mask
    desired=np.zeros_like(dense);desired[:,left]=left_share;desired[:,right]=1-left_share
    fitted=dense*(1-transfer[:,None])+desired*transfer[:,None]
    active=transfer>1e-8;assert active.sum()>500
    joint_rows=state['joints'].copy();weight_rows=state['weights'].copy();selected=np.flatnonzero(active)
    order=np.argsort(fitted[selected],axis=1)[:,-joint_rows.shape[1]:][:,::-1]
    values=np.take_along_axis(fitted[selected],order,axis=1);values/=values.sum(1,keepdims=True)
    joint_rows[selected]=order;weight_rows[selected]=values
    body=state['body'];assert np.array_equal(joint_rows[body],state['joints'][body]) and np.array_equal(weight_rows[body],state['weights'][body]),'True body0 skin changed'
    primitive=d['meshes'][state['node']['mesh']]['primitives'][0];attrs=primitive['attributes']
    for slot in range(joint_rows.shape[1]//4):
        attrs['JOINTS_'+str(slot)]=append(d,b,attrs['JOINTS_'+str(slot)],joint_rows[:,4*slot:4*slot+4])
        attrs['WEIGHTS_'+str(slot)]=append(d,b,attrs['WEIGHTS_'+str(slot)],weight_rows[:,4*slot:4*slot+4])
    args.output.parent.mkdir(parents=True,exist_ok=True);save(d,b,args.output)
    changed=np.any(joint_rows!=state['joints'],axis=1)|np.any(weight_rows!=state['weights'],axis=1)
    report={'stage':'kazuko-yellow-apron-incremental-thigh-weight-candidate','input':str(args.input),'source_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'output':str(args.output),'output_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),'maximum_added_transfer_fraction':args.thigh_share,'formula':'t=mask*bottom*follow; newrow=oldrow*(1-t)+twoThighDistribution*t','cloth_mask':'sum(abs(existing Garment_Local POSITION.z)) / 0.12; physical original-skin seam groups; body0 groups pinned','mask_amplitude_m':amplitude,'selected_cloth_vertices':int(active.sum()),'changed_skin_rows':int(changed.sum()),'protected_body0_vertices':len(body),'changed_body0_rows':int(changed[body].sum()),'physical_matching_skin_seam_pairs':len(pairs),'preserved':['all base geometry/normal/UV/index payloads','all old morph POSITION/NORMAL payloads','skeleton JSON and inverse binds','all animations and morph scalar streams','images/materials','all other meshes and skin rows outside selected cloth'],'acceptance':'pending 128-phase orientation/collapse + actual solver/Euclidean gap + native review','tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    report['orientation_retreat']={'reports':[str(p) for p in args.retreat_report],'factor_at_problem_faces':args.retreat_factor,'topological_feather_distance_m':args.retreat_distance}
    args.report.write_text(json.dumps(report,indent=2)+'\n');print(args.report,flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--thigh-share',type=float,default=.34);p.add_argument('--retreat-report',type=Path,action='append',default=[]);p.add_argument('--retreat-factor',type=float,default=0.);p.add_argument('--retreat-distance',type=float,default=.06);prepare(p.parse_args())
