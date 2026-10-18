"""Pure bake support extracted from the accepted garment field writers.

This module consumes solved fields; it does not run the offline collision QP.
Periodic scalar and batch implementations intentionally retain their original
operation order for the two historical bake formats.
"""
import hashlib
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from prepare_local_garments import read, colours
from motion_math import world_matrices
from audit_native_garment_surfaces import support_cloth_union


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def actual_skin_basis(state, row):
    worlds, _ = world_matrices(state['d'], state['b'])
    lookup = {node.get('name'): i for i, node in enumerate(state['d']['nodes'])}
    for bone in row['bones']:
        node = lookup[bone['name'].replace('mixamorig_', 'mixamorig:')]
        worlds[node][:3, :3] = np.asarray(bone['basis']).T
        worlds[node][:3, 3] = np.asarray(bone['position'])
    matrices = np.array([worlds[joint] @ bind for joint, bind in zip(state['skin']['joints'], state['binds'])])
    B = np.zeros((len(state['positions']), 3, 3))
    for slot in range(state['joints'].shape[1]):
        B += matrices[state['joints'][:, slot], :3, :3] * state['weights'][:, slot, None, None]
    return B



def circular_weights(phases, at):
    phases = np.asarray(phases)
    assert np.all(np.diff(phases) > 0) and phases[0] >= 0 and phases[-1] < 1
    at = float(at) % 1
    right = int(np.searchsorted(phases, at, side='right'))
    left = (right - 1) % len(phases)
    right %= len(phases)
    first, second = phases[left], phases[right]
    if second <= first:
        second += 1
    if at < first:
        at += 1
    fraction = (at - first) / (second - first)
    weights = np.zeros(len(phases))
    weights[left], weights[right] = 1 - fraction, fraction
    return weights


def circular_weights_batch(phases, times):
    phases=np.asarray(phases,float)
    q=np.mod(np.asarray(times,float),1.)
    if not len(phases) or phases[0]<0 or phases[-1]>=1 or not np.all(np.diff(phases)>0):
        raise ValueError('Periodic phase keys must be unique and in [0,1)')
    n=len(phases)
    if n==1:return np.ones((len(q),1))
    extended=np.r_[phases[-1]-1,phases,phases[0]+1]
    indices=np.r_[n-1,np.arange(n),0]
    left=np.searchsorted(extended,q,side='right')-1
    fraction=(q-extended[left])/(extended[left+1]-extended[left])
    weights=np.zeros((len(q),n))
    weights[np.arange(len(q)),indices[left]]+=1-fraction
    weights[np.arange(len(q)),indices[left+1]]+=fraction
    return weights

def extend_original_curve(times, values, knot_times, shapes=None):
 times=np.asarray(times,dtype=np.float32);values=np.asarray(values,dtype=np.float32)
 missing=[np.float32(t) for t in knot_times if not np.any(abs(times-np.float32(t))<1e-7)]
 if not missing:return times.copy(),values.copy(),{'inserted_key_count':0,'old_timestamp_rows_all_retained':True,'old_key_values_exact':True,'old_weight_function_max_absolute_error':0.,'old_rest_position_function_error_bound_m':0.}
 extended=np.sort(np.r_[times,np.asarray(missing,np.float32)],kind='stable')
 ideal=np.column_stack([np.interp(extended,times,values[:,i]) for i in range(values.shape[1])])
 actual=ideal.astype(np.float32)
 for at,value in zip(times,values):
  actual[np.flatnonzero(extended==at)[0]]=value
 error=actual.astype(float)-ideal
 rest_max=0.
 if shapes is not None:
  for row in error:
   ids=np.flatnonzero(row)
   if len(ids):rest_max=max(rest_max,float(np.linalg.norm(sum(float(row[i])*shapes[i] for i in ids),axis=1).max()))
 # Rounded interpolation differs by <= one representable f32 step. Zero is exact.
 ulp=abs(np.spacing(ideal.astype(np.float32)).astype(float))
 ratio=np.divide(abs(error),ulp,out=np.zeros_like(error),where=ulp>0)
 return extended,actual,{'inserted_key_count':len(extended)-len(times),'old_timestamp_rows_all_retained':bool(np.all(np.isin(times,extended))),'old_key_values_exact':True,'old_weight_function_max_absolute_error':float(abs(error).max()),'maximum_f32_ulp_error':float(ratio.max()),'old_rest_position_function_error_bound_m':rest_max,'proof':'Difference is piecewise linear on the union of old/new knots; maximum per-component and norm bounds occur at knots.'}

def complete_source_domain(state, colour):
    full, original = support_cloth_union(state)
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    faces = read(state['d'],state['b'],primitive['indices']).reshape(-1,3)
    rgb = colours(state['d'],state['b'],primitive)
    r,g,b = rgb.T
    x,y,z = state['positions'].T
    height = float(y.max())
    if colour == 'blue':
        paint = (b>r*1.08)&(b>g*1.04)&(rgb.sum(1)<1.)
    elif colour == 'yellow':
        paint = (r>g*.95)&(r<g*1.9)&(b<g*.65)&(g>.18)
    else:
        raise ValueError('Supported painted-cloth policies are blue and yellow')
    # Identical physical UV-copy groups share their independent paint label.
    pairs = cKDTree(state['positions']).query_pairs(1e-6,output_type='ndarray')
    same = np.all(state['joints'][pairs[:,0]]==state['joints'][pairs[:,1]],axis=1)
    same &= np.max(abs(state['weights'][pairs[:,0]]-state['weights'][pairs[:,1]]),axis=1)<1e-7
    pairs = pairs[same]
    while True:
        before = int(paint.sum())
        chosen = pairs[paint[pairs[:,0]]|paint[pairs[:,1]]]
        paint[chosen.ravel()] = True
        if int(paint.sum())==before:break
    paint &= (abs(x)<.24*height)&(y>.20*height)&(y<.59*height)
    painted_faces = faces[np.all(paint[faces],axis=1)]
    painted_vertices = np.unique(painted_faces)
    overlap = np.intersect1d(painted_vertices,state['body'])
    if len(overlap):raise ValueError('Complete painted triangles overlap original fixed body anchors')
    worlds,_ = world_matrices(state['d'],state['b'])
    hip = next(i for i,n in enumerate(state['d']['nodes']) if n.get('name')=='mixamorig:Hips')
    hip_z = float(worlds[hip][2,3])
    old = {tuple(f):side for side in ['front','back'] for f in full[side]}
    out = {side:{tuple(f) for f in full[side]} for side in ['front','back']}
    for triangle in painted_faces:
        key=tuple(triangle)
        if key in old:continue
        side='front' if float(state['positions'][triangle,2].mean())>hip_z else 'back'
        out[side].add(key)
    out={side:np.asarray(sorted(rows),int) for side,rows in out.items()}
    mask=np.zeros(len(state['positions']),bool)
    mask[painted_vertices]=True
    for i in state['local']:mask |= np.linalg.norm(state['shapes'][i],axis=1)>0
    before_uv_closure=int(mask.sum())
    while True:
        before=int(mask.sum())
        chosen=pairs[mask[pairs[:,0]]|mask[pairs[:,1]]]
        mask[chosen.ravel()]=True
        if int(mask.sum())==before:break
    if np.any(mask[state['body']]):raise ValueError('Complete physical UV source group intersects fixed body')
    return out,mask,{
        'original_sided_union':original,'complete_painted_source_triangles':len(painted_faces),
        'complete_painted_source_vertices':len(painted_vertices),
        'expanded_sided_union':{s:len(f) for s,f in out.items()},
        'added_sided_source_faces':{s:len(out[s])-len(full[s]) for s in out},
        'baked_source_movable_vertices':int(mask.sum()),'fixed_body_overlap':0,'added_physical_UV_copy_vertices':int(mask.sum())-before_uv_closure,
        'extra_domain_rule':__doc__,'hips_rest_z_m':hip_z,
    }
