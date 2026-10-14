"""Refine the approved anime furniture silhouettes without moving their uses.

Blender -b --factory-startup -P art/tools/refine_furniture_forms_20261014.py -- [ID ...]
Every run reads the committed immutable GLBs under art/library/.../source,
never an already refined game GLB. Pull Git LFS before regenerating the models.
Only raw GLB/blend outputs and this task's configuration/measurement manifest change.
"""
import bpy
import bmesh
import hashlib
import json
import math
import os
import struct
import sys
import traceback
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/library/furniture_forms_20261014/source'
OUT = ROOT / 'art/models/raw/furniture_forms_20261014'
MANIFEST = ROOT / 'art/manifests/furniture_forms_geometry_20261014.json'
IDS = ['P_cafe_table', 'P_community_table', 'P_reading_chair', 'I04_shop_counter',
       'P_gondola', 'W17_display_shelf', 'I05_bread_shelf',
       'W13_cedar_worktable', 'I02_cake_showcase']
ONLY = set(sys.argv[sys.argv.index('--') + 1:]) if '--' in sys.argv else set()
SOURCE.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
HAD_MANIFEST = MANIFEST.is_file()
REPORT = json.loads(MANIFEST.read_text()) if HAD_MANIFEST else {
    'revision': '20261014', 'kind': 'approved_imagegen_furniture_geometry',
    'source_is_current_game_archive': True, 'units': 'metres', 'assets': {}}
CHANGES = []


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(ob, world=False):
    vertices = [ob.matrix_world @ v.co if world else v.co for v in ob.data.vertices]
    return Vector([min(v[i] for v in vertices) for i in range(3)]), Vector([max(v[i] for v in vertices) for i in range(3)])


def scene_bounds():
    bpy.context.view_layer.update()
    corners = [bounds(ob, True) for ob in bpy.context.scene.objects if ob.type == 'MESH']
    return Vector([min(p[0][i] for p in corners) for i in range(3)]), Vector([max(p[1][i] for p in corners) for i in range(3)])


def godot(v):
    return [round(v.x, 7), round(v.z, 7), round(-v.y, 7)]


def godot_bounds(lo,hi):
    return [round(lo.x,7),round(lo.z,7),round(-hi.y,7)], [round(hi.x,7),round(hi.z,7),round(-lo.y,7)]


def triangles():
    return sum(sum(len(face.vertices) - 2 for face in ob.data.polygons) for ob in bpy.context.scene.objects if ob.type == 'MESH')


class UVSource:
    """Interpolate the existing UV field on its original triangles, including atlas seams."""
    def __init__(self, ob):
        mesh = ob.data
        mesh.calc_loop_triangles()
        self.vertices = [v.co.copy() for v in mesh.vertices]
        self.tris = [tuple(face.vertices) for face in mesh.loop_triangles]
        layer = mesh.uv_layers.active
        self.uv = [[Vector((layer.data[i].uv.x, layer.data[i].uv.y, 0)) for i in face.loops] for face in mesh.loop_triangles] if layer else None
        self.mats = [face.material_index for face in mesh.loop_triangles]
        self.bvh = BVHTree.FromPolygons(self.vertices, self.tris, all_triangles=True)
        self.by_material = {}
        for mat in set(self.mats):
            indices = [i for i, value in enumerate(self.mats) if value == mat]
            self.by_material[mat] = (BVHTree.FromPolygons(self.vertices, [self.tris[i] for i in indices], all_triangles=True), indices)

    def transfer(self, ob, required_material=None):
        mesh = ob.data
        layer = mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
        for face in mesh.polygons:
            for loop in face.loop_indices:
                point = mesh.vertices[mesh.loops[loop].vertex_index].co
                tree, indices = self.by_material[required_material] if required_material is not None else (self.bvh, None)
                nearest, _normal, hit, _distance = tree.find_nearest(point)
                if hit is None:
                    raise RuntimeError('Missing source UV triangle: ' + ob.name)
                index = indices[hit] if indices is not None else hit
                if self.uv:
                    corners = [self.vertices[i] for i in self.tris[index]]
                    mapped = barycentric_transform(nearest, *corners, *self.uv[index])
                    layer.data[loop].uv = mapped.xy
                face.material_index = required_material if required_material is not None else self.mats[index]


def install_mesh(ob, vertices, faces):
    materials = list(ob.data.materials)
    mesh = bpy.data.meshes.new(ob.name + '_CurvedGeometry')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for material in materials:
        mesh.materials.append(material)
    ob.data = mesh


def bevel(ob, radius, segments=6):
    if radius <= 0:
        return
    bpy.context.view_layer.objects.active = ob
    modifier = ob.modifiers.new('Measured multi-segment roundover', 'BEVEL')
    modifier.width = radius
    modifier.segments = segments
    modifier.limit_method = 'ANGLE'
    modifier.angle_limit = .35
    modifier.use_clamp_overlap = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    # Keep broad painted faces flat, roundovers interpolate their true curved normals.
    for polygon in ob.data.polygons:
        components = sorted(abs(v) for v in polygon.normal)
        polygon.use_smooth = components[-1] < .999


def outline(width, depth, radius, segments=8):
    radius = min(radius, width * .45, depth * .45)
    points = []
    for cx, cy, start in [(width/2-radius, depth/2-radius, 0), (-width/2+radius, depth/2-radius, math.pi/2),
                          (-width/2+radius, -depth/2+radius, math.pi), (width/2-radius, -depth/2+radius, math.pi*1.5)]:
        for step in range(segments + 1):
            angle = start + math.pi * .5 * step / segments
            points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def rounded_box(ob, corner, edge, segments=6, source=None):
    uv = source or UVSource(ob)
    lo, hi = bounds(ob)
    centre = (lo + hi) / 2
    size = hi - lo
    corner_segments = 3 if size.z > max(size.x, size.y) else (8 if min(size.x, size.y) > .25 else 4)
    ring = outline(size.x, size.y, corner, corner_segments)
    count = len(ring)
    vertices = [(x+centre.x, y+centre.y, z) for z in (lo.z, hi.z) for x, y in ring]
    faces = [tuple(reversed(range(count))), tuple(range(count, count*2))]
    faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
    install_mesh(ob, vertices, faces)
    bevel(ob, min(edge, min(size) * .40), segments)
    uv.transfer(ob)
    world_scale=max(abs(v) for v in ob.matrix_world.to_scale())
    CHANGES.append({'node': ob.name, 'kind': 'rounded_joinery', 'plan_corner_radius_m': corner*world_scale,
                    'edge_radius_m': min(edge, min(size)*.40)*world_scale, 'arc_segments': segments,
                    'uv': 'original_triangle_field_interpolation'})


def grid_volume(ob, kind, drop=.007, bow=.024, recline=7.):
    uv = UVSource(ob)
    lo, hi = bounds(ob)
    centre = (lo + hi) / 2
    size = hi - lo
    nx, ny = 14, 12
    vertices = []
    for side in range(2):
        for row in range(ny+1):
            v = row/ny
            for col in range(nx+1):
                u = col/nx
                x = lo.x+size.x*u
                if kind == 'back':
                    z = lo.z+size.z*v
                    # Upper centre stays within the original rear footprint; lower
                    # edge leans toward the seat, not into the aisle behind the chair.
                    y = (lo.y if side == 0 else hi.y) + math.tan(math.radians(recline))*(z-hi.z)-bow*(2*u-1)**2
                else:
                    y = lo.y+size.y*v
                    reach = max(abs(u-.5)*2, abs(v-.5)*2)
                    blend = min(1., max(0., (reach-.48)/.52))
                    blend = blend*blend*(3-2*blend)
                    z = lo.z if side == 0 else hi.z-drop*blend
                vertices.append((x,y,z))
    stride = nx+1
    layer = (nx+1)*(ny+1)
    faces = []
    for row in range(ny):
        for col in range(nx):
            index = row*stride+col
            cell = (index,index+1,index+1+stride,index+stride)
            faces.append(tuple(reversed(cell)) if kind == 'seat' else cell)
            faces.append(tuple(i+layer for i in cell) if kind == 'seat' else tuple(i+layer for i in reversed(cell)))
    boundary = list(range(nx+1)) + [row*stride+nx for row in range(1,ny+1)] + [ny*stride+col for col in range(nx-1,-1,-1)] + [row*stride for row in range(ny-1,0,-1)]
    for i,index in enumerate(boundary):
        following=boundary[(i+1)%len(boundary)]
        faces.append((index,following,following+layer,index+layer))
    install_mesh(ob,vertices,faces)
    # Recalculate winding for both the upright and horizontal volumes.
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    bevel(ob,.009 if kind=='back' else .014,6)
    for face in ob.data.polygons: face.use_smooth=True
    uv.transfer(ob)
    if kind=='back':
        tree=BVHTree.FromObject(ob,bpy.context.evaluated_depsgraph_get())
        def front(x,z):
            hit,_normal,_index,_distance=tree.ray_cast(Vector((x,lo.y-.25,z)),Vector((0,1,0)),1.)
            if hit is None:raise RuntimeError('Missing curved back probe '+ob.name)
            return hit.y
        span=size.x*.375;z_mid=centre.z
        mid=front(centre.x,z_mid);left=front(centre.x-span,z_mid);right=front(centre.x+span,z_mid)
        sag=mid-(left+right)*.5
        measured_radius=(span*span+sag*sag)/(2*sag)
        z0=lo.z+.03;z1=hi.z-.03
        measured_lean=math.degrees(math.atan2(front(centre.x,z1)-front(centre.x,z0),z1-z0))
        CHANGES.append({'node':ob.name,'kind':'curved_reclined_back','horizontal_bow_m':bow,'bow_radius_m':measured_radius,'measured_probe_span_m':span*2,'measured_probe_sag_m':sag,'recline_degrees':measured_lean,'edge_radius_m':.009,'arc_segments':6})
        dark=next((m for m in bpy.data.materials if m.name=='CedarDark'),None)
        if dark is not None:
            # Continuous rear stiles connect the formerly floating back to the
            # original rear legs; they stay behind the curved panel and in its footprint.
            for side in [-1,1]:
                x=centre.x+side*.205
                def rail_point(z):return Vector((x,hi.y-.004+math.tan(math.radians(recline))*(z-hi.z)-bow*((x-centre.x)/(size.x*.5))**2,z))
                start=rail_point(lo.z-.09);end=rail_point(hi.z-.035)
                stile=add_box(ob.name+'_BackStile_%d'%side,(.030,.028,(end-start).length),(start+end)/2,dark,ob,edge=.004)
                stile.rotation_mode='QUATERNION';stile.rotation_quaternion=Vector((0,0,1)).rotation_difference(end-start)
            CHANGES.append({'node':ob.name,'kind':'continuous_back_stiles','count':2,'joinery_width_m':.030,'connects_original_rear_legs':True})
    else:
        tree=BVHTree.FromObject(ob,bpy.context.evaluated_depsgraph_get())
        def top(x,y):
            hit,_normal,_index,_distance=tree.ray_cast(Vector((x,y,hi.z+.10)),Vector((0,0,-1)),1.)
            if hit is None:raise RuntimeError('Missing curved seat probe '+ob.name)
            return hit.z
        measured_drop=top(centre.x,centre.y)-top(centre.x+size.x*.40,centre.y)
        CHANGES.append({'node':ob.name,'kind':'shaped_seat','outer_drop_m':drop,'measured_drop_at80percent_width_m':measured_drop,'centre_support_local_z':hi.z,'centre_contact_width_m':size.x*.48,'edge_radius_m':.014,'arc_segments':6})
        dark=next((m for m in bpy.data.materials if m.name=='CedarDark'),None)
        if dark is not None:
            for side in [-1,1]:add_box(ob.name+'_SideStretcher_%d'%side,(.026,.36,.030),(centre.x+side*.19,centre.y,centre.z-.1875),dark,ob,edge=.004)
            CHANGES.append({'node':ob.name,'kind':'supported_chair_stretchers','count':2,'centre_height_below_seat_m':.1875})


def turned_round(ob, edge=.011, sides=96):
    uv=UVSource(ob);lo,hi=bounds(ob);centre=(lo+hi)/2;radius=min(hi.x-lo.x,hi.y-lo.y)/2
    vertices=[]
    for z in (lo.z,hi.z):
        for step in range(sides):
            angle=2*math.pi*step/sides;vertices.append((centre.x+radius*math.cos(angle),centre.y+radius*math.sin(angle),z))
    faces=[tuple(reversed(range(sides))),tuple(range(sides,sides*2))]+[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    install_mesh(ob,vertices,faces);bevel(ob,edge,6);uv.transfer(ob)
    CHANGES.append({'node':ob.name,'kind':'turned_pedestal_rim','radius_m':radius,'edge_radius_m':edge,'radial_segments':sides,'arc_segments':6})


def add_box(label,size,at,material,parent=None,edge=.003):
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob=bpy.context.object;ob.name=label
    ob.data.materials.append(material)
    ob.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if parent:
        ob.parent=parent;ob.matrix_parent_inverse.identity()
    ob.location=at
    bevel(ob,edge,5)
    # New joinery only: metric planar UVs, never random atlas coordinates.
    layer=ob.data.uv_layers.active or ob.data.uv_layers.new(name='UVMap')
    for face in ob.data.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]));axes=[i for i in range(3) if i!=axis]
        for loop in face.loop_indices:
            p=ob.data.vertices[ob.data.loops[loop].vertex_index].co
            layer.data[loop].uv=(p[axes[0]]*.7,p[axes[1]]*.7)
    ob['furniture_form_part']=True
    return ob


def frame_panel(ob,material):
    uv=UVSource(ob);lo,hi=bounds(ob);size=hi-lo;centre=(lo+hi)/2
    # Blender front=-Y. The inner panel is recessed7.5mm behind a real solid frame.
    width=size.x-.070;height=size.z-.075;depth=min(size.y,.010)
    verts=[(centre.x+x*width/2,centre.y+y*depth/2,centre.z+z*height/2) for x in [-1,1] for y in [-1,1] for z in [-1,1]]
    faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    install_mesh(ob,verts,faces);bevel(ob,.003,5);uv.transfer(ob)
    for side in [-1,1]:
        add_box(ob.name+'_FrameSide_%d'%side,(.035,size.y,height+.075),(centre.x+side*(size.x/2-.0175),centre.y,centre.z),material,ob)
        add_box(ob.name+'_FrameRail_%d'%side,(width,size.y,.0375),(centre.x,centre.y,centre.z+side*(size.z/2-.01875)),material,ob)
    CHANGES.append({'node':ob.name,'kind':'recessed_framed_panel','frame_width_m':.035,'recess_m':(size.y-depth)*.5,'edge_radius_m':.003,'arc_segments':5})


def supports(asset):
    materials=list(bpy.data.materials)
    dark=next((m for m in materials if m.name=='CedarDark'),None)
    if asset not in ('W17_display_shelf','I05_bread_shelf') or dark is None:return
    boards=[ob for ob in bpy.context.scene.objects if ob.type=='MESH' and ob.name.startswith('TrayBoard_')]
    for index,board in enumerate(boards):
        lo,hi=bounds(board,True);width=hi.x-lo.x
        for side in [-1,1]:
            # End brackets stay outside the working merchandise width.
            x=(lo.x+hi.x)/2+side*(width/2-.020)
            start=Vector((x,hi.y-.045,lo.z-.13));end=Vector((x,lo.y+.10,lo.z-.020))
            beam=add_box('FormShelfBracket_%d_%d'%(index,side),(.026,.026,(end-start).length),(start+end)/2,dark,edge=.004)
            beam.rotation_mode='QUATERNION';beam.rotation_quaternion=Vector((0,0,1)).rotation_difference(end-start)
            CHANGES.append({'node':beam.name,'kind':'real_shelf_support','width_m':.026,'length_m':(end-start).length,'edge_radius_m':.004,'arc_segments':5})


def gondola_components(ob):
    """Refine each existing joined timber while keeping the one authored mesh node/atlas."""
    uv=UVSource(ob)
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000005)
    bm.verts.ensure_lookup_table();bm.verts.index_update();bm.faces.index_update();seen=set();components=[]
    for vertex in bm.verts:
        if vertex in seen:continue
        pending=[vertex];seen.add(vertex);vertices=[];faces=set()
        while pending:
            item=pending.pop();vertices.append(item);faces.update(item.link_faces)
            for edge in item.link_edges:
                other=edge.other_vert(item)
                if other not in seen:seen.add(other);pending.append(other)
        components.append((vertices,faces))
    vertices_out=[];faces_out=[];material_out=[];uv_out=[]
    original_uv=bm.loops.layers.uv.active
    for number,(vertices,faces) in enumerate(components):
        mat=max(set(f.material_index for f in faces),key=lambda m:sum(1 for f in faces if f.material_index==m))
        lo=Vector([min(v.co[i] for v in vertices) for i in range(3)]);hi=Vector([max(v.co[i] for v in vertices) for i in range(3)]);size=hi-lo
        if mat==2 or min(size)<.006:
            mapping={v:len(vertices_out)+i for i,v in enumerate(vertices)};vertices_out += [v.co.copy() for v in vertices]
            for face in sorted(faces,key=lambda item:item.index):
                faces_out.append(tuple(mapping[v] for v in face.verts));material_out.append(face.material_index)
                uv_out.append([loop[original_uv].uv.copy() for loop in face.loops])
            continue
        # These imported connected pieces are the original rectangular rails/slats.
        temporary=bpy.data.objects.new('TemporaryTimber',bpy.data.meshes.new('TemporaryTimber'))
        bpy.context.collection.objects.link(temporary)
        temporary.data.from_pydata([(x,y,z) for x in (lo.x,hi.x) for y in (lo.y,hi.y) for z in (lo.z,hi.z)],[],[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])
        for material in ob.data.materials:temporary.data.materials.append(material)
        corner=min(.012,min(size.x,size.y)*.32);edge=min(.006,min(size)*.27)
        rounded_box(temporary,corner,edge,5,source=uv)
        CHANGES[-1]['node']=ob.name+'/component_%03d'%number
        # Match source material, excluding the nearby paper label atlas.
        uv.transfer(temporary,mat)
        offset=len(vertices_out);vertices_out += [v.co.copy() for v in temporary.data.vertices]
        for face in temporary.data.polygons:
            faces_out.append(tuple(offset+i for i in face.vertices));material_out.append(mat)
            uv_out.append([temporary.data.uv_layers.active.data[loop].uv.copy() for loop in face.loop_indices])
        bpy.data.objects.remove(temporary,do_unlink=True)
    bm.free();install_mesh(ob,vertices_out,faces_out)
    # Each source part's original UV domain is retained; labels remain their own material.
    for index,face in enumerate(ob.data.polygons):face.material_index=material_out[index]
    layer=ob.data.uv_layers.new(name='UVMap')
    for index,face in enumerate(ob.data.polygons):
        for loop,mapped in zip(face.loop_indices,uv_out[index]):layer.data[loop].uv=mapped
    CHANGES.append({'node':ob.name,'kind':'individual_joined_timber_roundovers','measured_components':len(components),'paper_material_untouched':True,'arc_segments':5})


def refine(asset):
    meshes=[ob for ob in bpy.context.scene.objects if ob.type=='MESH']
    if asset=='P_gondola':
        gondola_components(meshes[0]);return
    for ob in meshes:
        label=ob.name.lower()
        lo,hi=bounds(ob);size=hi-lo;scale=ob.matrix_world.to_scale().x
        if 'seatpoint' in label or 'glass' in label or 'linen' in label:continue
        if ('chair' in label and 'back' in label and 'leg' not in label and 'seat' not in label and size.z>.25):
            grid_volume(ob,'back');continue
        if 'chair' in label and 'seat' in label:
            grid_volume(ob,'seat');continue
        if asset=='P_cafe_table' and label in ('roundtop','foot','pedestal'):
            turned_round(ob,.011 if label=='roundtop' else .004,96 if label=='roundtop' else 64);continue
        if asset=='I04_shop_counter' and label.startswith('frontpanel'):
            sage=next(m for m in bpy.data.materials if m.name=='Sage');frame_panel(ob,sage);continue
        if asset=='I02_cake_showcase' and label=='insetfront':
            frame_panel(ob,next(m for m in bpy.data.materials if m.name=='Painted_cedar'));continue
        if 'register' in label or label=='display' or 'peg' in label:
            continue
        primary=('top' in label or 'tabletop' in label) and size.x>.5
        if primary:
            rounded_box(ob,.040/scale,.011/scale,6)
        elif 'arm' in label:
            rounded_box(ob,.022,.012,7)
        elif 'counterbody' in label or 'cabinetbase' in label:
            rounded_box(ob,.028,.007,6)
        else:
            edge=min(.006/scale,min(size)*.25)
            rounded_box(ob,min(.014/scale,min(size.x,size.y)*.32),edge,5)
    supports(asset)


def support_probes(before_objects):
    result=[]
    for name,record in before_objects.items():
        if record['type']!='MESH':continue
        label=name.lower()
        if not any(part in label for part in ('seat','top','trayboard','shelf_')) or 'point' in label:continue
        ob=bpy.data.objects.get(name)
        original_lo=Vector(record['world_lo']);original_hi=Vector(record['world_hi'])
        centre=(original_lo+original_hi)/2
        tree=BVHTree.FromObject(ob,bpy.context.evaluated_depsgraph_get())
        ray_world=Vector((centre.x,centre.y,original_hi.z+.10));inverse=ob.matrix_world.inverted()
        ray=inverse@ray_world;direction=(inverse.to_3x3()@Vector((0,0,-1))).normalized()
        hit,_normal,_index,_distance=tree.ray_cast(ray,direction,2.)
        height=(ob.matrix_world@hit).z if hit is not None else None
        result.append({'node':name,'original_top_y_m':round(original_hi.z,7),'actual_centre_top_y_m':round(height,7) if height is not None else None,'delta_m':round(height-original_hi.z,7) if height is not None else None})
    return result


def joined_shelf_probes(asset):
    if asset!='P_gondola':return []
    meshes=[ob for ob in bpy.context.scene.objects if ob.type=='MESH']
    trees=[(ob,BVHTree.FromObject(ob,bpy.context.evaluated_depsgraph_get())) for ob in meshes]
    probes=[]
    for ceiling in [.20,.54,.88,1.22]:
        for x in [-.65,0,.65]:
            for z in [-.17,-.065,.065,.17]:
                best=None
                for ob,tree in trees:
                    inverse=ob.matrix_world.inverted();origin=inverse@Vector((x,-z,ceiling));direction=(inverse.to_3x3()@Vector((0,0,-1))).normalized()
                    hit,_normal,_index,_distance=tree.ray_cast(origin,direction,ceiling+1.)
                    if hit is not None:
                        height=(ob.matrix_world@hit).z
                        best=max(best,height) if best is not None else height
                probes.append({'node':'P_gondola','x':x,'z':z,'ceiling':ceiling,'actual_top_y_m':best})
    return probes


def glb_proof(source,target):
    def read(path):
        blob=path.read_bytes();length=struct.unpack_from('<I',blob,12)[0]
        document=json.loads(blob[20:20+length]);binary=blob[28+length:]
        images=[]
        for image in document.get('images',[]):
            view=document['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
            images.append(hashlib.sha256(binary[start:start+view['byteLength']]).hexdigest())
        return document,images
    old,old_images=read(source);new,new_images=read(target)
    missing=set(n.get('name') for n in old['nodes'])-set(n.get('name') for n in new['nodes'])
    materials=set(m.get('name') for m in old.get('materials',[]))==set(m.get('name') for m in new.get('materials',[]))
    if missing or not materials or old_images!=new_images:raise RuntimeError('GLB source identity/texture retention failed '+str((missing,materials,old_images==new_images)))
    return {'all_original_node_names_present':True,'original_material_names_preserved':materials,'embedded_texture_bytes_exact':old_images==new_images,'texture_sha256':old_images}


def run(asset):
    global CHANGES
    CHANGES=[]
    source=SOURCE/(asset+'.glb')
    recovery='Run git lfs pull or restore art/library/furniture_forms_20261014/source from Git.'
    if not source.is_file():
        raise FileNotFoundError('Missing archived furniture source: '+str(source)+'. '+recovery)
    expected=REPORT.get('assets',{}).get(asset,{}).get('source_sha256','')
    if HAD_MANIFEST and not expected:
        raise ValueError('Missing archived-source SHA256 for '+asset+'; restore the furniture forms manifest from Git.')
    if expected and sha(source)!=expected:
        raise ValueError('Archived furniture source SHA256 mismatch: '+str(source)+'. '+recovery)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    bpy.context.view_layer.update()
    before={}
    for ob in bpy.context.scene.objects:
        record={'type':ob.type,'matrix':[list(row) for row in ob.matrix_world]}
        if ob.type=='MESH':
            lo,hi=bounds(ob,True);record.update(world_lo=list(lo),world_hi=list(hi))
        before[ob.name]=record
    lo_before,hi_before=scene_bounds();tris_before=triangles();joined_before=joined_shelf_probes(asset)
    refine(asset);bpy.context.view_layer.update()
    lo_after,hi_after=scene_bounds()
    missing=[name for name in before if bpy.data.objects.get(name) is None]
    moved=[name for name,record in before.items() if max(abs(obvalue-old) for row,oldrow in zip(bpy.data.objects[name].matrix_world,record['matrix']) for obvalue,old in zip(row,oldrow))>.000001]
    if missing or moved:raise RuntimeError('Original node/marker changed: '+str((missing,moved)))
    # Every modification stays within the previous collision/pedestrian footprint.
    expansion=max(lo_before.x-lo_after.x,lo_before.y-lo_after.y,hi_after.x-hi_before.x,hi_after.y-hi_before.y)
    if expansion>.0002:raise RuntimeError('%s footprint expanded %.7fm'%(asset,expansion))
    probes=support_probes(before)
    for first,last in zip(joined_before,joined_shelf_probes(asset)):
        old_height=first['actual_top_y_m'];new_height=last['actual_top_y_m']
        probes.append({'node':'P_gondola','point_xz':[first['x'],first['z']],'ray_ceiling':first['ceiling'],
                       'original_top_y_m':old_height,'actual_centre_top_y_m':new_height,
                       'delta_m':new_height-old_height if old_height is not None and new_height is not None else None})
    bad=[probe for probe in probes if probe['delta_m'] is None or abs(probe['delta_m'])>.001]
    if bad:raise RuntimeError('Original support changed: '+str(bad))
    for image in bpy.data.images:
        if image.source=='FILE':image.pack()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(asset+'.blend')))
    old_backup=OUT/(asset+'.blend1')
    if old_backup.exists():old_backup.unlink()
    target=OUT/(asset+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_extras=True)
    identity=glb_proof(source,target)
    old_config=json.loads((ROOT/'art/models/game_assets.json').read_text()).get('assets',{}).get(asset,{})
    before_min,before_max=godot_bounds(lo_before,hi_before);after_min,after_max=godot_bounds(lo_after,hi_after)
    entry={'src':'raw/furniture_forms_20261014/'+asset+'.glb','preserve_parts':True,'preserve_origin':True,'level':False,'tex':old_config.get('tex',2048),
           'provider':'Blender measured curved joinery from approved imagegen previews 20261014',
           'source_archive':str(source.relative_to(ROOT)),'source_sha256':sha(source),'raw_sha256':sha(target),
           'retention':identity,'measurements':{'source_triangles':tris_before,'triangles':triangles(),'before_min_xyz':before_min,'before_max_xyz':before_max,
                           'after_min_xyz':after_min,'after_max_xyz':after_max,'footprint_expansion_m':round(expansion,8),
                           'original_nodes':len(before),'marker_names':[name for name,record in before.items() if record['type']!='MESH'],
                           'missing_nodes':missing,'changed_original_transforms':moved,'support_probes':probes,'forms':CHANGES}}
    REPORT['assets'][asset]=entry
    MANIFEST.write_text(json.dumps(REPORT,ensure_ascii=False,indent=2)+'\n')
    print('FURNITURE_FORMS',asset,'triangles',tris_before,'->',triangles(),'supports',len(probes),'footprint_expansion',expansion,flush=True)


try:
    unknown=ONLY-set(IDS)
    if unknown:raise ValueError('Unknown furniture IDs: '+str(sorted(unknown)))
    for asset in IDS:
        if not ONLY or asset in ONLY:run(asset)
except Exception:
    # Blender otherwise reports many script exceptions with exit status0.
    traceback.print_exc();sys.stdout.flush();sys.stderr.flush();os._exit(1)
