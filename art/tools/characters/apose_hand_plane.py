"""Palm plane fit for neutral A-pose hands; the chosen sign faces the torso."""
import numpy as np
from mathutils import Vector

def surface_palm_normal(mesh,wrist,direction,side):
    points=np.array([v.co[:] for v in mesh.data.vertices]);anchor=np.array(wrist[:]);axis=np.array(direction[:]);delta=points-anchor
    along=delta@axis;radial=np.linalg.norm(delta-along[:,None]*axis,axis=1)
    keep=(along>.012)&(along<.095)&(radial<.040)
    cloud=points[keep]
    if len(cloud)<25:raise RuntimeError('Not enough palm geometry for '+side)
    _,_,basis=np.linalg.svd(cloud-cloud.mean(axis=0),full_matrices=False)
    normal=Vector(basis[-1]);normal=(normal-direction*normal.dot(direction)).normalized()
    inward=Vector((-1 if side=='Left' else 1,0,0));inward=(inward-direction*inward.dot(direction)).normalized()
    if normal.dot(inward)<0:normal.negate()
    return normal,len(cloud)
