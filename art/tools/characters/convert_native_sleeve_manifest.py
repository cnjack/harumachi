#!/usr/bin/env python3
"""Convert acknowledged native transition packets to model-space writer rows.

The saved pose packets remain external evidence inputs. This converter does not
capture Godot or invent intermediate poses. Missing acknowledgements are counted;
an acknowledged mismatched bone/scalar packet fails instead of being accepted.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np


def convert(source, character, source_kind):
    document=json.loads(source.read_text());rows=[];excluded=0
    for case in document['cases']:
        if case['character']!=character:continue
        if case.get('sampling_failures',0):raise ValueError('Native case contains sampling failures')
        ack={s['applied_frame']:s for s in case['full_bone_samples']}
        if len(ack)!=len(case['full_bone_samples']):raise ValueError('Duplicate acknowledged frame')
        for frame in case['frames']:
            sample=ack.get(frame['frame'])
            if sample is None:excluded+=1;continue
            if sample['maximum_transform_difference_from_continuous']!=0 or sample['bone_transforms']!=frame['bone_transforms'] or sample['blend_shape_values']!=frame['blend_shape_values']:
                raise ValueError('Bone/scalar packets are not from the same final callback')
            if len(sample['bone_transforms'])!=len(case['bone_layout']):raise ValueError('Incomplete bone packet')
            M=np.asarray(frame['model_basis']).T;inv=np.linalg.inv(M);origin=np.asarray(frame['model_position']);bones=[]
            for meta,transform in zip(case['bone_layout'],sample['bone_transforms']):
                t=np.asarray(transform)
                if t.shape!=(12,) or not np.isfinite(t).all():raise ValueError('Invalid bone transform')
                bones.append({'name':meta['name'],'position':(inv@(t[:3]-origin)).tolist(),
                    'basis':(inv@t[3:].reshape(3,3).T).T.tolist()})
            rows.append({'id':character,'clip':frame['clip'],'clip_time':frame['clip_time'],'phase':frame['phase'],
                'position':[0.,0.,0.],'bones':bones,'blend_shape_values':sample['blend_shape_values'],
                'view':case['view'],'source_frame':frame['frame'],'kind':source_kind})
    if not rows:raise ValueError('No acknowledged rows for requested character')
    return {'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'excluded_without_ack':excluded,'shots':rows}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--character',default='mio');p.add_argument('--source-kind',default='source-native-continuous-counterfactual')
    args=p.parse_args();result=convert(args.input,args.character,args.source_kind)
    if args.output.exists():raise FileExistsError(args.output)
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result))
    print(json.dumps({'output':str(args.output),'rows':len(result['shots']),
        'stretch_rows':sum(r['clip']=='stretch'for r in result['shots']),
        'excluded_without_ack':result['excluded_without_ack']}))


if __name__=='__main__':main()
