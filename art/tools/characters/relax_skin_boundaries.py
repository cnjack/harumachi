"""Blend discontinuous body weights on welded topology, preserving face/fingers."""
from pathlib import Path
import argparse, json, sys
import numpy as np
from scipy.spatial.transform import Rotation
from scipy.sparse import coo_matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from repair_head_neck import read, append, save, HEAD_START
from retime_glb import load, durations


def relax(source, target, who, mesh_names=None):
    d, raw = load(source); b = bytearray(raw); parents = {c:i for i,n in enumerate(d['nodes']) for c in n.get('children', [])}; worlds = {}
    rig = next((n for n in d['nodes'] if n.get('name')=='Rig'), {})
    head_start = rig.get('extras', {}).get('head_neck_repair', {}).get('head_start_fraction', HEAD_START[who])
    def world(i):
        if i in worlds: return worlds[i]
        n = d['nodes'][i]; m = np.eye(4)
        if 'matrix' in n: m = np.array(n['matrix']).reshape(4,4).T
        else:
            m[:3,:3] = Rotation.from_quat(n.get('rotation',[0,0,0,1])).as_matrix() @ np.diag(n.get('scale',[1,1,1])); m[:3,3] = n.get('translation',[0,0,0])
        worlds[i] = world(parents[i])@m if i in parents else m
        return worlds[i]
    reports = []
    # Garments are separate mesh parts. Face/feet protection must use the whole
    # character's height, otherwise a sleeve's upper edge is mistaken for skull.
    all_points = []
    for ni, node in enumerate(d['nodes']):
        if 'mesh' not in node or 'skin' not in node: continue
        mesh = d['meshes'][node['mesh']]
        if mesh.get('name','').startswith('HiddenArm'): continue
        for p in mesh['primitives']:
            local = read(d,b,p['attributes']['POSITION'])
            all_points.append((np.c_[local,np.ones(len(local))]@world(ni).T)[:,:3])
    character_points = np.concatenate(all_points)
    H = float(np.ptp(character_points[:,1])); floor = character_points[:,1].min()
    for ni, node in enumerate(d['nodes']):
        if 'mesh' not in node or 'skin' not in node: continue
        mesh = d['meshes'][node['mesh']]
        if mesh.get('name','').startswith('HiddenArm'): continue
        if mesh_names is not None and mesh.get('name','') not in mesh_names: continue
        skin = d['skins'][node['skin']]; names = [d['nodes'][j].get('name','') for j in skin['joints']]
        for p in mesh['primitives']:
            a = p['attributes']; local = read(d,b,a['POSITION']); points = (np.c_[local,np.ones(len(local))]@world(ni).T)[:,:3]
            ids = np.concatenate([read(d,b,a[k]) for k in ['JOINTS_0','JOINTS_1'] if k in a],axis=1)
            weights = np.concatenate([read(d,b,a[k]) for k in ['WEIGHTS_0','WEIGHTS_1'] if k in a],axis=1).astype(float)
            if who == 'tanaka':
                initial = np.zeros((len(points),len(names)),np.float32)
                np.add.at(initial,(np.repeat(np.arange(len(points)),ids.shape[1]),ids.ravel()),weights.ravel())
                lower = [j for j,n in enumerate(names) if any(v in n for v in ['UpLeg','Toe','Foot']) or n.endswith('Leg')]
                initial[np.ix_(points[:,1]>floor+.55*H,lower)] = 0
                initial /= np.maximum(initial.sum(axis=1,keepdims=True),1e-12)
                torso_names = ['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2']
                tj = [names.index(n) for n in torso_names]; heights = [world(skin['joints'][j])[1,3] for j in tj]
                torso = np.zeros_like(initial)
                for vi, height in enumerate(points[:,1]):
                    if height<=heights[0]: torso[vi,tj[0]]=1
                    elif height>=heights[-1]: torso[vi,tj[-1]]=1
                    else:
                        k=int(np.searchsorted(heights,height)-1);u=(height-heights[k])/(heights[k+1]-heights[k]);torso[vi,tj[k]]=1-u;torso[vi,tj[k+1]]=u
                def smooth(lo,hi,value):
                    t=np.clip((value-lo)/(hi-lo),0,1);return t*t*(3-2*t)
                core=(1-smooth(.075*H,.14*H,abs(points[:,0])))*smooth(floor+.44*H,floor+.53*H,points[:,1])*(1-smooth(floor+.77*H,floor+.83*H,points[:,1]))
                initial=initial*(1-core[:,None])+torso*core[:,None]
                order=np.argsort(initial,axis=1)[:,-ids.shape[1]:][:,::-1];value=np.take_along_axis(initial,order,axis=1);value/=np.maximum(value.sum(axis=1,keepdims=True),1e-12)
                ids,weights=order,value
            _, first, inv = np.unique(np.rint(points/1e-6).astype(np.int64),axis=0,return_index=True,return_inverse=True)
            count = len(first); dense = np.zeros((count,len(names)),np.float32); visits = np.bincount(inv,minlength=count)
            np.add.at(dense,(np.repeat(inv,ids.shape[1]),ids.ravel()),weights.ravel()); dense /= visits[:,None]
            tri = inv[read(d,b,p['indices']).reshape(-1,3)]
            edges = np.vstack([tri[:,[0,1]],tri[:,[1,2]],tri[:,[2,0]]]); edges = np.unique(np.sort(edges,axis=1),axis=0)
            edges = edges[edges[:,0]!=edges[:,1]]; pp = points[first]
            length = np.linalg.norm(pp[edges[:,0]]-pp[edges[:,1]],axis=1)
            difference = abs(dense[edges[:,0]]-dense[edges[:,1]]).sum(axis=1)
            hand = dense[:,[j for j,n in enumerate(names) if 'Hand' in n]].sum(axis=1)
            fixed = (pp[:,1] > floor+head_start*H) | (hand>.45) | (pp[:,1] < floor+.08*H)
            bad = (length<.018) & (difference>.30) & ~(fixed[edges[:,0]]&fixed[edges[:,1]])
            seeds = np.zeros(count,bool); seeds[edges[bad].ravel()] = True
            ri = np.r_[edges[:,0],edges[:,1]]; ci = np.r_[edges[:,1],edges[:,0]]
            graph = coo_matrix((np.ones(len(ri)),(ri,ci)),shape=(count,count)).tocsr()
            degree = np.maximum(np.asarray(graph.sum(axis=1)).ravel(),1)
            mask = seeds.copy()
            for _ in range(10): mask |= np.asarray(graph@mask.astype(float)).ravel()>0
            mask &= ~fixed
            for _ in range(48):
                average = (graph@dense)/degree[:,None]
                dense[mask] = dense[mask]*.30+average[mask]*.70
                if who == 'tanaka':
                    dense[np.ix_(pp[:,1]>floor+.57*H,lower)] = 0
                    dense /= np.maximum(dense.sum(axis=1,keepdims=True),1e-12)
            slots = 8 if who == 'tanaka' else ids.shape[1]
            result = dense[inv]; order = np.argsort(result,axis=1)[:,-slots:][:,::-1]
            values = np.take_along_axis(result,order,axis=1); values /= np.maximum(values.sum(axis=1,keepdims=True),1e-12)
            for k in range(slots//4):
                a['JOINTS_'+str(k)] = append(d,b,a.get('JOINTS_'+str(k),a['JOINTS_0']),order[:,k*4:(k+1)*4])
                a['WEIGHTS_'+str(k)] = append(d,b,a.get('WEIGHTS_'+str(k),a['WEIGHTS_0']),values[:,k*4:(k+1)*4])
            reports.append({'mesh':mesh.get('name'),'seam_edges':int(bad.sum()),'relaxed_vertices':int(mask.sum()),'fixed_vertices':int(fixed.sum())})
    save(d,b,target); assert durations(source)==durations(target)
    report = {'character':who,'source':str(source),'target':str(target),'parts':reports,'geometry_changed':False,'clip_times_preserved':True}
    target.with_suffix('.boundary.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--character',choices=list(HEAD_START),required=True)
    p.add_argument('--mesh',action='append',help='Only relax these mesh parts; omitted means all visible parts')
    a=p.parse_args();print(json.dumps(relax(a.source,a.target,a.character,a.mesh)))
