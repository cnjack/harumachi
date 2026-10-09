"""Rip arm/body seams on the same exterior; cap only the internal opening."""
import bpy,bmesh,numpy as np
from mathutils import Vector

def _loops_of(edges):
    """Order boundary edges into chains. Returns lists of verts (closed chains repeat nothing)."""
    nb = {}
    for e in edges:
        a, b = e.verts
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    seen = set()
    chains = []
    starts = [v for v in nb if len(nb[v]) == 1] + list(nb)
    for s in starts:
        if s in seen:
            continue
        chain = [s]
        seen.add(s)
        cur = s
        while True:
            nxt = [u for u in nb[cur] if u not in seen]
            if not nxt:
                break
            cur = nxt[0]
            seen.add(cur)
            chain.append(cur)
        if len(chain) >= 3:
            chains.append(chain)
    return chains


def _cap(bm, chain, outward, uvl, src_faces):
    """Triangulate the polygon closed by `chain` (projected on its best-fit plane)."""
    import numpy as np
    from mathutils import geometry
    P = np.array([v.co[:] for v in chain])
    c = P.mean(0)
    _, _, vt = np.linalg.svd(P - c)
    u_ax, v_ax = vt[0], vt[1]
    pts = [Vector(((p - c) @ u_ax, (p - c) @ v_ax)) for p in P]
    out = geometry.delaunay_2d_cdt(pts, [], [list(range(len(pts)))], 1, 1e-6, True)
    verts_out, _, faces_out, orig_verts = out[0], out[1], out[2], out[3]
    made = 0
    for f in faces_out:
        ids = []
        for k in f:
            o = orig_verts[k]
            if not o:
                break
            ids.append(o[0])
        if len(ids) != 3 or len(set(ids)) != 3:
            continue
        vs = [chain[i] for i in ids]
        n = (vs[1].co - vs[0].co).cross(vs[2].co - vs[0].co)
        if n.length < 1e-12:
            continue
        if n.dot(outward) < 0:
            vs = [vs[0], vs[2], vs[1]]
        try:
            nf = bm.faces.new(vs)
        except ValueError:
            continue
        ref = src_faces.get(vs[0])
        if ref is not None:
            nf.material_index = ref.material_index
        for lp in nf.loops:
            rf = src_faces.get(lp.vert)
            if rf is not None and uvl is not None:
                for rl in rf.loops:
                    if rl.vert == lp.vert:
                        lp[uvl].uv = rl[uvl].uv
                        break
        made += 1
    return made



def separate_arm_seams(mesh,rig,H):
    bm=bmesh.new();bm.from_mesh(mesh.data);dl=bm.verts.layers.deform.verify();uvl=bm.loops.layers.uv.active
    report=[]
    for side,sign in [('Left',1),('Right',-1)]:
        arm_names=['mixamorig:'+side+s for s in ['Arm','ForeArm','Hand']]
        ids={g.index for g in mesh.vertex_groups if g.name in arm_names or g.name=='TWIST_'+side or g.name.startswith('mixamorig:'+side+'Hand')}
        segments={n:(rig.data.bones[n].head_local.copy(),rig.data.bones[n].tail_local.copy()) for n in arm_names}
        shoulder=rig.data.bones[arm_names[0]].head_local
        def segment_distance(p,name):
            a,b=segments[name];delta=b-a;u=max(0,min(1,(p-a).dot(delta)/delta.length_squared));return (p-a-u*delta).length
        share={v:sum(v[dl].get(i,0) for i in ids) for v in bm.verts}
        radii={}
        for name in arm_names:
            a,b=segments[name];delta=b-a
            values=sorted(segment_distance(v.co,name) for v in bm.verts if share[v]>.5 and .12<(v.co-a).dot(delta)/delta.length_squared<.9)
            radius=values[len(values)//4] if values else .025*H
            radii[name]=(min(max(radius*1.6,.035*H),.065*H),min(max(radius*2.8,.07*H),.105*H))
        def near_arm(face):
            p=face.calc_center_median()
            for name in arm_names:
                a,b=segments[name];delta=b-a
                if name.endswith('Hand'):delta*=1.8
                u=max(0,min(1,(p-a).dot(delta)/delta.length_squared));offset=p-a-u*delta
                inward=-sign*offset.x>offset.length*.5
                if offset.length<=radii[name][0 if inward else 1]:return True
            return False
        cls={f:sign*f.calc_center_median().x>sign*shoulder.x-.015*H and near_arm(f) for f in bm.faces}
        # Eliminate small islands in the face classification.
        for iteration in range(2):
            seen=set()
            for first in list(bm.faces):
                if first in seen:continue
                component=[first];stack=[first];seen.add(first)
                while stack:
                    f=stack.pop()
                    for edge in f.edges:
                        for other in edge.link_faces:
                            if other not in seen and cls[other]==cls[first]:seen.add(other);stack.append(other);component.append(other)
                if len(component)<40:
                    for f in component:cls[f]=not cls[f]
        armpit=shoulder.z-.04*H
        old_boundary={e for e in bm.edges if e.is_boundary}
        mixed=[v for v in bm.verts if v.co.z<armpit and len({cls[f] for f in v.link_faces})==2]
        twins={v:bm.verts.new(v.co,v) for v in mixed}
        for f in {f for v in mixed for f in v.link_faces if cls[f]}:
            old_uv=[lp[uvl].uv.copy() for lp in f.loops] if uvl else []
            new=bm.faces.new([twins.get(v,v) for v in f.verts],f)
            for lp,uv in zip(new.loops,old_uv):lp[uvl].uv=uv
            cls[new]=True;bm.faces.remove(f)
        torso_ids=[mesh.vertex_groups[n].index for n in ['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2']]
        for v in bm.verts:
            if v.co.z>=armpit or not v.link_faces:continue
            owners={cls.get(f,False) for f in v.link_faces}
            if len(owners)!=1:continue
            on_arm=owners.pop();weights=v[dl];keep={i:w for i,w in weights.items() if (i in ids)==on_arm}
            if not keep:
                if on_arm:
                    name=min(arm_names,key=lambda n:segment_distance(v.co,n));keep={mesh.vertex_groups[name].index:1}
                else:keep={min(torso_ids,key=lambda i:abs(v.co.z-rig.data.bones[mesh.vertex_groups[i].name].head_local.z)):1}
            total=sum(keep.values())
            for i in list(weights.keys()):del weights[i]
            for i,w in keep.items():weights[i]=w/total
        new_edges=[e for e in bm.edges if e.is_boundary and e not in old_boundary];src={}
        for edge in new_edges:
            for v in edge.verts:src.setdefault(v,edge.link_faces[0])
        caps=0
        for on_arm in [False,True]:
            edges=[e for e in new_edges if cls.get(e.link_faces[0],False)==on_arm]
            outward=Vector((-sign if on_arm else sign,0,0))
            for chain in _loops_of(edges):caps+=_cap(bm,chain,outward,uvl,src)
        report.append({'side':side,'split_vertices':len(mixed),'inner_cap_faces':caps})
    bm.normal_update();bm.to_mesh(mesh.data);bm.free();mesh.data.update()
    return report
