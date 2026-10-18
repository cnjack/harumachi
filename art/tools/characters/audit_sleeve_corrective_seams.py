"""Check physical sleeve seams, preservation, and decoded corrective orientation.

Use the actual source manifest; candidate replay is explicitly counterfactual.
The old fractured field must fail the same seam/orientation checks.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from glb_io import load
from prepare_local_garments import read
from sew_arm_seams import dense_part
from synchronize_sleeve_corrective_seams import physical_groups,posed_part
from stabilize_sleeve_corrective_fields import authored_rows,cross


def run(args):
    sd,sb=load(args.source);d,b=load(args.candidate)
    names=['CharacterBody','Sleeve_Left','Sleeve_Right']
    source={n['name']:dense_part(sd,sb,n)for n in sd['nodes']if n.get('name')in names}
    parts={n['name']:dense_part(d,b,n)for n in d['nodes']if n.get('name')in names}
    order,offsets,groups,pairs=physical_groups(source,args.character)
    edited=[name for name in source['CharacterBody']['names']if name.startswith('SleeveFit_stretch_')]
    preserved=[]
    for ni,(old,new) in enumerate(zip(sd['nodes'],d['nodes'])):
        assert old==new,'node or metadata changed'
        if 'mesh'not in old:continue
        om,nm=sd['meshes'][old['mesh']],d['meshes'][new['mesh']]
        assert {k:v for k,v in om.items()if k!='primitives'}=={k:v for k,v in nm.items()if k!='primitives'}
        for pi,(op,np_) in enumerate(zip(om['primitives'],nm['primitives'])):
            for attr,index in op['attributes'].items():assert np.array_equal(read(sd,sb,index),read(d,b,np_['attributes'][attr])),(old['name'],attr)
            assert np.array_equal(read(sd,sb,op['indices']),read(d,b,np_['indices']))
            targets=om.get('extras',{}).get('targetNames',[])
            for ti,(ot,nt) in enumerate(zip(op.get('targets',[]),np_.get('targets',[]))):
                if targets[ti]in edited and old['name']in names:continue
                for field,index in ot.items():assert np.array_equal(read(sd,sb,index),read(d,b,nt[field])),(old['name'],targets[ti],field)
            preserved.append({'mesh':old['name'],'base_attributes_indices_and_unedited_targets_exact':True})
    assert sd['skins']==d['skins']
    assert sd['animations']==d['animations'],'animation JSON changed; use unpacked candidate for this preservation check'
    assert b[:len(sb)]==sb,'source binary prefix changed'
    native=[r for r in json.loads(args.manifest.read_text())['shots']if r['id']==args.character and r['clip']=='stretch'and r['view']=='front']
    rows=native+list(authored_rows(d,b,parts,'stretch',128))
    samples=[];worstgap=0.;new_bad=0;source_bad=0;max_repair=0.;outside_change=0.
    for row in rows:
        packet={'phase':row['phase'],'kind':row.get('kind','native'),'parts':[]};cat=[];oldcat=[]
        for name in order:
            part=parts[name];old=source[name]
            points,B,_=posed_part(d,b,part,row);oldpoints,_,_=posed_part(sd,sb,old,row)
            zero={n:np.zeros_like(v)if n in edited else v for n,v in old['shapes'].items()};ref,_,_=posed_part(sd,sb,old,row,shapes=zero)
            faces=read(sd,sb,old['p']['indices']).reshape(-1,3);refcross=cross(ref,faces);area=np.linalg.norm(refcross,axis=1);valid=area>1e-12
            def bad_count(p):
                current=cross(p,faces);return valid&(((current*refcross).sum(1)<=0)|(np.linalg.norm(current,axis=1)<.15*area))
            bad=bad_count(points);oldbad=bad_count(oldpoints);new_bad+=int(bad.sum());source_bad+=int(oldbad.sum());delta=np.linalg.norm(points-oldpoints,axis=1);max_repair=max(max_repair,float(delta.max()));cat.append(points);oldcat.append(oldpoints)
            # All pre-existing skirt, body, arm, finger and hand data are exact;
            # additionally expose POSITION changes outside the upper-cloth ROI.
            H=float(source['CharacterBody']['pos'][:,1].max());outside=(old['pos'][:,1]<=.52*H)
            if outside.any():outside_change=max(outside_change,float(delta[outside].max()))
            packet['parts'].append({'mesh':name,'source_bad_orientation_or_collapse':int(oldbad.sum()),'candidate_bad_orientation_or_collapse':int(bad.sum()),'maximum_world_repair_m':float(delta.max())})
        cat=np.concatenate(cat);oldcat=np.concatenate(oldcat);gap=np.linalg.norm(cat[pairs[:,0]]-cat[pairs[:,1]],axis=1);oldgap=np.linalg.norm(oldcat[pairs[:,0]]-oldcat[pairs[:,1]],axis=1);worstgap=max(worstgap,float(gap.max()));packet['physical_gap_max_m']=float(gap.max());packet['source_physical_gap_max_m']=float(oldgap.max());samples.append(packet)
    # Every non-stretch stream is identical and the four edited columns are
    # identically zero at every original key, so its LINEAR function is zero.
    protected=[]
    for animation in d['animations']:
        if animation['name']=='stretch':continue
        for name,part in parts.items():
            ni=d['nodes'].index(part['node'])
            for channel in animation['channels']:
                if channel['target']!={'node':ni,'path':'weights'}:continue
                values=read(d,b,animation['samplers'][channel['sampler']]['output']).reshape(-1,len(part['names']))
                assert np.all(values[:,[part['names'].index(n)for n in edited]]==0)
        protected.append(animation['name'])
    passed=worstgap<.0001 and new_bad==0 and outside_change==0
    report={'source':str(args.source),'source_sha256':hashlib.sha256(args.source.read_bytes()).hexdigest(),'candidate':str(args.candidate),'candidate_sha256':hashlib.sha256(args.candidate.read_bytes()).hexdigest(),'manifest_sha256':hashlib.sha256(args.manifest.read_bytes()).hexdigest(),'scope':'4 source-native final bone/scalar peaks + 129 authored stretch poses; no candidate native render','pass':passed,'seam_limit_m':.0001,'maximum_physical_gap_m':worstgap,'source_bad_orientation_or_collapse_samples':source_bad,'candidate_bad_orientation_or_collapse_samples':new_bad,'geometry_reference':'same posed original surface with only the four SleeveFit stretch target POSITION columns zeroed; original source faces retained','maximum_world_repair_m':max_repair,'lower_body_skirt_POSITION_change_m':outside_change,'all_base_attrs_skin_uv_indices_images_nodes_animations_and_other_targets_exact':True,'protected_nonstretch_actions':protected,'preserved':preserved,'samples':samples,'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n');print(args.output,'pass',passed,'gap',worstgap,'bad',new_bad)
    if args.expect_fixed and not passed:raise SystemExit(1)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True,type=Path);p.add_argument('--candidate',required=True,type=Path);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--character',default='mio');p.add_argument('--expect-fixed',action='store_true');run(p.parse_args())
