"""UV-preserving radial reconstruction of provider plants that remained planar."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector


def restore_depth(model, aid):
    thresholds = {'A14_hydrangea_pot': .35, 'A15_potted_plant': .34, 'C09_carrot': .20, 'C10_potato': .08,
                  'C11_eggplant': .08, 'C15_wheat': 0,
                  'C16_onion': .40, 'T09_bamboo_grove': 0, 'V21_white_hydrangea': .38,
                  'V23_cosmos_pot': .28, 'V24_fern_pot': .36, 'V25_dwarf_lemon': .29}
    if aid not in thresholds:
        return None
    points = [v.co for v in model.data.vertices]
    low = Vector([min(p[k] for p in points) for k in range(3)])
    high = Vector([max(p[k] for p in points) for k in range(3)])
    height = high.z - low.z
    cutoff = low.z + height * thresholds[aid]
    upper = [p for p in points if p.z >= low.z + height * max(thresholds[aid], .4)]
    width = max(p.x for p in upper) - min(p.x for p in upper)
    depth = max(p.y for p in upper) - min(p.y for p in upper)
    if min(depth,width) >= max(depth,width) * .65:
        return dict(kind='radial_depth_already_sufficient',upper_depth_to_width=depth/width)
    base = [p for p in points if p.z <= low.z + height * .07]
    centre = Vector(((min(p.x for p in base) + max(p.x for p in base)) / 2,
                     (min(p.y for p in base) + max(p.y for p in base)) / 2, 0))
    duplicate = model.copy()
    duplicate.data = model.data.copy()
    duplicate.name = 'Radial_recovered_branches_' + aid
    bpy.context.collection.objects.link(duplicate)
    if thresholds[aid] > 0:
        bm = bmesh.new()
        bm.from_mesh(duplicate.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                              plane_co=Vector((0, 0, cutoff)), plane_no=Vector((0, 0, 1)),
                              clear_inner=True, dist=1e-6)
        bm.to_mesh(duplicate.data)
        bm.free()
    transform = Matrix.Translation(centre) @ Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation(-centre)
    duplicate.data.transform(transform)
    bpy.ops.object.select_all(action='DESELECT')
    model.select_set(True)
    duplicate.select_set(True)
    bpy.context.view_layer.objects.active = model
    bpy.ops.object.join()
    return dict(kind='radial_reconstruction_of_planar_upper_plant',
                original_upper_depth_to_width=depth/width, added_rotation_degrees=90,
                retained='original complete model, pot/root, leaf and flower/fruit geometry, original UVs',
                added='one orthogonal copy of the upper branch system; wheat retains each full rooted stalk',
                cutoff_fraction=thresholds[aid], root_pivot_blender=list(centre),
                note='Repairs actual side-volume failure without stretching leaf thickness or changing the original source')


def creeping_vine(model, aid):
    if aid not in ['C13_pumpkin', 'C14_watermelon']:
        return None
    # The generated fruit and leaves are complete but arranged as a hanging
    # bush. Turn the connected vine plane onto the soil; keep round fruit and UVs.
    model.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
    points=np.asarray([v.co[:] for v in model.data.vertices])
    low=points.min(axis=0);high=points.max(axis=0);size=high-low
    # Asset-specific body windows were measured on these selected B meshes,
    # rather than using the whole plant's lowest dangling leaves as fruit feet.
    def window(bounds):
        return points[np.all((points>=np.asarray(bounds[0]))&(points<=np.asarray(bounds[1])),axis=1)]
    if aid=='C13_pumpkin':
        atlas=next(node.image for mat in model.data.materials if mat and mat.use_nodes
                   for node in mat.node_tree.nodes if node.type=='TEX_IMAGE' and node.image
                   and 'diffuse' in node.image.name.lower())
        pixels=np.empty(len(atlas.pixels),dtype=np.float32);atlas.pixels.foreach_get(pixels)
        pixels=pixels.reshape(atlas.size[1],atlas.size[0],4)
        uv=model.data.uv_layers.active;orange=set()
        for face in model.data.polygons:
            u,v=np.mean([uv.data[index].uv[:] for index in face.loop_indices],axis=0)
            r,g,b=pixels[min(atlas.size[1]-1,max(0,int(v*atlas.size[1]))),min(atlas.size[0]-1,max(0,int(u*atlas.size[0])))][:3]
            if r>g*1.8:orange.update(face.vertices)
        left=points[list(orange)]
        right=window([[.20,.25,-.28],[.80,.72,.20]])
        support_regions={'left':'orange fruit vertices selected through original albedo UV',
                         'right_raw_blender':[[.20,.25,-.28],[.80,.72,.20]]}
    else:
        left=window([[-.75,-.04,-.34],[-.05,.72,.28]])
        right=window([[.20,-.04,-.23],[.75,.56,.38]])
        support_regions={'left_raw_blender':[[-.75,-.04,-.34],[-.05,.72,.28]],
                         'right_raw_blender':[[.20,-.04,-.23],[.75,.56,.38]]}
    if len(left)<100 or len(right)<100:raise RuntimeError(aid+': reviewed fruit body regions are missing')
    def gap(angle):
        return float(np.min(-np.sin(angle)*right[:,0]+np.cos(angle)*right[:,2])-
                     np.min(-np.sin(angle)*left[:,0]+np.cos(angle)*left[:,2]))
    angles=np.linspace(-math.pi/3,math.pi/3,241)
    brackets=[(a,b) for a,b in zip(angles,angles[1:]) if gap(a)*gap(b)<=0]
    if not brackets:raise RuntimeError(aid+': no common fruit support angle; inspect geometry')
    first,last=min(brackets,key=lambda pair:abs(sum(pair)))
    for _ in range(32):
        middle=(first+last)/2
        if gap(first)*gap(middle)<=0:last=middle
        else:first=middle
    angle=(first+last)/2
    model.data.transform(Matrix.Rotation(angle,4,'Y'))
    floor=float(np.min(-np.sin(angle)*left[:,0]+np.cos(angle)*left[:,2]))
    changed=0
    for vertex in model.data.vertices:
        if vertex.co.z<floor:
            vertex.co.z=floor;changed+=1
    bm=bmesh.new();bm.from_mesh(model.data)
    bmesh.ops.dissolve_degenerate(bm,dist=1e-7,edges=bm.edges[:]);bm.to_mesh(model.data);bm.free()
    model.data.update()
    return dict(kind='creeping_vine_growth_orientation',rotation_x_degrees=90,
                retained='complete generated fruit, leaf and connected vine geometry with original UVs',
                purpose='puts the vine on a horizontal ground footprint instead of suspending fruit in an upright bush',
                fruit_support_rotation_y_degrees=math.degrees(angle),support_gap_raw=gap(angle),
                leaf_vertices_reposed_to_common_fruit_floor=changed,fruit_body_probe_counts=[len(left),len(right)],
                reviewed_fruit_support_regions=support_regions,
                contact_method='common support extrema of the two reviewed fruit-body windows; low vine leaves lie on that floor',
                acceptance='fruit/soil contact still requires game geometry and native review')
