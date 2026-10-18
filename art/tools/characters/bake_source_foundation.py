"""Bake measured, flat-floor foundation poses into existing source animation tracks.

The authoring sampler disables runtime arms, foot IK, clothing and transitions.
Mesh, skin weights, rest joints, inverse binds, morph tracks and textures remain
byte exact. Native unoptimized raw poses must first agree with original GLB TRS.
"""
from pathlib import Path
import argparse, copy, hashlib, json
import numpy as np
from scipy.spatial.transform import Rotation
from glb_io import load
from motion_math import sample_channel
from rebuild_locomotion import append_values
from repair_head_neck import save


def bake(source, capture, output):
    doc, raw = load(source)
    original = copy.deepcopy(doc)
    blob = bytearray(raw)
    sampled = json.loads(capture.read_text())
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha == sampled['source_sha256']
    ids = {n.get('name'): i for i,n in enumerate(doc['nodes'])}
    changes, max_raw_position, max_raw_angle = [], 0., 0.
    for clip, data in sampled['clips'].items():
        source_clip = next(a for a in original['animations'] if a['name'] == clip)
        target = next(a for a in doc['animations'] if a['name'] == clip)
        times = np.asarray([row['time'] for row in data['rows']], dtype=np.float32)
        assert np.all(np.diff(times)>0)
        for name in data['rows'][0]['before']:
            node = ids[name.replace('mixamorig_', 'mixamorig:')]
            for semantic in ['translation','rotation']:
                before = np.asarray([row['before'][name][semantic] for row in data['rows']])
                after = np.asarray([row['after'][name][semantic] for row in data['rows']])
                if semantic == 'rotation':
                    difference = (Rotation.from_quat(before).inv()*Rotation.from_quat(after)).magnitude()
                else:
                    difference = np.linalg.norm(after-before,axis=1)
                if difference.max() < 1e-6:
                    continue
                channel = next((c for c in source_clip['channels'] if c['target'] == {'node':node,'path':semantic}),None)
                values = np.asarray([sample_channel(original,raw,source_clip,channel,float(t)) if channel else original['nodes'][node].get(semantic,[0,0,0] if semantic=='translation' else [0,0,0,1]) for t in [row.get('evaluation_time',row['time']) for row in data['rows']]])
                if semantic == 'rotation':
                    error = (Rotation.from_quat(values).inv()*Rotation.from_quat(before)).magnitude().max()
                    max_raw_angle = max(max_raw_angle,float(error))
                    assert error < .001, (clip,name,'raw rotational mismatch',error)
                    for index in range(1,len(after)):
                        if after[index] @ after[index-1] < 0: after[index] *= -1
                else:
                    error = np.linalg.norm(values-before,axis=1).max()
                    max_raw_position = max(max_raw_position,float(error))
                    assert error < .0001, (clip,name,'raw positional mismatch',error)
                exact_values = np.asarray([sample_channel(original,raw,source_clip,channel,float(t)) if channel else original['nodes'][node].get(semantic,[0,0,0] if semantic=='translation' else [0,0,0,1]) for t in times])
                if semantic == 'rotation':
                    after = (Rotation.from_quat(exact_values)*Rotation.from_quat(before).inv()*Rotation.from_quat(after)).as_quat()
                    for index in range(1,len(after)):
                        if after[index] @ after[index-1] < 0: after[index] *= -1
                else:
                    after = exact_values + after - before
                if clip in ['idle','walk','run']:
                    # Make the correction periodic as well as the source curve.
                    # A stance-side switch in the old helper can otherwise leave
                    # a different endpoint despite a looped authored source.
                    u = np.clip((times/times[-1]-.85)/.15,0,1)
                    blend = u*u*(3-2*u)
                    if semantic == 'rotation':
                        closing = (Rotation.from_quat(after[-1]).inv()*Rotation.from_quat(after[0])).as_rotvec()
                        after = (Rotation.from_quat(after)*Rotation.from_rotvec(blend[:,None]*closing)).as_quat()
                    else:
                        after += blend[:,None]*(after[0]-after[-1])
                    after[-1] = after[0]
                sampler = {'input':append_values(doc,blob,times[:,None],'SCALAR'),
                    'output':append_values(doc,blob,after,'VEC4' if semantic=='rotation' else 'VEC3'),'interpolation':'LINEAR'}
                target_channel = next((c for c in target['channels'] if c['target']=={'node':node,'path':semantic}),None)
                if target_channel:
                    target['samplers'][target_channel['sampler']] = sampler
                else:
                    target['channels'].append({'target':{'node':node,'path':semantic},'sampler':len(target['samplers'])})
                    target['samplers'].append(sampler)
                changes.append({'clip':clip,'bone':name,'path':semantic,'samples':len(times),'maximum_change':float(difference.max())})
    actor = sampled['actor']
    flags = {'version':1,'source_sha256':sha,'authoring_capture_sha256':hashlib.sha256(capture.read_bytes()).hexdigest(),
             'standing':actor in ['aoi','tanaka','kazuko'], 'walk':actor in ['mio','kazuko'],
             'idle':actor=='mio', 'tanaka_arm':actor=='tanaka','kazuko_run':actor=='kazuko',
             'floor_reference_m':0,'terrain_or_transition_baked':False,'skin_weights_changed':False}
    next(n for n in doc['nodes'] if n.get('name')=='Rig').setdefault('extras',{})['source_pose_foundation']=flags
    for key in ['meshes','skins','materials','textures','images','samplers']:
        assert doc.get(key) == original.get(key), key
    assert bytes(blob[:len(raw)]) == raw
    output.parent.mkdir(parents=True,exist_ok=True)
    save(doc,blob,output)
    return {'actor':actor,'source':str(source),'source_sha256':sha,'output':str(output),
            'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'changes':changes,
            'maximum_native_raw_position_error_m':max_raw_position,'maximum_native_raw_rotation_error_rad':max_raw_angle,
            'mesh_skin_rest_and_morph_payloads_exact':True,'flags':flags}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['source','capture','output','report']:p.add_argument('--'+k,type=Path,required=True)
    a=p.parse_args();r=bake(a.source,a.capture,a.output);a.report.write_text(json.dumps(r,indent=2)+'\n');print(a.report)
