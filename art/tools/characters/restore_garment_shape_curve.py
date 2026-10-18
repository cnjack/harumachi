"""Restore one accepted LINEAR garment curve without changing model payloads.

All other columns in the selected clip must be zero, except explicitly named
corrective prefixes that are intentionally cleared. Other clips, geometry,
skin and every existing accessor are retained. This does not prove the restored
curve still passes current native contact or visual checks.
"""
import argparse
import copy
import json
from pathlib import Path
import numpy as np
from glb_io import load
from prepare_local_garments import read
from repair_head_neck import append, save
from garment_bake_support import digest


def main(args):
    if args.output.exists() or args.report.exists():
        raise FileExistsError('Use new output and report paths')
    if digest(args.input)!=args.expected_source_sha256 or digest(args.accepted)!=args.expected_accepted_sha256:
        raise ValueError('Explicit input identities do not match')
    source,binary=load(args.input)
    accepted,accepted_binary=load(args.accepted)
    def mesh_data(document,blob):
        matches=[(i,n) for i,n in enumerate(document['nodes']) if n.get('name')==args.mesh_node and 'mesh' in n and 'skin' in n]
        if len(matches)!=1:raise ValueError('Mesh node must resolve uniquely')
        index,node=matches[0];mesh=document['meshes'][node['mesh']]
        if len(mesh['primitives'])!=1:raise ValueError('Only a single primitive is supported')
        primitive=mesh['primitives'][0];names=mesh['extras']['targetNames']
        return index,node,mesh,primitive,names
    ni,node,mesh,primitive,names=mesh_data(source,binary)
    oi,on,om,op,old_names=mesh_data(accepted,accepted_binary)
    target=names.index(args.shape);old_target=old_names.index(args.shape)
    # A scalar from a different rest mesh/skin/target has no transferable meaning.
    for field in ['POSITION','JOINTS_0','WEIGHTS_0','JOINTS_1','WEIGHTS_1']:
        if (field in primitive['attributes'])!=(field in op['attributes']):raise ValueError('Skin attribute mismatch')
        if field in primitive['attributes'] and not np.array_equal(read(source,binary,primitive['attributes'][field]),read(accepted,accepted_binary,op['attributes'][field])):
            raise ValueError('Rest geometry or skin differs: '+field)
    if not np.array_equal(read(source,binary,primitive['targets'][target]['POSITION']),read(accepted,accepted_binary,op['targets'][old_target]['POSITION'])):
        raise ValueError('Restored target POSITION differs from the accepted source')
    def track(document,blob,index):
        animation=next(a for a in document['animations'] if a['name']==args.clip)
        channels=[c for c in animation['channels'] if c['target']=={'node':index,'path':'weights'}]
        if len(channels)!=1:raise ValueError('Selected clip must have one weights channel')
        channel=channels[0];sampler=animation['samplers'][channel['sampler']]
        if sampler.get('interpolation','LINEAR')!='LINEAR':raise ValueError('Only LINEAR curve restoration is supported')
        return animation,channel,sampler
    oa,oc,os=track(accepted,accepted_binary,oi)
    times=read(accepted,accepted_binary,os['input'])
    values=read(accepted,accepted_binary,os['output']).reshape(-1,len(old_names))[:,old_target]
    a0,c0,s0=track(source,binary,ni)
    previous=read(source,binary,s0['output']).reshape(-1,len(names))
    cleared=[i for i,n in enumerate(names) if any(n.startswith(p) for p in args.clear_prefix)]
    protected=[i for i in range(len(names)) if i!=target and i not in cleared]
    if np.any(previous[:,protected]):raise ValueError('Refuse to discard another nonzero selected-clip shape curve')
    duration=max(float(read(source,binary,s['input']).max()) for s in a0['samplers'])
    if float(times[-1,0])!=duration:raise ValueError('Accepted curve endpoint and current clip duration differ')
    document=copy.deepcopy(source);buffer=bytearray(binary)
    a1=next(a for a in document['animations'] if a['name']==args.clip)
    c1=next(c for c in a1['channels'] if c['target']=={'node':ni,'path':'weights'})
    expanded=np.zeros((len(times),len(names)),np.float32);expanded[:,target]=values
    sampler={'input':append(document,buffer,s0['input'],times),'output':append(document,buffer,s0['output'],expanded.reshape(-1,1)),'interpolation':'LINEAR'}
    c1['sampler']=len(a1['samplers']);a1['samplers'].append(sampler)
    rig=next(n for n in document['nodes'] if n.get('name')==args.profile_node)
    profile=rig['extras']['garment_local_clearance']
    before=copy.deepcopy(profile.get('disable_global_shapes',['Skirt_Clearance','Apron_Clearance']))
    profile['disable_global_shapes']=[name for name in before if name!=args.shape]
    save(document,buffer,args.output)
    verified,vb=load(args.output)
    assert all(np.array_equal(read(source,binary,i),read(verified,vb,i)) for i in range(len(source['accessors'])))
    assert [a for a in source['animations'] if a['name']!=args.clip]==[a for a in verified['animations'] if a['name']!=args.clip]
    assert source['meshes']==verified['meshes'] and source['skins']==verified['skins']
    for old,new in zip(a0['channels'],a1['channels']):
        if old['target']=={'node':ni,'path':'weights'}:continue
        assert old==new and a0['samplers'][old['sampler']]==a1['samplers'][new['sampler']]
    assert np.array_equal(read(verified,vb,sampler['input']),times)
    assert np.array_equal(read(verified,vb,sampler['output']).reshape(-1,len(names))[:,target],values)
    report={'scope':__doc__,'input_sha256':digest(args.input),'accepted_sha256':digest(args.accepted),'output_sha256':digest(args.output),'tool_sha256':digest(__file__),'clip':args.clip,'mesh_node':args.mesh_node,'shape':args.shape,'restored_key_count':len(times),'old_times_and_values_exact':True,'cleared_columns':[names[i] for i in cleared],'disable_global_shapes_before':before,'disable_global_shapes_after':profile['disable_global_shapes'],'all_existing_decoded_accessors_exact':True,'other_clips_and_skeletal_tracks_exact':True,'native_acceptance_inferred':False}
    args.report.write_text(json.dumps(report,indent=2));print(args.report)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for option in ['input','accepted','output','report']:parser.add_argument('--'+option,type=Path,required=True)
    for option in ['expected-source-sha256','expected-accepted-sha256','mesh-node','shape','clip']:parser.add_argument('--'+option,required=True)
    parser.add_argument('--clear-prefix',action='append',default=[])
    parser.add_argument('--profile-node',default='Rig')
    main(parser.parse_args())
