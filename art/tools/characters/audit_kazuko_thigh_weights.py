"""Independent same-pose surface and exact-preservation check for apron weights.

128 phases of every authored action check newly inverted/collapsed triangles,
original body0 displacement and physical UV seams. No contact-solver acceptance
is inferred: final source-proxy re-solving and actual Euclidean gap remain due.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from audit_local_garments import mesh_state,pose
from prepare_local_garments import read
from prepare_kazuko_thigh_weights import physical_groups


def audit(args):
    source=mesh_state(args.source,'kazuko');candidate=mesh_state(args.candidate,'kazuko');sd,sb=source['d'],source['b'];d,b=candidate['d'],candidate['b']
    for key in ['nodes','skins','animations','materials','images','textures','samplers','scenes','scene']:
        assert sd.get(key)==d.get(key),'Protected JSON changed: '+key
    assert d['accessors'][:len(sd['accessors'])]==sd['accessors'],'Original accessor JSON changed'
    assert b[:len(sb)]==sb,'Original binary payload modified'
    protected_attributes=0
    for mi,(sm,cm) in enumerate(zip(sd['meshes'],d['meshes'])):
        assert {k:v for k,v in sm.items() if k!='primitives'}=={k:v for k,v in cm.items() if k!='primitives'}
        for pi,(sp,cp) in enumerate(zip(sm['primitives'],cm['primitives'])):
            assert {k:v for k,v in sp.items() if k!='attributes'}=={k:v for k,v in cp.items() if k!='attributes'},'Original morph/index/material descriptor changed'
            for name,index in sp['attributes'].items():
                if mi==source['node']['mesh'] and pi==0 and name.startswith(('JOINTS_','WEIGHTS_')):continue
                assert index==cp['attributes'][name] and np.array_equal(read(sd,sb,index),read(d,b,cp['attributes'][name])),name
                protected_attributes+=1
    body=source['body'];assert np.array_equal(source['joints'][body],candidate['joints'][body]) and np.array_equal(source['weights'][body],candidate['weights'][body]),'Body0 weights changed'
    _,pairs,_,_=physical_groups(source);primitive=sd['meshes'][source['node']['mesh']]['primitives'][0];faces=read(sd,sb,primitive['indices']).reshape(-1,3)
    changed=np.any(source['joints']!=candidate['joints'],axis=1)|np.any(source['weights']!=candidate['weights'],axis=1)
    local_support=np.any(np.asarray([np.linalg.norm(source['shapes'][i],axis=1)>0 for i in source['local']]),axis=0)
    assert not np.any(changed&~local_support),'Skin outside existing apron templates changed'
    rows=[];bad_union=set();maximum_body=0.;maximum_seam_added=0.;max_shift=0.
    for animation in sd['animations']:
        if args.clips and animation['name'] not in args.clips:continue
        clip=animation['name'];duration=max(float(read(sd,sb,s['input']).max()) for s in animation['samplers'])
        flipped=set();collapsed=set();seam_added=0.;body_shift=0.;shift_max=0.
        phase_grid=np.unique(np.r_[np.arange(args.samples)/args.samples,.2,.8,1.])
        for phase in phase_grid:
            before,_=pose(source,clip,float(phase*duration));after,_=pose(candidate,clip,float(phase*duration));delta=after-before
            a=before[faces];z=after[faces];cross0=np.cross(a[:,1]-a[:,0],a[:,2]-a[:,0]);cross1=np.cross(z[:,1]-z[:,0],z[:,2]-z[:,0]);area=np.linalg.norm(cross0,axis=1);valid=area>1e-12
            bad=np.flatnonzero(((cross0*cross1).sum(1)<=0)&valid);small=np.flatnonzero((np.linalg.norm(cross1,axis=1)<.15*area)&valid)
            flipped.update(bad.tolist());collapsed.update(small.tolist());bad_union.update(bad.tolist());bad_union.update(small.tolist())
            body_shift=max(body_shift,float(np.linalg.norm(delta[body],axis=1).max()));shift_max=max(shift_max,float(np.linalg.norm(delta,axis=1).max()))
            if len(pairs):seam_added=max(seam_added,float(np.linalg.norm(delta[pairs[:,0]]-delta[pairs[:,1]],axis=1).max()))
        maximum_body=max(maximum_body,body_shift);maximum_seam_added=max(maximum_seam_added,seam_added);max_shift=max(max_shift,shift_max)
        rows.append({'clip':clip,'phases':len(phase_grid),'newly_inverted_faces':sorted(flipped),'near_collapsed_faces':sorted(collapsed),'body0_maximum_displacement_m':body_shift,'physical_UV_seam_maximum_added_gap_m':seam_added,'maximum_cloth_weight_change_displacement_m':shift_max})
        print(clip,'flips',len(flipped),'collapsed',len(collapsed),'body',body_shift,'seam',seam_added,flush=True)
    result={'source':str(args.source),'source_sha256':hashlib.sha256(args.source.read_bytes()).hexdigest(),'candidate':str(args.candidate),'candidate_sha256':hashlib.sha256(args.candidate.read_bytes()).hexdigest(),'scope':'128-phase authored action skin/morph preflight plus .2/.8/1; no post-IK contact solver, no native candidate acceptance','all_protected_JSON_accessors_original_binary_exact':True,'protected_base_attributes':protected_attributes,'body0_skin_rows_exact':True,'protected_body0_vertices':len(body),'actions':len(rows),'full_original_action_set':len(rows)==len(sd['animations']),'uniform_phases_per_action':args.samples,'evaluated_pose_count':sum(r['phases'] for r in rows),'samples':rows,'unique_problem_faces':sorted(bad_union),'maximum_body0_displacement_m':maximum_body,'maximum_physical_seam_added_gap_m':maximum_seam_added,'maximum_cloth_displacement_m':max_shift,'pending':['actual source-proxy solver re-run','Euclidean cloth-to-body gap A/B','native review on existing desktop only'],'pass':not bad_union and maximum_body<1e-10 and maximum_seam_added<1e-5}
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(args.output,result['pass'],flush=True)
    if not result['pass']:raise SystemExit(1)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True,type=Path);p.add_argument('--candidate',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--samples',type=int,default=128);p.add_argument('--clips',nargs='+');audit(p.parse_args())
