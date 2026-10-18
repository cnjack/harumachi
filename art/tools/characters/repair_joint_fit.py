"""Fit exterior elbow/finger pivots without rebuilding a character or its mesh.

Input/output directories are separate so this stage can precede motion/garment
stages. Rest changes rebase local animation TRS and inverse bind matrices. The
original positions, UVs, indices, images and morph targets remain byte-identical.
A direct-weight count alone is deliberately insufficient: verification exercises
all finger joints independently and checks meaningful displacement and locality.
"""
from pathlib import Path
import argparse, copy, hashlib, json, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
from scipy.spatial import cKDTree
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components, dijkstra
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from repair_head_neck import read, append, save
from glb_io import load, durations
from motion_math import world_matrices

P = 'mixamorig:'
PEOPLE = ['sora', 'mio', 'ren', 'haru', 'tanaka', 'aoi', 'kazuko']
FINGERS = ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']
HANDS = {'sora': ['Left', 'Right'], 'mio': ['Left', 'Right'],
         'ren': ['Left','Right'], 'tanaka': ['Left','Right'], 'aoi': ['Right']}
RAYS = [(1,.137,.271),(-1,.187,.219),(.157,1,.317),(.271,-1,.133),(.337,.191,1),(.173,.319,-1)]


def parts(doc, blob, worlds=None):
    worlds = worlds or world_matrices(doc, blob)[0]
    result = []
    for ni, node in enumerate(doc['nodes']):
        if 'mesh' not in node or 'skin' not in node: continue
        skin = doc['skins'][node['skin']]; joints = skin['joints']
        ibm = read(doc, blob, skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        transforms = np.array([worlds[j] @ m for j,m in zip(joints,ibm)])
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            attrs = primitive['attributes']; raw = read(doc,blob,attrs['POSITION'])
            ids = np.concatenate([read(doc,blob,attrs[k]) for k in ['JOINTS_0','JOINTS_1'] if k in attrs],axis=1).astype(int)
            weights = np.concatenate([read(doc,blob,attrs[k]) for k in ['WEIGHTS_0','WEIGHTS_1'] if k in attrs],axis=1)
            xyz = np.sum(np.einsum('nvij,nj->nvi',transforms[ids],np.c_[raw,np.ones(len(raw))])*weights[:,:,None],axis=1)[:,:3]
            dense = np.zeros((len(raw),len(joints)))
            np.add.at(dense,(np.repeat(np.arange(len(raw)),ids.shape[1]),ids.ravel()),weights.ravel())
            result.append({'node':ni,'name':node.get('name',''), 'primitive':primitive, 'raw':raw, 'xyz':xyz,
                           'faces':read(doc,blob,primitive['indices']).reshape(-1,3), 'ids':ids,
                           'weights':weights, 'dense':dense, 'joints':joints,
                           'names':[doc['nodes'][j].get('name','') for j in joints]})
    return result


def triangles(ps):
    return np.concatenate([p['xyz'][p['faces']] for p in ps if not p['name'].startswith('HiddenArm')])


def ray_inside(tri, p, direction):
    direction=np.array(direction,float);direction/=np.linalg.norm(direction)
    e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(direction,e2)
    det=np.sum(e1*h,axis=1);keep=abs(det)>1e-10;inv=1/det[keep]
    s=p-tri[keep,0];u=np.sum(s*h[keep],axis=1)*inv;q=np.cross(s,e1[keep]);v=q@direction*inv;t=np.sum(e2[keep]*q,axis=1)*inv
    t=np.sort(t[(u>=0)&(v>=0)&(u+v<=1)&(t>1e-7)])
    return bool(len(t[np.r_[True,np.diff(t)>1e-6]])%2) if len(t) else False



def surface_line_center(tri, point, direction):
    direction=direction/np.linalg.norm(direction);origin=point-direction*3.0
    e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(direction,e2)
    det=np.sum(e1*h,axis=1);keep=abs(det)>1e-10;inv=1/det[keep]
    ss=origin-tri[keep,0];u=np.sum(ss*h[keep],axis=1)*inv;q=np.cross(ss,e1[keep]);v=q@direction*inv;t=np.sum(e2[keep]*q,axis=1)*inv
    t=np.sort(t[(u>=0)&(v>=0)&(u+v<=1)&(t>0)])
    if not len(t):return None
    t=t[np.r_[True,np.diff(t)>1e-6]];choices=[]
    for a,b in zip(t[:-1],t[1:]):
        if b-a>.065:continue
        candidate=origin+direction*(a+b)*.5
        if np.linalg.norm(candidate-point)<.045 and sum(ray_inside(tri,candidate,r) for r in RAYS)>=5:choices.append((np.linalg.norm(candidate-point),candidate))
    return min(choices,key=lambda x:x[0])[1] if choices else None


def plane_segments(tri, pivot, normal):
    normal=normal/np.linalg.norm(normal);distance=(tri-pivot)@normal
    keep=(distance.min(axis=1)<0)&(distance.max(axis=1)>0);tt=tri[keep];dd=distance[keep]
    segments=[]
    for t,d in zip(tt,dd):
        hit=[]
        for a,b in [(0,1),(1,2),(2,0)]:
            if d[a]*d[b]<0: hit.append(t[a]+(t[b]-t[a])*d[a]/(d[a]-d[b]))
        if len(hit)==2: segments.append(hit)
    return np.asarray(segments)


def section_loops(segments):
    """Connected cut rings, including UV seam duplicates, rather than one hull."""
    if not len(segments): return []
    points=segments.reshape(-1,3);tree=cKDTree(points);links=tree.query_pairs(2e-5)
    parent=np.arange(len(points))
    def root(i):
        while parent[i]!=i: parent[i]=parent[parent[i]];i=parent[i]
        return i
    def union(a,b): parent[root(a)]=root(b)
    for i in range(0,len(points),2): union(i,i+1)
    for a,b in links: union(a,b)
    groups={}
    for i,p in enumerate(points): groups.setdefault(root(i),[]).append(p)
    return [np.array(v) for v in groups.values() if len(v)>=6]


def elbow_target(ps,world,names,side,estimate=None):
    shoulder=world[names[P+side+'Arm']][:3,3];wrist=world[names[P+side+'Hand']][:3,3]
    old=world[names[P+side+'ForeArm']][:3,3];axis=wrist-shoulder;tri=triangles(ps)
    probe=old if estimate is None else estimate
    loops=section_loops(plane_segments(tri,probe,axis))
    candidates=[]
    for loop in loops:
        # The local arm ring is a connected shell component. The torso must
        # never enter its convex hull merely because it is within a radius.
        center=(loop.min(axis=0)+loop.max(axis=0))*.5
        if center[0]*old[0]<0 or np.linalg.norm(center-old)>.20: continue
        direction=axis/np.linalg.norm(axis);center-=direction*np.dot(center-probe,direction)
        if all(ray_inside(tri,center,r) for r in RAYS):candidates.append((np.linalg.norm(center-probe),loop,center))
    assert candidates, 'No elbow shell section'
    _,loop,center=min(candidates,key=lambda x:x[0])
    # Box center is projected back onto the exact plane (axis coordinate fixed).
    axis/=np.linalg.norm(axis);center-=axis*np.dot(center-probe,axis)
    assert all(ray_inside(tri,center,r) for r in RAYS), 'Elbow center not enclosed'
    return center,{'old_world_m':old.tolist(),'new_world_m':center.tolist(),
                   'offset_m':float(np.linalg.norm(center-old)),'cut_ring_points':len(loop),
                   'all_six_rays_inside':True}


def hand_frame(doc,world,names,side,cloud=None):
    wrist=world[names[P+side+'Hand']][:3,3]
    x,y,z=next(n for n in doc['nodes'] if n.get('name')=='Rig')['extras']['palm_normal_'+side]
    normal=np.array([x,z,-y]);normal/=np.linalg.norm(normal)
    if cloud is not None:
        fitted=np.linalg.svd(cloud-cloud.mean(axis=0),full_matrices=False)[2][-1]
        if fitted@normal<0:fitted*=-1
        if fitted@normal<math.cos(math.radians(12)):normal=fitted
    axis=world[names[P+side+'HandMiddle2']][:3,3]-wrist
    axis-=normal*np.dot(axis,normal);axis/=np.linalg.norm(axis)
    cross=np.cross(axis,normal);cross/=np.linalg.norm(cross)
    return wrist,axis,cross,normal


def hand_cloud(ps,side):
    result=[]
    for p in ps:
        fam=p['dense'][:,[i for i,n in enumerate(p['names']) if n.startswith(P+side+'Hand')]].sum(axis=1)
        result.extend(p['xyz'][fam>.5])
    return np.asarray(result)


def fit_fingers(doc,ps,world,names,side):
    wrist,axis,cross,normal=hand_frame(doc,world,names,side,hand_cloud(ps,side))
    origin=wrist+axis*.025;size=1024;center=size//2;scale=4000
    canvas=Image.new('L',(size,size));draw=ImageDraw.Draw(canvas)
    for p in ps:
        fam=p['dense'][:,[i for i,n in enumerate(p['names']) if n.startswith(P+side+'Hand')]].sum(axis=1)
        xy=np.c_[(p['xyz']-origin)@cross,(p['xyz']-origin)@axis]*scale+center
        for face in p['faces'][(fam[p['faces']]>.5).all(axis=1)]:draw.polygon([tuple(v) for v in xy[face]],fill=255)
    mask=np.array(canvas)>0;angles=np.linspace(-np.pi*.61,np.pi*.61,1757);ray=np.linspace(0,.18,720)
    px=(center+np.sin(angles)[:,None]*ray*scale).astype(int);py=(center+np.cos(angles)[:,None]*ray*scale).astype(int)
    valid=(px>=0)&(px<size)&(py>=0)&(py<size)
    inside=mask[np.clip(py,0,size-1),np.clip(px,0,size-1)]&valid
    envelope=gaussian_filter1d((inside*ray).max(axis=1),5)
    peaks,properties=find_peaks(envelope,prominence=.0027,distance=100)
    forward=abs(angles[peaks])<np.radians(100)
    peaks=peaks[forward];properties['prominences']=properties['prominences'][forward]
    if len(peaks)>5:
        peaks=np.sort(peaks[np.argsort(properties['prominences'])[-5:]])
    assert len(peaks)==5, f'{side}: expected five independently visible digits, got {len(peaks)}'
    order=FINGERS if side=='Left' else FINGERS[::-1]
    cloud=hand_cloud(ps,side);tri=triangles(ps);targets={};report=[]
    for finger,k in zip(order,peaks):
        direction=np.sin(angles[k])*cross+np.cos(angles[k])*axis
        tip=origin+direction*envelope[k]
        planar=np.c_[(cloud-tip)@cross,(cloud-tip)@axis]
        cap=cloud[np.linalg.norm(planar,axis=1)<.006]
        if len(cap):tip+=normal*np.median((cap-tip)@normal)
        # A digit fans out from the palm, not from the wrist. Its radial ray
        # starts at the measured palm center. Using the wrist-to-tip chord can
        # cut a neighboring finger or a web gap in a splayed source hand.
        fraction=[.15,.56,.83] if finger=='Thumb' else [.42,.70,.88]
        lateral=np.cross(direction,normal);lateral/=np.linalg.norm(lateral)
        heads=[]
        for fi,f in enumerate(fraction):
            estimate=origin+direction*envelope[k]*f
            choices=[]
            for along in [0,.002,-.002,.004,-.004]:
                for offset in [0,.002,-.002,.004,-.004,.006,-.006]:
                    probe=estimate+direction*along+lateral*offset
                    q=surface_line_center(tri,probe,normal)
                    if q is not None:choices.append((np.hypot(along,offset)+.03*abs((q-probe)@normal),q))
                if choices and along==0:break
            assert choices, f'No local enclosed {side} {finger}{fi+1} palm-ray center'
            q=min(choices,key=lambda x:x[0])[1]
            assert sum(ray_inside(tri,q,r) for r in RAYS)>=5
            heads.append(q);targets[names[P+side+'Hand'+finger+str(fi+1)]]=q
        segments=np.linalg.norm(np.diff(np.array(heads),axis=0),axis=1)
        assert segments.max()<.055 and segments.min()>.003, f'{side} {finger}: implausible segment length'
        assert max(np.linalg.norm(v-wrist) for v in heads)<.16, f'{side} {finger}: nonlocal joint'
        report.append({'finger':finger,'angle_degrees':float(np.degrees(angles[k])),
                       'tip_world_m':tip.tolist(),'joints_world_m':[v.tolist() for v in heads]})
    return targets, report


def aligned_matrix(old_world, old_axis, new_axis, point):
    old_axis=old_axis/np.linalg.norm(old_axis);new_axis=new_axis/np.linalg.norm(new_axis)
    rotation=Rotation.align_vectors([new_axis],[old_axis])[0].as_matrix()
    matrix=old_world.copy();matrix[:3,:3]=rotation@matrix[:3,:3];matrix[:3,3]=point
    return matrix


def rebase(doc,blob,old,new):
    """Preserve rest surface while changing rotation centers and bone bases."""
    parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    changed={};old_local={};new_local={}
    for i,node in enumerate(doc['nodes']):
        a=np.linalg.inv(old[parents[i]])@old[i] if i in parents else old[i]
        z=np.linalg.inv(new[parents[i]])@new[i] if i in parents else new[i]
        if np.max(abs(a-z))<1e-10:continue
        assert 'matrix' not in node
        old_local[i]=a;new_local[i]=z;changed[i]=True
        scale=np.linalg.norm(z[:3,:3],axis=0)
        node['translation']=z[:3,3].tolist();node['rotation']=Rotation.from_matrix(z[:3,:3]/scale).as_quat().tolist()
        node['scale']=scale.tolist()
    for animation in doc.get('animations',[]):
        assert len({c['sampler'] for c in animation['channels']})==len(animation['channels']), 'Shared transform sampler requires per-channel cloning'
        for channel in animation['channels']:
            i=channel['target']['node'];path=channel['target']['path']
            if i not in changed or path not in ['translation','rotation']:continue
            sampler=animation['samplers'][channel['sampler']]
            values=read(doc,blob,sampler['output']).astype(float)
            cubic=sampler.get('interpolation')=='CUBICSPLINE'
            if path=='translation':
                delta=new_local[i][:3,3]-old_local[i][:3,3]
                if cubic:values[1::3]+=delta
                else:values+=delta
            else:
                assert not cubic, 'Rotation spline rebasing needs quaternion tangents'
                a=old_local[i][:3,:3];a/=np.linalg.norm(a,axis=0)
                z=new_local[i][:3,:3];z/=np.linalg.norm(z,axis=0)
                correction=Rotation.from_matrix(z) * Rotation.from_matrix(a).inv()
                values=(correction*Rotation.from_quat(values)).as_quat()
                # Do not insert a quaternion sign discontinuity into a track.
                for k in range(1,len(values)):
                    if values[k]@values[k-1]<0:values[k]*=-1
            sampler['output']=append(doc,blob,sampler['output'],values)
    for skin in doc['skins']:
        matrices=read(doc,blob,skin['inverseBindMatrices']).astype(float)
        for j,node in enumerate(skin['joints']):
            # A hand-only stage must not round or reserialize a body's bind
            # through an unnecessary inverse/multiply round trip.
            if np.array_equal(new[node],old[node]):continue
            matrices[j]=(np.linalg.inv(new[node])@old[node]@matrices[j].reshape(4,4).T).T.reshape(-1)
        skin['inverseBindMatrices']=append(doc,blob,skin['inverseBindMatrices'],matrices)
    return list(changed)


def rebuild_hand_weights(doc,blob,ps,world,names,side,fit_records):
    wrist,axis,cross,normal=hand_frame(doc,world,names,side,hand_cloud(ps,side))
    chains=[]
    for finger in FINGERS:
        nodes=[names[P+side+'Hand'+finger+str(k)] for k in [1,2,3]]
        q=np.array([world[i][:3,3] for i in nodes]);direction=q[2]-q[1];direction/=np.linalg.norm(direction)
        tip=q[2]+direction*np.linalg.norm(q[2]-q[1])*.78
        chains.append((finger,nodes,np.r_[q,tip[None,:]]))
    changed=0
    for p in ps:
        dense=p['dense'].copy();family=[i for i,n in enumerate(p['names']) if n.startswith(P+side+'Hand')]
        mass=dense[:,family].sum(axis=1);keep=mass>.5
        if not np.any(keep):continue
        points=p['xyz'][keep];desired=np.zeros((len(points),len(p['joints'])))
        # Closest complete digit segment locates each finger family. Segment
        # coordinates, rather than nearest joint alone, retain distal phalanges.
        distances=[];coordinates=[]
        for finger,nodes,q in chains:
            local_dist=[];local_u=[]
            for i in range(3):
                segment=q[i+1]-q[i];u=np.clip((points-q[i])@segment/(segment@segment),0,1)
                hit=q[i]+u[:,None]*segment
                local_dist.append(np.linalg.norm(points-hit,axis=1));local_u.append(i+u)
            local_dist=np.array(local_dist).T;best=local_dist.argmin(axis=1)
            distances.append(local_dist[np.arange(len(points)),best]);coordinates.append(np.array(local_u).T[np.arange(len(points)),best])
        distances=np.array(distances).T
        # Anatomical branch identity comes from its fan angle in the palm.
        # Three-dimensional nearest-bone distance alone can assign two curled
        # neighboring fingers to one chain. Distal ray sectors stay separate;
        # actual surface adjacency smooths only the connected web transitions.
        palm_origin=wrist+axis*.025
        ray=points-palm_origin;ray-=np.outer(ray@normal,normal)
        ray/=np.maximum(np.linalg.norm(ray,axis=1)[:,None],1e-12)
        directions=[]
        for finger,nodes,q in chains:
            direction=q[3]-palm_origin;direction-=normal*np.dot(direction,normal);direction/=np.linalg.norm(direction);directions.append(direction)
        digit=(ray@np.array(directions).T).argmax(axis=1)
        # Surface geodesics determine which physical finger owns each vertex.
        # A palm-plane Voronoi partition can split the front/back of a thick,
        # curled finger between neighbors even when the tip rays are distinct.
        local_map=np.full(len(p['xyz']),-1,dtype=int);local_map[keep]=np.arange(len(points))
        hand_edges=np.concatenate([p['faces'][:,[0,1]],p['faces'][:,[1,2]],p['faces'][:,[2,0]]])
        hand_edges=local_map[hand_edges[keep[hand_edges].all(axis=1)]]
        seam_pairs=np.array(list(cKDTree(points).query_pairs(2e-6)),dtype=int).reshape(-1,2)
        if len(seam_pairs):hand_edges=np.concatenate([hand_edges,seam_pairs])
        hand_edges=np.unique(np.sort(hand_edges,axis=1),axis=0)
        edge_length=np.maximum(np.linalg.norm(points[hand_edges[:,0]]-points[hand_edges[:,1]],axis=1),1e-8)
        geodesic_graph=csr_matrix((np.r_[edge_length,edge_length],(np.r_[hand_edges[:,0],hand_edges[:,1]],np.r_[hand_edges[:,1],hand_edges[:,0]])),shape=(len(points),len(points)))
        seed_points=np.array([next(r['tip_world_m'] for r in fit_records if r['finger']==f) for f in FINGERS])
        seeds=cKDTree(points).query(seed_points)[1]
        assert len(set(seeds))==5, 'Fingertip seeds are not distinct'
        travel=dijkstra(geodesic_graph,directed=False,indices=seeds)
        connected=np.isfinite(travel).any(axis=0);digit[connected]=travel[:,connected].argmin(axis=0)
        # Preserve the palm's rigid area. Root transition spans 1 cm, with the
        # first joint at its center; all three phalanges have finite core areas.
        hand=p['joints'].index(names[P+side+'Hand'])
        desired[:,hand]=1
        for di,(finger,nodes,q) in enumerate(chains):
            chosen=digit==di
            if not np.any(chosen):continue
            loc=np.where(chosen)[0];pts=points[chosen];u=coordinates[di][chosen]
            direction=q[3]-wrist;direction-=normal*np.dot(direction,normal);direction/=np.linalg.norm(direction)
            longitudinal=(pts-q[0])@direction
            blend=np.clip((longitudinal+.006)/.012,0,1);blend=blend*blend*(3-2*blend)
            # A geodesic finger region also includes part of the heel/palm.
            # Keep flesh far outside the actual digit tube on the hand bone;
            # otherwise a lateral palm bulge bends as an extra little finger.
            distance=distances[loc,di];distal=distance[u>.8]
            radius=float(np.clip(np.quantile(distal,.90) if len(distal) else .01,.004,.018))
            radial=np.clip((radius*2.0-distance)/(radius*.8),0,1);radial=radial*radial*(3-2*radial)
            blend*=radial
            # Smooth 25%-wide transitions centered on each anatomical knuckle.
            # Segment midpoint fully belongs to that phalanx; PIP and DIP share
            # weights only in the corresponding local neighborhoods.
            weight=np.zeros((len(pts),3));weight[:,0]=1
            for joint in [1,2]:
                t=np.clip((u-(joint-.24))/.48,0,1);t=t*t*(3-2*t)
                weight[:,:joint]*=(1-t[:,None]);weight[:,joint]+=t
            desired[loc]=0;desired[loc,hand]=1-blend
            for k,node in enumerate(nodes):desired[loc,p['joints'].index(node)]=blend*weight[:,k]
        # Smooth over real triangle adjacency, joining duplicated UV seams by
        # coincident position. Nearby but disconnected fingers do not exchange
        # weights through a Euclidean blur. This removes hard web boundaries.
        local_indices=np.full(len(p['xyz']),-1,dtype=int);local_indices[keep]=np.arange(len(points))
        edge=np.concatenate([p['faces'][:,[0,1]],p['faces'][:,[1,2]],p['faces'][:,[2,0]]])
        edge=edge[keep[edge].all(axis=1)];edge=local_indices[edge]
        seams=np.array(list(cKDTree(points).query_pairs(2e-6)),dtype=int).reshape(-1,2)
        if len(seams):edge=np.concatenate([edge,seams])
        edge=np.unique(np.sort(edge,axis=1),axis=0);row=np.r_[edge[:,0],edge[:,1]];col=np.r_[edge[:,1],edge[:,0]]
        adjacency=csr_matrix((np.ones(len(row)),(row,col)),shape=(len(points),len(points)))
        degree=np.maximum(np.asarray(adjacency.sum(axis=1)),1)
        seam_rows=np.r_[seams[:,0],seams[:,1]] if len(seams) else np.array([],dtype=int)
        seam_cols=np.r_[seams[:,1],seams[:,0]] if len(seams) else np.array([],dtype=int)
        seam_graph=csr_matrix((np.ones(len(seam_rows)),(seam_rows,seam_cols)),shape=(len(points),len(points)))
        component_count,labels=connected_components(seam_graph,directed=False)
        component_size=np.bincount(labels,minlength=component_count)
        for iteration in range(8):
            desired=.62*desired+.38*(adjacency@desired)/degree
            sums=np.zeros((component_count,desired.shape[1]));np.add.at(sums,labels,desired)
            desired=sums[labels]/component_size[labels,None]
        desired/=desired.sum(axis=1,keepdims=True)
        dense[np.ix_(keep,family)]=desired[:,family]*mass[keep,None]
        family_mask=np.zeros(len(p['joints']),dtype=bool);family_mask[family]=True
        for vertex in np.where(keep)[0]:
            other_count=np.count_nonzero((dense[vertex]>0)&(~family_mask))
            available=p['ids'].shape[1]-other_count
            assert available>=1
            selected=np.array(family)[np.argsort(dense[vertex,family])[-available:]]
            values=dense[vertex,selected].copy();values*=mass[vertex]/max(values.sum(),1e-30)
            dense[vertex,family]=0;dense[vertex,selected]=values
        # Other influences survive, including forearm wrist blends. Existing
        # duplicated UV vertices receive identical weights by equal positions.
        ids=p['ids'].copy();weights=p['weights'].copy()
        order=np.argsort(dense[keep],axis=1)[:,-ids.shape[1]:][:,::-1]
        ww=np.take_along_axis(dense[keep],order,axis=1);ww/=ww.sum(axis=1,keepdims=True)
        ids[keep]=order;weights[keep]=ww
        attrs=p['primitive']['attributes']
        for k in range(ids.shape[1]//4):
            attrs['JOINTS_'+str(k)]=append(doc,blob,attrs['JOINTS_'+str(k)],ids[:,4*k:4*k+4])
            attrs['WEIGHTS_'+str(k)]=append(doc,blob,attrs['WEIGHTS_'+str(k)],weights[:,4*k:4*k+4])
        p['dense']=dense;p['ids']=ids;p['weights']=weights
        changed+=int(keep.sum())
    return changed


def diagnose(doc,blob):
    world,_=world_matrices(doc,blob);ps=parts(doc,blob,world);names={n.get('name'):i for i,n in enumerate(doc['nodes'])};tri=triangles(ps)
    row={'elbows':{},'fingers':{}}
    for side in ['Left','Right']:
        pivot=world[names[P+side+'ForeArm']][:3,3]
        row['elbows'][side]={'pivot_world_m':pivot.tolist(),'inside_ray_count':sum(ray_inside(tri,pivot,r) for r in RAYS)}
        for finger in FINGERS:
            for k in [1,2,3]:
                name=P+side+'Hand'+finger+str(k);i=names[name];stats={'weight_sum':0.,'vertices_over_025':0,'max_displacement_30deg_m':0.,'vertices_moving_over_1mm':0}
                # Independent bend in this joint's anatomical curl plane. Child
                # joints follow by hierarchy, as in actual skinning.
                q=np.array(doc['nodes'][i].get('rotation',[0,0,0,1]));curl=Rotation.from_rotvec([math.radians(30),0,0])
                posed=world_matrices(doc,blob,rotations={i:(Rotation.from_quat(q)*curl).as_quat()})[0]
                bent=parts(doc,blob,posed)
                for p,z in zip(ps,bent):
                    if i not in p['joints']:continue
                    weights=p['dense'][:,p['joints'].index(i)]
                    movement=np.linalg.norm(p['xyz']-z['xyz'],axis=1)
                    stats['weight_sum']+=float(weights.sum());stats['vertices_over_025']+=int((weights>.25).sum())
                    stats['max_displacement_30deg_m']=max(stats['max_displacement_30deg_m'],float(movement.max()))
                    stats['vertices_moving_over_1mm']+=int((movement>.001).sum())
                row['fingers'][name]=stats
    return row


def shoulder_target(ps, world, names, side, factors=(1.14,1.28,1.42),maximum_drop=.08):
    """Extrapolate the actual outer upper-arm tube into the shoulder ball."""
    tri=triangles(ps);old=world[names[P+side+'Arm']][:3,3];sign=np.sign(old[0]);samples=[]
    for fraction in factors:
        probe=old.copy();probe[0]=old[0]*fraction
        loops=section_loops(plane_segments(tri,probe,np.array([1.,0.,0.])))
        choices=[]
        for loop in loops:
            center=(loop.min(axis=0)+loop.max(axis=0))*.5
            if center[1]<old[1]-maximum_drop or np.ptp(loop[:,1])>.35 or np.ptp(loop[:,2])<.07:continue
            choices.append((abs(center[1]-old[1]),loop,center))
        assert choices, 'Shoulder upper-arm section missing'
        _,loop,center=min(choices,key=lambda x:x[0]);samples.append(center)
    samples=np.array(samples);desired=old.copy()
    for axis in [1,2]:desired[axis]=np.polyval(np.polyfit(samples[:,0],samples[:,axis],1),old[0])
    assert all(ray_inside(tri,desired,r) for r in RAYS), 'Shoulder fit not enclosed'
    return desired,{'old_world_m':old.tolist(),'new_world_m':desired.tolist(),'sample_centers_m':samples.tolist(),'old_inside_ray_count':sum(ray_inside(tri,old,r) for r in RAYS),'new_inside_ray_count':6,'all_six_rays_inside':True}


def leg_targets(ps,world,names,who):
    """Measure separate pants/shoe shell sections; do not guess hidden anatomy.

    Knee/ankle height is retained. Hip depth comes from a line through the broad
    pelvis contour at that side's original X, excluding small pockets and trim.
    """
    targets={};report={};tri=triangles(ps)
    for side in ['Left','Right']:
        for joint in (['UpLeg','Leg','Foot'] if who!='kazuko' else ['Foot']):
            node=names[P+side+joint];old=world[node][:3,3]
            loops=section_loops(plane_segments(tri,old,np.array([0.,1.,0.])))
            if joint=='UpLeg':
                broad=[l for l in loops if np.ptp(l[:,0])>.25 and l[:,0].min()<old[0]<l[:,0].max()]
                if not broad:continue
                loop=max(broad,key=lambda l:np.ptp(l[:,0]));z=[]
                # Intersect connected contour segments with x=hip.x. Points
                # are not ordered, so use a narrow X slab and its front/back.
                use=loop[abs(loop[:,0]-old[0])<.012]
                if len(use)<4:continue
                desired=old.copy();desired[2]=(use[:,2].min()+use[:,2].max())*.5
                if abs(desired[2]-old[2])<.025:continue
            else:
                candidates=[]
                for loop in loops:
                    center=(loop.min(axis=0)+loop.max(axis=0))*.5
                    if center[0]*old[0]<=0 or len(loop)<80 or np.ptp(loop[:,0])<.025:continue
                    if np.ptp(loop[:,0])>.30:continue
                    candidates.append((float(np.linalg.norm(center-old)),loop,center))
                assert candidates, f'{who} {side} {joint}: separate leg ring missing'
                _,loop,desired=min(candidates,key=lambda x:x[0])
            if not all(ray_inside(tri,desired,r) for r in RAYS):
                raise AssertionError(f'{who} {side} {joint}: measured center is outside shell')
            targets[node]=desired;report[side+joint]={'old_world_m':old.tolist(),'new_world_m':desired.tolist(),'offset_m':float(np.linalg.norm(desired-old)),'section_points':len(loop),'all_six_rays_inside':True}
    return targets,report


def run(source_dir,output_dir,people,skip_hands=False,skip_body=False,ren_shoulders=False,ren_shoulders_only=False):
    assert source_dir.resolve()!=output_dir.resolve(), "Input/output directories must be distinct"
    output_dir.mkdir(parents=True,exist_ok=True);summary=[]
    for who in people:
        source=source_dir/('CH_'+who+'.glb');target=output_dir/source.name
        doc,old_blob=load(source);blob=bytearray(old_blob);old=world_matrices(doc,blob)[0]
        names={n.get('name'):i for i,n in enumerate(doc['nodes'])};ps=parts(doc,blob,old)
        print(who, 'diagnose original', flush=True);before=diagnose(doc,blob);(output_dir/(who+'-source-audit.json')).write_text(json.dumps(before,indent=2)+'\n');new={i:m.copy() for i,m in old.items()};report={'character':who,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'before':before,'elbow_fit':{},'hand_fit':{}}
        report['shoulder_fit']={};report['leg_fit']={}
        if not skip_body and who=='tanaka':
            for side in ['Left','Right']:
                point,rr=shoulder_target(ps,old,names,side);report['shoulder_fit'][side]=rr
                new[names[P+side+'Arm']][:3,3]=point
        if ren_shoulders and who=='ren' and (not skip_body or ren_shoulders_only):
            for side in ['Left','Right']:
                point,rr=shoulder_target(ps,old,names,side,factors=(1.05,1.10,1.15),maximum_drop=.15);report['shoulder_fit'][side]=rr
                arm=names[P+side+'Arm'];fore=names[P+side+'ForeArm']
                new[arm]=aligned_matrix(old[arm],old[fore][:3,3]-old[arm][:3,3],old[fore][:3,3]-point,point)
        for side in (['Left','Right'] if not skip_body and who in ['sora','tanaka'] else []):
            arm=names[P+side+'Arm'];fore=names[P+side+'ForeArm'];hand=names[P+side+'Hand']
            estimate=(new[arm][:3,3]+old[hand][:3,3])*.5 if who=='tanaka' else None
            center,rr=elbow_target(ps,new,names,side,estimate);report['elbow_fit'][side]=rr
            new[arm]=aligned_matrix(old[arm],old[fore][:3,3]-old[arm][:3,3],center-new[arm][:3,3],new[arm][:3,3])
            new[fore]=aligned_matrix(old[fore],old[hand][:3,3]-old[fore][:3,3],old[hand][:3,3]-center,center)
            twist=names.get('TWIST_'+side)
            if twist is not None:new[twist]=new[fore]@np.linalg.inv(old[fore])@old[twist]
        if not skip_body and who in ['sora','ren','aoi','tanaka','kazuko']:
            leg_points,rr=leg_targets(ps,old,names,who);report['leg_fit']=rr
            for side in ['Left','Right']:
                chain=[names[P+side+j] for j in ['UpLeg','Leg','Foot']]
                for k,node in enumerate(chain):
                    child=chain[k+1] if k<2 else None
                    if node not in leg_points and child not in leg_points:continue
                    point=leg_points.get(node,old[node][:3,3])
                    if child:
                        desired_child=leg_points.get(child,old[child][:3,3])
                        new[node]=aligned_matrix(old[node],old[child][:3,3]-old[node][:3,3],desired_child-point,point)
                    else:new[node][:3,3]=point
        for side in ([] if skip_hands else HANDS.get(who,[])):
            targets,rr=fit_fingers(doc,ps,old,names,side);report['hand_fit'][side]=rr
            for finger in FINGERS:
                chain=[names[P+side+'Hand'+finger+str(k)] for k in [1,2,3]]
                tip=np.array(next(r['tip_world_m'] for r in rr if r['finger']==finger))
                for k,node in enumerate(chain):
                    child=chain[k+1] if k<2 else None
                    old_axis=old[child][:3,3]-old[node][:3,3] if child else old[node][:3,:3]@np.array([0,1,0])
                    new_axis=targets[child]-targets[node] if child else tip-targets[node]
                    new[node]=aligned_matrix(old[node],old_axis,new_axis,targets[node])
        report['rebased_nodes']=[doc['nodes'][i].get('name') for i in rebase(doc,blob,old,new)]
        for side in ([] if skip_hands else HANDS.get(who,[])):rebuild_hand_weights(doc,blob,ps,new,names,side,report['hand_fit'][side])
        print(who, 'diagnose candidate', flush=True);report['after']=diagnose(doc,blob)
        after_ps=parts(doc,blob);report['rest_surface_max_error_m']=max(float(np.linalg.norm(p['xyz']-q['xyz'],axis=1).max()) for p,q in zip(ps,after_ps))
        assert report['rest_surface_max_error_m']<2e-6, 'Rest surface shifted '+str(report['rest_surface_max_error_m'])
        # Confirm immutable geometry, not just a visually similar rest pose.
        for p in ps:
            old_d,_=load(source);ni=p['node'];old_prim=next(pr for pr in old_d['meshes'][old_d['nodes'][ni]['mesh']]['primitives'] if pr['attributes']['POSITION']==p['primitive']['attributes']['POSITION'])
            for key,value in old_prim['attributes'].items():
                if key.startswith(('JOINTS_','WEIGHTS_')):continue
                assert np.array_equal(read(old_d,old_blob,value),read(doc,blob,p['primitive']['attributes'][key]))
        (output_dir/(who+'-joint-fit.json')).write_text(json.dumps(report,indent=2)+'\n')
        failed={k:v for k,v in report['after']['fingers'].items() if v['vertices_over_025']<4 or v['vertices_moving_over_1mm']<4}
        if not skip_hands:assert not failed, 'Finger lacks meaningful independently moving region: '+str(failed)
        if not skip_body and who=='tanaka':assert all(v['inside_ray_count']==6 for v in report['after']['elbows'].values())
        rig=next(n for n in doc['nodes'] if n.get('name')=='Rig')
        # Preserve the provenance of an already-composed body/gait/cloth input.
        metadata_key='finger_fit_repair' if skip_body and not skip_hands else 'joint_fit_repair'
        rig.setdefault('extras',{})[metadata_key]={'version':2 if metadata_key=='finger_fit_repair' else 1,'hands':[] if skip_hands else HANDS.get(who,[]),'elbows':list(report['elbow_fit']),'legs':list(report['leg_fit']),'shoulders':list(report['shoulder_fit']),'rest_surface_max_error_m':report['rest_surface_max_error_m']}
        if report['rebased_nodes'] or report['hand_fit']:save(doc,blob,target)
        else:target.write_bytes(source.read_bytes())
        assert durations(source)==durations(target)
        report['output_sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
        assert hashlib.sha256(source.read_bytes()).hexdigest()==report['source_sha256'],'Input asset changed during fitting'
        (output_dir/(who+'-joint-fit.json')).write_text(json.dumps(report,indent=2)+'\n')
        summary.append(report);print(who,report['rest_surface_max_error_m'],flush=True)
    (output_dir/'joint-fit-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    upstream=source_dir/'manifest.json'
    manifest={'stage':'ren-shoulders-only' if ren_shoulders_only else ('body-joints-only' if skip_hands else ('fingers-only' if skip_body else 'body-and-fingers')),'options':{'skip_body':skip_body,'skip_hands':skip_hands,'ren_shoulders':ren_shoulders,'ren_shoulders_only':ren_shoulders_only},'input_dir':str(source_dir.resolve()),'output_dir':str(output_dir.resolve()),'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'upstream_manifest':str(upstream.resolve()) if upstream.exists() else None,'upstream_manifest_sha256':hashlib.sha256(upstream.read_bytes()).hexdigest() if upstream.exists() else None,'characters':[{'id':r['character'],'source_sha256':r['source_sha256'],'output_sha256':r['output_sha256'],'rest_surface_max_error_m':r['rest_surface_max_error_m']} for r in summary]}
    (output_dir/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return summary


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--characters',nargs='+',choices=PEOPLE,default=PEOPLE);parser.add_argument('--skip-hands',action='store_true');parser.add_argument('--skip-body',action='store_true');parser.add_argument('--ren-shoulders',action='store_true');parser.add_argument('--ren-shoulders-only',action='store_true');args=parser.parse_args()
    if args.ren_shoulders_only:args.ren_shoulders=True;args.skip_hands=True;args.skip_body=True
    run(args.input_dir,args.output_dir,args.characters,args.skip_hands,args.skip_body,args.ren_shoulders,args.ren_shoulders_only)
