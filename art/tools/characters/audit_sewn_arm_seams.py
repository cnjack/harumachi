"""Independent same-pose seam-gap negative control using native final matrices.

The after result is explicitly a counterfactual under the source capture's final
bones/scalar morph values. Re-rendering the candidate remains required.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from scipy.spatial import cKDTree
from audit_sleeve_weights import assets
from audit_local_garments import pose
from prepare_sleeve_weights import cloth_mask
from prepare_local_garments import read
from motion_math import world_matrices


def positions(bundle,part,row):
    d,b=bundle[:2];state={'d':d,'b':b,'ni':part['ni'],'node':d['nodes'][part['ni']],'positions':part['pos'],'skin':part['skin'],'binds':part['binds'],'names':part['names'],'joints':part['joints'],'weights':part['weights'],'shapes':part['shapes'],'local':[]}
    return pose(state,row['clip'],row['clip_time'],row,actual_shapes=True)[0]


def audit(args):
    before=assets(args.before,args.character);after=assets(args.after,args.character);d,b,parts,height=before;body=parts[('CharacterBody',0)];tree=cKDTree(body['pos']);rest,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};pairs={};preserved=[]
    provenance=args.manifest.parent.parent/'model-hashes.json'
    if json.loads(provenance.read_text())[f'CH_{args.character}.glb']!=hashlib.sha256(args.before.read_bytes()).hexdigest():raise ValueError('Before source does not match the actual native capture')
    for side in ['Left','Right']:
        part=parts[('Sleeve_'+side,0)];shoulder=rest[ids['mixamorig:'+side+'Arm']][:3,3];matches=tree.query_ball_point(part['pos'],1e-6);selected=[]
        for si,members in enumerate(matches):
            point=part['pos'][si]
            if abs(point[0])>abs(shoulder[0])+.04*height or point[1]<shoulder[1]-.14*height:continue
            for bi in members:
                if body['cloth'][bi] and part['cloth'][si]:selected.append((bi,si))
        pairs[side]=np.array(selected,int)
    for key,part in parts.items():
        new=after[2][key];attrs=part['p']['attributes'];target_attrs=new['p']['attributes'];kept={field:np.array_equal(read(d,b,attrs[field]),read(after[0],after[1],target_attrs[field])) for field in ['POSITION','NORMAL','TEXCOORD_0']};kept['indices']=np.array_equal(read(d,b,part['p']['indices']),read(after[0],after[1],new['p']['indices']));colour=__import__('prepare_local_garments').colours(d,b,part['p']);skin=(colour[:,0]>colour[:,1]*1.10)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.30);kept['strong_skin_weights']=np.array_equal(part['weights'][skin],new['weights'][skin]) and np.array_equal(part['joints'][skin],new['joints'][skin]);preserved.append({'mesh':key[0],**kept})
    raw_rows=[r for r in json.loads(args.manifest.read_text())['shots'] if r['id']==args.character];unique={}
    for row in raw_rows:
        signature=(row['clip'],row['clip_time'],json.dumps([{k:v[k] for k in ['name','basis','position']} for v in row['bones']],sort_keys=True));unique.setdefault(signature,row)
    samples=[]
    for row in unique.values():
        old_body=positions(before,body,row);new_body=positions(after,after[2][('CharacterBody',0)],row);result={'clip':row['clip'],'phase':row['phase'],'file':row['file'],'sides':{}}
        for side,pair in pairs.items():
            old_sleeve=positions(before,parts[('Sleeve_'+side,0)],row);new_sleeve=positions(after,after[2][('Sleeve_'+side,0)],row);old_gap=np.linalg.norm(old_body[pair[:,0]]-old_sleeve[pair[:,1]],axis=1);gap=np.linalg.norm(new_body[pair[:,0]]-new_sleeve[pair[:,1]],axis=1);result['sides'][side]={'sewn_source_pairs':len(pair),'before_max_gap_m':float(old_gap.max()),'counterfactual_max_gap_m':float(gap.max()),'before_gap_p95_m':float(np.percentile(old_gap,95)),'counterfactual_gap_p95_m':float(np.percentile(gap,95)),'maximum_body_surface_change_m':float(np.linalg.norm(new_body-old_body,axis=1).max()),'maximum_sleeve_surface_change_m':float(np.linalg.norm(new_sleeve-old_sleeve,axis=1).max())}
        samples.append(result)
    report={'before':str(args.before),'after':str(args.after),'after_sha256':hashlib.sha256(args.after.read_bytes()).hexdigest(),'scope':'native source final bases and exact source morph values; after is counterfactual, candidate native render remains required','preserved':preserved,'source_preservation_pass':all(all(value for key,value in row.items() if key!='mesh') for row in preserved),'samples':samples,'negative_control_has_visible_seam':max(s['before_max_gap_m'] for r in samples for s in r['sides'].values())>.05,'seam_counterfactual_below_0_1mm':all(s['counterfactual_max_gap_m']<.0001 for r in samples for s in r['sides'].values())};args.output.write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['samples','preserved']},indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--character',default='sora');p.add_argument('--output',type=Path,required=True);audit(p.parse_args())
