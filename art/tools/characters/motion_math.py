"""Evaluate a glTF skeleton at an authored sample without changing the mesh."""
import numpy as np
from scipy.spatial.transform import Rotation, Slerp
from repair_head_neck import read

def sample_channel(doc, binary, animation, channel, time):
    sampler = animation['samplers'][channel['sampler']]
    times = read(doc,binary,sampler['input']).ravel()
    values = read(doc,binary,sampler['output'])
    assert sampler.get('interpolation','LINEAR') != 'CUBICSPLINE'
    if time <= times[0]: return values[0].copy()
    if time >= times[-1]: return values[-1].copy()
    j = int(np.searchsorted(times,time)-1)
    if sampler.get('interpolation') == 'STEP': return values[j].copy()
    if channel['target']['path'] == 'rotation':
        return Slerp(times[j:j+2],Rotation.from_quat(values[j:j+2]))([time]).as_quat()[0]
    u = (time-times[j])/(times[j+1]-times[j])
    return values[j]*(1-u)+values[j+1]*u

def world_matrices(doc, binary, animation=None, time=0, rotations=None):
    parents = {c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    values = {}
    if animation:
        for channel in animation['channels']:
            if channel['target']['path']=='weights': continue
            values[(channel['target']['node'],channel['target']['path'])] = sample_channel(doc,binary,animation,channel,time)
    for i,q in (rotations or {}).items(): values[(i,'rotation')]=q
    worlds={}
    def matrix(i):
        if i in worlds:return worlds[i]
        n=doc['nodes'][i]
        if 'matrix' in n:
            assert not any(k[0]==i for k in values)
            local=np.array(n['matrix']).reshape(4,4).T
        else:
            local=np.eye(4)
            q=values.get((i,'rotation'),n.get('rotation',[0,0,0,1]))
            scale=values.get((i,'scale'),n.get('scale',[1,1,1]))
            local[:3,:3]=Rotation.from_quat(q).as_matrix()@np.diag(scale)
            local[:3,3]=values.get((i,'translation'),n.get('translation',[0,0,0]))
        worlds[i]=matrix(parents[i])@local if i in parents else local
        return worlds[i]
    for i in range(len(doc['nodes'])):matrix(i)
    return worlds,parents

def palm_normal(doc, rest, posed, side='Right'):
    rig=next(n for n in doc['nodes'] if n.get('name')=='Rig')
    # These source-fit landmarks were authored in Blender (Z-up). glTF is Y-up.
    x,y,z=rig['extras']['palm_normal_'+side]
    normal=np.array([x,z,-y])
    hand=next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='mixamorig:'+side+'Hand')
    result=(posed[hand]@np.linalg.inv(rest[hand]))[:3,:3]@normal
    return result/np.linalg.norm(result)
